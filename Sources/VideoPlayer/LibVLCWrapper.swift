//
//  LibVLCWrapper.swift
//  EmbyVideoPlayer
//
//  Created for LibVLC video playback
//

import Foundation
import Combine

// MARK: - LibVLC Types

public enum LibVLCError: LocalizedError {
    case initializationFailed
    case mediaLoadFailed(String)
    case playbackFailed(String)
    case notInitialized
    
    public var errorDescription: String? {
        switch self {
        case .initializationFailed: return "Failed to initialize LibVLC"
        case .mediaLoadFailed(let msg): return "Failed to load media: \(msg)"
        case .playbackFailed(let msg): return "Playback failed: \(msg)"
        case .notInitialized: return "LibVLC not initialized"
        }
    }
}

public struct LibVLCMediaInfo {
    public let duration: TimeInterval
    public let width: Int
    public let height: Int
    public let videoTracks: [LibVLCTrack]
    public let audioTracks: [LibVLCTrack]
    public let subtitleTracks: [LibVLCTrack]
}

public struct LibVLCTrack: Identifiable, Hashable {
    public let id: Int
    public let name: String
    public let language: String?
    public let codec: String?
    public var isSelected: Bool = false
}

public struct LibVLCPlaybackState {
    public var isPlaying: Bool = false
    public var position: Float = 0.0 // 0.0 to 1.0
    public var time: TimeInterval = 0
    public var duration: TimeInterval = 0
    public var rate: Float = 1.0
    public var volume: Float = 1.0
    public var isMuted: Bool = false
    public var videoTrack: Int = -1
    public var audioTrack: Int = -1
    public var subtitleTrack: Int = -1
    public var aspectRatio: String?
    public var cropGeometry: String?
}

// MARK: - LibVLC Wrapper Protocol (for testing)

public protocol LibVLCPlayerProtocol: AnyObject {
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

public class LibVLCWrapper: NSObject, LibVLCPlayerProtocol, ObservableObject, VLCMediaPlayerDelegate {
    @Published public var playbackState = LibVLCPlaybackState()
    public var playbackStatePublisher: Published<LibVLCPlaybackState>.Publisher { $playbackState }
    
    @Published public var mediaInfo: LibVLCMediaInfo?
    
    private var mediaPlayer: VLCMediaPlayer?
    private var media: VLCMedia?
    private var isInitialized = false
    
    public static let shared = LibVLCWrapper()
    
    public override init() {
        super.init()
    }
    
    public func initialize() throws {
        // MobileVLCKit initializes automatically
        // Just create the media player
        mediaPlayer = VLCMediaPlayer()
        mediaPlayer?.delegate = self
        isInitialized = true
    }
    
