import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_media_metadata/flutter_media_metadata.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:video_player/video_player.dart';

final AudioPlayer globalAudioPlayer = AudioPlayer();

class _AmbientVideo {
  final IconData icon;
  final String label;
  final String assetPath;

  const _AmbientVideo({required this.icon, required this.label, required this.assetPath});
}

class AudioplayerScreen extends StatefulWidget {
  static const String routeName = 'player';
  const AudioplayerScreen({super.key});

  @override
  State<AudioplayerScreen> createState() => _AudioplayerScreenState();
}

class _AudioplayerScreenState extends State<AudioplayerScreen> with TickerProviderStateMixin {
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

  late final AudioPlayer _audioPlayer;
  late StreamSubscription<PlayerState> _playerStateSub;
  late StreamSubscription<Duration> _durationSub;
  late StreamSubscription<Duration> _positionSub;
  late StreamSubscription<void> _completionSub;

  List<String> _audioFiles = [];
  late String audioPath;
  late String audioTitle;
  int audioIndex = 0;

  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;
  bool _isPlaying = false;
  bool _isLooping = false;
  
  double _currentVolume = 1.0;

  Uint8List? _albumImageBytes;
  String? _artistName;

  Color _themeColor1 = const Color(0xFF3d7a8a);
  Color _themeColor2 = const Color(0xFF2a5a6a);

  bool _isFirstLoad = true;

  late final AnimationController _artController;
  late final AnimationController _playlistController;
  late final AnimationController _ambientController;
  late final Animation<double> _ambientFade;
  late final Animation<Offset> _ambientSlide;

  bool _isSeeking = false;
  double _seekValue = 0;

  bool _playlistOpen = false;
  bool _ambientOpen = false;
  bool _isVolumeExpanded = false;

  double _playbackSpeed = 1.0;
  final List<double> _speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  static const List<_AmbientVideo> _ambientVideos = [
    _AmbientVideo(icon: Icons.air_rounded, label: 'Wind', assetPath: 'assets/video/wind.mp4'),
    _AmbientVideo(icon: Icons.water_rounded, label: 'Ocean', assetPath: 'assets/video/ocean.mp4'),
    _AmbientVideo(icon: Icons.forest_rounded, label: 'Forest', assetPath: 'assets/video/forest.mp4'),
    _AmbientVideo(icon: Icons.nights_stay_rounded, label: 'Night', assetPath: 'assets/video/night.mp4'),
  ];

  int _selectedAmbientIndex = -1;
  VideoPlayerController? _videoController;

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

    _artController = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _playlistController = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
    _ambientController = AnimationController(vsync: this, duration: const Duration(milliseconds: 380));
    _ambientFade = CurvedAnimation(parent: _ambientController, curve: Curves.easeOut);
    _ambientSlide = Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(CurvedAnimation(parent: _ambientController, curve: Curves.easeOutCubic));

