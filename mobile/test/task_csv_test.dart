import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_assistant/phone_data.dart';
import 'package:personal_assistant/task_csv.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  group('TaskCsv', () {
    test(
      'round-trips quoted commas, quotes, newlines and inert scheduling fields',
      () {
        final tasks = [
          {
            'title': 'Plan, then "review"\nnext',
            'done': true,
            'imported_inactive_schedule_metadata': {
              'due_date': '2026-10-30',
              'reminder': '08:30',
              'repeat': 'weekly',
              'active': false,
            },
          },
        ];
        final csv = TaskCsv.exportRows(tasks);
        final parsed = TaskCsv.parse(csv).single;
        expect(parsed['title'], tasks.single['title']);
        expect(parsed['done'], isTrue);
        expect(parsed['imported_inactive_schedule_metadata'], {
          'due_date': '2026-10-30',
          'reminder': '08:30',
          'repeat': 'weekly',
          'active': false,
        });
      },
    );

    test('escapes spreadsheet formulas in task and schedule cells', () {
      final csv = TaskCsv.exportRows([
        {
          'title': ' =HYPERLINK("https://example.test")',
          'done': false,
          'imported_inactive_schedule_metadata': {
            'due_date': '+cmd',
            'reminder': '-1+2',
            'repeat': '@SUM(A1:A2)',
          },
        },
      ]);
      expect(csv, contains("' =HYPERLINK"));
      expect(csv, contains("'+cmd"));
      expect(csv, contains("'-1+2"));
      expect(csv, contains("'@SUM"));
    });

    test('requires a title and validates done values atomically', () {
      expect(() => TaskCsv.parse('done\ntrue\n'), throwsFormatException);
      expect(
        () => TaskCsv.parse('title,done\na task,perhaps\n'),
        throwsFormatException,
      );
    });

    test(
      'rejects duplicate headers, malformed quoting, and more than 500 rows',
      () {
        expect(
          () => TaskCsv.parse('title,title\na,b\n'),
          throwsFormatException,
        );
        expect(() => TaskCsv.parse('title\n"open\n'), throwsFormatException);
        final rows = List.generate(501, (index) => 'task $index').join('\n');
        expect(() => TaskCsv.parse('title\n$rows\n'), throwsFormatException);
      },
    );

    test('local task, water, habit and expense data persist without overwriting', () async {
      const secure = FlutterSecureStorage();
      final data = PhoneData(secure);
      await data.load();
      await data.writeChat('existing', [
        {'role': 'user', 'text': 'keep this chat'},
      ]);
      await data.task('Existing task');
      await data.addWaterLog(250);
      await data.addHabit('Walk');
      final habitId = data.rows('habits').single['id'] as String;
      final today = DateTime.now();
      final todayKey =
          '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      await data.toggleHabitCheckin(habitId, todayKey);
      await data.addExpense(
        amountMinor: 1250,
        currency: 'EUR',
        category: 'Food',
      );
      await data.importTasks(
        TaskCsv.parse(
          'title,done,due_date,reminder,repeat\r\nImported,false,2030-01-01,08:30,weekly\r\n',
        ),
      );

      expect(data.rows('tasks'), hasLength(2));
      expect(data.rows('tasks').last['imported_inactive_schedule_metadata'], {
        'due_date': '2030-01-01',
        'reminder': '08:30',
        'repeat': 'weekly',
        'active': false,
      });
      expect(data.rows('water_logs').single['milliliters'], 250);
      expect(data.rows('habits').single['completed_dates'], [todayKey]);
      expect(data.rows('expenses').single['currency'], 'EUR');
      expect(data.chat('existing').single['text'], 'keep this chat');

      final restored = PhoneData(secure);
      await restored.load();
      expect(restored.rows('tasks'), hasLength(2));
      expect(
        restored
            .rows('tasks')
            .last['imported_inactive_schedule_metadata']['active'],
        false,
      );
      expect(restored.rows('water_logs'), hasLength(1));
      expect(restored.rows('habits').single['completed_dates'], [todayKey]);
      expect(restored.rows('expenses').single['amount_minor'], 1250);
      expect(restored.chat('existing').single['text'], 'keep this chat');
      await expectLater(
        data.toggleHabitCheckin(habitId, '2026-02-30'),
        throwsArgumentError,
      );
      await expectLater(data.addWaterLog(4001), throwsArgumentError);
      await expectLater(
        data.addExpense(amountMinor: 100, currency: ' ', category: 'Food'),
        throwsArgumentError,
      );
    });

    test('sort is a view and leaves stored order unchanged', () {
      final source = [
        {'title': 'Zulu', 'done': true},
        {'title': 'beta', 'done': false},
        {'title': 'Alpha', 'done': false},
      ];
      expect(sortLocalTasks(source, 'title').map((e) => e['title']), [
        'Alpha',
        'beta',
        'Zulu',
      ]);
      expect(sortLocalTasks(source, 'open').map((e) => e['title']), [
        'beta',
        'Alpha',
        'Zulu',
      ]);
      expect(source.map((e) => e['title']), ['Zulu', 'beta', 'Alpha']);
    });
  });
}
