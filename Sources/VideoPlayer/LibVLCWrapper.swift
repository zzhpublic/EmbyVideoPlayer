//
//  LibVLCWrapper.swift
//  SideStore
//
//  Created for LibVLC video playback
//

import Foundation
import Combine

// MARK: - LibVLC Types

enum LibVLCError: LocalizedError {
    case initializationFailed
    case mediaLoadFailed(String)
    case playbackFailed(String)
    case notInitialized
    
    var errorDescription: String? {
        switch self {
        case .initializationFailed: return "Failed to initialize LibVLC"
        case .mediaLoadFailed(let msg): return "Failed to load media: \(msg)"
        case .playbackFailed(let msg): return "Playback failed: \(msg)"
        case .notInitialized: return "LibVLC not initialized"
        }
    }
}

struct LibVLCMediaInfo {
    let duration: TimeInterval
    let width: Int
    let height: Int
    let videoTracks: [LibVLCTrack]
    let audioTracks: [LibVLCTrack]
    let subtitleTracks: [LibVLCTrack]
}

struct LibVLCTrack: Identifiable, Hashable {
    let id: Int
    let name: String
    let language: String?
    let codec: String?
    var isSelected: Bool = false
}

struct LibVLCPlaybackState {
    var isPlaying: Bool = false
    var position: Float = 0.0 // 0.0 to 1.0
    var time: TimeInterval = 0
    var duration: TimeInterval = 0
    var rate: Float = 1.0
    var volume: Float = 1.0
    var isMuted: Bool = false
    var videoTrack: Int = -1
    var audioTrack: Int = -1
    var subtitleTrack: Int = -1
    var aspectRatio: String?
    var cropGeometry: String?
}

// MARK: - LibVLC Wrapper Protocol (for testing)

protocol LibVLCPlayerProtocol: AnyObject {
    var playbackState: LibVLCPlaybackState { get }
    var playbackStatePublisher: Published<LibVLCPlaybackState>.Publisher { get }
    var mediaInfo: LibVLCMediaInfo? { get }
    
    func initialize() throws
    func openMedia(url: URL, options: [String]?) throws
    func play()
    func pause()
    func stop()
    func seek(to position: Float) // 0.0 to 1.0
    func seek(to time: TimeInterval)
    func setRate(_ rate: Float)
    func setVolume(_ volume: Float)
    func toggleMute()
    func setVideoTrack(_ trackId: Int)
    func setAudioTrack(_ trackId: Int)
    func setSubtitleTrack(_ trackId: Int)
    func setAspectRatio(_ aspectRatio: String?)
    func setCropGeometry(_ geometry: String?)
    func takeSnapshot() -> Data?
    func addSubtitleTrack(url: URL) throws
    func cleanup()
}

// MARK: - LibVLC Wrapper (Platform-specific implementation)

#if os(iOS) || os(tvOS)
import MobileVLCKit

class LibVLCWrapper: NSObject, LibVLCPlayerProtocol, ObservableObject, VLCMediaPlayerDelegate {
    @Published var playbackState = LibVLCPlaybackState()
    var playbackStatePublisher: Published<LibVLCPlaybackState>.Publisher { $playbackState }
    
    @Published var mediaInfo: LibVLCMediaInfo?
    
    private var mediaPlayer: VLCMediaPlayer?
    private var media: VLCMedia?
    private var isInitialized = false
    
    // VLCMediaPlayerDelegate
    func mediaPlayerStateChanged(_ aNotification: Notification) {
        guard let player = aNotification.object as? VLCMediaPlayer else { return }
        
        DispatchQueue.main.async {
            self.updatePlaybackState(from: player)
        }
    }
    
    func mediaPlayerTimeChanged(_ aNotification: Notification) {
        guard let player = aNotification.object as? VLCMediaPlayer else { return }
        
        DispatchQueue.main.async {
            self.playbackState.time = player.time.intValue / 1000 // Convert to seconds
            if player.media.length.intValue > 0 {
                self.playbackState.position = Float(player.time.intValue) / Float(player.media.length.intValue)
                self.playbackState.duration = TimeInterval(player.media.length.intValue) / 1000
            }
        }
    }
    
    func mediaPlayerSnapshot(_ aNotification: Notification) {
        // Handle snapshot if needed
    }
    
    override init() {
        super.init()
    }
    
    func initialize() throws {
        // MobileVLCKit initializes automatically
        // Just create the media player
        mediaPlayer = VLCMediaPlayer()
        mediaPlayer?.delegate = self
        isInitialized = true
    }
    
    func openMedia(url: URL, options: [String]? = nil) throws {
        guard isInitialized, let player = mediaPlayer else {
            throw LibVLCError.notInitialized
        }
        
        stop()
        
        // Create media from URL
        media = VLCMedia(url: url)
        
        // Add options if provided
        if let options = options {
            for option in options {
                media?.addOption(option)
            }
        }
        
        // Common options for network streaming
        media?.addOption("network-caching=1000")
        media?.addOption("file-caching=1000")
        media?.addOption("live-caching=1000")
        media?.addOption("sout-mux-caching=1000")
        
        player.media = media
        
        // Parse media to get tracks info
        media?.parse { [weak self] success in
            if success {
                self?.updateMediaInfo()
            }
        }
    }
    
