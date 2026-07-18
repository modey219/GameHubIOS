import SwiftUI
import UniformTypeIdentifiers
import Network

struct ImportGameView: View {
    @Environment(\.dismiss) var dismiss
    @State private var selectedMethod: ImportMethod = .files
    @State private var webServerRunning = false
    @State private var webServerPort: UInt16 = 8080
    @State private var webServer: SimpleHTTPServer?
    @State private var uploadedFiles: [String] = []

    enum ImportMethod: String, CaseIterable {
        case files = "Files App"
        case itunes = "iTunes/Finder"
        case webDAV = "WebDAV"
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Picker("Method", selection: $selectedMethod) {
                    ForEach(ImportMethod.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                switch selectedMethod {
                case .files: filesView
                case .itunes: itunesView
                case .webDAV: webDAVView
                }
                Spacer()
            }
            .navigationTitle("Import Games")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Done") {
                    webServer?.stop()
                    webServer = nil
                    webServerRunning = false
                    dismiss()
                } }
            }
        }
    }

    private var filesView: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder").font(.system(size: 40)).foregroundColor(.blue)
            Text("Files App").font(.headline)
            Text("Select .exe files or game folders from your device")
                .font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)

            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            VStack(alignment: .leading, spacing: 4) {
                Text("Place files in:").font(.caption).bold()
                Text(docs.appendingPathComponent("Containers").path)
                    .font(.caption2).foregroundColor(.secondary).textSelection(.enabled)
            }
            .padding().background(Color(.systemGray6)).cornerRadius(8).padding(.horizontal)
        }
    }

    private var itunesView: some View {
        VStack(spacing: 16) {
            Image(systemName: "desktopcomputer").font(.system(size: 40)).foregroundColor(.blue)
            Text("iTunes / Finder").font(.headline)
            Text("Connect iPhone to computer → Select device → File Sharing → GameHub → Drag & drop .exe files")
                .font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center).padding(.horizontal)
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            Text(docs.path).font(.caption).foregroundColor(.secondary).textSelection(.enabled)
                .padding().background(Color(.systemGray6)).cornerRadius(8).padding(.horizontal)
        }
    }

    private var webDAVView: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi").font(.system(size: 40)).foregroundColor(.blue)
            Text("File Server").font(.headline)
            Text("Upload files wirelessly from any device on the same network")
                .font(.subheadline).foregroundColor(.secondary)

            Button(action: toggleServer) {
                Label(webServerRunning ? "Stop Server" : "Start Server",
                      systemImage: webServerRunning ? "stop.fill" : "play.fill")
                    .frame(maxWidth: .infinity).padding()
                    .background(webServerRunning ? Color.red : Color.green)
                    .foregroundColor(.white).cornerRadius(10)
            }
            .padding(.horizontal)

            if webServerRunning, let ip = getIPAddress() {
                VStack(spacing: 8) {
                    Text("Upload URL:").font(.caption).bold()
                    Text("http://\(ip):\(webServerPort)").font(.caption).textSelection(.enabled)
                    Text("Open this URL in a browser on any device to upload files")
                        .font(.caption2).foregroundColor(.secondary)
                }
                .padding().background(Color(.systemGray6)).cornerRadius(8).padding(.horizontal)
            }

            if !uploadedFiles.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recently uploaded:").font(.caption).bold()
                    ForEach(uploadedFiles.suffix(5), id: \.self) { file in
                        HStack {
                            Image(systemName: "checkmark.circle.fill").foregroundColor(.green).font(.caption2)
                            Text(file).font(.caption2)
                        }
                    }
                }
                .padding().background(Color(.systemGray6)).cornerRadius(8).padding(.horizontal)
            }
        }
    }

    private func toggleServer() {
        if webServerRunning {
            webServer?.stop()
            webServer = nil
            webServerRunning = false
        } else {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].path
            let server = SimpleHTTPServer(port: webServerPort, directory: docs) { [weak self] fileName in
                DispatchQueue.main.async {
                    self?.uploadedFiles.append(fileName)
                }
            }
            if server.start() {
                webServer = server
                webServerRunning = true
            }
        }
    }

    private func getIPAddress() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            guard let addrPointer = interface.ifa_addr else { continue }
            if addrPointer.pointee.sa_family == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" || name == "en1" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    let sockLen = socklen_t(addrPointer.pointee.sa_len)
                    getnameinfo(addrPointer, sockLen, &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
                    let ip = String(cString: hostname)
                    if !ip.isEmpty { return ip }
                }
            }
        }
        return nil
    }
}

