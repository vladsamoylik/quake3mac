/*
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.

This file is part of Quake III Arena source code.

Quake III Arena source code is free software; you can redistribute it
and/or modify it under the terms of the GNU General Public License as
published by the Free Software Foundation; either version 2 of the License,
or (at your option) any later version.

Quake III Arena source code is distributed in the hope that it will be
useful, but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with Quake III Arena source code; if not, write to the Free Software
Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
===========================================================================
*/

/*
** MACOSX_GLIMP.M
**
** This file contains macOS specific stuff having to do with the
** graphics subsystem using native Cocoa APIs.
*/

#import <Cocoa/Cocoa.h>
#import <QuartzCore/CAMetalLayer.h>
#import <Metal/Metal.h>
#include <unistd.h>

#include "../client/client.h"
#include "unix_glw.h"

// Forward declarations for input
void IN_Init( void );
void HandleEvents( void );

typedef enum
{
	RSERR_OK,
	RSERR_INVALID_FULLSCREEN,
	RSERR_INVALID_MODE,
	RSERR_FATAL_ERROR,
	RSERR_UNKNOWN
} rserr_t;

glwstate_t glw_state;
void *metal_layer = NULL;

static NSWindow *window = nil;
static NSView *view = nil;
static qboolean window_created = qfalse;

// Cvars
cvar_t *r_fullscreen;
cvar_t *r_mode;
cvar_t *vid_xpos;
cvar_t *vid_ypos;

/*
==================
Sys_GetVideoDriver
==================
*/
const char *Sys_GetVideoDriver( void )
{
	return "macOS Cocoa";
}

/*
==================
GLimp_GetModeInfo
==================
*/
typedef struct vidmode_s
{
	const char *description;
	int width, height;
	float pixelAspect;
} vidmode_t;

static const vidmode_t r_vidModes[] =
{
	{ "Mode  0: 320x240",    320,  240, 1 },
	{ "Mode  1: 400x300",    400,  300, 1 },
	{ "Mode  2: 512x384",    512,  384, 1 },
	{ "Mode  3: 640x480",    640,  480, 1 },
	{ "Mode  4: 800x600",    800,  600, 1 },
	{ "Mode  5: 960x720",    960,  720, 1 },
	{ "Mode  6: 1024x768",   1024, 768, 1 },
	{ "Mode  7: 1152x864",   1152, 864, 1 },
	{ "Mode  8: 1280x1024",  1280, 1024, 1 },
	{ "Mode  9: 1600x1200",  1600, 1200, 1 },
	{ "Mode 10: 2048x1536",  2048, 1536, 1 },
	{ "Mode 11: 856x480",    856,  480, 1 }
};
static const int s_numVidModes = sizeof( r_vidModes ) / sizeof( r_vidModes[0] );

qboolean GLimp_GetModeInfo( int *width, int *height, float *windowAspect, int mode, const char *modeFS, int dw, int dh )
{
	const vidmode_t *vm;

	if ( mode < -2 )
		return qfalse;

	if ( mode >= s_numVidModes )
		return qfalse;

	if ( mode == -2 )
	{
		// Use native screen resolution (in pixels, not points)
		// This ensures proper resolution on Retina/HiDPI displays
		*width = dw;
		*height = dh;
		*windowAspect = (float)*width / (float)*height;
		Com_Printf( "Auto-detecting native resolution: %dx%d (from screen backing store)\n", *width, *height );
		return qtrue;
	}

	if ( mode == -1 )
	{
		// Deprecated: use -2 for auto-detect instead
		Com_Printf( "WARNING: r_mode -1 is deprecated, using -2 (auto-detect) instead\n" );
		*width = dw;
		*height = dh;
		*windowAspect = (float)*width / (float)*height;
		return qtrue;
	}

	vm = &r_vidModes[mode];

	*width = vm->width;
	*height = vm->height;
	*windowAspect = (float)vm->width / (float)vm->height;

	return qtrue;
}