    func play() {
        mediaPlayer?.play()
    }
    
    func pause() {
        mediaPlayer?.pause()
    }
    
    func stop() {
        mediaPlayer?.stop()
    }
    
    func seek(to position: Float) {
        mediaPlayer?.position = position
    }
    
    func seek(to time: TimeInterval) {
        mediaPlayer?.time = VLCTime(int: Int32(time * 1000))
    }
    
    func setRate(_ rate: Float) {
        mediaPlayer?.rate = rate
        playbackState.rate = rate
    }
    
    func setVolume(_ volume: Float) {
        mediaPlayer?.audio.volume = Int32(volume * 100)
        playbackState.volume = volume
    }
    
    func toggleMute() {
        guard let player = mediaPlayer else { return }
        player.audio.isMuted = !player.audio.isMuted
        playbackState.isMuted = player.audio.isMuted
    }
    
    func setVideoTrack(_ trackId: Int) {
        mediaPlayer?.currentVideoTrackIndex = Int32(trackId)
        playbackState.videoTrack = trackId
    }
    
    func setAudioTrack(_ trackId: Int) {
        mediaPlayer?.currentAudioTrackIndex = Int32(trackId)
        playbackState.audioTrack = trackId
    }
    
    func setSubtitleTrack(_ trackId: Int) {
        mediaPlayer?.currentVideoSubTitleIndex = Int32(trackId)
        playbackState.subtitleTrack = trackId
    }
    
    func setAspectRatio(_ aspectRatio: String?) {
        if let aspectRatio = aspectRatio {
            mediaPlayer?.videoAspectRatio = aspectRatio
        } else {
            mediaPlayer?.videoAspectRatio = nil
        }
        playbackState.aspectRatio = aspectRatio
    }
    
    func setCropGeometry(_ geometry: String?) {
        if let geometry = geometry {
            mediaPlayer?.videoCropGeometry = geometry
        } else {
            mediaPlayer?.videoCropGeometry = nil
        }
        playbackState.cropGeometry = geometry
    }
    
    func takeSnapshot() -> Data? {
        guard let player = mediaPlayer,
              let image = player.snapshot() else { return nil }
        return image.pngData()
    }
    
    func addSubtitleTrack(url: URL) throws {
        guard let player = mediaPlayer else { throw LibVLCError.notInitialized }
        
        let subtitleTrack = VLCMedia(url: url)
        player.addPlaybackSlave(subtitleTrack, type: .subtitle, enforce: true)
    }
    
    func cleanup() {
        stop()
        mediaPlayer = nil
        media = nil
        isInitialized = false
    }
    
    // MARK: - Private Helpers
    
    private func updatePlaybackState(from player: VLCMediaPlayer) {
        playbackState.isPlaying = player.isPlaying
        
        if player.media.length.intValue > 0 {
            playbackState.duration = TimeInterval(player.media.length.intValue) / 1000
            playbackState.position = Float(player.time.intValue) / Float(player.media.length.intValue)
        }
        playbackState.time = TimeInterval(player.time.intValue) / 1000
        playbackState.rate = player.rate
        playbackState.volume = Float(player.audio.volume) / 100.0
        playbackState.isMuted = player.audio.isMuted
        playbackState.videoTrack = Int(player.currentVideoTrackIndex)
        playbackState.audioTrack = Int(player.currentAudioTrackIndex)
        playbackState.subtitleTrack = Int(player.currentVideoSubTitleIndex)
        playbackState.aspectRatio = player.videoAspectRatio
        playbackState.cropGeometry = player.videoCropGeometry
    }
    
