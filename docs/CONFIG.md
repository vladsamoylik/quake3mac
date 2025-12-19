# Quake 3 Mac Configuration

All settings are stored in `~/Library/Application Support/Quake3/baseq3/q3config.cfg`

## Graphics

### Resolution and Display Mode

| Command | Description | Values |
|---------|-------------|--------|
| `r_mode` | Resolution mode | -2 = auto-detect (native display resolution), 0-11 = presets |
| `r_fullscreen` | Fullscreen mode | 0 = window, 1 = fullscreen |
| `r_hidpi` | HiDPI/Retina support | 0 = scaled, 1 = native resolution |

**Automatic Resolution Detection (`r_mode -2`):**
The game automatically detects your display's native resolution (e.g., 5120x2880 for 5K or 3840x2160 for 4K). This is the recommended mode for modern displays. The game uses system APIs to get accurate resolution with Retina scaling taken into account.

### Graphics Quality

| Command | Description | Values |
|---------|-------------|--------|
| `r_picmip` | Texture quality | 0 = maximum, 1-16 = lower |
| `r_ext_multisample` | MSAA anti-aliasing | 0, 2, 4, 8 |
| `r_fbo` | Framebuffer objects | 0 = off, 1 = on (required for HDR/Bloom) |
| `r_hdr` | HDR rendering | 0 = off, 1 = 16-bit HDR |
| `r_bloom` | Bloom effect | 0 = off, 1 = on |
| `r_overBrightBits` | Lighting brightness | 0-2 |

### HDR and EDR (Extended Dynamic Range)

| Command | Description | Values |
|---------|-------------|--------|
| `r_edr` | macOS EDR for Apple XDR displays | 0 = off, 1 = on (requires `r_fbo 1`) |
| `r_edr_toneMapping` | Tone mapping operator for EDR | 0 = Linear (EDR default), 1 = PQ (HDR10-style), 2 = ACES Filmic |
| `r_gamma` | Gamma/brightness (works as exposure in EDR mode) | 0.5-3.0, default 1.0 |

**EDR (Extended Dynamic Range)** - support for extended dynamic range for Apple XDR displays (Pro Display XDR, Studio Display, etc.). Allows displaying content with brightness above standard SDR white.

**EDR Requirements:**
- macOS 10.15+ (Catalina or newer)
- Apple XDR display or display with EDR support
- `r_fbo 1` (required)
- Vulkan renderer (MoltenVK)

**Tone Mapping:**
- **Linear (0)** - linear output, standard EDR mode
- **PQ (1)** - Perceptual Quantizer (ST2084), HDR10-style tone mapping for cinematic look
- **ACES Filmic (2)** - alternative tone mapping operator for cinematic look

**Brightness Adjustment in EDR:**
In EDR mode, the `r_gamma` parameter works as an exposure multiplier. Use it to adjust image brightness:
```
r_edr 1
r_fbo 1
r_edr_toneMapping 1  // PQ for HDR10-style
r_gamma 1.2           // Increase brightness
```

### Performance

| Command | Description | Values |
|---------|-------------|--------|
| `r_swapInterval` | Vertical sync | 0 = off, 1 = on |
| `r_finish` | Wait for GPU | 0 = off, 1 = on |
| `com_maxfps` | FPS limit | 0 = unlimited, 60-250 |

## Audio

### OpenAL Settings

| Command | Description | Values |
|---------|-------------|--------|
| `s_backend` | Audio backend | "openal" or "base" |
| `s_volume` | Master volume | 0.0 - 1.0 |
| `s_musicvolume` | Music volume | 0.0 - 1.0 |
| `s_alSources` | Number of audio sources | 64-256 |
| `s_alMinDistance` | Min. attenuation distance | default 120 |
| `s_alMaxDistance` | Max. attenuation distance | default 1024 |
| `s_alRolloff` | Attenuation coefficient | default 2 |

## Controls

### Mouse

| Command | Description | Values |
|---------|-------------|--------|
| `sensitivity` | Mouse sensitivity | 1-30 |
| `m_pitch` | Vertical inversion | 0.022 = normal, -0.022 = inverted |
| `m_yaw` | Horizontal sensitivity | default 0.022 |
| `in_mouse` | Mouse mode | 1 = on |

### Keyboard

Key binding:
```
bind <key> <command>
```

Examples:
```
bind F11 screenshot
bind F12 screenshotJPEG
bind ESCAPE togglemenu
bind ` toggleconsole
```

## Console

| Command | Description | Values |
|---------|-------------|--------|
| `con_scale` | Console font scale | 1 = FullHD, 2 = 2K, 4 = 4K/5K |
| `con_notifytime` | Message display time | seconds |
| `scr_conspeed` | Console open speed | 1-10 |

## Network

| Command | Description | Values |
|---------|-------------|--------|
| `rate` | Connection speed | 25000 for broadband |
| `snaps` | Snapshots per second | 20-40 |
| `cl_maxpackets` | Max packets per second | 30-125 |
| `cl_packetdup` | Packet duplication | 0-2 |

## Memory

| Command | Description | Values |
|---------|-------------|--------|
| `com_hunkMegs` | Hunk memory size | 256 for 5K screenshots |
| `com_zoneMegs` | Zone memory size | 25 |

## Screenshots

| Command | Description | Values |
|---------|-------------|--------|
| `r_screenshotJpegQuality` | JPEG quality | 1-100, default 98 |

Commands:
- `screenshot` - save as JPEG (default)
- `screenshotTGA` - save as TGA
- `screenshotBMP` - save as BMP

Screenshots are saved to `~/Library/Application Support/Quake3/baseq3/screenshots/`

## Debugging

| Command | Description |
|---------|-------------|
| `developer 1` | Enable debug messages |
| `cvarlist` | List all variables |
| `cmdlist` | List all commands |
| `gfxinfo` | Graphics information |
| `vkinfo` | Vulkan information |

## Recommended Settings

### For 5K Displays (iMac, Studio Display)

```
r_mode -2
r_hidpi 1
r_ext_multisample 4
r_fbo 1
r_hdr 1
r_bloom 1
con_scale 4
com_hunkMegs 256
```

### For Apple XDR Displays (Pro Display XDR, Studio Display with EDR)

```
r_mode -2
r_hidpi 1
r_fbo 1
r_edr 1
r_edr_toneMapping 1  // PQ (HDR10-style) or 2 for ACES Filmic
r_gamma 1.0          // Brightness/exposure adjustment
r_ext_multisample 4
r_hdr 1
r_bloom 1
con_scale 4
com_hunkMegs 256
```

### For Maximum Performance

```
r_swapInterval 0
com_maxfps 0
r_ext_multisample 0
r_bloom 0
r_hdr 0
```
