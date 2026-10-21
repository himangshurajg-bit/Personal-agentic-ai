import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'assistant_state.dart';

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
      title: 'Personal assistant',
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
      },
    ),
  );
}

class Shell extends StatelessWidget {
  final String title;
  final Widget child;
  final List<Widget>? actions;
  const Shell({
    super.key,
    required this.title,
    required this.child,
    this.actions,
  });
  @override
  Widget build(BuildContext context) => Scaffold(
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
    title: 'Personal assistant',
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
                'Chat with your own AI service, keep chosen memories, and prepare small actions. AI needs a configured model; there are no pretend replies.',
              ),
            ],
          ),
        ),
        const Glass(
          child: Text(
            'Voice starts only when you tap the microphone. Android speech recognition may use its provider’s network service. You can always type instead. Reminders ask for notification permission only when needed. No always-listening mode.',
          ),
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
      final draft = await state.request('POST', '/actions/prepare', {
        'action': action,
      });
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
      // Single use: if approval reply is lost, do not execute or automatically retry.
      final admitted = await state.request(
        'POST',
        '/actions/${draft['id']}/approve',
        {'token': draft['approval_token']},
      );
      Map result;
      try {
        result =
            await AssistantState.device.invokeMapMethod(
              'execute',
              Map<String, dynamic>.from(admitted['action']),
            ) ??
            {
              'result': 'unknown',
              'detail': 'No device result; do not repeat blindly.',
            };
      } catch (_) {
        result = {
          'result': 'unknown',
          'detail':
              'Device action could not be verified. Do not repeat blindly.',
        };
      }
      String report = result['detail'].toString();
      try {
        await state.request('POST', '/actions/${draft['id']}/receipt', {
          'result': result['result'],
          'detail': report,
        });
      } catch (_) {
        report += ' The service did not receive the result; do not repeat the action blindly.';
      }
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
    title: 'Your space',
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
              const Icon(Icons.auto_awesome_outlined, size: 36),
              const SizedBox(height: 16),
              Text(
                'What’s on your mind?',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                state.token.isEmpty
                    ? 'Connect your private AI service in Settings. Your offline notebook is ready now.'
                    : 'Chat uses your configured private service. Only explicitly saved facts become memories.',
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
                subtitle: const Text('Inspect, save, export or forget'),
                onTap: () => Navigator.pushNamed(context, '/memory'),
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
  final speech = SpeechToText();
  final tts = FlutterTts();
  bool listening = false, speaking = false;
  double level = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.state.loadHistory();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      speech.cancel();
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
    await speech.cancel();
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
      await speech.stop();
      if (mounted) {
        setState(() => listening = false);
      }
      return;
    }
    await stopAll();
    try {
      final available = await speech.initialize(
        onError: (error) {
          if (mounted) {
            setState(() => listening = false);
            notice(
              context,
              'Voice is unavailable or permission was denied. You can type instead.',
            );
          }
        },
        onStatus: (status) {
          if (mounted && (status == 'done' || status == 'notListening')) {
            setState(() => listening = false);
          }
        },
      );
      if (!available) {
        if (mounted) {
          notice(
            context,
            'No speech recognizer or microphone permission. Typing still works.',
          );
        }
        return;
      }
      if (mounted) {
        setState(() => listening = true);
      }
      await speech.listen(
        onResult: (r) {
          input.text = r.recognizedWords;
        },
        onSoundLevelChange: (l) {
          if (mounted) {
            setState(() => level = l);
          }
        },
        listenOptions: SpeechListenOptions(
          listenFor: const Duration(seconds: 45),
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(() => listening = false);
        notice(context, 'Voice could not start. Type your message instead.');
      }
    }
  }

  Future<void> send([String? retry]) async {
    final text = retry ?? input.text;
    if (text.trim().isEmpty) {
      return;
    }
    await speech.stop();
    await tts.stop();
    if (mounted) {
      setState(() => listening = false);
    }
    input.clear();
    await widget.state.send(text);
    if (widget.state.speakReplies &&
        widget.state.error.isEmpty &&
        widget.state.messages.isNotEmpty &&
        mounted) {
      final last = widget.state.messages.last;
      if (last['role'] == 'assistant' && last['state'] == 'complete') {
        try {
          setState(() => speaking = true);
          await tts.awaitSpeakCompletion(true);
          await tts.speak(last['text']);
        } catch (_) {
          if (mounted) {
            notice(
              context,
              'Speech playback unavailable. The reply remains readable.',
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
    speech.cancel();
    tts.stop();
    widget.state.stop();
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.state,
    builder: (context, _) {
      final state = widget.state;
      return Shell(
        title: 'Conversation',
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
                      final rows = List<Map<String, dynamic>>.from(
                        await state.request('GET', '/conversations'),
                      );
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
                        await speech.stop();
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
                      await speech.stop();
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
                'Model replies need your service. Voice is tap-to-start; recognized words stay editable. Memory scope: ${state.conversation}',
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
                                m['role'] == 'user' ? 'YOU' : 'ASSISTANT',
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                              const SizedBox(height: 6),
                              SelectableText(m['text'] as String),
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
          (level.abs().clamp(0, 20) / 20) *
              20 *
              (.3 + .7 * math.sin(i * .8).abs());
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
  late String theme = widget.state.theme;
  @override
  void dispose() {
    url.dispose();
    token.dispose();
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
            'Private service connection\n\nRun the FastAPI service on your computer. Use USB port forwarding for plain loopback HTTP, or trusted HTTPS. No provider keys are embedded in the app. A local model is configured on the service, not here.',
          ),
        ),
        Glass(
          child: Column(
            children: [
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
                  labelText: 'Private service token',
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
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
                child: const Text('Test saved connection'),
              ),
            ],
          ),
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
                  'Delete service history for ${widget.state.conversation}. Saved memories remain until you forget them separately.',
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
                await widget.state.request(
                  'DELETE',
                  '/conversations/${widget.state.conversation}',
                );
                widget.state.messages = [];
                if (context.mounted) {
                  notice(context, 'Current service history deleted.');
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
    refresh();
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

  Future<void> add() async {
    final fact = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Save a fact'),
        content: TextField(
          controller: fact,
          maxLength: 1000,
          minLines: 2,
          maxLines: 5,
          decoration: InputDecoration(
            hintText: 'A fact to use in ${widget.state.conversation}',
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
      await widget.state.remember(value);
      await refresh();
    } catch (e) {
      if (mounted) {
        notice(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Shell(
    title: 'Chosen memories',
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
            'Only facts you explicitly save appear here. The service retrieves a small relevant subset from the current conversation, not your entire memory list. Memory text is data, not permission to act.',
          ),
        ),
        FilledButton.icon(
          onPressed: add,
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
