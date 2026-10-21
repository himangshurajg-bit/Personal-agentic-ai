import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter/services.dart';

import 'assistant_state.dart';
import 'phone_screens.dart';

import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(AssistantApp(state: AssistantState()..initialize()));
}

class AssistantApp extends StatelessWidget {
  final AssistantState state;
  const AssistantApp({super.key, required this.state});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: state,
    builder: (context, _) => MaterialApp(
      title: state.assistantName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff5267a6)),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xffa9b9ef),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xff101827),
        useMaterial3: true,
      ),
      themeMode: state.theme == 'dark'
          ? ThemeMode.dark
          : state.theme == 'light'
          ? ThemeMode.light
          : ThemeMode.system,
      home: !state.ready
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : state.onboarded
          ? Home(state: state)
          : Onboarding(state: state),
      routes: {
        '/home': (_) => Home(state: state),
        '/chat': (_) => ChatScreen(state: state),
        '/settings': (_) => Settings(state: state),
        '/memory': (_) => Memories(state: state),
        '/library': (_) => PhoneLibrary(state: state),
        '/study': (_) => StudyScreen(state: state),
        '/files': (_) => SelectedFiles(state: state),
        '/automations': (_) => ActionHistory(state: state),
      },
    ),
  );
}

class Shell extends StatelessWidget {
  final String title;
  final Widget child;
  final List<Widget>? actions;
  final bool primaryNavigation;
  const Shell({
    super.key,
    required this.title,
    required this.child,
    this.actions,
    this.primaryNavigation = true,
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    bottomNavigationBar: !primaryNavigation
        ? null
        : NavigationBar(
            selectedIndex: switch (ModalRoute.of(context)?.settings.name) {
              '/chat' => 1,
              '/study' => 1,
              '/files' => 1,
              '/automations' => 2,
              '/memory' => 3,
              '/library' => 3,
              '/settings' => 4,
              _ => 0,
            },
            onDestinationSelected: (i) {
              final route = [
                '/home',
                '/chat',
                '/automations',
                '/memory',
                '/settings',
              ][i];
              if (ModalRoute.of(context)?.settings.name != route) {
                Navigator.pushReplacementNamed(context, route);
              }
            },
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                label: 'Home',
              ),
              NavigationDestination(
                icon: Icon(Icons.chat_bubble_outline),
                label: 'Chat',
              ),
              NavigationDestination(
                icon: Icon(Icons.bolt_outlined),
                label: 'Automations',
              ),
              NavigationDestination(
                icon: Icon(Icons.library_books_outlined),
                label: 'Memory & Library',
              ),
              NavigationDestination(icon: Icon(Icons.tune), label: 'Settings'),
            ],
          ),
    appBar: AppBar(
      title: Text(title),
      actions: actions,
      backgroundColor: Colors.transparent,
    ),
    body: Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: Theme.of(context).brightness == Brightness.dark
              ? const [Color(0xff19283e), Color(0xff111722), Color(0xff263139)]
              : const [Color(0xffe4ecfc), Color(0xfff5f6fb), Color(0xffe1efec)],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: child,
          ),
        ),
      ),
    ),
  );
}

class Glass extends StatelessWidget {
  final Widget child;
  const Glass({super.key, required this.child});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface.withValues(alpha: .75),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Theme.of(context).colorScheme.outline
                  .withValues(alpha: .25),
            ),
          ),
          child: Material(type: MaterialType.transparency, child: child),
        ),
      ),
    ),
  );
}

void notice(BuildContext context, Object text) {
  if (context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(text.toString())));
  }
}

