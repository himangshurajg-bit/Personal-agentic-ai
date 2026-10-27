import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:personal_assistant/phone_data.dart';

/// Source returned by the optional, online website-draft generator.
/// It is validated before being offered to the editor and is never executed.
class GeneratedWebProject {
  final String html;
  final String css;
  final String js;

  const GeneratedWebProject({
    required this.html,
    required this.css,
    required this.js,
  });

  factory GeneratedWebProject.fromResponse(String response) {
    final decoded = jsonDecode(response);
    if (decoded is! Map ||
        decoded['html'] is! String ||
        decoded['css'] is! String ||
        decoded['js'] is! String) {
      throw const FormatException(
        'Gemini did not return all three website source files.',
      );
    }
    String unwrapFence(String source) {
      final trimmed = source.trim();
      final match = RegExp(
        r'^```(?:html|css|javascript|js)?\s*([\s\S]*?)\s*```$',
        caseSensitive: false,
      ).firstMatch(trimmed);
      return match?.group(1) ?? source;
    }

    final project = GeneratedWebProject(
      html: unwrapFence(decoded['html'] as String),
      css: unwrapFence(decoded['css'] as String),
      js: unwrapFence(decoded['js'] as String),
    );
    if (project.html.trim().isEmpty) {
      throw const FormatException('Gemini returned an empty HTML file.');
    }
    try {
      LocalWebProjects._validateFiles(
        html: project.html,
        css: project.css,
        js: project.js,
      );
    } on ArgumentError catch (error) {
      throw FormatException('Gemini returned invalid project source: $error');
    }
    return project;
  }
}

/// Bounded, device-local HTML/CSS/JS project drafts. Source is stored as text;
/// this feature never evaluates code or contacts a network service.
class LocalWebProjects {
  static const maxProjects = 50;
  static const maxNameLength = 60;
  static const maxFileCharacters = 30000;
  static const maxProjectCharacters = maxFileCharacters * 3;
  static const maxTodos = 100;
  static const maxTodoLength = 160;
  static const maxNestedFiles = 50;
  static const maxProjectPathLength = 180;
  static const maxNestedFileCharacters = 30000;
  static const maxNestedFilesCharacters = 90000;
  static const maxContextFiles = 5;
  static const maxContextCharacters = 20000;
  static const maxZipBytes = 256 * 1024;
  static const todoStatuses = <String>{
    'pending',
    'in_progress',
    'completed',
    'failed',
  };

  final PhoneData data;
  const LocalWebProjects(this.data);

  List<Map<String, dynamic>> all() => data.rows('web_projects')
    ..sort(
      (a, b) => (b['updated_at'] as String? ?? '').compareTo(
        a['updated_at'] as String? ?? '',
      ),
    );

