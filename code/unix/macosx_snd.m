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
** MACOSX_SND.M
**
** macOS sound using Core Audio
*/

#import <Cocoa/Cocoa.h>
#import <CoreAudio/CoreAudio.h>
#import <AudioToolbox/AudioToolbox.h>

#include "../client/client.h"
#include "../client/snd_local.h"

#define AUDIO_BUFFER_SIZE 4096

static AudioQueueRef audioQueue = NULL;
static AudioQueueBufferRef audioBuffers[3];
static qboolean snd_inited = qfalse;
static int sample_pos = 0;

/*
==================
AudioCallback
==================
*/
static void AudioCallback( void *inUserData, AudioQueueRef inAQ, AudioQueueBufferRef inBuffer )
{
	if ( !snd_inited || !dma.buffer )
		return;
	
	int samples = inBuffer->mAudioDataByteSize / (dma.samplebits / 8);
	
	// Copy audio data from DMA buffer
	if ( dma.samplebits == 16 )
	{
		short *out = (short *)inBuffer->mAudioData;
		
		for ( int i = 0; i < samples; i++ )
		{
			*out++ = dma.buffer[sample_pos];
			sample_pos = (sample_pos + 1) % dma.samples;
		}
	}
	else if ( dma.samplebits == 8 )
	{
		unsigned char *out = (unsigned char *)inBuffer->mAudioData;
		
		for ( int i = 0; i < samples; i++ )
		{
			*out++ = dma.buffer[sample_pos] >> 8;
			sample_pos = (sample_pos + 1) % dma.samples;
		}
	}
	
	// Re-queue the buffer
	AudioQueueEnqueueBuffer( inAQ, inBuffer, 0, NULL );
}

/*
==================
SNDDMA_Init
==================
*/
qboolean SNDDMA_Init( void )
{
	@autoreleasepool {
		OSStatus status;
		AudioStreamBasicDescription audioFormat;
		
		Com_Printf( "Initializing Core Audio\n" );
		
		// Setup audio format
		audioFormat.mSampleRate = 44100;
		audioFormat.mFormatID = kAudioFormatLinearPCM;
		audioFormat.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
		audioFormat.mBytesPerPacket = 4;
		audioFormat.mFramesPerPacket = 1;
		audioFormat.mBytesPerFrame = 4;
		audioFormat.mChannelsPerFrame = 2;
		audioFormat.mBitsPerChannel = 16;
		audioFormat.mReserved = 0;
		
		// Create audio queue
		status = AudioQueueNewOutput( &audioFormat, AudioCallback, NULL, 
		                              CFRunLoopGetCurrent(), kCFRunLoopCommonModes,
		                              0, &audioQueue );
		if ( status != noErr )
		{
			Com_Printf( "Failed to create audio queue: %d\n", (int)status );
			return qfalse;
		}
		
		// Allocate and prime audio buffers
		for ( int i = 0; i < 3; i++ )
		{
			status = AudioQueueAllocateBuffer( audioQueue, AUDIO_BUFFER_SIZE, &audioBuffers[i] );
			if ( status != noErr )
			{
				Com_Printf( "Failed to allocate audio buffer: %d\n", (int)status );
				SNDDMA_Shutdown();
				return qfalse;
			}
			
			audioBuffers[i]->mAudioDataByteSize = AUDIO_BUFFER_SIZE;
			memset( audioBuffers[i]->mAudioData, 0, AUDIO_BUFFER_SIZE );
			AudioQueueEnqueueBuffer( audioQueue, audioBuffers[i], 0, NULL );
		}
		
		// Setup DMA buffer
		dma.samplebits = 16;
		dma.speed = 44100;
		dma.channels = 2;
		dma.samples = 32768;
		dma.submission_chunk = 1;
		dma.buffer = calloc( 1, dma.samples * (dma.samplebits / 8) );
		
		if ( !dma.buffer )
		{
			Com_Printf( "Failed to allocate DMA buffer\n" );
			SNDDMA_Shutdown();
			return qfalse;
		}
		
		sample_pos = 0;
		
		// Start audio queue
		status = AudioQueueStart( audioQueue, NULL );
		if ( status != noErr )
		{
			Com_Printf( "Failed to start audio queue: %d\n", (int)status );
			SNDDMA_Shutdown();
			return qfalse;
		}
		
		snd_inited = qtrue;
		
		Com_Printf( "Core Audio initialized: %d Hz, %d bit, %d channels\n",
		           dma.speed, dma.samplebits, dma.channels );
		
		return qtrue;
	}
}

/*
==================
SNDDMA_GetDMAPos
==================
*/
int SNDDMA_GetDMAPos( void )
{
	if ( !snd_inited )
		return 0;
	
	return sample_pos;
}

/*
==================
SNDDMA_Shutdown
==================
*/
void SNDDMA_Shutdown( void )
{
	Com_Printf( "Shutting down Core Audio\n" );
	
	if ( audioQueue )
	{
		AudioQueueStop( audioQueue, true );
		AudioQueueDispose( audioQueue, true );
		audioQueue = NULL;
	}
	
	if ( dma.buffer )
	{
		free( dma.buffer );
		dma.buffer = NULL;
	}
	
	snd_inited = qfalse;
}

/*
==================
SNDDMA_Submit
==================
*/
void SNDDMA_Submit( void )
{
	// Audio callback handles submission
}

/*
==================
SNDDMA_BeginPainting
==================
*/
void SNDDMA_BeginPainting( void )
{
	// Not needed for Core Audio
}

/*
==================
SNDDMA_Activate
==================
*/
void SNDDMA_Activate( void )
{
	// Stub - audio queue runs continuously on macOS
	// No activation/deactivation needed
}

