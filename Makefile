
# Quake3 Unix Makefile
#
# Nov '98 by Zoid <zoid@idsoftware.com>
#
# Loki Hacking by Bernd Kreimeier
#  and a little more by Ryan C. Gordon.
#  and a little more by Rafael Barrero
#  and a little more by the ioq3 cr3w
#
# GNU Make required
#
COMPILE_PLATFORM=$(shell uname | sed -e 's/_.*//' | tr '[:upper:]' '[:lower:]' | sed -e 's/\//_/g')
COMPILE_ARCH=$(shell uname -m | sed -e 's/i.86/x86/' | sed -e 's/^arm.*/arm/')

ifeq ($(shell uname -m),arm64)
  COMPILE_ARCH=aarch64
endif


BUILD_CLIENT     = 1
BUILD_SERVER     = 0

USE_SDL          = 0  # macOS uses native Cocoa, Linux uses SDL
USE_OPENAL       = 1
USE_CURL         = 1

USE_OGG_VORBIS    = 1
USE_FREETYPE      = 1

USE_RENDERER_DLOPEN = 1

# macOS-only fork - Vulkan only
RENDERER_DEFAULT = vulkan

CNAME            = quake3mac
DNAME            = quake3mac.ded

RENDERER_PREFIX  = $(CNAME)


ifeq ($(V),1)
echo_cmd=@:
Q=
else
echo_cmd=@echo
Q=@
endif

# Parallel build support
# Use JOBS environment variable or default to number of CPU cores
ifeq ($(JOBS),)
  # Try to get performance cores count first (for M1/M2), fallback to total cores
  JOBS := $(shell sysctl -n hw.perflevel0.logicalcpu 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 8)
endif
MAKEFLAGS += -j$(JOBS)

#############################################################################
#
# If you require a different configuration from the defaults below, create a
# new file named "Makefile.local" in the same directory as this file and define
# your parameters there. This allows you to change configuration without
# causing problems with keeping up to date with the repository.
#
#############################################################################
-include Makefile.local

ifeq ($(COMPILE_PLATFORM),darwin)
  # macOS uses native Cocoa/Core Audio - no SDL needed
  USE_SDL = 0
  USE_RENDERER_DLOPEN = 0
else
  # Linux and other platforms use SDL
  USE_SDL = 1
endif

# macOS and Linux only - no Windows support

ifndef PLATFORM
PLATFORM=$(COMPILE_PLATFORM)
endif
export PLATFORM


ifeq ($(COMPILE_ARCH),i86pc)
  COMPILE_ARCH=x86
endif

ifeq ($(COMPILE_ARCH),amd64)
  COMPILE_ARCH=x86_64
endif
ifeq ($(COMPILE_ARCH),x64)
  COMPILE_ARCH=x86_64
endif

ifndef ARCH
ARCH=$(COMPILE_ARCH)
endif
export ARCH

ifneq ($(PLATFORM),$(COMPILE_PLATFORM))
  CROSS_COMPILING=1
else
  CROSS_COMPILING=0

  ifneq ($(ARCH),$(COMPILE_ARCH))
    CROSS_COMPILING=1
  endif
endif
export CROSS_COMPILING

ifndef DESTDIR
DESTDIR=/usr/local/games/quake3
endif

ifndef MOUNT_DIR
MOUNT_DIR=code
endif

ifndef BUILD_DIR
BUILD_DIR=build
endif

ifndef GENERATE_DEPENDENCIES
GENERATE_DEPENDENCIES=1
endif

ifndef USE_CCACHE
USE_CCACHE=0
endif
export USE_CCACHE

ifndef USE_CURL
USE_CURL=1
endif

ifndef USE_CURL_DLOPEN
  USE_CURL_DLOPEN=1
endif

ifndef USE_OGG_VORBIS
  USE_OGG_VORBIS=1
endif


#############################################################################

BD=$(BUILD_DIR)/debug-$(PLATFORM)-$(ARCH)
BR=$(BUILD_DIR)/release-$(PLATFORM)-$(ARCH)
ADIR=$(MOUNT_DIR)/asm
CDIR=$(MOUNT_DIR)/client
# Old OpenAL directory removed - now using code/client/snd_openal.c
SDIR=$(MOUNT_DIR)/server
RCDIR=$(MOUNT_DIR)/renderercommon
RVDIR=$(MOUNT_DIR)/renderervk
SDLDIR=$(MOUNT_DIR)/sdl
CMDIR=$(MOUNT_DIR)/qcommon
UDIR=$(MOUNT_DIR)/unix
BLIBDIR=$(MOUNT_DIR)/botlib

bin_path=$(shell which $(1) 2> /dev/null)

STRIP ?= strip
PKG_CONFIG ?= pkg-config
INSTALL=install
MKDIR=mkdir -p

