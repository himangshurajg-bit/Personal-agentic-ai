import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

const promptTemplateLimit = 20;
const promptTemplateTitleLimit = 60;
const promptTemplateTextLimit = 4000;
const promptTemplatesStorageKey = 'assistant_prompt_templates_v1';

class PromptTemplate {
  final String id;
  final String title;
  final String prompt;

  const PromptTemplate({
    required this.id,
    required this.title,
    required this.prompt,
  });

  Map<String, Object?> toJson() => {'id': id, 'title': title, 'prompt': prompt};

  static PromptTemplate? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    final title = value['title'];
    final prompt = value['prompt'];
    if (id is! String || title is! String || prompt is! String) return null;
    final cleanTitle = title.trim();
    final cleanPrompt = prompt.trim();
    if (id.isEmpty ||
        cleanTitle.isEmpty ||
        cleanTitle.length > promptTemplateTitleLimit ||
        cleanPrompt.isEmpty ||
        cleanPrompt.length > promptTemplateTextLimit) {
      return null;
    }
    return PromptTemplate(id: id, title: cleanTitle, prompt: cleanPrompt);
  }
}

abstract interface class PromptTemplateStorage {
  Future<String?> read();
  Future<void> write(String value);
}

class SharedPreferencesPromptTemplateStorage implements PromptTemplateStorage {
  @override
  Future<String?> read() async => (await SharedPreferences.getInstance())
      .getString(promptTemplatesStorageKey);

  @override
  Future<void> write(String value) async =>
      (await SharedPreferences.getInstance()).setString(
        promptTemplatesStorageKey,
        value,
      );
}

class PromptTemplateRepository {
  final PromptTemplateStorage storage;
  final String Function() createId;

  PromptTemplateRepository(this.storage, {String Function()? createId})
    : createId = createId ?? _defaultId;

  static String _defaultId() =>
      DateTime.now().microsecondsSinceEpoch.toString();

  Future<List<PromptTemplate>> list() async {
    final raw = await storage.read();
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .map(PromptTemplate.fromJson)
          .whereType<PromptTemplate>()
          .take(promptTemplateLimit)
          .toList(growable: false);
    } on FormatException {
      return [];
    }
  }

  Future<PromptTemplate> create({
    required String title,
    required String prompt,
  }) async {
    final cleanTitle = _validate(title, promptTemplateTitleLimit, 'Name');
    final cleanPrompt = _validate(prompt, promptTemplateTextLimit, 'Prompt');
    final current = await list();
    if (current.length >= promptTemplateLimit) {
      throw StateError('You can save up to $promptTemplateLimit templates.');
    }
    final template = PromptTemplate(
      id: createId(),
      title: cleanTitle,
      prompt: cleanPrompt,
    );
    await _save([...current, template]);
    return template;
  }

  Future<PromptTemplate> update(
    String id, {
    required String title,
    required String prompt,
  }) async {
    final cleanTitle = _validate(title, promptTemplateTitleLimit, 'Name');
    final cleanPrompt = _validate(prompt, promptTemplateTextLimit, 'Prompt');
    final current = await list();
    final index = current.indexWhere((item) => item.id == id);
    if (index < 0) throw StateError('That template no longer exists.');
    final updated = PromptTemplate(
      id: id,
      title: cleanTitle,
      prompt: cleanPrompt,
    );
    current[index] = updated;
    await _save(current);
    return updated;
  }

  Future<void> delete(String id) async {
    final current = await list();
    await _save(current.where((item) => item.id != id).toList());
  }

  /// Returns plain draft text only. The caller must leave it for the user to review/send.
  String prepareDraft(PromptTemplate template) => template.prompt;

  Future<void> _save(List<PromptTemplate> templates) => storage.write(
    jsonEncode(templates.map((template) => template.toJson()).toList()),
  );

  static String _validate(String value, int maxLength, String label) {
    final result = value.trim();
    if (result.isEmpty) throw FormatException('$label can’t be empty.');
    if (result.length > maxLength) throw FormatException('$label is too long.');
    return result;
  }
}
