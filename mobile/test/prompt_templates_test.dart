import 'package:flutter_test/flutter_test.dart';
import 'package:personal_assistant/prompt_templates.dart';

class MemoryTemplateStorage implements PromptTemplateStorage {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async => this.value = value;
}

void main() {
  group('PromptTemplateRepository', () {
    late MemoryTemplateStorage storage;
    late PromptTemplateRepository repository;
    var nextId = 0;
    setUp(() {
      storage = MemoryTemplateStorage();
      repository = PromptTemplateRepository(
        storage,
        createId: () => 'id-${nextId++}',
      );
    });

    test(
      'creates, persists, edits, drafts and deletes without executing',
      () async {
        final first = await repository.create(
          title: ' Explain ',
          prompt: ' Teach me this. ',
        );
        expect((await repository.list()).single.title, 'Explain');
        expect(repository.prepareDraft(first), 'Teach me this.');
        final edited = await repository.update(
          first.id,
          title: 'Physics',
          prompt: 'Solve step by step',
        );
        expect((await repository.list()).single.prompt, edited.prompt);
        await repository.delete(first.id);
        expect(await repository.list(), isEmpty);
      },
    );

    test(
      'rejects empty or oversized fields and caps collection at twenty',
      () async {
        await expectLater(
          repository.create(title: ' ', prompt: 'x'),
          throwsFormatException,
        );
        await expectLater(
          repository.create(
            title: 'x',
            prompt: 'x' * (promptTemplateTextLimit + 1),
          ),
          throwsFormatException,
        );
        for (var i = 0; i < promptTemplateLimit; i++) {
          await repository.create(title: 'Template $i', prompt: 'Prompt $i');
        }
        await expectLater(
          repository.create(title: 'Overflow', prompt: 'No'),
          throwsStateError,
        );
        expect(await repository.list(), hasLength(promptTemplateLimit));
      },
    );

    test(
      'ignores malformed stored entries and malformed JSON safely',
      () async {
        storage.value =
            '[{"id":"a","title":"ok","prompt":"prompt"},{"bad":true}]';
        expect((await repository.list()).map((item) => item.id), ['a']);
        storage.value = '{';
        expect(await repository.list(), isEmpty);
      },
    );
  });
}