/*
==================
CreateNSWindow
==================
*/
static qboolean CreateNSWindow( int width, int height, qboolean fullscreen )
{
	@autoreleasepool {
		// Ensure NSApp is initialized
		if ( ![NSApp isRunning] )
		{
			[NSApp finishLaunching];
		}
		
		NSRect contentRect = NSMakeRect(0, 0, width, height);
		NSUInteger styleMask;
		
		if ( fullscreen )
		{
			styleMask = NSWindowStyleMaskBorderless;
		}
		else
		{
			styleMask = NSWindowStyleMaskTitled | 
			           NSWindowStyleMaskClosable | 
			           NSWindowStyleMaskMiniaturizable |
			           NSWindowStyleMaskResizable;
		}

		window = [[NSWindow alloc] initWithContentRect:contentRect
		                                     styleMask:styleMask
		                                       backing:NSBackingStoreBuffered
		                                         defer:NO];
		if ( !window )
		{
			Com_Printf( "Failed to create NSWindow\n" );
			return qfalse;
		}

	[window setTitle:@"Quake3e"];
	[window setAcceptsMouseMovedEvents:YES];
	
	// Register for backing properties changes (e.g., moving to different display with different scale)
	[[NSNotificationCenter defaultCenter] addObserverForName:NSWindowDidChangeBackingPropertiesNotification
	                                                   object:window
	                                                    queue:nil
	                                               usingBlock:^(NSNotification *note) {
		CAMetalLayer *layer = (CAMetalLayer*)view.layer;
		if (layer) {
			CGFloat newScale = window.screen.backingScaleFactor;
			if (layer.contentsScale != newScale) {
				layer.contentsScale = newScale;
				// Update drawable size when scale changes
				NSRect bounds = [view bounds];
				NSRect backing = [view convertRectToBacking:bounds];
				layer.drawableSize = CGSizeMake(backing.size.width, backing.size.height);
				Com_DPrintf("Display scale changed to %.1f, drawable size: %.0fx%.0f\n", 
				           newScale, layer.drawableSize.width, layer.drawableSize.height);
			}
		}
	}];
		
		// Create content view first
		view = [[NSView alloc] initWithFrame:contentRect];
		[window setContentView:view];
		
		if ( fullscreen )
		{
			// IMPORTANT: Use window.screen (actual screen where window is), NOT mainScreen
			// This fixes the issue when MacBook lid is open with external monitor
			NSScreen *actualScreen = window.screen;
			NSRect screenFrame = [actualScreen frame];
			
			Com_Printf( "Setting fullscreen on screen: %.0fx%.0f\n", 
			           screenFrame.size.width, screenFrame.size.height );
			
			// Set window frame to cover entire screen
			[window setFrame:screenFrame display:YES];
			
			[window setLevel:NSMainMenuWindowLevel + 1];
			[window setHidesOnDeactivate:YES];
			
			// CRITICAL: Update view frame after window resize
			[view setFrame:NSMakeRect(0, 0, screenFrame.size.width, screenFrame.size.height)];
			
			Com_Printf( "View frame after fullscreen: %.0fx%.0f\n", 
			           view.bounds.size.width, view.bounds.size.height );
		}
		else
		{
			// Center window
			[window center];
		}
		
		// Show window first
		[window makeKeyAndOrderFront:nil];
		[window orderFrontRegardless];
		[window makeKeyWindow];
		
		// Activate application (important when launched from terminal)
		[NSApp activateIgnoringOtherApps:YES];
		
		// Process pending events to ensure window is displayed and activated
		for ( int i = 0; i < 10; i++ )
		{
			NSEvent *event;
			while ( (event = [NSApp nextEventMatchingMask:NSEventMaskAny
			                                     untilDate:[NSDate distantPast]
			                                        inMode:NSDefaultRunLoopMode
			                                       dequeue:YES]) )
			{
				[NSApp sendEvent:event];
			}
			
			if ( [window isKeyWindow] )
				break;
				
			usleep(10000); // 10ms
		}
		
		// Set presentation options AFTER window is visible and active
		if ( fullscreen )
		{
			[NSApp setPresentationOptions:NSApplicationPresentationHideMenuBar | 
			                              NSApplicationPresentationHideDock];
		}
		
		Com_Printf( "Window visibility: %s, key: %s\n",
		           [window isVisible] ? "YES" : "NO",
		           [window isKeyWindow] ? "YES" : "NO" );
		
	// Create Metal layer for Vulkan
	CAMetalLayer *metalLayer = [CAMetalLayer layer];
	metalLayer.frame = view.bounds;
	metalLayer.device = MTLCreateSystemDefaultDevice();
	
	// CRITICAL for Retina: Set backing scale factor for native resolution
	CGFloat scale = [window.screen backingScaleFactor];
	metalLayer.contentsScale = scale;
	
	// Get actual window size in pixels (backing store) for Retina displays
	NSRect frame = [view bounds];
	NSRect backingFrame = [view convertRectToBacking:frame];
	
	Com_Printf( "DEBUG: view.bounds = %.0fx%.0f points\n", 
	           frame.size.width, frame.size.height );
	Com_Printf( "DEBUG: backingFrame = %.0fx%.0f pixels\n", 
	           backingFrame.size.width, backingFrame.size.height );
	Com_Printf( "DEBUG: window.frame = %.0fx%.0f points\n",
	           window.frame.size.width, window.frame.size.height );
	Com_Printf( "DEBUG: window.screen.frame = %.0fx%.0f points\n",
	           window.screen.frame.size.width, window.screen.frame.size.height );
	
	// CRITICAL: Set drawable size explicitly in pixels for MoltenVK
	// This ensures the Metal surface is created at native resolution
	metalLayer.drawableSize = CGSizeMake(backingFrame.size.width, backingFrame.size.height);
	
	// EDR toggle (Apple XDR): enable extended dynamic range content and use float drawable.
	cvar_t *r_edr = Cvar_Get( "r_edr", "0", CVAR_ARCHIVE_ND | CVAR_LATCH );
	cvar_t *r_fbo = Cvar_Get( "r_fbo", "1", CVAR_ARCHIVE_ND | CVAR_LATCH );
	const BOOL edrRequested = (r_edr && r_edr->integer != 0);
	const BOOL fboEnabled = (r_fbo && r_fbo->integer != 0);
	BOOL edrEnabled = NO;
	
	if ( edrRequested && !fboEnabled ) {
		Com_Printf( "WARNING: EDR requires r_fbo 1, forcing EDR off\n" );
	} else if ( edrRequested ) {
		// Check API availability at runtime (macOS 10.14.6+ for extended linear colorspace)
		if ( @available(macOS 10.14.6, *) ) {
			if ( [metalLayer respondsToSelector:@selector(setWantsExtendedDynamicRangeContent:)] ) {
				edrEnabled = YES;
				metalLayer.wantsExtendedDynamicRangeContent = YES;
				Com_Printf( "EDR: enabled (macOS 10.14.6+)\n" );
			} else {
				Com_Printf( "WARNING: EDR not available on this macOS version\n" );
			}
		} else {
			Com_Printf( "WARNING: EDR requires macOS 10.14.6+\n" );
		}
	}
	
	// Set colorspace appropriately
	if ( [metalLayer respondsToSelector:@selector(setColorspace:)] ) {
		CGColorSpaceRef cs = NULL;
		
		if ( edrEnabled ) {
			if ( @available(macOS 10.14.6, *) ) {
				// Extended Linear Display P3 for EDR
				cs = CGColorSpaceCreateWithName( kCGColorSpaceExtendedLinearDisplayP3 );
				if ( !cs ) {
					Com_Printf( "WARNING: kCGColorSpaceExtendedLinearDisplayP3 unavailable, trying fallback\n" );
					// Fallback to extended sRGB if available
					cs = CGColorSpaceCreateWithName( kCGColorSpaceExtendedLinearSRGB );
				}
			}
		} else {
			// Standard sRGB for SDR
			cs = CGColorSpaceCreateWithName( kCGColorSpaceSRGB );
		}
		
		if ( cs ) {
			metalLayer.colorspace = cs;
			CGColorSpaceRelease( cs );
			Com_Printf( "EDR: colorspace set (%s)\n", edrEnabled ? "extended linear" : "sRGB" );
		}
	}
	
	// Choose pixel format. For EDR we need a float format to preserve values > 1.0.
	// Note: MoltenVK will expose this as VK_FORMAT_R16G16B16A16_SFLOAT if supported.
	if ( edrEnabled ) {
		metalLayer.pixelFormat = MTLPixelFormatRGBA16Float;
		Com_Printf( "EDR: Metal layer pixelFormat = RGBA16Float\n" );
	} else {
		metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
	}
	
	// Optional: log EDR headroom if available (macOS 10.15+)
	if ( @available(macOS 10.15, *) ) {
		if ( [window.screen respondsToSelector:@selector(maximumExtendedDynamicRangeColorComponentValue)] ) {
			CGFloat maxEDR = window.screen.maximumExtendedDynamicRangeColorComponentValue;
			Com_Printf( "EDR: screen maxEDR headroom = %.2f (1.0 = SDR white)\n", maxEDR );
		}
	}
	
	[view setLayer:metalLayer];
	[view setWantsLayer:YES];
	
	metal_layer = (__bridge void*)metalLayer;
	
	glw_state.desktop_width = backingFrame.size.width;
	glw_state.desktop_height = backingFrame.size.height;
	
	Com_Printf( "Metal Layer: %.0fx%.0f points, drawable %.0fx%.0f pixels (scale: %.1f)\n",
	           frame.size.width, frame.size.height,
	           metalLayer.drawableSize.width, metalLayer.drawableSize.height, scale );
		
		window_created = qtrue;
		
		Com_Printf( "Created macOS window: %dx%d\n", width, height );
		
		return qtrue;
	}
}

