//
//  LibVLCWrapper.swift
//  EmbyVideoPlayer
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
            if let media = player.media {
                let currentTime = player.time.intValue
                let totalTime = media.length.intValue
                
                self.playbackState.time = TimeInterval(currentTime) / 1000
                if totalTime > 0 {
                    self.playbackState.position = Float(currentTime) / Float(totalTime)
                    self.playbackState.duration = TimeInterval(totalTime) / 1000
                }
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
                media?.parse()
                updateMediaInfo()
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
        guard let player = mediaPlayer, let media = player.media else { return }
        let totalTime = media.length.intValue
        let targetTime = Int32(Float(totalTime) * max(0, min(1, position)))
        player.time = VLCTime(int: targetTime)
    }
    
    func seek(to time: TimeInterval) {
        guard let player = mediaPlayer else { return }
        player.time = VLCTime(int: Int32(time * 1000))
    }
    
    func setRate(_ rate: Float) {
        mediaPlayer?.rate = rate
        playbackState.rate = rate
    }
    
    func setVolume(_ volume: Float) {
        if let audio = mediaPlayer?.audio {
            audio.volume = Int32(volume * 100)
            playbackState.volume = volume
        }
    }
    
    func toggleMute() {
        guard let audio = mediaPlayer?.audio else { return }
        audio.isMuted = !audio.isMuted
        playbackState.isMuted = audio.isMuted
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
            // Note: videoAspectRatio property type varies in MobileVLCKit versions
            // For now, just update playback state
            playbackState.aspectRatio = aspectRatio
            // TODO: Implement actual aspect ratio setting when API is confirmed
        }
    
        func setCropGeometry(_ geometry: String?) {
            // Note: videoCropGeometry property type varies in MobileVLCKit versions
            // For now, just update playback state
            playbackState.cropGeometry = geometry
            // TODO: Implement actual crop geometry setting when API is confirmed
        }
    
    func takeSnapshot() -> Data? {
        guard let player = mediaPlayer else { return nil }
        // MobileVLCKit doesn't have a direct snapshot() method on VLCMediaPlayer
        // Would need to use drawable/snapshot APIs
        return nil
    }
    
    func addSubtitleTrack(url: URL) throws {
        guard let player = mediaPlayer else { throw LibVLCError.notInitialized }
        
        let subtitleTrack = VLCMedia(url: url)
        // Note: addPlaybackSlave is not available in MobileVLCKit
        // Subtitle handling would need different approach
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
        
        if let media = player.media {
            let totalTime = media.length.intValue
            if totalTime > 0 {
                playbackState.duration = TimeInterval(totalTime) / 1000
                playbackState.position = Float(player.time.intValue) / Float(totalTime)
            }
        }
        playbackState.time = TimeInterval(player.time.intValue) / 1000
        playbackState.rate = player.rate
        
        if let audio = player.audio {
            playbackState.volume = Float(audio.volume) / 100.0
            playbackState.isMuted = audio.isMuted
        }
        
        playbackState.videoTrack = Int(player.currentVideoTrackIndex)
        playbackState.audioTrack = Int(player.currentAudioTrackIndex)
        playbackState.subtitleTrack = Int(player.currentVideoSubTitleIndex)
                if let aspectRatioPtr = player.videoAspectRatio {
                    let aspectRatio = String(cString: aspectRatioPtr)
                    if !aspectRatio.isEmpty {
                        playbackState.aspectRatio = aspectRatio
                    }
                }
                if let cropGeometryPtr = player.videoCropGeometry {
                    let cropGeometry = String(cString: cropGeometryPtr)
                    if !cropGeometry.isEmpty {
                        playbackState.cropGeometry = cropGeometry
                    }
                }
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
    
    func setDrawable(_ drawable: Any?) {
        mediaPlayer?.drawable = drawable
    }
}

#elseif os(macOS)
// macOS implementation would use VLCKit
// For now, provide a stub
class LibVLCWrapper: LibVLCPlayerProtocol, ObservableObject {
    @Published var playbackState = LibVLCPlaybackState()
    var playbackStatePublisher: Published<LibVLCPlaybackState>.Publisher { $playbackState }
    
    @Published var mediaInfo: LibVLCMediaInfo?
    
    func initialize() throws {
        throw LibVLCError.initializationFailed
    }
    
    func openMedia(url: URL, options: [String]?) throws {
        throw LibVLCError.notInitialized
    }
    
    func play() {}
    func pause() {}
    func stop() {}
    func seek(to position: Float) {}
    func seek(to time: TimeInterval) {}
    func setRate(_ rate: Float) {}
    func setVolume(_ volume: Float) {}
    func toggleMute() {}
    func setVideoTrack(_ trackId: Int) {}
    func setAudioTrack(_ trackId: Int) {}
    func setSubtitleTrack(_ trackId: Int) {}
    func setAspectRatio(_ aspectRatio: String?) {}
    func setCropGeometry(_ geometry: String?) {}
    func takeSnapshot() -> Data? { nil }
    func addSubtitleTrack(url: URL) throws {}
    func cleanup() {}
    
    var drawable: Any? { nil }
}

#else
// Fallback for other platforms
class LibVLCWrapper: LibVLCPlayerProtocol, ObservableObject {
    @Published var playbackState = LibVLCPlaybackState()
    var playbackStatePublisher: Published<LibVLCPlaybackState>.Publisher { $playbackState }
    
    @Published var mediaInfo: LibVLCMediaInfo?
    
    func initialize() throws {
        throw LibVLCError.initializationFailed
    }
    
    func openMedia(url: URL, options: [String]?) throws {
        throw LibVLCError.notInitialized
    }
    
    func play() {}
    func pause() {}
    func stop() {}
    func seek(to position: Float) {}
    func seek(to time: TimeInterval) {}
    func setRate(_ rate: Float) {}
    func setVolume(_ volume: Float) {}
    func toggleMute() {}
    func setVideoTrack(_ trackId: Int) {}
    func setAudioTrack(_ trackId: Int) {}
    func setSubtitleTrack(_ trackId: Int) {}
    func setAspectRatio(_ aspectRatio: String?) {}
    func setCropGeometry(_ geometry: String?) {}
    func takeSnapshot() -> Data? { nil }
    func addSubtitleTrack(url: URL) throws {}
    func cleanup() {}
    
    var drawable: Any? { nil }
}
#endif