import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

String audioTimeLabel(Duration duration) {
  final seconds = duration.inSeconds < 0 ? 0 : duration.inSeconds;
  final minutes = seconds ~/ 60;
  final remainder = seconds % 60;
  return '$minutes:${remainder.toString().padLeft(2, '0')}';
}

const int maxLocalAudioQueueLength = 25;

/// Converts picker results into a bounded, in-memory local playback queue.
/// Files without a usable local path and duplicate paths are ignored.
List<LocalAudioTrack> localAudioTracks(
  Iterable<PlatformFile> files, {
  int maxTracks = maxLocalAudioQueueLength,
}) {
  if (maxTracks <= 0) return const [];
  final tracks = <LocalAudioTrack>[];
  final paths = <String>{};
  for (final file in files) {
    final path = file.path;
    if (path == null || path.isEmpty || !paths.add(path)) continue;
    final fallbackName = path.split('/').last;
    final name = file.name.trim().isEmpty ? fallbackName : file.name.trim();
    tracks.add(LocalAudioTrack(name: name, path: path));
    if (tracks.length == maxTracks) break;
  }
  return List.unmodifiable(tracks);
}

class LocalAudioTrack {
  const LocalAudioTrack({required this.name, required this.path});

  final String name;
  final String path;
}

/// Plays a user-selected, temporary queue of local audio files while this
/// screen is visible. No file bytes or metadata are sent to a remote service.
class LocalAudioPreview extends StatefulWidget {
  const LocalAudioPreview({super.key});

  @override
  State<LocalAudioPreview> createState() => _LocalAudioPreviewState();
}

