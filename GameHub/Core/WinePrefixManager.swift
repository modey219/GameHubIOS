import Foundation

class WinePrefixManager {
    static let shared = WinePrefixManager()

    private let fileManager = FileManager.default
    private var documentsPath: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    private var winePrefix: String {
        documentsPath.appendingPathComponent("Wine").path
    }

    func initializePrefix() {
        let fm = fileManager

        let directories = [
            "drive_c",
            "drive_c/windows",
            "drive_c/windows/system32",
            "drive_c/windows/system32/drivers",
            "drive_c/windows/system32/drivers/etc",
            "drive_c/windows/fonts",
            "drive_c/windows/temp",
            "drive_c/Program Files",
            "drive_c/Program Files (x86)",
            "drive_c/users",
            "drive_c/users/Public",
            "drive_c/users/Public/Desktop",
            "drive_c/users/Public/Documents",
            "drive_c/users/winuser",
            "drive_c/users/winuser/AppData",
            "drive_c/users/winuser/AppData/Local",
            "drive_c/users/winuser/AppData/Local/Temp",
            "drive_c/users/winuser/AppData/Roaming",
            "drive_c/users/winuser/Desktop",
            "drive_c/users/winuser/Documents",
            "drive_c/users/winuser/Downloads",
            "drive_c/users/winuser/My Games",
            "drive_c/games",
            "drive_c/Games",
            "temp",
            "input",
            "logs",
        ]

        for dir in directories {
            let fullPath = (winePrefix as NSString).appendingPathComponent(dir)
            if !fm.fileExists(atPath: fullPath) {
                try? fm.createDirectory(atPath: fullPath, withIntermediateDirectories: true)
            }
        }

        writeSystemRegistry()
        writeUserRegistry()
        writeDllOverrides()
        writeDriveMappings()
        writeWineDebugConfig()
        createStartMenuEntries()
    }

    private func writeSystemRegistry() {
        let content = """
        Windows Registry Editor Version 5.00

        [HKEY_LOCAL_MACHINE\\Software\\Wine]
        "Version"="wine-9.0"
        "SYSDLLS"="disabled"

        [HKEY_LOCAL_MACHINE\\Software\\Wine\\Direct3D]
        "UseGLSL"="enabled"
        "DirectDrawRenderer"="opengl"
        "OffscreenRenderingMode"="fbo"
        "VideoMemorySize"="2048"
        "MaxFrameLatency"="1"
        "StrictDrawOrdering"="disabled"
        "CSMT"="enabled"
        "VideoPciDeviceId"=dword:00000000
        "VideoVendorID"=dword:00000000

        [HKEY_LOCAL_MACHINE\\Software\\Wine\\DllOverrides]
        "dxgi"="native,builtin"
        "d3d11"="native,builtin"
        "d3d10"="native,builtin"
        "d3d9"="native,builtin"
        "d3d8"="native,builtin"
        "d3dcompiler_47"="native,builtin"
        "dinput"="native,builtin"
        "dinput8"="native,builtin"
        "xinput1_3"="native,builtin"
        "xinput9_1_0"="native,builtin"
        "msvcrt"="native,builtin"
        "msvcp140"="native,builtin"
        "vcruntime140"="native,builtin"
        "vcruntime140_1"="native,builtin"
        "ole32"="builtin"
        "oleaut32"="builtin"
        "shell32"="builtin"
        "kernel32"="builtin"
        "ntdll"="builtin"
        "user32"="builtin"
        "gdi32"="builtin"
        "advapi32"="builtin"
        "winmm"="builtin"

        [HKEY_LOCAL_MACHINE\\Software\\Wine\\Drivers]
        "Audio"="pulse"

        [HKEY_LOCAL_MACHINE\\System\\CurrentControlSet\\Control\\ProductOptions]
        "ProductType"="WinNT"

        [HKEY_LOCAL_MACHINE\\System\\CurrentControlSet\\Control\\Windows]
        "CSDVersion"=dword:00000100
        """
        try? content.write(toFile: winePrefix + "/system.reg", atomically: true, encoding: .utf8)
    }

