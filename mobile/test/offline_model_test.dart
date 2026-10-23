import 'package:flutter_test/flutter_test.dart';
import 'package:personal_assistant/offline_model.dart';

void main() {
  group('Gemma 4 local screening download preflight', () {
    test('uses the pinned E2B artifact byte count, not parameter count', () {
      expect(gemma4ModelSizeBytes, 2_588_147_712);
    });

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

    test('the lighter artifact has its own exact download-size preflight', () {
      expect(qwen3ModelSizeBytes, 613722264);
      expect(
        offlineModelDownloadHasSpace(
          availableBytes: qwen3ModelSizeBytes + gemma4StorageReserveBytes,
          partialBytes: 0,
          modelSizeBytes: qwen3ModelSizeBytes,
        ),
        isTrue,
      );
      expect(
        offlineModelDownloadHasSpace(
          availableBytes: qwen3ModelSizeBytes + gemma4StorageReserveBytes - 1,
          partialBytes: 0,
          modelSizeBytes: qwen3ModelSizeBytes,
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
