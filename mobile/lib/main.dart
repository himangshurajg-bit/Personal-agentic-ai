import 'dart:async';
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

class AssistantApp extends StatefulWidget {
  final AssistantState state;
  const AssistantApp({super.key, required this.state});

  @override
  State<AssistantApp> createState() => _AssistantAppState();
}

class _AssistantAppState extends State<AssistantApp>
    with WidgetsBindingObserver {
  bool _leftForeground = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _leftForeground = true;
      widget.state.lockApp();
    } else if (_leftForeground) {
      _leftForeground = false;
      widget.state.lockApp();
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.state,
    builder: (context, _) => MaterialApp(
      title: widget.state.assistantName,
      debugShowCheckedModeBanner: false,
      theme: _assistantTheme(Brightness.light),
      darkTheme: _assistantTheme(Brightness.dark),
      themeMode: widget.state.theme == 'dark'
          ? ThemeMode.dark
          : widget.state.theme == 'light'
          ? ThemeMode.light
          : ThemeMode.system,
      builder: (context, child) => _AppLockGate(
        state: widget.state,
        child: child ?? const SizedBox.shrink(),
      ),
      home: !widget.state.ready
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : widget.state.onboarded
          ? Home(state: widget.state)
          : Onboarding(state: widget.state),
      routes: {
        '/home': (_) => Home(state: widget.state),
        '/chat': (_) => ChatScreen(state: widget.state),
        '/settings': (_) => Settings(state: widget.state),
        '/memory': (_) => Memories(state: widget.state),
        '/library': (_) => PhoneLibrary(state: widget.state),
        '/study': (_) => StudyScreen(state: widget.state),
        '/files': (_) => SelectedFiles(state: widget.state),
        '/automations': (_) => ActionHistory(state: widget.state),
      },
    ),
  );
}

ThemeData _assistantTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: brightness == Brightness.dark
        ? const Color(0xffb8c8ff)
        : const Color(0xff536fbd),
    brightness: brightness,
  );
  final outline = scheme.outlineVariant.withValues(alpha: .62);
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: brightness == Brightness.dark
        ? const Color(0xff101522)
        : const Color(0xfff4f6fb),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surface.withValues(alpha: .64),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: scheme.primary, width: 1.7),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(17),
          side: BorderSide(color: scheme.primary.withValues(alpha: .34)),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        side: BorderSide(color: scheme.outline.withValues(alpha: .56)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
      ),
    ),
  );
}

class _AppLockGate extends StatelessWidget {
  final AssistantState state;
  final Widget child;
  const _AppLockGate({required this.state, required this.child});

  @override
  Widget build(BuildContext context) {
    final blocked = state.appLockGateVisible;
    return Stack(
      fit: StackFit.expand,
      children: [
        Offstage(
          offstage: blocked,
          child: ExcludeSemantics(
            excluding: blocked,
            child: IgnorePointer(ignoring: blocked, child: child),
          ),
        ),
        if (blocked) _LockScreen(state: state),
      ],
    );
  }
}

class _LockScreen extends StatefulWidget {
  final AssistantState state;
  const _LockScreen({required this.state});