ifneq ($(call bin_path, $(PKG_CONFIG)),)
  ifneq ($(USE_SDL),0)
    SDL_INCLUDE ?= $(shell $(PKG_CONFIG) --silence-errors --cflags-only-I sdl2)
    SDL_LIBS ?= $(shell $(PKG_CONFIG) --silence-errors --libs sdl2)
  else
    X11_INCLUDE ?= $(shell $(PKG_CONFIG) --silence-errors --cflags-only-I x11)
    X11_LIBS ?= $(shell $(PKG_CONFIG) --silence-errors --libs x11)
  endif

  # Define library flags
  SDL_CFLAGS = $(shell $(PKG_CONFIG) --silence-errors --cflags sdl2 2>/dev/null)
  SDL_LIBS ?= $(shell $(PKG_CONFIG) --silence-errors --libs sdl2 2>/dev/null || echo -lSDL2)
  JPEG_CFLAGS = $(shell $(PKG_CONFIG) --silence-errors --cflags jpeg 2>/dev/null)
  JPEG_LIBS ?= $(shell $(PKG_CONFIG) --silence-errors --libs jpeg 2>/dev/null || echo -ljpeg)
  OGG_CFLAGS = $(shell $(PKG_CONFIG) --silence-errors --cflags ogg 2>/dev/null)
  OGG_LIBS ?= $(shell $(PKG_CONFIG) --silence-errors --libs ogg 2>/dev/null || echo -logg)
  VORBIS_CFLAGS = $(shell $(PKG_CONFIG) --silence-errors --cflags vorbisfile 2>/dev/null)
  VORBIS_LIBS ?= $(shell $(PKG_CONFIG) --silence-errors --libs vorbisfile 2>/dev/null || echo -lvorbisfile)
endif

# Supply reasonable defaults for system libraries
ifeq ($(X11_INCLUDE),)
  X11_INCLUDE = -I/usr/X11R6/include
endif
ifeq ($(X11_LIBS),)
  X11_LIBS = -lX11
endif
ifeq ($(SDL_LIBS),)
  SDL_LIBS = -lSDL2
endif
ifeq ($(JPEG_LIBS),)
  JPEG_LIBS = -ljpeg
endif
ifeq ($(OGG_LIBS),)
  OGG_LIBS = -logg
endif
ifeq ($(VORBIS_LIBS),)
  VORBIS_LIBS = -lvorbisfile
endif

# extract version info
VERSION=$(shell grep "define[ \t]\+Q3_VERSION[ \t]\+" $(CMDIR)/q_shared.h | \
  sed -e 's/.*".*\([^"]*\)".*/\1/' 2>/dev/null || echo "1.32e")

# common qvm definition
ifeq ($(ARCH),x86_64)
  HAVE_VM_COMPILED = true
else
ifeq ($(ARCH),x86)
  HAVE_VM_COMPILED = true
else
  HAVE_VM_COMPILED = false
endif
endif

ifeq ($(ARCH),arm)
  HAVE_VM_COMPILED = true
endif
ifeq ($(ARCH),aarch64)
  HAVE_VM_COMPILED = true
endif

BASE_CFLAGS =

# Always use system JPEG library
BASE_CFLAGS += -DUSE_SYSTEM_JPEG

ifneq ($(HAVE_VM_COMPILED),true)
  BASE_CFLAGS += -DNO_VM_COMPILED
endif

ifneq ($(USE_RENDERER_DLOPEN),0)
  BASE_CFLAGS += -DUSE_RENDERER_DLOPEN
  BASE_CFLAGS += -DRENDERER_PREFIX=\\\"$(RENDERER_PREFIX)\\\"
  BASE_CFLAGS += -DRENDERER_DEFAULT="$(RENDERER_DEFAULT)"
endif

ifdef DEFAULT_BASEDIR
  BASE_CFLAGS += -DDEFAULT_BASEDIR=\\\"$(DEFAULT_BASEDIR)\\\"
endif

ifeq ($(USE_CURL),1)
  BASE_CFLAGS += -DUSE_CURL
  ifeq ($(USE_CURL_DLOPEN),1)
    BASE_CFLAGS += -DUSE_CURL_DLOPEN
  endif
endif

BASE_CFLAGS += -DUSE_VULKAN_API


ifeq ($(GENERATE_DEPENDENCIES),1)
  BASE_CFLAGS += -MMD
endif


ARCHEXT=

CLIENT_EXTRA_FILES=


ifeq ($(COMPILE_PLATFORM),darwin)

