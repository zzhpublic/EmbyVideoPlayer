//
//  VideoPlayerView.swift
//  SideStore
//
//  Created for LibVLC video player with full controls
//

import SwiftUI
import Combine
import MobileVLCKit

// MARK: - Video Player View

struct VideoPlayerView: View {
    let playbackInfo: EmbyPlaybackInfo
    @EnvironmentObject var vlcManager: LibVLCManager
    @EnvironmentObject var embyClient: EmbyAPIClient
    @Environment(\.dismiss) var dismiss
    
    @State private var player: LibVLCWrapper
    @State private var showControls = true
    @State private var controlsTimer: Timer?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedAudioTrack: Int = -1
    @State private var selectedSubtitleTrack: Int = -1
    @State private var selectedVideoTrack: Int = -1
    @State private var showTrackSelection = false
    @State private var showPlaybackSpeed = false
    @State private var showQualitySelection = false
    @State private var isFullScreen = true
    @State private var dragPosition: Float?
    @State private var lastPosition: TimeInterval = 0
    
    private let mediaSourceId: String
    private let itemId: String
    
    init(playbackInfo: EmbyPlaybackInfo) {
        self.playbackInfo = playbackInfo
        // Select best media source (prefer direct play/stream)
        let bestSource = playbackInfo.mediaSources
            .sorted { ($0.supportsDirectPlay ?? false) && !($1.supportsDirectPlay ?? false) }
            .first ?? playbackInfo.mediaSources.first!
        
        self.mediaSourceId = bestSource.id
        self.itemId = playbackInfo.item.id
        self._player = State(initialValue: LibVLCManager.shared.player)
    }
    
    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
            
