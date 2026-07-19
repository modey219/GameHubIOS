# MN emulator - PC Game Emulator for iOS

Run Windows PC games on your iPhone and iPad. No internet required after installation.

**Created by @R_MOX** | Telegram: [@R_MOX](https://t.me/R_MOX)

## How It Works

```
game.exe (Windows x86_64)
    |
    v
Box64 (translates x86_64 instructions to ARM64)
    |
    v
Wine (Windows API compatibility layer)
    |
    v
MoltenVK (Vulkan -> Metal)
    |
    v
Metal (iPhone GPU rendering)
```

## Installation

### 1. Download the IPA
- Go to **Actions** tab on GitHub
- Click the latest build
- Download **MNEmulator.ipa** from Artifacts at the bottom

### 2. Install on iPhone

| Method | Website | Difficulty |
|--------|---------|------------|
| **AltStore** | [altstore.io](https://altstore.io) | Easy |
| **Sideloadly** | [sideloadly.io](https://sideloadly.io) | Easy |
| **LiveContainer** | App Store | Easy |
| **Scarlet** | [scarletinstall.com](https://scarletinstall.com) | Easy |

### 3. Enable JIT
- Install **StikDebug** from the App Store
- Open StikDebug -> tap "Enable JIT"
- Select MN emulator
- Return to the app and start playing

**Alternative JIT methods:**
- **SideJIT**: Run `pip install sidejit` on computer, connect iPhone via USB, run `sidejit server`
- **TrollStore**: If you have TrollStore, enable JIT permanently from TrollStore settings

## Adding Games

### Method 1: Direct Import
1. Open MN emulator
2. Tap **+** in the game library
3. Select a `.exe` file from the Files app
4. Tap **Add Game**

### Method 2: File Sharing (USB)
1. Connect iPhone to computer
2. Open Finder -> iPhone -> File Sharing -> MN emulator
3. Drag and drop game files

### Method 3: WiFi Transfer
1. In MN emulator, go to Settings
2. Start the WebDAV server
3. On computer, open browser and go to `http://YOUR_IP:8080`
4. Upload game files

### Method 4: Cloud Storage
1. Upload game files to Google Drive / iCloud
2. Download them on iPhone via Files app
3. In MN emulator, use Import to add them

## Recommended Settings

### Graphics
| Setting | Value | Notes |
|---------|-------|-------|
| GPU Driver | MoltenVK | Best for iOS |
| DXVK | Enabled | For DirectX 11 games |
| VKD3D | Enabled | For DirectX 12 games |
| Max FPS | 60 | Lower for heavy games |
| VSync | Enabled | Prevents tearing |

### Box64 Dynarec
| Setting | Value | Notes |
|---------|-------|-------|
| Enable Dynarec | Yes | **Requires JIT** |
| Big Block | Enabled | Speed boost |
| Strong Memory | Enabled | Stability |
| Safe Flags | Enabled | Safety |

**Presets available:** Safe / Balanced / Fast / Max Performance

### Wine
| Setting | Value | Notes |
|---------|-------|-------|
| ESync | Enabled | Better multithreading |
| FSync | Disabled | May not work on all games |
| CSMT | Enabled | Command stream optimization |

## Troubleshooting

### "Game is slow"
- Make sure JIT is enabled (StikDebug)
- Lower Max FPS in Graphics settings
- Use "Balanced" or "Safe" Box64 preset

### "No audio"
- Check Audio settings
- Try "Core Audio" driver
- Increase buffer size

### "Game won't launch"
- Make sure the .exe is Win64 (not Win32)
- Check the exe path is correct in container settings
- Enable debug logging and check the log
- Some games need additional DLL files (place in container's drive_c)

### "JIT not detected"
- Install StikDebug from the App Store
- Restart StikDebug, then restart MN emulator
- Use JIT-less mode as fallback (much slower)

### "posix_spawn failed / Operation not permitted"
- iOS restricts executing binaries from the Documents folder
- Enable JIT via StikDebug or TrollStore
- On jailbroken devices this works natively

## Requirements

- iPhone 12 or newer (A14 Bionic+)
- iOS 16.0+
- 2GB+ free storage
- No internet required after installation

## Project Structure

```
GameHubiOS/
├── GameHub/                 # Main source code
│   ├── GameHubApp.swift     # Entry point
│   ├── SwiftUI/             # UI views
│   ├── Core/                # Engine
│   │   ├── Box64/           # x86 emulation bridge
│   │   ├── Wine/            # Windows API layer
│   │   ├── Graphics/        # Metal rendering
│   │   ├── JIT/             # JIT management
│   │   ├── Input/           # Game controller support
│   │   └── Audio/           # Audio output
│   └── Native/              # C code
│       ├── Box64/           # Box64 bridge (C)
│       ├── SyscallTranslation/ # Linux syscall translation
│       └── Include/         # Headers
├── Scripts/                 # Build scripts
├── .github/workflows/       # CI/CD (GitHub Actions)
├── project.yml              # XcodeGen project spec
└── README.md
```

## Components

| Component | Version | License |
|-----------|---------|---------|
| Box64 | 0.4.0 | MIT |
| Wine | 9.21 | LGPL 2.1 |
| MoltenVK | 1.4.1 | Apache 2.0 |
| DXVK | 2.6.1 | zlib |

## License

MIT License - Open Source

---

**Created by [@R_MOX](https://t.me/R_MOX)**