class Onboarding extends StatelessWidget {
  final AssistantState state;
  const Onboarding({super.key, required this.state});
  @override
  Widget build(BuildContext context) => Shell(
    title: state.assistantName,
    primaryNavigation: false,
    child: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 32),
        const Icon(Icons.bubble_chart_outlined, size: 72),
        const SizedBox(height: 28),
        Text(
          'A little more space\nfor your day.',
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const SizedBox(height: 24),
        const Glass(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Your words. Your choices.', style: TextStyle(fontSize: 22)),
              SizedBox(height: 12),
              Text(
                'Keep notes, memories, tasks and study progress on your phone. Choose an online AI service or offline mode. No offline model is installed yet; there are no pretend AI replies.',
              ),
            ],
          ),
        ),
        const Glass(
          child: Text(
            'Voice starts only when you tap the microphone. Android speech recognition may use its provider’s network service. You can always type instead. Reminders ask for notification permission only when needed. No always-listening mode.',
          ),
        ),
        TextButton(
          onPressed: () => editAssistantName(context, state),
          child: const Text('Choose your assistant’s name'),
        ),
        FilledButton(
          onPressed: () async {
            try {
              await state.finishOnboarding();
            } catch (e) {
              if (context.mounted) {
                notice(context, e);
              }
            }
          },
          child: const Text('Get started'),
        ),
      ],
    ),
  );
}

class Home extends StatelessWidget {
  final AssistantState state;
  const Home({super.key, required this.state});
  Future<void> action(BuildContext context, Map<String, dynamic> action) async {
    try {
      final draft = await state.prepareAction(action);
      if (!context.mounted) {
        return;
      }
      final description = action['kind'] == 'reminder'
          ? 'Schedule “${action['title']}” for ${DateTime.fromMillisecondsSinceEpoch(action['at_ms'])}. Android delivery is approximate; battery restrictions may delay it.'
          : 'Open ${action['package']} on this device.';
      final approved = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Review device action'),
          content: Text(description),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Approve this action'),
            ),
          ],
        ),
      );
      if (approved != true) {
        return;
      }
      final result = await state.executeApproved(draft['id']);
      final report = result['detail'].toString();
      if (context.mounted) {
        notice(context, report);
      }
    } catch (e) {
      if (context.mounted) {
        notice(context, e);
      }
    }
  }

  Future<void> reminder(BuildContext context) async {
    final title = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('New reminder'),
        content: TextField(
          controller: title,
          maxLength: 120,
          decoration: const InputDecoration(labelText: 'What should it say?'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, title.text.trim()),
            child: const Text('Choose time'),
          ),
        ],
      ),
    );
    title.dispose();
    if (text == null || text.isEmpty || !context.mounted) {
      return;
    }
    final now = DateTime.now();
    final day = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      initialDate: now,
    );
    if (day == null || !context.mounted) {
      return;
    }
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
    );
    if (time == null || !context.mounted) {
      return;
    }
    await action(context, {
      'kind': 'reminder',
      'title': text,
      'at_ms': DateTime(
        day.year,
        day.month,
        day.day,
        time.hour,
        time.minute,
      ).millisecondsSinceEpoch,
    });
  }

  Future<void> notebook(BuildContext context) async {
    final controller = TextEditingController(text: state.note);
    final value = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Offline notebook'),
        content: TextField(
          controller: controller,
          minLines: 5,
          maxLines: 10,
          maxLength: 8000,
          decoration: const InputDecoration(
            hintText: 'Private note, stored only on this device',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, controller.text),
            child: const Text('Save on device'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null) {
      return;
    }
    try {
      await state.saveNote(value);
      if (context.mounted) {
        notice(context, 'Saved on this device.');
      }
    } catch (e) {
      if (context.mounted) {
        notice(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Shell(
    title: state.assistantName,
    actions: [
      IconButton(
        tooltip: 'Settings',
        onPressed: () => Navigator.pushNamed(context, '/settings'),
        icon: const Icon(Icons.tune),
      ),
    ],
    child: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Center(child: AssistantOrb(busy: state.busy)),
        const SizedBox(height: 12),
        Text(
          'A clearer day,\none thought at a time.',
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const SizedBox(height: 12),
        Text(
          'PERSONAL ASSISTANT  /  PRIVATE TEST',
          style: Theme.of(context).textTheme.labelSmall,
        ),
        const SizedBox(height: 24),
        Glass(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your local overview',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text(
                '${state.local.rows('tasks').where((r) => !r['done']).length} open tasks · ${state.local.rows('attempts').length} recorded study attempts',
              ),
              for (final task
                  in state.local.rows('tasks').where((r) => !r['done']).take(3))
                Text('— ${task['title']}'),
              for (final reminder
                  in state.local
                      .rows('actions')
                      .where(
                        (r) =>
                            r['status'] == 'scheduled' &&
                            r['action']['at_ms'] >
                                DateTime.now().millisecondsSinceEpoch,
                      )
                      .take(3))
                Text(
                  'Reminder: ${reminder['action']['title']} · ${DateTime.fromMillisecondsSinceEpoch(reminder['action']['at_ms'])}',
                ),
              const Text(
                'Only actual local records. Calendar and automatic briefings are not connected.',
              ),
            ],
          ),
        ),
        Glass(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.auto_awesome_outlined, size: 36),
              const SizedBox(height: 16),
              Text(
                'What’s on your mind?',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                '${state.config.description}. Local notes, memory, tasks and progress work without a server. Online sends always need review.',
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () => Navigator.pushNamed(context, '/chat'),
                icon: const Icon(Icons.arrow_forward),
                label: const Text('Open conversation'),
              ),
            ],
          ),
        ),
        Glass(
          child: Column(
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.book_outlined),
                title: const Text('Offline notebook'),
                subtitle: const Text('A note that stays on this device'),
                onTap: () => notebook(context),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.psychology_outlined),
                title: const Text('Chosen memories'),
                subtitle: const Text('Local · inspect, edit, export or forget'),
                onTap: () => Navigator.pushNamed(context, '/memory'),
              ),
              ListTile(
                leading: const Icon(Icons.checklist),
                title: const Text('Tasks & history'),
                subtitle: const Text(
                  'Local tasks, chat search and data export',
                ),
                onTap: () => Navigator.pushNamed(context, '/library'),
              ),
              ListTile(
                leading: const Icon(Icons.school_outlined),
                title: const Text('Study mode'),
                subtitle: const Text(
                  'Tutoring prompts and recorded practice attempts',
                ),
                onTap: () => Navigator.pushNamed(context, '/study'),
              ),
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: const Text('Selected files'),
                subtitle: const Text(
                  'Open only a file you choose; no broad storage access',
                ),
                onTap: () => Navigator.pushNamed(context, '/files'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.notifications_outlined),
                title: const Text('Set a reminder'),
                subtitle: const Text('Choose the details, then approve'),
                onTap: () => reminder(context),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.open_in_new),
                title: const Text('Open an Android app'),
                subtitle: const Text('Only supported installed apps'),
                onTap: () async {
                  final package = await showModalBottomSheet<String>(
                    context: context,
                    builder: (c) => SafeArea(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final entry in const {
                            'Settings': 'com.android.settings',
                            'Chrome': 'com.android.chrome',
                            'YouTube': 'com.google.android.youtube',
                            'Calculator': 'com.google.android.calculator',
                          }.entries)
                            ListTile(
                              title: Text(entry.key),
                              onTap: () => Navigator.pop(c, entry.value),
                            ),
                        ],
                      ),
                    ),
                  );
                  if (package != null && context.mounted) {
                    await action(context, {
                      'kind': 'open_app',
                      'package': package,
                    });
                  }
                },
              ),
            ],
          ),
        ),
        const Text(
          'Device actions need your review. The AI cannot run shell commands or send messages.',
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );
}

