import 'package:flutter_test/flutter_test.dart';
import 'package:personal_assistant/offline_model.dart';

void main() {
  group('Gemma 4 local screening download preflight', () {
    test('a new download reserves the full artifact plus safety space', () {
      expect(
        gemma4DownloadHasSpace(
          availableBytes: gemma4ModelSizeBytes + gemma4StorageReserveBytes,
          partialBytes: 0,
        ),
        isTrue,
      );
      expect(
        gemma4DownloadHasSpace(
          availableBytes: gemma4ModelSizeBytes + gemma4StorageReserveBytes - 1,
          partialBytes: 0,
        ),
        isFalse,
      );
    });

    test('resuming reserves only the missing bytes plus safety space', () {
      final partial = gemma4ModelSizeBytes ~/ 2;
      final remaining = gemma4ModelSizeBytes - partial;
      expect(
        gemma4DownloadHasSpace(
          availableBytes: remaining + gemma4StorageReserveBytes,
          partialBytes: partial,
        ),
        isTrue,
      );
      expect(
        gemma4DownloadHasSpace(
          availableBytes: remaining + gemma4StorageReserveBytes - 1,
          partialBytes: partial,
        ),
        isFalse,
      );
    });

    test('corrupt persisted byte counts require a full fresh-download reserve', () {
      expect(
        gemma4DownloadHasSpace(
          availableBytes: gemma4StorageReserveBytes,
          partialBytes: gemma4ModelSizeBytes + 1,
        ),
        isFalse,
      );
      expect(
        gemma4DownloadHasSpace(
          availableBytes: gemma4ModelSizeBytes + gemma4StorageReserveBytes,
          partialBytes: gemma4ModelSizeBytes + 1,
        ),
        isTrue,
      );
    });
  });
}
