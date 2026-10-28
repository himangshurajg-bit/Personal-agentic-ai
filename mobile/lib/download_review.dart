import 'package:flutter/material.dart';

import 'download_input.dart';

/// Shows the final, user-facing review before a download is enqueued.
Future<bool> reviewDownload(BuildContext context, DownloadInput download) async {
  final approved = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Review download'),
      content: SelectableText(
        'Download ${download.fileName} from:\n${download.url}\n\nThis uses network data and may incur charges. The file will be stored in Personal AI’s app-specific Downloads folder.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Start download'),
        ),
      ],
    ),
  );
  return approved == true;
}
