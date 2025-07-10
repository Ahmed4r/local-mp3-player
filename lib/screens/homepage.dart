import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:onboarding/screens/audioplayer_screen.dart';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';  // Add this import

class Homepage extends StatefulWidget {
  static const String routeName = '/homepage';
  const Homepage({super.key});

  @override
  _HomepageState createState() => _HomepageState();
}

class _HomepageState extends State<Homepage> {
  List<String> _mp3Files = [];
  int? _currentIndex;
  PlayerState _playerState = PlayerState.stopped;
  String? _savedFolderPath;  // To hold saved folder path

  @override
  void initState() {
    super.initState();
    _loadSavedFolder();
  }

  Future<void> _loadSavedFolder() async {
    final prefs = await SharedPreferences.getInstance();
    final savedPath = prefs.getString('saved_folder_path');
    if (savedPath != null) {
      final dir = Directory(savedPath);
      if (await dir.exists()) {
        final files = await _listMp3FilesRecursively(dir);
        setState(() {
          _mp3Files = files;
          _savedFolderPath = savedPath;
          _currentIndex = null;
          _playerState = PlayerState.stopped;
        });
      } else {
        // Folder no longer exists, clear saved path
        prefs.remove('saved_folder_path');
      }
    }
  }

  Future<void> _pickFiles() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['mp3'],
    allowMultiple: true,
  );

  if (result == null || result.files.isEmpty) return;

 final files = result.files
    .where((file) => file.path != null && file.path!.endsWith('.mp3'))
    .map((file) => file.path!)
    .toList(); // List<String>


  if (files.isNotEmpty) {
    final prefs = await SharedPreferences.getInstance();
    // Saving paths is risky on iOS, just store them temporarily in memory

    setState(() {
     _mp3Files = files; // List<String>

      _savedFolderPath = null; // not used anymore
      _currentIndex = null;
      _playerState = PlayerState.stopped;
    });
  }
}


  Future<List<String>> _listMp3FilesRecursively(Directory dir) async {
    final files = <String>[];
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File && p.extension(entity.path).toLowerCase() == '.mp3') {
        files.add(entity.path);
      }
    }
    return files;
  }

  @override


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,  // Set scaffold background to black
      appBar: AppBar(
        leading: Icon(Icons.dark_mode,color: Colors.white,),
        backgroundColor: Colors.black,  // AppBar background black
        title: const Text(
          'Audio Player',
          style: TextStyle(color: Colors.white),  // Title text white
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_open, color: Colors.white),  // Icon white
            onPressed: _pickFiles,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _mp3Files.isEmpty
                ? const Center(
                    child: Text(
                      'No audio files found.',
                      style: TextStyle(color: Colors.white),  // Text white
                    ),
                  )
                : ListView.builder(
                    itemCount: _mp3Files.length,
                    itemBuilder: (context, index) {
                      final isSelected = _currentIndex == index;
                      return ListTile(
                        splashColor: Colors.amber,
                       contentPadding: EdgeInsets.all(10.r),
                        leading: Image.asset('assets/apple-music-note.jpg',filterQuality: FilterQuality.high,scale: 4.sp,),
                        title: Text(
                          p.basename(_mp3Files[index]),
                          style:  TextStyle(color: Colors.white,fontSize: 18.sp),  // Text white
                        ),
                        onTap: () {
                          Navigator.pushNamed(
                            context,
                            AudioplayerScreen.routeName,
                            arguments: {
                              'selected': isSelected,
                              'audioPath': _mp3Files[index],
                              'audioTitle': p.basename(_mp3Files[index]),
                              'audioIndex': index,
                              'audioList': _mp3Files,
                            },
                          );
                        },
                        
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }



}
