lib/
│
├── main.dart                      # App entry point, initializes services & Hive/Isar
├── app.dart                       # MaterialApp configuration and routing
│
├── models/                        # Data structures
│   ├── track_model.dart           # Defines a Track (path, title, artist, album, duration)
│   └── playlist_model.dart        # Defines a Playlist (name, list of track IDs/paths)
│
├── services/                      # Background processes & data handling
│   ├── audio_handler.dart         # Wraps audio_service/just_audio for background playback
│   ├── file_scanner_service.dart  # Logic to scan the OS for .mp3, .m4a files
│   └── storage_service.dart       # Local DB (Hive/Isar) for Favorites, Playlists, Settings
│
├── providers/                     # State management (if using Riverpod/Provider)
│   ├── library_provider.dart      # Holds the scanned list of all local songs
│   └── playback_provider.dart     # Holds current song, playing state, queue
│
├── screens/                       # Full-page views
│   ├── home_screen.dart           # Main library view (Tabs for Tracks, Albums, Folders)
│   ├── audioplayer_screen.dart    # Your current Now Playing screen
│   └── settings_screen.dart       # App settings (Sleep timer, scan folders, theme)
│
├── widgets/                       # Reusable UI components
│   ├── glass_container.dart       # Extracted _glass() widget from your player
│   ├── glass_icon_button.dart     # Extracted _glassIconButton()
│   ├── mini_player.dart           # Small playback bar to show on the HomeScreen
│   └── track_list_tile.dart       # Reusable row for displaying a song in lists
│
└── utils/                         # Global helpers
    ├── formatters.dart            # e.g., the _fmt(Duration d) method
    ├── theme.dart                 # Extracted gradients, constant colors, and text styles
    └── constants.dart             # Supported file extensions, default padding, etc.