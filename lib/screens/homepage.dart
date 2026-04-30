import 'dart:developer';
import 'dart:typed_data';
import 'dart:io';
import 'dart:ui';
import 'package:audioplayer/screens/audioplayer_screen.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_media_metadata/flutter_media_metadata.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

// ─── Supported audio extensions ─────────────────────────────────────────────
const _kSupportedExtensions = ['mp3', 'm4a', 'wav', 'flac', 'aac', 'ogg'];
const _kPrefsKey = 'audio_files'; // renamed from 'mp3_files'

// ─── Theme constants ─────────────────────────────────────────────────────────
const _kBg1 = Color(0xFF000000); // pure black
const _kBg2 = Color(0xFF0A0A0A); // near-black
const _kAccent = Color(0xFF0fbcf9);
const _kAccent2 = Color(0xFF52D7BF);
const _kGlassWhite = Color(0x0DFFFFFF); // white @ 5%
const _kBorderWhite = Color(0x1AFFFFFF); // white @ 10%
const _KFavoriteRed = Color(0xFFE63946);

class Homepage extends StatefulWidget {
  static const String routeName = '/homepage';
  const Homepage({super.key});

  @override
  State<Homepage> createState() => _HomepageState();
}

class _HomepageState extends State<Homepage> with TickerProviderStateMixin {
  // ─── State ────────────────────────────────────────────────────────────────
  List<String> _audioFiles = [];
  List<String> _allFiles = [];
  int? _currentIndex;
  PlayerState _playerState = PlayerState.stopped;
  bool _showingFavorites = false;

  // ─── Metadata cache ───────────────────────────────────────────────────────
  // Key: file path → Value: album art bytes (null = no art / not yet loaded)
  final Map<String, Uint8List?> _artCache = {};
  // Track which paths are currently being fetched so we don't double-fetch
  final Set<String> _fetching = {};

  // ─── Animation ────────────────────────────────────────────────────────────
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnim;