            if isLoading {
                ProgressView("Loading video...")
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundColor(.red)
                    Text("Playback Error")
                        .font(.title.bold())
                        .foregroundColor(.white)
                    Text(error)
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Button("Retry") { loadMedia() }
                        .buttonStyle(.borderedProminent)
                    Button("Close") { dismiss() }
                        .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Video layer container
                VideoLayerView(player: player)
                    .ignoresSafeArea()
                    .onTapGesture { toggleControls() }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                handleDrag(value)
                            }
                            .onEnded { value in
                                endDrag(value)
                            }
                    )
                
                // Controls overlay
                if showControls {
                    VStack {
                        // Top bar
                        TopControlsBar(
                            title: playbackInfo.item.name,
                            onClose: { dismiss() },
                            onTrackSelect: { showTrackSelection = true },
                            onQualitySelect: { showQualitySelection = true }
                        )
                        .transition(.move(edge: .top).combined(with: .opacity))
                        
                        Spacer()
                        
                        // Bottom controls
                        BottomControlsBar(
                            player: player,
                            dragPosition: $dragPosition,
                            onPlayPause: { togglePlayPause() },
                            onSeekBack: { seekRelative(-10) },
                            onSeekForward: { seekRelative(30) },
                            onSpeedChange: { showPlaybackSpeed = true },
                            onFullScreen: { toggleFullScreen() },
                            onAirPlay: { /* AirPlay not available with LibVLC directly */ }
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    .animation(.easeInOut(duration: 0.2), value: showControls)
                }
            }
        }
        .statusBarHidden(isFullScreen)
        .onAppear {
            setupPlayer()
            loadMedia()
            startControlsTimer()
        }
        .onDisappear {
            cleanup()
        }
        .sheet(isPresented: $showTrackSelection) {
            TrackSelectionView(
                player: player,
                selectedAudioTrack: $selectedAudioTrack,
                selectedSubtitleTrack: $selectedSubtitleTrack,
                selectedVideoTrack: $selectedVideoTrack
            )
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showPlaybackSpeed) {
            PlaybackSpeedView(currentSpeed: player.playbackState.rate) { speed in
                player.setRate(speed)
            }
            .presentationDetents([.height(200)])
        }
        .sheet(isPresented: $showQualitySelection) {
            QualitySelectionView(
                mediaSources: playbackInfo.mediaSources,
                currentSourceId: mediaSourceId
            ) { sourceId in
                switchQuality(to: sourceId)
            }
            .presentationDetents([.medium])
        }
    }
    
    // MARK: - Player Setup
    
    private func setupPlayer() {
        // Player is already initialized via LibVLCManager
        // Subscribe to playback state updates
    }
    
    private func loadMedia() {
        isLoading = true
        errorMessage = nil
        
            // Get stream URL from Emby - use shared client instance
            @EnvironmentObject var embyClient: EmbyAPIClient
        
            if let server = embyClient.currentServer,
               let token = server.accessToken {
            let streamURL = "\(server.baseURL)/emby/Videos/\(itemId)/stream?MediaSourceId=\(mediaSourceId)&api_key=\(token)"
            
            if let url = URL(string: streamURL) {
                do {
                    try player.openMedia(url: url, options: [
                        "network-caching=2000",
                        "file-caching=2000",
                        "live-caching=2000",
                        "sout-mux-caching=2000",
                        "clock-jitter=0",
                        "clock-synchro=0"
                    ])
                    player.play()
                    
                    // Load subtitles if available
                    loadSubtitles()
                    
                    // Wait a bit for media to start
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        isLoading = false
                    }
                } catch {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            } else {
                errorMessage = "Invalid stream URL"
                isLoading = false
            }
        } else {
            errorMessage = "No server connection"
            isLoading = false
        }
    }
    
    private func loadSubtitles() {
        // Get subtitle tracks from media info
        if let mediaInfo = player.mediaInfo {
            for subtitle in mediaInfo.subtitleTracks {
                if subtitle.isSelected {
                    // Load external subtitle if needed
                }
            }
        }
        
        // Also try to get subtitle streams from Emby
        if let server = embyClient.currentServer,
           let token = server.accessToken {
            // Fetch subtitle streams
            let subtitleURL = "\(server.baseURL)/emby/Videos/\(itemId)/0/stream?MediaSourceId=\(mediaSourceId)&api_key=\(token)&format=vtt"
            // This would be handled by LibVLC automatically for embedded subtitles
        }
    }
    
    // MARK: - Playback Controls
    
    private func togglePlayPause() {
        if player.playbackState.isPlaying {
            player.pause()
        } else {
            player.play()
        }
        resetControlsTimer()
    }
    
    private func seekRelative(_ seconds: TimeInterval) {
        let newTime = player.playbackState.time + seconds
        player.seek(to: max(0, min(newTime, player.playbackState.duration)))
        resetControlsTimer()
    }
    
    private func seekToPosition(_ position: Float) {
        player.seek(to: position)
    }
    
    private func switchQuality(to sourceId: String) {
        // Reload with new quality
        // This would require getting new stream URL and reloading
        showQualitySelection = false
        loadMedia()
    }
    
    // MARK: - Controls Visibility
    
    private func toggleControls() {
        withAnimation {
            showControls.toggle()
        }
        if showControls {
            startControlsTimer()
        } else {
            stopControlsTimer()
        }
    }
    
    private func showControlsTemporarily() {
        withAnimation {
            showControls = true
        }
        resetControlsTimer()
    }
    
    private func startControlsTimer() {
        controlsTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
            withAnimation {
                showControls = false
            }
        }
    }
    
    private func resetControlsTimer() {
        controlsTimer?.invalidate()
        startControlsTimer()
    }
    
    private func stopControlsTimer() {
        controlsTimer?.invalidate()
        controlsTimer = nil
    }
    
    // MARK: - Gesture Handling
    
    private func handleDrag(_ value: DragGesture.Value) {
        // Horizontal drag for seeking
        let translation = value.translation.width
        let screenWidth = UIScreen.main.bounds.width
        let seekAmount = Float(translation / screenWidth)
        dragPosition = max(0, min(1, player.playbackState.position + seekAmount))
    }
    
    private func endDrag(_ value: DragGesture.Value) {
        if let position = dragPosition {
            player.seek(to: position)
            lastPosition = player.playbackState.duration * Double(position)
        }
        dragPosition = nil
        resetControlsTimer()
    }
    
    private func toggleFullScreen() {
        withAnimation {
            isFullScreen.toggle()
        }
    }
    
    // MARK: - Cleanup
    
    private func cleanup() {
        stopControlsTimer()
        player.stop()
    }
}

