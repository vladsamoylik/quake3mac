# Building Quake 3 Mac

## Requirements

### macOS
- macOS 11.0+ (Big Sur or newer)
- Xcode Command Line Tools
- Homebrew

### Dependencies

Install via Homebrew:

```bash
brew install freetype openal-soft jpeg-turbo libogg libvorbis
```

**Note:** 
- **macOS**: SDL2 not required - uses native Cocoa (windows, input), Core Audio (audio) and Metal (rendering)
- **Linux**: SDL2 required for windows and input

## Building

### Cloning the repository

```bash
git clone https://github.com/vladsamoylik/quake3mac.git
cd quake3mac
```

### Compilation

```bash
make
```

Binary will be created in `build/release-darwin-aarch64/quake3mac.aarch64`

### Creating .app bundle

```bash
make app
```

Application will be created in `build/release-darwin-aarch64/Quake 3.app`

### Cleanup

```bash
make clean
```

## Build Options

| Variable | Description | Default |
|----------|-------------|---------|
| `USE_OPENAL` | Enable OpenAL audio | 1 |
| `USE_CURL` | Enable libcurl for downloads | 1 |
| `USE_FREETYPE` | Enable FreeType for fonts | 1 |

Example:
```bash
make USE_OPENAL=1 USE_CURL=0
```

## Architectures

- **Apple Silicon (M1/M2/M3/M4)**: `aarch64` - native build
- **Intel Mac**: `x86_64` - supported but not optimized

Architecture is determined automatically.

## Debug Build

```bash
make debug
```

Creates binary with debug symbols in `build/debug-darwin-aarch64/`

## Shader Compilation

Shaders are already compiled and included in the repository. If you modified shaders (e.g., `code/renderervk/shaders/gamma.frag`), they need to be recompiled:

### Requirements

Install Vulkan SDK or glslang:

```bash
# Via Homebrew
brew install vulkan-headers vulkan-loader glslang

# Or download Vulkan SDK from https://vulkan.lunarg.com/
```

### Compilation

```bash
cd code/renderervk/shaders
./compile_macos.sh
```

The script automatically:
1. Compiles GLSL shaders to SPIR-V
2. Converts them to C arrays
3. Updates `spirv/shader_data.c`

After compiling shaders, rebuild the project:

```bash
make clean && make release
```

**Important:** Shaders must be recompiled after any changes to `.frag` or `.vert` files for new features to work (e.g., tone mapping for EDR).
