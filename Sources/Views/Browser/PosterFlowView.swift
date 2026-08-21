//
//  PosterFlowView.swift
//  SideStore
//
//  Created for Emby poster flow video player
//

import SwiftUI
import Kingfisher
import EmbyVideoPlayer

// Helper for conditional iOS 17+ modifiers
extension View {
    @ViewBuilder
    func ifAvailable(_ transform: (Self) -> some View) -> some View {
        transform(self)
    }
}

// MARK: - Poster Flow Models

struct PosterItem: Identifiable, Hashable {
    let id: String
    let title: String
    let posterURL: URL?
    let backdropURL: URL?
    let itemType: String // Movie, Series, Episode, etc.
    let year: Int?
    let rating: Double?
    let duration: TimeInterval?
    let genres: [String]?
    let overview: String?
    let parentId: String?
    
    init(from embyItem: EmbyItem) {
        self.id = embyItem.id
        self.title = embyItem.name
        self.posterURL = embyItem.posterURL.flatMap(URL.init)
        self.backdropURL = embyItem.backdropURL.flatMap(URL.init)
        self.itemType = embyItem.type
        self.year = embyItem.productionYear
        self.rating = embyItem.communityRating
        self.duration = embyItem.runtime
        self.genres = embyItem.genreItems
        self.overview = embyItem.overview
        self.parentId = embyItem.parentId
    }
}

enum PosterFlowLayout {
    case horizontal(rowHeight: CGFloat = 200)
    case grid(columns: Int = 3, aspectRatio: CGFloat = 0.67) // poster aspect ratio
    case carousel(itemWidth: CGFloat = 150, itemHeight: CGFloat = 225)
}

// MARK: - Poster Card View

struct PosterCardView: View {
    let item: PosterItem
    let layout: PosterFlowLayout
    let onTap: () -> Void
    let onLongPress: (() -> Void)?
    
    @State private var isPressed = false
    @State private var imageLoaded = false
    
    private var cardSize: CGSize {
        switch layout {
        case .horizontal(let rowHeight):
            let aspectRatio: CGFloat = 0.67
            return CGSize(width: rowHeight * aspectRatio, height: rowHeight)
        case .grid(_, let aspectRatio):
            // Width will be determined by grid
            return CGSize(width: 150, height: 150 / aspectRatio)
        case .carousel(let itemWidth, let itemHeight):
            return CGSize(width: itemWidth, height: itemHeight)
        }
    }
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                // Poster Image
                ZStack(alignment: .bottomTrailing) {
                    if let posterURL = item.posterURL {
                        KFImage(posterURL)
                            .placeholder {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.3))
                                    .overlay(
                                        Image(systemName: "photo")
                                            .font(.system(size: 24))
                                            .foregroundColor(.gray)
                                    )
                            }
                                            .onSuccess { _ in
                                                imageLoaded = true
                                            }
                                            .fade(duration: 0.25)
                                            .resizable()
                                            .aspectRatio(0.67, contentMode: .fill)
                                            .frame(width: cardSize.width, height: cardSize.height)
                                            .clipped()
                                            .cornerRadius(8)
                    } else {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: cardSize.width, height: cardSize.height)
                            .cornerRadius(8)
                            .overlay(
                                Image(systemName: "photo")
                                    .font(.system(size: 24))
                                    .foregroundColor(.gray)
                            )
                    }
                    
                    // Media type badge
                    if item.itemType == "Episode" {
                        Text("EP")
                            .font(.caption2.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue)
                            .cornerRadius(4)
                            .padding(8)
                    } else if item.itemType == "Movie" {
                        Text("MOVIE")
                            .font(.caption2.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green)
                            .cornerRadius(4)
                            .padding(8)
                    }
                    
                    // Duration badge
                    if let duration = item.duration {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                Text(formatDuration(duration))
                                    .font(.caption2.bold())
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.black.opacity(0.7))
                                    .cornerRadius(4)
                                    .padding(8)
                            }
                        }
                    }
                }
                
                // Title and metadata
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.subheadline.bold())
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    
                    HStack(spacing: 8) {
                        if let year = item.year {
                            Text("\(year)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        if let rating = item.rating {
                            HStack(spacing: 2) {
                                Image(systemName: "star.fill")
                                    .font(.caption)
                                    .foregroundColor(.yellow)
                                Text(String(format: "%.1f", rating))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        if let genres = item.genres?.prefix(2) {
                            Text(genres.joined(separator: " · "))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .frame(width: cardSize.width, alignment: .leading)
            }
        }
        .buttonStyle(PosterCardButtonStyle(isPressed: $isPressed))
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: isPressed)
        .contextMenu {
            if let onLongPress = onLongPress {
                Button("More Options", action: onLongPress)
            }
            
            Button("Play") {
                onTap()
            }
            
            if item.itemType == "Series" {
                Button("View Seasons") {
                    onLongPress?()
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title)\(item.year.map { " (\($0))" } ?? "")\(item.rating.map { ", rating \(String(format: "%.1f", $0))" } ?? "")")
        .accessibilityAddTraits(.isButton)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

struct PosterCardButtonStyle: ButtonStyle {
    @Binding var isPressed: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
                .onChange(of: configuration.isPressed) { pressed in
                isPressed = pressed
            }
    }
}

// MARK: - Horizontal Poster Flow

struct HorizontalPosterFlow: View {
    let title: String
    let items: [PosterItem]
    let layout: PosterFlowLayout
    let onItemTap: (PosterItem) -> Void
    let onItemLongPress: ((PosterItem) -> Void)?
    let seeAllAction: (() -> Void)?
    
    @State private var scrollPosition: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack {
                Text(title)
                    .font(.title2.bold())
                    .foregroundColor(.primary)
                
                Spacer()
                
                if let seeAllAction = seeAllAction {
                    Button("See All", action: seeAllAction)
                        .font(.subheadline)
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal)
            
            // Horizontal scroll
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    ForEach(items) { item in
                        PosterCardView(
                            item: item,
                            layout: layout,
                            onTap: { onItemTap(item) },
                            onLongPress: { onItemLongPress?(item) }
                        )
                        .id(item.id)
                    }
                }
                .padding(.horizontal)
            }
                            .ifAvailable { view in
                                if #available(iOS 17.0, *) {
                                    view.scrollTargetLayout().scrollPosition(id: $scrollPosition)
                                } else {
                                    view
                                }
                            }
        }
    }
}