class SimpleHTTPServer {
    private var listener: CFSocketRef?
    private var port: UInt16
    private var directory: String
    private var onUpload: ((String) -> Void)?
    private var serverQueue = DispatchQueue(label: "com.gamehub.httpserver", qos: .userInitiated)

    init(port: UInt16, directory: String, onUpload: ((String) -> Void)? = nil) {
        self.port = port
        self.directory = directory
        self.onUpload = onUpload
    }

    func start() -> Bool {
        let serverFD = socket(AF_INET, SOCK_STREAM, 0)
        guard serverFD >= 0 else { return false }

        var reuse: Int32 = 1
        setsockopt(serverFD, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = INADDR_ANY

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(serverFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else { close(serverFD); return false }
        guard listen(serverFD, 5) == 0 else { close(serverFD); return false }

        serverQueue.async { [weak self] in
            self?.acceptLoop(serverFD: serverFD)
        }

        print("[HTTPServer] Started on port \(port), serving \(directory)")
        return true
    }

    func stop() {
        if let fd = listener { close(CFSocketGetNative(fd)) }
        listener = nil
    }

    private func acceptLoop(serverFD: Int32) {
        while true {
            var clientAddr = sockaddr_in()
            var clientLen = socklen_t(MemoryLayout<sockaddr_in>.size)
            let clientFD = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    accept(serverFD, $0, &clientLen)
                }
            }
            guard clientFD >= 0 else { break }
            serverQueue.async { [weak self] in
                self?.handleClient(clientFD: clientFD)
            }
        }
    }

    private func handleClient(clientFD: Int32) {
        defer { close(clientFD) }

        var buffer = [UInt8](repeating: 0, count: 65536)
        let bytesRead = recv(clientFD, &buffer, buffer.count, 0)
        guard bytesRead > 0 else { return }

        let request = String(bytes: buffer.prefix(bytesRead), encoding: .utf8) ?? ""
        let lines = request.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else { return }
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else { return }

        let method = String(parts[0])
        let path = String(parts[1])

        if method == "GET" && (path == "/" || path.isEmpty) {
            sendUploadPage(clientFD: clientFD)
        } else if method == "POST" && path == "/upload" {
            handleUpload(clientFD: clientFD, request: request, buffer: buffer, bytesRead: bytesRead)
        } else {
            send404(clientFD: clientFD)
        }
    }

