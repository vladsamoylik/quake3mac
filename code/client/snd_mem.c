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

/*****************************************************************************
 * name:		snd_mem.c
 *
 * desc:		sound caching
 *
 * $Archive: /MissionPack/code/client/snd_mem.c $
 *
 *****************************************************************************/

#include "snd_local.h"
#include "snd_codec.h"

#define DEF_COMSOUNDMEGS "8"

/*
===============================================================================

memory management

===============================================================================
*/

static	sndBuffer	*buffer = NULL;
static	sndBuffer	*freelist = NULL;
static	int inUse = 0;
static	int totalInUse = 0;

short *sfxScratchBuffer = NULL;
sfx_t *sfxScratchPointer = NULL;
int	   sfxScratchIndex = 0;

// Sound memory management
int soundMemoryUsed = 0;		// Current memory used by loaded sounds (accessible from other files)
static int soundMemoryLimit = 128 * 1024 * 1024; // 128MB limit for sound data
static int soundBufferCount = 0;	// Number of allocated sound buffers
static int soundBufferLimit = 8192;	// Maximum number of sound buffers


// Sound LRU cache for frequently used sounds
#define SOUND_CACHE_SIZE 256
typedef struct sound_cache_s {
	char name[MAX_QPATH];
	sfx_t *sfx;
	int lastUsedTime;
	struct sound_cache_s *next;
} sound_cache_t;

static sound_cache_t sound_cache[SOUND_CACHE_SIZE];
static int sound_cache_frame = 0;
static int sound_cache_memory = 0;
static int sound_cache_max_memory = 32 * 1024 * 1024; // 32MB limit for cached sounds

// Asynchronous sound loading system
typedef struct load_sound_request_s {
	char filename[MAX_QPATH];
	sfx_t *sfx;
	qboolean loaded;
	qboolean failed;
	struct load_sound_request_s *next;
} load_sound_request_t;

static load_sound_request_t *sound_load_queue = NULL;
static load_sound_request_t *sound_load_queue_tail = NULL;


// Find sound in LRU cache
sfx_t *S_FindCachedSound(const char *name) {
	extern unsigned int S_HashSFXName(const char *name);
	uint32_t hash = S_HashSFXName(name) % SOUND_CACHE_SIZE;
	sound_cache_t *entry = &sound_cache[hash];

	if (entry->sfx && !Q_stricmp(entry->name, name)) {
		entry->lastUsedTime = sound_cache_frame++;
		return entry->sfx;
	}
	return NULL;
}

// Cleanup least recently used sounds from cache
static void S_CleanupSoundCache(void) {
	int oldestTime = sound_cache_frame;
	sound_cache_t *oldestEntry = NULL;

	// Find least recently used entry
	for (int i = 0; i < SOUND_CACHE_SIZE; i++) {
		if (sound_cache[i].sfx && sound_cache[i].lastUsedTime < oldestTime) {
			oldestTime = sound_cache[i].lastUsedTime;
			oldestEntry = &sound_cache[i];
		}
	}

	// Remove oldest entry if found
	if (oldestEntry) {
		sound_cache_memory -= oldestEntry->sfx->soundLength * sizeof(short);
		Com_Memset(oldestEntry, 0, sizeof(sound_cache_t));
	}
}

// Add sound to LRU cache
void S_AddToSoundCache(sfx_t *sfx) {
	if (!sfx || !sfx->soundData) return;

	extern unsigned int S_HashSFXName(const char *name);
	uint32_t hash = S_HashSFXName(sfx->soundName) % SOUND_CACHE_SIZE;
	sound_cache_t *entry = &sound_cache[hash];

	// If slot is occupied by different sound, remove old one
	if (entry->sfx && Q_stricmp(entry->name, sfx->soundName)) {
		sound_cache_memory -= entry->sfx->soundLength * sizeof(short);
	}

	// Add new sound to cache
	Q_strncpyz(entry->name, sfx->soundName, sizeof(entry->name));
	entry->sfx = sfx;
	entry->lastUsedTime = sound_cache_frame++;

	// Track memory usage
	sound_cache_memory += sfx->soundLength * sizeof(short);

	// If over memory limit, cleanup old entries
	if (sound_cache_memory > sound_cache_max_memory) {
		S_CleanupSoundCache();
	}
}

