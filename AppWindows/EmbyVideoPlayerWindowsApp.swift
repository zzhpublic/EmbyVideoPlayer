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
        vlcWrapper.initialize()
        
        // Test with a sample media URL
        // In a real app, this would be from Emby server or SMB share
        let testURL = "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4"
        
        print("Testing playback with: \(testURL)")
        
        do {
            try await vlcWrapper.openMedia(url: testURL)
            vlcWrapper.play()
            
            print("Playback started. Press Ctrl+C to stop.")
            
            // Keep the app running
            while true {
                try await Task.sleep(nanoseconds: 1_000_000_000)
                if let state = vlcWrapper.playbackState {
                    print("State: \(state)")
                    if state == .ended || state == .error {
                        break
                    }
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