    public func openMedia(url: URL, options: [String]? = nil) throws {
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
    
    public func play() {
        mediaPlayer?.play()
    }
    
    public func pause() {
        mediaPlayer?.pause()
    }
    
    public func stop() {
        mediaPlayer?.stop()
    }
    
    public func seek(to position: Float) {
        guard let player = mediaPlayer, let media = player.media else { return }
        let totalTime = media.length.intValue
        let targetTime = Int32(Float(totalTime) * max(0, min(1, position)))
        player.time = VLCTime(int: targetTime)
    }
    
    public func seek(to time: TimeInterval) {
        guard let player = mediaPlayer else { return }
        player.time = VLCTime(int: Int32(time * 1000))
    }
    
    public func setRate(_ rate: Float) {
        mediaPlayer?.rate = rate
        playbackState.rate = rate
    }
    
    public func setVolume(_ volume: Float) {
        if let audio = mediaPlayer?.audio {
            audio.volume = Int32(volume * 100)
            playbackState.volume = volume
        }
    }
    
    public func toggleMute() {
        guard let audio = mediaPlayer?.audio else { return }
        audio.isMuted = !audio.isMuted
        playbackState.isMuted = audio.isMuted
    }
    
    public func setVideoTrack(_ trackId: Int) {
        mediaPlayer?.currentVideoTrackIndex = Int32(trackId)
        playbackState.videoTrack = trackId
    }
    
    public func setAudioTrack(_ trackId: Int) {
        mediaPlayer?.currentAudioTrackIndex = Int32(trackId)
        playbackState.audioTrack = trackId
    }
    
    public func setSubtitleTrack(_ trackId: Int) {
        mediaPlayer?.currentVideoSubTitleIndex = Int32(trackId)
        playbackState.subtitleTrack = trackId
    }
    
    public func setAspectRatio(_ aspectRatio: String?) {
        // Note: videoAspectRatio property type varies in MobileVLCKit versions
        // For now, just update playback state
        playbackState.aspectRatio = aspectRatio
        // TODO: Implement actual aspect ratio setting when API is confirmed
    }
    
    public func setCropGeometry(_ geometry: String?) {
        // Note: videoCropGeometry property type varies in MobileVLCKit versions
        // For now, just update playback state
        playbackState.cropGeometry = geometry
        // TODO: Implement actual crop geometry setting when API is confirmed
    }
    
    public func takeSnapshot() -> Data? {
        guard let player = mediaPlayer else { return nil }
        // MobileVLCKit doesn't have a direct snapshot() method on VLCMediaPlayer
        // Would need to use drawable/snapshot APIs
        return nil
    }
    
    public func addSubtitleTrack(url: URL) throws {
        guard let player = mediaPlayer else { throw LibVLCError.notInitialized }
        
        let subtitleTrack = VLCMedia(url: url)
        // Note: addPlaybackSlave is not available in MobileVLCKit
        // Subtitle handling would need different approach
    }
    
    public func cleanup() {
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
import VLCKit

public class LibVLCWrapper: NSObject, LibVLCPlayerProtocol, ObservableObject, VLCMediaPlayerDelegate {
    @Published public var playbackState = LibVLCPlaybackState()
    public var playbackStatePublisher: Published<LibVLCPlaybackState>.Publisher { $playbackState }
    
    @Published public var mediaInfo: LibVLCMediaInfo?
    
    private var mediaPlayer: VLCMediaPlayer?
    private var media: VLCMedia?
    private var isInitialized = false
    
    public static let shared = LibVLCWrapper()
    
    public override init() {
        super.init()
    }
    
    public func initialize() throws {
        // VLCKit initializes automatically
        mediaPlayer = VLCMediaPlayer()
        mediaPlayer?.delegate = self
        isInitialized = true
    }
    
    public func openMedia(url: URL, options: [String]? = nil) throws {
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
    
    public func play() {
        mediaPlayer?.play()
    }
    
    public func pause() {
        mediaPlayer?.pause()
    }
    
    public func stop() {
        mediaPlayer?.stop()
    }
    
    public func seek(to position: Float) {
        guard let player = mediaPlayer, let media = player.media else { return }
        let totalTime = media.length.intValue
        let targetTime = Int32(Float(totalTime) * max(0, min(1, position)))
        player.time = VLCTime(int: targetTime)
    }
    
    public func seek(to time: TimeInterval) {
        guard let player = mediaPlayer else { return }
        player.time = VLCTime(int: Int32(time * 1000))
    }
    
    public func setRate(_ rate: Float) {
        mediaPlayer?.rate = rate
        playbackState.rate = rate
    }
    
    public func setVolume(_ volume: Float) {
        if let audio = mediaPlayer?.audio {
            audio.volume = Int32(volume * 100)
            playbackState.volume = volume
        }
    }
    
    public func toggleMute() {
        guard let audio = mediaPlayer?.audio else { return }
        audio.isMuted = !audio.isMuted
        playbackState.isMuted = audio.isMuted
    }
    
    public func setVideoTrack(_ trackId: Int) {
        mediaPlayer?.currentVideoTrackIndex = Int32(trackId)
        playbackState.videoTrack = trackId
    }
    
    public func setAudioTrack(_ trackId: Int) {
        mediaPlayer?.currentAudioTrackIndex = Int32(trackId)
        playbackState.audioTrack = trackId
    }
    
    public func setSubtitleTrack(_ trackId: Int) {
        mediaPlayer?.currentVideoSubTitleIndex = Int32(trackId)
        playbackState.subtitleTrack = trackId
    }
    
    public func setAspectRatio(_ aspectRatio: String?) {
        playbackState.aspectRatio = aspectRatio
    }
    
    public func setCropGeometry(_ geometry: String?) {
        playbackState.cropGeometry = geometry
    }
    
    public func takeSnapshot() -> Data? {
        guard let player = mediaPlayer else { return nil }
        // VLCKit snapshot implementation
        return nil
    }
    
    public func addSubtitleTrack(url: URL) throws {
        guard let player = mediaPlayer else { throw LibVLCError.notInitialized }
        
        let subtitleTrack = VLCMedia(url: url)
        player.addPlaybackSlave(subtitleTrack, type: .subtitle)
    }
    
    public func cleanup() {
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
        return nil
    }
    
    func setDrawable(_ drawable: Any?) {
        mediaPlayer?.drawable = drawable
    }
}

#elseif os(Windows)
import CLibVLC

public class LibVLCWrapper: LibVLCPlayerProtocol, ObservableObject {
    @Published public var playbackState = LibVLCPlaybackState()
    public var playbackStatePublisher: Published<LibVLCPlaybackState>.Publisher { $playbackState }
    
    @Published public var mediaInfo: LibVLCMediaInfo?
    
    private var libvlcInstance: OpaquePointer?
    private var mediaPlayer: OpaquePointer?
    private var media: OpaquePointer?
    private var isInitialized = false
    
    public static let shared = LibVLCWrapper()
    
    public override init() {
        super.init()
    }
    
    public func initialize() throws {
        // Initialize libvlc
        let args = [
            "--no-video-title-show",
            "--network-caching=1000",
            "--file-caching=1000",
            "--live-caching=1000"
        ]
        
        var cArgs = args.map { strdup($0) }
        defer { cArgs.forEach { free($0) } }
        
        libvlcInstance = libvlc_new(Int32(args.count), &cArgs)
        guard libvlcInstance != nil else {
            throw LibVLCError.initializationFailed
        }
        
        mediaPlayer = libvlc_media_player_new(libvlcInstance)
        guard mediaPlayer != nil else {
            libvlc_release(libvlcInstance)
            libvlcInstance = nil
            throw LibVLCError.initializationFailed
        }
        
        isInitialized = true
    }
    
    public func openMedia(url: URL, options: [String]? = nil) throws {
        guard isInitialized, let player = mediaPlayer, let instance = libvlcInstance else {
            throw LibVLCError.notInitialized
        }
        
        stop()
        
        // Create media from URL
        let urlString = url.absoluteString
        media = libvlc_media_new_location(instance, urlString)
        guard media != nil else {
            throw LibVLCError.mediaLoadFailed("Failed to create media from URL")
        }
        
        // Add options if provided
        if let options = options {
            for option in options {
                libvlc_media_add_option(media, option)
            }
        }
        
        // Common options for network streaming
        libvlc_media_add_option(media, "network-caching=1000")
        libvlc_media_add_option(media, "file-caching=1000")
        libvlc_media_add_option(media, "live-caching=1000")
        libvlc_media_add_option(media, "sout-mux-caching=1000")
        
        libvlc_media_player_set_media(player, media)
        
        // Parse media to get tracks info
        libvlc_media_parse(media)
        updateMediaInfo()
    }
    
    public func play() {
        guard let player = mediaPlayer else { return }
        libvlc_media_player_play(player)
    }
    
    public func pause() {
        guard let player = mediaPlayer else { return }
        libvlc_media_player_pause(player)
    }
    
    public func stop() {
        guard let player = mediaPlayer else { return }
        libvlc_media_player_stop(player)
    }
    
    public func seek(to position: Float) {
        guard let player = mediaPlayer else { return }
        let pos = max(0, min(1, position))
        libvlc_media_player_set_position(player, pos)
    }
    
    public func seek(to time: TimeInterval) {
        guard let player = mediaPlayer else { return }
        let timeMs = Int64(time * 1000)
        libvlc_media_player_set_time(player, timeMs)
    }
    
    public func setRate(_ rate: Float) {
        guard let player = mediaPlayer else { return }
        libvlc_media_player_set_rate(player, rate)
        playbackState.rate = rate
    }
    
    public func setVolume(_ volume: Float) {
        guard let player = mediaPlayer else { return }
        let vol = Int32(volume * 100)
        libvlc_audio_set_volume(player, vol)
        playbackState.volume = volume
    }
    
    public func toggleMute() {
        guard let player = mediaPlayer else { return }
        let isMuted = libvlc_audio_get_mute(player) != 0
        libvlc_audio_set_mute(player, isMuted ? 0 : 1)
        playbackState.isMuted = !isMuted
    }
    
    public func setVideoTrack(_ trackId: Int) {
        guard let player = mediaPlayer else { return }
        libvlc_video_set_track(player, Int32(trackId))
        playbackState.videoTrack = trackId
    }
    
    public func setAudioTrack(_ trackId: Int) {
        guard let player = mediaPlayer else { return }
        libvlc_audio_set_track(player, Int32(trackId))
        playbackState.audioTrack = trackId
    }
    
    public func setSubtitleTrack(_ trackId: Int) {
        guard let player = mediaPlayer else { return }
        libvlc_video_set_spu(player, Int32(trackId))
        playbackState.subtitleTrack = trackId
    }
    
    public func setAspectRatio(_ aspectRatio: String?) {
        guard let player = mediaPlayer, let ratio = aspectRatio else { return }
        libvlc_video_set_aspect_ratio(player, ratio)
        playbackState.aspectRatio = aspectRatio
    }
    
    public func setCropGeometry(_ geometry: String?) {
        guard let player = mediaPlayer, let crop = geometry else { return }
        libvlc_video_set_crop_geometry(player, crop)
        playbackState.cropGeometry = geometry
    }
    
    public func takeSnapshot() -> Data? {
        // Windows snapshot implementation
        return nil
    }
    
    public func addSubtitleTrack(url: URL) throws {
        guard let player = mediaPlayer, let instance = libvlcInstance else { throw LibVLCError.notInitialized }
        
        let urlString = url.absoluteString
        let subtitleMedia = libvlc_media_new_location(instance, urlString)
        guard subtitleMedia != nil else { return }
        
        libvlc_media_player_add_slave(player, subtitleMedia, libvlc_media_slave_type_t(libvlc_media_slave_type_subtitle), true)
    }
    
    public func cleanup() {
        stop()
        if let media = media {
            libvlc_media_release(media)
            self.media = nil
        }
        if let player = mediaPlayer {
            libvlc_media_player_release(player)
            mediaPlayer = nil
        }
        if let instance = libvlcInstance {
            libvlc_release(instance)
            libvlcInstance = nil
        }
        isInitialized = false
    }
    
    // MARK: - Private Helpers
    
    private func updatePlaybackState() {
        guard let player = mediaPlayer else { return }
        
        playbackState.isPlaying = libvlc_media_player_is_playing(player) != 0
        
        let position = libvlc_media_player_get_position(player)
        playbackState.position = position
        
        let time = libvlc_media_player_get_time(player)
        playbackState.time = TimeInterval(time) / 1000
        
        let length = libvlc_media_player_get_length(player)
        if length > 0 {
            playbackState.duration = TimeInterval(length) / 1000
        }
        
        playbackState.rate = libvlc_media_player_get_rate(player)
        
        let volume = libvlc_audio_get_volume(player)
        playbackState.volume = Float(volume) / 100.0
        
        playbackState.isMuted = libvlc_audio_get_mute(player) != 0
        
        playbackState.videoTrack = Int(libvlc_video_get_track(player))
        playbackState.audioTrack = Int(libvlc_audio_get_track(player))
        playbackState.subtitleTrack = Int(libvlc_video_get_spu(player))
    }
    
    private func updateMediaInfo() {
        guard let media = media else { return }
        
        var videoTracks: [LibVLCTrack] = []
        var audioTracks: [LibVLCTrack] = []
        var subtitleTracks: [LibVLCTrack] = []
        
        // Get track information
        var tracksPtr: UnsafeMutablePointer<libvlc_media_track_t?>? = nil
        let trackCount = libvlc_media_tracks_get(media, &tracksPtr)
        
        if trackCount > 0, let tracks = tracksPtr {
            for i in 0..<Int(trackCount) {
                let track = tracks[i]
                let id = Int(track.pointee.i_id)
                let name = track.pointee.psz_name != nil ? String(cString: track.pointee.psz_name!) : "Track \(id)"
                let language = track.pointee.psz_language != nil ? String(cString: track.pointee.psz_language!) : nil
                let codec = track.pointee.psz_codec != nil ? String(cString: track.pointee.psz_codec!) : nil
                
                switch track.pointee.i_type {
                case libvlc_track_video:
                    videoTracks.append(LibVLCTrack(id: id, name: name, language: language, codec: codec))
                case libvlc_track_audio:
                    audioTracks.append(LibVLCTrack(id: id, name: name, language: language, codec: codec))
                case libvlc_track_text:
                    subtitleTracks.append(LibVLCTrack(id: id, name: name, language: language, codec: codec))
                default:
                    break
                }
            }
            libvlc_media_tracks_release(tracksPtr, trackCount)
        }
        
        // Get video dimensions
        var width = 0
        var height = 0
        if let videoTrack = videoTracks.first {
            // Would need to get dimensions from track info
        }
        
        let length = libvlc_media_get_duration(media)
        mediaInfo = LibVLCMediaInfo(
            duration: TimeInterval(length) / 1000,
            width: width,
            height: height,
            videoTracks: videoTracks,
            audioTracks: audioTracks,
            subtitleTracks: subtitleTracks
        )
    }
    
    // MARK: - Drawable (for video output)
    
    var drawable: Any? {
        return nil
    }
    
    func setDrawable(_ drawable: Any?) {
        // Windows: set HWND or swap chain
        // libvlc_media_player_set_hwnd(mediaPlayer, drawable as HWND)
    }
    
    deinit {
        cleanup()
    }
}

#else
// Fallback for other platforms
public class LibVLCWrapper: LibVLCPlayerProtocol, ObservableObject {
    @Published public var playbackState = LibVLCPlaybackState()
    public var playbackStatePublisher: Published<LibVLCPlaybackState>.Publisher { $playbackState }
    
    @Published public var mediaInfo: LibVLCMediaInfo?
    
    public func initialize() throws {
        throw LibVLCError.initializationFailed
    }
    
    public func openMedia(url: URL, options: [String]?) throws {
        throw LibVLCError.notInitialized
    }
    
    public func play() {}
    public func pause() {}
    public func stop() {}
    public func seek(to position: Float) {}
    public func seek(to time: TimeInterval) {}
    public func setRate(_ rate: Float) {}
    public func setVolume(_ volume: Float) {}
    public func toggleMute() {}
    public func setVideoTrack(_ trackId: Int) {}
    public func setAudioTrack(_ trackId: Int) {}
    public func setSubtitleTrack(_ trackId: Int) {}
    public func setAspectRatio(_ aspectRatio: String?) {}
    public func setCropGeometry(_ geometry: String?) {}
    public func takeSnapshot() -> Data? { nil }
    public func addSubtitleTrack(url: URL) throws {}
    public func cleanup() {}
    
    public var drawable: Any? { nil }
}
#endif