// Update sound cache timestamp (for existing sounds)
void S_UpdateSoundCache(sfx_t *sfx) {
	if (!sfx) return;

	extern unsigned int S_HashSFXName(const char *name);
	uint32_t hash = S_HashSFXName(sfx->soundName) % SOUND_CACHE_SIZE;
	sound_cache_t *entry = &sound_cache[hash];

	if (entry->sfx == sfx) {
		entry->lastUsedTime = sound_cache_frame++;
	}
}

// Initialize sound cache
static void S_InitSoundCache(void) {
	Com_Memset(sound_cache, 0, sizeof(sound_cache));
	sound_cache_frame = 0;
	sound_cache_memory = 0;
}

// Queue sound for asynchronous loading
void S_QueueSoundLoad(sfx_t *sfx, const char *filename) {
	if (!sfx || !filename || !*filename) return;

	load_sound_request_t *req = Z_Malloc(sizeof(load_sound_request_t));
	if (!req) return;

	Q_strncpyz(req->filename, filename, sizeof(req->filename));
	req->sfx = sfx;
	req->loaded = qfalse;
	req->failed = qfalse;
	req->next = NULL;

	// Add to queue
	if (!sound_load_queue) {
		sound_load_queue = req;
		sound_load_queue_tail = req;
	} else {
		sound_load_queue_tail->next = req;
		sound_load_queue_tail = req;
	}
}

// Get next sound load request
load_sound_request_t *S_GetNextSoundLoadRequest(void) {
	if (!sound_load_queue) return NULL;

	load_sound_request_t *req = sound_load_queue;
	sound_load_queue = sound_load_queue->next;

	if (!sound_load_queue) {
		sound_load_queue_tail = NULL;
	}

	return req;
}

// Process pending sound load requests (called from main loop)
void S_ProcessSoundLoadQueue(void) {
	static int last_process_time = 0;
	int current_time = Com_Milliseconds();

	// Process at most one sound per frame to avoid blocking
	if (current_time - last_process_time < 1) return;
	last_process_time = current_time;

	load_sound_request_t *req = S_GetNextSoundLoadRequest();
	if (!req) return;

	// Load the sound
	if (S_LoadSound(req->sfx)) {
		req->loaded = qtrue;
		Com_DPrintf("Loaded sound from queue: %s\n", req->filename);

		// Add to cache after successful load
		extern void S_AddToSoundCache(sfx_t *sfx);
		S_AddToSoundCache(req->sfx);
	} else {
		req->failed = qtrue;
		req->sfx->defaultSound = qtrue;
		Com_DPrintf("Failed to load sound from queue: %s\n", req->filename);
	}

	// Free the request
	Z_Free(req);
}

// Stop sound loading system
static void S_StopSoundLoadSystem(void) {
	// Free remaining requests
	load_sound_request_t *req = sound_load_queue;
	while (req) {
		load_sound_request_t *next = req->next;
		Z_Free(req);
		req = next;
	}
	sound_load_queue = NULL;
	sound_load_queue_tail = NULL;
}

// Forward declarations
static qboolean S_CompactSoundMemory(void);

// Sound memory management functions
static qboolean S_CheckSoundMemoryLimit(int additionalBytes) {
	if (soundMemoryUsed + additionalBytes > soundMemoryLimit) {
		// Try to free some memory
		if (!S_CompactSoundMemory()) {
			return qfalse; // Cannot allocate, limit reached
		}
		// Check again after cleanup
		if (soundMemoryUsed + additionalBytes > soundMemoryLimit) {
			return qfalse;
		}
	}
	return qtrue;
}

