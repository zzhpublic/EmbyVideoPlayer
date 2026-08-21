//
//  MainView.swift
//  EmbyVideoPlayer
//
//  Main tab view for the video player app
//

import SwiftUI
import EmbyVideoPlayer

struct MainView: View {
    @EnvironmentObject var vlcManager: LibVLCWrapper
    @EnvironmentObject var embyClient: EmbyAPIClient
    @EnvironmentObject var smbBrowser: SMBBrowser
     
    @State private var selectedTab: MainTab = .home
    
    enum MainTab: String, CaseIterable {
        case home = "Home"
        case emby = "Emby"
        case smb = "SMB"
        case local = "Local"
        case settings = "Settings"
        
        var icon: String {
            switch self {
            case .home: return "house.fill"
            case .emby: return "tv.fill"
            case .smb: return "server.rack"
            case .local: return "iphone.gen3"
            case .settings: return "gear"
            }
        }
    }
    
    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack { HomeView() }
                .tabItem { Label(MainTab.home.rawValue, systemImage: MainTab.home.icon) }
                .tag(MainTab.home)
            
            NavigationStack { PosterFlowView() }
                .tabItem { Label(MainTab.emby.rawValue, systemImage: MainTab.emby.icon) }
                .tag(MainTab.emby)
            
            NavigationStack { SMBBrowserView() }
                .tabItem { Label(MainTab.smb.rawValue, systemImage: MainTab.smb.icon) }
                .tag(MainTab.smb)
            
            NavigationStack { Text("Local Files").navigationTitle("Local") }
                .tabItem { Label(MainTab.local.rawValue, systemImage: MainTab.local.icon) }
                .tag(MainTab.local)
            
                        NavigationStack { Text("Settings").navigationTitle("Settings") }
                .tabItem { Label(MainTab.settings.rawValue, systemImage: MainTab.settings.icon) }
                .tag(MainTab.settings)
        }
        .tint(.accentColor)
        .onAppear { embyClient.loadServers() }
    }
}

struct HomeView: View {
    @EnvironmentObject var embyClient: EmbyAPIClient
    @EnvironmentObject var smbBrowser: SMBBrowser
    
    @State private var continueWatching: [PosterItem] = []
    @State private var nextUp: [PosterItem] = []
    @State private var isLoading = false
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 24) {
                StatsCardView()
                if !continueWatching.isEmpty {
                    HorizontalPosterFlow(
                        title: "Continue Watching",
                        items: continueWatching,
                        layout: .horizontal(rowHeight: 180),
                        onItemTap: { _ in },
                        onItemLongPress: nil,
                        seeAllAction: nil
                    )
                }
                if !nextUp.isEmpty {
                    HorizontalPosterFlow(
                        title: "Next Up Episodes",
                        items: nextUp,
                        layout: .horizontal(rowHeight: 180),
                        onItemTap: { _ in },
                        onItemLongPress: nil,
                        seeAllAction: nil
                    )
                }
                QuickActionsView()
                ConnectedServersView()
            }
            .padding(.vertical)
        }
        .navigationTitle("EmbyVideoPlayer")
        .refreshable { await loadHomeData() }
        .task { await loadHomeData() }
    }
    
    private func loadHomeData() async {
        isLoading = true
        defer { isLoading = false }
        async let cw = embyClient.getItems(parentId: "", includeItemTypes: "Movie,Episode", sortBy: "DatePlayed", limit: 10)
        async let nu = embyClient.getItems(parentId: "", includeItemTypes: "Episode", sortBy: "DatePlayed", limit: 10)
        if let cwResult = await cw { continueWatching = cwResult.map { PosterItem(from: $0) } }
        if let nuResult = await nu { nextUp = nuResult.map { PosterItem(from: $0) } }
    }
}

struct StatsCardView: View {
    @EnvironmentObject var embyClient: EmbyAPIClient
    @EnvironmentObject var smbBrowser: SMBBrowser
    var body: some View {
        HStack(spacing: 16) {
            StatCard(title: "Emby Servers", value: "\(embyClient.servers.count)", icon: "tv.fill", color: .blue)
            StatCard(title: "SMB Servers", value: "\(smbBrowser.discoveredServers.count)", icon: "server.rack", color: .green)
            StatCard(title: "Current Server", value: embyClient.currentServer?.name ?? "None", icon: "checkmark.circle", color: .orange)
        }
        .padding(.horizontal)
    }
}

struct StatCard: View {
    let title: String, value: String, icon: String, color: Color
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.title2).foregroundColor(color)
            Text(value).font(.headline.bold()).lineLimit(1)
            Text(title).font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity).padding().background(Color(.systemGray6)).cornerRadius(12)
    }
}

struct QuickActionsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions").font(.headline).padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    QuickActionButton(title: "Add Emby", icon: "plus.circle", color: .blue) { }
                    QuickActionButton(title: "Add SMB", icon: "server.rack", color: .green) { }
                    QuickActionButton(title: "Scan Local", icon: "folder.badge.plus", color: .orange) { }
                    QuickActionButton(title: "Search", icon: "magnifyingglass", color: .purple) { }
                }.padding(.horizontal)
            }
        }
    }
}

struct QuickActionButton: View {
    let title: String, icon: String, color: Color, action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon).font(.title2).foregroundColor(color)
                Text(title).font(.caption.bold()).foregroundColor(.primary)
            }
            .frame(width: 80, height: 80).background(Color(.systemGray6)).cornerRadius(12)
        }
    }
}

struct ConnectedServersView: View {
    @EnvironmentObject var embyClient: EmbyAPIClient
    @EnvironmentObject var smbBrowser: SMBBrowser
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connected Servers").font(.headline).padding(.horizontal)
            if embyClient.servers.isEmpty && smbBrowser.discoveredServers.isEmpty {
                Text("No servers connected").foregroundColor(.secondary).padding(.horizontal)
            } else {
                if !embyClient.servers.isEmpty {
                    SectionCard(title: "Emby", color: .blue) {
                        ForEach(embyClient.servers) { ServerRowView(server: $0, isCurrent: embyClient.currentServer?.id == $0.id) }
                    }
                }
                if !smbBrowser.discoveredServers.isEmpty {
                    SectionCard(title: "SMB", color: .green) {
                        ForEach(smbBrowser.discoveredServers) { SMBServerRowView(server: $0) }
                    }
                }
            }
        }
    }
}

struct SectionCard<Content: View>: View {
    let title: String, color: Color
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: title == "Emby" ? "tv.fill" : "server.rack")
                .font(.subheadline.bold()).foregroundColor(color).padding(.horizontal)
            VStack(spacing: 0) { content }
                .background(Color(.systemGray6)).cornerRadius(12).padding(.horizontal)
        }
    }
}

struct ServerRowView: View {
    let server: EmbyServer, isCurrent: Bool
    var body: some View {
        HStack {
            Image(systemName: "tv.fill").foregroundColor(.blue).frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(server.name).font(.subheadline)
                Text(server.address).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            if isCurrent { Image(systemName: "checkmark.circle.fill").foregroundColor(.blue) }
        }.padding().background(Color(.systemBackground))
    }
}

struct SMBServerRowView: View {
    let server: SMBServer
    var body: some View {
        HStack {
            Image(systemName: "server.rack").foregroundColor(.green).frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(server.displayName).font(.subheadline)
                Text("\(server.host):\(server.port)").font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            if server.username != nil { Image(systemName: "lock.fill").foregroundColor(.green) }
        }.padding().background(Color(.systemBackground))
    }
}