// MARK: - Video Layer View (wraps LibVLC drawable)

struct VideoLayerView: UIViewRepresentable {
    let player: LibVLCWrapper
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        view.contentMode = .scaleAspectFit
        
        // Set the drawable for LibVLC
        #if os(iOS) || os(tvOS)
        player.setDrawable(view)
        #endif
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Update if needed
    }
}

// MARK: - Top Controls Bar

struct TopControlsBar: View {
    let title: String
    let onClose: () -> Void
    let onTrackSelect: () -> Void
    let onQualitySelect: () -> Void
    
    var body: some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.title2)
                    .foregroundColor(.white)
                    .padding(12)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Circle())
            }
            
            Spacer()
            
            Text(title)
                .font(.headline)
                .foregroundColor(.white)
                .lineLimit(1)
            
            Spacer()
            
            HStack(spacing: 12) {
                Button(action: onTrackSelect) {
                    Image(systemName: "text.bubble")
                        .font(.title2)
                        .foregroundColor(.white)
                        .padding(12)
                        .background(Color.black.opacity(0.5))
                        .clipShape(Circle())
                }
                
                Button(action: onQualitySelect) {
                    Image(systemName: "hd")
                        .font(.title2)
                        .foregroundColor(.white)
                        .padding(12)
                        .background(Color.black.opacity(0.5))
                        .clipShape(Circle())
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.7), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

// MARK: - Bottom Controls Bar

struct BottomControlsBar: View {
    @ObservedObject var player: LibVLCWrapper
    @Binding var dragPosition: Float?
    let onPlayPause: () -> Void
    let onSeekBack: () -> Void
    let onSeekForward: () -> Void
    let onSpeedChange: () -> Void
    let onFullScreen: () -> Void
    let onAirPlay: () -> Void
    
    var body: some View {
        VStack(spacing: 8) {
            // Progress bar
            ProgressBar(
                position: dragPosition ?? player.playbackState.position,
                bufferedPosition: 0, // LibVLC doesn't expose buffer easily
                onSeek: { position in
                    dragPosition = position
                },
                onSeekEnd: { position in
                    player.seek(to: position)
                    dragPosition = nil
                }
            )
            .padding(.horizontal, 16)
            
            // Time labels
            HStack {
                Text(formatTime(player.playbackState.time))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.white)
                
                Spacer()
                
                Text(formatTime(player.playbackState.duration))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 16)
            
            // Control buttons
            HStack(spacing: 24) {
                Button(action: onSeekBack) {
                    Image(systemName: "gobackward.10")
                        .font(.title)
                        .foregroundColor(.white)
                }
                
                Button(action: onPlayPause) {
                    Image(systemName: player.playbackState.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 36))
                        .foregroundColor(.white)
                }
                
                Button(action: onSeekForward) {
                    Image(systemName: "goforward.30")
                        .font(.title)
                        .foregroundColor(.white)
                }
            }
            .padding(.vertical, 8)
            
            // Additional controls
            HStack {
                Button(action: onSpeedChange) {
                    Text(String(format: "%.1fx", player.playbackState.rate))
                        .font(.caption.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.2))
                        .cornerRadius(8)
                }
                
                Spacer()
                
                // Volume
                VolumeSlider(volume: Binding(
                    get: { player.playbackState.volume },
                    set: { player.setVolume($0) }
                ))
                .frame(width: 80)
                
                Button(action: { player.toggleMute() }) {
                    Image(systemName: player.playbackState.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                }
                
                Button(action: onFullScreen) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.title2)
                        .foregroundColor(.white)
                }
                
                Button(action: onAirPlay) {
                    Image(systemName: "airplayvideo")
                        .font(.title2)
                        .foregroundColor(.white)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .background(
            LinearGradient(
                colors: [Color.clear, Color.black.opacity(0.9)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = (Int(time) % 3600) / 60
        let seconds = Int(time) % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}

// MARK: - Progress Bar

struct ProgressBar: View {
    let position: Float
    let bufferedPosition: Float
    let onSeek: (Float) -> Void
    let onSeekEnd: (Float) -> Void
    
    @State private var isDragging = false
    @State private var dragPosition: Float = 0
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background track
                Capsule()
                    .fill(Color.white.opacity(0.3))
                    .frame(height: 4)
                
                // Buffered track
                if bufferedPosition > 0 {
                    Capsule()
                        .fill(Color.white.opacity(0.5))
                        .frame(width: geometry.size.width * CGFloat(bufferedPosition), height: 4)
                }
                
                // Progress track
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: geometry.size.width * CGFloat(isDragging ? dragPosition : position), height: 4)
                
                // Thumb
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 16, height: 16)
                    .offset(x: geometry.size.width * CGFloat(isDragging ? dragPosition : position) - 8)
                    .opacity(isDragging ? 1 : 0)
                    .animation(.easeInOut(duration: 0.1), value: isDragging)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        let newPosition = Float(value.location.x / geometry.size.width)
                        dragPosition = max(0, min(1, newPosition))
                        onSeek(dragPosition)
                    }
                    .onEnded { _ in
                        isDragging = false
                        onSeekEnd(dragPosition)
                    }
            )
            .onTapGesture { location in
                let newPosition = Float(location.x / geometry.size.width)
                let clamped = max(0, min(1, newPosition))
                onSeek(clamped)
                onSeekEnd(clamped)
            }
        }
        .frame(height: 20) // Larger hit area
    }
}

