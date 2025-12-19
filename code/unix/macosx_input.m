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
** MACOSX_INPUT.M
**
** macOS input handling using Cocoa events
*/

#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>

#include "../client/client.h"

static qboolean mouse_active = qfalse;
static qboolean mouse_grab = qfalse;

/*
==================
KeycodeToQuake
==================
*/
static int KeycodeToQuake( unsigned short keycode )
{
	// macOS virtual key codes to Quake key codes
	switch ( keycode )
	{
		case kVK_ANSI_A:              return 'a';
		case kVK_ANSI_S:              return 's';
		case kVK_ANSI_D:              return 'd';
		case kVK_ANSI_F:              return 'f';
		case kVK_ANSI_H:              return 'h';
		case kVK_ANSI_G:              return 'g';
		case kVK_ANSI_Z:              return 'z';
		case kVK_ANSI_X:              return 'x';
		case kVK_ANSI_C:              return 'c';
		case kVK_ANSI_V:              return 'v';
		case kVK_ANSI_B:              return 'b';
		case kVK_ANSI_Q:              return 'q';
		case kVK_ANSI_W:              return 'w';
		case kVK_ANSI_E:              return 'e';
		case kVK_ANSI_R:              return 'r';
		case kVK_ANSI_Y:              return 'y';
		case kVK_ANSI_T:              return 't';
		case kVK_ANSI_1:              return '1';
		case kVK_ANSI_2:              return '2';
		case kVK_ANSI_3:              return '3';
		case kVK_ANSI_4:              return '4';
		case kVK_ANSI_6:              return '6';
		case kVK_ANSI_5:              return '5';
		case kVK_ANSI_Equal:          return '=';
		case kVK_ANSI_9:              return '9';
		case kVK_ANSI_7:              return '7';
		case kVK_ANSI_Minus:          return '-';
		case kVK_ANSI_8:              return '8';
		case kVK_ANSI_0:              return '0';
		case kVK_ANSI_RightBracket:   return ']';
		case kVK_ANSI_O:              return 'o';
		case kVK_ANSI_U:              return 'u';
		case kVK_ANSI_LeftBracket:    return '[';
		case kVK_ANSI_I:              return 'i';
		case kVK_ANSI_P:              return 'p';
		case kVK_ANSI_L:              return 'l';
		case kVK_ANSI_J:              return 'j';
		case kVK_ANSI_Quote:          return '\'';
		case kVK_ANSI_K:              return 'k';
		case kVK_ANSI_Semicolon:      return ';';
		case kVK_ANSI_Backslash:      return '\\';
		case kVK_ANSI_Comma:          return ',';
		case kVK_ANSI_Slash:          return '/';
		case kVK_ANSI_N:              return 'n';
		case kVK_ANSI_M:              return 'm';
		case kVK_ANSI_Period:         return '.';
		case kVK_ANSI_Grave:          return '`';
		
		case kVK_ANSI_KeypadDecimal:  return K_KP_DEL;
		case kVK_ANSI_KeypadMultiply: return K_KP_STAR;
		case kVK_ANSI_KeypadPlus:     return K_KP_PLUS;
		case kVK_ANSI_KeypadClear:    return K_KP_NUMLOCK;
		case kVK_ANSI_KeypadDivide:   return K_KP_SLASH;
		case kVK_ANSI_KeypadEnter:    return K_KP_ENTER;
		case kVK_ANSI_KeypadMinus:    return K_KP_MINUS;
		case kVK_ANSI_KeypadEquals:   return K_KP_EQUALS;
		case kVK_ANSI_Keypad0:        return K_KP_INS;
		case kVK_ANSI_Keypad1:        return K_KP_END;
		case kVK_ANSI_Keypad2:        return K_KP_DOWNARROW;
		case kVK_ANSI_Keypad3:        return K_KP_PGDN;
		case kVK_ANSI_Keypad4:        return K_KP_LEFTARROW;
		case kVK_ANSI_Keypad5:        return K_KP_5;
		case kVK_ANSI_Keypad6:        return K_KP_RIGHTARROW;
		case kVK_ANSI_Keypad7:        return K_KP_HOME;
		case kVK_ANSI_Keypad8:        return K_KP_UPARROW;
		case kVK_ANSI_Keypad9:        return K_KP_PGUP;
		
		case kVK_Return:              return K_ENTER;
		case kVK_Tab:                 return K_TAB;
		case kVK_Space:               return K_SPACE;
		case kVK_Delete:              return K_BACKSPACE;
		case kVK_Escape:              return K_ESCAPE;
		case kVK_Command:             return K_COMMAND;
		case kVK_Shift:               return K_SHIFT;
		case kVK_CapsLock:            return K_CAPSLOCK;
		case kVK_Option:              return K_ALT;
		case kVK_Control:             return K_CTRL;
		case kVK_RightShift:          return K_SHIFT;
		case kVK_RightOption:         return K_ALT;
		case kVK_RightControl:        return K_CTRL;
		
		case kVK_F1:                  return K_F1;
		case kVK_F2:                  return K_F2;
		case kVK_F3:                  return K_F3;
		case kVK_F4:                  return K_F4;
		case kVK_F5:                  return K_F5;
		case kVK_F6:                  return K_F6;
		case kVK_F7:                  return K_F7;
		case kVK_F8:                  return K_F8;
		case kVK_F9:                  return K_F9;
		case kVK_F10:                 return K_F10;
		case kVK_F11:                 return K_F11;
		case kVK_F12:                 return K_F12;
		case kVK_F13:                 return K_F13;
		case kVK_F14:                 return K_F14;
		case kVK_F15:                 return K_F15;
		
		case kVK_Help:                return K_INS;
		case kVK_Home:                return K_HOME;
		case kVK_PageUp:              return K_PGUP;
		case kVK_ForwardDelete:       return K_DEL;
		case kVK_End:                 return K_END;
		case kVK_PageDown:            return K_PGDN;
		
		case kVK_LeftArrow:           return K_LEFTARROW;
		case kVK_RightArrow:          return K_RIGHTARROW;
		case kVK_DownArrow:           return K_DOWNARROW;
		case kVK_UpArrow:             return K_UPARROW;
		
		default:
			Com_DPrintf( "Unknown keycode: %d\n", keycode );
			return 0;
	}
}

