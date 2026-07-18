import SwiftUI

struct ImportGameView: View {
    @EnvironmentObject var containerManager: ContainerManager
    @Environment(\.dismiss) var dismiss
    @State private var selectedMethod: ImportMethod = .files
    @State private var isLoading = false
    @State private var importedFiles: [URL] = []
    @State private var showProgress = false

    enum ImportMethod: String, CaseIterable {
        case files = "Files App"
        case itunes = "iTunes/Finder"
        case webDAV = "WebDAV"
        case clipboard = "Clipboard"
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Picker("Import Method", selection: $selectedMethod) {
                    ForEach(ImportMethod.allCases, id: \.self) { method in
                        Text(method.rawValue).tag(method)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                switch selectedMethod {
                case .files:
                    filesImportView
                case .itunes:
                    itunesImportView
                case .webDAV:
                    webDAVImportView
                case .clipboard:
                    clipboardImportView
                }

                Spacer()
            }
            .navigationTitle("Import Games")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var filesImportView: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder")
                .font(.system(size: 40))
                .foregroundColor(.blue)

            Text("Import from Files App")
                .font(.headline)

            Text("Select .exe files or game folders")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Button(action: openFilePicker) {
                Label("Browse Files", systemImage: "doc.badge.plus")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding(.horizontal)

            if showProgress {
                ProgressView("Importing files...")
                    .padding()
            }
        }
    }

    private var itunesImportView: some View {
        VStack(spacing: 16) {
            Image(systemName: "desktopcomputer")
                .font(.system(size: 40))
                .foregroundColor(.blue)

            Text("Import via iTunes/Finder")
                .font(.headline)

            Text("Connect your iPhone to your computer and use Finder (macOS Catalina+) or iTunes to transfer game files to the GameHub Documents folder.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            Text("Files should be placed in:\n\(documentsPath.path)")
                .font(.caption)
                .foregroundColor(.secondary)
                .textSelection(.enabled)
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal)
        }
    }

    private var webDAVImportView: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi")
                .font(.system(size: 40))
                .foregroundColor(.blue)

            Text("Import via WebDAV")
                .font(.headline)

            Text("Use any WebDAV client to upload files wirelessly.")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Button(action: startWebDAVServer) {
                Label("Start WebDAV Server", systemImage: "server.rack")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding(.horizontal)

            if let ip = getWiFiIPAddress() {
                Text("WebDAV URL: http://\(ip):8080")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                    .padding(.horizontal)
            }
        }
    }

    private var clipboardImportView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 40))
                .foregroundColor(.blue)

            Text("Import from Clipboard")
                .font(.headline)

            Text("Copy a file path and paste it here")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Button(action: importFromClipboard) {
                Label("Paste & Import", systemImage: "doc.on.clipboard")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding(.horizontal)
        }
    }

    private func openFilePicker() {
        let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: [.data, .folder])
        documentPicker.allowsMultipleSelection = true
        documentPicker.delegate = DocumentPickerDelegate.shared

        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            root.present(documentPicker, animated: true)
        }
    }

    private func startWebDAVServer() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [
            "-m", "http.server", "8080",
            "--directory", FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].path,
        ]
        try? process.run()
    }

    private func importFromClipboard() {
        if let path = UIPasteboard.general.string {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: path) {
                importedFiles.append(url)
            }
        }
    }

    private func getWiFiIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family

            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(
                        interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                        &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST
                    )
                    address = String(cString: hostname)
                }
            }
        }

        return address
    }
}

class DocumentPickerDelegate: NSObject, UIDocumentPickerDelegate, ObservableObject {
    static let shared = DocumentPickerDelegate()

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        for url in urls {
            let shouldAccess = url.startAccessingSecurityScopedResource()
            defer { if shouldAccess { url.stopAccessingSecurityScopedResource() } }

            let destPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent(url.lastPathComponent).path

            try? FileManager.default.copyItem(atPath: url.path, toPath: destPath)
        }
    }
}
