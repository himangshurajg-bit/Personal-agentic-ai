import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_assistant/phone_data.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('journal entries are local, editable and survive reload', () async {
    final storage = const FlutterSecureStorage();
    final data = PhoneData(storage);
    await data.load();

    final id = await data.saveJournalEntry(
      date: '2026-10-27',
      text: '  A note I chose to write.  ',
    );
    expect(
      data.rows('journal_entries').single,
      containsPair('text', 'A note I chose to write.'),
    );

    await data.saveJournalEntry(
      id: id,
      date: '2026-10-26',
      text: 'Updated note.',
    );
    expect(data.rows('journal_entries'), hasLength(1));
    expect(data.rows('journal_entries').single['date'], '2026-10-26');
    expect(data.rows('journal_entries').single['created_at'], isNotNull);
    expect(data.rows('journal_entries').single['updated_at'], isNotNull);

    final stored = jsonDecode((await storage.read(key: 'phone_data_v1'))!);
    expect(stored['journal_entries'].single['text'], 'Updated note.');
    final restored = PhoneData(storage);
    await restored.load();
    expect(restored.rows('journal_entries').single['id'], id);
    expect(restored.rows('journal_entries').single['text'], 'Updated note.');

    await restored.deleteJournalEntry(id);
    expect(restored.rows('journal_entries'), isEmpty);
  });

  test('older local stores migrate additively without changing existing data', () async {
    const legacy =
        '{"chats":{},"memories":[],"tasks":[{"id":"t1"}],"attempts":[],"actions":[]}';
    FlutterSecureStorage.setMockInitialValues({'phone_data_v1': legacy});
    final data = PhoneData(const FlutterSecureStorage());
    await data.load();
    expect(data.rows('tasks'), [containsPair('id', 't1')]);
    expect(data.rows('journal_entries'), isEmpty);
    await data.saveJournalEntry(date: '2026-10-27', text: 'New entry');
    expect(data.rows('tasks'), [containsPair('id', 't1')]);
    expect(data.rows('journal_entries'), hasLength(1));
  });

  test('invalid date, blank text, missing edit target and oversized text fail safely', () async {
    final data = PhoneData(const FlutterSecureStorage());
    await data.load();
    await expectLater(
      data.saveJournalEntry(date: '2026-02-30', text: 'Note'),
      throwsArgumentError,
    );
    await expectLater(
      data.saveJournalEntry(date: '2026-10-27', text: '  '),
      throwsArgumentError,
    );
    await expectLater(
      data.saveJournalEntry(date: '2026-10-27', text: 'x' * 10001),
      throwsArgumentError,
    );
    await expectLater(
      data.saveJournalEntry(id: 'missing', date: '2026-10-27', text: 'Note'),
      throwsStateError,
    );
    await expectLater(data.deleteJournalEntry('missing'), throwsStateError);
    expect(data.rows('journal_entries'), isEmpty);
  });
}