  @override
  State<_LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<_LockScreen> {
  String message = '';

  Future<void> _unlock() async {
    setState(() => message = '');
    final ok = await widget.state.unlockApp();
    if (!mounted) return;
    if (!ok && widget.state.appLockConfigurationReady) {
      setState(
        () => message = 'Authentication was cancelled or unavailable. Your app stays locked.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final canUnlock = widget.state.appLockConfigurationReady;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline, size: 56),
                const SizedBox(height: 20),
                Text(
                  canUnlock
                      ? 'Your assistant is locked'
                      : 'Secure settings unavailable',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Text(
                  canUnlock
                      ? 'Unlock with your phone’s biometric or screen lock.'
                      : 'App content is hidden until secure settings can be read.',
                  textAlign: TextAlign.center,
                ),
                if (message.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(message, textAlign: TextAlign.center),
                ],
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: widget.state.appLockBusy
                      ? null
                      : canUnlock
                      ? _unlock
                      : widget.state.retryInitialization,
                  icon: widget.state.appLockBusy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(canUnlock ? Icons.fingerprint : Icons.refresh),
                  label: Text(
                    widget.state.appLockBusy
                        ? 'Checking…'
                        : canUnlock
                        ? 'Unlock'
                        : 'Try again',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
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
        : _GlassDock(
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
            onSelected: (i) {
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
              : const [Color(0xffe5ebff), Color(0xfff7f8fc), Color(0xffe9e8ff)],
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

class _GlassDock extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  const _GlassDock({required this.selectedIndex, required this.onSelected});

  static const _items = [
    (Icons.home_rounded, 'Home'),
    (Icons.chat_bubble_rounded, 'Chat'),
    (Icons.bolt_rounded, 'Actions'),
    (Icons.auto_stories_rounded, 'Library'),
    (Icons.tune_rounded, 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 5, 12, 9),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 6),
              decoration: BoxDecoration(
                color: scheme.surface.withValues(alpha: .77),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: scheme.onSurface.withValues(alpha: .15),
                ),
                boxShadow: [
                  BoxShadow(
                    color: scheme.primary.withValues(alpha: .10),
                    blurRadius: 26,
                    spreadRadius: -8,
                  ),
                ],
              ),
              child: Row(
                children: [
                  for (var i = 0; i < _items.length; i++)
                    Expanded(
                      child: Semantics(
                        button: true,
                        selected: i == selectedIndex,
                        label: _items[i].$2,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(22),
                            splashColor: scheme.primary.withValues(alpha: .16),
                            highlightColor: scheme.primary.withValues(
                              alpha: .09,
                            ),
                            onTap: () => onSelected(i),
                            child: AnimatedContainer(
                              duration: Duration(
                                milliseconds: reduceMotion ? 0 : 180,
                              ),
                              constraints: const BoxConstraints(minHeight: 50),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 2,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: i == selectedIndex
                                    ? scheme.primary.withValues(alpha: .14)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(22),
                                border: Border.all(
                                  color: i == selectedIndex
                                      ? scheme.primary.withValues(alpha: .28)
                                      : Colors.transparent,
                                ),
                                boxShadow: i == selectedIndex
                                    ? [
                                        BoxShadow(
                                          color: scheme.primary.withValues(
                                            alpha: .14,
                                          ),
                                          blurRadius: 14,
                                          spreadRadius: -4,
                                        ),
                                      ]
                                    : const [],
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _items[i].$1,
                                    size: 20,
                                    color: i == selectedIndex
                                        ? scheme.primary
                                        : scheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _items[i].$2,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color: i == selectedIndex
                                              ? scheme.primary
                                              : scheme.onSurfaceVariant,
                                          fontWeight: i == selectedIndex
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
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
            color: Theme.of(context).colorScheme.surface.withValues(alpha: .68),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Theme.of(context).colorScheme.onSurface
                  .withValues(alpha: .13),
            ),
            boxShadow: [
              BoxShadow(
                color: Theme.of(context).colorScheme.primary
                    .withValues(alpha: .07),
                blurRadius: 24,
                spreadRadius: -7,
                offset: const Offset(0, 8),
              ),
            ],
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
  static const audioEvents = MethodChannel('personal_assistant/audio');
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
    audioEvents.setMethodCallHandler((call) async {
      if (!mounted || call.method != 'audio_event') return;
      final event = Map<String, dynamic>.from(call.arguments);
      if (event['kind'] == 'completed' || event['kind'] == 'error') {
        if (mounted) setState(() => speaking = false);
        if (event['kind'] == 'error' && mounted) {
          notice(
            context,
            'Expressive voice playback stopped; the reply remains readable.',
          );
        }
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      AssistantState.device.invokeMethod('voice_cancel');
      tts.stop();
      if (speaking) unawaited(stopExpressiveAudio());
      widget.state.stop();
      if (mounted) {
        setState(() {
          listening = false;
          speaking = false;
        });
      }
    }
  }

  Future<void> stopExpressiveAudio() async {
    try {
      await audioEvents.invokeMethod('stop_audio');
    } on MissingPluginException {
      // Platforms without the Android playback channel keep other chat controls usable.
    } on PlatformException {
      // Stopping optional audio must not block microphone or typed chat.
    }
  }

  Future<void> stopAll() async {
    widget.state.stop();
    await AssistantState.device.invokeMethod('voice_cancel');
    await tts.stop();
    if (speaking) await stopExpressiveAudio();
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

  Future<void> playExpressiveVoice(String text) async {
    if (speaking) {
      await stopAll();
      return;
    }
    var style = 'neutral';
    final approved =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => StatefulBuilder(
            builder: (dialogContext, setDialogState) => AlertDialog(
              title: const Text('Generate expressive voice?'),
              scrollable: true,
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'This sends the selected reply text to your private service and then to ElevenLabs. ElevenLabs retains text and generated-audio history by default. Avoid sending private text unless you accept this retention. Zero Retention is available only to some Enterprise accounts. It can use credits from the account configured on that service. Nothing is generated until you confirm here.',
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: style,
                    decoration: const InputDecoration(labelText: 'Expression'),
                    items: const [
                      DropdownMenuItem(
                        value: 'neutral',
                        child: Text('Natural'),
                      ),
                      DropdownMenuItem(
                        value: 'curious',
                        child: Text('Curious'),
                      ),
                      DropdownMenuItem(value: 'crying', child: Text('Crying')),
                      DropdownMenuItem(
                        value: 'mischievous',
                        child: Text('Mischievous'),
                      ),
                      DropdownMenuItem(
                        value: 'whispering',
                        child: Text('Whispering'),
                      ),
                      DropdownMenuItem(
                        value: 'shouting',
                        child: Text('Shouting'),
                      ),
                      DropdownMenuItem(
                        value: 'laughing',
                        child: Text('Laughing'),
                      ),
                      DropdownMenuItem(
                        value: 'sighing',
                        child: Text('Sighing'),
                      ),
                    ],
                    onChanged: (value) =>
                        setDialogState(() => style = value ?? 'neutral'),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'These documented audio tags guide delivery; they cannot guarantee every emotion or a particular performance.',
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Generate once'),
                ),
              ],
            ),
          ),
        ) ??
        false;
    if (!approved || !mounted) return;
    setState(() => speaking = true);
    try {
      final audio = await widget.state.synthesizeElevenLabs(text, style);
      await audioEvents.invokeMethod('play_audio', {'bytes': audio});
    } catch (e) {
      if (mounted) {
        setState(() => speaking = false);
        if (e is! PlatformException || e.code != 'cancelled') {
          notice(context, e);
        }
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
    if (speaking) await stopExpressiveAudio();
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
    audioEvents.setMethodCallHandler(null);
    if (speaking) unawaited(stopExpressiveAudio());
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
                              if (m['state'] == 'complete' &&
                                  m['role'] == 'assistant')
                                TextButton.icon(
                                  onPressed: () =>
                                      playExpressiveVoice(m['text'] as String),
                                  icon: Icon(
                                    speaking
                                        ? Icons.stop_circle_outlined
                                        : Icons.record_voice_over,
                                  ),
                                  label: Text(
                                    speaking
                                        ? 'Stop voice'
                                        : 'Play expressive voice',
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
  late final serviceUrl = TextEditingController(
    text: widget.state.privateServiceEndpoint,
  );
  late final compatibleUrl = TextEditingController(
    text: widget.state.compatibleApiEndpoint,
  );
  final serviceSecret = TextEditingController();
  final compatibleSecret = TextEditingController();
  late String speechMode = widget.state.speechMode;
  late String theme = widget.state.theme;
  late String engine = widget.state.engine, language = widget.state.language;
  late final model = TextEditingController(text: widget.state.model);
  late final name = TextEditingController(text: widget.state.assistantName);
  @override
  void initState() {
    super.initState();
    widget.state.addListener(_stateChanged);
  }

  void _stateChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.state.removeListener(_stateChanged);
    serviceUrl.dispose();
    compatibleUrl.dispose();
    serviceSecret.dispose();
    compatibleSecret.dispose();
    model.dispose();
    name.dispose();
    super.dispose();
  }

  Future<void> _clearCredential({required bool compatible}) async {
    final label = compatible ? 'API key' : 'private service token';
    final remove =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Clear $label?'),
            content: const Text(
              'This removes the saved credential from this phone. It does not revoke it at the provider.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Keep'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Clear'),
              ),
            ],
          ),
        ) ??
        false;
    if (!remove || !mounted) return;
    await widget.state.clearProviderCredential(compatible: compatible);
    if (mounted) notice(context, '$label cleared from this phone.');
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
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: widget.state.appLockEnabled,
            onChanged: widget.state.appLockBusy
                ? null
                : (enabled) async {
                    final saved = await widget.state.setAppLockEnabled(enabled);
                    if (!context.mounted) return;
                    if (saved) {
                      notice(
                        context,
                        enabled ? 'App lock enabled.' : 'App lock disabled.',
                      );
                    } else {
                      notice(
                        context,
                        'Device authentication did not succeed. App lock was not changed.',
                      );
                    }
                  },
            secondary: const Icon(Icons.lock_outline),
            title: const Text('App lock'),
            subtitle: const Text(
              'Require your phone’s biometric or screen lock when opening or returning to the app.',
            ),
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
                onChanged: (v) => setState(() => engine = v!),
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
              const Text(
                'ElevenLabs expressive voice is on-demand per reply. It sends only that reply through your private service; each play asks first and may use your account credits. The ElevenLabs key and voice ID must be configured on the service host and are never stored in this APK. Audio tags guide delivery but do not guarantee an emotion. No provider key is bundled. Offline never falls back online.',
              ),
              const SizedBox(height: 12),
              const Text(
                'Online providers may retain submitted content and charge your account. Configure only your own authorized service. Offline never falls back online.',
              ),
              if (engine == 'compatible') ...[
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('OpenAI-compatible API'),
                ),
                TextField(
                  controller: compatibleUrl,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'HTTPS API origin',
                    hintText: 'https://api.example.com',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: model,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    labelText: 'Model ID',
                    hintText: 'Use the exact model name from your provider',
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'API key: ${widget.state.compatibleApiKey.isEmpty ? 'Not set' : 'Saved securely on this phone'}',
                ),
                TextField(
                  controller: compatibleSecret,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  autofillHints: const [],
                  decoration: const InputDecoration(
                    labelText: 'API key',
                    hintText: 'Enter a new key to replace the saved key',
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Keys are kept in Android secure storage, are not shown again, and are sent only as authentication when you approve an online request. Leave blank to keep the saved key.',
                ),
                if (widget.state.compatibleApiKey.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => _clearCredential(compatible: true),
                      icon: const Icon(Icons.key_off),
                      label: const Text('Clear API key'),
                    ),
                  ),
              ] else if (engine == 'private_service') ...[
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Private FastAPI service'),
                ),
                TextField(
                  controller: serviceUrl,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Service origin',
                    hintText: 'https://your-private-service.example',
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Service token: ${widget.state.privateServiceToken.isEmpty ? 'Not set' : 'Saved securely on this phone'}',
                ),
                TextField(
                  controller: serviceSecret,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  autofillHints: const [],
                  decoration: const InputDecoration(
                    labelText: 'Private service token',
                    hintText: 'Enter a new token to replace the saved token',
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Leave blank to keep the saved token. The service remains separate from public provider credentials.',
                ),
                if (widget.state.privateServiceToken.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => _clearCredential(compatible: false),
                      icon: const Icon(Icons.key_off),
                      label: const Text('Clear service token'),
                    ),
                  ),
              ] else
                const Text(
                  'Offline AI is unavailable: no model is installed. No online fallback will be used.',
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
                      serviceUrl.text,
                      serviceSecret.text,
                      theme,
                      compatibleUrl: compatibleUrl.text,
                      compatibleSecret: compatibleSecret.text,
                    );
                    serviceSecret.clear();
                    compatibleSecret.clear();
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
              if (engine == 'private_service')
                TextButton(
                  onPressed: () async {
                    try {
                      final result = await widget.state.request(
                        'GET',
                        '/health',
                      );
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
            'Privacy & permissions\n\nOptional app lock uses Android device authentication (biometrics or screen lock where supported). No PIN or authentication secret is created or stored. The lock is checked when enabled and gates the app on launch and return from the background.\n\nMicrophone access is requested only when starting voice input. Notification permission is requested when scheduling your first reminder. Neither is needed for typed chat. Android speech providers may send audio to their service. There is no background microphone or wake phrase.\n\nReminders use approximate alarms and are lost if this private test app is removed. Battery settings can delay them.',
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