    _loadFavorites();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isFirstLoad) {
      _isFirstLoad = false;
      final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
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
      log('Metadata error: ');
    }
  }

  Future<void> _extractThemeColors(Uint8List imageBytes) async {
    final palette = await PaletteGenerator.fromImageProvider(MemoryImage(imageBytes));
    if (mounted) {
      setState(() {
        _themeColor1 = palette.dominantColor?.color ?? const Color(0xFF3d7a8a);
        _themeColor2 = palette.vibrantColor?.color ?? const Color(0xFF2a5a6a);
      });
    }
  }

  void _playPause() => _isPlaying ? _audioPlayer.pause() : _audioPlayer.resume();

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
    _audioPlayer.setReleaseMode(_isLooping ? ReleaseMode.loop : ReleaseMode.stop);
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

  Future<void> _selectAmbientVideo(int index) async {
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
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      await ctrl.initialize();
      ctrl.setLooping(true);
      await ctrl.setVolume(0.0);
      ctrl.play();

      if (mounted) {
        setState(() {
          _videoController = ctrl;
          _selectedAmbientIndex = index;
        });
      }
    } catch (e) {
      log('Ambient video error: ');
      if (mounted) {
        _showSnack('Video not found — add ');
      }
    }
  }

  String _fmt(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return ':';
  }

  String _stripExtension(String filename) {
    const supported = {'.mp3', '.m4a', '.wav', '.flac', '.aac', '.ogg', '.opus'};
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
        margin: EdgeInsets.only(bottom: mq.size.height - mq.padding.top - 120, left: 16, right: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: AdaptiveButton.icon(
          icon: Icons.keyboard_arrow_down_rounded, 
          iconColor: Colors.white,
          style: AdaptiveButtonStyle.plain,
          onPressed: () => Navigator.pop(context),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Stack(
        children: [
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
          Positioned.fill(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 800),
              curve: Curves.easeInOut,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    (_videoController != null ? Colors.black : _themeColor1).withOpacity(_videoController != null ? 0.35 : 0.55),
                    (_videoController != null ? Colors.black : _themeColor2).withOpacity(_videoController != null ? 0.25 : 0.35),
                    Colors.black,
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.0, 0.45, 1.0],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.w),
              child: Column(
                children: [
                  const Spacer(),
                  _buildAlbumArt(),
                  SizedBox(height: 20.h),
                  _buildAmbientRow(),
                  _buildMainPlayerCard(),
                  SizedBox(height: 10.h),
                  _buildExpandableVolume(),
                  SizedBox(height: 16.h),
                ],
              ),
            ),
          ),
          if (_playlistOpen) _buildPlaylistOverlay(MediaQuery.of(context).size.height),
        ],
      ),
    );
  }

  Widget _buildAlbumArt() {
    final size = MediaQuery.of(context).size.width * 0.82;
    Widget art = _albumImageBytes != null
        ? Image.memory(_albumImageBytes!, width: size, height: size * 0.75, fit: BoxFit.cover)
        : Container(
            width: size,
            height: size * 0.75,
            color: Colors.white10,
            child: Icon(Icons.music_note_rounded, size: 72.r, color: Colors.white24),
          );
    return ClipRRect(borderRadius: BorderRadius.circular(20.r), child: art);
  }

  Widget _buildMainPlayerCard() {
    return AdaptiveBlurView(
      borderRadius: BorderRadius.circular(28.r),
      child: Container(
        color: _themeColor1.withOpacity(0.15),
        padding: EdgeInsets.fromLTRB(20.w, 20.h, 20.w, 16.h),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        audioTitle.contains('.') ? _stripExtension(audioTitle) : audioTitle,
                        style: GoogleFonts.inter(color: Colors.white, fontSize: 18.sp, fontWeight: FontWeight.w700, letterSpacing: -0.3),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (_artistName != null) ...[
                        SizedBox(height: 3.h),
                        Text(
                          _artistName!,
                          style: GoogleFonts.inter(color: Colors.white70, fontSize: 13.sp),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                AdaptiveButton.icon(
                  onPressed: _toggleFavorite,
                  style: AdaptiveButtonStyle.plain,
                  icon: _favoritePaths.contains(audioPath) ? Icons.favorite_rounded : Icons.more_horiz_rounded,
                  iconColor: Colors.white,
                ),
              ],
            ),
            SizedBox(height: 18.h),
            _buildSeekBar(),
            SizedBox(height: 20.h),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                GestureDetector(
                  onTap: _cycleSpeed,
                  child: Text('×', style: GoogleFonts.inter(color: Colors.white, fontSize: 13.sp, fontWeight: FontWeight.w600)),
                ),
                AdaptiveButton.icon(
                  onPressed: _playPrevious, 
                  icon: Icons.fast_rewind_rounded, 
                  iconColor: Colors.white,
                  style: AdaptiveButtonStyle.plain,
                ),
                AdaptiveButton.icon(
                  onPressed: _playPause,
                  icon: _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, 
                  iconColor: Colors.white,
                  style: AdaptiveButtonStyle.plain,
                ),
                AdaptiveButton.icon(
                  onPressed: _playNext, 
                  icon: Icons.fast_forward_rounded, 
                  iconColor: Colors.white,
                  style: AdaptiveButtonStyle.plain,
                ),
                AdaptiveButton.icon(
                  onPressed: _toggleLoop,
                  icon: _isLooping ? Icons.repeat_one_rounded : Icons.bedtime_rounded,
                  iconColor: _isLooping ? Colors.white : Colors.white70,
                  style: AdaptiveButtonStyle.plain,
                ),
              ],
            ),
            SizedBox(height: 20.h),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                AdaptiveButton.icon(
                  onPressed: _toggleAmbient,
                  icon: Icons.cloud_rounded, 
                  iconColor: Colors.white,
                  style: AdaptiveButtonStyle.plain,
                ),
                AdaptiveButton.icon(
                  onPressed: _openPlaylist,
                  icon: Icons.queue_music_rounded, 
                  iconColor: Colors.white,
                  style: AdaptiveButtonStyle.plain,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSeekBar() {
    final maxMs = _totalDuration.inMilliseconds > 0 ? _totalDuration.inMilliseconds.toDouble() : 1.0;
    final curMs = _isSeeking ? _seekValue : _currentPosition.inMilliseconds.toDouble();
    final rem = _totalDuration - _currentPosition;

    return Column(
      children: [
        AdaptiveSlider(
          value: curMs.clamp(0.0, maxMs),
          min: 0,
          max: maxMs,
          activeColor: Colors.white,
          onChangeStart: (_) => setState(() => _isSeeking = true),
          onChanged: (v) => setState(() => _seekValue = v),
          onChangeEnd: (v) {
            setState(() => _isSeeking = false);
            _audioPlayer.seek(Duration(milliseconds: v.toInt()));
          },
        ),
        SizedBox(height: 2.h),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(_fmt(_currentPosition), style: GoogleFonts.inter(color: Colors.white70, fontSize: 11.sp, fontWeight: FontWeight.w600)),
            Text('-', style: GoogleFonts.inter(color: Colors.white70, fontSize: 11.sp, fontWeight: FontWeight.w600)),
          ],
        ),
      ],
    );
  }

  Widget _buildExpandableVolume() {
    return GestureDetector(
      onTap: () => setState(() => _isVolumeExpanded = !_isVolumeExpanded),
      child: AdaptiveBlurView(
        borderRadius: BorderRadius.circular(20.r),
        child: Container(
          color: _themeColor1.withOpacity(0.1),
          padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: _isVolumeExpanded ? 18.h : 14.h),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(Icons.volume_up_rounded, color: Colors.white, size: 20.r),
                  Text('Sound Settings', style: GoogleFonts.inter(color: Colors.white, fontSize: 14.sp, fontWeight: FontWeight.w500)),
                  Icon(_isVolumeExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 20.r),
                ],
              ),
              AnimatedCrossFade(
                duration: const Duration(milliseconds: 320),
                crossFadeState: _isVolumeExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                firstChild: const SizedBox(width: double.infinity, height: 0),
                secondChild: Padding(
                  padding: EdgeInsets.only(top: 16.h),
                  child: AdaptiveSlider(
                    value: _currentVolume,
                    min: 0.0,
                    max: 1.0,
                    activeColor: _themeColor1,
                    onChanged: _onVolumeChanged,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

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
                    children: List.generate(_ambientVideos.length, (index) {
                      final isSelected = _selectedAmbientIndex == index;
                      final v = _ambientVideos[index];
                      return AdaptiveButton.icon(
                        style: AdaptiveButtonStyle.plain,
                        onPressed: () => _selectAmbientVideo(index),
                        icon: v.icon,
                        iconColor: isSelected ? Colors.white : Colors.white54,
                      );
                    }),
                  ),
                ),
              ),
            )
          : const SizedBox.shrink(),
    );
  }

  Widget _buildPlaylistOverlay(double screenHeight) {
    return Positioned.fill(
      child: GestureDetector(
        onTap: _closePlaylist,
        child: Container(
          color: Colors.black.withOpacity(0.45),
          alignment: Alignment.bottomCenter,
          child: GestureDetector(
            onTap: () {},
            child: AdaptiveBlurView(
              borderRadius: BorderRadius.vertical(top: Radius.circular(26.r)),
              child: Container(
                height: screenHeight * 0.58,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.14),
                  border: Border(top: BorderSide(color: Colors.white.withOpacity(0.2), width: 1)),
                ),
                child: Column(
                  children: [
                    SizedBox(height: 12.h),
                    Container(width: 36.w, height: 4.h, decoration: BoxDecoration(color: Colors.white30, borderRadius: BorderRadius.circular(2.r))),
                    SizedBox(height: 16.h),
                    Text('Playlist', style: GoogleFonts.inter(color: Colors.white, fontSize: 17.sp, fontWeight: FontWeight.w700)),
                    SizedBox(height: 12.h),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _audioFiles.length,
                        itemBuilder: (context, i) {
                          final isActive = i == audioIndex;
                          return ListTile(
                            leading: Icon(isActive ? Icons.music_note_rounded : Icons.music_note_outlined, color: isActive ? Colors.white : Colors.white38, size: 20.r),
                            title: Text(
                              _stripExtension(_audioFiles[i].split('/').last),
                              style: GoogleFonts.inter(color: isActive ? Colors.white : Colors.white70, fontSize: 14.sp, fontWeight: isActive ? FontWeight.w700 : FontWeight.w400),
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
    );
  }
}
