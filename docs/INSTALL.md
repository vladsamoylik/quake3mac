# Quake 3 Mac Installation

## Requirements

- macOS 11.0+ (Big Sur or newer)
- Original Quake III Arena game files (pak0.pk3 and others)

## Game Data Installation

### Step 1: Create Directory

```bash
mkdir -p ~/Library/Application\ Support/Quake3/baseq3
```

### Step 2: Copy Game Files

Copy the contents of the `baseq3` folder from your Quake III Arena installation:

```bash
cp /path/to/quake3/baseq3/*.pk3 ~/Library/Application\ Support/Quake3/baseq3/
```

Minimum required files:
- `pak0.pk3` - main game data (required)
- `pak1.pk3` - `pak8.pk3` - patches and addons (recommended)

### Step 3: Build Application

If you don't have a ready `.app` bundle yet, build it:

```bash
cd quake3mac
make
make app
```

After building, `Quake 3.app` will be in `build/release-darwin-aarch64/`

### Step 4: Install Application

Move `Quake 3.app` to `/Applications` folder or run from anywhere.

## Directory Structure

```
~/Library/Application Support/Quake3/
├── baseq3/
│   ├── pak0.pk3          # Main game data
│   ├── pak1.pk3          # Patch 1.11
│   ├── ...
│   ├── q3config.cfg      # Configuration (created automatically)
│   └── screenshots/      # Screenshots
├── missionpack/          # Team Arena (optional)
└── mods/                 # Modifications
```

## First Launch

1. Launch `Quake 3.app`
2. Game will create configuration file `q3config.cfg`
3. Configure graphics and controls in menu

## Modifications

To install mods, create a folder with the mod name:

```bash
mkdir -p ~/Library/Application\ Support/Quake3/mymod
```

And copy mod files there. Launch:

```bash
./quake3mac.aarch64 +set fs_game mymod
```

## Multiplayer

For online play, make sure:
- Port 27960 UDP is open in firewall
- Game version is compatible with server (1.32)

## Troubleshooting

### Game Won't Launch
- Check for `pak0.pk3` in the correct directory
- Make sure dependencies are installed (`brew list`)

### No Audio
- Check `s_backend` in console (should be `openal`)
- Make sure OpenAL is installed: `brew list openal-soft`

### Low FPS
- Disable vertical sync: `r_swapInterval 0`
- Reduce resolution: set `r_mode` to a preset value (0-11) instead of automatic detection