#############################################################################
# SETUP AND BUILD -- MACOS
#############################################################################

  BASE_CFLAGS += -Wall -Wimplicit -Wstrict-prototypes -pipe

  BASE_CFLAGS += -Wno-unused-result
  BASE_CFLAGS += -fstack-protector-strong
  BASE_CFLAGS += -Wno-missing-braces -Wno-missing-field-initializers

  BASE_CFLAGS += -DMACOS_X

  # Base optimization flags
  OPTIMIZE = -O3 -march=native -ffast-math -fvisibility=hidden

  # Apple Silicon (M-series) specific optimizations
  ifeq ($(ARCH),aarch64)
    # Vectorization and SIMD (use NEON)
    OPTIMIZE += -ftree-vectorize -fvectorize
    # Additional ARM optimizations
    OPTIMIZE += -fomit-frame-pointer -mcpu=native
    # Link Time Optimization for whole-program optimization
    OPTIMIZE += -flto=thin
    LDFLAGS += -flto=thin
  else ifeq ($(ARCH),x86_64)
    # Link Time Optimization for Intel Macs
    OPTIMIZE += -flto
    LDFLAGS += -flto
  endif

  SHLIBEXT = dylib
  SHLIBCFLAGS = -fPIC -fvisibility=hidden
  SHLIBLDFLAGS = -dynamiclib $(LDFLAGS)

  ARCHEXT = .$(ARCH)

  LDFLAGS += -framework Cocoa -framework IOKit
  
  # Add Metal framework for MoltenVK/Vulkan support
  LDFLAGS += -framework Metal -framework QuartzCore
  BASE_CFLAGS += -DUSE_MOLTENVK
  
  # Add audio frameworks for native sound
  ifneq ($(USE_SDL),1)
    CLIENT_LDFLAGS += -framework CoreAudio -framework AudioToolbox
  endif

  ifeq ($(ARCH),x86_64)
    BASE_CFLAGS += -arch x86_64
    LDFLAGS += -arch x86_64
  endif
  ifeq ($(ARCH),aarch64)
    BASE_CFLAGS += -arch arm64
    LDFLAGS += -arch arm64
  endif

  # Always use system libraries via pkg-config
  BASE_CFLAGS += $(JPEG_CFLAGS)
  CLIENT_LDFLAGS += $(JPEG_LIBS)
  
  # SDL only for non-macOS platforms
  ifneq ($(COMPILE_PLATFORM),darwin)
    ifeq ($(USE_SDL),1)
      BASE_CFLAGS += $(SDL_CFLAGS)
      CLIENT_LDFLAGS += $(SDL_LIBS)
    endif
  endif

  ifeq ($(USE_OGG_VORBIS),1)
    BASE_CFLAGS += -DUSE_OGG_VORBIS $(OGG_CFLAGS) $(VORBIS_CFLAGS)
    CLIENT_LDFLAGS += $(OGG_LIBS) $(VORBIS_LIBS)
  endif

  # FreeType for smooth scalable fonts
  ifeq ($(USE_FREETYPE),1)
    BASE_CFLAGS += -DBUILD_FREETYPE
    ifeq ($(ARCH),aarch64)
      # Apple Silicon
      BASE_CFLAGS += -I/opt/homebrew/include/freetype2 -I/opt/homebrew/include
      CLIENT_LDFLAGS += -L/opt/homebrew/lib -lfreetype
    else
      # Intel Mac
      BASE_CFLAGS += -I/usr/local/include/freetype2 -I/usr/local/include
      CLIENT_LDFLAGS += -L/usr/local/lib -lfreetype
    endif
  endif

  # OpenAL for 3D positional audio (using openal-soft from Homebrew)
  ifeq ($(USE_OPENAL),1)
    BASE_CFLAGS += -DUSE_OPENAL
    ifeq ($(ARCH),aarch64)
      # Apple Silicon - openal-soft from Homebrew
      BASE_CFLAGS += -I/opt/homebrew/opt/openal-soft/include
      CLIENT_LDFLAGS += -L/opt/homebrew/opt/openal-soft/lib -lopenal
    else
      # Intel Mac
      BASE_CFLAGS += -I/usr/local/opt/openal-soft/include
      CLIENT_LDFLAGS += -L/usr/local/opt/openal-soft/lib -lopenal
    endif
  endif

  DEBUG_CFLAGS = $(BASE_CFLAGS) -DDEBUG -D_DEBUG -g -O0
  RELEASE_CFLAGS = $(BASE_CFLAGS) -DNDEBUG $(OPTIMIZE)

else

