import 'dart:typed_data';
import 'dart:io';
import 'dart:ui';
import 'package:audioplayer/screens/audioplayer_screen.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_media_metadata/flutter_media_metadata.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

const _kSupportedExtensions = ['mp3', 'm4a', 'wav', 'flac', 'aac', 'ogg'];
const _kPrefsKey = 'audio_files'; 

const _kBg1 = Color(0xFF000000); 
const _kBg2 = Color(0xFF0A0A0A); 
const _kAccent = Color(0xFF0fbcf9);

class Homepage extends StatefulWidget {
  static const String routeName = '/homepage';
  const Homepage({super.key});

  @override
  State<Homepage> createState() => _HomepageState();
}

class _HomepageState extends State<Homepage> with TickerProviderStateMixin {
  List<String> _audioFiles = [];
  List<String> _allFiles = [];
  bool _showingFavorites = false;

  final Map<String, Uint8List?> _artCache = {};
  final Set<String> _fetching = {};

  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnim;
  bool _isGlobalPlaying = false;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnim = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
    _loadSavedFiles();
    _loadFavorites();
    globalAudioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _isGlobalPlaying = state == PlayerState.playing);
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedFiles() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_kPrefsKey) ?? prefs.getStringList('mp3_files') ?? [];
    final valid = raw.where((f) => File(f).existsSync()).toList();
    await prefs.setStringList(_kPrefsKey, valid);
    await prefs.remove('mp3_files');

    if (mounted) {
      setState(() {
        _audioFiles = valid;
        _allFiles = valid;
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
          _audioFiles = _allFiles;
          _showingFavorites = false;
        } else {
          if (favs.isEmpty) return;
          _audioFiles = _allFiles.where((path) => favs.contains(path)).toList();
          _showingFavorites = true;
        }
      });
    }
  }

  Future<void> _prefetchArt(List<String> paths) async {
    for (final path in paths) {
      if (_artCache.containsKey(path) || _fetching.contains(path)) continue;
      _fetching.add(path);
      try {
        final meta = await MetadataRetriever.fromFile(File(path));
        _artCache[path] = meta.albumArt;
      } catch (_) {
        _artCache[path] = null;
      } finally {
        _fetching.remove(path);
        if (mounted) setState(() {});
      }
    }
  }

  bool _isSupportedExtension(String path) => _kSupportedExtensions.contains(p.extension(path).toLowerCase().replaceFirst('.', ''));

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: _kSupportedExtensions, allowMultiple: true);
    if (result == null || result.files.isEmpty) return;
    
    final newFiles = result.files.where((f) => f.path != null && _isSupportedExtension(f.path!)).map((f) => f.path!).toList();
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getStringList(_kPrefsKey) ?? [];
    final uniqueNew = newFiles.where((f) => !existing.contains(f)).toList();

    if (uniqueNew.isEmpty) return;

    final all = [...existing, ...uniqueNew];
    await prefs.setStringList(_kPrefsKey, all);

    if (mounted) {
      setState(() => _audioFiles = all);
      _prefetchArt(uniqueNew);
    }
  }

  Widget _buildMiniPlayer() {
    if (globalAudioPlayer.source == null) return const SizedBox.shrink();

    return AdaptiveBlurView(
      borderRadius: BorderRadius.only(topLeft: Radius.circular(24.r), topRight: Radius.circular(24.r)),
      child: Container(
        color: const Color(0xFF111111).withOpacity(0.55),
        padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 16.h),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _isGlobalPlaying ? 'Now Playing in Background...' : 'Paused',
                  style: TextStyle(color: Colors.white, fontSize: 14.sp, fontWeight: FontWeight.w600),
                ),
              ),
              AdaptiveButton.icon(
                icon: _isGlobalPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, 
                iconColor: _kAccent, 
                style: AdaptiveButtonStyle.plain,
                onPressed: () => _isGlobalPlaying ? globalAudioPlayer.pause() : globalAudioPlayer.resume(),
              ),
              AdaptiveButton.icon(
                icon: Icons.close_rounded, 
                iconColor: Colors.white54, 
                style: AdaptiveButtonStyle.plain,
                onPressed: () async {
                  await globalAudioPlayer.stop();
                  await globalAudioPlayer.release();
                  setState(() {});
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: AdaptiveBlurView(child: Container(color: Colors.black.withOpacity(0.3))),
        title: Text('GLASSIFY', style: GoogleFonts.bakbakOne(color: Colors.white, fontSize: 20.sp, letterSpacing: 3)),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [_kBg1, _kBg2, Color(0xFF0D0D0D), Color(0xFF000000)]),
            ),
          ),
          SafeArea(
            child: FadeTransition(
              opacity: _fadeAnim,
              child: _audioFiles.isEmpty ? const Center(child: Text("No audio files", style: TextStyle(color: Colors.white))) 
                  : ListView.builder(
                      itemCount: _audioFiles.length,
                      itemBuilder: (context, index) => ListTile(
                        title: Text(p.basename(_audioFiles[index]), style: const TextStyle(color: Colors.white)),
                        onTap: () => Navigator.pushNamed(context, AudioplayerScreen.routeName, arguments: {
                          'audioList': _audioFiles,
                          'audioPath': _audioFiles[index],
                          'audioTitle': p.basename(_audioFiles[index]),
                          'audioIndex': index
                        }),
                      ),
                    ),
            ),
          ),
          Align(alignment: Alignment.bottomCenter, child: _buildMiniPlayer()),
        ],
      ),
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: globalAudioPlayer.source != null ? 80.h : 0),
        child: FloatingActionButton(
          backgroundColor: _kAccent,
          onPressed: _pickFiles,
          child: const Icon(Icons.add, color: Colors.white),
        ),
      ),
    );
  }
}
