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

#ifdef USE_LOCAL_HEADERS
#	include "SDL.h"
#	include "SDL_vulkan.h"
#else
#	include <SDL.h>
#	include <SDL_vulkan.h>
#endif


#include "../client/client.h"
#include "../renderercommon/tr_public.h"
#include "sdl_glw.h"
#include "sdl_icon.h"


typedef enum {
	RSERR_OK,
	RSERR_INVALID_FULLSCREEN,
	RSERR_INVALID_MODE,
	RSERR_FATAL_ERROR,
	RSERR_UNKNOWN
} rserr_t;

glwstate_t glw_state;

SDL_Window *SDL_window = NULL;
static PFN_vkGetInstanceProcAddr qvkGetInstanceProcAddr;

cvar_t *r_stereoEnabled;
cvar_t *in_nograb;

#ifdef MACOS_X
static cvar_t *r_hidpi; // macOS HiDPI/Retina support
#endif

/*
===============
GLimp_Shutdown
===============
*/
void GLimp_Shutdown( qboolean unloadDLL )
{
	IN_Shutdown();

	SDL_DestroyWindow( SDL_window );
	SDL_window = NULL;

	if ( glw_state.isFullscreen )
		SDL_WarpMouseGlobal( glw_state.desktop_width / 2, glw_state.desktop_height / 2 );

	if ( unloadDLL )
		SDL_QuitSubSystem( SDL_INIT_VIDEO );
}


/*
===============
GLimp_Minimize

Minimize the game so that user is back at the desktop
===============
*/
void GLimp_Minimize( void )
{
	SDL_MinimizeWindow( SDL_window );
}


/*
===============
GLimp_LogComment
===============
*/
void GLimp_LogComment( const char *comment )
{
}


static int FindNearestDisplay( int *x, int *y, int w, int h )
{
	const int cx = *x + w / 2;
	const int cy = *y + h / 2;
	int i, index, numDisplays;
	SDL_Rect *list, *m;

	index = -1; // selected display index

	numDisplays = SDL_GetNumVideoDisplays();
	if ( numDisplays <= 0 )
		return -1;

	glw_state.monitorCount = numDisplays;

	list = Z_Malloc( numDisplays * sizeof( list[0] ) );

	for ( i = 0; i < numDisplays; i++ )
	{
		SDL_GetDisplayBounds( i, list + i );
		//Com_Printf( "[%i]: x=%i, y=%i, w=%i, h=%i\n", i, list[i].x, list[i].y, list[i].w, list[i].h );
	}

	// select display by window center intersection
	for ( i = 0; i < numDisplays; i++ )
	{
		m = list + i;
		if ( cx >= m->x && cx < (m->x + m->w) && cy >= m->y && cy < (m->y + m->h) )
		{
			index = i;
			break;
		}
	}

	// select display by nearest distance between window center and display center
	if ( index == -1 )
	{
		unsigned long nearest, dist;
		int dx, dy;
		nearest = ~0UL;
		for ( i = 0; i < numDisplays; i++ )
		{
			m = list + i;
			dx = (m->x + m->w/2) - cx;
			dy = (m->y + m->h/2) - cy;
			dist = ( dx * dx ) + ( dy * dy );
			if ( dist < nearest )
			{
				nearest = dist;
				index = i;
			}
		}
	}

	// adjust x and y coordinates if needed
	if ( index >= 0 )
	{
		m = list + index;
		if ( *x < m->x )
			*x = m->x;

		if ( *y < m->y )
			*y = m->y;
	}

	Z_Free( list );

	return index;
}


static SDL_HitTestResult SDL_HitTestFunc( SDL_Window *win, const SDL_Point *area, void *data )
{
	if ( Key_GetCatcher() & KEYCATCH_CONSOLE && keys[ K_ALT ].down )
		return SDL_HITTEST_DRAGGABLE;

	return SDL_HITTEST_NORMAL;
}


