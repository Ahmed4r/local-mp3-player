import 'dart:developer';
import 'dart:typed_data';
import 'dart:io';

import 'package:audioplayer/screens/audioplayer_screen.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_media_metadata/flutter_media_metadata.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

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
  String? _savedFolderPath;
  Uint8List? albumImageBytes;

  @override
  void initState() {
    super.initState();
    _loadSavedFiles();
  }

  Future<void> _loadSavedFiles() async {
    final prefs = await SharedPreferences.getInstance();
    final files = prefs.getStringList('mp3_files') ?? [];

    // تحقق إن الملفات لسه موجودة في الجهاز
    final validFiles = files.where((path) => File(path).existsSync()).toList();

    setState(() {
      _mp3Files = validFiles;
      _currentIndex = null;
      _playerState = PlayerState.stopped;
    });

    // حدث SharedPreferences (احذف الملفات اللي اتمسحت)
    prefs.setStringList('mp3_files', validFiles);
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3'],
      allowMultiple: true,
    );

    if (result == null || result.files.isEmpty) return;

    final newFiles = result.files
        .where((file) => file.path != null && file.path!.endsWith('.mp3'))
        .map((file) => file.path!)
        .toList();

    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getStringList('mp3_files') ?? [];

    // ✅ أضف فقط الملفات اللي مش موجودة
    final uniqueNewFiles = newFiles
        .where((path) => !existing.contains(path))
        .toList();

    if (uniqueNewFiles.isEmpty) {
      // ممكن تعرض SnackBar أو Alert إن الملفات كلها كانت موجودة
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All selected files already exist')),
      );
      return;
    }

    final allFiles = [...existing, ...uniqueNewFiles];

    await prefs.setStringList('mp3_files', allFiles);

    setState(() {
      _mp3Files = allFiles;
      _currentIndex = null;
      _playerState = PlayerState.stopped;
    });
  }

  Future<List<String>> _listMp3FilesRecursively(Directory dir) async {
    final files = <String>[];
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File && p.extension(entity.path).toLowerCase() == '.mp3') {
        files.add(entity.path);
      }
    }

    final prefs = await SharedPreferences.getInstance();
    prefs.setString('saved_folder_path', dir.path);
    prefs.setStringList('mp3_files', files);

    log('Saved folder path: ${dir.path}');
    log('Saved mp3 files: ${files.join(', ')}');

    setState(() {
      _mp3Files = files;
      _currentIndex = null;
      _playerState = PlayerState.stopped;
    });

    return files;
  }

  Future<void> _clearAllFiles() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('mp3_files');
    setState(() {
      _mp3Files.clear();
      _currentIndex = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        leading: IconButton(
          onPressed: _clearAllFiles,
          tooltip: 'Clear All Files',
          icon: Icon(Icons.delete, color: Colors.white),
        ),
        backgroundColor: Colors.black,
        title: const Text(
          'Audio Player',
          style: TextStyle(color: Colors.white),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_open, color: Colors.white),
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
                      style: TextStyle(color: Colors.white),
                    ),
                  )
                : ListView.builder(
                    itemCount: _mp3Files.length,
                    itemBuilder: (context, index) {
                      final isSelected = _currentIndex == index;
                      return FutureBuilder<Uint8List?>(
                        future: _getTrackImage(_mp3Files[index]),
                        builder: (context, snapshot) {
                          final coverImage = snapshot.data;

                          return Dismissible(
                            key: Key(_mp3Files[index]),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: EdgeInsets.symmetric(horizontal: 20.w),
                              color: Colors.red,
                              child: Icon(Icons.delete, color: Colors.white),
                            ),
                            onDismissed: (direction) async {
                              final removedFile = _mp3Files.removeAt(index);
                              final prefs =
                                  await SharedPreferences.getInstance();
                              prefs.setStringList('mp3_files', _mp3Files);
                              setState(() {});
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '${p.basename(removedFile)} removed',
                                  ),
                                ),
                              );
                            },
                            child: ListTile(
                              splashColor: Colors.amber,
                              contentPadding: EdgeInsets.all(10.r),
                              leading: coverImage != null
                                  ? Image.memory(
                                      coverImage,
                                      fit: BoxFit.cover,
                                      scale: 4.sp,
                                    )
                                  : Image.asset(
                                      'assets/Song Cover Art 1.png',
                                      fit: BoxFit.cover,
                                      scale: 4.sp,
                                    ),
                              title: Text(
                                p.basename(_mp3Files[index]),
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18.sp,
                                ),
                              ),
                              onTap: () async {
                                final metadata =
                                    await MetadataRetriever.fromFile(
                                      File(_mp3Files[index]),
                                    );

                                setState(() {
                                  albumImageBytes = metadata.albumArt;
                                  _currentIndex = index;
                                });

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
                            ),
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

  Future<Uint8List?> _getTrackImage(String path) async {
    try {
      final metadata = await MetadataRetriever.fromFile(File(path));
      return metadata.albumArt;
    } catch (e) {
      return null;
    }
  }
}
