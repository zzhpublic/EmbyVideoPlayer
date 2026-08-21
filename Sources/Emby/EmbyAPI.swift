//
//  EmbyAPI.swift
//  SideStore
//
//  Created for Emby poster flow video player
//

import Foundation
import Combine

// MARK: - Emby Models

struct EmbyServer: Identifiable, Codable, Hashable {
    let id = UUID()
    let name: String
    let address: String
    let accessToken: String?
    let userId: String?
    
    var baseURL: String {
        address.hasPrefix("http") ? address : "http://\(address)"
    }
}

struct EmbyUser: Codable {
    let id: String
    let name: String
    let serverId: String?
}

struct EmbyItem: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let type: String
    let mediaType: String?
    let seriesName: String?
    let parentId: String?
    let path: String?
    let overview: String?
    let productionYear: Int?
    let communityRating: Double?
    let officialRating: String?
    let runTimeTicks: Int64?
    let imageTags: [String: String]?
    let backdropImageTags: [String: String]?
    let genreItems: [String]?
    let people: [EmbyPerson]?
    let studios: [EmbyStudio]?
    let taglines: [String]?
    let premiereDate: String?
    let isFolder: Bool?
    let childCount: Int?
    let locationType: String?
    let mediaStreams: [EmbyMediaStream]?
    let playAccess: String?
    
    var runtime: TimeInterval? {
        guard let ticks = runTimeTicks else { return nil }
        return TimeInterval(ticks) / 10_000_000
    }
    
    var posterURL: String? {
        guard let imageTags = imageTags, let primary = imageTags["Primary"] else { return nil }
        return "\(baseURL)/Items/\(id)/Images/Primary?tag=\(primary)"
    }
    
    var backdropURL: String? {
        guard let backdropImageTags = backdropImageTags, let backdrop = backdropImageTags["Backdrop"] else { return nil }
        return "\(baseURL)/Items/\(id)/Images/Backdrop?tag=\(backdrop)"
    }
    
    // Need baseURL from context
    var baseURL: String = ""
}

struct EmbyPerson: Codable, Hashable {
    let name: String
    let role: String?
    let type: String
    let imageTag: String?
}

struct EmbyStudio: Codable, Hashable {
    let name: String
    let id: String?
}

struct EmbyMediaStream: Codable, Hashable {
    let codec: String
    let type: String // Video, Audio, Subtitle
    let language: String?
    let displayTitle: String?
    let index: Int?
    let isExternal: Bool?
    let path: String?
}

struct EmbyItemsResponse: Codable {
    let items: [EmbyItem]
    let totalRecordCount: Int
    let startIndex: Int
}

struct EmbyPlaybackInfo: Codable {
    let mediaSources: [EmbyMediaSource]
    let item: EmbyItem
}

struct EmbyMediaSource: Codable {
    let `protocol`: String
    let id: String
    let path: String
    let encodings: [EmbyEncoding]?
    let container: String?
    let size: Int64?
    let name: String?
    let runTimeTicks: Int64?
    let bitrate: Int?
    let width: Int?
    let height: Int?
    let videoType: String?
    let video3DFormat: String?
    let isoType: String?
    let videoProfile: String?
    let audioProfile: String?
    let supportsDirectPlay: Bool?
    let supportsDirectStream: Bool?
    let supportsTranscoding: Bool?
    let isRemote: Bool?
}

struct EmbyEncoding: Codable {
    let codec: String
    let type: String
    let bitDepth: Int?
    let channels: Int?
    let sampleRate: Int?
    let isDefault: Bool?
    let displayTitle: String?
}

// MARK: - Emby API Client

class EmbyAPIClient: ObservableObject {
    @Published var servers: [EmbyServer] = []
    @Published var currentServer: EmbyServer?
    @Published var currentUser: EmbyUser?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private var cancellables = Set<AnyCancellable>()
    private let session = URLSession.shared
    
    // MARK: - Server Management
    
    func addServer(_ server: EmbyServer) {
        if !servers.contains(where: { $0.address == server.address }) {
            servers.append(server)
            saveServers()
        }
    }
    
    func removeServer(_ server: EmbyServer) {
        servers.removeAll { $0.id == server.id }
        if currentServer?.id == server.id {
            currentServer = nil
            currentUser = nil
        }
        saveServers()
    }
    
    func setCurrentServer(_ server: EmbyServer) {
        currentServer = server
        loadUser()
    }
    
    private func loadUser() {
        guard let server = currentServer, let token = server.accessToken else { return }
        request("/Users/\(token)", server: server) { (user: EmbyUser?) in
            DispatchQueue.main.async {
                self.currentUser = user
            }
        }
    }
    
    private func saveServers() {
        if let data = try? JSONEncoder().encode(servers) {
            UserDefaults.standard.set(data, forKey: "emby_servers")
        }
    }
    
    func loadServers() {
        if let data = UserDefaults.standard.data(forKey: "emby_servers"),
           let servers = try? JSONDecoder().decode([EmbyServer].self, from: data) {
            self.servers = servers
        }
    }
    
    // MARK: - API Requests
    
