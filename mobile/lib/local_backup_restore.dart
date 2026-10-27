import 'dart:convert';

import 'package:flutter/material.dart';

/// A fully parsed and validated export. Constructing a preview never writes data.
class LocalBackupPreview {
  static const int maxBackupCharacters = 2000000;
  static const Set<String> _dataKeys = {
    'chats',
    'memories',
    'tasks',
    'attempts',
    'actions',
    'study_decks',
    'flashcards',
    'study_reviews',
    'study_lessons',
    'study_practice_attempts',
    'water_logs',
    'habits',
    'expenses',
    'web_projects',
    'focus_timer',
    'journal_entries',
  };
  static const Set<String> _requiredKeys = {
    'chats',
    'memories',
    'tasks',
    'attempts',
    'actions',
  };
  static const Map<String, String> _labels = {
    'chats': 'Conversations',
    'memories': 'Approved memories',
    'tasks': 'Tasks',
    'attempts': 'Study attempts',
    'actions': 'Action receipts',
    'study_decks': 'Study decks',
    'flashcards': 'Flashcards',
    'study_reviews': 'Study reviews',
    'study_lessons': 'Study lessons',
    'study_practice_attempts': 'Practice attempts',
    'water_logs': 'Water logs',
    'habits': 'Habits',
    'expenses': 'Expenses',
    'web_projects': 'Web projects',
    'focus_timer': 'Focus timer',
    'journal_entries': 'Journal entries',
  };

  final Map<String, dynamic> data;
  final String? privateNote;
  final String? assistantDisplayName;
  final Map<String, int> counts;
  final int chatMessageCount;

  const LocalBackupPreview._({
    required this.data,
    required this.privateNote,
    required this.assistantDisplayName,
    required this.counts,
    required this.chatMessageCount,
  });

  factory LocalBackupPreview.parse(String source) {
    if (source.isEmpty || source.length > maxBackupCharacters) {
      throw const FormatException('Backup is empty or larger than 2 MB.');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException {
      throw const FormatException('This file is not valid backup JSON.');
    }
    if (decoded is! Map) {
      throw const FormatException('Backup root must be a JSON object.');
    }
    final root = Map<String, dynamic>.from(decoded);
    final allowed = {..._dataKeys, 'private_note', 'assistant_display_name'};
    final unknown = root.keys.toSet().difference(allowed);
    if (unknown.isNotEmpty || !_requiredKeys.every(root.containsKey)) {
      throw const FormatException(
        'This file is not a supported Personal AI backup.',
      );
    }

    final note = root['private_note'];
    final displayName = root['assistant_display_name'];
    if ((root.containsKey('private_note') &&
            (note is! String || note.length > 20000)) ||
        (root.containsKey('assistant_display_name') &&
            (displayName is! String ||
                displayName.trim().isEmpty ||
                displayName.runes.length > 40 ||
                displayName.contains(RegExp(r'[\x00-\x1f]'))))) {
      throw const FormatException('Backup profile or note data is invalid.');
    }

    final data = <String, dynamic>{
      'chats': <String, dynamic>{},
      'memories': <dynamic>[],
      'tasks': <dynamic>[],
      'attempts': <dynamic>[],
      'actions': <dynamic>[],
      'study_decks': <dynamic>[],
      'flashcards': <dynamic>[],
      'study_reviews': <dynamic>[],
      'study_lessons': <dynamic>[],
      'study_practice_attempts': <dynamic>[],
      'water_logs': <dynamic>[],
      'habits': <dynamic>[],
      'expenses': <dynamic>[],
      'web_projects': <dynamic>[],
      'focus_timer': null,
      'journal_entries': <dynamic>[],
    };
    var totalRecords = 0;
    for (final key in _dataKeys) {
      if (!root.containsKey(key)) continue; // Older supported exports.
      final value = root[key];
      if (key == 'chats') {
        if (value is! Map || value.length > 10000) {
          throw const FormatException('Backup conversations are invalid.');
        }
        final chats = <String, dynamic>{};
        for (final entry in value.entries) {
          if (entry.key is! String ||
              (entry.key as String).isEmpty ||
              (entry.key as String).length > 120 ||
              entry.value is! List ||
              (entry.value as List).length > 50000 ||
              !(entry.value as List).every((item) => item is Map)) {
            throw const FormatException('Backup conversation data is invalid.');
          }
          totalRecords += (entry.value as List).length;
          chats[entry.key as String] = entry.value;
        }
        data[key] = chats;
      } else if (key == 'focus_timer') {
        if (value != null && value is! Map) {
          throw const FormatException('Backup focus timer data is invalid.');
        }
        data[key] = value;
      } else {
        if (value is! List ||
            value.length > 50000 ||
            !value.every((item) => item is Map)) {
          throw FormatException('Backup ${_labels[key]} data is invalid.');
        }
        totalRecords += value.length;
        data[key] = value;
      }
      if (totalRecords > 100000) {
        throw const FormatException('Backup contains too many records.');
      }
    }

    final counts = <String, int>{};
    for (final entry in _labels.entries) {
      counts[entry.key] = entry.key == 'chats'
          ? (data['chats'] as Map).length
          : entry.key == 'focus_timer'
          ? (data['focus_timer'] == null ? 0 : 1)
          : (data[entry.key] as List).length;
    }
    final chatMessageCount = (data['chats'] as Map).values.fold<int>(
      0,
      (sum, messages) => sum + (messages as List).length,
    );
    return LocalBackupPreview._(
      data: data,
      privateNote: note as String?,
      assistantDisplayName: displayName as String?,
      counts: Map.unmodifiable(counts),
      chatMessageCount: chatMessageCount,
    );
  }

  String get summary => _labels.entries
      .map((entry) => '${entry.value}: ${counts[entry.key]}')
      .join('\n');
}

/// Selects a local backup, previews its validated contents, then asks before
/// replacing any supported on-device records.
class LocalBackupRestoreControl extends StatefulWidget {
  final Future<String?> Function() selectBackup;
  final Future<void> Function(LocalBackupPreview preview) restore;
  final void Function(String message) onResult;

  const LocalBackupRestoreControl({
    super.key,
    required this.selectBackup,
    required this.restore,
    required this.onResult,
  });

  @override
  State<LocalBackupRestoreControl> createState() =>
      _LocalBackupRestoreControlState();
}

class _LocalBackupRestoreControlState extends State<LocalBackupRestoreControl> {
  bool _busy = false;

  Future<void> _restore() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final source = await widget.selectBackup();
      if (source == null || !mounted) return;
      final preview = LocalBackupPreview.parse(source);
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Replace on-phone records?'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'The selected backup is valid. These supported categories will replace the current local records:',
                ),
                const SizedBox(height: 10),
                Text(preview.summary),
                Text('Messages in conversations: ${preview.chatMessageCount}'),
                if (preview.privateNote != null ||
                    preview.assistantDisplayName != null) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'The backup also contains your private note and assistant name.',
                  ),
                ],
                const SizedBox(height: 10),
                const Text(
                  'Provider credentials, OAuth tokens, security settings and other app preferences will not change. The JSON backup itself is readable and unencrypted.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Replace local records'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      await widget.restore(preview);
      if (mounted) {
        widget.onResult('Local records restored from the selected backup.');
      }
    } on FormatException catch (error) {
      if (mounted) widget.onResult(error.message);
    } catch (error) {
      if (mounted) widget.onResult(error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: _busy ? null : _restore,
    icon: const Icon(Icons.restore_rounded),
    label: Text(_busy ? 'Checking backup…' : 'Restore local data'),
  );
}
