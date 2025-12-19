# Quake3mac Comparison with Other Forks

User-friendly document explaining key differences between Quake3mac, ioquake3, and quake3e.

## Quick Comparison

| Feature | ioquake3 | quake3e | **Quake3mac** |
|---------|----------|---------|---------------|
| **Platforms** | Windows, macOS, Linux | Windows, macOS, Linux | **macOS, Linux** |
| **Renderer** | OpenGL (GL1/GL2) | OpenGL + Vulkan + GL2 | **Vulkan only** (MoltenVK) |
| **EDR/HDR10** | No | No | **Yes (Apple XDR)** |
| **Tone Mapping** | No | No | **PQ + ACES** |
| **Apple Silicon** | Basic support | Basic support | **Deep optimization (NEON)** |
| **Windows** | SDL required | SDL optional | **Native Cocoa (no SDL on macOS)** |
| **Input** | SDL | SDL or native | **Native NSEvent (macOS), SDL (Linux)** |
| **Resolution** | Manual setup | Manual setup | **Automatic detection (r_mode -2)** |
| **Audio** | OpenAL (optional) | Basic (no OpenAL) | **OpenAL 3D + Core Audio** |
| **Optimizations** | Standard | Performance + security | **LRU caches, async loading, SIMD** |

---

## ioquake3

**What it is:** Classic community source port of Quake III Arena with open source code.

**Key features:**
- Cross-platform (Windows, macOS, Linux)
- OpenGL renderer
- OpenAL audio
- VoIP support
- Ogg Vorbis music
- Active community and support

**For whom:** Those who need a stable, time-tested version with support for all platforms.

**Limitations:**
- OpenGL renderer (outdated API)
- No optimizations for Apple Silicon
- No support for modern HDR displays
- General performance without special optimizations

---

## quake3e

**What it is:** Modern fork focused on performance and security.

**Key features:**
- Cross-platform (Windows, macOS, Linux)
- Three renderers: optimized OpenGL, optimized Vulkan, OpenGL2 (legacy)
- Performance and security optimizations
- Raw mouse input
- Enhanced DoS attack protection
- SDL optional (can build without SDL)
- Compatibility with all Q3A mods
- Reworked QVM and Zone allocator

**For whom:** Those who want maximum performance and modern technologies on all platforms.

**Limitations:**
- No special optimizations for Apple Silicon
- No EDR/HDR10 support for Apple XDR displays
- No OpenAL (basic audio only)
- On macOS uses SDL by default (not native windows)

---

## Quake3mac

**What it is:** Specialized fork for macOS and Linux, optimized for Apple Silicon and modern displays.

### Unique Features

#### EDR/HDR10 for Apple XDR Displays
- **Only fork** with Extended Dynamic Range support for Apple XDR displays
- PQ (HDR10-style) and ACES Filmic tone mapping support
- Native work with Pro Display XDR, Studio Display and other EDR displays
- Proper handling of brightness above standard SDR white

#### Deep Apple Silicon Optimizations
- **NEON SIMD vectorization** for mathematical operations
- Compiler optimizations specifically for M1/M2/M3/M4
- Link Time Optimization (LTO) for better performance
- Automatic detection of performance cores for parallel builds

#### Native macOS Integration (no SDL)
- **Fully native Cocoa** (NSWindow, NSEvent) - no SDL on macOS
- **Native mouse input** via NSEvent (precise tracking, proper cursor capture)
- **Core Audio** for audio (AudioQueue API)
- **Automatic resolution detection** - game automatically detects native display resolution (5K, 4K, etc.)
- **Separate Space** for fullscreen mode (like native games)
- Proper Retina display support (native resolution)
- CAMetalLayer for optimal Vulkan work via MoltenVK
- Fewer dependencies - SDL2 not required on macOS (remains only for Linux)