/*
==================
DestroyNSWindow
==================
*/
static void DestroyNSWindow( void )
{
	@autoreleasepool {
		// Restore normal presentation options when destroying fullscreen window
		if ( glw_state.isFullscreen )
		{
			[NSApp setPresentationOptions:NSApplicationPresentationDefault];
		}
		
		// Reset EDR settings on Metal layer before releasing to speed up cleanup
		if ( metal_layer && [((__bridge CAMetalLayer*)metal_layer) respondsToSelector:@selector(setWantsExtendedDynamicRangeContent:)] ) {
			((__bridge CAMetalLayer*)metal_layer).wantsExtendedDynamicRangeContent = NO;
		}
		
		if ( view )
		{
			// Explicitly remove layer before releasing view
			if ( view.layer ) {
				view.layer = nil;
			}
			[view release];
			view = nil;
		}
		
		if ( window )
		{
			[window close];
			[window release];
			window = nil;
		}
		
		metal_layer = NULL;
		window_created = qfalse;
	}
}

/*
==================
GLimp_SetMode
==================
*/
static rserr_t GLimp_SetMode( int mode, qboolean fullscreen )
{
	int width, height;
	float windowAspect;
	glconfig_t *config = (glconfig_t*)glw_state.config;
	
	NSScreen *screen = [NSScreen mainScreen];
	NSRect screenFrame = [screen frame];
	
	// Get real resolution in pixels (not points) for Retina displays
	NSRect backingFrame = [screen convertRectToBacking:screenFrame];
	CGFloat scaleFactor = [screen backingScaleFactor];
	
	Com_Printf( "Initializing macOS display\n" );
	Com_Printf( "mainScreen: %.0fx%.0f points, %.0fx%.0f pixels (scale: %.1f)\n",
	           screenFrame.size.width, screenFrame.size.height,
	           backingFrame.size.width, backingFrame.size.height, scaleFactor );
	
	// Log all available screens for debugging multi-monitor setups
	NSArray *screens = [NSScreen screens];
	Com_Printf( "Available screens: %lu\n", (unsigned long)[screens count] );
	for (NSUInteger i = 0; i < [screens count]; i++) {
		NSScreen *s = [screens objectAtIndex:i];
		NSRect sf = [s frame];
		NSRect bf = [s convertRectToBacking:sf];
		Com_Printf( "  Screen %lu: %.0fx%.0f points, %.0fx%.0f pixels (scale: %.1f)\n",
		           (unsigned long)i, sf.size.width, sf.size.height,
		           bf.size.width, bf.size.height, [s backingScaleFactor] );
	}
	
	if ( !GLimp_GetModeInfo( &width, &height, &windowAspect, mode, "", 
	                         backingFrame.size.width, backingFrame.size.height ) )
	{
		Com_Printf( "Invalid mode %d\n", mode );
		return RSERR_INVALID_MODE;
	}
	
	Com_Printf( "...setting mode %d: %dx%d %s\n", mode, width, height, 
	           fullscreen ? "FS" : "W" );
	
	// Destroy existing window if any
	if ( window_created )
	{
		DestroyNSWindow();
	}
	
	// Create new window
	if ( !CreateNSWindow( width, height, fullscreen ) )
	{
		return RSERR_FATAL_ERROR;
	}
	
	// After window creation, get actual screen where window is located
	// This is important for multi-monitor setups
	NSScreen *actualScreen = window.screen;
	NSRect actualScreenFrame = [actualScreen frame];
	NSRect actualBackingFrame = [actualScreen convertRectToBacking:actualScreenFrame];
	
	Com_Printf( "Window created on screen: %.0fx%.0f points, %.0fx%.0f pixels\n",
	           actualScreenFrame.size.width, actualScreenFrame.size.height,
	           actualBackingFrame.size.width, actualBackingFrame.size.height );
	
	// Update config
	config->vidWidth = width;
	config->vidHeight = height;
	config->windowAspect = windowAspect;
	config->isFullscreen = fullscreen;
	config->colorBits = 32;
	config->depthBits = 24;
	config->stencilBits = 8;
	
	glw_state.isFullscreen = fullscreen;
	// Store real pixel dimensions for Retina displays from the ACTUAL screen
	glw_state.desktop_width = actualBackingFrame.size.width;
	glw_state.desktop_height = actualBackingFrame.size.height;
	
	return RSERR_OK;
}

