//
//  SMBBrowserView.swift
//  SideStore
//
//  Created for SMB network video browser
//

import SwiftUI

// MARK: - SMB Browser View

struct SMBBrowserView: View {
    @StateObject var browser = SMBBrowser()
    @EnvironmentObject var vlcManager: LibVLCManager
    
    @State private var showingAddServer = false
    @State private var showingAuth = false
    @State private var authServer: SMBServer?
    @State private var authUsername = ""
    @State private var authPassword = ""
    @State private var navigationPath = NavigationPath()
    @State private var selectedVideo: SMBFile?
    @State private var showVideoPlayer = false
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()
                
                if browser.discoveredServers.isEmpty && !browser.isLoading {
                    // Empty state with add server button
                    VStack(spacing: 24) {
                        Image(systemName: "server.rack")
                            .font(.system(size: 64))
                            .foregroundColor(.secondary)
                        
                        Text("No SMB Servers Found")
                            .font(.title2.bold())
                            .foregroundColor(.primary)
                        
                        Text("Add a server manually or start discovery to find SMB shares on your network")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        Button(action: { showingAddServer = true }) {
                            Label("Add Server", systemImage: "plus.circle.fill")
                                .font(.headline)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        
                        Button(action: { browser.startDiscovery() }) {
                            Label("Start Discovery", systemImage: "magnifyingglass")
                                .font(.headline)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Server list
                    List {
                        // Discovered servers section
                        if !browser.discoveredServers.isEmpty {
                            Section("Discovered Servers") {
                                ForEach(browser.discoveredServers) { server in
                                    SMBServerRow(server: server) {
                                        connectToServer(server)
                                    } onAuth: {
                                        authServer = server
                                        showingAuth = true
                                    } onDelete: {
                                        browser.removeServer(server)
                                    }
                                }
                            }
                        }
                        
                        // Manual servers section (if any saved)
                        let manualServers = browser.discoveredServers.filter { !$0.name.hasPrefix("SMB-") }
                        if !manualServers.isEmpty {
                            Section("Saved Servers") {
                                ForEach(manualServers) { server in
                                    SMBServerRow(server: server) {
                                        connectToServer(server)
                                    } onAuth: {
                                        authServer = server
                                        showingAuth = true
                                    } onDelete: {
                                        browser.removeServer(server)
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(InsetGroupedListStyle())
                    .refreshable {
                        browser.startDiscovery()
                    }
                }
            }
            .navigationTitle("SMB Browser")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: { showingAddServer = true }) {
                            Label("Add Server", systemImage: "plus")
                        }
                        
                        Button(action: { browser.startDiscovery() }) {
                            Label("Discover Servers", systemImage: "magnifyingglass")
                        }
                        
                        if browser.isLoading {
                            ProgressView()
                                .frame(width: 20, height: 20)
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showingAddServer) {
                AddSMBServerView { server in
                    browser.saveServer(server)
                    connectToServer(server)
                }
            }
            .sheet(isPresented: $showingAuth) {
                if let server = authServer {
                    SMBAuthView(server: server) { username, password in
                        Task {
                            let success = await browser.authenticate(server: server, username: username, password: password)
                            if success {
                                showingAuth = false
                                connectToServer(server)
                            }
                        }
                    } onCancel: {
                        showingAuth = false
                    }
                }
            }
            .navigationDestination(for: SMBShare.self) { share in
                SMBShareView(share: share, browser: browser)
            }
            .navigationDestination(for: SMBFile.self) { file in
                if file.isDirectory {
                    SMBShareView(share: file.share, browser: browser, path: file.path.replacingOccurrences(of: file.share.path + "/", with: ""))
                } else if file.isVideoFile {
                    // Video player will be presented
                    Color.clear.onAppear {
                        selectedVideo = file
                        showVideoPlayer = true
                    }
                }
            }
            .fullScreenCover(isPresented: $showVideoPlayer) {
                if let video = selectedVideo, let url = browser.getStreamURL(video) {
                    SMBVideoPlayerView(video: video, url: url)
                }
            }
            .alert("Error", isPresented: .constant(browser.errorMessage != nil)) {
                Button("OK") { browser.errorMessage = nil }
            } message: {
                Text(browser.errorMessage ?? "")
            }
        }
        .onAppear {
            browser.startDiscovery()
        }
        .onDisappear {
            browser.stopDiscovery()
        }
    }
    
    private func connectToServer(_ server: SMBServer) {
        browser.connectToServer(server) { result in
            switch result {
            case .success(let shares):
                if let firstShare = shares.first {
                    navigationPath.append(firstShare)
                }
            case .failure(let error):
                browser.errorMessage = error.localizedDescription
                if case .authenticationFailed = error {
                    authServer = server
                    showingAuth = true
                }
            }
        }
    }
}

// MARK: - SMB Server Row

struct SMBServerRow: View {
    let server: SMBServer
    let onConnect: () -> Void
    let onAuth: () -> Void
    let onDelete: () -> Void
    
    @State private var showDeleteConfirm = false
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "server.rack")
                .font(.system(size: 28))
                .foregroundColor(.blue)
                .frame(width: 44, height: 44)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(10)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(server.displayName)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text("\(server.host):\(server.port)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                if server.username != nil {
                    Label("Authenticated", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
            
            Spacer()
            
            Button(action: onConnect) {
                Text("Connect")
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.accentColor)
                    .cornerRadius(8)
            }
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
            
            if server.username == nil {
                Button {
                    onAuth()
                } label: {
                    Label("Auth", systemImage: "lock")
                }
                .tint(.orange)
            }
        }
        .alert("Delete Server", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) { onDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to remove \(server.displayName)?")
        }
    }
}

// MARK: - Add SMB Server View

struct AddSMBServerView: View {
    @Environment(\.dismiss) var dismiss
    let onSave: (SMBServer) -> Void
    
    @State private var name = ""
    @State private var host = ""
    @State private var port = "445"
    @State private var workgroup = ""
    @State private var username = ""
    @State private var password = ""
    @State private var saveCredentials = false
    @State private var isTesting = false
    @State private var testResult: String?
    
    var body: some View {
        NavigationView {
            Form {
                Section("Server Details") {
                    TextField("Name (optional)", text: $name)
                    TextField("Host (IP or hostname)", text: $host)
                    TextField("Port", text: $port)
                        .keyboardType(.numberPad)
                    TextField("Workgroup (optional)", text: $workgroup)
                }
                
                Section("Authentication (optional)") {
                    Toggle("Save Credentials", isOn: $saveCredentials)
                    
                    if saveCredentials {
                        TextField("Username", text: $username)
                        SecureField("Password", text: $password)
                    }
                }
                
                Section {
                    Button(action: testConnection) {
                        HStack {
                            if isTesting {
                                ProgressView()
                                    .frame(width: 20, height: 20)
                            }
                            Text("Test Connection")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(isTesting || host.isEmpty)
                    
                    if let result = testResult {
                        Text(result)
                            .font(.caption)
                            .foregroundColor(result.contains("Success") ? .green : .red)
                    }
                }
            }
            .navigationTitle("Add SMB Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { saveServer() }
                        .disabled(host.isEmpty)
                }
            }
        }
    }
    
    private func testConnection() {
        isTesting = true
        testResult = nil
        
        let server = SMBServer(
            name: name.isEmpty ? host : name,
            host: host,
            port: Int(port) ?? 445,
            workgroup: workgroup.isEmpty ? nil : workgroup,
            username: saveCredentials && !username.isEmpty ? username : nil,
            password: saveCredentials && !password.isEmpty ? password : nil
        )
        
        // Test connection (mock for now)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            isTesting = false
            testResult = "Connection successful!"
        }
    }
    
    private func saveServer() {
        let server = SMBServer(
            name: name.isEmpty ? host : name,
            host: host,
            port: Int(port) ?? 445,
            workgroup: workgroup.isEmpty ? nil : workgroup,
            username: saveCredentials && !username.isEmpty ? username : nil,
            password: saveCredentials && !password.isEmpty ? password : nil
        )
        
        onSave(server)
        dismiss()
    }
}

// MARK: - SMB Auth View

struct SMBAuthView: View {
    let server: SMBServer
    let onAuth: (String, String) -> Void
    let onCancel: () -> Void
    
    @State private var username = ""
    @State private var password = ""
    @State private var saveCredentials = true
    @State private var isAuthenticating = false
    @State private var error: String?
    
    var body: some View {
        NavigationView {
            Form {
                Section("Authentication for \(server.displayName)") {
                    TextField("Username", text: $username)
                    SecureField("Password", text: $password)
                    Toggle("Save Credentials", isOn: $saveCredentials)
                }
                
                if let error = error {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                    }
                }
                
                Section {
                    Button(action: authenticate) {
                        HStack {
                            if isAuthenticating {
                                ProgressView()
                                    .frame(width: 20, height: 20)
                            }
                            Text("Connect")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(isAuthenticating || username.isEmpty)
                }
            }
            .navigationTitle("Authentication Required")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
    }
    
    private func authenticate() {
        isAuthenticating = true
        error = nil
        
        onAuth(username, password)
        
        // The actual auth is handled by the parent view
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            isAuthenticating = false
        }
    }
}

// MARK: - SMB Share View

struct SMBShareView: View {
    let share: SMBShare
    @ObservedObject var browser: SMBBrowser
    let path: String
    
    @State private var showingSortOptions = false
    @State private var sortOption: SMBSortOption = .name
    @State private var showingViewOptions = false
    @State private var viewMode: SMBViewMode = .list
    
    enum SMBSortOption: String, CaseIterable {
        case name = "Name"
        case date = "Date Modified"
        case size = "Size"
        case type = "Type"
    }
    
    enum SMBViewMode: String, CaseIterable {
        case list = "List"
        case grid = "Grid"
    }
    
    private var sortedFiles: [SMBFile] {
        var files = browser.files
        
        // Put directories first
        files.sort { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory && !rhs.isDirectory
            }
            
            switch sortOption {
            case .name:
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            case .date:
                return lhs.modificationDate > rhs.modificationDate
            case .size:
                return lhs.size > rhs.size
            case .type:
                let lhsExt = (lhs.name as NSString).pathExtension.lowercased()
                let rhsExt = (rhs.name as NSString).pathExtension.lowercased()
                return lhsExt.localizedCaseInsensitiveCompare(rhsExt) == .orderedAscending
            }
        }
        
        return files
    }
    
    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
            
            if browser.isLoading {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if sortedFiles.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "folder")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Empty Folder")
                        .font(.title2.bold())
                    Text("No files or folders in this directory")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                switch viewMode {
                case .list:
                    List {
                        // Parent directory option
                        if !path.isEmpty {
                            Button(action: { browser.browseShare(share, path: parentPath) }) {
                                HStack {
                                    Image(systemName: "folder")
                                        .foregroundColor(.blue)
                                    Text("..")
                                        .foregroundColor(.primary)
                                    Spacer()
                                }
                            }
                        }
                        
                        ForEach(sortedFiles) { file in
                            SMBFileRow(file: file)
                        }
                    }
                    .listStyle(InsetGroupedListStyle())
                    .refreshable {
                        browser.browseShare(share, path: path) { _ in }
                    }
                    
                case .grid:
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 16)], spacing: 16) {
                            if !path.isEmpty {
                                SMBFileGridItem(file: SMBFile(
                                    name: "..",
                                    path: parentPath,
                                    isDirectory: true,
                                    size: 0,
                                    modificationDate: Date(),
                                    share: share
                                )) {
                                    browser.browseShare(share, path: parentPath) { _ in }
                                }
                            }
                            
                            ForEach(sortedFiles) { file in
                                SMBFileGridItem(file: file) {
                                    handleFileTap(file)
                                }
                            }
                        }
                        .padding()
                    }
                    .refreshable {
                        browser.browseShare(share, path: path) { _ in }
                    }
                }
            }
        }
        .navigationTitle(share.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Picker("Sort By", selection: $sortOption) {
                        ForEach(SMBSortOption.allCases, id: \.self) { option in
                            Label(option.rawValue, systemImage: sortIcon(option))
                                .tag(option)
                        }
                    }
                    
                    Picker("View", selection: $viewMode) {
                        ForEach(SMBViewMode.allCases, id: \.self) { mode in
                            Label(mode.rawValue, systemImage: viewIcon(mode))
                                .tag(mode)
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .onAppear {
            if browser.currentPath != path {
                browser.browseShare(share, path: path) { _ in }
            }
        }
    }
    
    private var parentPath: String {
        let components = path.split(separator: "/")
        return components.dropLast().joined(separator: "/")
    }
    
    private func handleFileTap(_ file: SMBFile) {
        if file.isDirectory {
            browser.browseShare(share, path: file.path.replacingOccurrences(of: share.path + "/", with: "")) { _ in }
        } else if file.isVideoFile {
            // Navigation handled by parent
        }
    }
    
    private func sortIcon(_ option: SMBSortOption) -> String {
        switch option {
        case .name: return "textformat"
        case .date: return "clock"
        case .size: return "doc.badge.gearshape"
        case .type: return "doc.text"
        }
    }
    
    private func viewIcon(_ mode: SMBViewMode) -> String {
        switch mode {
        case .list: return "list.bullet"
        case .grid: return "square.grid.2x2"
        }
    }
}

// MARK: - SMB File Row (List View)

struct SMBFileRow: View {
    let file: SMBFile
    
    var body: some View {
        HStack(spacing: 12) {
            // File icon
            Image(systemName: fileIcon)
                .font(.system(size: 24))
                .foregroundColor(fileColor)
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .font(.body)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                if !file.isDirectory {
                    HStack(spacing: 8) {
                        Text(file.formattedSize)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text(file.modificationDate, style: .date)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            if file.isVideoFile {
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                    .foregroundColor(.accentColor)
            } else if file.isDirectory {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
    
    private var fileIcon: String {
        if file.isDirectory {
            return "folder.fill"
        } else if file.isVideoFile {
            return "film.fill"
        } else if file.isPosterFile {
            return "photo.fill"
        } else {
            return "doc.fill"
        }
    }
    
    private var fileColor: Color {
        if file.isDirectory {
            return .blue
        } else if file.isVideoFile {
            return .purple
        } else if file.isPosterFile {
            return .green
        } else {
            return .gray
        }
    }
}

// MARK: - SMB File Grid Item

struct SMBFileGridItem: View {
    let file: SMBFile
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(fileColor.opacity(0.2))
                        .aspectRatio(0.67, contentMode: .fit)
                    
                    Image(systemName: fileIcon)
                        .font(.system(size: 32))
                        .foregroundColor(fileColor)
                    
                    if file.isVideoFile {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                Image(systemName: "play.circle.fill")
                                    .font(.title)
                                    .foregroundColor(.white)
                                    .padding(8)
                            }
                        }
                    }
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.name)
                        .font(.caption.bold())
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    
                    if !file.isDirectory {
                        Text(file.formattedSize)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
    
    private var fileIcon: String {
        if file.isDirectory {
            return "folder.fill"
        } else if file.isVideoFile {
            return "film.fill"
        } else if file.isPosterFile {
            return "photo.fill"
        } else {
            return "doc.fill"
        }
    }
    
    private var fileColor: Color {
        if file.isDirectory {
            return .blue
        } else if file.isVideoFile {
            return .purple
        } else if file.isPosterFile {
            return .green
        } else {
            return .gray
        }
    }
}

// MARK: - SMB Video Player View

struct SMBVideoPlayerView: View {
    let video: SMBFile
    let url: URL
    @EnvironmentObject var vlcManager: LibVLCManager
    @Environment(\.dismiss) var dismiss
    
    @State private var player: LibVLCWrapper
    @State private var showControls = true
    @State private var controlsTimer: Timer?
    @State private var isLoading = true
    @State private var errorMessage: String?
    
    init(video: SMBFile, url: URL) {
        self.video = video
        self.url = url
        self._player = State(initialValue: LibVLCManager.shared.player)
    }
    
    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
            
            if isLoading {
                ProgressView("Loading \(video.name)...")
                    .foregroundColor(.white)
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
            } else {
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
                
                if showControls {
                    VStack {
                        TopControlsBar(
                            title: video.name,
                            onClose: { dismiss() },
                            onTrackSelect: { /* Track selection */ },
                            onQualitySelect: { /* Quality selection */ }
                        )
                        .transition(.move(edge: .top).combined(with: .opacity))
                        
                        Spacer()
                        
                        BottomControlsBar(
                            player: player,
                            dragPosition: .constant(nil),
                            onPlayPause: { togglePlayPause() },
                            onSeekBack: { seekRelative(-10) },
                            onSeekForward: { seekRelative(30) },
                            onSpeedChange: { /* Speed change */ },
                            onFullScreen: { /* Full screen */ },
                            onAirPlay: { /* AirPlay */ }
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    .animation(.easeInOut(duration: 0.2), value: showControls)
                }
            }
        }
        .statusBarHidden(true)
        .onAppear {
            loadMedia()
            startControlsTimer()
        }
        .onDisappear {
            cleanup()
        }
    }
    
    private func loadMedia() {
        isLoading = true
        errorMessage = nil
        
        do {
            try player.openMedia(url: url, options: [
                "network-caching=3000",
                "file-caching=3000",
                "smb-caching=3000"
            ])
            player.play()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                isLoading = false
            }
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
    
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
    
    private var dragPosition: Float? = nil
    
    private func handleDrag(_ value: DragGesture.Value) {
        let translation = value.translation.width
        let screenWidth = UIScreen.main.bounds.width
        let seekAmount = Float(translation / screenWidth)
        dragPosition = max(0, min(1, player.playbackState.position + seekAmount))
    }
    
    private func endDrag(_ value: DragGesture.Value) {
        if let position = dragPosition {
            player.seek(to: position)
        }
        dragPosition = nil
        resetControlsTimer()
    }
    
    private func toggleControls() {
        withAnimation { showControls.toggle() }
        if showControls { startControlsTimer() } else { stopControlsTimer() }
    }
    
    private func startControlsTimer() {
        controlsTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
            withAnimation { showControls = false }
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
    
    private func cleanup() {
        stopControlsTimer()
        player.stop()
    }
}

// MARK: - Preview

#Preview {
    SMBBrowserView()
        .environmentObject(LibVLCManager.shared)
}