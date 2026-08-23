// EmbyVideoPlayerWindowsApp.swift
// Windows entry point for EmbyVideoPlayer
// This is a console application for testing libvlc on Windows

import Foundation
import EmbyVideoPlayer

@main
struct EmbyVideoPlayerWindowsApp {
    static func main() async {
        print("EmbyVideoPlayer Windows Build")
        print("=============================")
        
        // Initialize LibVLC wrapper
        let vlcWrapper = LibVLCWrapper.shared
        do {
            try vlcWrapper.initialize()
        } catch {
            print("Failed to initialize: \(error)")
            return
        }
        
        // Test with a sample media URL
        // In a real app, this would be from Emby server or SMB share
        let testURL = "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4"
        
        print("Testing playback with: \(testURL)")
        
        do {
            try vlcWrapper.openMedia(url: URL(string: testURL)!)
            vlcWrapper.play()
            
            print("Playback started. Press Ctrl+C to stop.")
            
            // Keep the app running
            while true {
                try await Task.sleep(nanoseconds: 1_000_000_000)
                let state = vlcWrapper.playbackState
                print("State: playing=\(state.isPlaying), position=\(state.position), time=\(state.time)/\(state.duration)")
                // Check if playback ended
                if state.time >= state.duration && state.duration > 0 {
                    break
                }
            }
        } catch {
            print("Error: \(error)")
        }
        
        vlcWrapper.stop()
        vlcWrapper.cleanup()
        print("Done.")
    }
}