/*
===============
GLimp_SetMode
===============
*/
static int GLW_SetMode( int mode, const char *modeFS, qboolean fullscreen, qboolean vulkan )
{
	glconfig_t *config = glw_state.config;
	int colorBits, depthBits, stencilBits;
	int i;
	SDL_DisplayMode desktopMode;
	int display;
	int x;
	int y;
	Uint32 flags = SDL_WINDOW_SHOWN;

	flags |= SDL_WINDOW_VULKAN;
	Com_Printf( "Initializing Vulkan display\n");

	// If a window exists, note its display index
	if ( SDL_window != NULL )
	{
		display = SDL_GetWindowDisplayIndex( SDL_window );
		if ( display < 0 )
		{
			Com_DPrintf( "SDL_GetWindowDisplayIndex() failed: %s\n", SDL_GetError() );
		}
	}
	else
	{
		x = vid_xpos->integer;
		y = vid_ypos->integer;

		// find out to which display our window belongs to
		// according to previously stored \vid_xpos and \vid_ypos coordinates
		display = FindNearestDisplay( &x, &y, 640, 480 );

		//Com_Printf("Selected display: %i\n", display );
	}

	if ( display >= 0 && SDL_GetDesktopDisplayMode( display, &desktopMode ) == 0 )
	{
		glw_state.desktop_width = desktopMode.w;
		glw_state.desktop_height = desktopMode.h;
		
#ifdef MACOS_X
		// On macOS with HiDPI, desktop mode returns logical resolution
		// Get actual display mode to see physical resolution
		SDL_DisplayMode physicalMode;
		if ( SDL_GetCurrentDisplayMode( display, &physicalMode ) == 0 )
		{
			Com_Printf( "Display %d: logical %dx%d, physical %dx%d\n", 
			           display, desktopMode.w, desktopMode.h,
			           physicalMode.w, physicalMode.h );
		}
		
		// Debug: Show display bounds
		SDL_Rect bounds;
		if ( SDL_GetDisplayBounds( display, &bounds ) == 0 ) {
			Com_Printf( "Display %d bounds: %dx%d at position %d,%d\n",
			           display, bounds.w, bounds.h, bounds.x, bounds.y );
		}
#endif
	}
	else
	{
		glw_state.desktop_width = 640;
		glw_state.desktop_height = 480;
	}

	config->isFullscreen = fullscreen;
	glw_state.isFullscreen = fullscreen;

	Com_Printf( "...setting mode %d:", mode );

	if ( !CL_GetModeInfo( &config->vidWidth, &config->vidHeight, &config->windowAspect, mode, modeFS, glw_state.desktop_width, glw_state.desktop_height, fullscreen ) )
	{
		Com_Printf( " invalid mode\n" );
		return RSERR_INVALID_MODE;
	}

	Com_Printf( " %d %d\n", config->vidWidth, config->vidHeight );

	// Destroy existing state if it exists

	if ( SDL_window != NULL )
	{
		SDL_GetWindowPosition( SDL_window, &x, &y );
		Com_DPrintf( "Existing window at %dx%d before being destroyed\n", x, y );
		SDL_DestroyWindow( SDL_window );
		SDL_window = NULL;
	}

	gw_active = qfalse;
	gw_minimized = qtrue;

	if ( fullscreen )
	{
		// In fullscreen mode, position window at (0, 0) to avoid borders
		x = 0;
		y = 0;
#ifdef MACOS_X
		// Use FULLSCREEN_DESKTOP at creation time, not later via SetWindowFullscreen
		// This avoids the white border frame issue on macOS
		flags |= SDL_WINDOW_FULLSCREEN_DESKTOP;
		// Set window size to match display exactly before creation
		if ( display >= 0 )
		{
			SDL_Rect bounds;
			if ( SDL_GetDisplayBounds( display, &bounds ) == 0 )
			{
				config->vidWidth = bounds.w;
				config->vidHeight = bounds.h;
				x = bounds.x;
				y = bounds.y;
			}
		}
#else
		flags |= SDL_WINDOW_FULLSCREEN;
#endif
	}
	else if ( r_noborder->integer )
	{
		flags |= SDL_WINDOW_BORDERLESS;
	}

	// Enable HiDPI/Retina support on macOS
#ifdef MACOS_X
	if ( r_hidpi && r_hidpi->integer ) {
		flags |= SDL_WINDOW_ALLOW_HIGHDPI;
	}
#else
	flags |= SDL_WINDOW_ALLOW_HIGHDPI;
#endif

	colorBits = r_colorbits->value;

	if ( colorBits == 0 || colorBits > 32 )
		colorBits = 32;

	if ( cl_depthbits->integer == 0 )
	{
		// implicitly assume Z-buffer depth == desktop color depth
		if ( colorBits > 16 )
			depthBits = 24;
		else
			depthBits = 16;
	}
	else
		depthBits = cl_depthbits->integer;

	stencilBits = cl_stencilbits->integer;

	// do not allow stencil if Z-buffer depth likely won't contain it
	if ( depthBits < 24 )
		stencilBits = 0;

	for ( i = 0; i < 16; i++ )
	{
		int testColorBits, testDepthBits, testStencilBits;

		// 0 - default
		// 1 - minus colorBits
		// 2 - minus depthBits
		// 3 - minus stencil
		if ((i % 4) == 0 && i)
		{
			// one pass, reduce
			switch (i / 4)
			{
				case 2 :
					if (colorBits == 24)
						colorBits = 16;
					break;
				case 1 :
					if (depthBits == 24)
						depthBits = 16;
					else if (depthBits == 16)
						depthBits = 8;
				case 3 :
					if (stencilBits == 24)
						stencilBits = 16;
					else if (stencilBits == 16)
						stencilBits = 8;
			}
		}

		testColorBits = colorBits;
		testDepthBits = depthBits;
		testStencilBits = stencilBits;

		if ((i % 4) == 3)
		{ // reduce colorBits
			if (testColorBits == 24)
				testColorBits = 16;
		}

		if ((i % 4) == 2)
		{ // reduce depthBits
			if (testDepthBits == 24)
				testDepthBits = 16;
		}

		if ((i % 4) == 1)
		{ // reduce stencilBits
			if (testStencilBits == 8)
				testStencilBits = 0;
		}

		if ( ( SDL_window = SDL_CreateWindow( cl_title, x, y, config->vidWidth, config->vidHeight, flags ) ) == NULL )
		{
			Com_DPrintf( "SDL_CreateWindow failed: %s\n", SDL_GetError() );
			continue;
		}

		if ( fullscreen )
		{
			SDL_DisplayMode mode;

			switch ( testColorBits )
			{
				case 16: mode.format = SDL_PIXELFORMAT_RGB565;  break;
				case 24: mode.format = SDL_PIXELFORMAT_RGB24;   break;
				case 32: mode.format = SDL_PIXELFORMAT_RGBA8888; break;
				default: Com_DPrintf( "testColorBits is %d, can't fullscreen\n", testColorBits ); continue;
			}

			mode.w = config->vidWidth;
			mode.h = config->vidHeight;
			mode.refresh_rate = /* config->displayFrequency = */ Cvar_VariableIntegerValue( "r_displayRefresh" );
			mode.driverdata = NULL;

			if ( SDL_SetWindowDisplayMode( SDL_window, &mode ) < 0 )
			{
				Com_DPrintf( "SDL_SetWindowDisplayMode failed: %s\n", SDL_GetError( ) );
				continue;
			}

			if ( SDL_GetWindowDisplayMode( SDL_window, &mode ) >= 0 )
			{
				config->displayFrequency = mode.refresh_rate;
				config->vidWidth = mode.w;
				config->vidHeight = mode.h;
			}
		}

		config->colorBits = testColorBits;
		config->depthBits = testDepthBits;
		config->stencilBits = testStencilBits;


		Com_Printf( "Using %d color bits, %d depth, %d stencil display.\n",	config->colorBits, config->depthBits, config->stencilBits );

		break;
	}

	if ( SDL_window )
	{
#ifdef USE_ICON
		SDL_Surface *icon = SDL_CreateRGBSurfaceFrom(
			(void *)CLIENT_WINDOW_ICON.pixel_data,
			CLIENT_WINDOW_ICON.width,
			CLIENT_WINDOW_ICON.height,
			CLIENT_WINDOW_ICON.bytes_per_pixel * 8,
			CLIENT_WINDOW_ICON.bytes_per_pixel * CLIENT_WINDOW_ICON.width,
#ifdef Q3_LITTLE_ENDIAN
			0x000000FF, 0x0000FF00, 0x00FF0000, 0xFF000000
#else
			0xFF000000, 0x00FF0000, 0x0000FF00, 0x000000FF
#endif
		);
		if ( icon )
		{
			SDL_SetWindowIcon( SDL_window, icon );
			SDL_FreeSurface( icon );
		}
#endif
	}
	else
	{
		Com_Printf( "Couldn't get a visual\n" );
		return RSERR_INVALID_MODE;
	}

	if ( !fullscreen && r_noborder->integer )
		SDL_SetWindowHitTest( SDL_window, SDL_HitTestFunc, NULL );

#ifdef MACOS_X
	// Debug: Print window dimensions
	int windowW, windowH;
	SDL_GetWindowSize( SDL_window, &windowW, &windowH );
	Com_DPrintf( "SDL_GetWindowSize = %dx%d\n", windowW, windowH );
#endif

	SDL_Vulkan_GetDrawableSize( SDL_window, &config->vidWidth, &config->vidHeight );

#ifdef MACOS_X
	Com_DPrintf( "GetDrawableSize = %dx%d\n", config->vidWidth, config->vidHeight );
	
	if ( fullscreen ) {
		// Get window position to see which display it's on
		int wx, wy;
		SDL_GetWindowPosition( SDL_window, &wx, &wy );
		Com_DPrintf( "Window position = %d,%d\n", wx, wy );
		
		// Get display bounds
		SDL_Rect bounds;
		if ( SDL_GetDisplayBounds( display, &bounds ) == 0 ) {
			Com_DPrintf( "Display bounds = %dx%d at %d,%d\n", 
			           bounds.w, bounds.h, bounds.x, bounds.y );
		}
	}
#endif

	// save render dimensions as renderer may change it in advance
	glw_state.window_width = config->vidWidth;
	glw_state.window_height = config->vidHeight;

	SDL_WarpMouseInWindow( SDL_window, glw_state.window_width / 2, glw_state.window_height / 2 );

	return RSERR_OK;
}


