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

/// Plays one user-selected audio file locally while this screen is visible.
/// No file bytes or metadata are sent to the assistant or a remote service.
class LocalAudioPreview extends StatefulWidget {
  const LocalAudioPreview({super.key});

  @override
  State<LocalAudioPreview> createState() => _LocalAudioPreviewState();
}

class _LocalAudioPreviewState extends State<LocalAudioPreview>
    with WidgetsBindingObserver {
  final AudioPlayer _player = AudioPlayer();
  String? _fileName;
  String? _error;
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
    });
    try {
      final files = await FilePicker.pickFiles(type: FileType.audio);
      if (!mounted || files.isEmpty) return;
      final file = files.single;
      final path = file.path;
      if (path == null || path.isEmpty) {
        throw const FormatException(
          'This audio file could not be opened locally.',
        );
      }
      await _player.setFilePath(path);
      if (!mounted) return;
      setState(() => _fileName = file.name);
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Could not open this audio file: $error');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _togglePlayback(PlayerState state) async {
    if (_busy || _fileName == null) return;
    try {
      setState(() => _error = null);
      if (state.playing) {
        await _player.pause();
      } else {
        if (state.processingState == ProcessingState.completed) {
          await _player.seek(Duration.zero);
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
            'Choose one audio file to play on this device. It stays local.',
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : _chooseAudio,
            icon: const Icon(Icons.audio_file_outlined),
            label: Text(_busy ? 'Opening audio…' : 'Choose audio'),
          ),
          if (_fileName case final name?) ...[
            const SizedBox(height: 8),
            Text(name, maxLines: 2, overflow: TextOverflow.ellipsis),
            StreamBuilder<PlayerState>(
              stream: _player.playerStateStream,
              builder: (context, snapshot) {
                final state = snapshot.data;
                return Row(
                  children: [
                    IconButton(
                      tooltip: state?.playing == true
                          ? 'Pause audio'
                          : 'Play audio',
                      onPressed: _busy || state == null
                          ? null
                          : () => _togglePlayback(state),
                      icon: Icon(
                        state?.playing == true ? Icons.pause : Icons.play_arrow,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Stop audio',
                      onPressed: _busy || state == null ? null : _stopPlayback,
                      icon: const Icon(Icons.stop),
                    ),
                    Expanded(
                      child: StreamBuilder<Duration>(
                        stream: _player.positionStream,
                        builder: (context, positionSnapshot) {
                          final position =
                              positionSnapshot.data ?? Duration.zero;
                          final duration = _player.duration ?? Duration.zero;
                          final maxMs = duration.inMilliseconds > 0
                              ? duration.inMilliseconds.toDouble()
                              : 1.0;
                          final value =
                              (_scrubPositionMs ??
                                      position.inMilliseconds.toDouble())
                                  .clamp(0.0, maxMs);
                          return Slider(
                            min: 0,
                            max: maxMs,
                            value: value,
                            onChanged: _busy || duration <= Duration.zero
                                ? null
                                : (next) =>
                                      setState(() => _scrubPositionMs = next),
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
                    ),
                  ],
                );
              },
            ),
            StreamBuilder<Duration>(
              stream: _player.positionStream,
              builder: (context, snapshot) {
                final position = _scrubPositionMs == null
                    ? snapshot.data ?? Duration.zero
                    : Duration(milliseconds: _scrubPositionMs!.round());
                final duration = _player.duration ?? Duration.zero;
                return Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '${audioTimeLabel(position)} / ${audioTimeLabel(duration)}',
                  ),
                );
              },
            ),
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
