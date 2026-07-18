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
        createStartMenuEntries()
    }

    private func writeSystemRegistry() {
        let content = "Windows Registry Editor Version 5.00\n\n" +
        "[HKEY_LOCAL_MACHINE\\Software\\Wine]\n" +
        "\"Version\"=\"wine-9.0\"\n\n" +
        "[HKEY_LOCAL_MACHINE\\Software\\Wine\\Direct3D]\n" +
        "\"UseGLSL\"=\"enabled\"\n" +
        "\"DirectDrawRenderer\"=\"opengl\"\n" +
        "\"OffscreenRenderingMode\"=\"fbo\"\n" +
        "\"VideoMemorySize\"=\"2048\"\n" +
        "\"MaxFrameLatency\"=\"1\"\n" +
        "\"StrictDrawOrdering\"=\"disabled\"\n" +
        "\"CSMT\"=\"enabled\"\n\n" +
        "[HKEY_LOCAL_MACHINE\\Software\\Wine\\DllOverrides]\n" +
        "\"dxgi\"=\"native,builtin\"\n" +
        "\"d3d11\"=\"native,builtin\"\n" +
        "\"d3d10\"=\"native,builtin\"\n" +
        "\"d3d9\"=\"native,builtin\"\n" +
        "\"d3d8\"=\"native,builtin\"\n" +
        "\"d3dcompiler_47\"=\"native,builtin\"\n" +
        "\"dinput\"=\"native,builtin\"\n" +
        "\"dinput8\"=\"native,builtin\"\n" +
        "\"xinput1_3\"=\"native,builtin\"\n" +
        "\"xinput9_1_0\"=\"native,builtin\"\n\n" +
        "[HKEY_LOCAL_MACHINE\\System\\CurrentControlSet\\Control\\ProductOptions]\n" +
        "\"ProductType\"=\"WinNT\"\n"
        try? content.write(toFile: winePrefix + "/system.reg", atomically: true, encoding: .utf8)
    }

    private func writeUserRegistry() {
        let content = "Windows Registry Editor Version 5.00\n\n" +
        "[HKEY_CURRENT_USER\\Software\\Wine]\n" +
        "\"Version\"=\"win10\"\n\n" +
        "[HKEY_CURRENT_USER\\Software\\Wine\\Direct3D]\n" +
        "\"UseGLSL\"=\"enabled\"\n" +
        "\"DirectDrawRenderer\"=\"opengl\"\n" +
        "\"OffscreenRenderingMode\"=\"fbo\"\n" +
        "\"VideoMemorySize\"=\"2048\"\n" +
        "\"MaxFrameLatency\"=\"1\"\n" +
        "\"CSMT\"=\"enabled\"\n\n" +
        "[HKEY_CURRENT_USER\\Software\\Wine\\DllOverrides]\n" +
        "\"dxgi\"=\"native,builtin\"\n" +
        "\"d3d11\"=\"native,builtin\"\n" +
        "\"d3d9\"=\"native,builtin\"\n\n" +
        "[HKEY_CURRENT_USER\\Software\\Wine\\Explorer]\n" +
        "\"Desktop\"=\"Default\"\n\n" +
        "[HKEY_CURRENT_USER\\Control Panel\\Desktop]\n" +
        "\"Wallpaper\"=\"\"\n" +
        "\"TileWallpaper\"=\"0\"\n\n" +
        "[HKEY_CURRENT_USER\\Environment]\n" +
        "\"DXVK_HUD\"=\"fps\"\n" +
        "\"MVK_CONFIG_LOG_LEVEL\"=\"0\"\n"
        try? content.write(toFile: winePrefix + "/user.reg", atomically: true, encoding: .utf8)
    }

    private func writeDllOverrides() {
        let content = "Windows Registry Editor Version 5.00\n\n" +
        "[HKEY_CURRENT_USER\\Software\\Wine\\DllOverrides]\n" +
        "\"dxgi\"=\"native,builtin\"\n" +
        "\"d3d11\"=\"native,builtin\"\n" +
        "\"d3d10core\"=\"native,builtin\"\n" +
        "\"d3d9\"=\"native,builtin\"\n" +
        "\"d3d8\"=\"native,builtin\"\n" +
        "\"d3dcompiler_47\"=\"native,builtin\"\n" +
        "\"d3d12\"=\"native,builtin\"\n" +
        "\"d3d12core\"=\"native,builtin\"\n" +
        "\"dinput\"=\"native,builtin\"\n" +
        "\"dinput8\"=\"native,builtin\"\n" +
        "\"xinput1_3\"=\"native,builtin\"\n" +
        "\"xinput9_1_0\"=\"native,builtin\"\n" +
        "\"msvcrt\"=\"native,builtin\"\n" +
        "\"msvcp140\"=\"native,builtin\"\n" +
        "\"vcruntime140\"=\"native,builtin\"\n" +
        "\"vcruntime140_1\"=\"native,builtin\"\n" +
        "\"ucrtbase\"=\"native,builtin\"\n" +
        "\"ole32\"=\"builtin\"\n" +
        "\"oleaut32\"=\"builtin\"\n" +
        "\"shell32\"=\"builtin\"\n" +
        "\"kernel32\"=\"builtin\"\n" +
        "\"ntdll\"=\"builtin\"\n" +
        "\"user32\"=\"builtin\"\n" +
        "\"gdi32\"=\"builtin\"\n" +
        "\"advapi32\"=\"builtin\"\n" +
        "\"winmm\"=\"builtin\"\n" +
        "\"ws2_32\"=\"builtin\"\n"
        try? content.write(toFile: winePrefix + "/dlloverrides.reg", atomically: true, encoding: .utf8)
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
            "drive_c", "drive_c/windows/system32",
            "drive_c/Program Files", "drive_c/Program Files (x86)",
            "drive_c/games", "drive_c/users/winuser/Desktop",
            "drive_c/users/winuser/Documents", "drive_c/users/winuser/Downloads",
        ]
        for dir in dirs {
            try? fileManager.createDirectory(atPath: containerDir + "/" + dir, withIntermediateDirectories: true)
        }
        return containerDir
    }

    func setupDXVKForContainer(_ containerPath: String, maxFPS: Int = 60, showHUD: Bool = true) {
        let config = "[dxvk]\n" +
        "dxvk.numAsyncThreads = 2\n" +
        "dxvk.numCompilerThreads = 4\n" +
        "dxvk.enableAsync = true\n" +
        "dxvk.hud = \(showHUD ? "fps,frametimes" : "none")\n" +
        "dxvk.maxFrameRate = \(maxFPS)\n" +
        "dxvk.syncInterval = 0\n\n" +
        "[d3d9]\n" +
        "d3d9.presentInterval = 0\n" +
        "d3d9.allowDoNotWait = true\n\n" +
        "[d3d11]\n" +
        "d3d11.relaxedBarriers = true\n" +
        "d3d11.async = true\n"
        try? config.write(toFile: containerPath + "/dxvk.conf", atomically: true, encoding: .utf8)
    }

    func setupVKD3DForContainer(_ containerPath: String) {
        let config = "[VKD3D]\n" +
        "vkd3d.shader_model = 6_5\n"
        try? config.write(toFile: containerPath + "/vkd3d.conf", atomically: true, encoding: .utf8)
    }

    func setupContainerRegistry(_ containerPath: String) {
        let systemReg = "Windows Registry Editor Version 5.00\n\n" +
        "[HKEY_CURRENT_USER\\Software\\Wine\\Direct3D]\n" +
        "\"UseGLSL\"=\"enabled\"\n" +
        "\"VideoMemorySize\"=\"2048\"\n" +
        "\"CSMT\"=\"enabled\"\n" +
        "\"OffscreenRenderingMode\"=\"fbo\"\n" +
        "\"MaxFrameLatency\"=\"1\"\n\n" +
        "[HKEY_CURRENT_USER\\Software\\Wine\\DllOverrides]\n" +
        "\"dxgi\"=\"native,builtin\"\n" +
        "\"d3d11\"=\"native,builtin\"\n" +
        "\"d3d9\"=\"native,builtin\"\n"
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