/*
===============
GLimp_StartDriverAndSetMode
===============
*/
static rserr_t GLimp_StartDriverAndSetMode( int mode, const char *modeFS, qboolean fullscreen, qboolean vulkan )
{
	rserr_t err;

	if ( fullscreen && in_nograb->integer )
	{
		Com_Printf( "Fullscreen not allowed with \\in_nograb 1\n");
		Cvar_Set( "r_fullscreen", "0" );
		r_fullscreen->modified = qfalse;
		fullscreen = qfalse;
	}

	if ( !SDL_WasInit( SDL_INIT_VIDEO ) )
	{
		const char *driverName;

#ifdef MACOS_X
		// macOS-specific hints to prevent event loop blocking
		SDL_SetHint( SDL_HINT_MOUSE_FOCUS_CLICKTHROUGH, "1" );
		SDL_SetHint( SDL_HINT_VIDEO_MAC_FULLSCREEN_SPACES, "1" );
	
	// Use native macOS RAW input instead of warping for minimum input lag
	SDL_SetHint( SDL_HINT_MOUSE_RELATIVE_MODE_WARP, "0" );
	SDL_SetHint( SDL_HINT_MOUSE_RELATIVE_SCALING, "0" );  // Disable coordinate scaling
	SDL_SetHint( SDL_HINT_MOUSE_AUTO_CAPTURE, "0" );      // Manual mouse capture control
	SDL_SetHint( SDL_HINT_MOUSE_RELATIVE_SPEED_SCALE, "1.0" ); // No speed scaling
#endif

		if ( SDL_Init( SDL_INIT_VIDEO ) != 0 )
		{
			Com_Printf( "SDL_Init( SDL_INIT_VIDEO ) FAILED (%s)\n", SDL_GetError() );
			return RSERR_FATAL_ERROR;
		}

		driverName = SDL_GetCurrentVideoDriver();

		Com_Printf( "SDL using driver \"%s\"\n", driverName );
	}

	if ( vulkan )
	{
		// Load Vulkan library before creating window with SDL_WINDOW_VULKAN flag
		// On macOS, try MoltenVK paths first, then fall back to default
#ifdef MACOS_X
		const char *vulkan_paths[] = {
			"/opt/homebrew/lib/libMoltenVK.dylib",  // Homebrew Apple Silicon
			"/usr/local/lib/libMoltenVK.dylib",     // Homebrew Intel
			"/Library/Frameworks/MoltenVK.framework/MoltenVK"  // Framework
		};
		int i;
		int loaded = 0;

		// Try MoltenVK-specific paths first
		for ( i = 0; i < ARRAY_LEN( vulkan_paths ); i++ )
		{
			if ( SDL_Vulkan_LoadLibrary( vulkan_paths[i] ) == 0 )
			{
				Com_DPrintf( "Vulkan library loaded successfully from %s\n", vulkan_paths[i] );
				loaded = 1;
				break;
			}
			else
			{
				Com_DPrintf( "Failed to load Vulkan from %s: %s\n", vulkan_paths[i], SDL_GetError() );
			}
		}

		// If MoltenVK paths failed, try default SDL search
		if ( !loaded )
		{
			if ( SDL_Vulkan_LoadLibrary( NULL ) == 0 )
			{
				Com_DPrintf( "Vulkan library loaded successfully from default path\n" );
				loaded = 1;
			}
			else
			{
				Com_Printf( "Failed to load Vulkan from default path: %s\n", SDL_GetError() );
			}
		}

		if ( !loaded )
		{
			Com_Printf( "SDL_Vulkan_LoadLibrary() FAILED - could not find MoltenVK\n" );
			Com_Printf( "Try: brew install molten-vk\n" );
			return RSERR_FATAL_ERROR;
		}
#else
		if ( SDL_Vulkan_LoadLibrary( NULL ) != 0 )
		{
			Com_Printf( "SDL_Vulkan_LoadLibrary() FAILED (%s)\n", SDL_GetError() );
			return RSERR_FATAL_ERROR;
		}
		Com_DPrintf( "Vulkan library loaded successfully\n" );
#endif
	}

	err = GLW_SetMode( mode, modeFS, fullscreen, vulkan );

	switch ( err )
	{
		case RSERR_INVALID_FULLSCREEN:
			Com_Printf( "...WARNING: fullscreen unavailable in this mode\n" );
			return err;
		case RSERR_INVALID_MODE:
			Com_Printf( "...WARNING: could not set the given mode (%d)\n", mode );
			return err;
		default:
			break;
	}

	return RSERR_OK;
}