/*
==================
HandleEvents
==================
*/
void HandleEvents( void )
{
	@autoreleasepool {
		NSEvent *event;
		
		while ( (event = [NSApp nextEventMatchingMask:NSEventMaskAny
		                                     untilDate:[NSDate distantPast]
		                                        inMode:NSDefaultRunLoopMode
		                                       dequeue:YES]) )
		{
			switch ( [event type] )
			{
				case NSEventTypeKeyDown:
				{
					unsigned short keycode = [event keyCode];
					int key = KeycodeToQuake( keycode );
					if ( key )
					{
						Sys_QueEvent( Sys_Milliseconds(), SE_KEY, key, qtrue, 0, NULL );
					}
					break;
				}
				
				case NSEventTypeKeyUp:
				{
					unsigned short keycode = [event keyCode];
					int key = KeycodeToQuake( keycode );
					if ( key )
					{
						Sys_QueEvent( Sys_Milliseconds(), SE_KEY, key, qfalse, 0, NULL );
					}
					break;
				}
				
				case NSEventTypeMouseMoved:
				case NSEventTypeLeftMouseDragged:
				case NSEventTypeRightMouseDragged:
				case NSEventTypeOtherMouseDragged:
				{
					if ( mouse_active )
					{
						CGFloat dx = [event deltaX];
						CGFloat dy = [event deltaY];
						Sys_QueEvent( Sys_Milliseconds(), SE_MOUSE, dx, dy, 0, NULL );
					}
					break;
				}
				
				case NSEventTypeLeftMouseDown:
					Sys_QueEvent( Sys_Milliseconds(), SE_KEY, K_MOUSE1, qtrue, 0, NULL );
					break;
					
				case NSEventTypeLeftMouseUp:
					Sys_QueEvent( Sys_Milliseconds(), SE_KEY, K_MOUSE1, qfalse, 0, NULL );
					break;
					
				case NSEventTypeRightMouseDown:
					Sys_QueEvent( Sys_Milliseconds(), SE_KEY, K_MOUSE2, qtrue, 0, NULL );
					break;
					
				case NSEventTypeRightMouseUp:
					Sys_QueEvent( Sys_Milliseconds(), SE_KEY, K_MOUSE2, qfalse, 0, NULL );
					break;
					
				case NSEventTypeOtherMouseDown:
					Sys_QueEvent( Sys_Milliseconds(), SE_KEY, K_MOUSE3, qtrue, 0, NULL );
					break;
					
				case NSEventTypeOtherMouseUp:
					Sys_QueEvent( Sys_Milliseconds(), SE_KEY, K_MOUSE3, qfalse, 0, NULL );
					break;
					
				case NSEventTypeScrollWheel:
				{
					CGFloat deltaY = [event deltaY];
					if ( deltaY > 0 )
					{
						Sys_QueEvent( Sys_Milliseconds(), SE_KEY, K_MWHEELUP, qtrue, 0, NULL );
						Sys_QueEvent( Sys_Milliseconds(), SE_KEY, K_MWHEELUP, qfalse, 0, NULL );
					}
					else if ( deltaY < 0 )
					{
						Sys_QueEvent( Sys_Milliseconds(), SE_KEY, K_MWHEELDOWN, qtrue, 0, NULL );
						Sys_QueEvent( Sys_Milliseconds(), SE_KEY, K_MWHEELDOWN, qfalse, 0, NULL );
					}
					break;
				}
				
				default:
					[NSApp sendEvent:event];
					break;
			}
		}
	}
}

/*
==================
IN_Init
==================
*/
void IN_Init( void )
{
	Com_Printf( "------- Input Initialization -------\n" );
	mouse_active = qfalse;
	mouse_grab = qfalse;
	Com_Printf( "------------------------------------\n" );
}

/*
==================
IN_Shutdown
==================
*/
void IN_Shutdown( void )
{
	mouse_active = qfalse;
	mouse_grab = qfalse;
	
	// Show cursor
	[NSCursor unhide];
	CGAssociateMouseAndMouseCursorPosition( true );
}

/*
==================
IN_Frame
==================
*/
void IN_Frame( void )
{
	// Don't call HandleEvents() here - it's already called in Sys_SendKeyEvents()
	
	// Deactivate mouse if console is open
	if ( Key_GetCatcher() & KEYCATCH_CONSOLE )
	{
		if ( mouse_active )
		{
			[NSCursor unhide];
			CGAssociateMouseAndMouseCursorPosition( true );
			mouse_active = qfalse;
		}
		return;
	}
	
	// Activate mouse when in game
	if ( !mouse_active )
	{
		[NSCursor hide];
		CGAssociateMouseAndMouseCursorPosition( false );
		mouse_active = qtrue;
		Com_DPrintf( "Mouse activated\n" );
	}
}

/*
==================
IN_Activate
==================
*/
void IN_Activate( qboolean active )
{
	if ( active )
	{
		mouse_active = qtrue;
	}
	else
	{
		mouse_active = qfalse;
	}
}