#############################################################################
# SETUP AND BUILD -- *NIX PLATFORMS
#############################################################################

  BASE_CFLAGS += -Wall -Wimplicit -Wstrict-prototypes -pipe

  BASE_CFLAGS += -Wno-unused-result

  BASE_CFLAGS += -DUSE_ICON

  BASE_CFLAGS += -I/usr/include -I/usr/local/include

  OPTIMIZE = -O2 -fvisibility=hidden

  ifeq ($(ARCH),x86_64)
    ARCHEXT = .x64
  else
  ifeq ($(ARCH),x86)
    OPTIMIZE += -march=i586 -mtune=i686
  endif
  endif

  ifeq ($(ARCH),arm)
    OPTIMIZE += -march=armv7-a
    ARCHEXT = .arm
  endif

  ifeq ($(ARCH),aarch64)
    ARCHEXT = .aarch64
  endif

  SHLIBEXT = so
  SHLIBCFLAGS = -fPIC -fvisibility=hidden
  SHLIBLDFLAGS = -shared $(LDFLAGS)

  LDFLAGS += -lm
  LDFLAGS += -Wl,--gc-sections -fvisibility=hidden

  ifeq ($(USE_SDL),1)
    BASE_CFLAGS += $(SDL_INCLUDE)
    CLIENT_LDFLAGS = $(SDL_LIBS)
  else
    BASE_CFLAGS += $(X11_INCLUDE)
    CLIENT_LDFLAGS = $(X11_LIBS)
  endif

  # Always use system JPEG library
  BASE_CFLAGS += $(JPEG_CFLAGS)
  CLIENT_LDFLAGS += $(JPEG_LIBS)

  ifeq ($(USE_CURL),1)
    ifeq ($(USE_CURL_DLOPEN),0)
      CLIENT_LDFLAGS += -lcurl
    endif
  endif

  ifeq ($(USE_OGG_VORBIS),1)
    BASE_CFLAGS += -DUSE_OGG_VORBIS $(OGG_CFLAGS) $(VORBIS_CFLAGS)
    CLIENT_LDFLAGS += $(OGG_LIBS) $(VORBIS_LIBS)
  endif

  ifeq ($(PLATFORM),linux)
    LDFLAGS += -ldl -Wl,--hash-style=both
    ifeq ($(ARCH),x86)
      # linux32 make ...
      BASE_CFLAGS += -m32
      LDFLAGS += -m32
    endif
  endif

  DEBUG_CFLAGS = $(BASE_CFLAGS) -DDEBUG -D_DEBUG -g -O0
  RELEASE_CFLAGS = $(BASE_CFLAGS) -DNDEBUG $(OPTIMIZE)

  DEBUG_LDFLAGS = -rdynamic

endif # *NIX platforms


TARGET_CLIENT = $(CNAME)$(ARCHEXT)$(BINEXT)

TARGET_RENDV = $(RENDERER_PREFIX)_vulkan_$(SHLIBNAME)

TARGET_SERVER = $(DNAME)$(ARCHEXT)$(BINEXT)


TARGETS =

ifneq ($(BUILD_SERVER),0)
  TARGETS += $(B)/$(TARGET_SERVER)
endif

ifneq ($(BUILD_CLIENT),0)
  TARGETS += $(B)/$(TARGET_CLIENT)
  ifneq ($(USE_RENDERER_DLOPEN),0)
    TARGETS += $(B)/$(TARGET_RENDV)
  endif
endif

ifeq ($(USE_CCACHE),1)
  CC := ccache $(CC)
endif

ifneq ($(USE_RENDERER_DLOPEN),0)
    RENDCFLAGS=$(SHLIBCFLAGS)
endif

define DO_CC
$(echo_cmd) "CC $<"
$(Q)$(CC) $(CFLAGS) -o $@ -c $<
endef

define DO_CC_QVM
$(echo_cmd) "CC_QVM $<"
$(Q)$(CC) $(CFLAGS) -fno-fast-math -o $@ -c $<
endef

define DO_REND_CC
$(echo_cmd) "REND_CC $<"
$(Q)$(CC) $(CFLAGS) $(RENDCFLAGS) -o $@ -c $<
endef


define DO_BOT_CC
$(echo_cmd) "BOT_CC $<"
$(Q)$(CC) $(CFLAGS) $(BOTCFLAGS) -DBOTLIB -o $@ -c $<
endef

define DO_AS
$(echo_cmd) "AS $<"
$(Q)$(CC) $(CFLAGS) -DELF -x assembler-with-cpp -o $@ -c $<
endef

define DO_DED_CC
$(echo_cmd) "DED_CC $<"
$(Q)$(CC) $(CFLAGS) -DDEDICATED -o $@ -c $<
endef

define DO_DED_CC_QVM
$(echo_cmd) "DED_CC_QVM $<"
$(Q)$(CC) $(CFLAGS) -fno-fast-math -DDEDICATED -o $@ -c $<
endef


ifndef SHLIBNAME
  SHLIBNAME=$(ARCH).$(SHLIBEXT)
endif

#############################################################################
# MAIN TARGETS
#############################################################################

default: release
all: debug release