    private func request<T: Codable>(_ endpoint: String, server: EmbyServer? = nil, method: String = "GET", body: Data? = nil, completion: @escaping (T?) -> Void) {
        guard let server = server ?? currentServer else {
            completion(nil)
            return
        }
        
        let urlString = "\(server.baseURL)/emby\(endpoint)"
        guard let url = URL(string: urlString) else {
            completion(nil)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let token = server.accessToken {
            request.setValue("MediaBrowser Token=\"\(token)\"", forHTTPHeaderField: "Authorization")
        }
        
        if let body = body {
            request.httpBody = body
        }
        
        session.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Emby API error: \(error)")
                completion(nil)
                return
            }
            
            guard let data = data else {
                completion(nil)
                return
            }
            
            do {
                let result = try JSONDecoder().decode(T.self, from: data)
                completion(result)
            } catch {
                print("Emby API decode error: \(error)")
                completion(nil)
            }
        }.resume()
    }
    
    // MARK: - Library Browsing
    
    func getLibraries(completion: @escaping ([EmbyItem]?) -> Void) {
        guard let userId = currentUser?.id else {
            completion(nil)
            return
        }
        
        request("/Users/\(userId)/Items?IncludeItemTypes=CollectionFolder&Recursive=true&SortBy=SortName", completion: { (response: EmbyItemsResponse?) in
            completion(response?.items)
        })
    }
    
    func getItems(parentId: String, includeItemTypes: String? = nil, sortBy: String = "SortName", limit: Int = 100, completion: @escaping ([EmbyItem]?) -> Void) {
        guard let userId = currentUser?.id else {
            completion(nil)
            return
        }
        
        var query = "/Users/\(userId)/Items?ParentId=\(parentId)&SortBy=\(sortBy)&Limit=\(limit)&ImageTypeLimit=1&EnableImageTypes=Primary,Backdrop,Thumb"
        if let types = includeItemTypes {
            query += "&IncludeItemTypes=\(types)"
        }
        
        request(query, completion: { (response: EmbyItemsResponse?) in
            var items = response?.items ?? []
            if let server = self.currentServer {
                items = items.map { item in
                    var updated = item
                    updated.baseURL = server.baseURL
                    return updated
                }
            }
            completion(items)
        })
    }
    
    func getMovies(libraryId: String, completion: @escaping ([EmbyItem]?) -> Void) {
        getItems(parentId: libraryId, includeItemTypes: "Movie", completion: completion)
    }
    
    func getSeries(libraryId: String, completion: @escaping ([EmbyItem]?) -> Void) {
        getItems(parentId: libraryId, includeItemTypes: "Series", completion: completion)
    }
    
    func getEpisodes(seriesId: String, completion: @escaping ([EmbyItem]?) -> Void) {
        getItems(parentId: seriesId, includeItemTypes: "Episode", sortBy: "ParentIndexNumber,IndexNumber", completion: completion)
    }
    
    func getSeasons(seriesId: String, completion: @escaping ([EmbyItem]?) -> Void) {
        getItems(parentId: seriesId, includeItemTypes: "Season", sortBy: "IndexNumber", completion: completion)
    }
    
    func getMusic(libraryId: String, completion: @escaping ([EmbyItem]?) -> Void) {
        getItems(parentId: libraryId, includeItemTypes: "MusicAlbum,MusicArtist,Audio", completion: completion)
    }
    
    func getPhotos(libraryId: String, completion: @escaping ([EmbyItem]?) -> Void) {
        getItems(parentId: libraryId, includeItemTypes: "Photo,PhotoAlbum", completion: completion)
    }
    
    // MARK: - Playback
    
    func getPlaybackInfo(itemId: String, completion: @escaping (EmbyPlaybackInfo?) -> Void) {
        guard let userId = currentUser?.id else {
            completion(nil)
            return
        }
        
        let endpoint = "/Users/\(userId)/Items/\(itemId)/PlaybackInfo?AutoOpenLiveStream=true&MaxStreamingBitrate=140000000"
        request(endpoint, completion: completion)
    }
    
    func getStreamURL(itemId: String, mediaSourceId: String, completion: @escaping (URL?) -> Void) {
        guard let server = currentServer, let token = server.accessToken else {
            completion(nil)
            return
        }
        
        let urlString = "\(server.baseURL)/emby/Videos/\(itemId)/stream?MediaSourceId=\(mediaSourceId)&api_key=\(token)"
        completion(URL(string: urlString))
    }
    
    func getSubtitleURL(itemId: String, mediaSourceId: String, streamIndex: Int, format: String = "vtt", completion: @escaping (URL?) -> Void) {
        guard let server = currentServer, let token = server.accessToken else {
            completion(nil)
            return
        }
        
        let urlString = "\(server.baseURL)/emby/Videos/\(itemId)/\(streamIndex)/stream?MediaSourceId=\(mediaSourceId)&api_key=\(token)&format=\(format)"
        completion(URL(string: urlString))
    }
    
    // MARK: - Search
    
    func search(query: String, limit: Int = 50, completion: @escaping ([EmbyItem]?) -> Void) {
        guard let userId = currentUser?.id else {
            completion(nil)
            return
        }
        
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let endpoint = "/Users/\(userId)/Items?SearchTerm=\(encodedQuery)&Limit=\(limit)&ImageTypeLimit=1&EnableImageTypes=Primary,Backdrop,Thumb&Recursive=true"
        
        request(endpoint, completion: { (response: EmbyItemsResponse?) in
            var items = response?.items ?? []
            if let server = self.currentServer {
                items = items.map { item in
                    var updated = item
                    updated.baseURL = server.baseURL
                    return updated
                }
            }
            completion(items)
        })
    }
    
    // MARK: - Authentication
    
    func authenticate(server: EmbyServer, username: String, password: String, completion: @escaping (Bool, String?) -> Void) {
        let urlString = "\(server.baseURL)/emby/Users/AuthenticateByName"
        guard let url = URL(string: urlString) else {
            completion(false, "Invalid URL")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["Username": username, "Pw": password]
        request.httpBody = try? JSONEncoder().encode(body)
        
        session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(false, error.localizedDescription)
                return
            }
            
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let accessToken = json["AccessToken"] as? String,
                  let user = json["User"] as? [String: Any],
                  let userId = user["Id"] as? String else {
                completion(false, "Authentication failed")
                return
            }
            
            var authenticatedServer = server
            // Note: EmbyServer is a struct, so we can't mutate it directly
            // In practice, you'd update the stored server with the token
            let authenticatedServerWithToken = EmbyServer(
                name: server.name,
                address: server.address,
                accessToken: accessToken,
                userId: userId
            )
            
            DispatchQueue.main.async {
                if let index = self.servers.firstIndex(where: { $0.id == server.id }) {
                    self.servers[index] = authenticatedServerWithToken
                    self.saveServers()
                }
                self.setCurrentServer(authenticatedServerWithToken)
                completion(true, nil)
            }
        }.resume()
    }
    
    // MARK: - Device Discovery
    
    func discoverServers(completion: @escaping ([EmbyServer]) -> Void) {
        // Emby server discovery via SSDP/UPnP
        // This is a simplified version - real implementation would use SSDP
        var discovered: [EmbyServer] = []
        
        // Try common local addresses
        let commonAddresses = [
            "http://localhost:8096",
            "http://192.168.1.100:8096",
            "http://192.168.1.101:8096",
            "http://10.0.0.100:8096"
        ]
        
        let group = DispatchGroup()
        
        for address in commonAddresses {
            group.enter()
            checkServer(address: address) { server in
                if let server = server {
                    discovered.append(server)
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            completion(discovered)
        }
    }
    
    private func checkServer(address: String, completion: @escaping (EmbyServer?) -> Void) {
        let urlString = "\(address)/emby/System/Info/Public"
        guard let url = URL(string: urlString) else {
            completion(nil)
            return
        }
        
        session.dataTask(with: url) { data, response, error in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let name = json["ServerName"] as? String,
                  let id = json["Id"] as? String else {
                completion(nil)
                return
            }
            
            let server = EmbyServer(name: name, address: address, accessToken: nil, userId: nil)
            completion(server)
        }.resume()
    }
}

// MARK: - Async/Await Extensions

extension EmbyAPIClient {
    func getLibraries() async -> [EmbyItem]? {
        await withCheckedContinuation { continuation in
            getLibraries { continuation.resume(returning: $0) }
        }
    }
    
    func getItems(parentId: String, includeItemTypes: String? = nil, sortBy: String = "SortName", limit: Int = 100) async -> [EmbyItem]? {
        await withCheckedContinuation { continuation in
            getItems(parentId: parentId, includeItemTypes: includeItemTypes, sortBy: sortBy, limit: limit, completion: { continuation.resume(returning: $0) })
        }
    }
    
    func getMovies(libraryId: String, sortBy: String = "SortName", limit: Int = 100) async -> [EmbyItem]? {
        await withCheckedContinuation { continuation in
                getMovies(libraryId: libraryId, completion: { continuation.resume(returning: $0) })
        }
    }
    
    func getSeries(libraryId: String, sortBy: String = "SortName", limit: Int = 100) async -> [EmbyItem]? {
        await withCheckedContinuation { continuation in
                getSeries(libraryId: libraryId, completion: { continuation.resume(returning: $0) })
        }
    }
    
    func getEpisodes(seriesId: String, sortBy: String = "SortName", limit: Int = 100) async -> [EmbyItem]? {
        await withCheckedContinuation { continuation in
                getEpisodes(seriesId: seriesId, completion: { continuation.resume(returning: $0) })
        }
    }
    
    func getPlaybackInfo(itemId: String) async -> EmbyPlaybackInfo? {
        await withCheckedContinuation { continuation in
            getPlaybackInfo(itemId: itemId) { continuation.resume(returning: $0) }
        }
    }
    
    func search(query: String, limit: Int = 50) async -> [EmbyItem]? {
        await withCheckedContinuation { continuation in
                search(query: query, limit: limit) { continuation.resume(returning: $0) }
        }
    }
}