import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Device-owned data. No networking. Writes are serialized and commit before visibility.
class PhoneData {
  final FlutterSecureStorage storage;
  Map<String, dynamic> _data = {
    'chats': <String, dynamic>{},
    'memories': [],
    'tasks': [],
    'attempts': [],
    'actions': [],
  };
  bool _loadFailed = false;
  Future<void> _tail = Future.value();
  PhoneData(this.storage);
  Future<void> load() async {
    try {
      final value = await storage.read(key: 'phone_data_v1');
      if (value != null) {
        final parsed = Map<String, dynamic>.from(jsonDecode(value));
        if (parsed['chats'] is! Map ||
            ![
              'memories',
              'tasks',
              'attempts',
              'actions',
            ].every((k) => parsed[k] is List)) {
          throw const FormatException('Invalid local data');
        }
        _data = parsed;
      }
      _loadFailed = false;
    } catch (_) {
      _loadFailed = true;
      rethrow;
    }
  }

  Map<String, dynamic> get snapshot =>
      Map<String, dynamic>.from(jsonDecode(jsonEncode(_data)));
  Future<void> change(void Function(Map<String, dynamic>) edit) {
    final run = _tail.then((_) async {
      if (_loadFailed) {
        throw StateError(
          'Local storage could not be loaded. Existing data was not overwritten.',
        );
      }
      final next = snapshot;
      edit(next);
      final encoded = jsonEncode(next);
      if (encoded.length > 2000000) {
        throw StateError(
          'Local data is full. Export and delete older chats before adding more.',
        );
      }
      await storage.write(key: 'phone_data_v1', value: encoded);
      _data = next;
    });
    _tail = run.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return run;
  }

  List<Map<String, dynamic>> rows(String field) => (snapshot[field] as List)
      .map((x) => Map<String, dynamic>.from(x))
      .toList();
  List<Map<String, dynamic>> chat(String id) =>
      List<Map<String, dynamic>>.from(snapshot['chats'][id] ?? []);
  Future<void> writeChat(String id, List<Map<String, dynamic>> messages) =>
      change((d) => d['chats'][id] = jsonDecode(jsonEncode(messages)));
  Future<void> deleteChat(String id) => change((d) => d['chats'].remove(id));
  List<Map<String, dynamic>> searchChats(String query) {
    final results = <Map<String, dynamic>>[];
    (snapshot['chats'] as Map).forEach((id, items) {
      final matches = (items as List)
          .where(
            (m) => m['text'].toString().toLowerCase().contains(
              query.toLowerCase(),
            ),
          )
          .toList();
      if (matches.isNotEmpty) {
        results.add({
          'conversation': id,
          'title': matches.first['text'],
          'matches': matches.length,
        });
      }
    });
    return results;
  }

  String id() => DateTime.now().microsecondsSinceEpoch.toString();
  Future<void> saveMemory(
    String fact,
    String scope, {
    String? id,
    String type = 'preference',
  }) async {
    fact = fact.trim();
    if (fact.isEmpty ||
        fact.length > 1000 ||
        !['preference', 'project', 'approved_summary'].contains(type)) {
      throw ArgumentError('Choose a memory type and 1–1000 characters.');
    }
    await change((d) {
      final rows = d['memories'] as List;
      final index = rows.indexWhere((m) => m['id'] == id);
      if (id != null && index < 0) throw StateError('Memory no longer exists.');
      final entry = {
        'id': id ?? this.id(),
        'fact': fact,
        'conversation': scope,
        'type': type,
        'approved_at': DateTime.now().toUtc().toIso8601String(),
      };
      if (index >= 0) {
        rows[index] = entry;
      } else {
        rows.add(entry);
      }
    });
  }

  Future<void> forget(String id) =>
      change((d) => (d['memories'] as List).removeWhere((m) => m['id'] == id));
  List<Map<String, dynamic>> relevant(String text, String scope) {
    final words = text
        .toLowerCase()
        .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
        .where((s) => s.length > 1)
        .toSet();
    final scored =
        rows('memories')
            .where(
              (m) => m['conversation'] == scope || m['conversation'] == 'all',
            )
            .map((m) {
              final terms = m['fact']
                  .toString()
                  .toLowerCase()
                  .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
                  .toSet();
              return (memory: m, score: words.intersection(terms).length);
            })
            .where((r) => r.score > 0)
            .toList()
          ..sort((a, b) => b.score.compareTo(a.score));
    return scored.take(5).map((r) => r.memory).toList();
  }

  Future<void> task(String title) async {
    title = title.trim();
    if (title.isEmpty || title.length > 120) {
      throw ArgumentError('Task needs 1–120 characters.');
    }
    await change(
      (d) =>
          (d['tasks'] as List).add({'id': id(), 'title': title, 'done': false}),
    );
  }

  Future<void> setTask(String id, bool done) => change((d) {
    for (final m in d['tasks']) {
      if (m['id'] == id) m['done'] = done;
    }
  });
  Future<void> attempt(Map<String, dynamic> entry) => change(
    (d) => (d['attempts'] as List).add({
      ...entry,
      'id': id(),
      'at': DateTime.now().toUtc().toIso8601String(),
    }),
  );
  String export() => const JsonEncoder.withIndent('  ').convert(snapshot);
}
