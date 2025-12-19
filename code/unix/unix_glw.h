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

#ifndef __UNIX_GLW_H__
#define __UNIX_GLW_H__

typedef struct
{
	void *OpenGLLib; // instance of OpenGL library
	void *VulkanLib; // instance of Vulkan library
	void *config;

	qboolean isFullscreen;
	int desktop_width;
	int desktop_height;
} glwstate_t;

extern glwstate_t glw_state;

// macOS-specific: CAMetalLayer for Vulkan/Metal surface
#ifdef MACOS_X
extern void *metal_layer;
#endif

#ifdef USE_SDL
#include <SDL2/SDL.h>
extern SDL_Window *SDL_window;
extern void *qvkGetInstanceProcAddr;
#endif

#ifdef USE_OPENGL_API
void QGL_Shutdown( qboolean unloadDLL );
qboolean QGL_Init( const char *dllname );
void *GL_GetProcAddress( const char *symbol );
#endif

void QVK_Shutdown( qboolean unloadDLL );
qboolean QVK_Init( void );
// VK_GetInstanceProcAddr and VK_CreateSurface are declared in client.h

#if !defined(USE_SDL) && !defined(MACOS_X)
// X11 specific (Linux only, not macOS)
#include <X11/Xlib.h>
extern Display *dpy;
extern Window win;
#endif

#endif // __UNIX_GLW_H__