class _LocalAudioPreviewState extends State<LocalAudioPreview>
    with WidgetsBindingObserver {
  final AudioPlayer _player = AudioPlayer();
  List<LocalAudioTrack> _tracks = const [];
  String? _error;
  String? _notice;
  bool _busy = false;
  double? _scrubPositionMs;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      unawaited(_player.pause().catchError((Object _) {}));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_player.dispose());
    super.dispose();
  }

  Future<void> _chooseAudio() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      final files = await FilePicker.pickFiles(
        dialogTitle: 'Choose audio files',
        type: FileType.audio,
      );
      if (!mounted || files.isEmpty) return;
      final tracks = localAudioTracks(files);
      if (tracks.isEmpty) {
        throw const FormatException(
          'These audio files could not be opened locally.',
        );
      }
      await _player.setAudioSources(
        tracks.map((track) => AudioSource.file(track.path, tag: track.name)).toList(),
        initialIndex: 0,
      );
      if (!mounted) return;
      setState(() {
        _tracks = tracks;
        _scrubPositionMs = null;
        if (files.length > tracks.length) {
          _notice = 'Using up to ${tracks.length} unique files with local paths.';
        }
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Could not open these audio files: $error');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _togglePlayback(PlayerState state) async {
    if (_busy || _tracks.isEmpty) return;
    try {
      setState(() => _error = null);
      if (state.playing) {
        await _player.pause();
      } else {
        if (state.processingState == ProcessingState.completed) {
          await _player.seek(Duration.zero, index: _player.currentIndex);
        }
        await _player.play();
      }
    } catch (error) {
      if (mounted) setState(() => _error = 'Audio playback failed: $error');
    }
  }

  Future<void> _stopPlayback() async {
    try {
      setState(() => _error = null);
      await _player.stop();
      if (mounted) setState(() => _scrubPositionMs = null);
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Audio could not be stopped: $error');
      }
    }
  }

  Future<void> _selectTrack(int index) async {
    if (_busy || index < 0 || index >= _tracks.length) return;
    try {
      setState(() {
        _busy = true;
        _error = null;
        _scrubPositionMs = null;
      });
      await _player.seek(Duration.zero, index: index);
      await _player.play();
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not play this track: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _skipToPrevious() async {
    try {
      await _player.seekToPrevious();
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not play the previous track: $error');
    }
  }

  Future<void> _skipToNext() async {
    try {
      await _player.seekToNext();
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not play the next track: $error');
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Local audio preview',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          const Text(
            'Choose audio files for a temporary queue on this device. They stay local.',
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : _chooseAudio,
            icon: const Icon(Icons.audio_file_outlined),
            label: Text(_busy ? 'Opening audio…' : 'Choose audio files'),
          ),
          if (_tracks.isNotEmpty) ...[
            const SizedBox(height: 8),
            StreamBuilder<int?>(
              stream: _player.currentIndexStream,
              builder: (context, indexSnapshot) {
                final index = indexSnapshot.data ?? 0;
                final safeIndex = index.clamp(0, _tracks.length - 1);
                final track = _tracks[safeIndex];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.name,
                      key: const ValueKey('current-audio-track'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    StreamBuilder<PlayerState>(
                      stream: _player.playerStateStream,
                      builder: (context, playerSnapshot) {
                        final state = playerSnapshot.data;
                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Previous track',
                              onPressed: _busy || !_player.hasPrevious
                                  ? null
                                  : _skipToPrevious,
                              icon: const Icon(Icons.skip_previous),
                            ),
                            IconButton(
                              tooltip: state?.playing == true
                                  ? 'Pause audio'
                                  : 'Play audio',
                              onPressed: _busy || state == null
                                  ? null
                                  : () => _togglePlayback(state),
                              icon: Icon(
                                state?.playing == true
                                    ? Icons.pause
                                    : Icons.play_arrow,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Stop audio',
                              onPressed: _busy || state == null
                                  ? null
                                  : _stopPlayback,
                              icon: const Icon(Icons.stop),
                            ),
                            IconButton(
                              tooltip: 'Next track',
                              onPressed: _busy || !_player.hasNext
                                  ? null
                                  : _skipToNext,
                              icon: const Icon(Icons.skip_next),
                            ),
                          ],
                        );
                      },
                    ),
                    StreamBuilder<Duration>(
                      stream: _player.positionStream,
                      builder: (context, positionSnapshot) {
                        final position =
                            positionSnapshot.data ?? Duration.zero;
                        final duration = _player.duration ?? Duration.zero;
                        final maxMs = duration.inMilliseconds > 0
                            ? duration.inMilliseconds.toDouble()
                            : 1.0;
                        final value = (_scrubPositionMs ??
                                position.inMilliseconds.toDouble())
                            .clamp(0.0, maxMs);
                        return Slider(
                          min: 0,
                          max: maxMs,
                          value: value,
                          onChanged: _busy || duration <= Duration.zero
                              ? null
                              : (next) => setState(
                                  () => _scrubPositionMs = next,
                                ),
                          onChangeEnd: duration <= Duration.zero
                              ? null
                              : (next) {
                                  setState(() => _scrubPositionMs = null);
                                  unawaited(
                                    _player
                                        .seek(
                                          Duration(
                                            milliseconds: next.round(),
                                          ),
                                        )
                                        .catchError((Object error) {
                                          if (mounted) {
                                            setState(
                                              () => _error =
                                                  'Could not seek in audio: $error',
                                            );
                                          }
                                        }),
                                  );
                                },
                        );
                      },
                    ),
                    StreamBuilder<Duration>(
                      stream: _player.positionStream,
                      builder: (context, snapshot) {
                        final position = _scrubPositionMs == null
                            ? snapshot.data ?? Duration.zero
                            : Duration(
                                milliseconds: _scrubPositionMs!.round(),
                              );
                        final duration = _player.duration ?? Duration.zero;
                        return Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            '${audioTimeLabel(position)} / ${audioTimeLabel(duration)}',
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 4),
                    Text('Queue · ${_tracks.length} / $maxLocalAudioQueueLength'),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 240),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _tracks.length,
                        itemBuilder: (context, row) {
                          final item = _tracks[row];
                          final selected = row == safeIndex;
                          return ListTile(
                            dense: true,
                            selected: selected,
                            leading: Icon(
                              selected ? Icons.equalizer : Icons.music_note,
                            ),
                            title: Text(
                              item.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: _busy ? null : () => _selectTrack(row),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
          if (_notice case final notice?) ...[
            const SizedBox(height: 8),
            Text(notice),
          ],
          if (_error case final error?) ...[
            const SizedBox(height: 8),
            Text(
              error,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    ),
  );
}
