import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_media_metadata/flutter_media_metadata.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:video_player/video_player.dart';

final AudioPlayer globalAudioPlayer = AudioPlayer();

// ─── iOS 26 Liquid Glass ─────────────────────────────────────────────────────
// Replicates Apple's Liquid Glass material as closely as possible in Flutter:
//
//  Layer 1 — strong backdrop blur (lensing simulation)
//  Layer 2 — very low opacity white fill (20-30%)
//  Layer 3 — specular gradient: bright top-left → transparent bottom-right
//  Layer 4 — thin bright top border (light refraction edge)
//  Layer 5 — subtle inner shadow at bottom (depth)
//
// On iOS the blur sigma is higher because the GPU can handle it.
// On Android we dial it back slightly to avoid jank.

bool get _isIOS => Platform.isIOS;

class _LiquidGlass extends StatelessWidget {
  const _LiquidGlass({
    required this.child,
    this.padding,
    this.borderRadius,
    this.blurSigma,
    this.fillOpacity,
    this.tintColor,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final BorderRadiusGeometry? borderRadius;
  final double? blurSigma;
  final double? fillOpacity;
  final Color? tintColor; // optional color tint sampled from album art

  @override
  Widget build(BuildContext context) {
    final radius =
        (borderRadius ?? BorderRadius.circular(28.r)) as BorderRadius;
    final sigma = blurSigma ?? (_isIOS ? 60.0 : 32.0);
    final fill = fillOpacity ?? 0.15;
    final tint = tintColor ?? Colors.white;

    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        // Strong blur = lensing simulation (bending light behind the glass)
        filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: Container(
          padding: padding ?? EdgeInsets.all(18.r),
          decoration: BoxDecoration(
            borderRadius: radius,
            // Layer 2: very subtle white/tint base fill
            color: tint.withOpacity(fill),
            // Layer 3 + 4: specular highlight gradient
            // Top-left corner catches the "light" — mimics real glass refraction
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              stops: const [0.0, 0.18, 0.5, 1.0],
              colors: [
                Colors.white.withOpacity(0.38), // specular bright edge
                Colors.white.withOpacity(0.16), // fading highlight
                tint.withOpacity(fill * 0.8), // mid tint
                tint.withOpacity(fill * 0.4), // dark corner
              ],
            ),
            // Uniform border — Flutter requires same color on all sides
            // when borderRadius is set. The specular top-edge effect is
            // achieved via the gradient above instead.
            border: Border.all(
              color: Colors.white.withOpacity(0.25),
              width: 0.8,
            ),
            boxShadow: [
              // Outer glow — glass panels float
              BoxShadow(
                color: Colors.black.withOpacity(0.22),
                blurRadius: 32,
                spreadRadius: -4,
                offset: const Offset(0, 8),
              ),
              // Inner top highlight (simulates light entering glass from top)
              BoxShadow(
                color: Colors.white.withOpacity(0.10),
                blurRadius: 1,
                spreadRadius: 0,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

// ─── Ambient Video Option ────────────────────────────────────────────────────
// Each option represents a looping background video. Only one can be active.
// Videos should be placed in assets/videos/ and registered in pubspec.yaml.
class _AmbientVideo {
  final IconData icon;
  final String label;
  final String assetPath; // e.g. 'assets/videos/rain.mp4'

  const _AmbientVideo({
    required this.icon,
    required this.label,
    required this.assetPath,
  });
}

class AudioplayerScreen extends StatefulWidget {
  static const String routeName = 'player';
  const AudioplayerScreen({super.key});

  @override
  State<AudioplayerScreen> createState() => _AudioplayerScreenState();
}

class _AudioplayerScreenState extends State<AudioplayerScreen>
    with TickerProviderStateMixin {
  // ─── Favorites ───────────────────────────────────────────────────────────
  List<String> _favoritePaths = [];

  Future<void> _saveFavorites() async {
    final pref = await SharedPreferences.getInstance();
    pref.setStringList('favList', _favoritePaths);
  }

  Future<void> _loadFavorites() async {
    final pref = await SharedPreferences.getInstance();
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
    _saveFavorites();
  }

  // ─── Audio Engine ─────────────────────────────────────────────────────────
  late final AudioPlayer _audioPlayer;
  late StreamSubscription<PlayerState> _playerStateSub;
  late StreamSubscription<Duration> _durationSub;
  late StreamSubscription<Duration> _positionSub;
  late StreamSubscription<void> _completionSub;

  // ─── Playlist State ───────────────────────────────────────────────────────
  List<String> _audioFiles = [];
  late String audioPath;
  late String audioTitle;
  int audioIndex = 0;

  // ─── Playback State ───────────────────────────────────────────────────────
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;
  bool _isPlaying = false;
  bool _isLooping = false;
  bool _isShuffled = false;
  double _currentVolume = 1.0;

  // ─── Metadata ─────────────────────────────────────────────────────────────
  Uint8List? _albumImageBytes;
  String? _artistName;

  // ─── Theme Colors ─────────────────────────────────────────────────────────
  Color _themeColor1 = const Color(0xFF3d7a8a);
  Color _themeColor2 = const Color(0xFF2a5a6a);

  // ─── Init Guard ───────────────────────────────────────────────────────────
  bool _isFirstLoad = true;

  // ─── Animations ───────────────────────────────────────────────────────────
  late final AnimationController _artController;
  late final AnimationController _playlistController;
  late final AnimationController _ambientController;
  late final Animation<double> _ambientFade;
  late final Animation<Offset> _ambientSlide;

  // ─── Seek-drag ────────────────────────────────────────────────────────────
  bool _isSeeking = false;
  double _seekValue = 0;

  // ─── Overlay flags ────────────────────────────────────────────────────────
  bool _playlistOpen = false;
  bool _ambientOpen = false;
  bool _isVolumeExpanded = false;

  // ─── Speed ────────────────────────────────────────────────────────────────
  double _playbackSpeed = 1.0;
  final List<double> _speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  // ─── Ambient video options (radio — only one active at a time) ───────────
  static const List<_AmbientVideo> _ambientVideos = [
    // _AmbientVideo(icon: Icons.water_drop_outlined,  label: 'Rain',   assetPath: 'assets/video/Rain.mp4'),
    // _AmbientVideo(
    //   icon: Icons.air_rounded,
    //   label: 'Wind',
    //   assetPath: 'assets/video/Wind.mp4',
    // ),
    _AmbientVideo(
      icon: Icons.water_rounded,
      label: 'Ocean',
      assetPath: 'assets/video/ocean.mp4',
    ),
    _AmbientVideo(
      icon: Icons.forest_rounded,
      label: 'Forest',
      assetPath: 'assets/video/forest.mp4',
    ),
    // _AmbientVideo(icon: Icons.fireplace_rounded,     label: 'Fire',   assetPath: 'assets/video/Fire.mp4'),
    _AmbientVideo(
      icon: Icons.nights_stay_rounded,
      label: 'Night',
      assetPath: 'assets/video/night.mp4',
    ),
  ];

  /// Index into [_ambientVideos] of the currently playing video, or -1 = none.
  int _selectedAmbientIndex = -1;

  // video_player controller — null when no ambient video is active
  VideoPlayerController? _videoController;

  // ─── Lifecycle ────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
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

    _artController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _playlistController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );

    _ambientController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _ambientFade = CurvedAnimation(
      parent: _ambientController,
      curve: Curves.easeOut,
    );
    _ambientSlide = Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _ambientController,
            curve: Curves.easeOutCubic,
          ),
        );

    _loadFavorites();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isFirstLoad) {
      _isFirstLoad = false;
      final args =
          ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
      _audioFiles = List<String>.from(args['audioList'] ?? []);
      audioPath = args['audioPath'] as String;
      audioTitle = args['audioTitle'] as String;
      audioIndex = (args['audioIndex'] as int?) ?? 0;

      if (_audioFiles.isNotEmpty && !_audioFiles.contains(audioPath)) {
        audioPath = _audioFiles.first;
        audioTitle = _stripExtension(audioPath.split('/').last);
        audioIndex = 0;
      }
      _initAudio();
      _loadFavorites().then((_) {
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
    _artController.dispose();
    _playlistController.dispose();
    _ambientController.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  // ─── Audio Control ────────────────────────────────────────────────────────

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
        _themeColor1 = const Color(0xFF3d7a8a);
        _themeColor2 = const Color(0xFF2a5a6a);
      });
    }
    try {
      final metadata = await MetadataRetriever.fromFile(File(audioPath));
      if (mounted) {
        setState(() {
          _albumImageBytes = metadata.albumArt;
          _artistName = metadata.albumArtistName;
        });
        if (_albumImageBytes != null) _extractThemeColors(_albumImageBytes!);
      }
    } catch (e) {
      log('Metadata error: $e');
    }
  }

  Future<void> _extractThemeColors(Uint8List imageBytes) async {
    final palette = await PaletteGenerator.fromImageProvider(
      MemoryImage(imageBytes),
    );
    if (mounted) {
      setState(() {
        _themeColor1 = palette.dominantColor?.color ?? const Color(0xFF3d7a8a);
        _themeColor2 = palette.vibrantColor?.color ?? const Color(0xFF2a5a6a);
      });
    }
  }

  void _playPause() =>
      _isPlaying ? _audioPlayer.pause() : _audioPlayer.resume();

  Future<void> _playNext() async {
    if (_audioFiles.isEmpty) return;
    audioIndex = (audioIndex + 1) % _audioFiles.length;
    await _updateTrack();
  }

  Future<void> _playPrevious() async {
    if (_audioFiles.isEmpty) return;
    if (_currentPosition.inSeconds > 3) {
      await _audioPlayer.seek(Duration.zero);
      return;
    }
    audioIndex = (audioIndex - 1 + _audioFiles.length) % _audioFiles.length;
    await _updateTrack();
  }

  Future<void> _updateTrack() async {
    audioPath = _audioFiles[audioIndex];
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

  void _toggleShuffle() {
    setState(() => _isShuffled = !_isShuffled);
    if (_isShuffled) _audioFiles.shuffle();
  }

  void _onVolumeChanged(double v) {
    setState(() => _currentVolume = v);
    _audioPlayer.setVolume(v);
  }

  void _cycleSpeed() {
    final idx = _speeds.indexOf(_playbackSpeed);
    final next = _speeds[(idx + 1) % _speeds.length];
    setState(() => _playbackSpeed = next);
    _audioPlayer.setPlaybackRate(next);
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

  void _toggleAmbient() {
    setState(() => _ambientOpen = !_ambientOpen);
    if (_ambientOpen) {
      _ambientController.forward(from: 0);
    } else {
      _ambientController.reverse();
    }
  }

  /// Selects ambient video at [index]. Tapping the already-active index stops it.
  Future<void> _selectAmbientVideo(int index) async {
    // Tapping the active one → stop & deselect
    if (_selectedAmbientIndex == index) {
      final oldCtrl = _videoController;
      setState(() {
        _videoController = null;
        _selectedAmbientIndex = -1;
      });
      await oldCtrl?.pause();
      await oldCtrl?.dispose();
      return;
    }

    // Dispose any previous controller
    final oldCtrl = _videoController;
    setState(() {
      _videoController = null;
      _selectedAmbientIndex = -1;
    });
    await oldCtrl?.pause();
    await oldCtrl?.dispose();

    try {
      final video = _ambientVideos[index];
      final ctrl = VideoPlayerController.asset(
        video.assetPath,
        videoPlayerOptions: VideoPlayerOptions(
          // Prevents ExoPlayer from requesting audio focus,
          // so the audioplayers engine (Quran audio) keeps playing uninterrupted.
          mixWithOthers: true,
        ),
      );
      await ctrl.initialize();
      ctrl.setLooping(true);
      await ctrl.setVolume(0.0); // video is visual only — muted
      ctrl.play();

      if (mounted) {
        setState(() {
          _videoController = ctrl;
          _selectedAmbientIndex = index;
        });
      }
    } catch (e) {
      log('Ambient video error: $e');
      // Show a brief snack so the user knows the file is missing
      if (mounted) {
        _showSnack('Video not found — add ${_ambientVideos[index].assetPath}');
      }
    }
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  String _fmt(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inMinutes)}:${two(d.inSeconds.remainder(60))}';
  }

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
    final dot = filename.lastIndexOf('.');
    return dot != -1 ? filename.substring(0, dot) : filename;
  }

  void _showSnack(String message) {
    final mq = MediaQuery.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.white.withOpacity(0.12),
        elevation: 0,
        margin: EdgeInsets.only(
          bottom: mq.size.height - mq.padding.top - 120,
          left: 16,
          right: 16,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final double screenHeight = MediaQuery.of(context).size.height;
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.black,
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 32.r,
            color: Colors.white,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Stack(
        children: [
          // ── Ambient video background (plays behind everything) ─────────────
          if (_videoController != null && _videoController!.value.isInitialized)
            Positioned.fill(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _videoController!.value.size.width,
                  height: _videoController!.value.size.height,
                  child: VideoPlayer(_videoController!),
                ),
              ),
            ),

          // ── Background gradient derived from album art colors ──────────────
          Positioned.fill(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 800),
              curve: Curves.easeInOut,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    (_videoController != null ? Colors.black : _themeColor1)
                        .withOpacity(_videoController != null ? 0.35 : 0.55),
                    (_videoController != null ? Colors.black : _themeColor2)
                        .withOpacity(_videoController != null ? 0.25 : 0.35),
                    Colors.black,
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.0, 0.45, 1.0],
                ),
              ),
            ),
          ),

          // ── Main content ──────────────────────────────────────────────────
          SafeArea(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.w),
              child: Column(
                children: [
                  const Spacer(),

                  // Album art
                  // _buildAlbumArt(),
                  SizedBox(height: 20.h),

                  // Ambient video row — slides in above player card when open
                  _buildAmbientRow(),

                  // Main player card (matches the bottom card in the image)
                  _buildMainPlayerCard(),

                  SizedBox(height: 10.h),

                  // Sound settings expandable
                  _buildExpandableVolume(),

                  SizedBox(height: 16.h),
                ],
              ),
            ),
          ),

          // ── Playlist overlay ──────────────────────────────────────────────
          if (_playlistOpen) _buildPlaylistOverlay(screenHeight),
        ],
      ),
    );
  }

  // ─── Album Art ────────────────────────────────────────────────────────────

  Widget _buildAlbumArt() {
    final size = MediaQuery.of(context).size.width * 0.82;
    Widget art = _albumImageBytes != null
        ? Image.memory(
            _albumImageBytes!,
            width: size,
            height: size * 0.75,
            fit: BoxFit.cover,
          )
        : Container(
            width: size,
            height: size * 0.75,
            color: Colors.white10,
            child: Icon(
              Icons.music_note_rounded,
              size: 72.r,
              color: Colors.white24,
            ),
          );

    return ClipRRect(borderRadius: BorderRadius.circular(20.r), child: art);
  }

  // ─── Main Player Card (the glassy card at bottom of image) ───────────────

  Widget _buildMainPlayerCard() {
    return _LiquidGlass(
      padding: EdgeInsets.fromLTRB(20.w, 20.h, 20.w, 16.h),
      tintColor: _themeColor1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      audioTitle.contains('.')
                          ? _stripExtension(audioTitle)
                          : audioTitle,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 18.sp,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (_artistName != null) ...[
                      SizedBox(height: 3.h),
                      Text(
                        _artistName!,
                        style: GoogleFonts.inter(
                          color: Colors.white70,
                          fontSize: 13.sp,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              // ··· menu icon (three-dots, matching image)
              GestureDetector(
                onTap: _toggleFavorite,
                child: Container(
                  width: 36.r,
                  height: 36.r,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.12),
                    border: Border.all(color: Colors.white.withOpacity(0.2)),
                  ),
                  child: Icon(
                    _favoritePaths.contains(audioPath)
                        ? Icons.favorite_rounded
                        : Icons.more_horiz_rounded,
                    color: Colors.white,
                    size: 20.r,
                  ),
                ),
              ),
            ],
          ),

          SizedBox(height: 18.h),

          // Seek bar
          _buildSeekBar(),

          SizedBox(height: 20.h),

          // Controls row: speed | prev | play | next | sleep
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Speed (1× in image)
              GestureDetector(
                onTap: _cycleSpeed,
                child: Text(
                  '${_playbackSpeed == _playbackSpeed.truncateToDouble() ? _playbackSpeed.toInt() : _playbackSpeed}×',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

              // Rewind
              GestureDetector(
                onTap: _playPrevious,
                child: Icon(
                  Icons.fast_rewind_rounded,
                  color: Colors.white,
                  size: 30.r,
                ),
              ),

              // Play / Pause (large, central)
              GestureDetector(
                onTap: _playPause,
                child: Icon(
                  _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 52.r,
                ),
              ),

              // Fast forward
              GestureDetector(
                onTap: _playNext,
                child: Icon(
                  Icons.fast_forward_rounded,
                  color: Colors.white,
                  size: 30.r,
                ),
              ),

              // Sleep / loop (moon-z icon in image)
              GestureDetector(
                onTap: _toggleLoop,
                child: Icon(
                  _isLooping ? Icons.repeat_one_rounded : Icons.bedtime_rounded,
                  color: _isLooping ? Colors.white : Colors.white70,
                  size: 22.r,
                ),
              ),
            ],
          ),

          SizedBox(height: 20.h),

          // Bottom row: ambient (rain icon) | playlist
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Rain / ambient icon (left side, matches image)
              GestureDetector(
                onTap: _toggleAmbient,
                child: Container(
                  width: 40.r,
                  height: 40.r,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _ambientOpen
                        ? Colors.white.withOpacity(0.22)
                        : Colors.white.withOpacity(0.10),
                    border: Border.all(
                      color: Colors.white.withOpacity(_ambientOpen ? 0.4 : 0.2),
                    ),
                  ),
                  child: Center(
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Icon(
                          Icons.cloud_rounded,
                          color: Colors.white,
                          size: 18.r,
                        ),
                        Positioned(
                          bottom: 8.r,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: List.generate(
                              3,
                              (i) => Container(
                                margin: EdgeInsets.symmetric(horizontal: 1.r),
                                width: 2.r,
                                height: 5.r + (i == 1 ? 2.r : 0),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(1.r),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Playlist icon (right side)
              GestureDetector(
                onTap: _openPlaylist,
                child: Icon(
                  Icons.format_list_bulleted_rounded,
                  color: Colors.white70,
                  size: 22.r,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Seek Bar ─────────────────────────────────────────────────────────────

  Widget _buildSeekBar() {
    final maxMs = _totalDuration.inMilliseconds > 0
        ? _totalDuration.inMilliseconds.toDouble()
        : 1.0;
    final curMs = _isSeeking
        ? _seekValue
        : _currentPosition.inMilliseconds.toDouble();
    final rem = _totalDuration - _currentPosition;

    return Column(
      children: [
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 4.h,
            thumbShape: RoundSliderThumbShape(enabledThumbRadius: 7.r),
            overlayShape: RoundSliderOverlayShape(overlayRadius: 18.r),
            activeTrackColor: Colors.white,
            inactiveTrackColor: Colors.white.withOpacity(0.25),
            thumbColor: Colors.white,
          ),
          child: Slider(
            min: 0,
            max: maxMs,
            value: curMs.clamp(0.0, maxMs),
            onChangeStart: (_) => setState(() => _isSeeking = true),
            onChanged: (v) => setState(() => _seekValue = v),
            onChangeEnd: (v) {
              setState(() => _isSeeking = false);
              _audioPlayer.seek(Duration(milliseconds: v.toInt()));
            },
          ),
        ),
        SizedBox(height: 2.h),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _fmt(_currentPosition),
              style: GoogleFonts.inter(
                color: Colors.white70,
                fontSize: 11.sp,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              '-${_fmt(rem)}',
              style: GoogleFonts.inter(
                color: Colors.white70,
                fontSize: 11.sp,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ─── Expandable Sound Settings ────────────────────────────────────────────

  Widget _buildExpandableVolume() {
    return GestureDetector(
      onTap: () => setState(() => _isVolumeExpanded = !_isVolumeExpanded),
      child: _LiquidGlass(
        padding: EdgeInsets.symmetric(
          horizontal: 20.w,
          vertical: _isVolumeExpanded ? 18.h : 14.h,
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Sound settings',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                AnimatedRotation(
                  turns: _isVolumeExpanded ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 280),
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: Colors.white70,
                    size: 24.r,
                  ),
                ),
              ],
            ),
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 320),
              crossFadeState: _isVolumeExpanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              firstChild: const SizedBox(width: double.infinity, height: 0),
              secondChild: Column(
                children: [
                  SizedBox(height: 16.h),
                  Row(
                    children: [
                      Icon(
                        Icons.volume_mute_rounded,
                        color: Colors.white30,
                        size: 18.r,
                      ),
                      Expanded(
                        child: SliderTheme(
                          data: SliderThemeData(
                            trackHeight: 3.h,
                            thumbShape: RoundSliderThumbShape(
                              enabledThumbRadius: 6.r,
                            ),
                            overlayShape: RoundSliderOverlayShape(
                              overlayRadius: 14.r,
                            ),
                            activeTrackColor: Colors.white,
                            inactiveTrackColor: Colors.white12,
                            thumbColor: Colors.white,
                          ),
                          child: Slider(
                            min: 0,
                            max: 1,
                            value: _currentVolume,
                            onChanged: _onVolumeChanged,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.volume_up_rounded,
                        color: Colors.white70,
                        size: 18.r,
                      ),
                    ],
                  ),
                  SizedBox(height: 8.h),
                  // Shuffle toggle inside expanded panel
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Shuffle',
                        style: GoogleFonts.inter(
                          color: Colors.white60,
                          fontSize: 13.sp,
                        ),
                      ),
                      GestureDetector(
                        onTap: _toggleShuffle,
                        child: Icon(
                          Icons.shuffle_rounded,
                          color: _isShuffled ? Colors.white : Colors.white30,
                          size: 20.r,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Ambient Row ──────────────────────────────────────────────────────────
  // A horizontal row of circular glassy icon buttons that animates in/out
  // above the player card when the rain icon is tapped.
  // Only one option can be active at a time (radio behaviour).

  Widget _buildAmbientRow() {
    return AnimatedSize(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      child: _ambientOpen
          ? FadeTransition(
              opacity: _ambientFade,
              child: SlideTransition(
                position: _ambientSlide,
                child: Padding(
                  padding: EdgeInsets.only(bottom: 10.h),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: List.generate(_ambientVideos.length, (i) {
                      final opt = _ambientVideos[i];
                      final isActive = _selectedAmbientIndex == i;
                      return GestureDetector(
                        onTap: () => _selectAmbientVideo(i),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          width: 46.r,
                          height: 46.r,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isActive
                                ? Colors.white.withOpacity(0.28)
                                : Colors.white.withOpacity(0.10),
                            // Specular gradient on circle — same Liquid Glass layering
                            gradient: RadialGradient(
                              center: const Alignment(-0.4, -0.5),
                              radius: 1.0,
                              colors: [
                                Colors.white.withOpacity(
                                  isActive ? 0.45 : 0.22,
                                ),
                                Colors.white.withOpacity(
                                  isActive ? 0.18 : 0.06,
                                ),
                              ],
                            ),
                            border: Border.all(
                              color: isActive
                                  ? Colors.white.withOpacity(0.70)
                                  : Colors.white.withOpacity(0.25),
                              width: isActive ? 1.5 : 0.8,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.20),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                              if (isActive)
                                BoxShadow(
                                  color: Colors.white.withOpacity(0.15),
                                  blurRadius: 8,
                                  spreadRadius: 1,
                                ),
                            ],
                          ),
                          child: ClipOval(
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                              child: Center(
                                child: Icon(
                                  opt.icon,
                                  size: 22.r,
                                  color: isActive
                                      ? Colors.white
                                      : Colors.white.withOpacity(0.65),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ),
            )
          : const SizedBox.shrink(),
    );
  }

  // ─── Playlist Overlay ─────────────────────────────────────────────────────

  Widget _buildPlaylistOverlay(double screenHeight) {
    return Positioned.fill(
      child: GestureDetector(
        onTap: _closePlaylist,
        child: Container(
          color: Colors.black.withOpacity(0.45),
          alignment: Alignment.bottomCenter,
          child: GestureDetector(
            onTap: () {},
            child: ClipRRect(
              borderRadius: BorderRadius.vertical(top: Radius.circular(26.r)),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 32, sigmaY: 32),
                child: Container(
                  height: screenHeight * 0.58,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.14),
                    border: Border(
                      top: BorderSide(
                        color: Colors.white.withOpacity(0.2),
                        width: 1,
                      ),
                    ),
                  ),
                  child: Column(
                    children: [
                      SizedBox(height: 12.h),
                      Container(
                        width: 36.w,
                        height: 4.h,
                        decoration: BoxDecoration(
                          color: Colors.white30,
                          borderRadius: BorderRadius.circular(2.r),
                        ),
                      ),
                      SizedBox(height: 16.h),
                      Text(
                        'Playlist',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 17.sp,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 12.h),
                      Expanded(
                        child: ListView.builder(
                          itemCount: _audioFiles.length,
                          itemBuilder: (context, i) {
                            final isActive = i == audioIndex;
                            return ListTile(
                              leading: isActive
                                  ? Icon(
                                      Icons.music_note_rounded,
                                      color: Colors.white,
                                      size: 20.r,
                                    )
                                  : Icon(
                                      Icons.music_note_outlined,
                                      color: Colors.white38,
                                      size: 20.r,
                                    ),
                              title: Text(
                                _stripExtension(_audioFiles[i].split('/').last),
                                style: GoogleFonts.inter(
                                  color: isActive
                                      ? Colors.white
                                      : Colors.white70,
                                  fontSize: 14.sp,
                                  fontWeight: isActive
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () => _jumpToTrack(i),
                            );
                          },
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
    );
  }
}
