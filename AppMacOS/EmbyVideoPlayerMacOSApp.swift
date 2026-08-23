//
//  EmbyVideoPlayerMacOSApp.swift
//  EmbyVideoPlayerMacOS
//
//  Main macOS app entry point
//

import SwiftUI
import EmbyVideoPlayer

@main
struct EmbyVideoPlayerMacOSApp: App {
    @StateObject private var vlcWrapper = LibVLCWrapper.shared
    @StateObject private var embyClient = EmbyAPIClient()
    @StateObject private var smbBrowser = SMBBrowser()
    
    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(vlcWrapper)
                .environmentObject(embyClient)
                .environmentObject(smbBrowser)
                .frame(minWidth: 1024, minHeight: 768)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        
        Settings {
            Text("Settings view")
                .padding()
        }
    }
}