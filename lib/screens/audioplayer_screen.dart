import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_media_metadata/flutter_media_metadata.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

class AudioplayerScreen extends StatefulWidget {
  static const String routeName = 'player';
  const AudioplayerScreen({super.key});

  @override
  _AudioplayerScreenState createState() => _AudioplayerScreenState();
}

class _AudioplayerScreenState extends State<AudioplayerScreen> {
  late AudioPlayer _audioPlayer;
  late String audioPath;
  late String audioTitle;
  late List<String> _mp3Files;
  int audioIndex = 0;

  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;
   bool _isPlaying = false;

  late StreamSubscription<PlayerState> _playerStateSubscription;
  late StreamSubscription<Duration> _durationSubscription;
  late StreamSubscription<Duration> _positionSubscription;

  bool _isLooping = false;
  Uint8List? albumImageBytes;

  String? artistName;
  String? albumName;

  Future<void> getAlbumImage() async {
  try {
    albumImageBytes = null;
    artistName = null;
    albumName = null;
    setState(() {}); // عشان يمسح القديم فورًا

    final file = File(audioPath);
    final metadata = await MetadataRetriever.fromFile(file);

    if (metadata.albumArt != null) {
      albumImageBytes = metadata.albumArt;
    }
    artistName = metadata.albumArtistName;
    albumName = metadata.albumName;

    setState(() {});
  } catch (e) {
    log('Error reading album art: $e');
  }
}


  @override
  @override
void initState() {
  super.initState();

  _audioPlayer = AudioPlayer();

  _playerStateSubscription = _audioPlayer.onPlayerStateChanged.listen((state) {
    if (mounted) {
      setState(() {
        _isPlaying = state == PlayerState.playing;
      });
    }

    if (state == PlayerState.completed && !_isLooping) {
      _playNext();
    }
  });

  _durationSubscription = _audioPlayer.onDurationChanged.listen((duration) {
    if (mounted) {
      setState(() => _totalDuration = duration);
    }
  });

  _positionSubscription = _audioPlayer.onPositionChanged.listen((position) {
    if (mounted) {
      setState(() => _currentPosition = position);
    }
  });
}


  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args =
        ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
    audioPath = args['audioPath'];
    audioTitle = args['audioTitle'];
    _mp3Files = List<String>.from(args['audioList'] ?? []);
    audioIndex = args['audioIndex'] ?? 0;

    _audioPlayer.setSource(DeviceFileSource(audioPath));
     getAlbumImage();
    _audioPlayer.resume();
   
  }

  @override
  void dispose() {
    _playerStateSubscription.cancel();
    _durationSubscription.cancel();
    _positionSubscription.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  void _playPause() async {
  if (_isPlaying) {
    await _audioPlayer.pause();
  } else {
    await _audioPlayer.resume();
  }
}

  void _playNext() async{
   
    if (_mp3Files.isEmpty) return;
    audioIndex = (audioIndex + 1) % _mp3Files.length;
    audioPath = _mp3Files[audioIndex];
    audioTitle = audioPath.split('/').last;
    _audioPlayer.setSource(DeviceFileSource(audioPath));
    await  getAlbumImage();
    _audioPlayer.resume();
   
    if (mounted) setState(() {});
  }

  void _playPrevious() {
    if (_mp3Files.isEmpty) return;
    audioIndex = (audioIndex - 1 + _mp3Files.length) % _mp3Files.length;
    audioPath = _mp3Files[audioIndex];
    audioTitle = audioPath.split('/').last;
    _audioPlayer.setSource(DeviceFileSource(audioPath));
     getAlbumImage();
    _audioPlayer.resume();
   
    if (mounted) setState(() {});
  }

  String formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes);
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: BackButton(color: Colors.white),
        title: Text(
          'Now playing',
          style: GoogleFonts.bakbakOne(color: Colors.white, fontSize: 20),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.all(16.r),
          child: Column(
            children: [
              Container(
                height: 360.h,
                width: double.infinity,
                decoration: BoxDecoration(
                  image: DecorationImage(
                    filterQuality: FilterQuality.high,
                    fit: BoxFit.cover,
                    scale: 4.sp,
                    image: albumImageBytes != null
                        ? MemoryImage(albumImageBytes!)
                        : const AssetImage('assets/Song Cover Art 1.png')
                              as ImageProvider,
                  ),
                ),
              ),

              Text(
                audioTitle,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 24.sp,
                  color: Colors.white,
                  fontFamily: 'Nunito',
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 20.h),
              if (artistName != null)
                Text(
                  artistName!,
                  style: TextStyle(color: Colors.grey, fontSize: 16.sp),
                  textAlign: TextAlign.center,
                ),

              if (albumName != null)
                Text(
                  albumName!,
                  style: TextStyle(color: Colors.grey, fontSize: 14.sp),
                  textAlign: TextAlign.center,
                ),

              Column(
                children: [
                  // Duration Text
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        formatDuration(_currentPosition),
                        style: TextStyle(color: Colors.white),
                      ),
                      Text(
                        formatDuration(_totalDuration),
                        style: TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                  // Slider
                  Slider(
                    min: 0,
                   max: _totalDuration.inMilliseconds > 0
    ? _totalDuration.inMilliseconds.toDouble()
    : 1.0,

                    value: _currentPosition.inMilliseconds
                        .clamp(0, _totalDuration.inMilliseconds)
                        .toDouble(),
                    onChanged: (value) {
                      _audioPlayer.seek(Duration(milliseconds: value.toInt()));
                    },

                    activeColor: Color(0xff52D7BF),
                    inactiveColor: Colors.grey,
                  ),
                ],
              ),
              Container(
                width: 350.w,
                height: 100.h,
                decoration: BoxDecoration(
                  color: Color.fromARGB(255, 23, 23, 23),
                  borderRadius: BorderRadius.circular(30.r),
                ),
                child: Column(
                  children: [
                    SizedBox(height: 10.h),
                    Text(
                      'Up next',
                      style: GoogleFonts.bakbakOne(
                        color: Colors.white,
                        fontSize: 20.sp,
                      ),
                    ),
                    SizedBox(height: 10.h),
                    Text(_mp3Files.isNotEmpty?
                      _mp3Files[audioIndex < _mp3Files.length - 1
                              ? audioIndex + 1
                              : 0]
                          .split('/')
                          .last: "no songs",
                      style: TextStyle(color: Colors.white, fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              SizedBox(height: 10.h),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  IconButton(
                    onPressed: _playPrevious,
                    icon: Icon(
                      Icons.skip_previous_rounded,
                      size: 30.r,
                      color: Colors.white,
                    ),
                  ),
                  IconButton(
  onPressed: _playPause,
  icon: Icon(
    _isPlaying
      ? Icons.pause_circle_filled
      : Icons.play_circle_fill,
    size: 70.r,
    color: Colors.white,
  ),
),

                  IconButton(
                    onPressed: _playNext,
                    icon: Icon(
                      Icons.skip_next_rounded,
                      color: Colors.white,
                      size: 30.r,
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      setState(() => _isLooping = !_isLooping);
                      _audioPlayer.setReleaseMode(
                        _isLooping ? ReleaseMode.loop : ReleaseMode.release,
                      );
                    },
                    icon: Icon(
                      Icons.loop,
                      color: _isLooping
                          ? const Color(0xff52D7BF)
                          : Colors.white,
                      size: 30.r,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
