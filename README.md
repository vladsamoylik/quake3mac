# Quake 3 Mac

Modern Quake III Arena client for macOS and Linux, based on [Quake3e](https://github.com/ec-/Quake3e) and [ioquake3](https://github.com/ioquake/ioq3).

**Repository:** https://github.com/vladsamoylik/quake3mac

## Features

- **Vulkan renderer** via MoltenVK (no legacy OpenGL)
- **EDR/HDR10 support** for Apple XDR displays with PQ and ACES tone mapping
- **Native macOS** - Cocoa windows, Core Audio, native input (no SDL on macOS)
- **Automatic resolution detection** - game automatically detects native display resolution
- **OpenAL 3D audio** with positional audio (via openal-soft)
- **Apple Silicon optimization** (M1/M2/M3/M4 with NEON vectorization)
- **Modern dependencies** via Homebrew (FreeType, libjpeg-turbo, Ogg/Vorbis, OpenAL)
- **Clean code** - Windows support and legacy code removed

## Quick Start

```bash
# Install dependencies
brew install freetype openal-soft jpeg-turbo libogg libvorbis

# Build
make
make app

# Copy game data
mkdir -p ~/Library/Application\ Support/Quake3/baseq3
cp /path/to/quake3/baseq3/*.pk3 ~/Library/Application\ Support/Quake3/baseq3/
```

## Documentation

- [Comparison with other forks](docs/COMPARISON.md) - how Quake3mac differs from ioquake3 and quake3e
- [Building](docs/BUILD.md) - compilation instructions
- [Installation](docs/INSTALL.md) - game installation and data setup
- [Configuration](docs/CONFIG.md) - all configuration parameters

## Credits

- [id Software](https://www.idsoftware.com/) - original Quake III Arena
- [ioquake3](https://ioquake3.org/) - community source port
- [Quake3e](https://github.com/ec-/Quake3e) - improved client with Vulkan renderer

## License

GPL v2 - see [COPYING.txt](COPYING.txt)