# macOS app bundle
ifeq ($(COMPILE_PLATFORM),darwin)
app: release
	@echo "Creating Quake 3.app bundle..."
	@rm -rf "$(BR)/Quake 3.app"
	@mkdir -p "$(BR)/Quake 3.app/Contents/MacOS"
	@mkdir -p "$(BR)/Quake 3.app/Contents/Resources"
	@cp $(BR)/$(TARGET_CLIENT) "$(BR)/Quake 3.app/Contents/MacOS/quake3mac"
	@cp misc/macos/Info.plist "$(BR)/Quake 3.app/Contents/"
	@cp misc/macos/quake3.icns "$(BR)/Quake 3.app/Contents/Resources/"
	@echo "Created: $(BR)/Quake 3.app"
endif

debug:
	@$(MAKE) -j$(JOBS) targets B=$(BD) CFLAGS="$(CFLAGS) $(DEBUG_CFLAGS)" LDFLAGS="$(LDFLAGS) $(DEBUG_LDFLAGS)" V=$(V)

release:
	@$(MAKE) -j$(JOBS) targets B=$(BR) CFLAGS="$(CFLAGS) $(RELEASE_CFLAGS)" V=$(V)

define ADD_COPY_TARGET
TARGETS += $2
$2: $1
	$(echo_cmd) "CP $$<"
	@cp $1 $2
endef

# These functions allow us to generate rules for copying a list of files
# into the base directory of the build; this is useful for bundling libs,
# README files or whatever else
define GENERATE_COPY_TARGETS
$(foreach FILE,$1, \
  $(eval $(call ADD_COPY_TARGET, \
    $(FILE), \
    $(addprefix $(B)/,$(notdir $(FILE))))))
endef

ifneq ($(BUILD_CLIENT),0)
  $(call GENERATE_COPY_TARGETS,$(CLIENT_EXTRA_FILES))
endif

# Create the build directories and tools, print out
# an informational message, then start building
targets: makedirs tools
	@echo ""
	@echo "Building quake3 in $(B):"
	@echo ""
	@echo "  VERSION: $(VERSION)"
	@echo "  PLATFORM: $(PLATFORM)"
	@echo "  ARCH: $(ARCH)"
	@echo "  COMPILE_PLATFORM: $(COMPILE_PLATFORM)"
	@echo "  COMPILE_ARCH: $(COMPILE_ARCH)"
	@echo "  CC: $(CC)"
	@echo ""
	@echo "  CFLAGS:"
	@for i in $(CFLAGS); \
	do \
		echo "    $$i"; \
	done
	@echo ""
	@echo "  Output:"
	@for i in $(TARGETS); \
	do \
		echo "    $$i"; \
	done
	@echo ""
ifneq ($(TARGETS),)
	@$(MAKE) $(TARGETS) V=$(V)
endif

makedirs:
	@if [ ! -d $(BUILD_DIR) ];then $(MKDIR) $(BUILD_DIR);fi
	@if [ ! -d $(B) ];then $(MKDIR) $(B);fi
	@if [ ! -d $(B)/client ];then $(MKDIR) $(B)/client/qvm;fi
	@if [ ! -d $(B)/rend1 ];then $(MKDIR) $(B)/rend1;fi
	@if [ ! -d $(B)/rend2 ];then $(MKDIR) $(B)/rend2;fi
	@if [ ! -d $(B)/rendv ];then $(MKDIR) $(B)/rendv;fi
ifneq ($(BUILD_SERVER),0)
	@if [ ! -d $(B)/ded ];then $(MKDIR) $(B)/ded/qvm;fi
endif

#############################################################################
# CLIENT/SERVER
#############################################################################

Q3RENDVOBJ = \
  $(B)/rendv/tr_animation.o \
  $(B)/rendv/tr_backend.o \
  $(B)/rendv/tr_bsp.o \
  $(B)/rendv/tr_cmds.o \
  $(B)/rendv/tr_curve.o \
  $(B)/rendv/tr_font.o \
  $(B)/rendv/tr_image.o \
  $(B)/rendv/tr_image_png.o \
  $(B)/rendv/tr_image_jpg.o \
  $(B)/rendv/tr_image_bmp.o \
  $(B)/rendv/tr_image_tga.o \
  $(B)/rendv/tr_image_pcx.o \
  $(B)/rendv/tr_init.o \
  $(B)/rendv/tr_light.o \
  $(B)/rendv/tr_main.o \
  $(B)/rendv/tr_marks.o \
  $(B)/rendv/tr_mesh.o \
  $(B)/rendv/tr_model.o \
  $(B)/rendv/tr_model_iqm.o \
  $(B)/rendv/tr_noise.o \
  $(B)/rendv/tr_scene.o \
  $(B)/rendv/tr_shade.o \
  $(B)/rendv/tr_shade_calc.o \
  $(B)/rendv/tr_shader.o \
  $(B)/rendv/tr_shadows.o \
  $(B)/rendv/tr_sky.o \
  $(B)/rendv/tr_surface.o \
  $(B)/rendv/tr_world.o \
  $(B)/rendv/vk.o \
  $(B)/rendv/vk_flares.o \
  $(B)/rendv/vk_vbo.o \