// MARK: - Grid Poster Flow

struct GridPosterFlow: View {
    let title: String
    let items: [PosterItem]
    let layout: PosterFlowLayout
    let onItemTap: (PosterItem) -> Void
    let onItemLongPress: ((PosterItem) -> Void)?
    let seeAllAction: (() -> Void)?
    
    private var columns: [GridItem] {
        switch layout {
        case .grid(let columns, _):
            return Array(repeating: GridItem(.flexible(), spacing: 16), count: columns)
        default:
            return Array(repeating: GridItem(.flexible(), spacing: 16), count: 3)
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack {
                Text(title)
                    .font(.title2.bold())
                    .foregroundColor(.primary)
                
                Spacer()
                
                if let seeAllAction = seeAllAction {
                    Button("See All", action: seeAllAction)
                        .font(.subheadline)
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal)
            
            // Grid
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(items) { item in
                    PosterCardView(
                        item: item,
                        layout: layout,
                        onTap: { onItemTap(item) },
                        onLongPress: { onItemLongPress?(item) }
                    )
                }
            }
            .padding(.horizontal)
        }
    }
}

// MARK: - Carousel Poster Flow

struct CarouselPosterFlow: View {
    let title: String
    let items: [PosterItem]
    let layout: PosterFlowLayout
    let onItemTap: (PosterItem) -> Void
    let onItemLongPress: ((PosterItem) -> Void)?
    let seeAllAction: (() -> Void)?
    
    @State private var currentIndex = 0
    @State private var dragOffset: CGFloat = 0
    
    private var itemWidth: CGFloat {
        switch layout {
        case .carousel(let width, _): return width
        default: return 150
        }
    }
    