class ChatScreen extends StatefulWidget {
  final AssistantState state;
  const ChatScreen({super.key, required this.state});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final input = TextEditingController();
  static const voiceEvents = MethodChannel('personal_assistant/voice');
  final tts = FlutterTts();
  bool listening = false, speaking = false;
  double level = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    tts.setStartHandler(() {
      if (mounted) setState(() => speaking = true);
    });
    tts.setCompletionHandler(() {
      if (mounted) setState(() => speaking = false);
    });
    tts.setCancelHandler(() {
      if (mounted) setState(() => speaking = false);
    });
    tts.setErrorHandler((_) {
      if (mounted) setState(() => speaking = false);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.state.loadHistory();
    });
    voiceEvents.setMethodCallHandler((call) async {
      if (!mounted || call.method != 'voice_event') return;
      final event = Map<String, dynamic>.from(call.arguments);
      if (event['kind'] == 'text' || event['kind'] == 'partial') {
        input.text = event['value'] as String;
      }
      setState(() {
        if (event['kind'] == 'listening') listening = true;
        if (event['kind'] == 'level') {
          level = (event['value'] as num).toDouble();
        }
        if (event['kind'] == 'stopped' || event['kind'] == 'error') {
          listening = false;
          level = 0;
        }
      });
      if (event['kind'] == 'error') notice(context, event['value'].toString());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      AssistantState.device.invokeMethod('voice_cancel');
      tts.stop();
      widget.state.stop();
      if (mounted) {
        setState(() {
          listening = false;
          speaking = false;
        });
      }
    }
  }

