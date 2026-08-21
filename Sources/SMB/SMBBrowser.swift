//
//  SMBBrowser.swift
//  SideStore
//
//  Created for SMB network video browser
//

import Foundation
import Network
import Combine

// MARK: - SMB Models

struct SMBServer: Identifiable, Hashable, Codable {
    let id = UUID()
    let name: String
    let host: String
    let port: Int
    let workgroup: String?
    var username: String?
    var password: String?
    
    var displayName: String {
        if let workgroup = workgroup, !workgroup.isEmpty {
            return "\(name) (\(workgroup))"
        }
        return name
    }
    
    var connectionString: String {
        "smb://\(host):\(port)"
    }
}

struct SMBShare: Identifiable, Hashable, Codable {
    let id = UUID()
    let name: String
    let path: String
    let server: SMBServer
    var isAccessible: Bool = false
}

struct SMBFile: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let path: String
    let isDirectory: Bool
    let size: Int64
    let modificationDate: Date
    let share: SMBShare
    
    var isVideoFile: Bool {
        let videoExtensions = ["mp4", "mkv", "avi", "mov", "m4v", "mpg", "mpeg", "ts", "m2ts", "webm", "flv", "wmv", "ogv", "3gp"]
        let ext = (name as NSString).pathExtension.lowercased()
        return videoExtensions.contains(ext)
    }
    
    var isPosterFile: Bool {
        let posterExtensions = ["jpg", "jpeg", "png", "bmp", "tiff", "webp"]
        let ext = (name as NSString).pathExtension.lowercased()
        return posterExtensions.contains(ext)
    }
    
    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
}

// MARK: - SMB Browser Error

enum SMBBrowserError: LocalizedError {
    case connectionFailed(String)
    case authenticationFailed
    case shareNotFound
    case pathNotFound
    case permissionDenied
    case timeout
    case unknown(Error)
    
    var errorDescription: String? {
        switch self {
        case .connectionFailed(let msg): return "Connection failed: \(msg)"
        case .authenticationFailed: return "Authentication failed"
        case .shareNotFound: return "Share not found"
        case .pathNotFound: return "Path not found"
        case .permissionDenied: return "Permission denied"
        case .timeout: return "Connection timeout"
        case .unknown(let error): return error.localizedDescription
        }
    }
}

// MARK: - SMB Browser

class SMBBrowser: ObservableObject {
    @Published var discoveredServers: [SMBServer] = []
    @Published var shares: [SMBShare] = []
    @Published var currentPath: String = ""
    @Published var files: [SMBFile] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var currentServer: SMBServer?
    @Published var currentShare: SMBShare?
    
    private var browser: NWBrowser?
    private let queue = DispatchQueue(label: "smb.browser.queue")
    private var connection: NWConnection?
    
    // Bonjour service type for SMB
    private let smbServiceType = "_smb._tcp."
    
    init() {
        loadSavedServers()
    }
    
    // MARK: - Server Discovery
    