// MARK: - Volume Slider

struct VolumeSlider: View {
    @Binding var volume: Float
    
    var body: some View {
        Slider(value: $volume, in: 0...1) {
            // Empty label
        } minimumValueLabel: {
            Image(systemName: "speaker.fill")
                .font(.caption)
                .foregroundColor(.white)
        } maximumValueLabel: {
            Image(systemName: "speaker.wave.3.fill")
                .font(.caption)
                .foregroundColor(.white)
        }
        .accentColor(.white)
    }
}

// MARK: - Track Selection View

struct TrackSelectionView: View {
    @ObservedObject var player: LibVLCWrapper
    @Binding var selectedAudioTrack: Int
    @Binding var selectedSubtitleTrack: Int
    @Binding var selectedVideoTrack: Int
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            List {
                if let mediaInfo = player.mediaInfo {
                    // Video tracks
                    if !mediaInfo.videoTracks.isEmpty {
                        Section("Video Tracks") {
                            ForEach(mediaInfo.videoTracks) { track in
                                TrackRow(
                                    track: track,
                                    isSelected: selectedVideoTrack == track.id,
                                    onSelect: { selectedVideoTrack = track.id; player.setVideoTrack(track.id) }
                                )
                            }
                        }
                    }
                    
                    // Audio tracks
                    if !mediaInfo.audioTracks.isEmpty {
                        Section("Audio Tracks") {
                            ForEach(mediaInfo.audioTracks) { track in
                                TrackRow(
                                    track: track,
                                    isSelected: selectedAudioTrack == track.id,
                                    onSelect: { selectedAudioTrack = track.id; player.setAudioTrack(track.id) }
                                )
                            }
                        }
                    }
                    
                    // Subtitle tracks
                    if !mediaInfo.subtitleTracks.isEmpty {
                        Section("Subtitles") {
                            // Off option
                            TrackRow(
                                track: LibVLCTrack(id: -1, name: "Off", language: nil, codec: nil),
                                isSelected: selectedSubtitleTrack == -1,
                                onSelect: { selectedSubtitleTrack = -1; player.setSubtitleTrack(-1) }
                            )
                            
                            ForEach(mediaInfo.subtitleTracks) { track in
                                TrackRow(
                                    track: track,
                                    isSelected: selectedSubtitleTrack == track.id,
                                    onSelect: { selectedSubtitleTrack = track.id; player.setSubtitleTrack(track.id) }
                                )
                            }
                        }
                    }
                }
            }
            .navigationTitle("Tracks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct TrackRow: View {
    let track: LibVLCTrack
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.name)
                        .font(.body)
                        .foregroundColor(.primary)
                    
