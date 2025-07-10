import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();

    _playerStateSubscription = _audioPlayer.onPlayerStateChanged.listen((state) {
      if (!mounted) return;  // Check mounted before setState
      setState(() {
        _isPlaying = state == PlayerState.playing;
      });
    });

    _durationSubscription = _audioPlayer.onDurationChanged.listen((duration) {
      if (!mounted) return;
      setState(() {
        _totalDuration = duration;
      });
    });

    _positionSubscription = _audioPlayer.onPositionChanged.listen((position) {
      if (!mounted) return;
      setState(() {
        _currentPosition = position;
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
    audioPath = args['audioPath'];
    audioTitle = args['audioTitle'];
    _mp3Files = List<String>.from(args['audioList'] ?? []);
    audioIndex = args['audioIndex'] ?? 0;

    _audioPlayer.setSource(DeviceFileSource(audioPath));
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

  void _playPause() {
    if (_isPlaying) {
      _audioPlayer.pause();
    } else {
      _audioPlayer.resume();
    }
  }

  void _seekTo(Duration position) {
    _audioPlayer.seek(position);
  }

  void _playNext() {
    if (_mp3Files.isEmpty) return;
    audioIndex = (audioIndex + 1) % _mp3Files.length;
    audioPath = _mp3Files[audioIndex];
    audioTitle = audioPath.split('/').last;
    _audioPlayer.setSource(DeviceFileSource(audioPath));
    _audioPlayer.resume();
    if (mounted) setState(() {});
  }

  void _playPrevious() {
    if (_mp3Files.isEmpty) return;
    audioIndex = (audioIndex - 1 + _mp3Files.length) % _mp3Files.length;
    audioPath = _mp3Files[audioIndex];
    audioTitle = audioPath.split('/').last;
    _audioPlayer.setSource(DeviceFileSource(audioPath));
    _audioPlayer.resume();
    if (mounted) setState(() {});
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
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              height: 380.h,
              width: double.infinity,
              decoration: BoxDecoration(
                image: DecorationImage(
                  image: AssetImage('assets/Song Cover Art 1.png'),
                ),
              ),
            ),
           
            Text(
              audioTitle,
              style: const TextStyle(
                fontSize: 24,
                color: Colors.white,
                fontFamily: 'Nunito',
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 20.h),
            Slider(
              thumbColor: Color(0xff52D7BF),
              inactiveColor: Colors.grey,
    
              label:
                  '${_currentPosition.inMinutes}:${_currentPosition.inSeconds.remainder(60).toString().padLeft(2, '0')} / ${_totalDuration.inMinutes}:${_totalDuration.inSeconds.remainder(60).toString().padLeft(2, '0')}',
              activeColor: Color(0xff52D7BF),
              min: 0,
              max: _totalDuration.inMilliseconds.toDouble(),
              value: _currentPosition.inMilliseconds
                  .clamp(0, _totalDuration.inMilliseconds)
                  .toDouble(),
              onChanged: (value) {
                _seekTo(Duration(milliseconds: value.toInt()));
              },
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
                  SizedBox(height: 10.h,),
                  Text(
                    'Up next',
                    style: GoogleFonts.bakbakOne(
                      color: Colors.white,
                      fontSize: 20,
                    ),
                  ),
                  SizedBox(height: 10.h),
                  Text(
                    '${_mp3Files[audioIndex < _mp3Files.length - 1 ? audioIndex + 1 : 0].split('/').last}',
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
                  icon: const Icon(
                    Icons.skip_previous_rounded,
                    size: 30,
                    color: Colors.white,
                  ),
                ),
                IconButton(
                  onPressed: _playPause,
                  icon: Icon(
                    _isPlaying
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_fill,
                    size: 70,
                    color: Colors.white,
                  ),
                ),
                IconButton(
                  onPressed: _playNext,
                  icon: const Icon(
                    Icons.skip_next_rounded,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
              IconButton(
  onPressed: () {
    setState(() => _isLooping = !_isLooping);
    _audioPlayer.setReleaseMode(_isLooping ? ReleaseMode.loop : ReleaseMode.release);
  },
  icon: Icon(
    Icons.loop,
    color: _isLooping ? const Color(0xff52D7BF) : Colors.white,
    size: 30,
  ),
),


              ],
            ),
          ],
        ),
      ),
    );
  }
}