    func startDiscovery() {
        stopDiscovery()
        
        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        
        let browser = NWBrowser(for: .bonjour(type: smbServiceType, domain: nil), using: parameters)
        browser.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    print("SMB Browser ready")
                case .failed(let error):
                    print("SMB Browser failed: \(error)")
                    self?.errorMessage = "Discovery failed: \(error.localizedDescription)"
                case .cancelled:
                    print("SMB Browser cancelled")
                default:
                    break
                }
            }
        }
        
        browser.browseResultsChangedHandler = { [weak self] results, changes in
            self?.processBrowseResults(results)
        }
        
        browser.start(queue: queue)
        self.browser = browser
    }
    
    func stopDiscovery() {
        browser?.cancel()
        browser = nil
    }
    
    private func processBrowseResults(_ results: Set<NWBrowser.Result>) {
        var servers: [SMBServer] = []
        
        for result in results {
            switch result.endpoint {
            case .service(name: let name, type: _, domain: _, interface: _):
                // Resolve the service to get IP and port
                resolveService(name: name) { server in
                    if let server = server {
                        DispatchQueue.main.async {
                            if !self.discoveredServers.contains(where: { $0.host == server.host && $0.port == server.port }) {
                                self.discoveredServers.append(server)
                            }
                        }
                    }
                }
            default:
                break
            }
        }
    }
    
    private func resolveService(name: String, completion: @escaping (SMBServer?) -> Void) {
        let parameters = NWParameters()
        let connection = NWConnection(to: .service(name: name, type: smbServiceType, domain: "local", interface: nil), using: parameters)
        
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                if let endpoint = connection.currentPath?.remoteEndpoint {
                    switch endpoint {
                    case .hostPort(host: let host, port: let port):
                        let server = SMBServer(
                            name: name,
                            host: "\(host)",
                                                port: Int(port.rawValue),
                            workgroup: nil,
                            username: nil,
                            password: nil
                        )
                        completion(server)
                    default:
                        completion(nil)
                    }
                } else {
                    completion(nil)
                }
                connection.cancel()
            case .failed, .cancelled:
                completion(nil)
            default:
                break
            }
        }
        
        connection.start(queue: queue)
    }
    
    // MARK: - Manual Server Connection
    
    func connectToServer(_ server: SMBServer, completion: @escaping (Result<[SMBShare], SMBBrowserError>) -> Void) {
        isLoading = true
        errorMessage = nil
        currentServer = server
        
        // For iOS, we use URLSession with SMB URLs via the FileProvider extension
        // or we can use a library like libsmbclient wrapper
        // This is a simplified implementation using NSFileProvider
        
        // In a real implementation, you would:
        // 1. Use libsmbclient via a Swift wrapper
        // 2. Or use the SMB3 protocol implementation
        // 3. Or use NSFileProvider for SMB shares
        
        // For now, simulate with a mock implementation
        queue.asyncAfter(deadline: .now() + 1) {
            // Mock shares for demonstration
            let shares = [
                SMBShare(name: "Videos", path: "/Videos", server: server),
                SMBShare(name: "Movies", path: "/Movies", server: server),
                SMBShare(name: "TV Shows", path: "/TV Shows", server: server),
                SMBShare(name: "Music", path: "/Music", server: server),
                SMBShare(name: "Photos", path: "/Photos", server: server)
            ]
            
            DispatchQueue.main.async {
                self.isLoading = false
                self.shares = shares
                completion(.success(shares))
            }
        }
    }
    
    // MARK: - Share Browsing
    
    func browseShare(_ share: SMBShare, path: String = "", completion: @escaping (Result<[SMBFile], SMBBrowserError>) -> Void) {
        isLoading = true
        errorMessage = nil
        currentShare = share
        currentPath = path
        
        // In a real implementation, this would use SMB protocol to list directory contents
        // For now, simulate with mock data
        
        queue.asyncAfter(deadline: .now() + 0.5) {
            let mockFiles = self.generateMockFiles(for: share, path: path)
            
            DispatchQueue.main.async {
                self.isLoading = false
                self.files = mockFiles
                completion(.success(mockFiles))
            }
        }
    }
    
    private func generateMockFiles(for share: SMBShare, path: String) -> [SMBFile] {
        let fullPath = share.path + (path.isEmpty ? "" : "/\(path)")
        
        // Mock data - in reality this comes from SMB protocol
        if path.isEmpty {
            return [
                SMBFile(name: "Movies", path: "\(fullPath)/Movies", isDirectory: true, size: 0, modificationDate: Date(), share: share),
                SMBFile(name: "TV Shows", path: "\(fullPath)/TV Shows", isDirectory: true, size: 0, modificationDate: Date(), share: share),
                SMBFile(name: "Videos", path: "\(fullPath)/Videos", isDirectory: true, size: 0, modificationDate: Date(), share: share),
                SMBFile(name: "Sample.mp4", path: "\(fullPath)/Sample.mp4", isDirectory: false, size: 1_234_567_890, modificationDate: Date(), share: share),
                SMBFile(name: "demo.mkv", path: "\(fullPath)/demo.mkv", isDirectory: false, size: 2_345_678_901, modificationDate: Date(), share: share)
            ]
        } else if path.contains("Movies") {
            return [
                SMBFile(name: "Inception.mp4", path: "\(fullPath)/Inception.mp4", isDirectory: false, size: 8_500_000_000, modificationDate: Date(), share: share),
                SMBFile(name: "The Matrix.mkv", path: "\(fullPath)/The Matrix.mkv", isDirectory: false, size: 12_300_000_000, modificationDate: Date(), share: share),
                SMBFile(name: "Interstellar.mov", path: "\(fullPath)/Interstellar.mov", isDirectory: false, size: 15_600_000_000, modificationDate: Date(), share: share)
            ]
        } else if path.contains("TV Shows") {
            return [
                SMBFile(name: "Breaking Bad", path: "\(fullPath)/Breaking Bad", isDirectory: true, size: 0, modificationDate: Date(), share: share),
                SMBFile(name: "Game of Thrones", path: "\(fullPath)/Game of Thrones", isDirectory: true, size: 0, modificationDate: Date(), share: share),
                SMBFile(name: "Stranger Things", path: "\(fullPath)/Stranger Things", isDirectory: true, size: 0, modificationDate: Date(), share: share)
            ]
        }
        
        return []
    }
    
    // MARK: - File Operations
    
    func getFileURL(_ file: SMBFile) -> URL? {
        // In a real implementation, this would return an SMB URL that can be played
        // For LibVLC, we can use smb:// URLs directly if credentials are embedded
        guard let server = currentServer, let share = currentShare else { return nil }
        
        var urlString = "smb://"
        if let username = server.username, let password = server.password {
            urlString += "\(username):\(password)@"
        }
        urlString += "\(server.host):\(server.port)\(file.path)"
        
        return URL(string: urlString)
    }
    
    func getStreamURL(_ file: SMBFile) -> URL? {
        // For streaming, we might want to use HTTP range requests via a local proxy
        // or use the SMB URL directly with LibVLC
        return getFileURL(file)
    }
    
    // MARK: - Saved Servers
    
    func saveServer(_ server: SMBServer) {
        if !discoveredServers.contains(where: { $0.host == server.host && $0.port == server.port }) {
            discoveredServers.append(server)
        }
        saveServers()
    }
    
    func removeServer(_ server: SMBServer) {
        discoveredServers.removeAll { $0.id == server.id }
        saveServers()
    }
    
    private func saveServers() {
        if let data = try? JSONEncoder().encode(discoveredServers) {
            UserDefaults.standard.set(data, forKey: "smb_servers")
        }
    }
    
    private func loadSavedServers() {
        if let data = UserDefaults.standard.data(forKey: "smb_servers"),
           let servers = try? JSONDecoder().decode([SMBServer].self, from: data) {
            discoveredServers = servers
        }
    }
    
    // MARK: - Authentication
    
    func authenticate(server: SMBServer, username: String, password: String, completion: @escaping (Bool) -> Void) {
        // Test authentication by trying to list shares
        var authenticatedServer = server
        authenticatedServer.username = username
        authenticatedServer.password = password
        
        connectToServer(authenticatedServer) { [weak self] result in
            switch result {
            case .success:
                self?.saveServer(authenticatedServer)
                completion(true)
            case .failure:
                completion(false)
            }
        }
    }
}

// MARK: - SMB File Provider (iOS 11+)

/*
 For production use, you would implement NSFileProviderExtension to provide
 native SMB support in the Files app and for other apps. This requires:
 
 1. Add File Provider Extension target to your Xcode project
 2. Implement NSFileProviderEnumerator, NSFileProviderReplicatedExtension
 3. Handle SMB protocol communication in the extension
 
 This is complex and requires App Groups and proper entitlements.
 For a simpler approach, use the SMBBrowser class above with LibVLC directly.
 */

// MARK: - Async/Await Extensions

extension SMBBrowser {
    func connectToServer(_ server: SMBServer) async throws -> [SMBShare] {
        try await withCheckedThrowingContinuation { continuation in
            connectToServer(server) { result in
                continuation.resume(with: result)
            }
        }
    }
    
    func browseShare(_ share: SMBShare, path: String = "") async throws -> [SMBFile] {
        try await withCheckedThrowingContinuation { continuation in
            browseShare(share, path: path) { result in
                continuation.resume(with: result)
            }
        }
    }
    
    func authenticate(server: SMBServer, username: String, password: String) async -> Bool {
        await withCheckedContinuation { continuation in
            authenticate(server: server, username: username, password: password) { continuation.resume(returning: $0) }
        }
    }
}