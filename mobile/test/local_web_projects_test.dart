import 'dart:convert';

import 'package:archive/archive.dart';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_assistant/local_web_projects.dart';
import 'package:personal_assistant/phone_data.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('creates and restores an offline starter project without changing other data', () async {
    const storage = FlutterSecureStorage();
    final data = PhoneData(storage);
    await data.load();
    await data.writeChat('existing', [
      {'role': 'user', 'text': 'preserve this'},
    ]);
    await data.task('Existing task');

    final repository = LocalWebProjects(data);
    final id = await repository.create('  Tiny site  ');
    expect(repository.all(), hasLength(1));
    expect(repository.all().single['name'], 'Tiny site');
    expect(repository.all().single['html'], contains('viewport'));
    expect(repository.all().single['js'], contains('not run'));
    final todoId = await repository.addTodo(id, '  Check layout  ');

    await repository.save(
      id: id,
      name: 'Tiny site v2',
      html: '<!doctype html><title>Demo</title>',
      css: 'body { color: teal; }',
      js: 'document.title = "Demo";',
    );

    final restored = PhoneData(storage);
    await restored.load();
    final saved = LocalWebProjects(restored).all().single;
    expect(saved['id'], id);
    expect(saved['name'], 'Tiny site v2');
    expect(saved['html'], '<!doctype html><title>Demo</title>');
    expect(LocalWebProjects(restored).todos(id).single, {
      'id': todoId,
      'content': 'Check layout',
      'status': 'pending',
    });
    expect(restored.chat('existing').single['text'], 'preserve this');
    expect(restored.rows('tasks').single['title'], 'Existing task');
  });

  test(
    'adds web projects when migrating an existing local data record',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'phone_data_v1':
            '{"chats":{},"memories":[],"tasks":[],"attempts":[],"actions":[]}',
      });
      final data = PhoneData(const FlutterSecureStorage());
      await data.load();
      expect(data.rows('web_projects'), isEmpty);
      await LocalWebProjects(data).create('Migrated install');
      expect(LocalWebProjects(data).all(), hasLength(1));
    },
  );

  test(
    'project task list supports bounded edits, ordering, and one active task',
    () async {
      final data = PhoneData(const FlutterSecureStorage());
      await data.load();
      final repository = LocalWebProjects(data);
      final project = await repository.create('Task project');
      final first = await repository.addTodo(project, 'Write a title');
      final second = await repository.addTodo(project, 'Check mobile layout');

      await repository.setTodoStatus(project, first, 'in_progress');
      await repository.setTodoStatus(project, second, 'in_progress');
      expect(repository.todos(project).map((item) => item['status']).toList(), [
        'pending',
        'in_progress',
      ]);

      await repository.reorderTodos(project, [second, first]);
      expect(repository.todos(project).map((item) => item['id']).toList(), [
        second,
        first,
      ]);
      await repository.setTodoStatus(project, second, 'completed');
      await repository.removeTodo(project, first);
      expect(repository.todos(project), [
        {'id': second, 'content': 'Check mobile layout', 'status': 'completed'},
      ]);

      await expectLater(repository.addTodo(project, '  '), throwsArgumentError);
      await expectLater(
        repository.addTodo(project, 'x' * (LocalWebProjects.maxTodoLength + 1)),
        throwsArgumentError,
      );
      await expectLater(
        repository.setTodoStatus(project, second, 'running'),
        throwsArgumentError,
      );
      await expectLater(
        repository.reorderTodos(project, [second, second]),
        throwsArgumentError,
      );
      await expectLater(
        repository.removeTodo(project, 'missing'),
        throwsStateError,
      );
      expect(repository.todos(project), hasLength(1));
    },
  );

  test(
    'rejects invalid names, oversized source, and missing project updates',
    () async {
      final data = PhoneData(const FlutterSecureStorage());
      await data.load();
      final repository = LocalWebProjects(data);
      await expectLater(repository.create('  '), throwsArgumentError);
      await expectLater(
        repository.create('x' * (LocalWebProjects.maxNameLength + 1)),
        throwsArgumentError,
      );
      final id = await repository.create('Bounded');
      await expectLater(
        repository.save(
          id: id,
          name: 'Bounded',
          html: 'x' * (LocalWebProjects.maxFileCharacters + 1),
          css: '',
          js: '',
        ),
        throwsArgumentError,
      );
      await expectLater(
        repository.save(
          id: 'missing',
          name: 'No project',
          html: '',
          css: '',
          js: '',
        ),
        throwsStateError,
      );
      expect(repository.all(), hasLength(1));
    },
  );

  test(
    'nested files stay project-relative, bounded, and survive editor save',
    () async {
      final data = PhoneData(const FlutterSecureStorage());
      await data.load();
      final repository = LocalWebProjects(data);
      final id = await repository.create('Nested project');
      await repository.saveProjectFile(
        projectId: id,
        path: 'src/components/card.css',
        contents: '.card { color: teal; }',
      );
      await expectLater(
        repository.saveProjectFile(
          projectId: id,
          path: '../secret.txt',
          contents: 'x',
        ),
        throwsArgumentError,
      );
      await expectLater(
        repository.saveProjectFile(
          projectId: id,
          path: '/absolute.css',
          contents: 'x',
        ),
        throwsArgumentError,
      );
      await repository.save(
        id: id,
        name: 'Nested project edited',
        html: '<!doctype html><title>Project</title>',
        css: '',
        js: '',
      );
      expect(
        repository.projectFiles(id)['src/components/card.css'],
        contains('teal'),
      );
      final restored = PhoneData(const FlutterSecureStorage());
      await restored.load();
      expect(
        LocalWebProjects(restored).projectFiles(id)['src/components/card.css'],
        contains('teal'),
      );
    },
  );

  test(
    'only explicit @file context is included and missing paths fail closed',
    () async {
      final data = PhoneData(const FlutterSecureStorage());
      await data.load();
      final repository = LocalWebProjects(data);
      final id = await repository.create('Context project');
      await repository.saveProjectFile(
        projectId: id,
        path: 'src/a.css',
        contents: 'A',
      );
      await repository.saveProjectFile(
        projectId: id,
        path: 'src/b.js',
        contents: 'B',
      );
      expect(repository.contextFilesForPrompt(id, 'Make a page @src/a.css'), {
        'src/a.css': 'A',
      });
      expect(repository.contextFilesForPrompt(id, 'No references'), isEmpty);
      await expectLater(
        () => repository.contextFilesForPrompt(id, 'Use @src/missing.js'),
        throwsFormatException,
      );
      await expectLater(
        () => repository.contextFilesForPrompt(id, 'Use @../outside'),
        throwsArgumentError,
      );
    },
  );

  test('ZIP export contains only starter and nested files beneath a project folder', () async {
    final data = PhoneData(const FlutterSecureStorage());
    await data.load();
    final repository = LocalWebProjects(data);
    final id = await repository.create('Nested Site');
    await repository.saveProjectFile(
      projectId: id,
      path: 'src/card.css',
      contents: '.card{}',
    );
    final archive = ZipDecoder().decodeBytes(repository.exportProjectZip(id));
    final paths = archive.files
        .where((file) => file.isFile)
        .map((file) => file.name)
        .toSet();
    expect(
      paths,
      containsAll({
        'Nested-Site/index.html',
        'Nested-Site/style.css',
        'Nested-Site/script.js',
        'Nested-Site/src/card.css',
      }),
    );
    expect(paths.any((path) => path.startsWith('/')), isFalse);
    final nested = archive.findFile('Nested-Site/src/card.css')!;
    expect(String.fromCharCodes(nested.content as List<int>), '.card{}');
  });

  test(
    'accepts compact generated JSON source and unwraps whole-file fences',
    () {
      final project = GeneratedWebProject.fromResponse(
        jsonEncode({
          'html': '```html\n<!doctype html><title>Study</title>\n```',
          'css': '```css\nbody { color: teal; }\n```',
          'js': '',
        }),
      );
      expect(project.html, '<!doctype html><title>Study</title>');
      expect(project.css, 'body { color: teal; }');
      expect(project.js, isEmpty);
    },
  );

  test(
    'rejects malformed, incomplete, empty, and oversized generated files',
    () {
      expect(
        () => GeneratedWebProject.fromResponse('not json'),
        throwsFormatException,
      );
      expect(
        () => GeneratedWebProject.fromResponse('{"html":"<main>Hi</main>"}'),
        throwsFormatException,
      );
      expect(
        () => GeneratedWebProject.fromResponse('{"html":" ","css":"","js":""}'),
        throwsFormatException,
      );
      expect(
        () => GeneratedWebProject.fromResponse(
          jsonEncode({
            'html': 'x' * (LocalWebProjects.maxFileCharacters + 1),
            'css': '',
            'js': '',
          }),
        ),
        throwsFormatException,
      );
    },
  );

  test('basic review reports simple mobile and local-file gaps without executing source', () {
    final findings = LocalWebProjects.review(
      html: '<html><head><link rel="stylesheet" href="style.css"></head><body></body></html>',
      css: '',
      js: 'alert(1)',
    );
    expect(
      findings,
      contains(
        'No viewport meta tag found; mobile pages may use a desktop-width layout.',
      ),
    );
    expect(
      findings,
      contains(
        'HTML links to a CSS file, but the project CSS editor is empty.',
      ),
    );
    expect(
      findings,
      contains(
        'JavaScript is present, but no local .js script reference was found in HTML.',
      ),
    );
  });

  test(
    'static review flags missing local refs and dynamic or network code',
    () {
      final findings = LocalWebProjects.review(
        html: '<script src="missing.js"></script><img src="https://example.org/a.png">',
        css: '',
        js: 'eval("unsafe"); fetch("https://example.org");',
        files: {'src/data.txt': 'local'},
      );
      expect(
        findings.any((finding) => finding.contains('not present')),
        isTrue,
      );
      expect(findings.any((finding) => finding.contains('Remote URL')), isTrue);
      expect(
        findings.any((finding) => finding.contains('Dynamic code execution')),
        isTrue,
      );
      expect(
        findings.any((finding) => finding.contains('Network-capable')),
        isTrue,
      );
    },
  );
}