    private var itemHeight: CGFloat {
        switch layout {
        case .carousel(_, let height): return height
        default: return 225
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack {
                Text(title)
                    .font(.title2.bold())
                    .foregroundColor(.primary)
                
                Spacer()
                
                if let seeAllAction = seeAllAction {
                    Button("See All", action: seeAllAction)
                        .font(.subheadline)
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal)
            
            // Carousel
            GeometryReader { geometry in
                let visibleCount = max(1, Int(geometry.size.width / (itemWidth + 16)))
                
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 16) {
                        ForEach(items.indices, id: \.self) { index in
                            let item = items[index]
                            let isCurrent = index == currentIndex
                            
                            PosterCardView(
                                item: item,
                                layout: .carousel(itemWidth: itemWidth, itemHeight: itemHeight),
                                onTap: { onItemTap(item) },
                                onLongPress: { onItemLongPress?(item) }
                            )
                            .scaleEffect(isCurrent ? 1.0 : 0.9)
                            .opacity(isCurrent ? 1.0 : 0.7)
                            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: currentIndex)
                        }
                    }
                    .padding(.horizontal, (geometry.size.width - itemWidth) / 2)
                    .scrollTargetLayout()
                }
                                    .ifAvailable { view in
                                        if #available(iOS 17.0, *) {
                                            view.scrollTargetBehavior(.viewAligned)
                                                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                                                    geometry.contentOffset.x + geometry.contentInsets.leading
                                                } action: { _, newOffset in
                                                    let newIndex = Int(round(newOffset / (itemWidth + 16)))
                                                    if newIndex >= 0 && newIndex < items.count {
                                                        currentIndex = newIndex
                                                    }
                                                }
                                        } else {
                                            view
                                        }
                                    }
            }
            .frame(height: itemHeight + 80) // Account for title
        }
    }
}

// MARK: - Main Poster Flow Container

struct PosterFlowView: View {
    @EnvironmentObject var embyClient: EmbyAPIClient
    