    private func updateMediaInfo() {
        guard let media = media else { return }
        
        var videoTracks: [LibVLCTrack] = []
        var audioTracks: [LibVLCTrack] = []
        var subtitleTracks: [LibVLCTrack] = []
        
        // Video tracks
        for i in 0..<media.tracksInformation.count {
            if let trackInfo = media.tracksInformation[i] as? [String: Any],
               let type = trackInfo["type"] as? String, type == "video",
               let id = trackInfo["id"] as? Int {
                let name = trackInfo["name"] as? String ?? "Track \(id)"
                let language = trackInfo["language"] as? String
                let codec = trackInfo["codec"] as? String
                videoTracks.append(LibVLCTrack(id: id, name: name, language: language, codec: codec))
            }
        }
        
        // Audio tracks
        for i in 0..<media.tracksInformation.count {
            if let trackInfo = media.tracksInformation[i] as? [String: Any],
               let type = trackInfo["type"] as? String, type == "audio",
               let id = trackInfo["id"] as? Int {
                let name = trackInfo["name"] as? String ?? "Track \(id)"
                let language = trackInfo["language"] as? String
                let codec = trackInfo["codec"] as? String
                audioTracks.append(LibVLCTrack(id: id, name: name, language: language, codec: codec))
            }
        }
        
        // Subtitle tracks
        for i in 0..<media.tracksInformation.count {
            if let trackInfo = media.tracksInformation[i] as? [String: Any],
               let type = trackInfo["type"] as? String, type == "text",
               let id = trackInfo["id"] as? Int {
                let name = trackInfo["name"] as? String ?? "Track \(id)"
                let language = trackInfo["language"] as? String
                let codec = trackInfo["codec"] as? String
                subtitleTracks.append(LibVLCTrack(id: id, name: name, language: language, codec: codec))
            }
        }
        
        // Get video dimensions
        var width = 0
        var height = 0
        if let videoTrack = media.tracksInformation.first(where: { 
            ($0 as? [String: Any])?["type"] as? String == "video" 
        }) as? [String: Any] {
            width = videoTrack["width"] as? Int ?? 0
            height = videoTrack["height"] as? Int ?? 0
        }
        
        mediaInfo = LibVLCMediaInfo(
            duration: TimeInterval(media.length.intValue) / 1000,
            width: width,
            height: height,
            videoTracks: videoTracks,
            audioTracks: audioTracks,
            subtitleTracks: subtitleTracks
        )
    }
    
    // MARK: - Drawable (for video output)
    
    var drawable: Any? {
        // Return the UIView or CALayer for video rendering
        // This should be set by the view controller
        return nil
    }
    
    func setDrawable(_ drawable: Any) {
        mediaPlayer?.drawable = drawable
    }
}

#else
// Mock implementation for non-iOS platforms (macOS, etc.)
class LibVLCWrapper: LibVLCPlayerProtocol, ObservableObject {
    @Published var playbackState = LibVLCPlaybackState()
    var playbackStatePublisher: Published<LibVLCPlaybackState>.Publisher { $playbackState }
    
    @Published var mediaInfo: LibVLCMediaInfo?
    private var isInitialized = false
    
    func initialize() throws {
        isInitialized = true
    }
    
    func openMedia(url: URL, options: [String]?) throws {
        guard isInitialized else { throw LibVLCError.notInitialized }
        print("Mock: Opening media \(url)")
    }
    
    func play() { playbackState.isPlaying = true; print("Mock: Play") }
    func pause() { playbackState.isPlaying = false; print("Mock: Pause") }
    func stop() { playbackState.isPlaying = false; playbackState.time = 0; playbackState.position = 0; print("Mock: Stop") }
    func seek(to position: Float) { playbackState.position = position; print("Mock: Seek to \(position)") }
    func seek(to time: TimeInterval) { playbackState.time = time; print("Mock: Seek to \(time)s") }
    func setRate(_ rate: Float) { playbackState.rate = rate; print("Mock: Rate \(rate)") }
    func setVolume(_ volume: Float) { playbackState.volume = volume; print("Mock: Volume \(volume)") }
    func toggleMute() { playbackState.isMuted.toggle(); print("Mock: Mute \(playbackState.isMuted)") }
    func setVideoTrack(_ trackId: Int) { playbackState.videoTrack = trackId; print("Mock: Video track \(trackId)") }
    func setAudioTrack(_ trackId: Int) { playbackState.audioTrack = trackId; print("Mock: Audio track \(trackId)") }
    func setSubtitleTrack(_ trackId: Int) { playbackState.subtitleTrack = trackId; print("Mock: Subtitle track \(trackId)") }
    func setAspectRatio(_ aspectRatio: String?) { playbackState.aspectRatio = aspectRatio; print("Mock: Aspect \(aspectRatio ?? "auto")") }
    func setCropGeometry(_ geometry: String?) { playbackState.cropGeometry = geometry; print("Mock: Crop \(geometry ?? "none")") }
    func takeSnapshot() -> Data? { print("Mock: Snapshot"); return nil }
    func addSubtitleTrack(url: URL) throws { print("Mock: Add subtitle \(url)") }
    func cleanup() { isInitialized = false; print("Mock: Cleanup") }
}
#endif

// MARK: - LibVLC Manager (Singleton for app-wide access)

class LibVLCManager: ObservableObject {
    static let shared = LibVLCManager()
    
    @Published var player: LibVLCWrapper
    @Published var isReady = false
    @Published var error: LibVLCError?
    
    private init() {
        #if os(iOS) || os(tvOS)
        self.player = LibVLCWrapper()
        #else
        self.player = LibVLCWrapper()
        #endif
        
        do {
            try player.initialize()
            isReady = true
        } catch {
            self.error = error as? LibVLCError ?? .initializationFailed
        }
    }
    
    func openAndPlay(url: URL, options: [String]? = nil) {
        do {
            try player.openMedia(url: url, options: options)
            player.play()
        } catch {
            self.error = error as? LibVLCError ?? .mediaLoadFailed(error.localizedDescription)
        }
    }
}