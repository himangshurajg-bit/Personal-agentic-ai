import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_assistant/local_audio_preview.dart';

final class _TestPlatformFile extends PlatformFile {
  _TestPlatformFile(this.name, this.path);

  @override
  final String name;

  @override
  final String? path;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

void main() {
  group('audioTimeLabel', () {
    test('formats minutes and seconds', () {
      expect(audioTimeLabel(const Duration(seconds: 0)), '0:00');
      expect(audioTimeLabel(const Duration(seconds: 65)), '1:05');
    });

    test('keeps long tracks in total minutes', () {
      expect(audioTimeLabel(const Duration(hours: 1, seconds: 2)), '60:02');
    });

    test('clamps a negative duration to zero', () {
      expect(audioTimeLabel(const Duration(seconds: -1)), '0:00');
    });
  });

  group('localAudioTracks', () {
    PlatformFile file(String name, String? path) =>
        _TestPlatformFile(name, path);

    test('keeps only unique files with usable local paths', () {
      final tracks = localAudioTracks([
        file('first.mp3', '/music/first.mp3'),
        file('missing.mp3', null),
        file('duplicate.mp3', '/music/first.mp3'),
        file('second.ogg', '/music/second.ogg'),
        file('empty.mp3', ''),
      ]);

      expect(tracks.map((track) => track.name), ['first.mp3', 'second.ogg']);
      expect(tracks.map((track) => track.path), [
        '/music/first.mp3',
        '/music/second.ogg',
      ]);
    });

    test('caps queue at 25 unique tracks in picker order', () {
      final tracks = localAudioTracks(
        List.generate(
          maxLocalAudioQueueLength + 2,
          (index) => file('track-$index.mp3', '/music/$index.mp3'),
        ),
      );

      expect(tracks, hasLength(maxLocalAudioQueueLength));
      expect(tracks.first.name, 'track-0.mp3');
      expect(tracks.last.name, 'track-24.mp3');
    });

    test('uses the path basename when picker name is blank', () {
      final tracks = localAudioTracks([file('  ', '/music/track.mp3')]);
      expect(tracks.single.name, 'track.mp3');
    });

    test('non-positive queue limits produce an empty immutable list', () {
      expect(
        localAudioTracks([file('track.mp3', '/music/track.mp3')], maxTracks: 0),
        isEmpty,
      );
    });
  });
}