static qboolean S_CheckSoundBufferLimit(void) {
	return soundBufferCount < soundBufferLimit;
}

// Compact sound memory by freeing least recently used sounds
static qboolean S_CompactSoundMemory(void) {
	int freedMemory = 0;
	int targetFree = soundMemoryLimit / 4; // Try to free 25% of limit
	int freedBuffers = 0;

	Com_DPrintf("S_CompactSoundMemory: Starting cleanup (used: %d KB, limit: %d KB)\n",
		soundMemoryUsed / 1024, soundMemoryLimit / 1024);

	// Free sounds that haven't been used recently
	for (int i = 1; i < s_numSfx; i++) {
		sfx_t *sfx = &s_knownSfx[i];
		if (!sfx->inMemory || !sfx->soundData) continue;

		// Skip recently used sounds (used within last 30 seconds)
		int timeSinceUsed = s_soundtime - sfx->lastTimeUsed;
		if (timeSinceUsed < 30000) continue;

		// Free this sound
		int soundSize = sfx->soundLength * sizeof(short);
		sndBuffer *buffer = sfx->soundData;
		while (buffer) {
			sndBuffer *next = buffer->next;
			SND_free(buffer);
			buffer = next;
			freedBuffers++;
		}

		sfx->inMemory = qfalse;
		sfx->soundData = NULL;
		soundMemoryUsed -= soundSize;
		freedMemory += soundSize;

		Com_DPrintf("Freed sound: %s (%d KB)\n", sfx->soundName, soundSize / 1024);

		// Check if we freed enough
		if (freedMemory >= targetFree) break;
	}

	Com_DPrintf("S_CompactSoundMemory: Freed %d KB in %d buffers\n", freedMemory / 1024, freedBuffers);
	return freedMemory > 0;
}

// Get sound memory statistics
void S_GetSoundMemoryStats(int *used, int *limit, int *buffers) {
	*used = soundMemoryUsed;
	*limit = soundMemoryLimit;
	*buffers = soundBufferCount;
}

void SND_free( sndBuffer *v )
{
	*(sndBuffer **)v = freelist;
	freelist = (sndBuffer*)v;
	inUse += sizeof(sndBuffer);
	totalInUse -= sizeof(sndBuffer); // -EC-
	soundBufferCount--;
}


sndBuffer *SND_malloc( void ) {
	sndBuffer *v;

	// Check buffer limit before allocation
	if (!S_CheckSoundBufferLimit()) {
		Com_DPrintf("SND_malloc: Buffer limit reached (%d/%d), forcing cleanup\n",
			soundBufferCount, soundBufferLimit);
		S_CompactSoundMemory();

		if (!S_CheckSoundBufferLimit()) {
			Com_Printf("SND_malloc: Cannot allocate buffer, limit reached\n");
			return NULL;
		}
	}

	while ( freelist == NULL )
		S_FreeOldestSound();

	inUse -= sizeof(sndBuffer);
	totalInUse += sizeof(sndBuffer);
	soundBufferCount++;

	v = freelist;
	freelist = *(sndBuffer **)freelist;
	v->next = NULL;
	return v;
}


