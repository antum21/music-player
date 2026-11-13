// ============================================================
// Pemutar Musik Glassmorphism + Lagu dari Penyimpanan Lokal
//
// Dependency (jalankan di terminal):
//   flutter pub add just_audio
//   flutter pub add file_picker
//
// Android: tambahkan izin internet (untuk lagu streaming) di
//   android/app/src/main/AndroidManifest.xml
//   <uses-permission android:name="android.permission.INTERNET"/>
//
// Memilih file lewat file picker bawaan sistem tidak butuh izin
// storage khusus. Ganti isi lib/main.dart dengan file ini.
// ============================================================

import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

void main() => runApp(const MusicPlayerApp());

class Song {
  final String title;
  final String artist;
  final String url; // URL (streaming) atau path file (lokal)
  final Color color;
  final bool isLocal;
  const Song(
    this.title,
    this.artist,
    this.url,
    this.color, {
    this.isLocal = false,
  });
}

const playlist = [
  Song(
    'SoundHelix Song 1',
    'SoundHelix',
    'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3',
    Color(0xFF7C4DFF),
  ),
  Song(
    'SoundHelix Song 2',
    'SoundHelix',
    'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-2.mp3',
    Color(0xFF00BCD4),
  ),
  Song(
    'SoundHelix Song 3',
    'SoundHelix',
    'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-3.mp3',
    Color(0xFFFF4081),
  ),
];

// Warna aksen untuk lagu lokal (dipakai bergantian)
const localColors = [
  Color(0xFFFF9800),
  Color(0xFF4CAF50),
  Color(0xFF03A9F4),
  Color(0xFFE91E63),
  Color(0xFF9C27B0),
];

class MusicPlayerApp extends StatelessWidget {
  const MusicPlayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pemutar Musik',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        colorSchemeSeed: Colors.deepPurple,
      ),
      home: const PlayerPage(),
    );
  }
}

