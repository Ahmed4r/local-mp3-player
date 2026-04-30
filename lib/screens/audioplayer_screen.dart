import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_media_metadata/flutter_media_metadata.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

final AudioPlayer globalAudioPlayer = AudioPlayer();

class AudioplayerScreen extends StatefulWidget {
  static const String routeName = 'player';
  const AudioplayerScreen({super.key});

  @override
  State<AudioplayerScreen> createState() => _AudioplayerScreenState();
}

class _AudioplayerScreenState extends State<AudioplayerScreen>
    with TickerProviderStateMixin {
  // pref
  List<String> _favoritePaths = [];
  bool isFav = false;

  Future<void> SaveFavorites() async {
    SharedPreferences pref = await SharedPreferences.getInstance();
    pref.setStringList('favList', _favoritePaths);
  }

  Future<void> LoadFavorites() async {
    SharedPreferences pref = await SharedPreferences.getInstance();
    // Make sure the key matches what you used in audioplayer_screen ('favList')
    _favoritePaths = pref.getStringList('favList') ?? [];
  }

  void _toggleFavorite() {
    setState(() {
      if (_favoritePaths.contains(audioPath)) {
        _favoritePaths.remove(audioPath);
        _showSnack('Removed from favorites');
      } else {
        _favoritePaths.add(audioPath);
        _showSnack('Added to favorites');
      }
    });
    SaveFavorites();
  }

  // ─── Audio Engine ────────────────────────────────────────────────────────────
  late final AudioPlayer _audioPlayer;
  late StreamSubscription<PlayerState> _playerStateSub;
  late StreamSubscription<Duration> _durationSub;
  late StreamSubscription<Duration> _positionSub;
  late StreamSubscription<void> _completionSub;

  // ─── Playlist State ──────────────────────────────────────────────────────────
  // Holds paths for ALL supported formats: .mp3 .m4a .wav .flac .aac
  List<String> _audioFiles = [];
  List<String> _allFiles = []; // <-- Add this line
  bool _showingFavorites = false; // <-- Add this
  late String audioPath;
  late String audioTitle;
  int audioIndex = 0;

  // ─── Playback State ──────────────────────────────────────────────────────────
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;
  bool _isPlaying = false;
  bool _isLooping = false;
  bool _isShuffled = false;

  // ─── Metadata ────────────────────────────────────────────────────────────────
  Uint8List? _albumImageBytes;
  String? _artistName;
  String? _albumName;

  // ─── Init Guard ──────────────────────────────────────────────────────────────
  // Prevents re-initialisation on every UI rebuild triggered by
  // keyboard appearance, orientation change, etc.
  bool _isFirstLoad = true;

  // ─── Album Art Animation ─────────────────────────────────────────────────────
  late final AnimationController _artController;
  late final Animation<double> _artScale;

  // ─── Seek-drag state ─────────────────────────────────────────────────────────
  bool _isSeeking = false;
  double _seekValue = 0;

  // ─── Playlist Overlay ────────────────────────────────────────────────────────
  bool _playlistOpen = false;
  late final AnimationController _playlistController;
  late final Animation<double> _playlistScale;
  late final Animation<double> _playlistFade;
  late final Animation<double> _playlistBlur;

  // ────────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ────────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();

    // FIX: Use the global player instead of creating a new one
    _audioPlayer = globalAudioPlayer;

    _audioPlayer.setReleaseMode(ReleaseMode.stop);

    _playerStateSub = _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _isPlaying = state == PlayerState.playing);
    });

    _durationSub = _audioPlayer.onDurationChanged.listen((d) {
      if (mounted) setState(() => _totalDuration = d);
    });

    _positionSub = _audioPlayer.onPositionChanged.listen((p) {
      if (mounted && !_isSeeking) setState(() => _currentPosition = p);
    });

    _completionSub = _audioPlayer.onPlayerComplete.listen((_) {
      if (!_isLooping) _playNext();
    });

    // Album-art pulse animation
    _artController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _artScale = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(parent: _artController, curve: Curves.easeOutBack),
    );

    // Playlist overlay — smooth "explosion" open/close
    _playlistController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _playlistScale = Tween<double>(begin: 0.82, end: 1.0).animate(
      CurvedAnimation(parent: _playlistController, curve: Curves.easeOutExpo),
    );
    _playlistFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _playlistController,
        curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
      ),
    );
    _playlistBlur = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _playlistController, curve: Curves.easeOut),
    );
    LoadFavorites();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // FIX 2 ▸ Guard so this runs ONLY on the very first build,
    //          not on every subsequent rebuild.
    if (_isFirstLoad) {
      _isFirstLoad = false;

      final args =
          ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;

      // Accept any list of audio file paths regardless of extension.
      _audioFiles = List<String>.from(args['audioList'] ?? []);
      audioPath = args['audioPath'] as String;
      audioTitle = args['audioTitle'] as String;
      audioIndex = (args['audioIndex'] as int?) ?? 0;

      // Safety: if the provided path isn't in the list, fall back to first.
      if (_audioFiles.isNotEmpty && !_audioFiles.contains(audioPath)) {
        audioPath = _audioFiles.first;
        audioTitle = _stripExtension(audioPath.split('/').last);
        audioIndex = 0;
      }

      _initAudio();
      LoadFavorites().then((_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _playerStateSub.cancel();
    _durationSub.cancel();
    _positionSub.cancel();
    _completionSub.cancel();
    // _audioPlayer.dispose();
    _artController.dispose();
    _playlistController.dispose();
    super.dispose();
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Audio Control
  // ────────────────────────────────────────────────────────────────────────────

  Future<void> _initAudio() async {
    await _audioPlayer.setSource(DeviceFileSource(audioPath));
    await _loadMetadata();
    await _audioPlayer.resume();
    _artController.forward(from: 0);
  }

  Future<void> _loadMetadata() async {
    if (mounted) {
      setState(() {
        _albumImageBytes = null;
        _artistName = null;
        _albumName = null;
      });
    }
    try {
      final metadata = await MetadataRetriever.fromFile(File(audioPath));
      if (mounted) {
        setState(() {
          _albumImageBytes = metadata.albumArt;
          _artistName = metadata.albumArtistName;
          _albumName = metadata.albumName;
        });
      }
    } catch (e) {
      log('Metadata error: $e');
    }
  }

  void _playPause() {
    _isPlaying ? _audioPlayer.pause() : _audioPlayer.resume();
  }

  Future<void> _playNext() async {
    if (_audioFiles.isEmpty) return;
    audioIndex = (audioIndex + 1) % _audioFiles.length;
    await _updateTrack();
  }

  Future<void> _playPrevious() async {
    if (_audioFiles.isEmpty) return;
    // If more than 3 s into the track, restart instead of going back.
    if (_currentPosition.inSeconds > 3) {
      await _audioPlayer.seek(Duration.zero);
      return;
    }
    audioIndex = (audioIndex - 1 + _audioFiles.length) % _audioFiles.length;
    await _updateTrack();
  }

  Future<void> _updateTrack() async {
    audioPath = _audioFiles[audioIndex];
    // Strip full extension regardless of format (.mp3, .m4a, .flac, etc.)
    audioTitle = _stripExtension(audioPath.split('/').last);
    if (mounted) setState(() {});
    await _initAudio();
  }

  void _toggleLoop() {
    setState(() => _isLooping = !_isLooping);
    _audioPlayer.setReleaseMode(
      _isLooping ? ReleaseMode.loop : ReleaseMode.stop,
    );
  }

  void _openPlaylist() {
    setState(() => _playlistOpen = true);
    _playlistController.forward(from: 0);
  }

  Future<void> _closePlaylist() async {
    await _playlistController.reverse();
    if (mounted) setState(() => _playlistOpen = false);
  }

  Future<void> _jumpToTrack(int index) async {
    await _closePlaylist();
    if (index == audioIndex) return;
    audioIndex = index;
    await _updateTrack();
  }

  void _toggleShuffle() {
    setState(() => _isShuffled = !_isShuffled);
    _audioFiles.shuffle();
    log(_isShuffled.toString());
    log('suffled : ${_audioFiles}');
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Helpers
  // ────────────────────────────────────────────────────────────────────────────

  String _fmt(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inMinutes)}:${two(d.inSeconds.remainder(60))}';
  }

  /// Strips the file extension from a filename regardless of format.
  /// e.g. "track.m4a" → "track", "song.flac" → "song"
  String _stripExtension(String filename) {
    const supported = {
      '.mp3',
      '.m4a',
      '.wav',
      '.flac',
      '.aac',
      '.ogg',
      '.opus',
    };
    for (final ext in supported) {
      if (filename.toLowerCase().endsWith(ext)) {
        return filename.substring(0, filename.length - ext.length);
      }
    }
    // Fallback: strip anything after the last dot
    final dot = filename.lastIndexOf('.');
    return dot != -1 ? filename.substring(0, dot) : filename;
  }

  String get _upNextTitle {
    if (_audioFiles.length <= 1) return '—';
    final next = _audioFiles[(audioIndex + 1) % _audioFiles.length];
    return _stripExtension(next.split('/').last);
  }

  void _showSnack(String message) {
    final MediaQueryData mediaQuery = MediaQuery.of(context);
    // Calculate the height of the screen minus status bar and desired offset
    final double topPadding = mediaQuery.padding.top + 20;
    final double screenHeight = mediaQuery.size.height;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color.fromARGB(
          255,
          214,
          212,
          212,
        ).withOpacity(0.14),
        elevation: 0,
        // The bottom margin pushes the SnackBar to the top
        margin: EdgeInsets.only(
          bottom:
              screenHeight -
              topPadding -
              100, // Adjust 100 based on SnackBar height
          left: 16,
          right: 16,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Build
  // ────────────────────────────────────────────────────────────────────────────

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
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.symmetric(horizontal: 22.w, vertical: 12.h),
              child: Column(
                children: [
                  SizedBox(height: 8.h),
                  _buildAlbumArtCard(),
                  SizedBox(height: 20.h),
                  _buildSeekCard(),
                  SizedBox(height: 16.h),
                  _buildUpNextCard(),
                  SizedBox(height: 16.h),
                  _buildControlsCard(),
                  SizedBox(height: 20.h),
                ],
              ),
            ),
          ),
          // ── Playlist Overlay (explodes open on long-press) ────────────────
          if (_playlistOpen) _buildPlaylistOverlay(),
        ],
      ),
    );
  }

  // ─── App Bar ─────────────────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      leading: IconButton(
        icon: Icon(
          Icons.keyboard_arrow_down_rounded,
          color: Colors.white,
          size: 32.r,
        ),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: Column(
        children: [
          Text(
            'NOW PLAYING',
            style: GoogleFonts.bakbakOne(
              color: Colors.white60,
              fontSize: 11.sp,
              letterSpacing: 3,
            ),
          ),
          if (_albumName != null)
            Text(
              _albumName!,
              style: TextStyle(
                color: Colors.white,
                fontSize: 13.sp,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
      actions: [
        IconButton(
          icon: Icon(
            Icons.more_vert_rounded,
            color: Colors.white70,
            size: 24.r,
          ),
          onPressed: () {},
        ),
      ],
    );
  }

  // ─── Background ──────────────────────────────────────────────────────────────

  Widget _buildBackground() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF000000), // pure black
            Color(0xFF0A0A0A), // near-black
            Color(0xFF111111), // dark charcoal
            Color(0xFF000000), // pure black
          ],
          stops: [0.0, 0.35, 0.70, 1.0],
        ),
      ),
      child: Stack(
        children: [
          // Soft bokeh orbs for depth
          _orb(
            top: -60,
            left: -60,
            size: 220,
            color: const Color(0xFF0fbcf9),
            opacity: 0.07,
          ),
          _orb(
            top: 180,
            right: -80,
            size: 200,
            color: const Color(0xFF52D7BF),
            opacity: 0.06,
          ),
          _orb(
            bottom: 100,
            left: 40,
            size: 160,
            color: const Color(0xFF1A1A1A),
            opacity: 0.80,
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
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withOpacity(opacity),
        ),
      ),
    );
  }

  // ─── Album Art Card ───────────────────────────────────────────────────────────

  Widget _buildAlbumArtCard() {
    return _glass(
      child: Column(
        children: [
          ScaleTransition(
            scale: _artScale,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20.r),
              child: _albumImageBytes != null
                  ? Image.memory(
                      _albumImageBytes!,
                      height: 280.h,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    )
                  : _defaultArt(),
            ),
          ),
          SizedBox(height: 18.h),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      audioTitle.contains('.')
                          ? _stripExtension(audioTitle)
                          : audioTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 20.sp,
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
                    if (_artistName != null) ...[
                      SizedBox(height: 3.h),
                      Text(
                        _artistName!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 14.sp,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              _glassIconButton(
                // Dynamic icon: solid if favorite, outlined if not
                icon: _favoritePaths.contains(audioPath)
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                size: 22.r,
                // Make it red/pink if it is a favorite
                active: _favoritePaths.contains(audioPath),
                activeColor: Colors.pinkAccent,
                onTap: _toggleFavorite, // Call your new function
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _defaultArt() {
    return Container(
      height: 280.h,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20.r),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A1A1A), Color(0xFF0D0D0D)],
        ),
      ),
      child: Icon(
        Icons.music_note_rounded,
        size: 100.r,
        color: Colors.white.withOpacity(0.3),
      ),
    );
  }

  // ─── Seek Bar Card ────────────────────────────────────────────────────────────

  Widget _buildSeekCard() {
    final maxMs = _totalDuration.inMilliseconds > 0
        ? _totalDuration.inMilliseconds.toDouble()
        : 1.0;
    final currentMs = _isSeeking
        ? _seekValue
        : _currentPosition.inMilliseconds
              .clamp(0, _totalDuration.inMilliseconds)
              .toDouble();

    return _glass(
      padding: EdgeInsets.fromLTRB(16.w, 14.h, 16.w, 10.h),
      child: Column(
        children: [
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 3.h,
              thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6.r),
              overlayShape: RoundSliderOverlayShape(overlayRadius: 14.r),
              activeTrackColor: const Color(0xFF52D7BF),
              inactiveTrackColor: Colors.white12,
              thumbColor: Colors.white,
              overlayColor: const Color(0xFF52D7BF).withOpacity(0.2),
            ),
            child: Slider(
              min: 0,
              max: maxMs,
              value: currentMs,
              onChangeStart: (v) {
                _isSeeking = true;
                _seekValue = v;
              },
              onChanged: (v) => setState(() => _seekValue = v),
              onChangeEnd: (v) {
                _isSeeking = false;
                _audioPlayer.seek(Duration(milliseconds: v.toInt()));
              },
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 6.w),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _fmt(
                    _isSeeking
                        ? Duration(milliseconds: _seekValue.toInt())
                        : _currentPosition,
                  ),
                  style: TextStyle(color: Colors.white60, fontSize: 12.sp),
                ),
                Text(
                  _fmt(_totalDuration),
                  style: TextStyle(color: Colors.white60, fontSize: 12.sp),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Up Next Card (long-press → playlist overlay) ─────────────────────────

  Widget _buildUpNextCard() {
    final hasMultiple = _audioFiles.length > 1;
    return GestureDetector(
      onLongPress: hasMultiple ? _openPlaylist : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        child: _glass(
          padding: EdgeInsets.symmetric(horizontal: 18.w, vertical: 14.h),
          child: Row(
            children: [
              Container(
                width: 38.r,
                height: 38.r,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10.r),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0fbcf9), Color(0xFF52D7BF)],
                  ),
                ),
                child: Icon(
                  Icons.queue_music_rounded,
                  color: Colors.white,
                  size: 20.r,
                ),
              ),
              SizedBox(width: 14.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'UP NEXT',
                          style: TextStyle(
                            color: Colors.white38,
                            fontSize: 10.sp,
                            letterSpacing: 2,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (hasMultiple) ...[
                          SizedBox(width: 8.w),
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 6.w,
                              vertical: 1.h,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(4.r),
                              color: const Color(0xFF0fbcf9).withOpacity(0.15),
                            ),
                            child: Text(
                              'HOLD TO BROWSE',
                              style: TextStyle(
                                color: const Color(0xFF0fbcf9),
                                fontSize: 8.sp,
                                letterSpacing: 1,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    SizedBox(height: 2.h),
                    Text(
                      _upNextTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                hasMultiple
                    ? Icons.expand_less_rounded
                    : Icons.chevron_right_rounded,
                color: Colors.white30,
                size: 22.r,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Playlist Overlay ─────────────────────────────────────────────────────────

  Widget _buildPlaylistOverlay() {
    return AnimatedBuilder(
      animation: _playlistController,
      builder: (context, _) {
        final blur = _playlistBlur.value * 22.0;
        return Stack(
          children: [
            // ── Blurred scrim ──────────────────────────────────────────────
            GestureDetector(
              onTap: _closePlaylist,
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                child: Container(
                  color: Colors.black.withOpacity(0.55 * _playlistFade.value),
                ),
              ),
            ),
            // ── Exploding panel ───────────────────────────────────────────
            Align(
              alignment: Alignment.bottomCenter,
              child: FadeTransition(
                opacity: _playlistFade,
                child: ScaleTransition(
                  scale: _playlistScale,
                  alignment: Alignment.bottomCenter,
                  child: SafeArea(
                    top: false,
                    child: Container(
                      margin: EdgeInsets.fromLTRB(16.w, 0, 16.w, 16.h),
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * 0.68,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(28.r),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(28.r),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.15),
                                width: 1.2,
                              ),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Handle + header
                                _buildPlaylistHeader(),
                                // Track rows
                                Flexible(
                                  child: ListView.builder(
                                    padding: EdgeInsets.fromLTRB(
                                      12.w,
                                      0,
                                      12.w,
                                      16.h,
                                    ),
                                    physics: const BouncingScrollPhysics(),
                                    itemCount: _audioFiles.length,
                                    itemBuilder: (ctx, i) =>
                                        _buildPlaylistRow(i),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPlaylistHeader() {
    return Padding(
      padding: EdgeInsets.fromLTRB(20.w, 14.h, 20.w, 8.h),
      child: Column(
        children: [
          // Drag handle
          Container(
            width: 36.w,
            height: 4.h,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2.r),
            ),
          ),
          SizedBox(height: 14.h),
          Row(
            children: [
              Icon(
                Icons.queue_music_rounded,
                color: const Color(0xFF0fbcf9),
                size: 20.r,
              ),
              SizedBox(width: 10.w),
              Text(
                'PLAYLIST',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2.5,
                ),
              ),
              const Spacer(),
              Text(
                '${_audioFiles.length} tracks',
                style: TextStyle(color: Colors.white38, fontSize: 12.sp),
              ),
              SizedBox(width: 12.w),
              GestureDetector(
                onTap: _closePlaylist,
                child: Icon(
                  Icons.close_rounded,
                  color: Colors.white38,
                  size: 20.r,
                ),
              ),
            ],
          ),
          SizedBox(height: 10.h),
          Divider(color: Colors.white.withOpacity(0.08), height: 1),
        ],
      ),
    );
  }

  Widget _buildPlaylistRow(int i) {
    final isActive = i == audioIndex;
    final title = _stripExtension(_audioFiles[i].split('/').last);

    return GestureDetector(
      onTap: () => _jumpToTrack(i),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        margin: EdgeInsets.symmetric(vertical: 4.h),
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16.r),
          color: isActive
              ? const Color(0xFF0fbcf9).withOpacity(0.14)
              : Colors.white.withOpacity(0.04),
          border: Border.all(
            color: isActive
                ? const Color(0xFF0fbcf9).withOpacity(0.45)
                : Colors.transparent,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            // Track number / equaliser icon
            SizedBox(
              width: 28.r,
              child: isActive
                  ? Icon(
                      Icons.equalizer_rounded,
                      color: const Color(0xFF0fbcf9),
                      size: 18.r,
                    )
                  : Text(
                      '${i + 1}',
                      style: TextStyle(
                        color: Colors.white30,
                        fontSize: 12.sp,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
            ),
            SizedBox(width: 10.w),
            // Title
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isActive ? Colors.white : Colors.white70,
                  fontSize: 13.sp,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ),
            if (isActive)
              Icon(
                Icons.volume_up_rounded,
                color: const Color(0xFF52D7BF),
                size: 16.r,
              ),
          ],
        ),
      ),
    );
  }

  // ─── Controls Card ────────────────────────────────────────────────────────────

  Widget _buildControlsCard() {
    return _glass(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 14.h),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Loop toggle
          _glassIconButton(
            icon: Icons.loop_rounded,
            size: 22.r,
            active: _isLooping,
            activeColor: const Color(0xFF52D7BF),
            onTap: _toggleLoop,
          ),

          // Previous
          _glassIconButton(
            icon: Icons.skip_previous_rounded,
            size: 34.r,
            onTap: _playPrevious,
          ),

          // Play / Pause — accent button
          GestureDetector(
            onTap: _playPause,
            child: Container(
              width: 70.r,
              height: 70.r,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF0fbcf9), Color(0xFF52D7BF)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0fbcf9).withOpacity(0.45),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Icon(
                _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: Colors.white,
                size: 38.r,
              ),
            ),
          ),

          // Next
          _glassIconButton(
            icon: Icons.skip_next_rounded,
            size: 34.r,
            onTap: _playNext,
          ),

          // Shuffle placeholder
          _glassIconButton(
            icon: Icons.shuffle_rounded,
            size: 22.r,
            active: _isShuffled,
            activeColor: const Color(0xFF52D7BF),
            onTap: _toggleShuffle,
          ),
        ],
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Reusable Glass Widgets
  // ────────────────────────────────────────────────────────────────────────────

  /// Core glassmorphism container with BackdropFilter blur.
  Widget _glass({required Widget child, EdgeInsetsGeometry? padding}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28.r),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: double.infinity,
          padding: padding ?? EdgeInsets.all(18.r),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.07),
            borderRadius: BorderRadius.circular(28.r),
            border: Border.all(
              color: Colors.white.withOpacity(0.15),
              width: 1.2,
            ),
          ),
          child: child,
        ),
      ),
    );
  }

  /// Small circular glass icon button.
  Widget _glassIconButton({
    required IconData icon,
    required VoidCallback onTap,
    double? size,
    bool active = false,
    Color activeColor = Colors.white,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            width: (size ?? 22.r) + 18.r,
            height: (size ?? 22.r) + 18.r,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(active ? 0.18 : 0.07),
              border: Border.all(
                color: active
                    ? activeColor.withOpacity(0.6)
                    : Colors.white.withOpacity(0.12),
                width: 1,
              ),
            ),
            child: Icon(
              icon,
              size: size ?? 22.r,
              color: active ? activeColor : Colors.white70,
            ),
          ),
        ),
      ),
    );
  }
}