  // ─────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────────────────
  bool _isGlobalPlaying = false;

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);

    _loadSavedFiles();
    _loadFavorites();
    // Listen to global player state changes
    globalAudioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _isGlobalPlaying = state == PlayerState.playing;
        });
      }
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Data / Logic
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _loadSavedFiles() async {
    final prefs = await SharedPreferences.getInstance();

    // Support migration: also check old key so existing users don't lose data
    final raw =
        prefs.getStringList(_kPrefsKey) ??
        prefs.getStringList('mp3_files') ??
        [];

    // Validate: only keep files still present on device
    final valid = raw.where((f) => File(f).existsSync()).toList();

    await prefs.setStringList(_kPrefsKey, valid);
    // Remove old key if it existed
    await prefs.remove('mp3_files');

    if (mounted) {
      setState(() {
        _audioFiles = valid;
        _allFiles = valid;
        _currentIndex = null;
        _playerState = PlayerState.stopped;
      });
      _fadeController.forward(from: 0);
      _prefetchArt(valid);
    }
  }

  Future<void> _loadFavorites() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    final favs = prefs.getStringList('favList') ?? [];

    if (mounted) {
      setState(() {
        if (_showingFavorites) {
          // Toggle OFF: Show all files
          _audioFiles = _allFiles;
          _showingFavorites = false;
        } else {
          // Toggle ON: Show only favorites
          if (favs.isEmpty) {
            _showSnack(
              'No favorites yet. Tap the heart icon on a track to add it here!',
            );
            return;
          }

          // Filter _allFiles to only show ones safely stored in the favs list
          _audioFiles = _allFiles.where((path) => favs.contains(path)).toList();
          _showingFavorites = true;
        }

        // Reset player index state when switching lists
        _currentIndex = null;
        _playerState = PlayerState.stopped;
      });
    }
  }

  /// Eagerly fetches album art for all files in the background, populating
  /// [_artCache]. This means the ListView never needs to await metadata —
  /// it just reads from cache. Prevents per-row jank entirely.
  Future<void> _prefetchArt(List<String> paths) async {
    for (final path in paths) {
      if (_artCache.containsKey(path) || _fetching.contains(path)) continue;
      _fetching.add(path);
      try {
        final meta = await MetadataRetriever.fromFile(File(path));
        _artCache[path] = meta.albumArt; // null if no art — that's fine
      } catch (_) {
        _artCache[path] = null;
      } finally {
        _fetching.remove(path);
        if (mounted) setState(() {});
      }
    }
  }

  bool _isSupportedExtension(String path) {
    final ext = p.extension(path).toLowerCase().replaceFirst('.', '');
    return _kSupportedExtensions.contains(ext);
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _kSupportedExtensions,
      allowMultiple: true,
    );

    if (result == null || result.files.isEmpty) return;

    final newFiles = result.files
        .where((f) => f.path != null && _isSupportedExtension(f.path!))
        .map((f) => f.path!)
        .toList();

    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getStringList(_kPrefsKey) ?? [];

    final uniqueNew = newFiles.where((f) => !existing.contains(f)).toList();

    if (uniqueNew.isEmpty) {
      if (mounted) {
        _showSnack('All selected files are already in your library.');
      }
      return;
    }

    final all = [...existing, ...uniqueNew];
    await prefs.setStringList(_kPrefsKey, all);

    if (mounted) {
      setState(() {
        _audioFiles = all;
        _currentIndex = null;
        _playerState = PlayerState.stopped;
      });
      _prefetchArt(uniqueNew); // fetch art only for new additions
    }
  }

  Future<void> _removeFile(int index) async {
    final removed = _audioFiles.removeAt(index);
    _artCache.remove(removed);
    final prefs = await SharedPreferences.getInstance();
    prefs.setStringList(_kPrefsKey, _audioFiles);
    if (mounted) setState(() {});
    _showSnack('${p.basename(removed)} removed');
  }

  Future<void> _clearAllFiles() async {
    final confirmed = await _showConfirmDialog();
    if (!confirmed) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPrefsKey);
    _artCache.clear();
    if (mounted) {
      setState(() {
        _audioFiles.clear();
        _currentIndex = null;
      });
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF111111),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.r),
          side: BorderSide(color: _kBorderWhite),
        ),
        content: Text(
          message,
          style: TextStyle(color: Colors.white70, fontSize: 13.sp),
        ),
      ),
    );
  }

  Future<bool> _showConfirmDialog() async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: AlertDialog(
              backgroundColor: const Color(0xFF0D0D0D),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20.r),
                side: BorderSide(color: _kBorderWhite),
              ),
              title: Text(
                'Clear Library?',
                style: GoogleFonts.bakbakOne(
                  color: Colors.white,
                  fontSize: 18.sp,
                ),
              ),
              content: Text(
                'This will remove all tracks from your library. Files on your device won\'t be deleted.',
                style: TextStyle(color: Colors.white60, fontSize: 13.sp),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(
                    'Cancel',
                    style: TextStyle(color: Colors.white54, fontSize: 14.sp),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(
                    'Clear',
                    style: TextStyle(color: Colors.redAccent, fontSize: 14.sp),
                  ),
                ),
              ],
            ),
          ),
        ) ??
        false;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────
  // ─── Mini Player ──────────────────────────────────────────────────────────
  Widget _buildMiniPlayer() {
    // Only show if there's actually a song currently loaded in the player
    if (globalAudioPlayer.source == null) return const SizedBox.shrink();

    return ClipRRect(
      borderRadius: BorderRadius.only(
        topLeft: Radius.circular(24.r),
        topRight: Radius.circular(24.r),
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 16.h),
          decoration: BoxDecoration(
            color: const Color(0xFF111111).withOpacity(0.85),
            border: Border(
              top: BorderSide(
                color: Colors.white.withOpacity(0.15),
                width: 1.2,
              ),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    _isGlobalPlaying
                        ? 'Now Playing in Background...'
                        : 'Paused',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                // Play/Pause Button
                IconButton(
                  icon: Icon(
                    _isGlobalPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    color: _kAccent,
                    size: 32.r,
                  ),
                  onPressed: () {
                    _isGlobalPlaying
                        ? globalAudioPlayer.pause()
                        : globalAudioPlayer.resume();
                  },
                ),
                // Close/Stop Session Button
                IconButton(
                  icon: Icon(
                    Icons.close_rounded,
                    color: Colors.white54,
                    size: 28.r,
                  ),
                  onPressed: () async {
                    await globalAudioPlayer.stop();
                    await globalAudioPlayer.release(); // Clears the loaded path
                    setState(() {}); // Hide mini player
                  },
                ),
                SizedBox(width: 50.w),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: _buildAppBar(),
      body: Stack(
        children: [
          _buildBackground(),
          SafeArea(
            child: FadeTransition(
              opacity: _fadeAnim,
              child: _audioFiles.isEmpty
                  ? _buildEmptyState()
                  : _buildTrackList(),
            ),
          ),
          // ADD THIS: The Mini Player anchored to the bottom
          Align(alignment: Alignment.bottomCenter, child: _buildMiniPlayer()),
        ],
      ),
      floatingActionButton: _audioFiles.isNotEmpty ? _buildFab() : null,
    );
  }

  // ─── App Bar ──────────────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      flexibleSpace: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(color: Colors.white.withOpacity(0.04)),
        ),
      ),
      leading: _audioFiles.isNotEmpty
          ? IconButton(
              tooltip: 'Clear Library',
              onPressed: _clearAllFiles,
              icon: Icon(
                Icons.delete_sweep_rounded,
                color: Colors.white54,
                size: 22.r,
              ),
            )
          : null,
      title: Column(
        children: [
          Text(
            'GLASSIFY',
            style: GoogleFonts.bakbakOne(
              color: Colors.white,
              fontSize: 20.sp,
              letterSpacing: 3,
            ),
          ),
          if (_audioFiles.isNotEmpty)
            Text(
              '${_audioFiles.length} track${_audioFiles.length == 1 ? '' : 's'}',
              style: TextStyle(
                color: Colors.white38,
                fontSize: 11.sp,
                letterSpacing: 1,
              ),
            ),
        ],
      ),
      centerTitle: true,
      actions: [
        IconButton(
          tooltip: _showingFavorites ? 'Show All' : 'Show Favorites',
          icon: Icon(
            _showingFavorites
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded,
            color: Colors.white54,
            size: 20.r,
          ),
          onPressed: _loadFavorites,
        ),
        SizedBox(width: 4.w),
      ],
    );
  }

  // ─── Background ───────────────────────────────────────────────────────────

  Widget _buildBackground() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_kBg1, _kBg2, Color(0xFF0D0D0D), Color(0xFF000000)],
          stops: [0.0, 0.4, 0.75, 1.0],
        ),
      ),
      child: Stack(
        children: [
          _orb(top: -80, left: -60, size: 260, color: _kAccent, opacity: 0.06),
          _orb(
            bottom: 120,
            right: -80,
            size: 220,
            color: _kAccent2,
            opacity: 0.05,
          ),
          _orb(
            top: 300,
            left: 60,
            size: 160,
            color: const Color(0xFF1A1A1A),
            opacity: 0.08,
          ),
        ],
      ),
    );
  }

  Widget _orb({
    double? top,
    double? bottom,
    double? left,
    double? right,
    required double size,
    required Color color,
    required double opacity,
  }) {
    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      child: IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withOpacity(opacity),
          ),
        ),
      ),
    );
  }

  // ─── Empty State ──────────────────────────────────────────────────────────

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 40.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Large frosted icon orb
            ClipOval(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Container(
                  width: 120.r,
                  height: 120.r,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.06),
                    border: Border.all(color: _kBorderWhite, width: 1.2),
                  ),
                  child: Icon(
                    Icons.library_music_rounded,
                    size: 56.r,
                    color: _kAccent.withOpacity(0.7),
                  ),
                ),
              ),
            ),
            SizedBox(height: 28.h),
            Text(
              'Your library is empty',
              style: GoogleFonts.bakbakOne(
                color: Colors.white,
                fontSize: 20.sp,
                letterSpacing: 0.5,
              ),
            ),
            SizedBox(height: 10.h),
            Text(
              'Add MP3, M4A, FLAC, WAV, AAC or OGG files\nto start listening.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white38,
                fontSize: 13.sp,
                height: 1.6,
              ),
            ),
            SizedBox(height: 32.h),
            // CTA glass button
            GestureDetector(
              onTap: _pickFiles,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(50.r),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 32.w,
                      vertical: 14.h,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(50.r),
                      gradient: LinearGradient(
                        colors: [
                          _kAccent.withOpacity(0.25),
                          _kAccent2.withOpacity(0.25),
                        ],
                      ),
                      border: Border.all(
                        color: _kAccent.withOpacity(0.5),
                        width: 1.2,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.add_rounded,
                          color: Colors.white,
                          size: 20.r,
                        ),
                        SizedBox(width: 8.w),
                        Text(
                          'Add Music',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15.sp,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Track List ───────────────────────────────────────────────────────────

  Widget _buildTrackList() {
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 100.h),
      physics: const BouncingScrollPhysics(),
      itemCount: _audioFiles.length,
      itemBuilder: (context, index) => _buildTrackCard(index),
    );
  }

  Widget _buildTrackCard(int index) {
    final path = _audioFiles[index];
    final filename = p.basename(path);
    final isSelected = _currentIndex == index;
    // Read from cache — may be null if not yet fetched or no art
    final art = _artCache[path];
    final isCached = _artCache.containsKey(path);
    final ext = p
        .extension(path)
        .toLowerCase()
        .replaceFirst('.', '')
        .toUpperCase();

    return Padding(
      padding: EdgeInsets.only(bottom: 10.h),
      child: Dismissible(
        key: Key(path),
        direction: DismissDirection.endToStart,
        // Glass-red dismiss background
        background: ClipRRect(
          borderRadius: BorderRadius.circular(20.r),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              alignment: Alignment.centerRight,
              padding: EdgeInsets.symmetric(horizontal: 24.w),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20.r),
                color: Colors.red.withOpacity(0.25),
                border: Border.all(
                  color: Colors.red.withOpacity(0.4),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    'Remove',
                    style: TextStyle(
                      color: Colors.redAccent,
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(width: 8.w),
                  Icon(
                    Icons.delete_rounded,
                    color: Colors.redAccent,
                    size: 22.r,
                  ),
                ],
              ),
            ),
          ),
        ),
        onDismissed: (_) => _removeFile(index),
        child: GestureDetector(
          onTap: () => _openTrack(index),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20.r),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20.r),
                  color: isSelected ? _kAccent.withOpacity(0.12) : _kGlassWhite,
                  border: Border.all(
                    color: isSelected
                        ? _kAccent.withOpacity(0.5)
                        : _kBorderWhite,
                    width: 1.2,
                  ),
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: 14.w,
                    vertical: 12.h,
                  ),
                  child: Row(
                    children: [
                      // Album art / placeholder
                      _buildArtThumbnail(art, isCached, ext),
                      SizedBox(width: 14.w),
                      // Track info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _cleanFilename(filename),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14.sp,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.2,
                              ),
                            ),
                            SizedBox(height: 4.h),
                            Row(
                              children: [
                                _formatBadge(ext),
                                SizedBox(width: 8.w),
                                if (isSelected)
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.equalizer_rounded,
                                        color: _kAccent,
                                        size: 14.r,
                                      ),
                                      SizedBox(width: 4.w),
                                      Text(
                                        'Now playing',
                                        style: TextStyle(
                                          color: _kAccent,
                                          fontSize: 11.sp,
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      // Chevron / playing indicator
                      Icon(
                        isSelected
                            ? Icons.play_circle_fill_rounded
                            : Icons.chevron_right_rounded,
                        color: isSelected ? _kAccent : Colors.white24,
                        size: isSelected ? 26.r : 20.r,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildArtThumbnail(Uint8List? art, bool isCached, String ext) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12.r),
      child: SizedBox(
        width: 52.r,
        height: 52.r,
        child: isCached && art != null
            // Loaded art
            ? Image.memory(art, fit: BoxFit.cover)
            // Placeholder — either loading skeleton or default icon
            : !isCached
            ? Container(
                color: Colors.white.withOpacity(0.06),
                child: Icon(
                  Icons.music_note_rounded,
                  color: Colors.white12,
                  size: 24.r,
                ),
              )
            : Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      _kAccent.withOpacity(0.25),
                      _kAccent2.withOpacity(0.25),
                    ],
                  ),
                ),
                child: Icon(
                  Icons.music_note_rounded,
                  color: _kAccent.withOpacity(0.6),
                  size: 26.r,
                ),
              ),
      ),
    );
  }

  Widget _formatBadge(String ext) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4.r),
        color: _kAccent.withOpacity(0.12),
        border: Border.all(color: _kAccent.withOpacity(0.25)),
      ),
      child: Text(
        ext,
        style: TextStyle(
          color: _kAccent,
          fontSize: 9.sp,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  // ─── FAB ─────────────────────────────────────────────────────────────────

  Widget _buildFab() {
    return ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_kAccent, _kAccent2],
            ),
            boxShadow: [
              BoxShadow(
                color: _kAccent.withOpacity(0.4),
                blurRadius: 20,
                spreadRadius: 1,
              ),
            ],
          ),
          child: FloatingActionButton(
            backgroundColor: Colors.transparent,
            elevation: 0,
            onPressed: _pickFiles,
            tooltip: 'Add Files',
            child: Icon(Icons.add_rounded, color: Colors.white, size: 28.r),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Navigation
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _openTrack(int index) async {
    setState(() => _currentIndex = index);

    Navigator.pushNamed(
      context,
      AudioplayerScreen.routeName,
      arguments: {
        'audioPath': _audioFiles[index],
        'audioTitle': _cleanFilename(p.basename(_audioFiles[index])),
        'audioIndex': index,
        'audioList': List<String>.from(_audioFiles), // defensive copy
      },
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────────────

  /// Strips file extension for any supported format cleanly.
  String _cleanFilename(String filename) {
    for (final ext in _kSupportedExtensions) {
      if (filename.toLowerCase().endsWith('.$ext')) {
        return filename.substring(0, filename.length - ext.length - 1);
      }
    }
    final dot = filename.lastIndexOf('.');
    return dot != -1 ? filename.substring(0, dot) : filename;
  }
}