    private func sendUploadPage(clientFD: Int32) {
        let html = """
        <!DOCTYPE html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <title>GameHub File Upload</title>
        <style>body{font-family:-apple-system,sans-serif;max-width:600px;margin:40px auto;padding:20px;background:#1a1a2e;color:#e0e0e0}
        h1{color:#00d4ff}input[type=file]{padding:10px;background:#16213e;border:1px solid #0f3460;border-radius:8px;color:#e0e0e0;width:100%}
        button{background:#00d4ff;color:#000;border:none;padding:12px 24px;border-radius:8px;font-size:16px;cursor:pointer;margin-top:10px;width:100%}
        button:hover{background:#00b8d4}.info{color:#888;font-size:12px;margin-top:20px}</style></head>
        <body><h1>GameHub File Upload</h1>
        <p>Select game files (.exe, .iso, .rar, .zip) to upload:</p>
        <form action="/upload" method="post" enctype="multipart/form-data">
        <input type="file" name="file" multiple><br><button type="submit">Upload</button></form>
        <p class="info">Files will be saved to the app's Documents directory.</p></body></html>
        """
        var response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)"
        response.withCString { ptr in
            _ = send(clientFD, ptr, strlen(ptr), 0)
        }
    }

    private func handleUpload(clientFD: Int32, request: String, buffer: [UInt8], bytesRead: Int) {
        var fullData = Data(buffer.prefix(bytesRead))

        if let range = request.range(of: "\r\n\r\n") {
            let headerEnd = request.distance(from: request.startIndex, to: range.upperBound)
            if headerEnd < bytesRead {
                var remaining = Data()
                while true {
                    var chunk = [UInt8](repeating: 0, count: 65536)
                    let n = recv(clientFD, &chunk, chunk.count, 0)
                    if n <= 0 { break }
                    remaining.append(contentsOf: chunk.prefix(n))
                }
                fullData.append(remaining)
            }
        }

        if let boundaryStart = request.range(of: "boundary="),
           let contentTypeLine = request.components(separatedBy: "\r\n").first(where: { $0.lowercased().hasPrefix("content-type:") }) {
            let boundary = String(contentTypeLine[boundaryStart.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)

            let boundaryData = ("--" + boundary).data(using: .utf8) ?? Data()
            let endBoundaryData = ("--" + boundary + "--").data(using: .utf8) ?? Data()

            var offset = 0
            while offset < fullData.count {
                guard let range = fullData.range(of: boundaryData, options: [], in: (fullData.startIndex + offset)..<fullData.endIndex) else { break }
                offset = fullData.distance(from: fullData.startIndex, to: range.upperBound)

                if let endRange = fullData.range(of: endBoundaryData, options: [], in: (fullData.startIndex + offset)..<fullData.endIndex) {
                    let partData = fullData[(fullData.startIndex + offset)..<endRange.lowerBound]
                    if let filename = extractFilename(from: partData) {
                        let fileData = extractFileData(from: partData)
                        let savePath = (directory as NSString).appendingPathComponent(filename)
                        try? fileData.write(to: URL(fileURLWithPath: savePath))
                        print("[HTTPServer] Saved: \(filename) (\(fileData.count) bytes)")
                        onUpload?(filename)
                    }
                    offset = fullData.distance(from: fullData.startIndex, to: endRange.upperBound)
                } else {
                    break
                }
            }
        }

        let html = """
        <!DOCTYPE html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <title>Upload Complete</title>
        <style>body{font-family:-apple-system,sans-serif;max-width:400px;margin:40px auto;padding:20px;background:#1a1a2e;color:#e0e0e0;text-align:center}
        h1{color:#4CAF50}</style></head>
        <body><h1>Upload Complete!</h1><p>Files saved to GameHub.</p>
        <a href="/" style="color:#00d4ff">Upload more files</a></body></html>
        """
        var response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)"
        response.withCString { ptr in
            _ = send(clientFD, ptr, strlen(ptr), 0)
        }
    }

    private func extractFilename(from data: Data) -> String? {
        guard let str = String(data: data, encoding: .utf8) else { return nil }
        let lines = str.components(separatedBy: "\r\n")
        for line in lines {
            if line.lowercased().contains("content-disposition") && line.contains("filename=") {
                if let range = line.range(of: "filename=\"") {
                    let start = range.upperBound
                    if let endRange = line[start...].range(of: "\"") {
                        return String(line[start..<endRange.lowerBound])
                    }
                }
            }
        }
        return nil
    }

    private func extractFileData(from data: Data) -> Data {
        guard let str = String(data: data, encoding: .utf8) else { return data }
        if let range = str.range(of: "\r\n\r\n") {
            let offset = data.distance(from: data.startIndex, to: range.upperBound)
            return data[(data.startIndex + offset)...]
        }
        return data
    }

    private func send404(clientFD: Int32) {
        let body = "Not Found"
        var response = "HTTP/1.1 404 Not Found\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        response.withCString { ptr in
            _ = send(clientFD, ptr, strlen(ptr), 0)
        }
    }
}