ifneq ($(USE_RENDERER_DLOPEN), 0)
  Q3RENDVOBJ += \
    $(B)/rendv/q_shared.o \
    $(B)/rendv/puff.o \
    $(B)/rendv/q_math.o
endif

# JPEG: always use system library
# No embedded object files needed

# Ogg/Vorbis: always use system libraries
# No embedded object files needed

Q3OBJ = \
  $(B)/client/cl_cgame.o \
  $(B)/client/cl_cin.o \
  $(B)/client/cl_console.o \
  $(B)/client/cl_input.o \
  $(B)/client/cl_keys.o \
  $(B)/client/cl_main.o \
  $(B)/client/cl_net_chan.o \
  $(B)/client/cl_parse.o \
  $(B)/client/cl_scrn.o \
  $(B)/client/cl_ui.o \
  $(B)/client/cl_avi.o \
  $(B)/client/cl_jpeg.o \
  \
  $(B)/client/cm_load.o \
  $(B)/client/cm_patch.o \
  $(B)/client/cm_polylib.o \
  $(B)/client/cm_test.o \
  $(B)/client/cm_trace.o \
  \
  $(B)/client/cmd.o \
  $(B)/client/common.o \
  $(B)/client/cvar.o \
  $(B)/client/files.o \
  $(B)/client/history.o \
  $(B)/client/keys.o \
  $(B)/client/md4.o \
  $(B)/client/md5.o \
  $(B)/client/msg.o \
  $(B)/client/net_chan.o \
  $(B)/client/net_ip.o \
  $(B)/client/huffman.o \
  $(B)/client/huffman_static.o \
  \
  $(B)/client/snd_adpcm.o \
  $(B)/client/snd_dma.o \
  $(B)/client/snd_mem.o \
  $(B)/client/snd_mix.o \
  $(B)/client/snd_wavelet.o \
  \
  $(B)/client/snd_main.o \
  $(B)/client/snd_codec.o \
  $(B)/client/snd_codec_wav.o \
  \
  $(B)/client/sv_bot.o \
  $(B)/client/sv_ccmds.o \
  $(B)/client/sv_client.o \
  $(B)/client/sv_filter.o \
  $(B)/client/sv_game.o \
  $(B)/client/sv_init.o \
  $(B)/client/sv_main.o \
  $(B)/client/sv_net_chan.o \
  $(B)/client/sv_snapshot.o \
  $(B)/client/sv_world.o \
  \
  $(B)/client/q_math.o \
  $(B)/client/q_shared.o \
  \
  $(B)/client/unzip.o \
  $(B)/client/puff.o \
  \
  $(B)/client/be_aas_bspq3.o \
  $(B)/client/be_aas_cluster.o \
  $(B)/client/be_aas_debug.o \
  $(B)/client/be_aas_entity.o \
  $(B)/client/be_aas_file.o \
  $(B)/client/be_aas_main.o \
  $(B)/client/be_aas_move.o \
  $(B)/client/be_aas_optimize.o \
  $(B)/client/be_aas_reach.o \
  $(B)/client/be_aas_route.o \
  $(B)/client/be_aas_routealt.o \
  $(B)/client/be_aas_sample.o \
  $(B)/client/be_ai_char.o \
  $(B)/client/be_ai_chat.o \
  $(B)/client/be_ai_gen.o \
  $(B)/client/be_ai_goal.o \
  $(B)/client/be_ai_move.o \
  $(B)/client/be_ai_weap.o \
  $(B)/client/be_ai_weight.o \
  $(B)/client/be_ea.o \
  $(B)/client/be_interface.o \
  $(B)/client/l_crc.o \
  $(B)/client/l_libvar.o \
  $(B)/client/l_log.o \
  $(B)/client/l_memory.o \
  $(B)/client/l_precomp.o \
  $(B)/client/l_script.o \
  $(B)/client/l_struct.o

ifeq ($(USE_OGG_VORBIS),1)
  Q3OBJ += $(B)/client/snd_codec_ogg.o
endif

ifneq ($(USE_RENDERER_DLOPEN),1)
  Q3OBJ += $(Q3RENDVOBJ)
endif

ifeq ($(ARCH),x86)
  Q3OBJ += \
    $(B)/client/snd_mix_mmx.o \
    $(B)/client/snd_mix_sse.o
endif

ifeq ($(ARCH),x86_64)
  Q3OBJ += \
    $(B)/client/snd_mix_x86_64.o
endif

Q3OBJ += \
  $(B)/client/qvm/vm.o \
  $(B)/client/qvm/vm_interpreted.o