    private func writeUserRegistry() {
        let content = """
        Windows Registry Editor Version 5.00

        [HKEY_CURRENT_USER\\Software\\Wine]
        "Version"="win10"

        [HKEY_CURRENT_USER\\Software\\Wine\\Direct3D]
        "UseGLSL"="enabled"
        "DirectDrawRenderer"="opengl"
        "OffscreenRenderingMode"="fbo"
        "VideoMemorySize"="2048"
        "MaxFrameLatency"="1"
        "CSMT"="enabled"

        [HKEY_CURRENT_USER\\Software\\Wine\\DllOverrides]
        "dxgi"="native,builtin"
        "d3d11"="native,builtin"
        "d3d9"="native,builtin"

        [HKEY_CURRENT_USER\\Software\\Wine\\Explorer]
        "Desktop"="Default"

        [HKEY_CURRENT_USER\\Control Panel\\Desktop]
        "Wallpaper"=""
        "TileWallpaper"="0"

        [HKEY_CURRENT_USER\\Software\\Wine\\Vulkan\\Drivers]
        "MVK"="1"

        [HKEY_CURRENT_USER\\Environment]
        "DXVK_HUD"="fps"
        "MVK_CONFIG_LOG_LEVEL"="0"
        """
        try? content.write(toFile: winePrefix + "/user.reg", atomically: true, encoding: .utf8)
    }

    private func writeDllOverrides() {
        let content = """
        ; GameHub iOS - Wine DLL Overrides
        ; DXVK (DX11 → Vulkan)
        dxgi = native,builtin
        d3d11 = native,builtin
        d3d10core = native,builtin
        d3d9 = native,builtin
        d3d8 = native,builtin
        d3dcompiler_47 = native,builtin

        ; VKD3D (DX12 → Vulkan)
        d3d12 = native,builtin
        d3d12core = native,builtin

        ; Input
        dinput = native,builtin
        dinput8 = native,builtin
        xinput1_3 = native,builtin
        xinput9_1_0 = native,builtin

        ; Runtime
        msvcrt = native,builtin
        msvcp140 = native,builtin
        vcruntime140 = native,builtin
        vcruntime140_1 = native,builtin
        ucrtbase = native,builtin
        api-ms-win-crt-* = native,builtin

        ; Core (use builtin)
        ole32 = builtin
        oleaut32 = builtin
        shell32 = builtin
        kernel32 = builtin
        ntdll = builtin
        user32 = builtin
        gdi32 = builtin
        advapi32 = builtin
        winmm = builtin
        ws2_32 = builtin
        wininet = builtin
        winhttp = builtin
        urlmon = builtin
        crypt32 = builtin
        """
        try? content.write(toFile: winePrefix + "/dlloverrides.reg", atomically: true, encoding: .utf8)
    }

    private func writeDriveMappings() {
        let content = """
        [Wine]
        "W"="\\\\?\\unix\(documentsPath.appendingPathComponent("Containers").path.replacingOccurrences(of: "\\", with: "/"))"
        "Z"="\\\\?\\unix/"
        """
        try? content.write(toFile: winePrefix + "/dosdevices.reg", atomically: true, encoding: .utf8)
    }

    private func writeWineDebugConfig() {
        let content = """
        # Wine Debug Configuration for GameHub iOS
        # Disable noisy channels
        WINEDEBUG=-all

        # Enable specific channels for debugging
        # WINEDEBUG=+relay,+tid

        # DXVK settings
        DXVK_LOG_LEVEL=none
        DXVK_FRAME_RATE=60
        DXVK_HUD=fps

        # MoltenVK settings
        MVK_CONFIG_LOG_LEVEL=0
        MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS=1

        # VKD3D settings
        VKD3D_CONFIG=dxr
        VKD3D_FEATURE_LEVEL=12_1

        # Wine environment
        WINEARCH=win64
        WINEESYNC=1
        WINEFSYNC=1
        STAGING_SHARED_MEMORY=1
        """
        try? content.write(toFile: winePrefix + "/wine_debug.conf", atomically: true, encoding: .utf8)
    }

