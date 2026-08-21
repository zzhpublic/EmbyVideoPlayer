//
//  EmbyVideoPlayerApp.swift
//  EmbyVideoPlayer
//
//  Main app entry point
//

import SwiftUI

@main
struct EmbyVideoPlayerApp: App {
    @StateObject private var vlcManager = LibVLCManager.shared
    @StateObject private var embyClient = EmbyAPIClient()
    @StateObject private var smbBrowser = SMBBrowser()
    
    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(vlcManager)
                .environmentObject(embyClient)
                .environmentObject(smbBrowser)
        }
    }
}