#ifdef USE_OPENGL_API
/*
==================
GLimp_Init
==================
*/
void GLimp_Init( glconfig_t *config )
{
	Com_Printf( "Initializing OpenGL subsystem (macOS native)\n" );
	Com_Printf( "Note: Native OpenGL on macOS is deprecated.\n" );
	Com_Printf( "      Consider using Vulkan/MoltenVK instead.\n" );
	
	glw_state.config = config;
	
	r_fullscreen = Cvar_Get( "r_fullscreen", "1", CVAR_ARCHIVE | CVAR_LATCH );
	r_mode = Cvar_Get( "r_mode", "-2", CVAR_ARCHIVE | CVAR_LATCH );  // -2 = auto-detect native resolution
	vid_xpos = Cvar_Get( "vid_xpos", "3", CVAR_ARCHIVE );
	vid_ypos = Cvar_Get( "vid_ypos", "22", CVAR_ARCHIVE );
	
	if ( GLimp_SetMode( r_mode->integer, r_fullscreen->integer ) != RSERR_OK )
	{
		Com_Error( ERR_FATAL, "GLimp_Init() - could not load OpenGL subsystem\n" );
	}
	
	config->driverType = GLDRV_ICD;
	config->hardwareType = GLHW_GENERIC;
}

/*
==================
GLimp_Shutdown
==================
*/
void GLimp_Shutdown( qboolean unloadDLL )
{
	Com_Printf( "Shutting down OpenGL subsystem\n" );
	
	DestroyNSWindow();
	
#ifdef USE_OPENGL_API
	if ( unloadDLL )
		QGL_Shutdown( qtrue );
#endif
}

