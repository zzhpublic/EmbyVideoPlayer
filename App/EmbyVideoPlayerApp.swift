//
//  EmbyVideoPlayerApp.swift
//  EmbyVideoPlayer
//
//  Main app entry point
//

import SwiftUI
import EmbyVideoPlayer

@main
struct EmbyVideoPlayerApp: App {
    @StateObject private var vlcWrapper = LibVLCWrapper.shared
    @StateObject private var embyClient = EmbyAPIClient()
    @StateObject private var smbBrowser = SMBBrowser()
     
    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(vlcWrapper)
                .environmentObject(embyClient)
                .environmentObject(smbBrowser)
        }
    }
}