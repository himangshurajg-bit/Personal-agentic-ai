import 'dart:convert';

import 'package:flutter/services.dart';
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
    'study_decks': [],
    'flashcards': [],
    'study_reviews': [],
    'study_lessons': [],
    'study_practice_attempts': [],
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
        // Additive migration for installs created before local flashcards.
        parsed.putIfAbsent('study_decks', () => <dynamic>[]);
        parsed.putIfAbsent('flashcards', () => <dynamic>[]);
        parsed.putIfAbsent('study_reviews', () => <dynamic>[]);
        parsed.putIfAbsent('study_lessons', () => <dynamic>[]);
        parsed.putIfAbsent('study_practice_attempts', () => <dynamic>[]);
        if (parsed['study_decks'] is! List ||
            parsed['flashcards'] is! List ||
            parsed['study_reviews'] is! List ||
            parsed['study_lessons'] is! List ||
            parsed['study_practice_attempts'] is! List) {
          throw const FormatException('Invalid local study data');
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
  static const _rustSearch = MethodChannel('personal_assistant/rust_search');
  bool lastSearchUsedRust = false;

  Future<List<Map<String, dynamic>>> searchChats(String query) async {
    final chats = _data['chats'] as Map<String, dynamic>;
    // Browsing an empty query does not need to cross the platform channel.
    if (query.trim().isEmpty) {
      lastSearchUsedRust = false;
      return _searchChatsDart(query, chats);
    }
    final request = jsonEncode({'query': query, 'conversations': chats});
    try {
      final raw = await _rustSearch.invokeMethod<String>('search_chats', {
        'request': request,
      });
      if (raw == null) {
        throw const FormatException('Missing Rust search result');
      }
      final response = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final results = response['results'];
      if (response['engine'] != 'rust' ||
          response['error'] != null ||
          results is! List) {
        throw const FormatException('Invalid Rust search result');
      }
      lastSearchUsedRust = true;
      return results
          .map((hit) => Map<String, dynamic>.from(hit as Map))
          .toList();
    } on PlatformException {
      lastSearchUsedRust = false;
      return _searchChatsDart(query, chats);
    } on MissingPluginException {
      lastSearchUsedRust = false;
      return _searchChatsDart(query, chats);
    } on FormatException {
      lastSearchUsedRust = false;
      return _searchChatsDart(query, chats);
    } on TypeError {
      lastSearchUsedRust = false;
      return _searchChatsDart(query, chats);
    }
  }

  List<Map<String, dynamic>> _searchChatsDart(
    String query,
    Map<String, dynamic> chats,
  ) {
    final results = <Map<String, dynamic>>[];
    chats.forEach((id, items) {
      if (items is! List) return;
      final matches = items.where((message) {
        if (message is! Map) return false;
        return message['text'].toString().toLowerCase().contains(
          query.toLowerCase(),
        );
      }).toList();
      if (matches.isNotEmpty) {
        final first = matches.first as Map;
        results.add({
          'conversation': id.toString(),
          'title': first['text']?.toString() ?? '',
          'matches': matches.length,
          'score': 0,
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

  List<Map<String, dynamic>> get studyLessons {
    final lessons = rows('study_lessons');
    lessons.sort(
      (a, b) => (b['created_at'] as int? ?? 0).compareTo(
        a['created_at'] as int? ?? 0,
      ),
    );
    return lessons;
  }

  Future<String> saveStudyLesson({
    required String topic,
    required String explanation,
    required String conversationId,
  }) async {
    final cleanTopic = topic.trim();
    final cleanExplanation = explanation.trim();
    if (cleanTopic.isEmpty || cleanTopic.length > 8000) {
      throw ArgumentError('A study topic must be 1–8,000 characters.');
    }
    if (cleanExplanation.isEmpty || cleanExplanation.length > 100000) {
      throw ArgumentError('A study explanation must be 1–100,000 characters.');
    }
    final lessonId = id();
    await change(
      (d) => (d['study_lessons'] as List).add({
        'id': lessonId,
        'topic': cleanTopic,
        'explanation': cleanExplanation,
        'conversation_id': conversationId,
        'created_at': DateTime.now().toUtc().millisecondsSinceEpoch,
      }),
    );
    return lessonId;
  }

  Future<void> deleteStudyLesson(String lessonId) => change((d) {
    final lessons = d['study_lessons'] as List;
    if (!lessons.any((lesson) => lesson['id'] == lessonId)) {
      throw StateError('Study lesson no longer exists.');
    }
    lessons.removeWhere((lesson) => lesson['id'] == lessonId);
    (d['study_practice_attempts'] as List).removeWhere(
      (attempt) => attempt['lesson_id'] == lessonId,
    );
  });

  Future<void> saveStudyPracticeAttempt({
    required String lessonId,
    required int questionNumber,
    required String answer,
    required String selfAssessment,
  }) async {
    if (answer.length > 4000 ||
        !['still_learning', 'understood'].contains(selfAssessment)) {
      throw ArgumentError('Invalid local practice response.');
    }
    await change((d) {
      if (!(d['study_lessons'] as List).any(
        (lesson) => lesson['id'] == lessonId,
      )) {
        throw StateError('Study lesson no longer exists.');
      }
      (d['study_practice_attempts'] as List).add({
        'id': id(),
        'lesson_id': lessonId,
        'question_number': questionNumber,
        'answer': answer.trim(),
        'self_assessment': selfAssessment,
        'at': DateTime.now().toUtc().toIso8601String(),
      });
    });
  }

  List<Map<String, dynamic>> get studyDecks => rows('study_decks');

  List<Map<String, dynamic>> cardsForDeck(String deckId) =>
      rows('flashcards').where((card) => card['deck_id'] == deckId).toList();

  List<Map<String, dynamic>> dueFlashcards({String? deckId, DateTime? now}) {
    final at = (now ?? DateTime.now()).toUtc().millisecondsSinceEpoch;
    final due = rows('flashcards').where((card) {
      return (deckId == null || card['deck_id'] == deckId) &&
          (card['due_at'] as int? ?? 0) <= at;
    }).toList();
    due.sort((a, b) {
      final time = (a['due_at'] as int? ?? 0).compareTo(
        b['due_at'] as int? ?? 0,
      );
      return time != 0
          ? time
          : (a['created_at'] as int).compareTo(b['created_at'] as int);
    });
    return due;
  }

  Future<String> createStudyDeck(String title) async {
    final clean = title.trim();
    if (clean.isEmpty || clean.length > 100) {
      throw ArgumentError('Deck name must be 1–100 characters.');
    }
    final deckId = id();
    await change(
      (d) => (d['study_decks'] as List).add({
        'id': deckId,
        'title': clean,
        'created_at': DateTime.now().toUtc().millisecondsSinceEpoch,
      }),
    );
    return deckId;
  }

  Future<void> updateStudyDeck(String deckId, String title) async {
    final clean = title.trim();
    if (clean.isEmpty || clean.length > 100) {
      throw ArgumentError('Deck name must be 1–100 characters.');
    }
    await change((d) {
      final decks = d['study_decks'] as List;
      final index = decks.indexWhere((deck) => deck['id'] == deckId);
      if (index < 0) throw StateError('Deck no longer exists.');
      decks[index]['title'] = clean;
    });
  }

  Future<void> deleteStudyDeck(String deckId) => change((d) {
    final decks = d['study_decks'] as List;
    if (!decks.any((deck) => deck['id'] == deckId)) {
      throw StateError('Deck no longer exists.');
    }
    decks.removeWhere((deck) => deck['id'] == deckId);
    (d['flashcards'] as List).removeWhere((card) => card['deck_id'] == deckId);
  });

  Future<String> createFlashcard(
    String deckId,
    String front,
    String back,
  ) async {
    final cleanFront = front.trim();
    final cleanBack = back.trim();
    if (cleanFront.isEmpty ||
        cleanBack.isEmpty ||
        cleanFront.length > 2000 ||
        cleanBack.length > 4000) {
      throw ArgumentError(
        'Enter a front (1–2,000 characters) and back (1–4,000 characters).',
      );
    }
    final cardId = id();
    final created = DateTime.now().toUtc().millisecondsSinceEpoch;
    await change((d) {
      if (!(d['study_decks'] as List).any((deck) => deck['id'] == deckId)) {
        throw StateError('Deck no longer exists.');
      }
      (d['flashcards'] as List).add({
        'id': cardId,
        'deck_id': deckId,
        'front': cleanFront,
        'back': cleanBack,
        'created_at': created,
        'due_at': created,
        'interval_days': 0,
        'review_count': 0,
        'repetitions': 0,
        'last_reviewed_at': null,
      });
    });
    return cardId;
  }

  Future<void> updateFlashcard(String cardId, String front, String back) async {
    final cleanFront = front.trim();
    final cleanBack = back.trim();
    if (cleanFront.isEmpty ||
        cleanBack.isEmpty ||
        cleanFront.length > 2000 ||
        cleanBack.length > 4000) {
      throw ArgumentError(
        'Enter a front (1–2,000 characters) and back (1–4,000 characters).',
      );
    }
    await change((d) {
      final cards = d['flashcards'] as List;
      final index = cards.indexWhere((card) => card['id'] == cardId);
      if (index < 0) throw StateError('Flashcard no longer exists.');
      cards[index]['front'] = cleanFront;
      cards[index]['back'] = cleanBack;
    });
  }

  Future<void> deleteFlashcard(String cardId) => change((d) {
    final cards = d['flashcards'] as List;
    if (!cards.any((card) => card['id'] == cardId)) {
      throw StateError('Flashcard no longer exists.');
    }
    cards.removeWhere((card) => card['id'] == cardId);
  });

  /// Applies a deterministic local schedule only after an actual review action.
  Future<void> reviewFlashcard(
    String cardId,
    String rating, {
    DateTime? reviewedAt,
  }) async {
    const ratings = {'again', 'hard', 'good', 'easy'};
    if (!ratings.contains(rating)) {
      throw ArgumentError('Choose a review rating.');
    }
    final now = (reviewedAt ?? DateTime.now()).toUtc();
    await change((d) {
      final cards = d['flashcards'] as List;
      final index = cards.indexWhere((card) => card['id'] == cardId);
      if (index < 0) throw StateError('Flashcard no longer exists.');
      final card = Map<String, dynamic>.from(cards[index]);
      final oldDue = card['due_at'] as int? ?? 0;
      final nowMs = now.millisecondsSinceEpoch;
      if (oldDue > nowMs) throw StateError('This card is not due yet.');
      final oldCount = card['review_count'] as int? ?? 0;
      final repetitions = card['repetitions'] as int? ?? 0;
      final oldInterval = card['interval_days'] as int? ?? 0;
      int days;
      switch (rating) {
        case 'again':
          days = 0;
          card['repetitions'] = 0;
          card['review_count'] = oldCount + 1;
          break;
        case 'hard':
          days = repetitions == 0
              ? 1
              : (oldInterval * 1.2).ceil().clamp(1, 3650).toInt();
          card['repetitions'] = repetitions + 1;
          card['review_count'] = oldCount + 1;
          break;
        case 'good':
          days = repetitions == 0
              ? 1
              : repetitions == 1
              ? 3
              : (oldInterval * 2).round().clamp(1, 3650).toInt();
          card['repetitions'] = repetitions + 1;
          card['review_count'] = oldCount + 1;
          break;
        default:
          days = repetitions == 0
              ? 3
              : (oldInterval * 2.5).round().clamp(2, 3650).toInt();
          card['repetitions'] = repetitions + 1;
          card['review_count'] = oldCount + 1;
      }
      final delay = rating == 'again'
          ? const Duration(minutes: 10).inMilliseconds
          : Duration(days: days).inMilliseconds;
      card['interval_days'] = days;
      card['last_reviewed_at'] = nowMs;
      card['due_at'] = nowMs + delay;
      cards[index] = card;
      (d['study_reviews'] as List).add({
        'card_id': cardId,
        'deck_id': card['deck_id'],
        'rating': rating,
        'reviewed_at': nowMs,
        'next_due_at': nowMs + delay,
      });
    });
  }

  int reviewedToday({DateTime? now}) {
    final local = now ?? DateTime.now();
    final start = DateTime(
      local.year,
      local.month,
      local.day,
    ).toUtc().millisecondsSinceEpoch;
    final end = DateTime(
      local.year,
      local.month,
      local.day + 1,
    ).toUtc().millisecondsSinceEpoch;
    return rows('study_reviews').where((review) {
      final at = review['reviewed_at'] as int;
      return at >= start && at < end;
    }).length;
  }

  String export() => const JsonEncoder.withIndent('  ').convert(snapshot);
}