/*
===============
GLimp_Init

This routine is responsible for initializing the OS specific portions
of OpenGL
===============
*/
void GLimp_Init( glconfig_t *config )
{
	rserr_t err;

#ifndef _WIN32
	InitSig();
#endif

	Com_DPrintf( "GLimp_Init()\n" );

	glw_state.config = config; // feedback renderer configuration

	in_nograb = Cvar_Get( "in_nograb", "0", 0 );
	Cvar_SetDescription( in_nograb, "Do not capture mouse in game, may be useful during online streaming." );

#ifdef MACOS_X
	r_hidpi = Cvar_Get( "r_hidpi", "1", CVAR_ARCHIVE | CVAR_LATCH );
	Cvar_SetDescription( r_hidpi, "Enable HiDPI/Retina support for native pixel resolution. 1=native 5K/4K, 0=scaled 2K (default: 1)" );
#endif

	r_allowSoftwareGL = Cvar_Get( "r_allowSoftwareGL", "0", CVAR_LATCH );

	r_swapInterval = Cvar_Get( "r_swapInterval", "0", CVAR_ARCHIVE | CVAR_LATCH );
	r_stereoEnabled = Cvar_Get( "r_stereoEnabled", "0", CVAR_ARCHIVE | CVAR_LATCH );
	Cvar_SetDescription( r_stereoEnabled, "Enable stereo rendering for techniques like shutter glasses." );

	// Create the window and set up the context
	err = GLimp_StartDriverAndSetMode( r_mode->integer, r_modeFullscreen->string, r_fullscreen->integer, qfalse );
	if ( err != RSERR_OK )
	{
		if ( err == RSERR_FATAL_ERROR )
		{
			Com_Error( ERR_FATAL, "GLimp_Init() - could not load OpenGL subsystem" );
			return;
		}

		if ( r_mode->integer != 3 || ( r_fullscreen->integer && atoi( r_modeFullscreen->string ) != 3 ) )
		{
			Com_Printf( "Setting \\r_mode %d failed, falling back on \\r_mode %d\n", r_mode->integer, 3 );
			if ( GLimp_StartDriverAndSetMode( 3, "", r_fullscreen->integer, qfalse ) != RSERR_OK )
			{
				// Nothing worked, give up
				Com_Error( ERR_FATAL, "GLimp_Init() - could not load OpenGL subsystem" );
				return;
			}
		}
	}

	// These values force the UI to disable driver selection
	config->driverType = GLDRV_ICD;
	config->hardwareType = GLHW_GENERIC;

	// This depends on SDL_INIT_VIDEO, hence having it here
	IN_Init();

	HandleEvents();

	Key_ClearStates();
}