void SND_setup( void )
{
	sndBuffer *p, *q;
	cvar_t	*cv;
	int scs, sz;
	static int old_scs = -1;

	// Initialize sound cache
	S_InitSoundCache();

	cv = Cvar_Get( "com_soundMegs", DEF_COMSOUNDMEGS, CVAR_LATCH | CVAR_ARCHIVE );
	Cvar_CheckRange( cv, "1", "512", CV_INTEGER );
	Cvar_SetDescription( cv, "Amount of memory (RAM) assigned to the sound buffer (in MB)." );

	scs = ( cv->integer * /*1536*/ 12 * dma.speed ) / 22050;
	scs *= 128;

	sz = scs * sizeof( sndBuffer );

	// realloc buffer if com_soundMegs changed
	if ( old_scs != scs ) {
		if ( buffer != NULL ) {
			free( buffer );
			buffer = NULL;
		}
		old_scs = scs;
	}

	if ( buffer == NULL ) {
		buffer = malloc( sz );
	}

	// -EC-
	if ( buffer == NULL ) {
		Com_Error( ERR_FATAL, "Error allocating %i bytes for sound buffer", sz );
	} else {
		Com_Memset( buffer, 0, sz );
	}

	sz = SND_CHUNK_SIZE * sizeof(short) * 4;

	// allocate the stack based hunk allocator
	// -EC-
	if ( sfxScratchBuffer == NULL ) {
		sfxScratchBuffer = malloc( sz );	//Hunk_Alloc(SND_CHUNK_SIZE * sizeof(short) * 4);
	}

	// clear scratch buffer -EC-
	if ( sfxScratchBuffer == NULL ) {
		Com_Error( ERR_FATAL, "Error allocating %i bytes for sfxScratchBuffer",	sz );
	} else {
		Com_Memset( sfxScratchBuffer, 0, sz );
	}

	sfxScratchPointer = NULL;

	inUse = scs * sizeof( sndBuffer );
	totalInUse = 0; // -EC-

	p = buffer;
	q = p + scs;
	while (--q > p)
		*(sndBuffer **)q = q-1;

	*(sndBuffer **)q = NULL;
	freelist = p + scs - 1;

	Com_Printf( "Sound memory manager started\n" );
}


void SND_shutdown( void )
{
	if ( sfxScratchBuffer ) 
	{
		free( sfxScratchBuffer );
		sfxScratchBuffer = NULL;
	}
	if ( buffer )
	{
		free( buffer );
		buffer = NULL;
	}

	// Stop asynchronous sound loading system
	S_StopSoundLoadSystem();
}

/*
================
ResampleSfx

resample / decimate to the current source rate
================
*/
static int ResampleSfx( sfx_t *sfx, int channels, int inrate, int inwidth, int samples, byte *data, qboolean compressed ) {
	int		outcount;
	int		srcsample;
	float	stepscale;
	int		i, j;
	int		sample, samplefrac, fracstep;
	int			part;
	sndBuffer	*chunk;
	
	stepscale = (float)inrate / dma.speed;	// this is usually 0.5, 1, or 2

	outcount = samples / stepscale;

	srcsample = 0;
	samplefrac = 0;
	fracstep = stepscale * 256 * channels;
	chunk = sfx->soundData;

	for (i=0 ; i<outcount ; i++)
	{
		srcsample += samplefrac >> 8;
		samplefrac &= 255;
		samplefrac += fracstep;
		for (j=0 ; j<channels ; j++)
		{
			if( inwidth == 2 ) {
				sample = ( ((short *)data)[srcsample+j] );
			} else {
				sample = (unsigned int)( (unsigned char)(data[srcsample+j]) - 128) << 8;
			}
			part = (i*channels+j)&(SND_CHUNK_SIZE-1);
			if (part == 0) {
				sndBuffer	*newchunk;
				newchunk = SND_malloc();
				if (chunk == NULL) {
					sfx->soundData = newchunk;
				} else {
					chunk->next = newchunk;
				}
				chunk = newchunk;
			}

			chunk->sndChunk[part] = sample;
		}
	}

	return outcount;
}

/*
================
ResampleSfx

resample / decimate to the current source rate
================
*/
static int ResampleSfxRaw( short *sfx, int channels, int inrate, int inwidth, int samples, byte *data ) {
	int			outcount;
	int			srcsample;
	float		stepscale;
	int			i, j;
	int			sample, samplefrac, fracstep;
	
	stepscale = (float)inrate / dma.speed;	// this is usually 0.5, 1, or 2

	outcount = samples / stepscale;

	srcsample = 0;
	samplefrac = 0;
	fracstep = stepscale * 256 * channels;

	for (i=0 ; i<outcount ; i++)
	{
		srcsample += samplefrac >> 8;
		samplefrac &= 255;
		samplefrac += fracstep;
		for (j=0 ; j<channels ; j++)
		{
			if( inwidth == 2 ) {
				sample = LittleShort ( ((short *)data)[srcsample+j] );
			} else {
				sample = (int)( (unsigned char)(data[srcsample+j]) - 128) << 8;
			}
			sfx[i*channels+j] = sample;
		}
	}
	return outcount;
}

