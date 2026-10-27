import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_assistant/assistant_state.dart';
import 'package:personal_assistant/local_backup_restore.dart';

Map<String, dynamic> backup({String note = 'backup note'}) => {
  'chats': {
    'older chat': [
      {'role': 'user', 'text': 'hello'},
      {'role': 'assistant', 'text': 'hi'},
    ],
  },
  'memories': [
    {'id': 'm1', 'text': 'remembered'},
  ],
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
  'private_note': note,
  'assistant_display_name': 'Backup Assistant',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('parses known export schema and previews category counts', () {
    final preview = LocalBackupPreview.parse(jsonEncode(backup()));
    expect(preview.counts['chats'], 1);
    expect(preview.chatMessageCount, 2);
    expect(preview.counts['memories'], 1);
    expect(preview.privateNote, 'backup note');
    expect(preview.assistantDisplayName, 'Backup Assistant');
    expect(preview.summary, contains('Journal entries: 0'));
  });

  test('rejects malformed JSON, unknown schema and invalid nested records', () {
    expect(() => LocalBackupPreview.parse('{'), throwsFormatException);
    expect(() => LocalBackupPreview.parse('[]'), throwsFormatException);
    expect(
      () => LocalBackupPreview.parse(jsonEncode({...backup(), 'secret': 'x'})),
      throwsFormatException,
    );
    expect(
      () => LocalBackupPreview.parse(
        jsonEncode({
          ...backup(),
          'memories': ['not a record'],
        }),
      ),
      throwsFormatException,
    );
  });

  testWidgets('picker cancellation makes no restore call', (tester) async {
    var restoreCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocalBackupRestoreControl(
            selectBackup: () async => null,
            restore: (_) async => restoreCalls++,
            onResult: (_) {},
          ),
        ),
      ),
    );
    await tester.tap(find.text('Restore local data'));
    await tester.pumpAndSettle();
    expect(restoreCalls, 0);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('valid restore preview is cancelable before any write', (
    tester,
  ) async {
    var restoreCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocalBackupRestoreControl(
            selectBackup: () async => jsonEncode(backup()),
            restore: (_) async => restoreCalls++,
            onResult: (_) {},
          ),
        ),
      ),
    );
    await tester.tap(find.text('Restore local data'));
    await tester.pumpAndSettle();
    expect(find.text('Replace on-phone records?'), findsOneWidget);
    expect(find.textContaining('Conversations: 1'), findsOneWidget);
    expect(find.text('Messages in conversations: 2'), findsOneWidget);
    expect(find.textContaining('Provider credentials'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(restoreCalls, 0);
  });

  testWidgets('malformed file reports error and does not restore', (
    tester,
  ) async {
    var restoreCalls = 0;
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocalBackupRestoreControl(
            selectBackup: () async => '{broken',
            restore: (_) async => restoreCalls++,
            onResult: (message) => result = message,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Restore local data'));
    await tester.pumpAndSettle();
    expect(restoreCalls, 0);
    expect(result, contains('valid backup JSON'));
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('confirmed preview restores and preserves separate preferences', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({
      'phone_data_v1': jsonEncode({
        'chats': <String, dynamic>{},
        'memories': <dynamic>[],
        'tasks': <dynamic>[],
        'attempts': <dynamic>[],
        'actions': <dynamic>[],
      }),
      'note': 'old note',
      'assistant_name': 'Old Assistant',
      'theme': 'dark',
      'provider_secret': 'keep this local setting',
      'app_lock_enabled': 'true',
    });
    final state = AssistantState();
    // Initialize only the local record store under test; full app startup also
    // probes platform integrations unrelated to a backup restore.
    await state.local.load();
    state.note = 'old note';
    state.assistantName = 'Old Assistant';
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocalBackupRestoreControl(
            selectBackup: () async => jsonEncode(backup()),
            restore: (preview) async {
              await state.restoreLocalBackup(preview);
            },
            onResult: (message) => result = message,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Restore local data'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Replace local records'));
    await tester.pumpAndSettle();

    expect(state.local.snapshot['chats']['older chat'], hasLength(2));
    expect(state.local.rows('memories'), hasLength(1));
    expect(state.note, 'backup note');
    expect(state.assistantName, 'Backup Assistant');
    expect(await state.storage.read(key: 'theme'), 'dark');
    expect(
      await state.storage.read(key: 'provider_secret'),
      'keep this local setting',
    );
    expect(await state.storage.read(key: 'app_lock_enabled'), 'true');
    expect(result, contains('restored'));
  });

  test(
    'older backup without optional fields leaves those preferences unset',
    () {
      final old = backup()
        ..remove('private_note')
        ..remove('assistant_display_name');
      final preview = LocalBackupPreview.parse(jsonEncode(old));
      expect(preview.privateNote, isNull);
      expect(preview.assistantDisplayName, isNull);
    },
  );
}