/*
===============
GLimp_EndFrame

Responsible for doing a swapbuffers
===============
*/
void GLimp_EndFrame( void )
{
	// Vulkan handles presentation in its own render loop
	// This function is kept for API compatibility
}


/*
===============
GL_GetProcAddress

Stub function for compatibility with renderervk that may call this
Returns NULL since we don't use OpenGL
===============
*/
void *GL_GetProcAddress( const char *symbol )
{
	return NULL;
}


/*
===============
VKimp_Init

This routine is responsible for initializing the OS specific portions
of Vulkan
===============
*/
void VKimp_Init( glconfig_t *config )
{
	rserr_t err;

#ifndef _WIN32
	InitSig();
#endif

	Com_DPrintf( "VKimp_Init()\n" );

	in_nograb = Cvar_Get( "in_nograb", "0", CVAR_ARCHIVE );
	Cvar_SetDescription( in_nograb, "Do not capture mouse in game, may be useful during online streaming." );

#ifdef MACOS_X
	r_hidpi = Cvar_Get( "r_hidpi", "1", CVAR_ARCHIVE | CVAR_LATCH );
	Cvar_SetDescription( r_hidpi, "Enable HiDPI/Retina support for native pixel resolution. 1=native 5K/4K, 0=scaled 2K (default: 1)" );
#endif

	r_swapInterval = Cvar_Get( "r_swapInterval", "0", CVAR_ARCHIVE | CVAR_LATCH );
	r_stereoEnabled = Cvar_Get( "r_stereoEnabled", "0", CVAR_ARCHIVE | CVAR_LATCH );
	Cvar_SetDescription( r_stereoEnabled, "Enable stereo rendering for techniques like shutter glasses." );

	// feedback to renderer configuration
	glw_state.config = config;

	// Create the window and set up the context
	err = GLimp_StartDriverAndSetMode( r_mode->integer, r_modeFullscreen->string, r_fullscreen->integer, qtrue /* Vulkan */ );
	if ( err != RSERR_OK )
	{
		if ( err == RSERR_FATAL_ERROR )
		{
			Com_Error( ERR_FATAL, "VKimp_Init() - could not load Vulkan subsystem" );
			return;
		}

		Com_Printf( "Setting r_mode %d failed, falling back on r_mode %d\n", r_mode->integer, 3 );

		err = GLimp_StartDriverAndSetMode( 3, "", r_fullscreen->integer, qtrue /* Vulkan */ );
		if( err != RSERR_OK )
		{
			// Nothing worked, give up
			Com_Error( ERR_FATAL, "VKimp_Init() - could not load Vulkan subsystem" );
			return;
		}
	}

	qvkGetInstanceProcAddr = SDL_Vulkan_GetVkGetInstanceProcAddr();

	if ( qvkGetInstanceProcAddr == NULL )
	{
		SDL_QuitSubSystem( SDL_INIT_VIDEO );
		Com_Error( ERR_FATAL, "VKimp_Init: qvkGetInstanceProcAddr is NULL" );
	}

	// These values force the UI to disable driver selection
	config->driverType = GLDRV_ICD;
	config->hardwareType = GLHW_GENERIC;

	// This depends on SDL_INIT_VIDEO, hence having it here
	IN_Init();

	HandleEvents();

	Key_ClearStates();
}