    private func createStartMenuEntries() {
        let startMenu = winePrefix + "/drive_c/ProgramData/Microsoft/Windows/Start Menu/Programs"
        try? fileManager.createDirectory(atPath: startMenu, withIntermediateDirectories: true)

        let gamesDir = startMenu + "/Games"
        try? fileManager.createDirectory(atPath: gamesDir, withIntermediateDirectories: true)
    }

    func createContainer(name: String) -> String {
        let containerID = UUID().uuidString
        let containerDir = winePrefix + "/containers/\(containerID)"

        let dirs = [
            "drive_c",
            "drive_c/windows/system32",
            "drive_c/Program Files",
            "drive_c/Program Files (x86)",
            "drive_c/games",
            "drive_c/users/winuser/Desktop",
            "drive_c/users/winuser/Documents",
            "drive_c/users/winuser/Downloads",
        ]

        for dir in dirs {
            try? fileManager.createDirectory(atPath: containerDir + "/" + dir, withIntermediateDirectories: true)
        }

        return containerDir
    }

    func setupDXVKForContainer(_ containerPath: String, maxFPS: Int = 60, showHUD: Bool = true) {
        let config = """
        [dxvk]
        dxvk.numAsyncThreads = 2
        dxvk.numCompilerThreads = 4
        dxvk.enableAsync = true
        dxvk.hud = \(showHUD ? "fps,frametimes" : "none")
        dxvk.maxFrameRate = \(maxFPS)
        dxvk.syncInterval = 0
        dxvk.graphicsPipelineLibraryMode = 2

        [d3d9]
        d3d9.presentInterval = 0
        d3d9.forceSamplerTypeConstants = false
        d3d9.floatEmulation = strict
        d3d9.allowDoNotWait = true

        [d3d11]
        d3d11.relaxedBarriers = true
        d3d11.async = true
        """
        try? config.write(toFile: containerPath + "/dxvk.conf", atomically: true, encoding: .utf8)
    }

    func setupVKD3DForContainer(_ containerPath: String) {
        let config = """
        [VKD3D]
        vkd3d.shader_model = 6_5
        vkd3d.enable_acceleration_structure = 1
        vkd3d.enable_raytracing = 1
        """
        try? config.write(toFile: containerPath + "/vkd3d.conf", atomically: true, encoding: .utf8)
    }

    func setupContainerRegistry(_ containerPath: String) {
        let systemReg = """
        Windows Registry Editor Version 5.00

        [HKEY_CURRENT_USER\\Software\\Wine\\Direct3D]
        "UseGLSL"="enabled"
        "VideoMemorySize"="2048"
        "CSMT"="enabled"
        "OffscreenRenderingMode"="fbo"
        "MaxFrameLatency"="1"

        [HKEY_CURRENT_USER\\Software\\Wine\\DllOverrides]
        "dxgi"="native,builtin"
        "d3d11"="native,builtin"
        "d3d9"="native,builtin"
        """
        try? systemReg.write(toFile: containerPath + "/system.reg", atomically: true, encoding: .utf8)
    }

    func getWinePrefixPath() -> String { winePrefix }
    func getDriveCPath() -> String { winePrefix + "/drive_c" }
    func getBoxesPath() -> String { winePrefix + "/containers" }

    func deletePrefix() {
        try? fileManager.removeItem(atPath: winePrefix)
    }

    func getPrefixSize() -> Int64 {
        Self.getDirectorySize(URL(fileURLWithPath: winePrefix))
    }

    private static func getDirectorySize(_ url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
               let size = attrs[.size] as? Int64 {
                total += size
            }
        }
        return total
    }
}
