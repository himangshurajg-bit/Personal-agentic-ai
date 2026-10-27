import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'feature_services.dart';

import 'assistant_state.dart';
import 'local_web_projects.dart';

/// A small offline source workspace. It stores plain text locally and does not
/// run the JavaScript or preview the resulting page.
class LocalWebProjectsScreen extends StatefulWidget {
  final AssistantState state;
  const LocalWebProjectsScreen({super.key, required this.state});

  @override
  State<LocalWebProjectsScreen> createState() => _LocalWebProjectsScreenState();
}

class _LocalWebProjectsScreenState extends State<LocalWebProjectsScreen> {
  late final LocalWebProjects _repository = LocalWebProjects(
    widget.state.local,
  );
  final _name = TextEditingController();
  final _html = TextEditingController();
  final _css = TextEditingController();
  final _js = TextEditingController();
  final _todo = TextEditingController();
  final _generationPrompt = TextEditingController();
  final _nestedContents = TextEditingController();
  List<Map<String, dynamic>> _todos = [];
  List<Map<String, dynamic>> _projects = [];
  Map<String, String> _projectFiles = <String, String>{};
  String? _selectedNestedPath;
  String? _selectedId;
  bool _nestedDirty = false;
  String _file = 'HTML';
  String _message = '';
  bool _saving = false;
  bool _generating = false;
  bool _dirty = false;

  TextEditingController get _activeController => switch (_file) {
    'CSS' => _css,
    'JavaScript' => _js,
    _ => _html,
  };

  @override
  void initState() {
    super.initState();
    _refresh();
    for (final controller in [_name, _html, _css, _js]) {
      controller.addListener(_markDirty);
    }
  }

  @override
  void dispose() {
    for (final controller in [_name, _html, _css, _js]) {
      controller.removeListener(_markDirty);
      controller.dispose();
    }
    _todo.dispose();
    _generationPrompt.dispose();
    _nestedContents.dispose();
    super.dispose();
  }

  void _markDirty() {
    if (!_dirty && mounted) setState(() => _dirty = true);
  }

  void _refresh() {
    _projects = _repository.all();
    if (mounted) setState(() {});
  }

  Future<void> _create() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New local project'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: LocalWebProjects.maxNameLength,
          decoration: const InputDecoration(labelText: 'Project name'),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Create locally'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || !mounted) return;
    try {
      final id = await _repository.create(name);
      if (!mounted) return;
      _refresh();
      _loadProject(_projects.firstWhere((item) => item['id'] == id));
      setState(() => _message = 'Project created on this device.');
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    }
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Discard unsaved edits?'),
            content: const Text(
              'Changes in the editor have not been saved locally.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Stay here'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Discard edits'),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _loadProject(Map<String, dynamic> project) {
    _selectedId = project['id'] as String;
    _todos = _repository.todos(_selectedId!);
    _projectFiles = _repository.projectFiles(_selectedId!);
    _selectedNestedPath = null;
    _nestedContents.clear();
    _nestedDirty = false;
    _name.text = project['name'] as String? ?? '';
    _html.text = project['html'] as String? ?? '';
    _css.text = project['css'] as String? ?? '';
    _js.text = project['js'] as String? ?? '';
    _dirty = false;
    _message = '';
    setState(() {});
  }

  Future<void> _select(Map<String, dynamic> project) async {
    if (project['id'] == _selectedId) return;
    if (!await _confirmDiscard() || !mounted) return;
    _loadProject(project);
  }

