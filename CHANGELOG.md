# Changelog

## Build 2026.07.19 - Major Update

### Fixes
- **Box64 launch architecture**: Changed from `posix_spawn` (which fails on iOS due to noexec) to thread-based in-process launch via C bridge
- **Binary copy to /tmp**: Binaries are now copied to temp directory for better execution compatibility
- **Process.processIdentifier**: Added missing property to custom Process stub
- **WIFEXITED/WEXITSTATUS**: Replaced unavailable C macros with inline bit operations
- **iOSPipe optional unwrapping**: Fixed all optional chain access for pipe readOutput
- **UIKit import**: Added missing import for UIApplication in SettingsManager
- **Duplicate case 202**: Confirmed only one futex case in syscall_core.c
- **CI icon generation**: Inlined Python script to eliminate path dependency issues
- **project.yml bundleIdPrefix**: Fixed from com.gamehub to com.mnemulator

### New Features
- **Overlay menu**: Complete redesign with grid layout
  - Close menu button (xmark)
  - Controller toggle
  - Keyboard toggle  
  - Pause/Resume game
  - View game log
  - Take screenshot (saves to Photos)
  - In-game settings
  - Mute audio
  - Restart game
  - Exit to main menu (with confirmation dialog)
- **Top bar**: Prominent X close button with confirmation, FPS + timer + PAUSED indicator
- **Copy log button**: One-tap copy with toast notification
- **50+ settings** across 9 sections:
  - General: Dark mode, keep screen on, auto-save, haptic, touch buttons
  - Graphics: GPU driver, DXVK/VKD3D, MSAA, AF, texture quality, shader precision, async, HUD
  - Audio: Enable/disable, driver, volume, sample rate, buffer count, latency mode
  - Input: Gamepad type, deadzone, stick mode, touch sensitivity, button opacity
  - Wine: ESync/FSync/CSMT, Proton mode, virtual desktop, DLL overrides, debug levels
  - Box64: Dynarec, big block, strong mem, safe flags, altivec, call/ret, 4 presets
  - Display: Orientation, brightness, controller button
  - Advanced: Clear cache, clear containers, export/import settings, reset all
  - About: Component versions, credits, GitHub link, Telegram link
- **JIT detection**: Added `task_info` TASK_DYLD_INFO check alongside sysctl P_TRACED
- **TrollStore JIT**: Added TrollStore as 4th JIT method option
- **Restart game**: Button in overlay to restart the current game
- **Mute audio**: Quick mute button in overlay

### Improvements
- **Overlay buttons**: Icon + label vertical grid layout, 60x50pt
- **Exit confirmation**: Warning dialog with Cancel/Exit buttons before leaving game
- **Log view**: Dedicated Copy Log button with toast, monospace font
- **Settings segmented picker**: Replaced dropdown with segmented control
- **Box64 presets**: Safe/Balanced/Fast/Max Performance quick-select buttons
- **README**: Complete English rewrite with Telegram @R_MOX link, installation guide, troubleshooting

## Build 2026.07.18 - Initial Rename & Stabilization
- Renamed from GameHub to MN emulator
- Fixed extraction errors (pre-existing directories)
- Rewrote JITManager, ProcessStub, JITStatusView, DebugView
- Added LaunchResult struct for detailed error reporting
- CI pipeline with Box64 compilation, binary injection, icon generation