/*
===============
VK_GetInstanceProcAddr
===============
*/
void *VK_GetInstanceProcAddr( VkInstance instance, const char *name )
{
	return qvkGetInstanceProcAddr( instance, name );
}


/*
===============
VK_CreateSurface
===============
*/
qboolean VK_CreateSurface( VkInstance instance, VkSurfaceKHR *surface )
{
	if ( SDL_Vulkan_CreateSurface( SDL_window, instance, surface ) == SDL_TRUE )
		return qtrue;
	else
		return qfalse;
}


/*
===============
VKimp_Shutdown
===============
*/
void VKimp_Shutdown( qboolean unloadDLL )
{
	IN_Shutdown();

	SDL_DestroyWindow( SDL_window );
	SDL_window = NULL;

	if ( glw_state.isFullscreen )
		SDL_WarpMouseGlobal( glw_state.desktop_width / 2, glw_state.desktop_height / 2 );

	if ( unloadDLL )
		SDL_QuitSubSystem( SDL_INIT_VIDEO );
}


/*
================
GLW_HideFullscreenWindow
================
*/
void GLW_HideFullscreenWindow( void ) {
	if ( SDL_window && glw_state.isFullscreen ) {
		SDL_HideWindow( SDL_window );
	}
}


/*
===============
Sys_GetClipboardData
===============
*/
char *Sys_GetClipboardData( void )
{
#ifdef DEDICATED
	return NULL;
#else
	char *data = NULL;
	char *cliptext;

	if ( ( cliptext = SDL_GetClipboardText() ) != NULL ) {
		if ( cliptext[0] != '\0' ) {
			size_t bufsize = strlen( cliptext ) + 1;

			data = Z_Malloc( bufsize );
			Q_strncpyz( data, cliptext, bufsize );

			// find first listed char and set to '\0'
			strtok( data, "\n\r\b" );
		}
		SDL_free( cliptext );
	}
	return data;
#endif
}


/*
===============
Sys_SetClipboardBitmap
===============
*/
void Sys_SetClipboardBitmap( const byte *bitmap, int length )
{
#ifdef _WIN32
	HGLOBAL hMem;
	byte *ptr;

	if ( !OpenClipboard( NULL ) )
		return;

	EmptyClipboard();
	hMem = GlobalAlloc( GMEM_MOVEABLE | GMEM_DDESHARE, length );
	if ( hMem != NULL ) {
		ptr = ( byte* )GlobalLock( hMem );
		if ( ptr != NULL ) {
			memcpy( ptr, bitmap, length ); 
		}
		GlobalUnlock( hMem );
		SetClipboardData( CF_DIB, hMem );
	}
	CloseClipboard();
#endif
}