    @State private var libraries: [PosterItem] = []
    @State private var selectedLibrary: PosterItem?
    @State private var libraryItems: [PosterItem] = []
    @State private var continueWatching: [PosterItem] = []
    @State private var nextUp: [PosterItem] = []
    @State private var latestMovies: [PosterItem] = []
    @State private var latestEpisodes: [PosterItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    @State private var navigationPath = NavigationPath()
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()
                
                if isLoading && libraries.isEmpty {
                    ProgressView("Loading libraries...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 24) {
                            // Continue Watching
                            if !continueWatching.isEmpty {
                                HorizontalPosterFlow(
                                    title: "Continue Watching",
                                    items: continueWatching,
                                    layout: .horizontal(rowHeight: 180),
                                    onItemTap: { item in navigateToDetail(item) },
                                    onItemLongPress: { item in showItemOptions(item) },
                                    seeAllAction: { navigateToSection("Continue Watching", items: continueWatching) }
                                )
                            }
                            
                            // Next Up Episodes
                            if !nextUp.isEmpty {
                                HorizontalPosterFlow(
                                    title: "Next Up",
                                    items: nextUp,
                                    layout: .horizontal(rowHeight: 180),
                                    onItemTap: { item in navigateToDetail(item) },
                                    onItemLongPress: { item in showItemOptions(item) },
                                    seeAllAction: { navigateToSection("Next Up", items: nextUp) }
                                )
                            }
                            
                            // Latest Movies
                            if !latestMovies.isEmpty {
                                HorizontalPosterFlow(
                                    title: "Latest Movies",
                                    items: latestMovies,
                                    layout: .horizontal(rowHeight: 200),
                                    onItemTap: { item in navigateToDetail(item) },
                                    onItemLongPress: { item in showItemOptions(item) },
                                    seeAllAction: { navigateToSection("Latest Movies", items: latestMovies) }
                                )
                            }
                            
                            // Latest Episodes
                            if !latestEpisodes.isEmpty {
                                HorizontalPosterFlow(
                                    title: "Latest Episodes",
                                    items: latestEpisodes,
                                    layout: .horizontal(rowHeight: 180),
                                    onItemTap: { item in navigateToDetail(item) },
                                    onItemLongPress: { item in showItemOptions(item) },
                                    seeAllAction: { navigateToSection("Latest Episodes", items: latestEpisodes) }
                                )
                            }
                            
                            // Libraries
                            if !libraries.isEmpty {
                                GridPosterFlow(
                                    title: "Libraries",
                                    items: libraries,
                                    layout: .grid(columns: 2, aspectRatio: 0.67),
                                    onItemTap: { item in navigateToLibrary(item) },
                                    onItemLongPress: { item in showItemOptions(item) },
                                    seeAllAction: nil
                                )
                            }
                        }
                        .padding(.vertical)
                    }
                    .refreshable {
                        await loadHomeData()
                    }
                }
            }
            .navigationTitle("Emby")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("Search", systemImage: "magnifyingglass") {
                            // Navigate to search
                        }
                        Button("Servers", systemImage: "server.rack") {
                            // Navigate to server selection
                        }
                        Button("Settings", systemImage: "gear") {
                            // Navigate to settings
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .navigationDestination(for: PosterItem.self) { item in
                ItemDetailView(item: item)
            }
            .navigationDestination(for: String.self) { section in
                SectionView(section: section)
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .task {
            await loadHomeData()
        }
    }
    
    private func loadHomeData() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            async let libs = embyClient.getLibraries()
            async let cw = embyClient.getItems(parentId: "", includeItemTypes: "Movie,Episode", sortBy: "DatePlayed", limit: 20)
            async let nu = embyClient.getItems(parentId: "", includeItemTypes: "Episode", sortBy: "DatePlayed", limit: 10)
            async let lm = embyClient.getItems(parentId: "", includeItemTypes: "Movie", sortBy: "DateCreated", limit: 10)
            async let le = embyClient.getItems(parentId: "", includeItemTypes: "Episode", sortBy: "DateCreated", limit: 10)
            
            let (librariesResult, cwResult, nuResult, lmResult, leResult) = await (libs, cw, nu, lm, le)
            
            if let librariesResult = librariesResult {
                self.libraries = librariesResult.map { PosterItem(from: $0) }
            }
            
            if let cwResult = cwResult {
                self.continueWatching = cwResult.map { PosterItem(from: $0) }
            }
            
            if let nuResult = nuResult {
                self.nextUp = nuResult.map { PosterItem(from: $0) }
            }
            
            if let lmResult = lmResult {
                self.latestMovies = lmResult.map { PosterItem(from: $0) }
            }
            
            if let leResult = leResult {
                self.latestEpisodes = leResult.map { PosterItem(from: $0) }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    private func navigateToDetail(_ item: PosterItem) {
        navigationPath.append(item)
    }
    
    private func navigateToLibrary(_ item: PosterItem) {
        selectedLibrary = item
        Task {
            await loadLibraryItems(item)
        }
    }
    
    private func navigateToSection(_ title: String, items: [PosterItem]) {
        navigationPath.append(title)
    }
    
    private func showItemOptions(_ item: PosterItem) {
        // Show action sheet or context menu
    }
    
    private func loadLibraryItems(_ library: PosterItem) async {
        guard let items = await embyClient.getItems(parentId: library.id) else { return }
        libraryItems = items.map { PosterItem(from: $0) }
    }
}

// MARK: - Item Detail View

struct ItemDetailView: View {
    let item: PosterItem
    @EnvironmentObject var embyClient: EmbyAPIClient
    @EnvironmentObject var vlcManager: LibVLCWrapper
    
    @State private var seasons: [PosterItem] = []
    @State private var episodes: [PosterItem] = []
    @State private var similar: [PosterItem] = []
    @State private var isLoading = false
    @State private var showPlayer = false
    @State private var playbackInfo: EmbyPlaybackInfo?
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Backdrop
                if let backdropURL = item.backdropURL {
                    KFImage(backdropURL)
                        .resizable()
                        .aspectRatio(16/9, contentMode: .fill)
                        .frame(height: 250)
                        .clipped()
                        .overlay(
                            LinearGradient(
                                colors: [.clear, .black.opacity(0.8)],
                                startPoint: .center,
                                endPoint: .bottom
                            )
                        )
                        .overlay(alignment: .bottomLeading) {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(item.title)
                                        .font(.title.bold())
                                        .foregroundColor(.white)
                                    
                                    if let year = item.year {
                                        Text("\(year)")
                                            .font(.title3)
                                            .foregroundColor(.white.opacity(0.8))
                                    }
                                }
                                
                                HStack(spacing: 16) {
                                    if let rating = item.rating {
                                        Label(String(format: "%.1f", rating), systemImage: "star.fill")
                                            .foregroundColor(.yellow)
                                    }
                                    
                                    if let duration = item.duration {
                                        Label(formatDuration(duration), systemImage: "clock")
                                            .foregroundColor(.white)
                                    }
                                    
                                    if let genres = item.genres?.prefix(3) {
                                        Text(genres.joined(separator: " · "))
                                            .foregroundColor(.white.opacity(0.8))
                                    }
                                }
                                .font(.subheadline)
                            }
                            .padding()
                        }
                }
                
                // Metadata and actions
                VStack(alignment: .leading, spacing: 16) {
                    if let overview = item.overview {
                        Text(overview)
                            .font(.body)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                    }
                    
                    // Action buttons
                    HStack(spacing: 16) {
                        Button(action: playItem) {
                            Label("Play", systemImage: "play.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        
                        Button(action: { /* Resume or play from beginning */ }) {
                            Label("Resume", systemImage: "play.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                    .padding(.horizontal)
                    
                    // Content based on type
                    if item.itemType == "Series" {
                        if !seasons.isEmpty {
                            HorizontalPosterFlow(
                                title: "Seasons",
                                items: seasons,
                                layout: .horizontal(rowHeight: 160),
                                onItemTap: { season in navigateToSeason(season) },
                                onItemLongPress: nil,
                                seeAllAction: nil
                            )
                        }
                    } else if item.itemType == "Season" {
                        if !episodes.isEmpty {
                            GridPosterFlow(
                                title: "Episodes",
                                items: episodes,
                                layout: .grid(columns: 3, aspectRatio: 1.0),
                                onItemTap: { episode in playEpisode(episode) },
                                onItemLongPress: nil,
                                seeAllAction: nil
                            )
                        }
                    }
                    
                    // Similar content
                    if !similar.isEmpty {
                        HorizontalPosterFlow(
                            title: "Similar",
                            items: similar,
                            layout: .horizontal(rowHeight: 180),
                            onItemTap: { item in /* Navigate */ },
                            onItemLongPress: nil,
                            seeAllAction: nil
                        )
                    }
                }
                .padding(.vertical)
            }
        }
        .ignoresSafeArea(edges: .top)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadDetailData()
        }
        .fullScreenCover(isPresented: $showPlayer) {
            if let playbackInfo = playbackInfo {
                VideoPlayerView(playbackInfo: playbackInfo)
            }
        }
    }
    
    private func loadDetailData() async {
        isLoading = true
        defer { isLoading = false }
        
        if item.itemType == "Series" {
            if let seasonsResult = await embyClient.getSeasons(seriesId: item.id) {
                self.seasons = seasonsResult.map { PosterItem(from: $0) }
            }
        } else if item.itemType == "Season" {
            if let episodesResult = await embyClient.getEpisodes(seriesId: item.parentId ?? "") {
                self.episodes = episodesResult.map { PosterItem(from: $0) }
            }
        }
    }
    
    private func playItem() {
        Task {
            if let info = await embyClient.getPlaybackInfo(itemId: item.id) {
                self.playbackInfo = info
                self.showPlayer = true
            }
        }
    }
    
    private func playEpisode(_ episode: PosterItem) {
        Task {
            if let info = await embyClient.getPlaybackInfo(itemId: episode.id) {
                self.playbackInfo = info
                self.showPlayer = true
            }
        }
    }
    
    private func navigateToSeason(_ season: PosterItem) {
        // Navigate to season detail
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

// MARK: - Section View

struct SectionView: View {
    let section: String
    @EnvironmentObject var embyClient: EmbyAPIClient
    @State private var items: [PosterItem] = []
    @State private var isLoading = false
    
    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GridPosterFlow(
                    title: section,
                    items: items,
                    layout: .grid(columns: 3, aspectRatio: 0.67),
                    onItemTap: { item in /* Navigate */ },
                    onItemLongPress: nil,
                    seeAllAction: nil
                )
            }
        }
        .navigationTitle(section)
        .navigationBarTitleDisplayMode(.large)
        .task {
            await loadItems()
        }
    }
    
    private func loadItems() async {
        isLoading = true
        defer { isLoading = false }
        
        // Load based on section type
        // This is simplified - you'd map section names to appropriate API calls
    }
}

// MARK: - Preview

#Preview {
    PosterFlowView()
        .environmentObject(EmbyAPIClient())
        .environmentObject(LibVLCWrapper())
}