ifeq ($(HAVE_VM_COMPILED),true)
  ifeq ($(ARCH),x86)
    Q3OBJ += $(B)/client/qvm/vm_x86.o
  endif
  ifeq ($(ARCH),x86_64)
    Q3OBJ += $(B)/client/qvm/vm_x86.o
  endif
  ifeq ($(ARCH),arm)
    Q3OBJ += $(B)/client/qvm/vm_armv7l.o
  endif
  ifeq ($(ARCH),aarch64)
    Q3OBJ += $(B)/client/qvm/vm_aarch64.o
  endif
endif

ifeq ($(USE_CURL),1)
  Q3OBJ += $(B)/client/cl_curl.o
endif

  Q3OBJ += \
    $(B)/client/unix_main.o \
    $(B)/client/unix_shared.o

ifeq ($(COMPILE_PLATFORM),darwin)
  # macOS: native Cocoa/Core Audio implementations
  Q3OBJ += \
    $(B)/client/macosx_glimp_m.o \
    $(B)/client/macosx_input_m.o \
    $(B)/client/macosx_snd_m.o \
    $(B)/client/macosx_qvk.o
else ifeq ($(USE_SDL),1)
  # Linux and other platforms: SDL
  Q3OBJ += \
    $(B)/client/sdl_glimp.o \
    $(B)/client/sdl_gamma.o \
    $(B)/client/sdl_input.o \
    $(B)/client/sdl_snd.o
endif

# OpenAL support (works alongside SDL, provides 3D audio)
    ifeq ($(USE_OPENAL),1)
    Q3OBJ += $(B)/client/snd_openal.o
endif

# client binary

$(B)/$(TARGET_CLIENT): $(Q3OBJ)
	$(echo_cmd) "LD $@"
	$(Q)$(CC) -o $@ $(Q3OBJ) $(CLIENT_LDFLAGS) $(LDFLAGS)

# modular renderers

$(B)/$(TARGET_RENDV): $(Q3RENDVOBJ)
	$(echo_cmd) "LD $@"
	$(Q)$(CC) -o $@ $(Q3RENDVOBJ) $(SHLIBCFLAGS) $(SHLIBLDFLAGS)

#############################################################################
# DEDICATED SERVER
#############################################################################

Q3DOBJ = \
  $(B)/ded/sv_bot.o \
  $(B)/ded/sv_client.o \
  $(B)/ded/sv_ccmds.o \
  $(B)/ded/sv_filter.o \
  $(B)/ded/sv_game.o \
  $(B)/ded/sv_init.o \
  $(B)/ded/sv_main.o \
  $(B)/ded/sv_net_chan.o \
  $(B)/ded/sv_snapshot.o \
  $(B)/ded/sv_world.o \
  \
  $(B)/ded/cm_load.o \
  $(B)/ded/cm_patch.o \
  $(B)/ded/cm_polylib.o \
  $(B)/ded/cm_test.o \
  $(B)/ded/cm_trace.o \
  $(B)/ded/cmd.o \
  $(B)/ded/common.o \
  $(B)/ded/cvar.o \
  $(B)/ded/files.o \
  $(B)/ded/history.o \
  $(B)/ded/keys.o \
  $(B)/ded/md4.o \
  $(B)/ded/md5.o \
  $(B)/ded/msg.o \
  $(B)/ded/net_chan.o \
  $(B)/ded/net_ip.o \
  $(B)/ded/huffman.o \
  $(B)/ded/huffman_static.o \
  \
  $(B)/ded/q_math.o \
  $(B)/ded/q_shared.o \
  \
  $(B)/ded/unzip.o \
  \
  $(B)/ded/be_aas_bspq3.o \
  $(B)/ded/be_aas_cluster.o \
  $(B)/ded/be_aas_debug.o \
  $(B)/ded/be_aas_entity.o \
  $(B)/ded/be_aas_file.o \
  $(B)/ded/be_aas_main.o \
  $(B)/ded/be_aas_move.o \
  $(B)/ded/be_aas_optimize.o \
  $(B)/ded/be_aas_reach.o \
  $(B)/ded/be_aas_route.o \
  $(B)/ded/be_aas_routealt.o \
  $(B)/ded/be_aas_sample.o \
  $(B)/ded/be_ai_char.o \
  $(B)/ded/be_ai_chat.o \
  $(B)/ded/be_ai_gen.o \
  $(B)/ded/be_ai_goal.o \
  $(B)/ded/be_ai_move.o \
  $(B)/ded/be_ai_weap.o \
  $(B)/ded/be_ai_weight.o \
  $(B)/ded/be_ea.o \
  $(B)/ded/be_interface.o \
  $(B)/ded/l_crc.o \
  $(B)/ded/l_libvar.o \
  $(B)/ded/l_log.o \
  $(B)/ded/l_memory.o \
  $(B)/ded/l_precomp.o \
  $(B)/ded/l_script.o \
  $(B)/ded/l_struct.o

