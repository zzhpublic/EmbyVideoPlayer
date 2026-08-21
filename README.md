# EmbyVideoPlayer

A standalone iOS/tvOS/macOS video player app with:
- **Emby Integration** - Poster flow UI, library browsing, playback
- **SMB Network Browser** - Discover and browse SMB shares
- **LibVLC Player** - Hardware-accelerated playback with full controls
- **Local Files** - Browse and play local videos

## Requirements

- iOS 16+ / tvOS 16+ / macOS 13+
- Xcode 15+
- Swift 5.9+

## Dependencies

```bash
# Resolved via Swift Package Manager
- MobileVLCKit (videolan/libvlc-ios)
- Kingfisher (onevcat/Kingfisher)
```

## Building

```bash
# Open in Xcode
open Package.swift

# Or build from command line
swift build
```

## Features

### Emby
- Server discovery & authentication
- Poster flow home screen (Continue Watching, Next Up, Latest)
- Movies, Series, Episodes, Music, Photos libraries
- Direct play / Transcode support
- Subtitle & audio track selection
- Search

### SMB
- Bonjour service discovery (`_smb._tcp.`)
- Manual server configuration
- Credential storage (Keychain)
- Share browsing with list/grid views
- Video file detection and streaming

### LibVLC Player
- Hardware decoding
- Variable playback speed (0.25x - 4x)
- Track selection (video, audio, subtitles)
- Aspect ratio & crop controls
- Gesture controls (tap for controls, drag to seek)
- External subtitle loading (.srt, .vtt, .ass)
- Snapshot capture

### Local Files
- Document picker for folder access
- Recursive directory browsing
- Video file playback

## Project Structure

```
EmbyVideoPlayer/
├── Package.swift
├── App/
│   ├── EmbyVideoPlayerApp.swift
│   └── Info.plist
├── Sources/
│   ├── Emby/
│   │   └── EmbyAPI.swift          # Emby API client
│   ├── SMB/
│   │   └── SMBBrowser.swift       # SMB network browser
│   ├── VideoPlayer/
│   │   └── LibVLCWrapper.swift    # LibVLC Swift wrapper
│   └── Views/
│       ├── MainView.swift         # Main tab view
│       ├── Browser/
│       │   ├── PosterFlowView.swift
│       │   └── SMBBrowserView.swift
│       └── Player/
│           └── VideoPlayerView.swift
└── Tests/
    └── EmbyVideoPlayerTests.swift
```

## Entitlements Required

For SMB and network access:
- `com.apple.security.network.client`
- `com.apple.security.files.user-selected.read-only`

For background audio:
- Background Modes → "Audio, AirPlay, and Picture in Picture"

## License

MIT License