  Future<String> create(String name) async {
    final cleanName = _name(name);
    final id = data.id();
    final row = <String, dynamic>{
      'id': id,
      'name': cleanName,
      'html': starterHtml,
      'css': starterCss,
      'js': starterJs,
      'files': <String, String>{},
      'todos': <dynamic>[],
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    await data.change((store) {
      final projects = store['web_projects'] as List;
      if (projects.length >= maxProjects) {
        throw StateError('You can keep up to $maxProjects local projects.');
      }
      projects.add(row);
    });
    return id;
  }

  Future<void> save({
    required String id,
    required String name,
    required String html,
    required String css,
    required String js,
  }) async {
    final cleanName = _name(name);
    _validateFiles(html: html, css: css, js: js);
    await data.change((store) {
      final projects = store['web_projects'] as List;
      final index = projects.indexWhere(
        (item) => item is Map && item['id'] == id,
      );
      if (index < 0) throw StateError('This local project no longer exists.');
      projects[index] = <String, dynamic>{
        'id': id,
        'name': cleanName,
        'html': html,
        'css': css,
        'js': js,
        'files': projects[index] is Map && projects[index]['files'] is Map
            ? Map<String, String>.from(
                (projects[index]['files'] as Map).map(
                  (key, value) => MapEntry(key.toString(), value.toString()),
                ),
              )
            : <String, String>{},
        'todos': projects[index] is Map && projects[index]['todos'] is List
            ? List<dynamic>.from(projects[index]['todos'] as List)
            : <dynamic>[],
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
    });
  }

  Map<String, String> projectFiles(String projectId) {
    final project = _project(data.snapshot['web_projects'] as List, projectId);
    final raw = project?['files'];
    if (raw is! Map) return <String, String>{};
    return Map<String, String>.unmodifiable({
      for (final entry in raw.entries)
        if (entry.key is String && entry.value is String)
          entry.key as String: entry.value as String,
    });
  }

  Future<void> saveProjectFile({
    required String projectId,
    required String path,
    required String contents,
  }) async {
    final normalized = normalizeProjectPath(path);
    _validateProjectFile(contents);
    await data.change((store) {
      final project = _project(store['web_projects'] as List, projectId);
      if (project == null) {
        throw StateError('This local project no longer exists.');
      }
      final files = _projectFileMap(project);
      if (const {
        'index.html',
        'style.css',
        'script.js',
      }.contains(normalized.toLowerCase())) {
        throw ArgumentError(
          'The root HTML, CSS, and JavaScript files use the main editor.',
        );
      }
      if (!files.containsKey(normalized) && files.length >= maxNestedFiles) {
        throw StateError(
          'A local project can hold up to $maxNestedFiles nested files.',
        );
      }
      final previous = files[normalized];
      files[normalized] = contents;
      final aggregate = files.values.fold<int>(
        0,
        (sum, item) => sum + item.length,
      );
      if (aggregate > maxNestedFilesCharacters) {
        if (previous == null) {
          files.remove(normalized);
        } else {
          files[normalized] = previous;
        }
        throw StateError(
          'Nested project files exceed the 90,000-character limit.',
        );
      }
      project['files'] = files;
      project['updated_at'] = DateTime.now().toUtc().toIso8601String();
    });
  }

  Future<void> removeProjectFile({
    required String projectId,
    required String path,
  }) async {
    final normalized = normalizeProjectPath(path);
    await data.change((store) {
      final project = _project(store['web_projects'] as List, projectId);
      if (project == null) {
        throw StateError('This local project no longer exists.');
      }
      final files = _projectFileMap(project);
      if (files.remove(normalized) == null) {
        throw StateError('This local project file no longer exists.');
      }
      project['files'] = files;
      project['updated_at'] = DateTime.now().toUtc().toIso8601String();
    });
  }

  /// Resolve only explicit @path references to files in this project.
  /// A missing/invalid reference fails closed instead of silently widening context.
  Map<String, String> contextFilesForPrompt(String projectId, String prompt) {
    final references = <String>[];
    for (final match in RegExp(
      r'(?<![A-Za-z0-9_.%+-])@([A-Za-z0-9_./-]{1,180})',
    ).allMatches(prompt)) {
      final reference = match.group(1)!;
      // Only treat file-like references as context; ordinary @mentions and
      // CSS at-rules such as @media remain part of the brief text.
      if (!reference.contains('/') &&
          !RegExp(r'\.[A-Za-z0-9]{1,10}$').hasMatch(reference)) {
        continue;
      }
      references.add(reference);
    }
    if (references.isEmpty) return <String, String>{};
    final unique = <String>[];
    final seen = <String>{};
    for (final reference in references) {
      final path = normalizeProjectPath(reference);
      if (seen.add(path)) unique.add(path);
    }
    if (unique.length > maxContextFiles) {
      throw FormatException(
        'Reference at most $maxContextFiles project files with @path.',
      );
    }
    final files = projectFiles(projectId);
    final selected = <String, String>{};
    var total = 0;
    for (final path in unique) {
      final contents = files[path];
      if (contents == null) {
        throw FormatException(
          'Referenced project file "$path" does not exist.',
        );
      }
      total += contents.length;
      if (total > maxContextCharacters) {
        throw const FormatException(
          'Referenced file context exceeds 20,000 characters.',
        );
      }
      selected[path] = contents;
    }
    return Map<String, String>.unmodifiable(selected);
  }

  Uint8List exportProjectZip(String projectId) {
    final project = _project(data.snapshot['web_projects'] as List, projectId);
    if (project == null) {
      throw StateError('This local project no longer exists.');
    }
    final name = _zipSlug(project['name'] as String? ?? 'project');
    final archive = Archive();
    void add(String path, String contents) {
      final safePath = normalizeProjectPath(path);
      final bytes = utf8.encode(contents);
      archive.addFile(ArchiveFile('$name/$safePath', bytes.length, bytes));
    }

    add('index.html', project['html'] as String? ?? '');
    add('style.css', project['css'] as String? ?? '');
    add('script.js', project['js'] as String? ?? '');
    for (final entry in projectFiles(projectId).entries) {
      add(entry.key, entry.value);
    }
    final bytes = ZipEncoder().encode(archive);
    if (bytes == null || bytes.isEmpty || bytes.length > maxZipBytes) {
      throw StateError(
        'The project archive could not be encoded within the size limit.',
      );
    }
    return Uint8List.fromList(bytes);
  }

  String projectNotesScaffold(String projectId, Map<String, dynamic> project) {
    final paths = <String>{'index.html', 'style.css', 'script.js'}
      ..addAll(projectFiles(projectId).keys);
    final visible = paths.toList()..sort();
    final extensions =
        visible
            .map(
              (path) => path.contains('.')
                  ? path.split('.').last.toLowerCase()
                  : 'no extension',
            )
            .toSet()
            .toList()
          ..sort();
    return [
      '# Project notes: ${_name(project['name'] as String? ?? 'Website project')}',
      '',
      'This starter records visible project paths and file types only.',
      'It does not read file contents, run code, or publish anything.',
      '',
      '## Visible files',
      ...visible.map((path) => '- `$path`'),
      '',
      '## File types',
      ...extensions.map((extension) => '- `$extension`'),
      '',
      'Review source before sharing, running, or deploying it.',
      '',
    ].join('\n');
  }

  Future<void> createProjectNotes(String projectId) async {
    final files = projectFiles(projectId);
    if (files.containsKey('MYRA_CODER.md')) {
      throw StateError('MYRA_CODER.md already exists; it was not overwritten.');
    }
    final project = _project(data.snapshot['web_projects'] as List, projectId);
    if (project == null) {
      throw StateError('This local project no longer exists.');
    }
    await saveProjectFile(
      projectId: projectId,
      path: 'MYRA_CODER.md',
      contents: projectNotesScaffold(projectId, project),
    );
  }

  static String projectZipFilename(String name) => '${_zipSlug(name)}.zip';

  static String _zipSlug(String name) {
    final slug = _name(name)
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    return slug.isEmpty ? 'website-project' : slug;
  }

  static String normalizeProjectPath(String path) {
    final value = path.trim();
    final segments = value.split('/');
    if (value.isEmpty ||
        value.length > 180 ||
        value.startsWith('/') ||
        value.contains('\\') ||
        value.contains(':') ||
        segments.length > 6 ||
        segments.any(
          (segment) =>
              segment.isEmpty ||
              segment == '.' ||
              segment == '..' ||
              !RegExp(r'^[A-Za-z0-9_][A-Za-z0-9._-]{0,63}$').hasMatch(segment),
        )) {
      throw ArgumentError(
        'Use a safe project-relative path (for example src/page.css).',
      );
    }
    return segments.join('/');
  }

  static void _validateProjectFile(String contents) {
    if (contents.length > maxNestedFileCharacters ||
        contents.contains('\u0000')) {
      throw ArgumentError(
        'A nested file is limited to 30,000 characters and cannot contain NUL.',
      );
    }
  }

  static Map<String, String> _projectFileMap(Map<String, dynamic> project) {
    final raw = project['files'];
    if (raw is! Map) return <String, String>{};
    return <String, String>{
      for (final entry in raw.entries)
        if (entry.key is String && entry.value is String)
          entry.key as String: entry.value as String,
    };
  }

  List<Map<String, dynamic>> todos(String projectId) {
    final project = _project(data.snapshot['web_projects'] as List, projectId);
    final raw = project?['todos'];
    if (raw is! List) return <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<String> addTodo(String projectId, String content) async {
    final clean = _todoContent(content);
    final id = data.id();
    await data.change((store) {
      final project = _project(store['web_projects'] as List, projectId);
      if (project == null) {
        throw StateError('This local project no longer exists.');
      }
      final items = _todoList(project);
      if (items.length >= maxTodos) {
        throw StateError('You can keep up to $maxTodos project tasks.');
      }
      items.add(<String, dynamic>{
        'id': id,
        'content': clean,
        'status': 'pending',
      });
      project['todos'] = items;
      project['updated_at'] = DateTime.now().toUtc().toIso8601String();
    });
    return id;
  }

  Future<void> setTodoStatus(
    String projectId,
    String todoId,
    String status,
  ) async {
    if (!todoStatuses.contains(status)) {
      throw ArgumentError('Choose a supported project-task status.');
    }
    await data.change((store) {
      final project = _project(store['web_projects'] as List, projectId);
      if (project == null) {
        throw StateError('This local project no longer exists.');
      }
      final items = _todoList(project);
      final index = items.indexWhere((item) => item['id'] == todoId);
      if (index < 0) throw StateError('This project task no longer exists.');
      if (status == 'in_progress') {
        for (final item in items) {
          if (item['status'] == 'in_progress') item['status'] = 'pending';
        }
      }
      items[index]['status'] = status;
      project['todos'] = items;
      project['updated_at'] = DateTime.now().toUtc().toIso8601String();
    });
  }

  Future<void> removeTodo(String projectId, String todoId) async {
    await data.change((store) {
      final project = _project(store['web_projects'] as List, projectId);
      if (project == null) {
        throw StateError('This local project no longer exists.');
      }
      final items = _todoList(project);
      final index = items.indexWhere((item) => item['id'] == todoId);
      if (index < 0) throw StateError('This project task no longer exists.');
      items.removeAt(index);
      project['todos'] = items;
      project['updated_at'] = DateTime.now().toUtc().toIso8601String();
    });
  }

  Future<void> reorderTodos(String projectId, List<String> orderedIds) async {
    await data.change((store) {
      final project = _project(store['web_projects'] as List, projectId);
      if (project == null) {
        throw StateError('This local project no longer exists.');
      }
      final items = _todoList(project);
      final ids = items.map((item) => item['id'] as String).toList();
      if (orderedIds.length != ids.length ||
          orderedIds.toSet().length != ids.length ||
          !orderedIds.toSet().containsAll(ids)) {
        throw ArgumentError(
          'The reordered task list must contain every task once.',
        );
      }
      final byId = {for (final item in items) item['id'] as String: item};
      project['todos'] = orderedIds.map((id) => byId[id]!).toList();
      project['updated_at'] = DateTime.now().toUtc().toIso8601String();
    });
  }

  static Map<String, dynamic>? _project(List projects, String id) {
    for (final item in projects) {
      if (item is Map && item['id'] == id) return item.cast<String, dynamic>();
    }
    return null;
  }

  static List<Map<String, dynamic>> _todoList(Map<String, dynamic> project) {
    final raw = project['todos'];
    if (raw is! List) return <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  static String _todoContent(String content) {
    final value = content.trim();
    if (value.isEmpty ||
        value.length > maxTodoLength ||
        value.contains(RegExp(r'[\x00-\x1f]'))) {
      throw ArgumentError(
        'Task text must be 1–$maxTodoLength printable characters.',
      );
    }
    return value;
  }

  static String _name(String name) {
    final value = name.trim();
    if (value.isEmpty ||
        value.length > maxNameLength ||
        value.contains(RegExp(r'[\x00-\x1f]'))) {
      throw ArgumentError(
        'Project name must be 1–$maxNameLength printable characters.',
      );
    }
    return value;
  }

  static void _validateFiles({
    required String html,
    required String css,
    required String js,
  }) {
    if (html.length > maxFileCharacters ||
        css.length > maxFileCharacters ||
        js.length > maxFileCharacters ||
        html.length + css.length + js.length > maxProjectCharacters) {
      throw ArgumentError('Each project file is limited to 30,000 characters.');
    }
    if ([html, css, js].any((value) => value.contains('\u0000'))) {
      throw ArgumentError('Project files cannot contain NUL characters.');
    }
  }

  static bool _isSafeProjectReference(String value) {
    try {
      normalizeProjectPath(value);
      return true;
    } on ArgumentError {
      return false;
    }
  }

  static List<String> review({
    required String html,
    required String css,
    required String js,
    Map<String, String> files = const <String, String>{},
  }) {
    _validateFiles(html: html, css: css, js: js);
    if (files.length > maxNestedFiles ||
        files.entries.any((entry) {
          try {
            normalizeProjectPath(entry.key);
            _validateProjectFile(entry.value);
            return false;
          } on ArgumentError {
            return true;
          }
        }) ||
        files.values.fold<int>(0, (sum, text) => sum + text.length) >
            maxNestedFilesCharacters) {
      throw ArgumentError('Nested project files exceed safe review limits.');
    }
    final findings = <String>[];
    if (!RegExp(
      r'<title\b[^>]*>[^<]+</title>',
      caseSensitive: false,
    ).hasMatch(html)) {
      findings.add(
        'Add a non-empty <title> element for a clearer browser tab name.',
      );
    }
    if (!RegExp(
      r"""<meta\s+[^>]*name\s*=\s*["']viewport["']""",
      caseSensitive: false,
    ).hasMatch(html)) {
      findings.add(
        'No viewport meta tag found; mobile pages may use a desktop-width layout.',
      );
    }
    final styleRefs =
        RegExp(
              r"""<link\b[^>]*href\s*=\s*["']([^"']+)["'][^>]*>""",
              caseSensitive: false,
            )
            .allMatches(html)
            .map((match) => match.group(1)!)
            .where((ref) => ref.toLowerCase().endsWith('.css'))
            .toList();
    if (styleRefs.isNotEmpty && css.trim().isEmpty) {
      findings.add(
        'HTML links to a CSS file, but the project CSS editor is empty.',
      );
    }
    final scriptRefs =
        RegExp(
              r"""<script\b[^>]*src\s*=\s*["']([^"']+)["'][^>]*>""",
              caseSensitive: false,
            )
            .allMatches(html)
            .map((match) => match.group(1)!)
            .where((ref) => ref.toLowerCase().endsWith('.js'))
            .toList();
    if (scriptRefs.isNotEmpty && js.trim().isEmpty) {
      findings.add(
        'HTML links to a JavaScript file, but the project JS editor is empty.',
      );
    }
    if (styleRefs.isEmpty && css.trim().isNotEmpty) {
      findings.add('CSS is present, but no local .css link was found in HTML.');
    }
    if (scriptRefs.isEmpty && js.trim().isNotEmpty) {
      findings.add(
        'JavaScript is present, but no local .js script reference was found in HTML.',
      );
    }
    final allSource = '$html\n$css\n$js\n${files.values.join('\n')}';
    if (RegExp(r'\b(?:https?:)?//', caseSensitive: false).hasMatch(allSource)) {
      findings.add(
        'Remote URL references are present; this editor does not fetch or verify remote content.',
      );
    }
    if (RegExp(
      r'\b(eval|Function)\s*\(',
      caseSensitive: false,
    ).hasMatch(allSource)) {
      findings.add(
        'Dynamic code execution patterns such as eval/Function are present; inspect before using the source.',
      );
    }
    if (RegExp(
      r'\b(fetch|XMLHttpRequest|WebSocket|sendBeacon)\b',
      caseSensitive: false,
    ).hasMatch(allSource)) {
      findings.add(
        'Network-capable JavaScript patterns are present; this text review does not run or verify them.',
      );
    }
    if (RegExp(
      r'\b(document\.write|innerHTML\s*=)',
      caseSensitive: false,
    ).hasMatch(allSource)) {
      findings.add(
        'Dynamic HTML insertion is present; inspect the source and any inserted content carefully.',
      );
    }
    final missingLocal = <String>[];
    final localRefs =
        <String>{
          ...RegExp(r"""(?:src|href)\s*=\s*[\"']([^\"']+)[\"']""")
              .allMatches(html)
              .map((match) => match.group(1)!),
        }..removeWhere(
          (ref) =>
              ref.isEmpty ||
              ref.startsWith('#') ||
              ref.startsWith('data:') ||
              Uri.tryParse(ref)?.hasScheme == true ||
              ref.startsWith('//'),
        );
    final knownFiles = <String>{
      'index.html',
      'style.css',
      'script.js',
      ...files.keys,
    };
    for (final reference in localRefs) {
      final normalized = reference.split('?').first.split('#').first;
      if (normalized.isEmpty) continue;
      final safe = _isSafeProjectReference(normalized);
      final directoryIndex =
          safe &&
          !normalized.contains('/') &&
          files.containsKey('$normalized/index.html');
      if (!safe || (!knownFiles.contains(normalized) && !directoryIndex)) {
        missingLocal.add(normalized);
      }
    }
    if (missingLocal.isNotEmpty) {
      findings.add(
        'HTML references local files not present in the project: ${missingLocal.take(5).join(', ')}.',
      );
    }
    if (findings.isEmpty) {
      findings.add(
        'No issues found by these basic text checks. This is not a full validator.',
      );
    }
    return findings;
  }

  static const starterHtml = '''<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>My project</title>
  <link rel="stylesheet" href="style.css">
</head>
<body>
  <main>
    <h1>Hello, world</h1>
    <p>Start editing your local project.</p>
  </main>
  <script src="script.js"></script>
</body>
</html>
''';
  static const starterCss = '''body { font: 1rem system-ui; margin: 2rem; }
main { max-width: 42rem; margin: auto; }
''';
  static const starterJs =
      '''// This file is stored as text and is not run by the app.
''';
}