                    if let language = track.language {
                        Text(language.uppercased())
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if let codec = track.codec {
                        Text(codec.uppercased())
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundColor(.accentColor)
                }
            }
        }
    }
}

// MARK: - Playback Speed View

struct PlaybackSpeedView: View {
    let currentSpeed: Float
    let onSelect: (Float) -> Void
    @Environment(\.dismiss) var dismiss
    
    private let speeds: [Float] = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 3.0, 4.0]
    
    var body: some View {
        NavigationView {
            List {
                ForEach(speeds, id: \.self) { speed in
                    Button(action: { onSelect(speed); dismiss() }) {
                        HStack {
                            Text(String(format: "%.2fx", speed))
                                .font(.body)
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            if abs(speed - currentSpeed) < 0.01 {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Playback Speed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Quality Selection View

struct QualitySelectionView: View {
    let mediaSources: [EmbyMediaSource]
    let currentSourceId: String
    let onSelect: (String) -> Void
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            List {
                ForEach(mediaSources, id: \.id) { source in
                    Button(action: { onSelect(source.id) }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(source.name ?? "Auto")
                                    .font(.body)
                                    .foregroundColor(.primary)
                                
                                HStack(spacing: 12) {
                                    if let width = source.width, let height = source.height {
                                        Text("\(width)x\(height)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    if let bitrate = source.bitrate {
                                        Text("\(bitrate / 1000) kbps")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    if let container = source.container {
                                        Text(container.uppercased())
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            
                            Spacer()
                            
                            if source.id == currentSourceId {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                            
                            if source.supportsDirectPlay == true {
                                Text("Direct Play")
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.green.opacity(0.2))
                                    .foregroundColor(.green)
                                    .cornerRadius(4)
                            } else if source.supportsTranscoding == true {
                                Text("Transcode")
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.orange.opacity(0.2))
                                    .foregroundColor(.orange)
                                    .cornerRadius(4)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Quality")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Picture in Picture Support

extension VideoPlayerView {
    func enablePiP() {
        #if os(iOS)
        // PiP is handled by AVPlayerViewController, not directly with LibVLC
        // For LibVLC, you'd need to implement custom PiP using AVPictureInPictureController
        #endif
    }
}

// MARK: - Preview

#Preview {
    VideoPlayerView(playbackInfo: EmbyPlaybackInfo(
        mediaSources: [
            EmbyMediaSource(`protocol`: "File", id: "1", path: "/test.mp4", encodings: nil, container: "mp4", size: 1000000, name: "1080p", runTimeTicks: 72000000000, bitrate: 5000000, width: 1920, height: 1080, videoType: "VideoFile", video3DFormat: nil, isoType: nil, videoProfile: "High", audioProfile: "AAC", supportsDirectPlay: true, supportsDirectStream: true, supportsTranscoding: false, isRemote: false)
        ],
        item: EmbyItem(id: "1", name: "Test Movie", type: "Movie", mediaType: "Video", seriesName: nil, parentId: nil, path: nil, overview: "Test overview", productionYear: 2024, communityRating: 8.5, officialRating: "PG-13", runTimeTicks: 72000000000, imageTags: nil, backdropImageTags: nil, genreItems: ["Action", "Sci-Fi"], people: nil, studios: nil, taglines: nil, premiereDate: nil, isFolder: nil, childCount: nil, locationType: nil, mediaStreams: nil, playAccess: nil)
    ))
    .environmentObject(LibVLCManager.shared)
}