Q3DOBJ += \
  $(B)/ded/unix_main.o \
  $(B)/ded/unix_shared.o

  Q3DOBJ += \
  $(B)/ded/qvm/vm.o \
  $(B)/ded/qvm/vm_interpreted.o

ifeq ($(HAVE_VM_COMPILED),true)
  ifeq ($(ARCH),x86)
    Q3DOBJ += $(B)/ded/qvm/vm_x86.o
  endif
  ifeq ($(ARCH),x86_64)
    Q3DOBJ += $(B)/ded/qvm/vm_x86.o
  endif
  ifeq ($(ARCH),arm)
    Q3DOBJ += $(B)/ded/qvm/vm_armv7l.o
  endif
  ifeq ($(ARCH),aarch64)
    Q3DOBJ += $(B)/ded/qvm/vm_aarch64.o
  endif
endif

$(B)/$(TARGET_SERVER): $(Q3DOBJ)
	$(echo_cmd) $(Q3DOBJ)
	$(echo_cmd) "LD $@"
	$(Q)$(CC) -o $@ $(Q3DOBJ) $(LDFLAGS)

#############################################################################
## CLIENT/SERVER RULES
#############################################################################

$(B)/client/%.o: $(ADIR)/%.s
	$(DO_AS)

$(B)/client/%.o: $(CDIR)/%.c
	$(DO_CC)

$(B)/client/%.o: $(SDIR)/%.c
	$(DO_CC)

$(B)/client/%.o: $(CMDIR)/%.c
	$(DO_CC)

$(B)/client/qvm/%.o: $(CMDIR)/%.c
	$(DO_CC_QVM)

$(B)/client/%.o: $(BLIBDIR)/%.c
	$(DO_BOT_CC)

# JPEG compilation rules removed - using system library

# Ogg/Vorbis compilation rules removed - using system libraries

$(B)/client/%.o: $(SDLDIR)/%.c
	$(DO_CC)

$(B)/client/%.o: $(SDLDIR)/%.m
	$(echo_cmd) "CC(ObjC) $<"
	$(Q)$(CC) $(CFLAGS) -o $@ -c $<

$(B)/rendv/%.o: $(RVDIR)/%.c
	$(DO_REND_CC)

$(B)/rendv/%.o: $(RCDIR)/%.c
	$(DO_REND_CC)

$(B)/rendv/%.o: $(CMDIR)/%.c
	$(DO_REND_CC)

$(B)/client/%.o: $(UDIR)/%.c
	$(DO_CC)

# macOS-specific compilation rules
$(B)/client/macosx_%.o: $(UDIR)/macosx_%.c
	$(DO_CC)

# Objective-C compilation with special suffix
$(B)/client/macosx_%_m.o: $(UDIR)/macosx_%.m
	$(echo_cmd) "CC(ObjC) $<"
	$(Q)$(CC) $(CFLAGS) -o $@ -c $<


$(B)/ded/%.o: $(ADIR)/%.s
	$(DO_AS)

$(B)/ded/%.o: $(SDIR)/%.c
	$(DO_DED_CC)

$(B)/ded/%.o: $(CMDIR)/%.c
	$(DO_DED_CC)

$(B)/ded/qvm/%.o: $(CMDIR)/%.c
	$(DO_DED_CC_QVM)

$(B)/ded/%.o: $(BLIBDIR)/%.c
	$(DO_BOT_CC)

$(B)/ded/%.o: $(UDIR)/%.c
	$(DO_DED_CC)


#############################################################################
# MISC
#############################################################################

install: release
	@for i in $(TARGETS); do \
		if [ -f $(BR)$$i ]; then \
			$(INSTALL) -D -m 0755 "$(BR)/$$i" "$(DESTDIR)$$i"; \
			$(STRIP) "$(DESTDIR)$$i"; \
		fi \
	done

clean: clean-debug clean-release

clean2:
	@echo "CLEAN $(B)"
	@if [ -d $(B) ];then (find $(B) -name '*.d' -exec rm {} \;)fi
	@rm -f $(Q3OBJ) $(Q3DOBJ)
	@rm -f $(TARGETS)

clean-debug:
	@rm -rf $(BD)

clean-release:
	@echo $(BR)
	@rm -rf $(BR)

distclean: clean
	@rm -rf $(BUILD_DIR)

#############################################################################
# DEPENDENCIES
#############################################################################

D_FILES=$(shell find . -name '*.d')

ifneq ($(strip $(D_FILES)),)
 include $(D_FILES)
endif

.PHONY: all clean clean2 clean-debug clean-release copyfiles \
	debug default dist distclean makedirs release \
	targets tools toolsclean