/// Kotak kaca (efek blur + transparan + border tipis)
class GlassBox extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsets padding;
  final double blur;
  final double opacity;

  const GlassBox({
    super.key,
    required this.child,
    this.radius = 28,
    this.padding = const EdgeInsets.all(20),
    this.blur = 25,
    this.opacity = 0.12,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: Colors.white.withOpacity(0.25)),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withOpacity(opacity + 0.08),
                Colors.white.withOpacity(opacity - 0.04),
              ],
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key});

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage>
    with SingleTickerProviderStateMixin {
  final AudioPlayer _player = AudioPlayer();
  late final AnimationController _spin;
  final TextEditingController _searchCtrl = TextEditingController();

  // Daftar lagu yang bisa bertambah (streaming + lokal)
  final List<Song> _songs = List.of(playlist);

  int _index = 0;
  String _query = '';
  bool _isPlaying = false;
  bool _isLoading = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    );
    _loadSong(_index);

    _player.positionStream.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _player.durationStream.listen((d) {
      if (mounted) setState(() => _duration = d ?? Duration.zero);
    });
    _player.playerStateStream.listen((state) {
      if (!mounted) return;
      setState(() {
        _isPlaying = state.playing;
        _isLoading =
            state.processingState == ProcessingState.loading ||
            state.processingState == ProcessingState.buffering;
      });
      if (state.playing) {
        _spin.repeat();
      } else {
        _spin.stop();
      }
      if (state.processingState == ProcessingState.completed) _next();
    });
  }

  // ---------- Logika pemutar ----------

  Future<void> _loadSong(int index, {bool autoPlay = false}) async {
    final song = _songs[index];
    try {
      if (song.isLocal) {
        await _player.setFilePath(song.url);
      } else {
        await _player.setUrl(song.url);
      }
      if (autoPlay) _player.play();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Gagal memuat lagu: $e')));
      }
    }
  }

  void _selectSong(int index) {
    if (index == _index) {
      _togglePlay();
      return;
    }
    setState(() {
      _index = index;
      _position = Duration.zero;
    });
    _loadSong(index, autoPlay: true);
  }

  void _togglePlay() => _isPlaying ? _player.pause() : _player.play();
  void _next() => _selectSong((_index + 1) % _songs.length);
  void _previous() => _selectSong((_index - 1 + _songs.length) % _songs.length);

  // ---------- Cari lagu di penyimpanan lokal ----------

  Future<void> _pickLocalSongs() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: true,
      );
      if (result == null) return; // dibatalkan

      final firstNewIndex = _songs.length;
      var added = 0;

      for (final f in result.files) {
        final path = f.path;
        if (path == null) continue;
        if (_songs.any((s) => s.url == path)) continue; // hindari duplikat

        _songs.add(
          Song(
            _stripExtension(f.name),
            'Penyimpanan perangkat',
            path,
            localColors[_songs.length % localColors.length],
            isLocal: true,
          ),
        );
        added++;
      }

      if (!mounted) return;
      if (added == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tidak ada lagu baru yang ditambahkan')),
        );
        return;
      }

      // Kosongkan pencarian agar lagu baru terlihat, lalu putar yang pertama
      _searchCtrl.clear();
      setState(() {
        _query = '';
        _index = firstNewIndex;
        _position = Duration.zero;
      });
      await _loadSong(firstNewIndex, autoPlay: true);

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$added lagu ditambahkan')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Gagal membuka file: $e')));
      }
    }
  }

  String _stripExtension(String name) {
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  /// Indeks lagu yang cocok dengan kata kunci pencarian
  List<int> get _filteredIndexes {
    final q = _query.trim().toLowerCase();
    return [
      for (int i = 0; i < _songs.length; i++)
        if (q.isEmpty ||
            _songs[i].title.toLowerCase().contains(q) ||
            _songs[i].artist.toLowerCase().contains(q))
          i,
    ];
  }

  String _format(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void dispose() {
    _spin.dispose();
    _searchCtrl.dispose();
    _player.dispose();
    super.dispose();
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    final song = _songs[_index];
    final indexes = _filteredIndexes;

    return Scaffold(
      body: Stack(
        children: [
          _buildBackground(song.color),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              children: [
                _buildHeader(),
                const SizedBox(height: 20),
                _buildPlayerCard(song),
                const SizedBox(height: 28),
                _buildListHeader(),
                const SizedBox(height: 12),
                _buildSearchField(),
                const SizedBox(height: 14),
                if (indexes.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        'Lagu tidak ditemukan',
                        style: TextStyle(color: Colors.white60),
                      ),
                    ),
                  )
                else
                  for (final i in indexes) _buildTile(i),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackground(Color accent) {
    return Stack(
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0F0C29), Color(0xFF302B63), Color(0xFF24243E)],
            ),
          ),
        ),
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 70, sigmaY: 70),
          child: Stack(
            children: [
              Positioned(top: -60, left: -60, child: _orb(accent, 260)),
              Positioned(
                top: 280,
                right: -90,
                child: _orb(accent.withOpacity(0.7), 300),
              ),
              Positioned(
                bottom: -80,
                left: 20,
                child: _orb(const Color(0xFF3F51B5), 260),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _orb(Color color, double size) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 700),
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withOpacity(0.55),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _glassIconButton(Icons.keyboard_arrow_down_rounded, () {}),
        const Text(
          'SEDANG DIPUTAR',
          style: TextStyle(
            fontSize: 11,
            letterSpacing: 2,
            color: Colors.white70,
          ),
        ),
        _glassIconButton(Icons.folder_open_rounded, _pickLocalSongs),
      ],
    );
  }

  Widget _glassIconButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: GlassBox(
        radius: 16,
        padding: const EdgeInsets.all(10),
        blur: 15,
        child: Icon(icon, size: 22),
      ),
    );
  }

  Widget _buildListHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 6),
          child: Text(
            'Daftar Putar',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
        ),
        GestureDetector(
          onTap: _pickLocalSongs,
          child: const GlassBox(
            radius: 14,
            blur: 15,
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.library_music_rounded, size: 18),
                SizedBox(width: 6),
                Text('Cari di perangkat', style: TextStyle(fontSize: 13)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchField() {
    return GlassBox(
      radius: 20,
      blur: 18,
      opacity: 0.1,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: TextField(
        controller: _searchCtrl,
        onChanged: (v) => setState(() => _query = v),
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: 'Cari judul atau artis...',
          hintStyle: const TextStyle(color: Colors.white54),
          icon: const Icon(Icons.search_rounded, color: Colors.white70),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() => _query = '');
                  },
                ),
        ),
      ),
    );
  }

  Widget _buildPlayerCard(Song song) {
    final maxValue = _duration.inMilliseconds.toDouble();
    final value = _position.inMilliseconds
        .toDouble()
        .clamp(0, maxValue > 0 ? maxValue : 1)
        .toDouble();

    return GlassBox(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      child: Column(
        children: [
          RotationTransition(
            turns: _spin,
            child: Container(
              width: 210,
              height: 210,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: SweepGradient(
                  colors: [
                    song.color,
                    song.color.withOpacity(0.35),
                    Colors.white.withOpacity(0.8),
                    song.color.withOpacity(0.35),
                    song.color,
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: song.color.withOpacity(0.5),
                    blurRadius: 40,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Center(
                child: Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF1A1740),
                    border: Border.all(color: Colors.white24, width: 3),
                  ),
                  child: Icon(
                    song.isLocal
                        ? Icons.phone_android_rounded
                        : Icons.music_note_rounded,
                    size: 30,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 28),
          Text(
            song.title,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            song.artist,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 20),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              activeTrackColor: Colors.white,
              inactiveTrackColor: Colors.white24,
              thumbColor: Colors.white,
              overlayColor: Colors.white24,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
              min: 0,
              max: maxValue > 0 ? maxValue : 1,
              value: value,
              onChanged: (v) => _player.seek(Duration(milliseconds: v.toInt())),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _format(_position),
                  style: const TextStyle(color: Colors.white70),
                ),
                Text(
                  _format(_duration),
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                iconSize: 38,
                icon: const Icon(Icons.skip_previous_rounded),
                onPressed: _previous,
              ),
              const SizedBox(width: 18),
              _buildPlayButton(song.color),
              const SizedBox(width: 18),
              IconButton(
                iconSize: 38,
                icon: const Icon(Icons.skip_next_rounded),
                onPressed: _next,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPlayButton(Color color) {
    return GestureDetector(
      onTap: _isLoading ? null : _togglePlay,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 500),
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [color, color.withOpacity(0.6)],
          ),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.55),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: _isLoading
            ? const Padding(
                padding: EdgeInsets.all(22),
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: Colors.white,
                ),
              )
            : Icon(
                _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: 40,
                color: Colors.white,
              ),
      ),
    );
  }

  Widget _buildTile(int i) {
    final song = _songs[i];
    final active = i == _index;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: () => _selectSong(i),
        child: GlassBox(
          radius: 20,
          blur: 18,
          opacity: active ? 0.2 : 0.1,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: LinearGradient(
                    colors: [song.color, song.color.withOpacity(0.5)],
                  ),
                ),
                child: Icon(
                  active && _isPlaying
                      ? Icons.graphic_eq_rounded
                      : (song.isLocal
                            ? Icons.phone_android_rounded
                            : Icons.music_note_rounded),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: active
                            ? Colors.white
                            : Colors.white.withOpacity(0.9),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      song.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                active && _isPlaying
                    ? Icons.pause_circle_filled_rounded
                    : Icons.play_circle_fill_rounded,
                color: active ? Colors.white : Colors.white54,
                size: 30,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