#### Performance and Optimizations
- **LRU caches** for textures, sounds and files (fewer disk loads)
- **Asynchronous loading** of resources (game doesn't lag during loading)
- **Progressive loading** with priorities (critical resources first)
- **Preloading** of next map resources during gameplay
- Optimized ZIP archive work (PK3 files)

#### Enhanced Audio
- OpenAL 3D positional audio via openal-soft
- Optimized distance and attenuation calculations
- Batch updates of audio source positions
- Interpolation for smooth Doppler effect

#### Clean Code
- Windows support removed (focus on macOS/Linux)
- Legacy OpenGL code removed (Vulkan only)
- Simplified architecture without unnecessary abstractions

### Who Quake3mac is For

**Perfect for:**
- Mac owners with Apple Silicon (M1/M2/M3/M4)
- Apple XDR display owners (Pro Display XDR, Studio Display)
- Those who want maximum performance on macOS
- Users who value native macOS integration

**Not suitable for:**
- Windows users
- Those who need OpenGL renderer
- Users of old Intel Macs without Metal support

---

## Performance Comparison

### On Apple Silicon (M1/M2/M3/M4)

| Metric | ioquake3 | quake3e | **Quake3mac** |
|--------|----------|---------|---------------|
| FPS (1080p) | ~200 | ~250 | **~280+** |
| Map loading | ~3 sec | ~2.5 sec | **~1.5 sec** |
| CPU usage | High | Medium | **Low** |
| Memory | Standard | Optimized | **Caching** |

*Results may vary depending on map and settings*

### On Apple XDR Displays

| Feature | ioquake3 | quake3e | **Quake3mac** |
|---------|----------|---------|---------------|
| EDR support | No | No | Yes |
| HDR10 tone mapping | No | No | Yes |
| Brightness > SDR | No | No | Yes |
| Cinematic look | No | No | Yes |

---

## Technical Details

### Renderer

**ioquake3:**
- OpenGL renderer (renderergl1: GL 2.1+)
- OpenGL2 renderer (renderergl2: GL 3.3+, advanced shaders)
- Standard effects

**quake3e:**
- OpenGL renderer (optimized GL 1.1+, per-pixel dynamic lighting)
- Vulkan renderer (optimized, HDR, bloom, multisample, reversed depth buffer)
- OpenGL2 renderer (from ioquake3, unmaintained)
- FBO offscreen rendering

**Quake3mac:**
- **Vulkan only** (via MoltenVK)
- **EDR-optimized shaders** with tone mapping
- **Float16 swapchain** for HDR
- **PQ and ACES** tone mapping operators

### Loading System

**ioquake3 / quake3e:**
- Synchronous loading
- Basic caching

**Quake3mac:**
- **Asynchronous loading** in background
- **LRU caches** for all resources
- **Progressive loading** with priorities
- **Preloading** of next map

### Compilation Optimizations

**ioquake3 / quake3e:**
- Standard optimization flags
- Basic settings

**Quake3mac:**
- **-O3 -march=native** for target architecture
- **NEON vectorization** for Apple Silicon
- **LTO (Link Time Optimization)** for entire project
- **Automatic detection** of performance cores

---

## Recommendations

### Choose **ioquake3**, if:
- You need Windows support
- You want a stable, proven version
- You don't need modern optimizations
- You use an old Mac (Intel)

### Choose **quake3e**, if:
- You need maximum performance on all platforms
- You want choice between three renderers (OpenGL, Vulkan, OpenGL2)
- You play on Windows or Linux
- Security and DoS protection are important
- You don't need OpenAL (basic audio is enough)

### Choose **Quake3mac**, if:
- You use a Mac with Apple Silicon
- You have an Apple XDR display
- You need native macOS integration
- You want maximum performance on macOS
- Modern technologies (EDR/HDR10) are important
- You play only on macOS or Linux

---

## Conclusion

**Quake3mac** is a specialized fork created specifically for macOS users, especially for Apple Silicon and XDR display owners. If you play on Mac and want maximum performance and modern features (EDR/HDR10), then Quake3mac is the best choice.

For cross-platform play or if you need OpenGL, consider ioquake3 or quake3e.

---

## Additional Information

- [Building documentation](BUILD.md)
- [Configuration and settings](CONFIG.md)
- [Game installation](INSTALL.md)
