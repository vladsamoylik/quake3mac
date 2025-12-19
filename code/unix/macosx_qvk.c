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
** MACOSX_QVK.C
**
** This file implements the operating system binding of VK to QVK function
** pointers.  When doing a port of Quake3 you must implement the following
** two functions:
**
** QVK_Init() - loads libraries, assigns function pointers, etc.
** QVK_Shutdown() - unloads libraries, NULLs function pointers
**
** This implementation uses MoltenVK for macOS Vulkan support
*/

#include <dlfcn.h>
#include "../qcommon/q_shared.h"
#include "../qcommon/qcommon.h"
#include "../renderercommon/tr_types.h"
#include "unix_glw.h"

// Use Metal surface extension for modern macOS
#define VK_USE_PLATFORM_METAL_EXT
#include "../renderercommon/vulkan/vulkan.h"

static PFN_vkGetInstanceProcAddr qvkGetInstanceProcAddr;
static PFN_vkCreateMetalSurfaceEXT qvkCreateMetalSurfaceEXT;

// External variables set by window creation code
extern void *metal_layer;  // CAMetalLayer from window

/*
** QVK_Shutdown
**
** Unloads the specified DLL then nulls out all the proc pointers.
*/
void QVK_Shutdown( qboolean unloadDLL )
{
	Com_Printf( "...shutting down QVK\n" );

	if ( glw_state.VulkanLib && unloadDLL )
	{
		Com_Printf( "...unloading Vulkan DLL\n" );
		dlclose( glw_state.VulkanLib );
		glw_state.VulkanLib = NULL;

		qvkGetInstanceProcAddr = NULL;
	}

	qvkCreateMetalSurfaceEXT = NULL;
}


void *VK_GetInstanceProcAddr( VkInstance instance, const char *name )
{
	return qvkGetInstanceProcAddr( instance, name );
}


qboolean VK_CreateSurface( VkInstance instance, VkSurfaceKHR *surface )
{
	VkMetalSurfaceCreateInfoEXT desc;

	if ( !metal_layer ) {
		Com_Printf( "VK_CreateSurface: metal_layer is NULL\n" );
		return qfalse;
	}

	qvkCreateMetalSurfaceEXT = (PFN_vkCreateMetalSurfaceEXT) VK_GetInstanceProcAddr( instance, "vkCreateMetalSurfaceEXT" );
	if ( !qvkCreateMetalSurfaceEXT )
	{
		Com_Printf( "VK_CreateSurface: vkCreateMetalSurfaceEXT not found\n" );
		return qfalse;
	}

	desc.sType = VK_STRUCTURE_TYPE_METAL_SURFACE_CREATE_INFO_EXT;
	desc.pNext = NULL;
	desc.flags = 0;
	desc.pLayer = (CAMetalLayer*) metal_layer;

	if ( qvkCreateMetalSurfaceEXT( instance, &desc, NULL, surface ) == VK_SUCCESS )
		return qtrue;
	else
		return qfalse;
}


static void *load_vulkan_library( const char *dllname )
{
	void *lib;

	lib = Sys_LoadLibrary( dllname );
	if ( lib )
	{
		qvkGetInstanceProcAddr = (PFN_vkGetInstanceProcAddr) Sys_LoadFunction( lib, "vkGetInstanceProcAddr" );
		if ( qvkGetInstanceProcAddr )
		{
			return lib;
		}
		Sys_UnloadLibrary( lib );
	}

	return NULL;
}


/*
** QVK_Init
**
** Responsible for loading MoltenVK library and binding vkGetInstanceProcAddr
*/
qboolean QVK_Init( void )
{
	Com_Printf( "...initializing QVK for macOS/MoltenVK\n" );

	if ( glw_state.VulkanLib == NULL )
	{
		// Try multiple possible locations for MoltenVK
		const char *dllnames[] = {
			// Vulkan SDK location
			"libvulkan.dylib",
			"libvulkan.1.dylib",
			// Homebrew location
			"/usr/local/lib/libMoltenVK.dylib",
			"/opt/homebrew/lib/libMoltenVK.dylib",
			// Framework locations
			"/Library/Frameworks/MoltenVK.framework/MoltenVK",
			"@rpath/libMoltenVK.dylib",
			// Bundled with app
			"libMoltenVK.dylib"
		};
		int i;

		for ( i = 0; i < ARRAY_LEN( dllnames ); i++ )
		{
			glw_state.VulkanLib = load_vulkan_library( dllnames[i] );

			Com_Printf( "...loading '%s' : %s\n", dllnames[i], glw_state.VulkanLib ? "success" : "failed" );
			if ( glw_state.VulkanLib )
			{
				break;
			}
		}

		if ( !glw_state.VulkanLib )
		{
			Com_Printf( "...failed to load MoltenVK library\n" );
			Com_Printf( "...try: brew install molten-vk\n" );
			return qfalse;
		}
	}

	Sys_LoadFunctionErrors(); // reset error counter

	return qtrue;
}