  Future<void> stopAll() async {
    widget.state.stop();
    await AssistantState.device.invokeMethod('voice_cancel');
    await tts.stop();
    if (mounted) {
      setState(() {
        listening = false;
        speaking = false;
        level = 0;
      });
    }
  }

  Future<void> listen() async {
    if (listening) {
      await stopAll();
      return;
    }
    await stopAll();
    if (!mounted) return;
    var approved = false;
    if (widget.state.speechMode == 'online') {
      approved =
          await showDialog<bool>(
            context: context,
            builder: (c) => AlertDialog(
              title: const Text('Use online speech recognition?'),
              content: Text(
                'Your Android recognition service may send microphone audio to its provider for ${widget.state.language}. This is independent of the AI engine. No offline fallback or automatic retry.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(c, false),
                  child: const Text('Keep typing'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(c, true),
                  child: const Text('Start online microphone'),
                ),
              ],
            ),
          ) ??
          false;
      if (!approved) return;
    }
    try {
      await AssistantState.device.invokeMethod('voice_start', {
        'mode': widget.state.speechMode,
        'locale': widget.state.language,
        'approved_online': approved,
      });
    } on PlatformException catch (e) {
      if (mounted) {
        notice(context, e.message ?? 'Speech unavailable; type instead.');
      }
    }
  }