//=============================================================================

/*
==============
S_LoadSound

The filename may be different than sfx->name in the case
of a forced fallback of a player specific sound
==============
*/
qboolean S_LoadSound( sfx_t *sfx )
{
	byte	*data;
	short	*samples;
	snd_info_t	info;
//	int		size;

	// load it in
	data = S_CodecLoad(sfx->soundName, &info);
	if(!data)
		return qfalse;

	if ( info.width == 1 ) {
		Com_DPrintf(S_COLOR_YELLOW "WARNING: %s is a 8 bit audio file\n", sfx->soundName);
	}

	if ( info.rate != 22050 ) {
		Com_DPrintf(S_COLOR_YELLOW "WARNING: %s is not a 22kHz audio file\n", sfx->soundName);
	}

	// Estimate memory needed for this sound (rough estimate)
	int estimatedSize = info.samples * sizeof(short) * info.channels;
	if (!S_CheckSoundMemoryLimit(estimatedSize)) {
		Com_DPrintf("S_LoadSound: Not enough memory for sound %s (%d KB needed)\n",
			sfx->soundName, estimatedSize / 1024);
		Hunk_FreeTempMemory(data);
		return qfalse;
	}

	samples = Hunk_AllocateTempMemory(info.samples * sizeof(short) * 2);

	sfx->lastTimeUsed = s_soundtime + 1; // Com_Milliseconds()+1

	// each of these compression schemes works just fine
	// but the 16bit quality is much nicer and with a local
	// install assured we can rely upon the sound memory
	// manager to do the right thing for us and page
	// sound in as needed

	if( info.channels == 1 && sfx->soundCompressed == qtrue) {
		sfx->soundCompressionMethod = 1;
		sfx->soundData = NULL;
		sfx->soundLength = ResampleSfxRaw( samples, info.channels, info.rate, info.width, info.samples, data + info.dataofs );
		S_AdpcmEncodeSound(sfx, samples);
#if 0
	} else if (info.channels == 1 && info.samples>(SND_CHUNK_SIZE*16) && info.width >1) {
		sfx->soundCompressionMethod = 3;
		sfx->soundData = NULL;
		sfx->soundLength = ResampleSfxRaw( samples, info.channels, info.rate, info.width, info.samples, (data + info.dataofs) );
		encodeMuLaw( sfx, samples);
	} else if (info.channels == 1 && info.samples>(SND_CHUNK_SIZE*6400) && info.width >1) {
		sfx->soundCompressionMethod = 2;
		sfx->soundData = NULL;
		sfx->soundLength = ResampleSfxRaw( samples, info.channels, info.rate, info.width, info.samples, (data + info.dataofs) );
		encodeWavelet( sfx, samples);
#endif
	} else {
		sfx->soundCompressionMethod = 0;
		sfx->soundData = NULL;
		sfx->soundLength = ResampleSfx( sfx, info.channels, info.rate, info.width, info.samples, data + info.dataofs, qfalse );
	}

	sfx->soundChannels = info.channels;

	// Account for memory used by this sound
	soundMemoryUsed += sfx->soundLength * sizeof(short);

	Hunk_FreeTempMemory(samples);
	Hunk_FreeTempMemory(data);

	return qtrue;
}

void S_DisplayFreeMemory(void) {
	Com_Printf("%d bytes free sound buffer memory, %d total used\n", inUse, totalInUse);
	Com_Printf("Sound data: %d/%d KB used (%d buffers)\n",
		soundMemoryUsed / 1024, soundMemoryLimit / 1024, soundBufferCount);
}