/*
==================
GLimp_EndFrame
==================
*/
void GLimp_EndFrame( void )
{
	// OpenGL swap would go here
}
#endif // USE_OPENGL_API

/*
==================
VKimp_Init
==================
*/
void VKimp_Init( glconfig_t *config )
{
	rserr_t err;
	
	Com_Printf( "Initializing Vulkan subsystem (macOS/MoltenVK)\n" );
	
	// Initialize NSApplication if not already done
	if ( NSApp == nil )
	{
		[NSApplication sharedApplication];
	}
	
	// Set activation policy to make this a regular app (not background)
	[NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
	
	glw_state.config = config;
	
	r_fullscreen = Cvar_Get( "r_fullscreen", "1", CVAR_ARCHIVE | CVAR_LATCH );
	r_mode = Cvar_Get( "r_mode", "-2", CVAR_ARCHIVE | CVAR_LATCH );  // -2 = auto-detect native resolution
	vid_xpos = Cvar_Get( "vid_xpos", "3", CVAR_ARCHIVE );
	vid_ypos = Cvar_Get( "vid_ypos", "22", CVAR_ARCHIVE );
	
	// Load Vulkan library
	if ( !QVK_Init() )
	{
		Com_Error( ERR_FATAL, "VKimp_Init() - could not load Vulkan library\n" );
		return;
	}
	
	// Create window
	err = GLimp_SetMode( r_mode->integer, r_fullscreen->integer );
	if ( err != RSERR_OK )
	{
		if ( err == RSERR_INVALID_MODE )
		{
			Com_Printf( "Invalid mode, trying mode 3\n" );
			err = GLimp_SetMode( 3, r_fullscreen->integer );
		}
		
		if ( err != RSERR_OK )
		{
			Com_Error( ERR_FATAL, "VKimp_Init() - could not initialize window\n" );
			return;
		}
	}
	
	config->driverType = GLDRV_ICD;
	config->hardwareType = GLHW_GENERIC;
	
	// Initialize input (native Cocoa input)
	IN_Init();
	
	// Process initial events
	HandleEvents();
}

/*
==================
VKimp_Shutdown
==================
*/
void VKimp_Shutdown( qboolean unloadDLL )
{
	Com_Printf( "Shutting down Vulkan subsystem\n" );
	
	DestroyNSWindow();
	
	if ( unloadDLL )
		QVK_Shutdown( qtrue );
}

/*
==================
GLimp_InitGamma
==================
*/
void GLimp_InitGamma( glconfig_t *config )
{
	// Gamma initialization not needed for native macOS
}

/*
==================
GLimp_SetGamma
==================
*/
void GLimp_SetGamma( unsigned char red[256], unsigned char green[256], unsigned char blue[256] )
{
	// Gamma adjustment not implemented for native macOS yet
}

/*
==================
Sys_GetClipboardData
==================
*/
char *Sys_GetClipboardData( void )
{
	@autoreleasepool {
		NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
		NSString *type = [pasteboard availableTypeFromArray:@[NSPasteboardTypeString]];
		
		if ( type != nil )
		{
			NSString *contents = [pasteboard stringForType:NSPasteboardTypeString];
			if ( contents != nil )
			{
				const char *utf8 = [contents UTF8String];
				size_t len = strlen( utf8 ) + 1;
				char *data = Z_Malloc( len );
				Q_strncpyz( data, utf8, len );
				return data;
			}
		}
		
		return NULL;
	}
}

/*
==================
Sys_SetClipboardBitmap
==================
*/
void Sys_SetClipboardBitmap( const byte *bitmap, int length )
{
	// Not implemented
}