  Future<void> send([String? retry]) async {
    final text = retry ?? input.text;
    if (text.trim().isEmpty) {
      return;
    }
    await AssistantState.device.invokeMethod('voice_cancel');
    await tts.stop();
    if (mounted) {
      setState(() => listening = false);
    }
    if (!mounted) return;
    final payload = await reviewOnline(context, widget.state, text);
    if (!payload) return;
    input.clear();
    await widget.state.send(
      text,
      approvedOnline: true,
      shareMemories: widget.state.shareMemories,
      shareHistory: widget.state.shareHistory,
    );
    if (widget.state.speakReplies &&
        widget.state.error.isEmpty &&
        widget.state.messages.isNotEmpty &&
        mounted) {
      final last = widget.state.messages.last;
      if (last['role'] == 'assistant' && last['state'] == 'complete') {
        try {
          if (await tts.isLanguageAvailable(widget.state.language) != true) {
            throw StateError('Selected speech language is unavailable');
          }
          final voices = await tts.getVoices as List;
          final localVoice = voices
              .cast<Map>()
              .where(
                (v) =>
                    v['locale'].toString().replaceAll('_', '-').toLowerCase() ==
                        widget.state.language.toLowerCase() &&
                    v['network_required'].toString() == '0',
              )
              .firstOrNull;
          if (localVoice == null) {
            throw StateError(
              'No verified offline voice installed for this language',
            );
          }
          await tts.setLanguage(widget.state.language);
          await tts.setVoice({
            'name': localVoice['name'].toString(),
            'locale': localVoice['locale'].toString(),
          });
          await tts.awaitSpeakCompletion(true);
          await tts.speak(last['text']);
        } catch (_) {
          if (mounted) {
            notice(
              context,
              'No installed offline voice for the selected language, or playback unavailable. The reply remains readable; no network voice was substituted.',
            );
          }
        }
        if (mounted) {
          setState(() => speaking = false);
        }
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    voiceEvents.setMethodCallHandler(null);
    AssistantState.device.invokeMethod('voice_cancel');
    tts.stop();
    widget.state.stop(notify: false);
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.state,
    builder: (context, _) {
      final state = widget.state;
      return Shell(
        title: state.assistantName,
        actions: [
          IconButton(
            tooltip: 'Read replies aloud',
            onPressed: () =>
                setState(() => state.speakReplies = !state.speakReplies),
            icon: Icon(state.speakReplies ? Icons.volume_up : Icons.volume_off),
          ),
          IconButton(
            tooltip: 'Conversation history',
            onPressed: state.busy
                ? null
                : () async {
                    try {
                      final rows = await state.conversations();
                      if (!context.mounted) return;
                      final selected = await showDialog<String>(
                        context: context,
                        builder: (c) => SimpleDialog(
                          title: const Text('Conversation history'),
                          children: rows.isEmpty
                              ? [
                                  const Padding(
                                    padding: EdgeInsets.all(24),
                                    child: Text('No saved conversations yet.'),
                                  ),
                                ]
                              : rows
                                    .map(
                                      (r) => SimpleDialogOption(
                                        onPressed: () => Navigator.pop(
                                          c,
                                          r['conversation'] as String,
                                        ),
                                        child: Text(
                                          (r['title'] as String? ??
                                              'Conversation'),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    )
                                    .toList(),
                        ),
                      );
                      if (selected != null) {
                        await AssistantState.device.invokeMethod(
                          'voice_cancel',
                        );
                        await tts.stop();
                        if (mounted) {
                          setState(() {
                            listening = false;
                            speaking = false;
                          });
                        }
                        await state.selectConversation(selected);
                      }
                    } catch (e) {
                      if (context.mounted) notice(context, e);
                    }
                  },
            icon: const Icon(Icons.history),
          ),
          IconButton(
            tooltip: 'New conversation',
            onPressed: state.busy
                ? null
                : () async {
                    try {
                      await AssistantState.device.invokeMethod('voice_cancel');
                      await tts.stop();
                      if (mounted) {
                        setState(() {
                          listening = false;
                          speaking = false;
                        });
                      }
                      await state.selectConversation(
                        'chat_${DateTime.now().microsecondsSinceEpoch}',
                        load: false,
                      );
                    } catch (e) {
                      if (context.mounted) notice(context, e);
                    }
                  },
            icon: const Icon(Icons.add_comment_outlined),
          ),
        ],
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: Text(
                '${state.config.description} · ${state.language} · ${state.specialist}. No automatic online fallback. Memory scope: ${state.conversation}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  if (state.messages.isEmpty)
                    const Glass(
                      child: Text(
                        'Start with a thought, a question, or a plan. No model is bundled with this private test.',
                      ),
                    ),
                  for (final m in state.messages)
                    Align(
                      alignment: m['role'] == 'user'
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 560),
                        child: Glass(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                m['role'] == 'user'
                                    ? 'YOU'
                                    : state.assistantName,
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                              const SizedBox(height: 6),
                              MarkdownBody(
                                data: m['text'] as String,
                                selectable: true,
                                imageBuilder: (_, _, _) => const Text(
                                  '[Remote image blocked — no automatic network fetch]',
                                ),
                                onTapLink: (_, _, _) => notice(
                                  context,
                                  'Links are not opened automatically. Review and copy the destination if needed.',
                                ),
                              ),
                              if (m['state'] != 'complete')
                                const Text(
                                  'Interrupted • not a completed reply',
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (state.busy)
                    Glass(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const LinearProgressIndicator(),
                          const SizedBox(height: 12),
                          SelectableText(
                            state.partial.isEmpty
                                ? 'Waiting for your service…'
                                : state.partial,
                          ),
                        ],
                      ),
                    ),
                  if (state.error.isNotEmpty)
                    Glass(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(state.error),
                          if (state.lastPrompt.isNotEmpty && !state.busy)
                            TextButton(
                              onPressed: () => send(state.lastPrompt),
                              child: const Text('Retry last message'),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            if (listening)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  children: [
                    const Text('Microphone on • listening'),
                    SizedBox(
                      height: 28,
                      child: CustomPaint(
                        size: const Size(180, 28),
                        painter: WavePainter(
                          level,
                          Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: listening ? 'Stop microphone' : 'Use microphone',
                    onPressed: listen,
                    icon: Icon(listening ? Icons.mic : Icons.mic_none),
                  ),
                  Expanded(
                    child: TextField(
                      controller: input,
                      minLines: 1,
                      maxLines: 5,
                      maxLength: 8000,
                      decoration: const InputDecoration(
                        hintText: 'Write a message…',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(24)),
                        ),
                        counterText: '',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: state.busy || speaking
                        ? 'Stop response'
                        : 'Send message',
                    onPressed: state.busy || speaking ? stopAll : send,
                    icon: Icon(
                      state.busy || speaking ? Icons.stop : Icons.arrow_upward,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

class WavePainter extends CustomPainter {
  final double level;
  final Color color;
  WavePainter(this.level, this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 24; i++) {
      final h =
          3 +
          (level.clamp(0, 20) / 20) * 20 * (.3 + .7 * math.sin(i * .8).abs());
      canvas.drawLine(
        Offset(i * 7.5, (size.height - h) / 2),
        Offset(i * 7.5, (size.height + h) / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(WavePainter old) =>
      old.level != level || old.color != color;
}

class Settings extends StatefulWidget {
  final AssistantState state;
  const Settings({super.key, required this.state});
  @override
  State<Settings> createState() => _SettingsState();
}

class _SettingsState extends State<Settings> {
  late final url = TextEditingController(text: widget.state.endpoint);
  late final token = TextEditingController(text: widget.state.token);
  late String speechMode = widget.state.speechMode;
  late String theme = widget.state.theme;
  late String engine = widget.state.engine, language = widget.state.language;
  late final model = TextEditingController(text: widget.state.model);
  late final name = TextEditingController(text: widget.state.assistantName);
  @override
  void dispose() {
    url.dispose();
    token.dispose();
    model.dispose();
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Shell(
    title: 'Settings',
    child: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Glass(
          child: Text(
            'Your chats, approved memories, notes, tasks and study records stay on this phone. AI is optional: offline inference is not installed; online requests require an explicit payload review. The private FastAPI adapter remains optional, not a requirement for local tools.',
          ),
        ),
        Glass(
          child: Column(
            children: [
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: speechMode,
                decoration: const InputDecoration(
                  labelText: 'Speech recognition — independent of AI',
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'offline',
                    child: Text('Offline · installed on-device service'),
                  ),
                  DropdownMenuItem(
                    value: 'online',
                    child: Text('Online · Android recognition provider'),
                  ),
                ],
                onChanged: (v) => setState(() => speechMode = v!),
              ),
              const Text(
                'Offline requires a verified installed language on Android 13+. Unsupported devices/languages stay unavailable. Online asks before microphone use. No silent network fallback.',
              ),
              TextField(
                controller: name,
                maxLength: 40,
                decoration: const InputDecoration(
                  labelText: 'Assistant display name',
                ),
              ),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: engine,
                decoration: const InputDecoration(labelText: 'AI engine'),
                items: [
                  for (final item in {
                    'offline': 'Offline · model not installed',
                    'compatible': 'Online · OpenAI-compatible',
                    'private_service': 'Online · private FastAPI',
                  }.entries)
                    DropdownMenuItem(value: item.key, child: Text(item.value)),
                ],
                onChanged: (v) => setState(() {
                  engine = v!;
                  token.clear();
                }),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: language,
                decoration: const InputDecoration(
                  labelText: 'Conversation / voice language',
                ),
                items: const [
                  DropdownMenuItem(value: 'en-IN', child: Text('English')),
                  DropdownMenuItem(
                    value: 'as-IN',
                    child: Text('অসমীয়া · Assamese'),
                  ),
                ],
                onChanged: (v) => setState(() => language = v!),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: model,
                decoration: const InputDecoration(
                  labelText: 'Model identifier (compatible provider)',
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Online providers may retain submitted content and charge your account. Configure only your own authorized service. No provider key is bundled. Offline never falls back online.',
              ),
              TextField(
                controller: url,
                decoration: const InputDecoration(labelText: 'Service origin'),
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: token,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: 'Provider / private-service token',
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: theme,
                decoration: const InputDecoration(labelText: 'Appearance'),
                items: [
                  for (final mode in ['system', 'light', 'dark'])
                    DropdownMenuItem(value: mode, child: Text(mode)),
                ],
                onChanged: (v) => setState(() => theme = v ?? 'system'),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () async {
                  try {
                    await widget.state.saveSettings(
                      url.text,
                      token.text,
                      theme,
                    );
                    await widget.state.setAssistantName(name.text);
                    await widget.state.saveSpeechMode(speechMode);
                    await widget.state.saveEngine(engine, model.text, language);
                    if (context.mounted) {
                      notice(context, 'Settings saved on this device.');
                    }
                  } catch (e) {
                    if (context.mounted) {
                      notice(context, e);
                    }
                  }
                },
                child: const Text('Save settings'),
              ),
              TextButton(
                onPressed: () async {
                  try {
                    final result = await widget.state.request('GET', '/health');
                    if (context.mounted) {
                      notice(
                        context,
                        result['provider_configured'] == true
                            ? 'Service reachable; model configured.'
                            : 'Service reachable; no AI provider configured.',
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      notice(context, e);
                    }
                  }
                },
                child: const Text('Test private FastAPI connection'),
              ),
            ],
          ),
        ),
        TextButton(
          onPressed: () async {
            try {
              final info = await AssistantState.device.invokeMapMethod(
                'device_status',
              );
              if (context.mounted) {
                notice(
                  context,
                  'Android API ${info?['sdk']} · installed on-device recognizer: ${info?['on_device_recognizer']} · system recognizer: ${info?['system_recognizer']}. These flags do not verify Assamese or installed language models.',
                );
              }
            } catch (e) {
              if (context.mounted) notice(context, e);
            }
          },
          child: const Text('Check device speech capabilities'),
        ),
        const Glass(
          child: Text(
            'Privacy & permissions\n\nMicrophone access is requested only when starting voice input. Notification permission is requested when scheduling your first reminder. Neither is needed for typed chat. Android speech providers may send audio to their service. There is no background microphone or wake phrase.\n\nReminders use approximate alarms and are lost if this private test app is removed. Battery settings can delay them.',
          ),
        ),
        TextButton(
          onPressed: () async {
            final yes = await showDialog<bool>(
              context: context,
              builder: (c) => AlertDialog(
                title: const Text('Delete current chat history?'),
                content: Text(
                  'Delete on-phone history for ${widget.state.conversation}. Saved memories and any provider/service copies remain separate.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(c, false),
                    child: const Text('Keep'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(c, true),
                    child: const Text('Delete history'),
                  ),
                ],
              ),
            );
            if (yes == true) {
              try {
                await widget.state.deleteHistory();
                widget.state.messages = [];
                if (context.mounted) {
                  notice(
                    context,
                    'Current on-phone history deleted. Provider/service copies were not deleted.',
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  notice(context, e);
                }
              }
            }
          },
          child: const Text('Delete current conversation history'),
        ),
      ],
    ),
  );
}

class Memories extends StatefulWidget {
  final AssistantState state;
  const Memories({super.key, required this.state});
  @override
  State<Memories> createState() => _MemoriesState();
}

class _MemoriesState extends State<Memories> {
  String error = '';
  bool loading = true;
  @override
  void initState() {
    super.initState();
    // Local loading notifies the app-level ListenableBuilder synchronously.
    // Wait until the route has finished building before publishing that update.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) refresh();
    });
  }

  Future<void> refresh() async {
    try {
      await widget.state.loadMemories();
      error = '';
    } catch (e) {
      error = e.toString();
    }
    if (mounted) {
      setState(() => loading = false);
    }
  }

  Future<void> add([Map<String, dynamic>? existing]) async {
    final fact = TextEditingController(text: existing?['fact']);
    String type = existing?['type'] ?? 'preference',
        scope = existing?['conversation'] ?? widget.state.conversation;
    final value = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(
          existing == null ? 'Approve a memory' : 'Edit approved memory',
        ),
        content: SizedBox(
          width: 400,
          child: StatefulBuilder(
            builder: (c, set) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: type,
                  items: [
                    for (final v in [
                      'preference',
                      'project',
                      'approved_summary',
                    ])
                      DropdownMenuItem(value: v, child: Text(v)),
                  ],
                  onChanged: (v) => set(() => type = v!),
                ),
                DropdownButtonFormField<String>(
                  initialValue: scope,
                  items: [
                    DropdownMenuItem(
                      value: widget.state.conversation,
                      child: const Text('This conversation'),
                    ),
                    if (scope != widget.state.conversation && scope != 'all')
                      DropdownMenuItem(value: scope, child: Text(scope)),
                    const DropdownMenuItem(
                      value: 'all',
                      child: Text('All conversations'),
                    ),
                  ],
                  onChanged: (v) => set(() => scope = v!),
                ),
                TextField(
                  controller: fact,
                  maxLength: 1000,
                  minLines: 2,
                  maxLines: 5,
                  decoration: InputDecoration(
                    hintText: 'Exact approved text, not automatic chat capture',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, fact.text.trim()),
            child: const Text('Save this memory'),
          ),
        ],
      ),
    );
    fact.dispose();
    if (value == null || value.isEmpty) {
      return;
    }
    try {
      if (existing == null) {
        await widget.state.remember(value, type: type, scope: scope);
      } else {
        await widget.state.editMemory(
          existing['id'],
          value,
          type: type,
          scope: scope,
        );
      }
      await refresh();
    } catch (e) {
      if (mounted) {
        notice(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Shell(
    title: 'Memory & Library',
    actions: [
      IconButton(
        tooltip: 'Refresh memories',
        onPressed: refresh,
        icon: const Icon(Icons.refresh),
      ),
    ],
    child: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Glass(
          child: Text(
            'Only entries you explicitly approve are kept here on your phone. Chat history is separate. Relevant memory stays local unless you include it in an online send. Memory is data, not permission to act.',
          ),
        ),
        TextButton.icon(
          onPressed: () => Navigator.pushNamed(context, '/library'),
          icon: const Icon(Icons.search),
          label: const Text('Search local conversations & tasks'),
        ),
        TextButton.icon(
          onPressed: () => Home(state: widget.state).notebook(context),
          icon: const Icon(Icons.book_outlined),
          label: const Text('Private local note'),
        ),
        TextButton.icon(
          onPressed: () => Navigator.pushNamed(context, '/files'),
          icon: const Icon(Icons.description_outlined),
          label: const Text('Open a selected document'),
        ),
        FilledButton.icon(
          onPressed: () => add(),
          icon: const Icon(Icons.add),
          label: const Text('Save a fact'),
        ),
        const SizedBox(height: 16),
        if (loading) const LinearProgressIndicator(),
        if (error.isNotEmpty) Text(error),
        for (final memory in widget.state.memories)
          Glass(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  memory['conversation'],
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                const SizedBox(height: 8),
                SelectableText(memory['fact']),
                TextButton(
                  onPressed: () => add(memory),
                  child: const Text('Edit memory'),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () async {
                      final yes = await showDialog<bool>(
                        context: context,
                        builder: (c) => AlertDialog(
                          title: const Text('Forget this fact?'),
                          content: Text(memory['fact']),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(c, false),
                              child: const Text('Keep'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(c, true),
                              child: const Text('Forget'),
                            ),
                          ],
                        ),
                      );
                      if (yes == true) {
                        try {
                          await widget.state.forget(memory['id']);
                          await refresh();
                        } catch (e) {
                          if (context.mounted) {
                            notice(context, e);
                          }
                        }
                      }
                    },
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Forget'),
                  ),
                ),
              ],
            ),
          ),
        if (!loading && error.isEmpty && widget.state.memories.isEmpty)
          const Glass(
            child: Text('Nothing saved yet. You decide what belongs here.'),
          ),
        TextButton.icon(
          onPressed: () async {
            try {
              final json = await widget.state.exportMemories();
              await AssistantState.device.invokeMethod('export', {
                'text': json,
              });
            } catch (e) {
              if (context.mounted) {
                notice(context, e);
              }
            }
          },
          icon: const Icon(Icons.file_download_outlined),
          label: const Text('Export saved memories as JSON'),
        ),
      ],
    ),
  );
}