  Future<void> _save() async {
    final id = _selectedId;
    if (id == null) return;
    setState(() {
      _saving = true;
      _message = '';
    });
    try {
      await _repository.save(
        id: id,
        name: _name.text,
        html: _html.text,
        css: _css.text,
        js: _js.text,
      );
      if (!mounted) return;
      _refresh();
      _todos = _repository.todos(id);
      _dirty = false;
      _message = 'Saved on this device only.';
      setState(() {});
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _createProjectFile() async {
    final pathController = TextEditingController();
    final path = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add nested project file'),
        content: TextField(
          controller: pathController,
          autofocus: true,
          maxLength: LocalWebProjects.maxProjectPathLength,
          decoration: const InputDecoration(
            labelText: 'Project-relative path',
            hintText: 'src/styles/card.css',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, pathController.text),
            child: const Text('Add file'),
          ),
        ],
      ),
    );
    pathController.dispose();
    final projectId = _selectedId;
    if (path == null || projectId == null || !mounted) return;
    try {
      final normalized = LocalWebProjects.normalizeProjectPath(path);
      if (_projectFiles.containsKey(normalized)) {
        setState(() => _message = 'That project file already exists.');
        return;
      }
      await _repository.saveProjectFile(
        projectId: projectId,
        path: normalized,
        contents: '',
      );
      if (!mounted) return;
      _projectFiles = _repository.projectFiles(projectId);
      _selectedNestedPath = normalized;
      _nestedContents.clear();
      _nestedDirty = false;
      setState(
        () => _message = 'Added $normalized. Save its contents when ready.',
      );
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    }
  }

  void _selectProjectFile(String path) {
    final contents = _projectFiles[path];
    if (contents == null) return;
    _selectedNestedPath = path;
    _nestedContents.text = contents;
    _nestedDirty = false;
    setState(() => _message = 'Selected $path.');
  }

  Future<void> _saveProjectFile() async {
    final projectId = _selectedId;
    final path = _selectedNestedPath;
    if (projectId == null || path == null) return;
    try {
      await _repository.saveProjectFile(
        projectId: projectId,
        path: path,
        contents: _nestedContents.text,
      );
      if (!mounted) return;
      _projectFiles = _repository.projectFiles(projectId);
      _nestedDirty = false;
      setState(() => _message = 'Saved $path on this device.');
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    }
  }

  Future<void> _deleteProjectFile(String path) async {
    final projectId = _selectedId;
    if (projectId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete project file?'),
        content: Text(
          'Remove $path from local storage and future ZIP exports?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep file'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete file'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _repository.removeProjectFile(projectId: projectId, path: path);
      if (!mounted) return;
      _projectFiles = _repository.projectFiles(projectId);
      if (_selectedNestedPath == path) {
        _selectedNestedPath = null;
        _nestedContents.clear();
        _nestedDirty = false;
      }
      setState(() => _message = 'Removed $path from this device.');
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    }
  }

  Future<void> _previewAtFileContext() async {
    final projectId = _selectedId;
    if (projectId == null) return;
    try {
      final contextFiles = _repository.contextFilesForPrompt(
        projectId,
        _generationPrompt.text,
      );
      if (contextFiles.isEmpty) {
        setState(
          () => _message =
              'Add an explicit @path reference to the website brief first.',
        );
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Review @file context'),
          content: SizedBox(
            width: 560,
            height: 520,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Only these explicitly referenced project-relative files will be included.',
                  ),
                  const SizedBox(height: 12),
                  for (final entry in contextFiles.entries) ...[
                    Text(
                      entry.key,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      entry.value.isEmpty ? '(empty file)' : entry.value,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    }
  }

  Future<void> _exportProjectZip() async {
    final projectId = _selectedId;
    if (projectId == null || _dirty || _nestedDirty || _saving || _generating) {
      setState(
        () => _message = 'Save all editor changes before exporting a ZIP.',
      );
      return;
    }
    try {
      final bytes = _repository.exportProjectZip(projectId);
      final project = _repository.all().firstWhere(
        (item) => item['id'] == projectId,
      );
      final base = (project['name'] as String? ?? 'website-project')
          .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '-')
          .replaceAll(RegExp(r'-+'), '-')
          .replaceAll(RegExp(r'^-|-$'), '');
      final result = await AssistantState.device
          .invokeMapMethod<String, dynamic>('export_bytes', {
            'bytes': bytes,
            'filename': '${base.isEmpty ? 'website-project' : base}.zip',
          });
      if (mounted && result?['saved'] == true) {
        setState(() => _message = 'ZIP saved to the location you chose.');
      }
    } on PlatformException catch (error) {
      if (mounted) {
        setState(() => _message = error.message ?? 'ZIP export failed.');
      }
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    }
  }

  Future<void> _generateWebsite() async {
    if (_selectedId == null) {
      setState(() => _message = 'Create or choose a local project first.');
      return;
    }
    if (widget.state.engine != 'gemini') {
      setState(
        () => _message = 'Choose Gemini in Settings before using online website generation. No project source was sent.',
      );
      return;
    }
    final client = GeminiFeatureClient(
      model: widget.state.geminiModelSelection,
      apiKey: widget.state.geminiApiKey,
      clientFactory: widget.state.clientFactory,
    );
    if (client.apiKey.trim().isEmpty) {
      setState(
        () => _message = 'Add a Gemini API key in Settings before using online website generation. No project source was sent.',
      );
      return;
    }
    final prompt = _generationPrompt.text.trim();
    if (prompt.isEmpty) {
      setState(() => _message = 'Describe the website you want to draft.');
      return;
    }
    final Map<String, String> referencedFiles;
    try {
      referencedFiles = _repository.contextFilesForPrompt(_selectedId!, prompt);
    } catch (error) {
      setState(() => _message = error.toString());
      return;
    }
    final reviewFiles = <String, String>{
      'index.html': _html.text,
      'style.css': _css.text,
      'script.js': _js.text,
      ...referencedFiles,
    };
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Send project to Gemini?'),
        content: SizedBox(
          width: 560,
          height: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your website brief and the source files below will be sent online to Google Gemini (${client.model}). API quota or charges may apply. Generated code is untrusted: it will be shown for review, never run, and saved only if you choose to load and then save it.',
                ),
                const SizedBox(height: 12),
                const Text('Brief'),
                SelectableText(prompt),
                const SizedBox(height: 12),
                for (final entry in reviewFiles.entries) ...[
                  Text(
                    entry.key,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    entry.value.isEmpty ? '(empty file)' : entry.value,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Send and generate'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _generating = true;
      _message = 'Generating a draft with Gemini…';
    });
    try {
      final answer = await client.generateWebProject(
        prompt: prompt,
        html: _html.text,
        css: _css.text,
        js: _js.text,
        referencedFiles: referencedFiles,
      );
      final generated = GeneratedWebProject.fromResponse(answer.text);
      if (!mounted) return;
      final useDraft = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Review generated website'),
          content: SizedBox(
            width: 560,
            height: 520,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'This code has not been run. Review it before using; saving only stores text on this device.',
                  ),
                  const SizedBox(height: 16),
                  for (final file in [
                    ('index.html', generated.html),
                    ('style.css', generated.css),
                    ('script.js', generated.js),
                  ]) ...[
                    Text(
                      file.$1,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      file.$2.isEmpty ? '(empty)' : file.$2,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Discard'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Use in editor'),
            ),
          ],
        ),
      );
      if (useDraft == true && mounted) {
        _html.text = generated.html;
        _css.text = generated.css;
        _js.text = generated.js;
        setState(() {
          _dirty = true;
          _message = 'Draft loaded for review. Save it yourself when ready.';
        });
      } else if (mounted) {
        setState(() => _message = 'Generated draft discarded.');
      }
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _addTodo() async {
    final id = _selectedId;
    if (id == null || _todo.text.trim().isEmpty) return;
    try {
      await _repository.addTodo(id, _todo.text);
      if (!mounted) return;
      _todo.clear();
      _todos = _repository.todos(id);
      setState(() => _message = 'Task saved on this device.');
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    }
  }

  Future<void> _setTodoStatus(String todoId, String status) async {
    final id = _selectedId;
    if (id == null) return;
    try {
      await _repository.setTodoStatus(id, todoId, status);
      if (!mounted) return;
      _todos = _repository.todos(id);
      setState(() => _message = 'Task status saved on this device.');
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    }
  }

  Future<void> _removeTodo(String todoId) async {
    final id = _selectedId;
    if (id == null) return;
    try {
      await _repository.removeTodo(id, todoId);
      if (!mounted) return;
      _todos = _repository.todos(id);
      setState(() => _message = 'Task removed from this device.');
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    }
  }

  Future<void> _moveTodo(int index, int delta) async {
    final id = _selectedId;
    final next = index + delta;
    if (id == null || next < 0 || next >= _todos.length) return;
    final ordered = _todos.map((item) => item['id'] as String).toList();
    final moved = ordered.removeAt(index);
    ordered.insert(next, moved);
    try {
      await _repository.reorderTodos(id, ordered);
      if (!mounted) return;
      _todos = _repository.todos(id);
      setState(() => _message = 'Task order saved on this device.');
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    }
  }

  void _review() {
    try {
      final findings = LocalWebProjects.review(
        html: _html.text,
        css: _css.text,
        js: _js.text,
        files: _projectFiles,
      );
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Basic text review'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'These checks do not execute or fully validate your code.',
                  ),
                  const SizedBox(height: 12),
                  for (final finding in findings)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text('- $finding'),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (error) {
      setState(() => _message = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) => AbsorbPointer(
    absorbing: _generating,
    child: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Card(
          child: Padding(
            padding: EdgeInsets.all(14),
            child: Text(
              'Create and edit HTML/CSS/JavaScript drafts stored in this app’s encrypted local data; the code is never run. Nested project files, basic static review, explicit @file context preview and user-selected ZIP export are supported. Optional Gemini generation sends only the reviewed brief and listed source after you confirm; its reply remains text until you choose to use and save it.',
            ),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed:
                _saving ||
                    _generating ||
                    _projects.length >= LocalWebProjects.maxProjects
                ? null
                : _create,
            icon: const Icon(Icons.add),
            label: const Text('New project'),
          ),
        ),
        if (_projects.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Your projects', style: Theme.of(context).textTheme.titleMedium),
          for (final project in _projects)
            Card(
              child: ListTile(
                title: Text(project['name'] as String? ?? 'Untitled project'),
                subtitle: Text('Edited ${project['updated_at'] ?? ''}'),
                selected: project['id'] == _selectedId,
                trailing: const Icon(Icons.chevron_right),
                onTap: _saving || _generating ? null : () => _select(project),
              ),
            ),
        ],
        if (_selectedId != null) ...[
          const Divider(height: 28),
          TextField(
            controller: _name,
            maxLength: LocalWebProjects.maxNameLength,
            decoration: const InputDecoration(labelText: 'Project name'),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _file,
            decoration: const InputDecoration(labelText: 'File'),
            items: const [
              DropdownMenuItem(value: 'HTML', child: Text('index.html')),
              DropdownMenuItem(value: 'CSS', child: Text('style.css')),
              DropdownMenuItem(value: 'JavaScript', child: Text('script.js')),
            ],
            onChanged: (value) => setState(() => _file = value ?? 'HTML'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _activeController,
            minLines: 18,
            maxLines: 28,
            maxLength: LocalWebProjects.maxFileCharacters,
            keyboardType: TextInputType.multiline,
            autocorrect: false,
            enableSuggestions: false,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            decoration: InputDecoration(
              labelText: '$_file source',
              alignLabelWithHint: true,
              border: const OutlineInputBorder(),
              helperText: 'Stored as text. JavaScript is not executed.',
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Nested project files',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              OutlinedButton.icon(
                onPressed:
                    _saving ||
                        _generating ||
                        _projectFiles.length >= LocalWebProjects.maxNestedFiles
                    ? null
                    : _createProjectFile,
                icon: const Icon(Icons.add),
                label: const Text('Add file'),
              ),
            ],
          ),
          const Text(
            'Project-relative paths are bounded and kept as local text; nested files are included in ZIP exports only after you choose to export.',
          ),
          if (_projectFiles.isEmpty) const Text('No nested files yet.'),
          for (final path in _projectFiles.keys.toList()..sort())
            Card(
              child: ListTile(
                title: Text(path),
                selected: _selectedNestedPath == path,
                onTap: _saving || _generating
                    ? null
                    : () => _selectProjectFile(path),
                trailing: IconButton(
                  tooltip: 'Delete nested file',
                  onPressed: _saving || _generating
                      ? null
                      : () => _deleteProjectFile(path),
                  icon: const Icon(Icons.delete_outline),
                ),
              ),
            ),
          if (_selectedNestedPath != null) ...[
            const SizedBox(height: 8),
            Text(
              'Editing $_selectedNestedPath',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            TextField(
              controller: _nestedContents,
              minLines: 8,
              maxLines: 18,
              maxLength: LocalWebProjects.maxNestedFileCharacters,
              keyboardType: TextInputType.multiline,
              autocorrect: false,
              enableSuggestions: false,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              decoration: const InputDecoration(
                labelText: 'Nested file source',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() => _nestedDirty = true),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: _saving || _generating ? null : _saveProjectFile,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save nested file'),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Text(
            'Generate a website draft',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const Text(
            'Gemini uses the brief and current source as context. The generated files stay text-only and are not executed.',
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _generationPrompt,
            minLines: 2,
            maxLines: 5,
            maxLength: 4000,
            decoration: const InputDecoration(
              labelText: 'What should the website do or look like?',
              hintText: 'Describe the audience, content, and visual direction',
              border: OutlineInputBorder(),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _saving || _generating
                    ? null
                    : _previewAtFileContext,
                icon: const Icon(Icons.attach_file),
                label: const Text('Preview @file context'),
              ),
              OutlinedButton.icon(
                onPressed: _saving || _generating || _dirty || _nestedDirty
                    ? null
                    : _exportProjectZip,
                icon: const Icon(Icons.archive_outlined),
                label: const Text('Export project ZIP'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _saving || _generating ? null : _generateWebsite,
              icon: _generating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome),
              label: Text(_generating ? 'Generating…' : 'Generate with Gemini'),
            ),
          ),
          const SizedBox(height: 16),
          Text('Project tasks', style: Theme.of(context).textTheme.titleMedium),
          const Text(
            'Keep a local ordered checklist; changing a task never runs or sends code.',
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _todo,
                  maxLength: LocalWebProjects.maxTodoLength,
                  decoration: const InputDecoration(labelText: 'Add a task'),
                  onSubmitted: (_) => _addTodo(),
                ),
              ),
              IconButton(
                tooltip: 'Add task',
                onPressed: _saving ? null : _addTodo,
                icon: const Icon(Icons.add_task),
              ),
            ],
          ),
          if (_todos.isEmpty) const Text('No tasks yet.'),
          for (var index = 0; index < _todos.length; index++)
            Card(
              child: ListTile(
                title: Text(_todos[index]['content'] as String? ?? ''),
                leading: DropdownButton<String>(
                  value:
                      LocalWebProjects.todoStatuses.contains(
                        _todos[index]['status'],
                      )
                      ? _todos[index]['status'] as String
                      : 'pending',
                  underline: const SizedBox.shrink(),
                  items: const [
                    DropdownMenuItem(value: 'pending', child: Text('To do')),
                    DropdownMenuItem(
                      value: 'in_progress',
                      child: Text('Doing'),
                    ),
                    DropdownMenuItem(value: 'completed', child: Text('Done')),
                    DropdownMenuItem(value: 'failed', child: Text('Blocked')),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) {
                          if (value != null) {
                            _setTodoStatus(
                              _todos[index]['id'] as String,
                              value,
                            );
                          }
                        },
                ),
                trailing: Wrap(
                  spacing: 0,
                  children: [
                    IconButton(
                      tooltip: 'Move task up',
                      onPressed: _saving || index == 0
                          ? null
                          : () => _moveTodo(index, -1),
                      icon: const Icon(Icons.arrow_upward),
                    ),
                    IconButton(
                      tooltip: 'Move task down',
                      onPressed: _saving || index == _todos.length - 1
                          ? null
                          : () => _moveTodo(index, 1),
                      icon: const Icon(Icons.arrow_downward),
                    ),
                    IconButton(
                      tooltip: 'Delete task',
                      onPressed: _saving
                          ? null
                          : () => _removeTodo(_todos[index]['id'] as String),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _saving || _generating || _nestedDirty
                    ? null
                    : _save,
                icon: const Icon(Icons.save_outlined),
                label: Text(_saving ? 'Saving…' : 'Save on device'),
              ),
              OutlinedButton.icon(
                onPressed: _saving ? null : _review,
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('Basic text review'),
              ),
            ],
          ),
        ],
        if (_message.isNotEmpty) ...[
          const SizedBox(height: 8),
          Semantics(liveRegion: true, child: Text(_message)),
        ],
        if (_projects.isEmpty) ...[
          const SizedBox(height: 16),
          const Text('No local projects yet.'),
        ],
      ],
    ),
  );
}
