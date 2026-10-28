import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'package:record/record.dart';
import 'package:flutter/services.dart';

import 'app_update.dart';
import 'assistant_state.dart';
import 'local_backup_restore.dart';
import 'jee_question_request.dart';
import 'assistant_task_tracker.dart';
import 'mcp_servers.dart';
import 'wajo_oauth.dart';
import 'offline_model.dart';
import 'offline_voice.dart';
import 'phone_screens.dart';
import 'safe_workflows.dart';
import 'image_generation_screen.dart';
import 'assistant_features_screen.dart';
import 'download_input.dart';
import 'download_review.dart';
import 'spoken_download_command.dart';
import 'feature_services.dart';
import 'ui_motion.dart';
import 'typing_indicator.dart';
import 'visual_theme.dart';
import 'voice_services.dart';
import 'live_conversation.dart';
import 'readable_math.dart';

import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';

const MethodChannel _assistantAudioChannel = MethodChannel(
  'personal_assistant/audio',
);
const MethodChannel _assistantWebSearchChannel = MethodChannel(
  'personal_assistant/web_search',
);
final ValueNotifier<bool> _assistantAudioPlaying = ValueNotifier(false);
final GlobalKey<NavigatorState> _assistantNavigatorKey =
    GlobalKey<NavigatorState>();
const MethodChannel _assistantTaskChannel = MethodChannel(
  MethodChannelAssistantTaskNotificationPort.channelName,
);

Future<void> _playAssistantAudio(Object bytes) async {
  _assistantAudioPlaying.value = true;
  try {
    await _assistantAudioChannel.invokeMethod('play_audio', {'bytes': bytes});
  } catch (_) {
    _assistantAudioPlaying.value = false;
    rethrow;
  }
}

Future<void> _stopAssistantAudio() async {
  try {
    await _assistantAudioChannel.invokeMethod('stop_audio');
  } finally {
    _assistantAudioPlaying.value = false;
  }
}

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
  bool _pendingTaskVoiceCommand = false;

  void _assistantStateChanged() {
    if (_pendingTaskVoiceCommand && widget.state.ready) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _openTaskVoiceCommand(),
      );
    }
  }

  void _queueTaskVoiceCommand() {
    _pendingTaskVoiceCommand = true;
    _openTaskVoiceCommand();
  }

  void _openTaskVoiceCommand() {
    if (!mounted || !_pendingTaskVoiceCommand || !widget.state.ready) return;
    final navigator = _assistantNavigatorKey.currentState;
    if (navigator == null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _openTaskVoiceCommand(),
      );
      return;
    }
    _pendingTaskVoiceCommand = false;
    navigator.pushNamed(
      taskVoiceEntryRoute(
        ready: widget.state.ready,
        locked: widget.state.appLocked,
      ),
    );
  }

  Future<void> _consumeTaskVoiceCommand() async {
    try {
      final requested = await _assistantTaskChannel.invokeMethod<bool>(
        'consume_voice_command_request',
      );
      if (requested == true) _queueTaskVoiceCommand();
    } on PlatformException {
      // Older builds and notification permission failures keep ordinary chat usable.
    } on MissingPluginException {
      // The Android notification bridge is optional on non-Android platforms.
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.state.addListener(_assistantStateChanged);
    _assistantTaskChannel.setMethodCallHandler((call) async {
      if (call.method == 'voice_command_requested') {
        _queueTaskVoiceCommand();
        return true;
      }
      return null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_consumeTaskVoiceCommand());
    });
    _assistantAudioChannel.setMethodCallHandler((call) async {
      if (call.method != 'audio_event') return;
      final event = Map<String, dynamic>.from(call.arguments);
      if (event['kind'] == 'completed' || event['kind'] == 'error') {
        _assistantAudioPlaying.value = false;
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.state.removeListener(_assistantStateChanged);
    _assistantTaskChannel.setMethodCallHandler(null);
    _assistantAudioChannel.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Device-auth prompts can temporarily take focus without sending the app to
    // the background. Lock only after the app is actually hidden or paused.
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      _leftForeground = true;
      widget.state.lockApp();
    } else if (state == AppLifecycleState.resumed && _leftForeground) {
      _leftForeground = false;
      widget.state.lockApp();
    }
  }

  @override
  void didChangeAccessibilityFeatures() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = WidgetsBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations;
    return ListenableBuilder(
      listenable: widget.state,
      builder: (context, _) => MaterialApp(
        title: widget.state.assistantName,
        debugShowCheckedModeBanner: false,
        theme: _assistantTheme(
          Brightness.light,
          widget.state.visualTheme,
          reduceMotion: reduceMotion,
        ),
        darkTheme: _assistantTheme(
          Brightness.dark,
          widget.state.visualTheme,
          reduceMotion: reduceMotion,
        ),
        themeAnimationDuration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 520),
        themeAnimationCurve: Curves.easeInOutCubic,
        themeMode: widget.state.theme == 'dark'
            ? ThemeMode.dark
            : widget.state.theme == 'light'
            ? ThemeMode.light
            : ThemeMode.system,
        navigatorKey: _assistantNavigatorKey,
        builder: (context, child) => _AppLockGate(
          state: widget.state,
          child: child ?? const SizedBox.shrink(),
        ),
        home: !widget.state.ready
            ? WelcomeSplash(assistantName: widget.state.assistantName)
            : widget.state.onboarded
            ? Home(state: widget.state)
            : Onboarding(state: widget.state),
        routes: {
          '/home': (_) => Home(state: widget.state),
          '/features': (context) => FeaturesScreen(
            state: widget.state,
            onReminder: (context, title) =>
                Home(state: widget.state)
                    .reminder(context, initialTitle: title),
          ),
          '/features/research': (context) => FeaturesScreen(
            state: widget.state,
            initialTab: 2,
            onReminder: (context, title) =>
                Home(state: widget.state)
                    .reminder(context, initialTitle: title),
          ),
          '/chat': (context) {
            final draft = ModalRoute.of(context)?.settings.arguments;
            return ChatScreen(
              state: widget.state,
              initialDraft: draft is String ? draft : null,
            );
          },
          '/voice': (_) =>
              ChatScreen(state: widget.state, startWithVoice: true),
          '/task-voice': (_) =>
              ChatScreen(state: widget.state, startWithVoiceCommand: true),
          '/settings': (_) => Settings(state: widget.state),
          '/connections': (_) => ApiMcpSettings(state: widget.state),
          '/memory': (_) => Memories(state: widget.state),
          '/library': (_) => PhoneLibrary(state: widget.state),
          '/study': (_) => StudyScreen(state: widget.state),
          '/whiteboard': (context) {
            final lessonId = ModalRoute.of(context)?.settings.arguments;
            return StudyWhiteboardScreen(
              state: widget.state,
              lessonId: lessonId is String ? lessonId : null,
            );
          },
          '/files': (_) => SelectedFiles(state: widget.state),
          '/automations': (_) => ActionHistory(state: widget.state),
          '/drafts': (_) => const OutboundDraftsScreen(),
          '/skills': (_) => SafeSkillsScreen(state: widget.state),
          '/images': (_) => ImageGenerationScreen(
            endpoint: widget.state.endpoint,
            token: widget.state.token,
          ),
        },
      ),
    );
  }
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
  final String? assistantName;
  final Widget child;
  final List<Widget>? actions;
  final bool primaryNavigation;
  final bool showBottomNavigation;
  final double contentMaxWidth;
  const Shell({
    super.key,
    required this.title,
    required this.child,
    this.assistantName,
    this.actions,
    this.primaryNavigation = true,
    this.showBottomNavigation = true,
    this.contentMaxWidth = 700,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final route = ModalRoute.of(context);
    final currentRoute = route?.settings.name;
    final canPop = route?.canPop ?? false;
    return Scaffold(
      extendBody: true,
      drawer: primaryNavigation
          ? _AssistantDrawer(
              assistantName: assistantName ?? title,
              currentRoute: currentRoute,
            )
          : null,
      drawerScrimColor: theme.colorScheme.scrim.withValues(alpha: .34),
      drawerEnableOpenDragGesture: primaryNavigation,
      drawerEdgeDragWidth: primaryNavigation ? 40 : null,
      bottomNavigationBar: primaryNavigation && showBottomNavigation
          ? _AssistantDock(currentRoute: currentRoute)
          : null,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leadingWidth: 58,
        leading: !primaryNavigation
            ? null
            : canPop
            ? IconButton(
                tooltip: 'Back',
                onPressed: () => Navigator.maybePop(context),
                icon: const Icon(Icons.arrow_back_rounded),
              )
            : Builder(
                builder: (drawerContext) => IconButton(
                  tooltip: 'Open navigation menu',
                  onPressed: () => Scaffold.of(drawerContext).openDrawer(),
                  icon: const Icon(Icons.menu_rounded),
                ),
              ),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: actions,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        titleSpacing: 8,
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: dark
                    ? const [
                        Color(0xff101322),
                        Color(0xff151b2b),
                        Color(0xff101a20),
                      ]
                    : const [
                        Color(0xffe8edff),
                        Color(0xfff8f7fc),
                        Color(0xffe6f4f1),
                      ],
              ),
            ),
          ),
          const Positioned.fill(child: _AmbientGlow()),
          SafeArea(
            top: false,
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: contentMaxWidth),
                child: child,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class WelcomeSplash extends StatefulWidget {
  final String assistantName;
  const WelcomeSplash({super.key, required this.assistantName});

  @override
  State<WelcomeSplash> createState() => _WelcomeSplashState();
}

class _WelcomeSplashState extends State<WelcomeSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _float = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 8),
  );
  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion == _reduceMotion && (_float.isAnimating || reduceMotion)) {
      return;
    }
    _reduceMotion = reduceMotion;
    if (reduceMotion) {
      _float.stop();
    } else {
      _float.repeat();
    }
  }

  @override
  void dispose() {
    _float.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: AnimatedBuilder(
      animation: _float,
      builder: (context, _) {
        final phase = _reduceMotion ? 0.0 : _float.value * math.pi * 2;
        return Stack(
          fit: StackFit.expand,
          children: [
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xff070b25),
                    Color(0xff171543),
                    Color(0xff351a62),
                  ],
                ),
              ),
            ),
            Positioned(
              left: -70,
              top: 80 + math.sin(phase) * 18,
              child: _SplashGlow(
                size: 210,
                color: const Color(0xff4c83f2).withValues(alpha: .20),
              ),
            ),
            Positioned(
              right: -84,
              bottom: 120 + math.cos(phase * .7) * 22,
              child: _SplashGlow(
                size: 260,
                color: const Color(0xffbb7bff).withValues(alpha: .20),
              ),
            ),
            Positioned(
              right: 60,
              top: 125 + math.cos(phase * 1.15) * 14,
              child: _SplashDot(color: const Color(0xff9bd6ff), size: 7),
            ),
            Positioned(
              left: 48,
              bottom: 230 + math.sin(phase * .82) * 12,
              child: _SplashDot(color: const Color(0xffd5b5ff), size: 5),
            ),
            SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 36),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 112,
                          height: 112,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Color(0xff7bdcff),
                                Color(0xff9172f4),
                                Color(0xffd292ff),
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xff987cff)
                                    .withValues(alpha: .42),
                                blurRadius: 42,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.auto_awesome_rounded,
                            size: 48,
                            color: Color(0xff101333),
                          ),
                        ),
                        const SizedBox(height: 28),
                        Text(
                          widget.assistantName,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -.8,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'A little room to think.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(
                                color: Colors.white.withValues(alpha: .72),
                              ),
                        ),
                        const SizedBox(height: 34),
                        const ClipRRect(
                          borderRadius: BorderRadius.all(Radius.circular(8)),
                          child: LinearProgressIndicator(
                            minHeight: 4,
                            backgroundColor: Color(0x337c9cff),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Color(0xffa8c7ff),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Preparing your private space',
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: Colors.white.withValues(alpha: .58),
                                letterSpacing: .2,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}

class _SplashGlow extends StatelessWidget {
  final double size;
  final Color color;
  const _SplashGlow({required this.size, required this.color});

  @override
  Widget build(BuildContext context) => ImageFiltered(
    imageFilter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    ),
  );
}

class _SplashDot extends StatelessWidget {
  final Color color;
  final double size;
  const _SplashDot({required this.color, required this.size});

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      boxShadow: [
        BoxShadow(color: color.withValues(alpha: .65), blurRadius: 14),
      ],
    ),
  );
}

class _AssistantDrawer extends StatelessWidget {
  final String assistantName;
  final String? currentRoute;
  const _AssistantDrawer({
    required this.assistantName,
    required this.currentRoute,
  });

  bool _selected(String route) {
    if (route == '/home') {
      return currentRoute == null || currentRoute == '/home';
    }
    if (route == '/chat') {
      return currentRoute == '/chat' || currentRoute == '/voice';
    }
    if (route == '/memory') {
      return currentRoute == '/memory' ||
          currentRoute == '/library' ||
          currentRoute == '/files';
    }
    return currentRoute == route;
  }

  void _go(BuildContext context, String route) {
    Navigator.pop(context);
    final currentRoute = ModalRoute.of(context)?.settings.name;
    if (currentRoute != route) Navigator.pushReplacementNamed(context, route);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Drawer(
      width: math.min(MediaQuery.sizeOf(context).width * .86, 360),
      elevation: 0,
      backgroundColor: colors.surface.withValues(alpha: .96),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 18),
              child: Row(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [colors.primary, colors.secondary],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: colors.primary.withValues(alpha: .22),
                          blurRadius: 22,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.auto_awesome_rounded,
                      color: colors.onPrimary,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          assistantName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'YOUR PRIVATE ASSISTANT',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colors.onSurfaceVariant,
                            letterSpacing: .9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Divider(
              color: colors.outlineVariant.withValues(alpha: .5),
              height: 1,
            ),
            Expanded(
              child: ListView(
                key: const Key('navigation-drawer-list'),
                padding: const EdgeInsets.fromLTRB(12, 18, 12, 18),
                children: [
                  const _SettingsSectionLabel('HOME'),
                  _DrawerRow(
                    icon: Icons.home_rounded,
                    label: 'Home',
                    selected: _selected('/home'),
                    onTap: () => _go(context, '/home'),
                  ),
                  const SizedBox(height: 18),
                  const _SettingsSectionLabel('CHAT & STUDY'),
                  _DrawerRow(
                    icon: Icons.chat_bubble_outline_rounded,
                    label: 'Chat',
                    selected: _selected('/chat'),
                    onTap: () => _go(context, '/chat'),
                  ),
                  _DrawerRow(
                    icon: Icons.school_outlined,
                    label: 'Study',
                    selected: _selected('/study'),
                    onTap: () => _go(context, '/study'),
                  ),
                  _DrawerRow(
                    icon: Icons.draw_outlined,
                    label: 'Whiteboard',
                    selected: _selected('/whiteboard'),
                    onTap: () => _go(context, '/whiteboard'),
                  ),
                  const SizedBox(height: 18),
                  const _SettingsSectionLabel('TOOLS'),
                  _DrawerRow(
                    icon: Icons.bolt_rounded,
                    label: 'Actions',
                    selected: _selected('/automations'),
                    onTap: () => _go(context, '/automations'),
                  ),
                  _DrawerRow(
                    icon: Icons.auto_awesome_outlined,
                    label: 'Skills & actions',
                    selected: _selected('/skills'),
                    onTap: () => _go(context, '/skills'),
                  ),
                  _DrawerRow(
                    icon: Icons.edit_note_rounded,
                    label: 'Message & social drafts',
                    selected: _selected('/drafts'),
                    onTap: () => _go(context, '/drafts'),
                  ),
                  _DrawerRow(
                    icon: Icons.image_outlined,
                    label: 'Create image',
                    selected: _selected('/images'),
                    onTap: () => _go(context, '/images'),
                  ),
                  const SizedBox(height: 18),
                  const _SettingsSectionLabel('YOUR LIBRARY'),
                  _DrawerRow(
                    icon: Icons.psychology_alt_outlined,
                    label: 'Memory',
                    selected: _selected('/memory'),
                    onTap: () => _go(context, '/memory'),
                  ),
                  _DrawerRow(
                    icon: Icons.library_books_outlined,
                    label: 'Tasks & history',
                    selected: _selected('/library'),
                    onTap: () => _go(context, '/library'),
                  ),
                  _DrawerRow(
                    icon: Icons.folder_open_outlined,
                    label: 'Selected files',
                    selected: _selected('/files'),
                    onTap: () => _go(context, '/files'),
                  ),
                  const SizedBox(height: 18),
                  const _SettingsSectionLabel('SETTINGS'),
                  _DrawerRow(
                    icon: Icons.tune_rounded,
                    label: 'Settings',
                    selected: _selected('/settings'),
                    onTap: () => _go(context, '/settings'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
              child: Text(
                'A quiet space for your conversations, study and plans.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _DrawerRow({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: TapMotion(
        depth: .28,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onTap,
            child: AnimatedContainer(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: selected
                    ? null
                    : colors.surface.withValues(alpha: dark ? .12 : .18),
                gradient: selected
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          colors.primary.withValues(alpha: .20),
                          colors.secondary.withValues(alpha: .10),
                        ],
                      )
                    : null,
                border: Border.all(
                  color: selected
                      ? colors.primary.withValues(alpha: .48)
                      : colors.outlineVariant.withValues(
                          alpha: dark ? .34 : .48,
                        ),
                ),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: colors.primary.withValues(
                            alpha: dark ? .16 : .09,
                          ),
                          blurRadius: 16,
                          offset: const Offset(0, 5),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                children: [
                  Icon(
                    icon,
                    size: 21,
                    color: selected ? colors.primary : colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      label,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: selected ? colors.primary : colors.onSurface,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                  if (selected)
                    Icon(Icons.chevron_right_rounded, color: colors.primary),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AssistantDock extends StatelessWidget {
  final String? currentRoute;
  const _AssistantDock({required this.currentRoute});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final motionDuration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 360);
    final chat = currentRoute == '/chat';
    final voice = currentRoute == '/voice' || currentRoute == '/task-voice';
    final memory =
        currentRoute == '/memory' ||
        currentRoute == '/library' ||
        currentRoute == '/files';
    final settings =
        currentRoute == '/settings' || currentRoute == '/connections';
    // Secondary screens stay grouped with their parent dock destination.
    // Slot order: Home, Chat, Voice, Memory, Settings.
    final home = !chat && !voice && !memory && !settings;
    final selectionIndex = home
        ? 0
        : chat
        ? 1
        : voice
        ? 2
        : memory
        ? 3
        : 4;
    final dockSelectionAlignment = Alignment(-1 + selectionIndex * .5, 0);
    final dockSelectionTint = home
        ? colors.primary
        : chat
        ? colors.secondary
        : voice
        ? colors.primary
        : memory
        ? colors.tertiary
        : colors.primaryContainer;
    final radius = BorderRadius.circular(28);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: dark ? .25 : .12),
                blurRadius: 24,
                spreadRadius: -5,
                offset: const Offset(0, 10),
              ),
              BoxShadow(
                color: colors.primary.withValues(alpha: dark ? .16 : .11),
                blurRadius: 28,
                spreadRadius: -7,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: BackdropFilter(
              key: const ValueKey('assistant-dock-backdrop'),
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: SizedBox(
                key: const ValueKey('assistant-dock-glass'),
                height: 80,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            colors.surface.withValues(alpha: dark ? .72 : .76),
                            colors.surfaceContainerHighest.withValues(
                              alpha: dark ? .78 : .70,
                            ),
                            colors.surface.withValues(alpha: dark ? .84 : .82),
                          ],
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              stops: const [0, .42, 1],
                              colors: [
                                Colors.white.withValues(
                                  alpha: dark ? .14 : .28,
                                ),
                                colors.primary.withValues(
                                  alpha: dark ? .035 : .025,
                                ),
                                colors.tertiary.withValues(
                                  alpha: dark ? .09 : .055,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: radius,
                            border: Border.all(
                              color: Colors.white.withValues(
                                alpha: dark ? .20 : .72,
                              ),
                              width: 1,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 1,
                      left: 28,
                      right: 28,
                      height: 1.2,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.white.withValues(alpha: 0),
                                Colors.white.withValues(
                                  alpha: dark ? .62 : .88,
                                ),
                                Colors.white.withValues(alpha: 0),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      left: 38,
                      right: 38,
                      height: 12,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [
                                colors.primary.withValues(
                                  alpha: dark ? .13 : .07,
                                ),
                                colors.primary.withValues(alpha: 0),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 5,
                        ),
                        child: AnimatedAlign(
                          key: const ValueKey('dock-liquid-glass'),
                          alignment: dockSelectionAlignment,
                          duration: motionDuration,
                          curve: Curves.easeInOutCubicEmphasized,
                          child: Hero(
                            key: const ValueKey('dock-liquid-glass-hero'),
                            tag: reduceMotion
                                ? 'assistant-dock-liquid-glass-${currentRoute ?? '/home'}'
                                : 'assistant-dock-liquid-glass-selection',
                            child: FractionallySizedBox(
                              widthFactor: .2,
                              heightFactor: 1,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 3,
                                ),
                                child: IgnorePointer(
                                  child: ExcludeSemantics(
                                    child: AnimatedContainer(
                                      key: const ValueKey(
                                        'dock-liquid-glass-surface',
                                      ),
                                      duration: motionDuration,
                                      curve: Curves.easeInOutCubicEmphasized,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(22),
                                        gradient: LinearGradient(
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                          colors: [
                                            Colors.white.withValues(
                                              alpha: dark ? .16 : .34,
                                            ),
                                            dockSelectionTint.withValues(
                                              alpha: dark ? .20 : .11,
                                            ),
                                            colors.surface.withValues(
                                              alpha: dark ? .28 : .25,
                                            ),
                                          ],
                                        ),
                                        border: Border.all(
                                          color: Colors.white.withValues(
                                            alpha: dark ? .34 : .62,
                                          ),
                                          width: 1,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: dockSelectionTint.withValues(
                                              alpha: dark ? .24 : .16,
                                            ),
                                            blurRadius: 14,
                                            spreadRadius: -3,
                                            offset: const Offset(0, 4),
                                          ),
                                          BoxShadow(
                                            color: Colors.white.withValues(
                                              alpha: dark ? .12 : .32,
                                            ),
                                            blurRadius: 6,
                                            spreadRadius: -4,
                                            offset: const Offset(0, -2),
                                          ),
                                        ],
                                      ),
                                      child: Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          Align(
                                            alignment: Alignment.topCenter,
                                            child: FractionallySizedBox(
                                              widthFactor: .66,
                                              heightFactor: .12,
                                              child: DecoratedBox(
                                                decoration: BoxDecoration(
                                                  borderRadius:
                                                      BorderRadius.circular(99),
                                                  gradient: LinearGradient(
                                                    colors: [
                                                      Colors.white.withValues(
                                                        alpha: 0,
                                                      ),
                                                      Colors.white.withValues(
                                                        alpha: dark ? .56 : .84,
                                                      ),
                                                      Colors.white.withValues(
                                                        alpha: 0,
                                                      ),
                                                    ],
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
                            ),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 5,
                      ),
                      child: Row(
                        children: [
                          _DockItem(
                            icon: Icons.home_outlined,
                            selectedIcon: Icons.home_rounded,
                            label: 'Home',
                            selected: home,
                            motionDuration: motionDuration,
                            onTap: () => _navigate(context, '/home'),
                          ),
                          _DockItem(
                            icon: Icons.chat_bubble_outline_rounded,
                            selectedIcon: Icons.chat_bubble_rounded,
                            label: 'Chat',
                            selected: chat,
                            motionDuration: motionDuration,
                            onTap: () => _navigate(context, '/chat'),
                          ),
                          Expanded(
                            child: Semantics(
                              key: const ValueKey('dock-item-voice'),
                              container: true,
                              button: true,
                              label: 'Voice',
                              selected: voice,
                              onTap: () => _navigate(context, '/voice'),
                              child: ExcludeSemantics(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Tooltip(
                                      message: 'Start a voice conversation',
                                      child: TapMotion(
                                        depth: .7,
                                        child: Material(
                                          color: Colors.transparent,
                                          child: InkWell(
                                            customBorder: const CircleBorder(),
                                            onTap: () =>
                                                _navigate(context, '/voice'),
                                            child: AnimatedScale(
                                              key: const ValueKey(
                                                'dock-voice-scale',
                                              ),
                                              scale: voice ? 1.08 : 1,
                                              duration: motionDuration,
                                              curve: Curves.easeOutBack,
                                              child: AnimatedContainer(
                                                duration: motionDuration,
                                                curve: Curves.easeOutCubic,
                                                width: voice ? 51 : 47,
                                                height: voice ? 51 : 47,
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  gradient: LinearGradient(
                                                    begin: Alignment.topLeft,
                                                    end: Alignment.bottomRight,
                                                    colors: [
                                                      Color.alphaBlend(
                                                        Colors.white.withValues(
                                                          alpha: dark
                                                              ? .16
                                                              : .22,
                                                        ),
                                                        colors.primary,
                                                      ),
                                                      colors.secondary,
                                                    ],
                                                  ),
                                                  border: Border.all(
                                                    color: Colors.white
                                                        .withValues(
                                                          alpha: dark
                                                              ? .48
                                                              : .78,
                                                        ),
                                                    width: 1.2,
                                                  ),
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: colors.primary
                                                          .withValues(
                                                            alpha: .32,
                                                          ),
                                                      blurRadius: 17,
                                                      offset: const Offset(
                                                        0,
                                                        5,
                                                      ),
                                                    ),
                                                    BoxShadow(
                                                      color: Colors.white
                                                          .withValues(
                                                            alpha: dark
                                                                ? .10
                                                                : .25,
                                                          ),
                                                      blurRadius: 7,
                                                      spreadRadius: -4,
                                                      offset: const Offset(
                                                        0,
                                                        -2,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                child: Stack(
                                                  alignment: Alignment.center,
                                                  children: [
                                                    Icon(
                                                      Icons.mic_rounded,
                                                      color: colors.onPrimary,
                                                      size: 23,
                                                    ),
                                                    Positioned(
                                                      top: 5,
                                                      child: IgnorePointer(
                                                        child: Container(
                                                          width: 20,
                                                          height: 4,
                                                          decoration: BoxDecoration(
                                                            color: Colors.white
                                                                .withValues(
                                                                  alpha: dark
                                                                      ? .38
                                                                      : .56,
                                                                ),
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  99,
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
                                      ),
                                    ),
                                    const SizedBox(height: 1),
                                    AnimatedDefaultTextStyle(
                                      duration: motionDuration,
                                      curve: Curves.easeOutCubic,
                                      style:
                                          theme.textTheme.labelSmall?.copyWith(
                                            fontSize: 9,
                                            height: 1.1,
                                            fontWeight: voice
                                                ? FontWeight.w700
                                                : FontWeight.w600,
                                            color: voice
                                                ? colors.primary
                                                : colors.onSurfaceVariant,
                                          ) ??
                                          const TextStyle(),
                                      child: const Text('Voice'),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          _DockItem(
                            icon: Icons.psychology_alt_outlined,
                            selectedIcon: Icons.psychology_alt_rounded,
                            label: 'Memory',
                            selected: memory,
                            motionDuration: motionDuration,
                            onTap: () => _navigate(context, '/memory'),
                          ),
                          _DockItem(
                            icon: Icons.tune_rounded,
                            selectedIcon: Icons.tune_rounded,
                            label: 'Settings',
                            selected: settings,
                            motionDuration: motionDuration,
                            onTap: () => _navigate(context, '/settings'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _navigate(BuildContext context, String route) {
    if (ModalRoute.of(context)?.settings.name != route) {
      if (route == '/voice') {
        Navigator.pushNamed(context, route);
      } else {
        Navigator.pushReplacementNamed(context, route);
      }
    }
  }
}

class _DockItem extends StatelessWidget {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Duration motionDuration;
  const _DockItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.motionDuration,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Expanded(
      child: Semantics(
        key: ValueKey('dock-item-${label.toLowerCase()}'),
        container: true,
        button: true,
        label: label,
        selected: selected,
        onTap: onTap,
        child: ExcludeSemantics(
          child: TapMotion(
            depth: .24,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: onTap,
                child: AnimatedContainer(
                  key: ValueKey('dock-selection-${label.toLowerCase()}'),
                  duration: motionDuration,
                  curve: Curves.easeOutCubic,
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedSwitcher(
                        duration: motionDuration,
                        switchInCurve: Curves.easeOutBack,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, animation) => FadeTransition(
                          opacity: animation,
                          child: ScaleTransition(
                            scale: animation,
                            child: child,
                          ),
                        ),
                        child: Icon(
                          selected ? selectedIcon : icon,
                          key: ValueKey(selected ? 'active' : 'idle'),
                          size: 21,
                          color: selected
                              ? colors.primary
                              : colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.fade,
                        softWrap: false,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontSize: 9,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: selected
                              ? colors.primary
                              : colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsSectionLabel extends StatelessWidget {
  final String text;
  const _SettingsSectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(10, 12, 10, 8),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        letterSpacing: 1.1,
        fontWeight: FontWeight.w800,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

class _SettingsIconTile extends StatelessWidget {
  final IconData icon;
  const _SettingsIconTile({required this.icon});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.primary.withValues(alpha: .10)),
      ),
      child: Icon(icon, size: 20, color: colors.primary),
    );
  }
}

ThemeData _assistantTheme(
  Brightness brightness,
  String paletteId, {
  bool reduceMotion = false,
}) {
  final dark = brightness == Brightness.dark;
  final palette = FuturisticPalette.fromId(paletteId);
  final scheme =
      ColorScheme.fromSeed(
        seedColor: palette.primaryFor(brightness),
        brightness: brightness,
      ).copyWith(
        primary: palette.primaryFor(brightness),
        secondary: palette.secondaryFor(brightness),
        tertiary: palette.tertiaryFor(brightness),
      );
  final fieldRadius = BorderRadius.circular(18);
  final buttonRadius = BorderRadius.circular(22);
  final motionDuration = reduceMotion
      ? Duration.zero
      : const Duration(milliseconds: 180);
  final normalBorder = BorderSide(
    color: scheme.outlineVariant.withValues(alpha: dark ? .50 : .58),
    width: .9,
  );
  final glassBorder = WidgetStateProperty.resolveWith<BorderSide?>((states) {
    if (states.contains(WidgetState.disabled)) {
      return BorderSide(
        color: scheme.outlineVariant.withValues(alpha: .24),
        width: .8,
      );
    }
    if (states.contains(WidgetState.pressed) ||
        states.contains(WidgetState.focused)) {
      return BorderSide(
        color: scheme.primary.withValues(alpha: .82),
        width: 1.2,
      );
    }
    if (states.contains(WidgetState.hovered)) {
      return BorderSide(
        color: scheme.primary.withValues(alpha: .62),
        width: 1.1,
      );
    }
    return normalBorder;
  });
  final glassOverlay = WidgetStateProperty.resolveWith<Color?>((states) {
    if (states.contains(WidgetState.pressed)) {
      return scheme.primary.withValues(alpha: dark ? .16 : .12);
    }
    if (states.contains(WidgetState.focused)) {
      return scheme.primary.withValues(alpha: dark ? .12 : .09);
    }
    if (states.contains(WidgetState.hovered)) {
      return scheme.primary.withValues(alpha: dark ? .09 : .07);
    }
    return null;
  });
  final glassBackground = WidgetStateProperty.resolveWith<Color?>((states) {
    if (states.contains(WidgetState.disabled)) {
      return scheme.surfaceContainerHighest.withValues(alpha: .16);
    }
    if (states.contains(WidgetState.pressed)) {
      return scheme.primary.withValues(alpha: dark ? .20 : .14);
    }
    if (states.contains(WidgetState.focused) ||
        states.contains(WidgetState.hovered)) {
      return scheme.primary.withValues(alpha: dark ? .14 : .10);
    }
    return scheme.surfaceContainerHighest.withValues(alpha: dark ? .30 : .40);
  });
  final textButtonBackground = WidgetStateProperty.resolveWith<Color?>((
    states,
  ) {
    if (states.contains(WidgetState.disabled)) return Colors.transparent;
    if (states.contains(WidgetState.pressed)) {
      return scheme.primary.withValues(alpha: dark ? .16 : .12);
    }
    if (states.contains(WidgetState.focused) ||
        states.contains(WidgetState.hovered)) {
      return scheme.primary.withValues(alpha: dark ? .10 : .07);
    }
    return scheme.surfaceContainerHighest.withValues(alpha: dark ? .09 : .08);
  });
  final elevation = WidgetStateProperty.resolveWith<double>((states) {
    if (states.contains(WidgetState.disabled)) return 0;
    if (states.contains(WidgetState.pressed)) return 1;
    if (states.contains(WidgetState.hovered) ||
        states.contains(WidgetState.focused)) {
      return 3;
    }
    return 1;
  });
  final outline = OutlineInputBorder(
    borderRadius: fieldRadius,
    borderSide: normalBorder,
  );
  final outlineHighlight = BorderSide(
    color: scheme.primary.withValues(alpha: .96),
    width: 1.6,
  );
  return ThemeData(
    colorScheme: scheme,
    brightness: brightness,
    scaffoldBackgroundColor: palette.backgroundFor(brightness),
    extensions: [
      PaletteVisuals(
        orbColors: palette.orbColors,
        glowColors: [
          palette.primaryFor(brightness),
          palette.secondaryFor(brightness),
          palette.tertiaryFor(brightness),
        ],
      ),
    ],
    useMaterial3: true,
    splashFactory: InkSparkle.splashFactory,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: GlassDepthPageTransitionsBuilder(),
        TargetPlatform.iOS: GlassDepthPageTransitionsBuilder(),
        TargetPlatform.macOS: GlassDepthPageTransitionsBuilder(),
      },
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 20,
        fontWeight: FontWeight.w600,
        letterSpacing: -.35,
      ),
      iconTheme: IconThemeData(color: scheme.onSurface),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.transparent,
      elevation: 0,
      indicatorColor: scheme.primary.withValues(alpha: dark ? .28 : .13),
      labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.onSurfaceVariant,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          color: states.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.onSurfaceVariant,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: .1,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withValues(
        alpha: dark ? .36 : .46,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      border: outline,
      enabledBorder: outline,
      disabledBorder: OutlineInputBorder(
        borderRadius: fieldRadius,
        borderSide: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: .28),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: fieldRadius,
        borderSide: outlineHighlight,
      ),
      hintStyle: TextStyle(
        color: scheme.onSurfaceVariant.withValues(alpha: .78),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style:
          FilledButton.styleFrom(
            minimumSize: const Size(0, 48),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
            shape: RoundedRectangleBorder(borderRadius: buttonRadius),
            textStyle: const TextStyle(fontWeight: FontWeight.w600),
          ).copyWith(
            side: WidgetStateProperty.resolveWith<BorderSide?>((states) {
              if (states.contains(WidgetState.disabled)) {
                return BorderSide(
                  color: scheme.onSurface.withValues(alpha: .12),
                );
              }
              return BorderSide(
                color: scheme.onPrimary.withValues(alpha: dark ? .32 : .46),
                width: .9,
              );
            }),
            elevation: elevation,
            shadowColor: WidgetStatePropertyAll(
              scheme.primary.withValues(alpha: dark ? .26 : .19),
            ),
            overlayColor: WidgetStateProperty.resolveWith<Color?>((states) {
              if (states.contains(WidgetState.pressed)) {
                return scheme.onPrimary.withValues(alpha: .16);
              }
              if (states.contains(WidgetState.focused) ||
                  states.contains(WidgetState.hovered)) {
                return scheme.onPrimary.withValues(alpha: .10);
              }
              return null;
            }),
            animationDuration: motionDuration,
            splashFactory: InkSparkle.splashFactory,
          ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style:
          OutlinedButton.styleFrom(
            minimumSize: const Size(0, 48),
            foregroundColor: scheme.primary,
            shape: RoundedRectangleBorder(borderRadius: buttonRadius),
          ).copyWith(
            backgroundColor: glassBackground,
            side: glassBorder,
            overlayColor: glassOverlay,
            elevation: elevation,
            shadowColor: WidgetStatePropertyAll(
              scheme.primary.withValues(alpha: dark ? .18 : .10),
            ),
            animationDuration: motionDuration,
            splashFactory: InkSparkle.splashFactory,
          ),
    ),
    textButtonTheme: TextButtonThemeData(
      style:
          TextButton.styleFrom(
            minimumSize: const Size(40, 44),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            foregroundColor: scheme.primary,
            shape: RoundedRectangleBorder(borderRadius: buttonRadius),
          ).copyWith(
            backgroundColor: textButtonBackground,
            side: glassBorder,
            overlayColor: glassOverlay,
            animationDuration: motionDuration,
            splashFactory: InkSparkle.splashFactory,
          ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style:
          IconButton.styleFrom(
            foregroundColor: scheme.onSurfaceVariant,
            shape: const CircleBorder(),
          ).copyWith(
            backgroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
              if (states.contains(WidgetState.disabled)) {
                return Colors.transparent;
              }
              if (states.contains(WidgetState.pressed)) {
                return scheme.primary.withValues(alpha: dark ? .20 : .13);
              }
              if (states.contains(WidgetState.focused) ||
                  states.contains(WidgetState.hovered)) {
                return scheme.primary.withValues(alpha: dark ? .14 : .09);
              }
              return scheme.surfaceContainerHighest.withValues(
                alpha: dark ? .12 : .10,
              );
            }),
            side: glassBorder,
            overlayColor: glassOverlay,
            animationDuration: motionDuration,
            splashFactory: InkSparkle.splashFactory,
          ),
    ),
    listTileTheme: ListTileThemeData(
      tileColor: scheme.surfaceContainerHighest.withValues(
        alpha: dark ? .12 : .10,
      ),
      selectedTileColor: scheme.primary.withValues(alpha: dark ? .18 : .12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: dark ? .34 : .46),
        ),
      ),
      minVerticalPadding: 10,
      horizontalTitleGap: 12,
      enableFeedback: true,
    ),
    expansionTileTheme: ExpansionTileThemeData(
      backgroundColor: Colors.transparent,
      collapsedBackgroundColor: Colors.transparent,
      textColor: scheme.primary,
      iconColor: scheme.primary,
      collapsedShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: dark ? .34 : .46),
        ),
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: scheme.primary.withValues(alpha: .42)),
      ),
    ),
    cardTheme: CardThemeData(
      color: scheme.surface.withValues(alpha: dark ? .70 : .76),
      elevation: 1,
      shadowColor: scheme.primary.withValues(alpha: dark ? .14 : .09),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(26),
        side: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: dark ? .36 : .48),
        ),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: scheme.surface.withValues(alpha: dark ? .96 : .98),
      elevation: 10,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: dark ? .46 : .56),
        ),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith<Color?>((states) {
        if (states.contains(WidgetState.disabled)) {
          return scheme.onSurface.withValues(alpha: .38);
        }
        return states.contains(WidgetState.selected)
            ? scheme.onPrimary
            : scheme.onSurfaceVariant;
      }),
      trackColor: WidgetStateProperty.resolveWith<Color?>((states) {
        return states.contains(WidgetState.selected)
            ? scheme.primary.withValues(alpha: dark ? .56 : .42)
            : scheme.surfaceContainerHighest.withValues(alpha: .78);
      }),
      trackOutlineColor: WidgetStateProperty.resolveWith<Color?>((states) {
        return states.contains(WidgetState.selected)
            ? scheme.primary.withValues(alpha: .76)
            : scheme.outlineVariant.withValues(alpha: .68);
      }),
      overlayColor: glassOverlay,
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith<Color?>((states) {
        if (states.contains(WidgetState.disabled)) {
          return scheme.onSurface.withValues(alpha: .24);
        }
        return states.contains(WidgetState.selected)
            ? scheme.primary
            : Colors.transparent;
      }),
      checkColor: WidgetStatePropertyAll(scheme.onPrimary),
      overlayColor: glassOverlay,
      side: normalBorder,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith<Color?>((states) {
        if (states.contains(WidgetState.disabled)) {
          return scheme.onSurface.withValues(alpha: .30);
        }
        return states.contains(WidgetState.selected)
            ? scheme.primary
            : scheme.onSurfaceVariant;
      }),
      overlayColor: glassOverlay,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        animationDuration: motionDuration,
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        backgroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
          return states.contains(WidgetState.selected)
              ? scheme.primary.withValues(alpha: dark ? .24 : .15)
              : scheme.surfaceContainerHighest.withValues(alpha: .30);
        }),
        foregroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
          return states.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.onSurfaceVariant;
        }),
        side: glassBorder,
        overlayColor: glassOverlay,
        shape: WidgetStatePropertyAll<OutlinedBorder>(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
        splashFactory: InkSparkle.splashFactory,
      ),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant.withValues(alpha: dark ? .36 : .48),
      thickness: 1,
      space: 20,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? const Color(0xff292d40) : const Color(0xff25263a),
      contentTextStyle: const TextStyle(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: scheme.primary,
      selectionColor: scheme.primary.withValues(alpha: .24),
      selectionHandleColor: scheme.primary,
    ),
  );
}

class _AmbientGlow extends StatefulWidget {
  const _AmbientGlow();

  @override
  State<_AmbientGlow> createState() => _AmbientGlowState();
}

class _AmbientGlowState extends State<_AmbientGlow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 18),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) => CustomPaint(
      painter: _AmbientPainter(
        progress: MediaQuery.disableAnimationsOf(context)
            ? .45
            : _controller.value,
        scheme: Theme.of(context).colorScheme,
      ),
      child: const SizedBox.expand(),
    ),
  );
}

class _AmbientPainter extends CustomPainter {
  final double progress;
  final ColorScheme scheme;
  const _AmbientPainter({required this.progress, required this.scheme});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final dark = scheme.brightness == Brightness.dark;
    final phase = progress * math.pi * 2;
    void glow(Offset center, double radius, Color color, double opacity) {
      final bounds = Rect.fromCircle(center: center, radius: radius);
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: opacity),
            color.withValues(alpha: 0),
          ],
        ).createShader(bounds);
      canvas.drawCircle(center, radius, paint);
    }

    glow(
      Offset(size.width * (.18 + .14 * math.sin(phase)), size.height * .16),
      size.width * .78,
      scheme.primary,
      dark ? .28 : .24,
    );
    glow(
      Offset(size.width * (.84 - .12 * math.sin(phase)), size.height * .64),
      size.width * .68,
      scheme.tertiary,
      dark ? .22 : .19,
    );
    glow(
      Offset(size.width * (.48 + .10 * math.cos(phase)), size.height * .98),
      size.width * .56,
      scheme.secondary,
      dark ? .14 : .15,
    );
  }

  @override
  bool shouldRepaint(_AmbientPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.scheme != scheme;
}

class Glass extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? tintColor;
  final double bottomSpacing;
  final BorderRadius borderRadius;

  const Glass({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.tintColor,
    this.bottomSpacing = 14,
    this.borderRadius = const BorderRadius.all(Radius.circular(24)),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final surface = tintColor == null
        ? theme.colorScheme.surface
        : Color.alphaBlend(
            tintColor!.withValues(alpha: dark ? .24 : .12),
            theme.colorScheme.surface,
          );
    return Padding(
      padding: EdgeInsets.only(bottom: bottomSpacing),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          boxShadow: [
            BoxShadow(
              color: theme.colorScheme.primary.withValues(
                alpha: dark ? .20 : .13,
              ),
              blurRadius: 34,
              spreadRadius: -3,
              offset: const Offset(0, 11),
            ),
            BoxShadow(
              color: theme.colorScheme.tertiary.withValues(
                alpha: dark ? .11 : .08,
              ),
              blurRadius: 38,
              spreadRadius: -8,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: borderRadius,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withValues(alpha: dark ? .12 : .70),
                    surface.withValues(alpha: dark ? .62 : .62),
                    theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: dark ? .28 : .42,
                    ),
                  ],
                ),
                borderRadius: borderRadius,
                border: Border.all(
                  color: Colors.white.withValues(alpha: dark ? .18 : .82),
                  width: 1,
                ),
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.center,
                            colors: [
                              Colors.white.withValues(alpha: dark ? .07 : .30),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: padding,
                    child: Material(
                      type: MaterialType.transparency,
                      child: child,
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

class SoftEntrance extends StatefulWidget {
  final Widget child;
  final Duration delay;

  const SoftEntrance({
    super.key,
    required this.child,
    this.delay = Duration.zero,
  });

  @override
  State<SoftEntrance> createState() => _SoftEntranceState();
}

class _SoftEntranceState extends State<SoftEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 560),
  );
  Timer? _delayTimer;

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      _delayTimer = Timer(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final value = reduced
            ? 1.0
            : Curves.easeOutBack
                  .transform(_controller.value)
                  .clamp(0.0, 1.0)
                  .toDouble();
        final depth = Matrix4.identity()
          ..setEntry(3, 2, .0015)
          ..rotateX((1 - value) * .12)
          ..rotateY((1 - value) * -.16)
          ..scaleByDouble(
            .90 + .10 * value,
            .90 + .10 * value,
            .90 + .10 * value,
            1,
          );
        return Opacity(
          opacity: value,
          child: Transform(
            alignment: Alignment.center,
            transform: depth,
            child: Transform.translate(
              offset: Offset(0, 16 * (1 - value)),
              child: child,
            ),
          ),
        );
      },
    );
  }
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

class DeviceActionReviewDialog extends StatefulWidget {
  final Map<String, dynamic> action;
  final String? appLabel;
  final String? packageName;

  const DeviceActionReviewDialog({
    super.key,
    required this.action,
    this.appLabel,
    this.packageName,
  });

  @override
  State<DeviceActionReviewDialog> createState() =>
      _DeviceActionReviewDialogState();
}

class _DeviceActionReviewDialogState extends State<DeviceActionReviewDialog> {
  late final TextEditingController _title;
  late DateTime _when;

  bool get _isReminder => widget.action['kind'] == 'reminder';

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(
      text: (widget.action['title'] as String?) ?? '',
    );
    _when = DateTime.fromMillisecondsSinceEpoch(
      widget.action['at_ms'] as int? ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _editDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final lastDate = today.add(const Duration(days: 366));
    final selectedDay = await showDatePicker(
      context: context,
      firstDate: today,
      lastDate: lastDate,
      initialDate: _when.isBefore(today)
          ? today
          : _when.isAfter(lastDate)
          ? lastDate
          : _when,
    );
    if (selectedDay == null || !mounted) return;
    final selectedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_when),
    );
    if (selectedTime == null || !mounted) return;
    setState(() {
      _when = DateTime(
        selectedDay.year,
        selectedDay.month,
        selectedDay.day,
        selectedTime.hour,
        selectedTime.minute,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final description = _isReminder
        ? 'Review or edit the reminder. Nothing is scheduled until you approve it. Android delivery is approximate; battery restrictions may delay it.'
        : 'Open ${widget.appLabel} (${widget.packageName}) on this device. Cancel and choose another app if this is not the one you intended.';
    return AlertDialog(
      title: const Text('Review device action'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(description),
          if (_isReminder) ...[
            const SizedBox(height: 12),
            TextField(
              key: const Key('device-action-title-editor'),
              controller: _title,
              maxLength: 120,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Reminder'),
            ),
            OutlinedButton.icon(
              key: const Key('device-action-time-editor'),
              onPressed: _editDate,
              icon: const Icon(Icons.schedule),
              label: Text(
                '${MaterialLocalizations.of(context).formatMediumDate(_when)} at ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(_when))}',
              ),
            ),
          ] else ...[
            const SizedBox(height: 8),
            Text(widget.appLabel ?? 'Selected app'),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isReminder && _title.text.trim().isEmpty
              ? null
              : () => Navigator.pop(
                  context,
                  _isReminder
                      ? <String, dynamic>{
                          ...widget.action,
                          'title': _title.text.trim(),
                          'at_ms': _when.millisecondsSinceEpoch,
                        }
                      : Map<String, dynamic>.from(widget.action),
                ),
          child: const Text('Approve this action'),
        ),
      ],
    );
  }
}

class Home extends StatelessWidget {
  final AssistantState state;
  const Home({super.key, required this.state});
  Future<void> action(
    BuildContext context,
    Map<String, dynamic> action, {
    LaunchableApp? selectedApp,
  }) async {
    try {
      if (action['kind'] == 'open_app' && selectedApp == null) {
        throw ServiceException('Choose an app from the installed-app list.');
      }
      if (!context.mounted) return;
      final reviewedAction = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (_) => DeviceActionReviewDialog(
          action: action,
          appLabel: selectedApp?.label,
          packageName: selectedApp?.packageName,
        ),
      );
      if (reviewedAction == null || !context.mounted) return;
      final draft = reviewedAction['kind'] == 'open_app'
          ? await state.prepareSelectedAppLaunch(selectedApp!)
          : await state.prepareAction(reviewedAction);
      final result = await state.executeApproved(draft['id']);
      final report = result['detail'].toString();
      if (context.mounted) notice(context, report);
    } catch (e) {
      if (context.mounted) notice(context, e);
    }
  }

  Future<void> openAppPicker(BuildContext context) async {
    try {
      final apps = await state.loadLaunchableApps();
      if (!context.mounted) return;
      if (apps.isEmpty) {
        notice(context, 'No installed apps with a launcher screen were found.');
        return;
      }
      final selected = await showModalBottomSheet<LaunchableApp>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => AppPickerSheet(apps: apps),
      );
      if (selected != null && context.mounted) {
        await action(context, const {
          'kind': 'open_app',
        }, selectedApp: selected);
      }
    } catch (error) {
      if (context.mounted) notice(context, error);
    }
  }

  Future<void> reminder(BuildContext context, {String? initialTitle}) async {
    final title = TextEditingController(text: initialTitle ?? '');
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final openTasks = state.local
        .rows('tasks')
        .where((row) => !row['done'])
        .toList();
    final attempts = state.local.rows('attempts');
    final localNow = DateTime.now();
    final todayKey =
        '${localNow.year.toString().padLeft(4, '0')}-${localNow.month.toString().padLeft(2, '0')}-${localNow.day.toString().padLeft(2, '0')}';
    final monthKey = todayKey.substring(0, 7);
    final waterToday = state.local
        .rows('water_logs')
        .where((row) => row['date'] == todayKey)
        .fold<int>(0, (sum, row) => sum + (row['milliliters'] as int? ?? 0));
    final habitCheckinsToday = state.local
        .rows('habits')
        .where(
          (habit) =>
              habit['completed_dates'] is List &&
              (habit['completed_dates'] as List).contains(todayKey),
        )
        .length;
    final expenseTotals = <String, int>{};
    for (final entry in state.local.rows('expenses')) {
      final date = entry['date']?.toString() ?? '';
      final currency = entry['currency']?.toString().trim() ?? '';
      if (date.startsWith(monthKey) && currency.isNotEmpty) {
        expenseTotals[currency] =
            (expenseTotals[currency] ?? 0) +
            (entry['amount_minor'] as int? ?? 0);
      }
    }
    final upcomingReminders = state.local
        .rows('actions')
        .where(
          (row) =>
              row['status'] == 'scheduled' &&
              row['action']['at_ms'] > DateTime.now().millisecondsSinceEpoch,
        )
        .toList();
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 17
        ? 'Good afternoon'
        : 'Good evening';
    final modeLabel = state.chatMode == 'offline'
        ? state.experimentalOfflineChatEnabled
              ? 'Offline · local only'
              : 'Offline opt-in needed'
        : 'Online mode selected';
    return Shell(
      title: state.assistantName,
      assistantName: state.assistantName,
      actions: [
        IconButton(
          tooltip: 'Reminder activity',
          onPressed: () => Navigator.pushNamed(context, '/automations'),
          icon: const Icon(Icons.notifications_none_rounded),
        ),
      ],
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 118),
        children: [
          SoftEntrance(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        greeting,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: -.65,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'What would you like to do today?',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  margin: const EdgeInsets.only(top: 2),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface.withValues(alpha: .68),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: theme.colorScheme.primary.withValues(alpha: .14),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: theme.colorScheme.primary.withValues(alpha: .07),
                        blurRadius: 18,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        state.chatMode == 'offline'
                            ? Icons.cloud_off_rounded
                            : Icons.auto_awesome_rounded,
                        size: 15,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        modeLabel,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          SoftEntrance(
            delay: const Duration(milliseconds: 50),
            child: Glass(
              tintColor: theme.colorScheme.primary,
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
              child: Column(
                children: [
                  HolographicAssistantOrb(
                    state: state.busy
                        ? HolographicOrbState.thinking
                        : HolographicOrbState.idle,
                    size: 182,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    state.busy ? 'Thinking with you' : 'Here when you need me',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -.45,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Chat, study, or make a small plan.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _HomeQuickAction(
                        label: 'Chat',
                        icon: Icons.chat_bubble_outline_rounded,
                        onTap: () => Navigator.pushNamed(context, '/chat'),
                      ),
                      const SizedBox(width: 8),
                      _HomeQuickAction(
                        label: 'Study',
                        icon: Icons.school_outlined,
                        onTap: () => Navigator.pushNamed(context, '/study'),
                      ),
                      const SizedBox(width: 8),
                      _HomeQuickAction(
                        label: 'Memory',
                        icon: Icons.psychology_alt_outlined,
                        onTap: () => Navigator.pushNamed(context, '/memory'),
                      ),
                      const SizedBox(width: 8),
                      _HomeQuickAction(
                        label: 'Tools',
                        icon: Icons.build_circle_outlined,
                        onTap: () => Navigator.pushNamed(context, '/features'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          SoftEntrance(
            delay: const Duration(milliseconds: 100),
            child: Row(
              children: [
                Expanded(
                  child: _HomeInfoCard(
                    icon: Icons.check_circle_outline_rounded,
                    value: '${openTasks.length}',
                    label: 'Open tasks',
                    onTap: () => Navigator.pushNamed(context, '/library'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _HomeInfoCard(
                    icon: Icons.school_outlined,
                    value: '${attempts.length}',
                    label: 'Study attempts',
                    onTap: () => Navigator.pushNamed(context, '/study'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _HomeInfoCard(
                    icon: Icons.notifications_active_outlined,
                    value: '${upcomingReminders.length}',
                    label: 'Reminders',
                    onTap: () => Navigator.pushNamed(context, '/automations'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Glass(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Your logs', style: theme.textTheme.titleMedium),
                Text(
                  'Water today: $waterToday ml · Habit check-ins today: $habitCheckinsToday',
                ),
                if (expenseTotals.isEmpty)
                  const Text('No expense total logged this month.')
                else ...[
                  const SizedBox(height: 4),
                  for (final entry in expenseTotals.entries)
                    Text(
                      'This month · ${entry.key} ${entry.value ~/ 100}.${(entry.value % 100).toString().padLeft(2, '0')}',
                    ),
                ],
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.pushNamed(context, '/library'),
                    child: const Text('Open local logs'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SoftEntrance(
            delay: const Duration(milliseconds: 150),
            child: _HomeComposer(
              onOpenChat: (draft) =>
                  Navigator.pushNamed(context, '/chat', arguments: draft),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '${openTasks.isEmpty ? 'No open tasks yet' : 'Your tasks and notes stay on this device.'}  Voice starts only when you tap the mic.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeQuickAction extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _HomeQuickAction({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Expanded(
      child: Material(
        color: colors.surface.withValues(alpha: .54),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 5),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 16, color: colors.primary),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
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

class _HomeInfoCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final VoidCallback onTap;
  const _HomeInfoCard({
    required this.icon,
    required this.value,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Glass(
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: SizedBox(
          height: 108,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 19, color: colors.primary),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: theme.textTheme.titleLarge?.copyWith(
                    height: 1.0,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontSize: 9,
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

class _HomeComposer extends StatefulWidget {
  final ValueChanged<String?> onOpenChat;
  const _HomeComposer({required this.onOpenChat});

  @override
  State<_HomeComposer> createState() => _HomeComposerState();
}

class _HomeComposerState extends State<_HomeComposer> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _continue() {
    final draft = _controller.text.trim();
    widget.onOpenChat(draft.isEmpty ? null : draft);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Glass(
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      child: Row(
        children: [
          Icon(
            Icons.edit_note_rounded,
            color: colors.onSurfaceVariant,
            size: 22,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _controller,
              maxLines: 1,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _continue(),
              decoration: InputDecoration(
                hintText: 'Ask your assistant…',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                contentPadding: EdgeInsets.zero,
                hintStyle: TextStyle(color: colors.onSurfaceVariant),
              ),
            ),
          ),
          const SizedBox(width: 6),
          IconButton.filledTonal(
            tooltip: 'Continue in chat',
            onPressed: _continue,
            icon: const Icon(Icons.arrow_upward_rounded),
          ),
        ],
      ),
    );
  }
}

class AppPickerSheet extends StatefulWidget {
  final List<LaunchableApp> apps;
  const AppPickerSheet({super.key, required this.apps});

  @override
  State<AppPickerSheet> createState() => _AppPickerSheetState();
}

class _AppPickerSheetState extends State<AppPickerSheet> {
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final apps = widget.apps
        .where(
          (app) =>
              app.label.toLowerCase().contains(query) ||
              app.packageName.toLowerCase().contains(query),
        )
        .toList(growable: false);
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SizedBox(
        height: math
            .min(MediaQuery.sizeOf(context).height * .78, 680)
            .toDouble(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Installed apps', style: theme.textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              'Choose one to prepare a launch for your review.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: 'Search by app name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: apps.isEmpty
                  ? Center(
                      child: Text(
                        'No matching apps',
                        style: theme.textTheme.bodyMedium,
                      ),
                    )
                  : ListView.separated(
                      itemCount: apps.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final app = apps[index];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: app.iconPng == null
                              ? CircleAvatar(
                                  child: Text(app.label.substring(0, 1)),
                                )
                              : ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Image.memory(
                                    app.iconPng!,
                                    width: 40,
                                    height: 40,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => const SizedBox(
                                      width: 40,
                                      height: 40,
                                      child: Icon(Icons.apps_rounded),
                                    ),
                                  ),
                                ),
                          title: Text(
                            app.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            app.packageName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => Navigator.pop(context, app),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class VoiceTranscriptReviewDialog extends StatefulWidget {
  final String transcript;
  final bool sendMessage;

  const VoiceTranscriptReviewDialog({
    super.key,
    required this.transcript,
    this.sendMessage = false,
  });

  @override
  State<VoiceTranscriptReviewDialog> createState() =>
      _VoiceTranscriptReviewDialogState();
}

class _VoiceTranscriptReviewDialogState
    extends State<VoiceTranscriptReviewDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.transcript);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Review voice transcript'),
    scrollable: true,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.sendMessage
              ? 'Correct anything recognition got wrong. Tapping Send submits this message; device actions still need their normal approval.'
              : 'Correct anything recognition got wrong. Using this transcript only places it in the message box; it does not send or execute anything.',
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('voice-transcript-editor'),
          controller: _controller,
          onChanged: (_) => setState(() {}),
          minLines: 2,
          maxLines: 6,
          maxLength: 8000,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Recognized words'),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _controller.text.trim().isEmpty
            ? null
            : () => Navigator.pop(context, _controller.text),
        child: Text(widget.sendMessage ? 'Send message' : 'Use transcript'),
      ),
    ],
  );
}

class ChatScreen extends StatefulWidget {
  final AssistantState state;
  final String? initialDraft;
  final bool startWithVoice;
  final bool startWithVoiceCommand;
  const ChatScreen({
    super.key,
    required this.state,
    this.initialDraft,
    this.startWithVoice = false,
    this.startWithVoiceCommand = false,
  });
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final input = TextEditingController();
  final _inputFocus = FocusNode();
  final ScrollController _chatScrollController = ScrollController();
  int _lastObservedMessageCount = -1;
  String? _lastObservedConversation;
  String _lastObservedPartial = '';
  Uint8List? _chatAttachmentBytes;
  String _chatAttachmentName = '';
  String _chatAttachmentMime = '';
  bool _chatWebSearch = false;
  bool _chatFeatureBusy = false;
  String _chatFeatureError = '';

  void _chatStateChanged() {
    final state = widget.state;
    final count = state.messages.length;
    final conversation = state.conversation;
    final partial = state.partial;
    if (count == _lastObservedMessageCount &&
        conversation == _lastObservedConversation &&
        partial == _lastObservedPartial) {
      return;
    }
    _lastObservedMessageCount = count;
    _lastObservedConversation = conversation;
    _lastObservedPartial = partial;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrollToLatest();
    });
  }

  void _audioPlaybackChanged() {
    if (!mounted) return;
    final isPlaying = _assistantAudioPlaying.value;
    if (speaking != isPlaying) setState(() => speaking = isPlaying);
  }

  void _scrollToLatest({bool jump = false}) {
    if (!_chatScrollController.hasClients) return;
    final position = _chatScrollController.position;
    if (!position.hasContentDimensions) return;
    final target = position.maxScrollExtent;
    if (jump) {
      _chatScrollController.jumpTo(target);
    } else {
      _chatScrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    }
  }

  static const voiceEvents = MethodChannel('personal_assistant/voice');
  late final AzureSpeechSynthesizer _azureSpeech = AzureSpeechSynthesizer(
    clientFactory: widget.state.clientFactory,
  );
  late final GeminiExpressiveSpeechSynthesizer _geminiSpeech =
      GeminiExpressiveSpeechSynthesizer(
        clientFactory: widget.state.clientFactory,
      );
  final tts = FlutterTts();
  final _deepgramRecorder = AudioRecorder();
  final _deepgram = DeepgramTranscriber();
  DeepgramLiveSession? _liveDeepgram;
  StreamSubscription<Uint8List>? _liveAudioSubscription;
  final List<String> _liveTurnQueue = [];
  bool _liveConversationActive = false;
  bool _liveConversationStarting = false;
  bool _liveTurnProcessing = false;
  StreamSubscription<Uint8List>? _deepgramSubscription;
  final List<Uint8List> _deepgramChunks = [];
  Timer? _deepgramLimit;
  int _deepgramBytes = 0;
  bool _deepgramLimitHit = false;
  bool listening = false, speaking = false;
  bool _draftApplied = false;
  bool _reviewingTranscript = false;
  bool _speakNextReply = false;
  bool _handsFreeSessionActive = false;
  bool _handsFreeOnlineApproved = false;
  bool _initialVoiceStarted = false;
  double level = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_draftApplied && widget.initialDraft != null) {
      input.text = widget.initialDraft!;
      _draftApplied = true;
    }
    if ((widget.startWithVoice || widget.startWithVoiceCommand) &&
        !_initialVoiceStarted) {
      _initialVoiceStarted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (widget.startWithVoiceCommand) {
          // Notification action is an explicit, one-shot request. It never opts
          // into hands-free listening or sends the recognized transcript.
          unawaited(_listenOnce());
        } else {
          listen();
        }
      });
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lastObservedMessageCount = widget.state.messages.length;
    _lastObservedConversation = widget.state.conversation;
    _lastObservedPartial = widget.state.partial;
    widget.state.addListener(_chatStateChanged);
    _assistantAudioPlaying.addListener(_audioPlaybackChanged);
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
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await widget.state.loadHistory();
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToLatest(jump: true);
      });
    });
    voiceEvents.setMethodCallHandler((call) async {
      if (!mounted || call.method != 'voice_event') return;
      final event = Map<String, dynamic>.from(call.arguments);
      final kind = event['kind'];
      setState(() {
        if (kind == 'listening') listening = true;
        if (kind == 'level') {
          level = (event['value'] as num).toDouble();
        }
        if (kind == 'stopped' || kind == 'error' || kind == 'text') {
          listening = false;
          level = 0;
        }
      });
      if (kind == 'live_stop_requested') {
        unawaited(_endLiveConversation());
        return;
      }
      if (kind == 'text') {
        final transcript = (event['value'] as String? ?? '').trim();
        if (transcript.isEmpty) {
          notice(context, 'No speech was recognized. Your draft is unchanged.');
          if (_handsFreeSessionActive) unawaited(_endHandsFreeSession());
        } else {
          unawaited(_reviewVoiceTranscript(transcript));
        }
      }
      if (kind == 'error') {
        notice(context, event['value'].toString());
        if (_handsFreeSessionActive) unawaited(_endHandsFreeSession());
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _liveConversationActive) {
      return;
    }
    if (state != AppLifecycleState.resumed) {
      _handsFreeSessionActive = false;
      _handsFreeOnlineApproved = false;
      AssistantState.device.invokeMethod('voice_cancel');
      unawaited(_cancelDeepgramRecording());
      _deepgram.cancel();
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
      await _stopAssistantAudio();
    } on MissingPluginException {
      // Platforms without the Android playback channel keep other chat controls usable.
    } on PlatformException {
      // Stopping optional audio must not block microphone or typed chat.
    }
  }

  Future<void> stopAll() async {
    if (_liveConversationActive || _liveConversationStarting) {
      await _endLiveConversation();
    }
    _handsFreeSessionActive = false;
    _handsFreeOnlineApproved = false;
    if (listening && widget.state.speechMode == 'deepgram') {
      await _cancelDeepgramRecording();
    }
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

  Future<void> _cancelDeepgramRecording() async {
    _deepgramLimit?.cancel();
    _deepgramLimit = null;
    _deepgram.cancel();
    try {
      await _deepgramRecorder.stop();
    } catch (_) {
      // No active recording or platform service unavailable.
    }
    await _deepgramSubscription?.cancel();
    _deepgramSubscription = null;
    _deepgramChunks.clear();
    _deepgramBytes = 0;
    _deepgramLimitHit = false;
    if (mounted) {
      setState(() {
        listening = false;
        level = 0;
      });
    }
  }

  Future<void> _startDeepgramRecording() async {
    if (widget.state.deepgramApiKey.isEmpty) {
      notice(
        context,
        'Add your Deepgram API key in Settings before using Deepgram voice input.',
      );
      return;
    }
    var approved = false;
    approved =
        await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Record speech for Deepgram?'),
            content: const Text(
              'Recording starts only after you approve and stays on while this screen is open. When you tap Stop, the audio is sent once to Deepgram for transcription; it may be processed under your Deepgram plan. The transcript is placed in the message box and is not sent to the chat until you press Send. No recording is uploaded in the background.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Record with Deepgram'),
              ),
            ],
          ),
        ) ??
        false;
    if (!approved || !mounted) return;
    try {
      if (!await _deepgramRecorder.hasPermission()) {
        if (mounted) {
          notice(
            context,
            'Allow microphone access in Android to record speech.',
          );
        }
        return;
      }
      _deepgramChunks.clear();
      _deepgramBytes = 0;
      _deepgramLimitHit = false;
      final stream = await _deepgramRecorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
        ),
      );
      if (!mounted) {
        await _deepgramRecorder.stop();
        return;
      }
      _deepgramSubscription = stream.listen(
        (chunk) {
          if (!mounted || _deepgramLimitHit) return;
          _deepgramBytes += chunk.length;
          // 60 seconds of 16 kHz mono PCM16 is about 1.9 MB.
          if (_deepgramBytes > 16000 * 2 * 60) {
            _deepgramLimitHit = true;
            unawaited(_cancelDeepgramRecording());
            if (mounted) {
              notice(
                context,
                'Recording limit reached; audio was discarded. Tap the microphone to start again.',
              );
            }
            return;
          }
          _deepgramChunks.add(chunk);
        },
        onError: (_) {
          unawaited(_cancelDeepgramRecording());
          if (mounted) {
            notice(
              context,
              'Microphone recording stopped. Nothing was uploaded.',
            );
          }
        },
      );
      _deepgramLimit = Timer(const Duration(seconds: 60), () {
        if (!mounted) return;
        unawaited(_cancelDeepgramRecording());
        notice(
          context,
          'Recording limit reached; audio was discarded. Tap the microphone to start again.',
        );
      });
      setState(() {
        listening = true;
        level = 0;
      });
      if (mounted) {
        notice(
          context,
          'Recording on. Tap Stop to send this clip to Deepgram.',
        );
      }
    } on PlatformException catch (e) {
      if (mounted) {
        notice(
          context,
          e.message ?? 'Microphone unavailable. Nothing was uploaded.',
        );
      }
    } catch (_) {
      if (mounted) {
        notice(
          context,
          'Could not start microphone recording. Nothing was uploaded.',
        );
      }
    }
  }

  Future<void> _stopDeepgramRecording() async {
    _deepgramLimit?.cancel();
    _deepgramLimit = null;
    try {
      await _deepgramRecorder.stop();
      await _deepgramSubscription?.cancel();
      _deepgramSubscription = null;
      if (!mounted) return;
      final size = _deepgramBytes;
      final audio = Uint8List(size);
      var offset = 0;
      for (final chunk in _deepgramChunks) {
        audio.setRange(offset, offset + chunk.length, chunk);
        offset += chunk.length;
      }
      _deepgramChunks.clear();
      _deepgramBytes = 0;
      setState(() {
        listening = false;
        level = 0;
      });
      notice(
        context,
        'Sending this recording once to Deepgram for transcription…',
      );
      final transcript = await _deepgram.transcribe(
        pcm16le: audio,
        apiKey: widget.state.deepgramApiKey,
        locale: widget.state.language,
      );
      if (mounted) {
        await _reviewVoiceTranscript(transcript);
      }
    } catch (e) {
      if (mounted) notice(context, e);
    } finally {
      _deepgramChunks.clear();
      _deepgramBytes = 0;
      _deepgramLimitHit = false;
    }
  }

  Future<void> listen() async {
    if (_liveConversationActive || _liveConversationStarting) {
      await _endLiveConversation();
      return;
    }
    if (_handsFreeSessionActive) {
      await _endHandsFreeSession();
      return;
    }
    if (widget.state.voiceConversationMode == 'live_conversation') {
      await _startLiveConversation();
      return;
    }
    if (widget.state.voiceConversationMode == 'hands_free') {
      await _startHandsFreeSession();
      return;
    }
    await _listenOnce();
  }

  Future<void> _startLiveConversation() async {
    if (_liveConversationStarting || _liveConversationActive) return;
    if (widget.state.chatMode != 'online' || widget.state.engine != 'gemini') {
      notice(
        context,
        'Live Conversation needs Online chat with Gemini selected. No provider was contacted.',
      );
      return;
    }
    if (widget.state.speechMode != 'deepgram') {
      notice(
        context,
        'Choose Deepgram as speech recognition in Settings before starting Live Conversation. No provider was contacted.',
      );
      return;
    }
    if (widget.state.geminiApiKey.isEmpty ||
        widget.state.deepgramApiKey.isEmpty) {
      notice(
        context,
        'Add your Gemini and Deepgram API keys in Settings before starting. No provider was contacted.',
      );
      return;
    }
    if (!DeepgramLiveSession.supportedLocales.contains(widget.state.language)) {
      notice(
        context,
        'Deepgram Live Conversation supports English, Assamese and Hindi; choose one of those languages in Settings.',
      );
      return;
    }
    if (input.text.trim().isNotEmpty) {
      notice(
        context,
        'Send or clear your current draft before starting Live Conversation.',
      );
      return;
    }

    final consent =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Start Live Conversation?'),
            content: Text(
              'The microphone will stream live audio to Deepgram for ${widget.state.language}; recognized speech will be sent to Google Gemini for replies. ${widget.state.geminiTtsEnabled ? 'Expressive cloud speech is enabled: the exact reply text will also be sent to Google Gemini TTS; usage may be charged, and Google may use content on unpaid quota to improve products. ' : 'Replies use the installed Android voice. '}The session can continue when you switch apps, until you tap Stop here or in the ongoing notification. Start only while you want the microphone active. Provider processing, limits, and any charges follow your Deepgram and Google plans. No device action is performed automatically.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Start live session'),
              ),
            ],
          ),
        ) ??
        false;
    if (!consent || !mounted) return;

    _liveConversationStarting = true;
    if (mounted) setState(() {});
    var serviceStarted = false;
    try {
      if (!await _deepgramRecorder.hasPermission()) {
        throw ServiceException(
          'Allow Android microphone access before starting. No audio was sent.',
        );
      }
      final notificationPermission = await AssistantState.device
          .invokeMapMethod<String, dynamic>('request_access_permission', {
            'permission': 'notifications',
          });
      if (notificationPermission?['granted'] != true) {
        throw ServiceException(
          'Allow notifications so the ongoing microphone session has a visible Stop control. No audio was sent.',
        );
      }
      await LiveConversationService.start();
      serviceStarted = true;
      final session = DeepgramLiveSession(
        apiKey: widget.state.deepgramApiKey,
        locale: widget.state.language,
        onUtterance: (utterance) => unawaited(_queueLiveUtterance(utterance)),
        onError: (message) {
          if (mounted) notice(context, message);
          unawaited(_endLiveConversation());
        },
      );
      await session.start();
      _liveDeepgram = session;
      final stream = await _deepgramRecorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
        ),
      );
      if (!mounted) {
        await _deepgramRecorder.stop();
        await session.close();
        _liveDeepgram = null;
        await LiveConversationService.stop();
        return;
      }
      _liveAudioSubscription = stream.listen(
        (frame) {
          if (_liveConversationActive && !speaking && !widget.state.busy) {
            _liveDeepgram?.addAudio(frame);
          }
        },
        onError: (_) {
          if (mounted) {
            notice(
              context,
              'Microphone stream stopped. Live Conversation ended.',
            );
          }
          unawaited(_endLiveConversation());
        },
        cancelOnError: true,
      );
      _liveConversationActive = true;
      _liveTurnQueue.clear();
      setState(() {
        listening = true;
        level = 0;
      });
      notice(
        context,
        'Live Conversation is on. Audio streams to Deepgram until you tap Stop.',
      );
    } catch (error) {
      if (serviceStarted) await LiveConversationService.stop();
      if (mounted) notice(context, error);
    } finally {
      _liveConversationStarting = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _queueLiveUtterance(String utterance) async {
    final text = utterance.trim();
    if (!_liveConversationActive || text.isEmpty) return;
    if (_liveTurnQueue.length >= 3) {
      notice(
        context,
        'Live reply queue is full; pause and try again after the current reply.',
      );
      return;
    }
    _liveTurnQueue.add(text);
    if (_liveTurnProcessing) return;
    _liveTurnProcessing = true;
    try {
      while (_liveConversationActive && _liveTurnQueue.isNotEmpty) {
        final turn = _liveTurnQueue.removeAt(0);
        final download = SpokenDownloadCommand.parse(turn);
        if (download != null) {
          await _reviewAndStartLiveDownload(download);
          continue;
        }
        await widget.state.send(
          turn,
          shareMemories: widget.state.shareMemories,
          shareHistory: widget.state.shareHistory,
          spokenConversation: true,
        );
        if (!mounted || !_liveConversationActive) break;
        if (widget.state.error.isNotEmpty) {
          notice(context, widget.state.error);
          continue;
        }
        if (widget.state.messages.isNotEmpty) {
          final last = widget.state.messages.last;
          if (last['role'] == 'assistant' && last['state'] == 'complete') {
            await playReplyVoice(
              last['text'] as String,
              forceLocal: !widget.state.geminiTtsEnabled,
            );
          }
        }
      }
    } finally {
      _liveTurnProcessing = false;
    }
  }

  Future<void> _reviewAndStartLiveDownload(DownloadInput download) async {
    final approved = await reviewDownload(context, download);
    if (!approved || !mounted || !_liveConversationActive) return;
    try {
      final result = await AssistantState.device
          .invokeMapMethod<String, dynamic>('enqueue_user_download', {
            'url': download.url,
            'file_name': download.fileName,
          });
      if (!mounted) return;
      notice(
        context,
        result == null
            ? 'Android did not confirm that the download started.'
            : 'Android accepted ${result['file_name'] ?? download.fileName}. Completion is not verified.',
      );
    } catch (error) {
      if (mounted) notice(context, 'Download did not start: $error');
    }
  }

  Future<void> _endLiveConversation() async {
    final wasActive = _liveConversationActive || _liveConversationStarting;
    _liveConversationActive = false;
    _liveConversationStarting = false;
    _liveTurnQueue.clear();
    await _liveAudioSubscription?.cancel();
    _liveAudioSubscription = null;
    try {
      await _deepgramRecorder.stop();
    } catch (_) {
      // No active stream or the Android recorder already stopped.
    }
    final session = _liveDeepgram;
    _liveDeepgram = null;
    await session?.close();
    await LiveConversationService.stop();
    if (wasActive) widget.state.stop();
    try {
      await tts.stop();
    } catch (_) {}
    if (mounted) {
      setState(() {
        listening = false;
        speaking = false;
        level = 0;
      });
      if (wasActive) notice(context, 'Live Conversation stopped.');
    }
  }

  Future<void> _startHandsFreeSession() async {
    if (widget.state.speechMode == 'deepgram') {
      notice(
        context,
        'Hands-free sessions work with Android speech recognition. Deepgram needs you to stop each recording manually.',
      );
      return;
    }
    if (input.text.trim().isNotEmpty) {
      notice(
        context,
        'Send or clear your current draft before starting a voice session.',
      );
      return;
    }
    _handsFreeSessionActive = true;
    _handsFreeOnlineApproved = false;
    if (mounted) setState(() {});
    final started = await _listenOnce(handsFreeSession: true);
    if (!started && _handsFreeSessionActive) {
      await _endHandsFreeSession();
    }
  }

  Future<void> _endHandsFreeSession() async {
    _handsFreeSessionActive = false;
    _handsFreeOnlineApproved = false;
    try {
      await AssistantState.device.invokeMethod('voice_cancel');
    } catch (_) {
      // A missing speech plugin must not leave the session UI active.
    }
    try {
      await tts.stop();
    } catch (_) {
      // The session can still be ended if speech playback is unavailable.
    }
    if (speaking) await stopExpressiveAudio();
    if (mounted) {
      setState(() {
        listening = false;
        speaking = false;
        level = 0;
      });
    }
  }

  Future<bool> _listenOnce({bool handsFreeSession = false}) async {
    if (listening && widget.state.speechMode == 'deepgram') {
      await _stopDeepgramRecording();
      return true;
    }
    if (listening) {
      await stopAll();
      return false;
    }
    if (!handsFreeSession) await stopAll();
    if (!mounted) return false;
    if (widget.state.speechMode == 'deepgram') {
      await _startDeepgramRecording();
      return false;
    }
    var approved = false;
    if (widget.state.speechMode == 'online') {
      if (handsFreeSession && _handsFreeOnlineApproved) {
        approved = true;
      } else {
        approved =
            await showDialog<bool>(
              context: context,
              builder: (c) => AlertDialog(
                title: const Text('Use online speech recognition?'),
                content: Text(
                  handsFreeSession
                      ? 'During this hands-free session, Android recognition may send microphone audio to its provider for ${widget.state.language} on each turn, until you tap Stop or leave the app. This is independent of the AI engine. No offline fallback or automatic retry.'
                      : 'Your Android recognition service may send microphone audio to its provider for ${widget.state.language}. This is independent of the AI engine. No offline fallback or automatic retry.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(c, false),
                    child: const Text('Keep typing'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(c, true),
                    child: Text(
                      handsFreeSession
                          ? 'Start online session'
                          : 'Start online microphone',
                    ),
                  ),
                ],
              ),
            ) ??
            false;
        if (!approved) return false;
        if (handsFreeSession) _handsFreeOnlineApproved = true;
      }
    }
    try {
      await AssistantState.device.invokeMethod('voice_start', {
        'mode': widget.state.speechMode,
        'locale': widget.state.language,
        'approved_online': approved,
      });
      return true;
    } on PlatformException catch (e) {
      if (mounted) {
        notice(context, e.message ?? 'Speech unavailable; type instead.');
      }
      return false;
    }
  }

  Future<void> _reviewVoiceTranscript(String transcript) async {
    if (_reviewingTranscript || !mounted) return;
    _reviewingTranscript = true;
    try {
      final inHandsFreeSession = _handsFreeSessionActive;
      final corrected = await showDialog<String>(
        context: context,
        builder: (_) => VoiceTranscriptReviewDialog(
          transcript: transcript,
          sendMessage: inHandsFreeSession,
        ),
      );
      if (corrected == null || !mounted || corrected.trim().isEmpty) {
        if (inHandsFreeSession && _handsFreeSessionActive) {
          await _endHandsFreeSession();
        }
        return;
      }
      final existing = inHandsFreeSession ? '' : input.text.trim();
      final reviewed = corrected.trim();
      final combined = [
        existing,
        reviewed,
      ].where((part) => part.isNotEmpty).join(' ');
      input.value = TextEditingValue(
        text: combined,
        selection: TextSelection.collapsed(offset: combined.length),
      );
      _speakNextReply = true;
      if (inHandsFreeSession && _handsFreeSessionActive) {
        await send();
      }
    } finally {
      _reviewingTranscript = false;
    }
  }

  Future<bool> playReplyVoice(String text, {bool forceLocal = false}) async {
    if (speaking) {
      await stopAll();
      return false;
    }
    String? onlineFailure;
    if (!forceLocal && widget.state.geminiTtsEnabled) {
      if (widget.state.geminiApiKey.trim().isEmpty) {
        onlineFailure = 'Gemini API key is missing.';
      } else {
        try {
          final audio = await _geminiSpeech.synthesize(
            text: text,
            apiKey: widget.state.geminiApiKey,
            locale: widget.state.language,
            style: GeminiExpressiveSpeechSynthesizer.styleFor(
              widget.state.geminiTtsExpression,
            ),
          );
          if (!mounted) return false;
          setState(() => speaking = true);
          await _playAssistantAudio(audio);
          return true; // Native completion event resets speaking after playback.
        } catch (error) {
          onlineFailure = error.toString();
        }
      }
    }
    if (!forceLocal &&
        onlineFailure == null &&
        widget.state.azureSpeechEnabled &&
        widget.state.engine != 'offline') {
      if (widget.state.azureSpeechApiKey.isEmpty ||
          widget.state.azureSpeechRegion.isEmpty) {
        onlineFailure = 'Azure key or region is missing.';
      } else if (!AzureSpeechSynthesizer.supportedLocales.contains(
        widget.state.language,
      )) {
        onlineFailure = 'Azure online voice supports English and Hindi only.';
      } else {
        try {
          final audio = await _azureSpeech.synthesize(
            text: text,
            apiKey: widget.state.azureSpeechApiKey,
            region: widget.state.azureSpeechRegion,
            locale: widget.state.language,
            rate: widget.state.speechRate,
          );
          if (!mounted) return false;
          setState(() => speaking = true);
          await _playAssistantAudio(audio);
          return true; // Native completion event resets speaking after the audio ends.
        } catch (error) {
          onlineFailure = error.toString();
        }
      }
    }

    try {
      if (await tts.isLanguageAvailable(widget.state.language) != true) {
        throw StateError('Selected speech language is unavailable');
      }
      final voices = await tts.getVoices as List;
      final localVoice = selectInstalledOfflineVoice(
        voices,
        widget.state.language,
        preferredName: widget.state.speechVoiceName,
        preferredLocale: widget.state.speechVoiceLocale,
      );
      if (localVoice == null) {
        throw StateError('No installed Android voice is available');
      }
      await tts.setLanguage(widget.state.language);
      await tts.setVoice({
        'name': localVoice['name'].toString(),
        'locale': localVoice['locale'].toString(),
      });
      await tts.setSpeechRate(widget.state.speechRate);
      await tts.awaitSpeakCompletion(true);
      if (!mounted) return false;
      setState(() => speaking = true);
      await tts.speak(text);
      if (onlineFailure != null && mounted) {
        notice(
          context,
          '$onlineFailure Using the installed Android voice instead.',
        );
      }
      return true;
    } catch (_) {
      if (mounted) {
        final reason = onlineFailure == null ? '' : '$onlineFailure ';
        notice(
          context,
          '${reason}No installed Android voice could play this reply. It remains readable; no other online provider was used.',
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => speaking = false);
    }
  }

  Future<void> _openConversationHistory() async {
    try {
      final rows = await widget.state.conversations();
      if (!mounted) return;
      final selected = await showDialog<String>(
        context: context,
        builder: (dialogContext) => SimpleDialog(
          title: const Text('Conversation history'),
          children: rows.isEmpty
              ? const [
                  Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No saved conversations yet.'),
                  ),
                ]
              : rows
                    .map(
                      (row) => SimpleDialogOption(
                        onPressed: () => Navigator.pop(
                          dialogContext,
                          row['conversation'] as String,
                        ),
                        child: Text(
                          row['title'] as String? ?? 'Conversation',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
        ),
      );
      if (selected == null || !mounted) return;
      await widget.state.selectConversation(selected);
      if (mounted) _scrollToLatest(jump: true);
    } catch (error) {
      if (mounted) notice(context, error);
    }
  }

  Future<void> _startNewConversation() async {
    try {
      await widget.state.selectConversation(
        'chat_${DateTime.now().microsecondsSinceEpoch}',
        load: false,
      );
      if (mounted) _scrollToLatest(jump: true);
    } catch (error) {
      if (mounted) notice(context, error);
    }
  }

  Future<void> _pickChatAttachment() async {
    if (_chatFeatureBusy) return;
    try {
      final result = await AssistantState.device
          .invokeMapMethod<String, dynamic>('pick_file', {'ai_document': true});
      if (result == null || !mounted) return;
      final mime = result['mime'];
      final encoded = result['content_base64'];
      final name = result['name'];
      if (mime is! String || encoded is! String || name is! String) {
        throw FeatureServiceException(
          (result['unsupported'] as String?) ??
              'Choose a PDF or PNG, JPEG or WebP image.',
        );
      }
      final bytes = base64Decode(encoded);
      if (!supportedAiDocumentMimes.contains(mime) ||
          bytes.isEmpty ||
          bytes.lengthInBytes > maxAiDocumentBytes) {
        bytes.fillRange(0, bytes.length, 0);
        throw const FeatureServiceException(
          'Choose a non-empty PDF or PNG, JPEG or WebP image under 12 MB.',
        );
      }
      _chatAttachmentBytes?.fillRange(0, _chatAttachmentBytes!.length, 0);
      setState(() {
        _chatAttachmentBytes = bytes;
        _chatAttachmentName = name;
        _chatAttachmentMime = mime;
        _chatWebSearch = false;
        _chatFeatureError = '';
      });
    } on PlatformException catch (error) {
      if (mounted && error.code != 'cancelled') {
        setState(
          () => _chatFeatureError =
              error.message ?? 'Could not open the file picker.',
        );
      }
    } catch (error) {
      if (mounted) setState(() => _chatFeatureError = error.toString());
    }
  }

  void _removeChatAttachment() {
    _chatAttachmentBytes?.fillRange(0, _chatAttachmentBytes!.length, 0);
    setState(() {
      _chatAttachmentBytes = null;
      _chatAttachmentName = '';
      _chatAttachmentMime = '';
      _chatFeatureError = '';
    });
  }

  GeminiFeatureClient? _chatFeatureClient() {
    final state = widget.state;
    if (state.chatMode != 'online' || state.engine != 'gemini') {
      setState(
        () => _chatFeatureError = 'Chat attachments and web search need Online chat with Gemini. Nothing was sent; change the provider in Settings.',
      );
      return null;
    }
    if (state.geminiApiKey.trim().isEmpty) {
      setState(
        () => _chatFeatureError = 'Add a Gemini API key in Settings before using this online feature. Nothing was sent.',
      );
      return null;
    }
    return GeminiFeatureClient(
      model: state.geminiModelSelection,
      apiKey: state.geminiApiKey,
      clientFactory: state.clientFactory,
    );
  }

  Future<void> _sendChatFeature() async {
    if (_chatFeatureBusy) return;
    final text = input.text.trim();
    final attachment = _chatAttachmentBytes;
    if (attachment == null && text.isEmpty) {
      setState(
        () => _chatFeatureError =
            'Enter a question or topic before starting web research.',
      );
      return;
    }
    final client = _chatFeatureClient();
    if (client == null) return;
    final isResearch = _chatWebSearch;
    final prompt = text.isNotEmpty
        ? text
        : 'Explain this ${_chatAttachmentMime == 'application/pdf' ? 'document' : 'image'} clearly and summarize the important details.';
    final disclosure = isResearch
        ? '''Your exact question will be sent online to Google Gemini with Google Search grounding. Google handles it under its service terms; usage may incur charges. Web pages and search results are treated as untrusted source material, not instructions. Continue?

“$prompt”'''
        : '''“$_chatAttachmentName” and your question will be sent online to Google Gemini (${client.model}) for analysis. Google handles the content under its service terms; usage may incur charges. The file stays temporarily in this chat composer and is not saved in chat history. Continue?

“$prompt”''';
    final approved =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(
              isResearch
                  ? 'Search the web with Gemini?'
                  : 'Send this file to Gemini?',
            ),
            content: Text(disclosure),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Send to Gemini'),
              ),
            ],
          ),
        ) ??
        false;
    if (!approved || !mounted) return;
    setState(() {
      _chatFeatureBusy = true;
      _chatFeatureError = '';
    });
    try {
      final answer = isResearch
          ? await client.research(prompt)
          : await client.askDocument(
              mimeType: _chatAttachmentMime,
              bytes: attachment!,
              prompt: prompt,
            );
      if (!mounted) return;
      final sources = answer.sources
          .map(
            (source) => {
              'title': source.title,
              'url': source.uri.toString(),
              'supportingText': source.supportingText,
            },
          )
          .toList(growable: false);
      final nowState = widget.state;
      await nowState.addFeatureExchange(
        userText: prompt,
        answerText: answer.text,
        feature: isResearch ? 'web_research' : 'file_analysis',
        sources: isResearch ? sources : const [],
        searchQueries: isResearch ? answer.searchQueries : const [],
        attachmentName: isResearch ? null : _chatAttachmentName,
      );
      nowState.lastPrompt = prompt;
      input.clear();
      if (!isResearch) _removeChatAttachment();
      if (isResearch) setState(() => _chatWebSearch = false);
    } catch (error) {
      if (mounted) setState(() => _chatFeatureError = error.toString());
    } finally {
      if (mounted) setState(() => _chatFeatureBusy = false);
    }
  }

  Future<void> _openGoogleAiMode() async {
    if (_chatFeatureBusy) return;
    try {
      await _assistantWebSearchChannel.invokeMethod<void>(
        'open_google_ai_mode',
      );
      if (mounted) {
        notice(
          context,
          'Google AI Mode opened outside the app. Your draft was not sent; enter the question there. Its answer will not appear in this chat.',
        );
      }
    } on PlatformException catch (error) {
      if (mounted) {
        setState(
          () => _chatFeatureError =
              error.message ?? 'Google AI Mode could not be opened.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _chatFeatureError =
              'Google AI Mode is available only on Android in this app.',
        );
      }
    }
  }

  Future<void> _openResearchSource(String rawUrl, String title) async {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      notice(context, 'This source link is not a valid HTTPS address.');
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => _ChatResearchSourcePage(uri: uri, title: title),
      ),
    );
  }

  Future<void> send([String? retry]) async {
    final text = retry ?? input.text;
    final jeeRequest = JeeQuestionRequest.fromMessage(text);
    if (jeeRequest != null &&
        (_chatAttachmentBytes != null || _chatWebSearch)) {
      notice(
        context,
        'Clear the attachment or web-search option before starting JEE practice.',
      );
      return;
    }
    if (retry == null && (_chatAttachmentBytes != null || _chatWebSearch)) {
      await _sendChatFeature();
      return;
    }
    if (text.trim().isEmpty) {
      return;
    }
    final generatedPrompt = jeeRequest?.buildPrompt();
    if (generatedPrompt != null) {
      if (generatedPrompt.length > 5000) {
        notice(
          context,
          'Shorten the topic so the reviewed practice prompt stays within the safe prompt-size limit.',
        );
        return;
      }
      final approved =
          await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Review JEE practice prompt'),
              scrollable: true,
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'This generated prompt will be sent to your selected online provider (${widget.state.engine}, ${widget.state.model}). Provider services may retain it or charge your account. It will not include chat history or saved memories. The questions are newly generated practice, not verified past-year questions.',
                  ),
                  const SizedBox(height: 12),
                  SelectableText(generatedPrompt),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Send reviewed prompt'),
                ),
              ],
            ),
          ) ??
          false;
      if (!approved || !mounted) return;
    }
    await AssistantState.device.invokeMethod('voice_cancel');
    await tts.stop();
    if (speaking) await stopExpressiveAudio();
    if (mounted) {
      setState(() => listening = false);
    }
    if (!mounted) return;
    final priorUserMessageCount = widget.state.messages
        .where((message) => message['role'] == 'user')
        .length;
    final priorPrompt = widget.state.lastPrompt;
    final speakThisReply =
        widget.state.speakReplies || _speakNextReply || _handsFreeSessionActive;
    _speakNextReply = false;
    final studyModeForRequest = widget.state.studyModeEnabled;
    await widget.state.send(
      text,
      providerMessageOverride: generatedPrompt,
      shareMemories: jeeRequest == null && widget.state.shareMemories,
      shareHistory: jeeRequest == null && widget.state.shareHistory,
      retryLastMessage: retry != null,
      spokenConversation: speakThisReply,
    );
    final lessonId = widget.state.lastStudyLessonId;
    if (studyModeForRequest && lessonId != null && mounted) {
      await Navigator.pushNamed(context, '/whiteboard', arguments: lessonId);
    }
    final currentUserMessageCount = widget.state.messages
        .where((message) => message['role'] == 'user')
        .length;
    if (currentUserMessageCount > priorUserMessageCount ||
        (retry != null && text.trim() == priorPrompt)) {
      input.clear();
    }
    if (speakThisReply &&
        widget.state.error.isEmpty &&
        widget.state.messages.isNotEmpty &&
        mounted) {
      final last = widget.state.messages.last;
      if (last['role'] == 'assistant' && last['state'] == 'complete') {
        final played = await playReplyVoice(last['text'] as String);
        if (_handsFreeSessionActive) {
          if (played) {
            final started = await _listenOnce(handsFreeSession: true);
            if (!started && _handsFreeSessionActive) {
              await _endHandsFreeSession();
            }
          } else {
            await _endHandsFreeSession();
          }
        }
      } else if (_handsFreeSessionActive) {
        await _endHandsFreeSession();
      }
    } else if (_handsFreeSessionActive) {
      await _endHandsFreeSession();
    }
  }

  @override
  void dispose() {
    _chatAttachmentBytes?.fillRange(0, _chatAttachmentBytes!.length, 0);
    WidgetsBinding.instance.removeObserver(this);
    if (_liveConversationActive || _liveConversationStarting) {
      unawaited(_endLiveConversation());
    }
    widget.state.removeListener(_chatStateChanged);
    _assistantAudioPlaying.removeListener(_audioPlaybackChanged);
    _chatScrollController.dispose();
    voiceEvents.setMethodCallHandler(null);
    if (speaking) unawaited(stopExpressiveAudio());
    _deepgramLimit?.cancel();
    unawaited(_deepgramSubscription?.cancel());
    unawaited(_deepgramRecorder.dispose());
    _deepgram.cancel();
    AssistantState.device.invokeMethod('voice_cancel');
    tts.stop();
    widget.state.stop(notify: false);
    input.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.state,
    builder: (context, _) {
      final state = widget.state;
      return Shell(
        title: state.assistantName,
        assistantName: state.assistantName,
        contentMaxWidth: 1280,
        showBottomNavigation: false,
        actions: [
          IconButton(
            key: const ValueKey('study-mode-toggle'),
            tooltip: state.studyModeEnabled
                ? 'Study Mode on · tap to turn off'
                : 'Study Mode off · tap to send lessons to Whiteboard',
            onPressed: () async {
              try {
                await state.saveStudyModeEnabled(!state.studyModeEnabled);
                if (context.mounted) {
                  notice(
                    context,
                    state.studyModeEnabled
                        ? 'Study Mode is on. Topic replies will open on Whiteboard.'
                        : 'Study Mode is off. Replies stay in chat.',
                  );
                }
              } catch (error) {
                if (context.mounted) notice(context, error);
              }
            },
            icon: Icon(
              state.studyModeEnabled
                  ? Icons.school_rounded
                  : Icons.school_outlined,
              color: state.studyModeEnabled
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
          ),
          IconButton(
            key: const ValueKey('chat-history-button'),
            tooltip: 'Conversation history',
            onPressed: _openConversationHistory,
            icon: const Icon(Icons.history_rounded),
          ),
          IconButton(
            key: const ValueKey('new-conversation-button'),
            tooltip: 'New conversation',
            onPressed: _startNewConversation,
            icon: const Icon(Icons.add_comment_outlined),
          ),
        ],
        child: Column(
          children: [
            Expanded(
              child: ListView(
                controller: _chatScrollController,
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
                children: [
                  if (state.messages.isEmpty)
                    Glass(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const HolographicAssistantOrb(size: 146),
                          const SizedBox(height: 2),
                          Text(
                            'Start with a thought, a question, or a plan.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Your assistant is ready when you are.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                  for (final m in state.messages)
                    SoftEntrance(
                      child: Align(
                        alignment: m['role'] == 'user'
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1180),
                          child: Glass(
                            tintColor: m['role'] == 'user'
                                ? Theme.of(context).colorScheme.primary
                                : null,
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  m['role'] == 'user'
                                      ? 'YOU'
                                      : state.assistantName,
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                                if (m['feature'] == 'web_research')
                                  const _ChatFeatureBadge(
                                    label: 'WEB RESEARCH',
                                  ),
                                if (m['feature'] == 'file_analysis')
                                  const _ChatFeatureBadge(
                                    label: 'FILE ANALYSIS',
                                  ),
                                if (m['attachmentName'] is String)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 5),
                                    child: Text(
                                      'Attached: ${m['attachmentName']}',
                                    ),
                                  ),
                                const SizedBox(height: 6),
                                MarkdownBody(
                                  data: ReadableMath.formatMarkdown(
                                    m['text'] as String,
                                  ),
                                  selectable: true,
                                  imageBuilder: (_, _, _) => const Text(
                                    '[Remote image blocked — no automatic network fetch]',
                                  ),
                                  onTapLink: (_, _, _) => notice(
                                    context,
                                    'Links are not opened automatically. Review and copy the destination if needed.',
                                  ),
                                ),
                                if (m['feature'] == 'web_research' &&
                                    m['role'] == 'assistant')
                                  _ChatResearchSources(
                                    sources: (m['sources'] as List? ?? const [])
                                        .whereType<Map>()
                                        .map(
                                          (source) =>
                                              Map<String, dynamic>.from(source),
                                        )
                                        .toList(growable: false),
                                    onOpen: _openResearchSource,
                                    searchQueries:
                                        (m['searchQueries'] as List? ??
                                                const [])
                                            .whereType<String>()
                                            .toList(growable: false),
                                  ),
                                if (m['feature'] == 'web_research' &&
                                    m['role'] == 'assistant' &&
                                    (m['sources'] as List? ?? const []).isEmpty)
                                  const Text(
                                    'No source citations were returned. Treat this as an uncited model response, not verified web research.',
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
                    ),
                  if (state.busy) ...[
                    if (state.partial.trim().isNotEmpty)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1180),
                          child: Glass(
                            padding: const EdgeInsets.all(12),
                            bottomSpacing: 8,
                            child: SelectableText(
                              ReadableMath.formatMarkdown(state.partial),
                            ),
                          ),
                        ),
                      ),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: EdgeInsets.only(bottom: 14),
                        child: GlassTypingIndicator(),
                      ),
                    ),
                  ],
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
            if (listening || state.busy || speaking || _handsFreeSessionActive)
              Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 2),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    HolographicAssistantOrb(
                      state: listening
                          ? HolographicOrbState.listening
                          : state.busy
                          ? HolographicOrbState.thinking
                          : HolographicOrbState.speaking,
                      size: 92,
                      audioLevel: level,
                    ),
                    const SizedBox(height: 1),
                    Text(
                      listening
                          ? 'Listening'
                          : _handsFreeSessionActive && !state.busy && !speaking
                          ? 'Hands-free session · review each transcript'
                          : state.busy
                          ? 'Thinking'
                          : 'Speaking',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        letterSpacing: .35,
                      ),
                    ),
                  ],
                ),
              ),
            AnimatedSwitcher(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 240),
              transitionBuilder: (child, animation) => SizeTransition(
                sizeFactor: animation,
                alignment: Alignment.topCenter,
                child: FadeTransition(opacity: animation, child: child),
              ),
              child: listening
                  ? Padding(
                      key: const ValueKey('listening'),
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
                      child: Glass(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        bottomSpacing: 0,
                        child: Row(
                          children: [
                            Icon(
                              Icons.mic_rounded,
                              color: Theme.of(context).colorScheme.primary,
                              size: 18,
                            ),
                            const SizedBox(width: 10),
                            const Text('Microphone on · listening'),
                            const Spacer(),
                            SizedBox(
                              width: 110,
                              height: 28,
                              child: CustomPaint(
                                painter: WavePainter(
                                  level,
                                  Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : const SizedBox(key: ValueKey('not-listening')),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 2, 12, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_chatAttachmentBytes != null)
                    Card(
                      margin: const EdgeInsets.only(bottom: 6),
                      child: ListTile(
                        dense: true,
                        leading: _chatAttachmentMime.startsWith('image/')
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: Image.memory(
                                  _chatAttachmentBytes!,
                                  width: 42,
                                  height: 42,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) =>
                                      const Icon(Icons.broken_image_outlined),
                                ),
                              )
                            : const Icon(Icons.picture_as_pdf_outlined),
                        title: Text(
                          _chatAttachmentName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '$_chatAttachmentMime · ${(_chatAttachmentBytes!.lengthInBytes / 1024 / 1024).toStringAsFixed(1)} MB',
                        ),
                        trailing: IconButton(
                          tooltip: 'Remove attachment',
                          onPressed: _chatFeatureBusy
                              ? null
                              : _removeChatAttachment,
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ),
                    ),
                  Row(
                    key: const ValueKey('chat-feature-actions'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton.filledTonal(
                        tooltip: 'Attach image or file',
                        constraints: const BoxConstraints.tightFor(
                          width: 48,
                          height: 48,
                        ),
                        onPressed: _chatFeatureBusy
                            ? null
                            : _pickChatAttachment,
                        icon: const Icon(Icons.attach_file_rounded),
                      ),
                      const SizedBox(width: 4),
                      IconButton.filledTonal(
                        tooltip: 'Search web',
                        isSelected: _chatWebSearch,
                        selectedIcon: const Icon(Icons.travel_explore_rounded),
                        constraints: const BoxConstraints.tightFor(
                          width: 48,
                          height: 48,
                        ),
                        onPressed:
                            _chatFeatureBusy || _chatAttachmentBytes != null
                            ? null
                            : () => setState(() {
                                _chatWebSearch = !_chatWebSearch;
                                _chatFeatureError = '';
                              }),
                        icon: const Icon(Icons.travel_explore_rounded),
                      ),
                      const SizedBox(width: 4),
                      IconButton.filledTonal(
                        tooltip: 'JEE practice',
                        constraints: const BoxConstraints.tightFor(
                          width: 48,
                          height: 48,
                        ),
                        onPressed: _chatFeatureBusy
                            ? null
                            : () {
                                input.value = const TextEditingValue(
                                  text: '/jee ',
                                  selection: TextSelection.collapsed(offset: 5),
                                );
                                _inputFocus.requestFocus();
                              },
                        icon: const Icon(Icons.school_rounded),
                      ),
                      const SizedBox(width: 4),
                      IconButton.filledTonal(
                        tooltip: 'Google AI Mode',
                        constraints: const BoxConstraints.tightFor(
                          width: 48,
                          height: 48,
                        ),
                        onPressed: _chatFeatureBusy ? null : _openGoogleAiMode,
                        icon: const Icon(Icons.open_in_new_rounded),
                      ),
                      if (_chatFeatureBusy) ...[
                        const SizedBox(width: 8),
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ],
                    ],
                  ),
                  if (_chatFeatureError.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        _chatFeatureError,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
              child: Glass(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                bottomSpacing: 0,
                borderRadius: BorderRadius.circular(28),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    ActivityHalo(
                      active:
                          listening ||
                          _handsFreeSessionActive ||
                          _liveConversationActive ||
                          _liveConversationStarting,
                      color: Theme.of(context).colorScheme.primary,
                      child: IconButton.filledTonal(
                        tooltip:
                            _liveConversationActive || _liveConversationStarting
                            ? 'Stop Live Conversation'
                            : _handsFreeSessionActive
                            ? 'End hands-free session'
                            : widget.state.voiceConversationMode == 'hands_free'
                            ? 'Start hands-free session'
                            : listening
                            ? 'Stop microphone'
                            : 'Use microphone',
                        onPressed: listen,
                        icon: AnimatedSwitcher(
                          duration: MediaQuery.disableAnimationsOf(context)
                              ? Duration.zero
                              : const Duration(milliseconds: 220),
                          transitionBuilder: (child, animation) =>
                              ScaleTransition(
                                scale: animation,
                                child: RotationTransition(
                                  turns: Tween<double>(
                                    begin: -.08,
                                    end: 0,
                                  ).animate(animation),
                                  child: child,
                                ),
                              ),
                          child: Icon(
                            _liveConversationActive ||
                                    _liveConversationStarting ||
                                    _handsFreeSessionActive
                                ? Icons.stop_circle_rounded
                                : listening
                                ? Icons.mic_rounded
                                : Icons.mic_none_rounded,
                            key: ValueKey((
                              listening,
                              _handsFreeSessionActive,
                              _liveConversationActive,
                              _liveConversationStarting,
                            )),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: TextField(
                        controller: input,
                        focusNode: _inputFocus,
                        minLines: 1,
                        maxLines: 5,
                        maxLength: 8000,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          hintText: 'Message your assistant…',
                          filled: false,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 10,
                          ),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          counterText: '',
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    ActivityHalo(
                      active: state.busy || speaking,
                      color: Theme.of(context).colorScheme.tertiary,
                      strength: .9,
                      child: IconButton.filled(
                        tooltip: state.busy || speaking
                            ? 'Stop response'
                            : 'Send message',
                        onPressed: state.busy || speaking || _chatFeatureBusy
                            ? stopAll
                            : send,
                        style: IconButton.styleFrom(
                          fixedSize: const Size(48, 48),
                          backgroundColor: Theme.of(context)
                              .colorScheme
                              .primary,
                          foregroundColor: Theme.of(context)
                              .colorScheme
                              .onPrimary,
                        ),
                        icon: AnimatedSwitcher(
                          duration: MediaQuery.disableAnimationsOf(context)
                              ? Duration.zero
                              : const Duration(milliseconds: 220),
                          transitionBuilder: (child, animation) =>
                              ScaleTransition(
                                scale: animation,
                                child: RotationTransition(
                                  turns: Tween<double>(
                                    begin: -.10,
                                    end: 0,
                                  ).animate(animation),
                                  child: child,
                                ),
                              ),
                          child: Icon(
                            state.busy || speaking
                                ? Icons.stop_rounded
                                : Icons.arrow_upward_rounded,
                            key: ValueKey(state.busy || speaking),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _ChatFeatureBadge extends StatelessWidget {
  final String label;
  const _ChatFeatureBadge({required this.label});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Chip(
      visualDensity: VisualDensity.compact,
      avatar: const Icon(Icons.verified_outlined, size: 16),
      label: Text(label),
    ),
  );
}

class _ChatResearchSources extends StatelessWidget {
  final List<Map<String, dynamic>> sources;
  final List<String> searchQueries;
  final Future<void> Function(String, String) onOpen;
  const _ChatResearchSources({
    required this.sources,
    required this.searchQueries,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    if (sources.isEmpty && searchQueries.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (searchQueries.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.only(top: 10, bottom: 4),
            child: Text('Google Search queries used'),
          ),
          for (final query in searchQueries)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text('· $query'),
            ),
        ],
        if (sources.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.only(top: 10, bottom: 4),
            child: Text('Sources returned by Google Search'),
          ),
        ],
        for (final source in sources)
          Builder(
            builder: (context) {
              final title = source['title'] as String? ?? 'Source';
              final url = source['url'] as String? ?? '';
              final uri = Uri.tryParse(url);
              if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
                return const SizedBox.shrink();
              }
              final excerpt = source['supportingText'] as String? ?? '';
              return TextButton.icon(
                onPressed: () => onOpen(url, title),
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: Text(
                  excerpt.isEmpty
                      ? '$title · ${uri.host}'
                      : '$title · ${uri.host}\n$excerpt',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              );
            },
          ),
      ],
    );
  }
}

class _ChatResearchSourcePage extends StatefulWidget {
  final Uri uri;
  final String title;
  const _ChatResearchSourcePage({required this.uri, required this.title});

  @override
  State<_ChatResearchSourcePage> createState() =>
      _ChatResearchSourcePageState();
}

class _ChatResearchSourcePageState extends State<_ChatResearchSourcePage> {
  late final WebViewController _controller = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.disabled)
    ..setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: (request) {
          final uri = Uri.tryParse(request.url);
          return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty
              ? NavigationDecision.navigate
              : NavigationDecision.prevent;
        },
      ),
    )
    ..loadRequest(widget.uri);

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
    ),
    body: WebViewWidget(controller: _controller),
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

/// Interactive theme choices; palette selection applies and saves immediately.
class FuturisticThemePicker extends StatelessWidget {
  final AssistantState state;
  const FuturisticThemePicker({super.key, required this.state});

  Future<void> _choose(BuildContext context, String id) async {
    try {
      await state.setVisualTheme(id);
    } catch (_) {
      if (context.mounted) {
        notice(context, 'The visual theme could not be saved on this phone.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.palette_outlined, color: theme.colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Choose your visual universe',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Colors flow through the orb, glass and ambient light.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth < 300 ? 2 : 3;
            final itemWidth =
                (constraints.maxWidth - (columns - 1) * 8) / columns;
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final palette in FuturisticPalette.all)
                  SizedBox(
                    width: itemWidth,
                    child: _FuturisticThemeChoice(
                      palette: palette,
                      selected: state.visualTheme == palette.id,
                      onTap: () => _choose(context, palette.id),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _FuturisticThemeChoice extends StatelessWidget {
  final FuturisticPalette palette;
  final bool selected;
  final VoidCallback onTap;

  const _FuturisticThemeChoice({
    required this.palette,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return TapMotion(
      depth: 1.35,
      child: Semantics(
        button: true,
        selected: selected,
        label:
            '${palette.name}, ${palette.description}${selected ? ', selected' : ''}',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: ValueKey('theme-choice-${palette.id}'),
            onTap: onTap,
            borderRadius: BorderRadius.circular(20),
            child: AnimatedContainer(
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 360),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.fromLTRB(7, 9, 7, 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: selected
                      ? [
                          palette.primary.withValues(alpha: .30),
                          palette.secondary.withValues(alpha: .15),
                        ]
                      : [
                          palette.primary.withValues(alpha: .14),
                          palette.tertiary.withValues(alpha: .07),
                        ],
                ),
                border: Border.all(
                  color: selected
                      ? palette.primary.withValues(alpha: .88)
                      : Theme.of(context).colorScheme.outlineVariant
                            .withValues(alpha: .72),
                  width: selected ? 1.8 : 1,
                ),
                boxShadow: [
                  if (selected)
                    BoxShadow(
                      color: palette.primary.withValues(alpha: .26),
                      blurRadius: 22,
                      spreadRadius: -3,
                    ),
                ],
              ),
              child: ExcludeSemantics(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedScale(
                      scale: selected ? 1.08 : .92,
                      duration: reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 420),
                      curve: Curves.easeOutBack,
                      child: _PaletteOrbPreview(palette: palette),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      palette.name,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.fade,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontSize: 12,
                        fontWeight: selected
                            ? FontWeight.w800
                            : FontWeight.w600,
                        color: selected
                            ? palette.primaryFor(Theme.of(context).brightness)
                            : Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      palette.description,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.fade,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontSize: 9,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PaletteOrbPreview extends StatelessWidget {
  final FuturisticPalette palette;
  const _PaletteOrbPreview({required this.palette});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 48,
    height: 48,
    child: Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 46,
          height: 24,
          decoration: BoxDecoration(
            border: Border.all(color: palette.secondary.withValues(alpha: .62)),
            borderRadius: BorderRadius.circular(50),
            boxShadow: [
              BoxShadow(
                color: palette.secondary.withValues(alpha: .28),
                blurRadius: 9,
              ),
            ],
          ),
        ),
        Container(
          width: 31,
          height: 31,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              center: const Alignment(-.35, -.42),
              colors: [
                Colors.white.withValues(alpha: .98),
                palette.orbColors.first,
                palette.orbColors[1],
                const Color(0xff0a0d1b),
              ],
              stops: const [0, .17, .48, 1],
            ),
            boxShadow: [
              BoxShadow(
                color: palette.primary.withValues(alpha: .62),
                blurRadius: 15,
                spreadRadius: 1,
              ),
            ],
          ),
        ),
        Positioned(
          right: 5,
          top: 5,
          child: Container(
            width: 4,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: palette.secondary, blurRadius: 5)],
            ),
          ),
        ),
      ],
    ),
  );
}

class AndroidAccessPanel extends StatefulWidget {
  const AndroidAccessPanel({super.key});

  @override
  State<AndroidAccessPanel> createState() => _AndroidAccessPanelState();
}

class _AndroidAccessPanelState extends State<AndroidAccessPanel> {
  Map<String, dynamic>? _status;
  String? _loadingPermission;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final status = await AssistantState.device
          .invokeMapMethod<String, dynamic>('device_status');
      if (!mounted) return;
      setState(() {
        _status = status;
        _error = status == null
            ? 'Android access status is unavailable.'
            : null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _status = null;
        _error = 'Android access status is unavailable on this build.';
      });
    }
  }

  Future<void> _request(String permission) async {
    if (_loadingPermission != null) return;
    setState(() => _loadingPermission = permission);
    try {
      final result = await AssistantState.device
          .invokeMapMethod<String, dynamic>('request_access_permission', {
            'permission': permission,
          });
      await _refresh();
      if (!mounted) return;
      final granted = result?['granted'] == true;
      notice(
        context,
        granted
            ? '${permission == 'microphone' ? 'Microphone' : 'Notifications'} access is available.'
            : '${permission == 'microphone' ? 'Microphone' : 'Notifications'} access was not granted. You can keep using other features.',
      );
    } catch (error) {
      if (mounted) notice(context, error);
    } finally {
      if (mounted) setState(() => _loadingPermission = null);
    }
  }

  Widget _permissionRow({
    required String title,
    required String subtitle,
    required String permission,
    required bool granted,
  }) {
    final requesting = _loadingPermission == permission;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        granted ? Icons.check_circle_outline : Icons.radio_button_unchecked,
        color: granted ? Theme.of(context).colorScheme.primary : null,
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: granted
          ? const Text('Available')
          : TextButton(
              key: ValueKey('request-$permission'),
              onPressed: _loadingPermission == null
                  ? () => _request(permission)
                  : null,
              child: requesting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Request'),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sdk = _status?['sdk'];
    final microphoneGranted = _status?['microphone_granted'] == true;
    final notificationsGranted = _status?['notifications_granted'] == true;
    return Glass(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Android access', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          const Text(
            'Optional access is requested only when you tap Request. Typed chat needs neither permission. There is no always-listening microphone or blanket automation access.',
          ),
          const SizedBox(height: 8),
          _permissionRow(
            title: 'Microphone',
            subtitle: 'Only for voice input started by you.',
            permission: 'microphone',
            granted: microphoneGranted,
          ),
          _permissionRow(
            title: 'Notifications',
            subtitle: sdk is int && sdk < 33
                ? 'Not required on Android API $sdk.'
                : 'Used for reminders you prepare and approve.',
            permission: 'notifications',
            granted: notificationsGranted,
          ),
          const Text(
            'App launches and reminders stay individually approved. Accessibility, screen capture, and background automation are not enabled.',
          ),
          if (_error != null) ...[
            const SizedBox(height: 6),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _loadingPermission == null ? _refresh : null,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh access status'),
            ),
          ),
        ],
      ),
    );
  }
}

class ProviderProfilesEditor extends StatefulWidget {
  final AssistantState state;
  const ProviderProfilesEditor({super.key, required this.state});

  @override
  State<ProviderProfilesEditor> createState() => _ProviderProfilesEditorState();
}

class _ProviderProfilesEditorState extends State<ProviderProfilesEditor> {
  late final Map<String, TextEditingController> _origins = {
    for (final p in widget.state.providerProfiles)
      p.id: TextEditingController(text: p.origin),
  };
  late final Map<String, TextEditingController> _models = {
    for (final p in widget.state.providerProfiles)
      p.id: TextEditingController(text: p.model),
  };
  late final Map<String, TextEditingController> _keys = {
    for (final p in widget.state.providerProfiles)
      p.id: TextEditingController(),
  };
  final Set<String> _clearKeys = {};
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [..._origins.values, ..._models.values, ..._keys.values]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final profiles = [
        for (final p in widget.state.providerProfiles)
          p.copyWith(
            origin: _origins[p.id]!.text.trim(),
            model: _models[p.id]!.text.trim(),
            apiKey: _clearKeys.contains(p.id)
                ? ''
                : _keys[p.id]!.text.isEmpty
                ? p.apiKey
                : _keys[p.id]!.text.trim(),
          ),
      ];
      await widget.state.saveProviderProfiles(profiles);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        notice(context, error);
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Provider profiles'),
    scrollable: true,
    content: SizedBox(
      width: 520,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'These profiles are used only when you explicitly compare providers from Settings and approve that run. OpenAI API access is separate from a ChatGPT subscription. ElevenLabs is separate online speech, not a chat provider.',
          ),
          const SizedBox(height: 12),
          for (final p in widget.state.providerProfiles) ...[
            Text(p.name, style: Theme.of(context).textTheme.titleSmall),
            TextField(
              controller: _origins[p.id],
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'HTTPS API base'),
            ),
            TextField(
              controller: _models[p.id],
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(labelText: 'Model ID'),
            ),
            Text(
              'API key: ${p.apiKey.isEmpty ? 'Not set' : 'Saved securely on this phone'}',
            ),
            TextField(
              controller: _keys[p.id],
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              autofillHints: const [],
              decoration: const InputDecoration(
                labelText: 'New API key (leave blank to keep saved key)',
              ),
            ),
            if (p.apiKey.isNotEmpty)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _clearKeys.contains(p.id),
                onChanged: (clear) => setState(() {
                  if (clear == true) {
                    _clearKeys.add(p.id);
                    _keys[p.id]!.clear();
                  } else {
                    _clearKeys.remove(p.id);
                  }
                }),
                title: const Text('Clear saved key from this phone'),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            const Divider(height: 24),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: Text(_saving ? 'Saving…' : 'Save profiles'),
      ),
    ],
  );
}

class Settings extends StatefulWidget {
  final AssistantState state;
  const Settings({super.key, required this.state});
  @override
  State<Settings> createState() => _SettingsState();
}

class _SettingsState extends State<Settings> {
  static const _automaticVoiceKey = '__automatic_offline_voice__';
  final deepgramSecret = TextEditingController();
  final azureSpeechSecret = TextEditingController();
  late final TextEditingController azureSpeechRegion = TextEditingController(
    text: widget.state.azureSpeechRegion,
  );
  final FlutterTts _voicePreview = FlutterTts();
  late String speechMode = widget.state.speechMode;
  late String chatMode = widget.state.chatMode;
  late String voiceConversationMode = widget.state.voiceConversationMode;
  late double speechRate = widget.state.speechRate;
  late String theme = widget.state.theme;
  late String language = widget.state.language;
  late String responseStyle = widget.state.responseStyle;
  late String aiMode = widget.state.aiMode;
  late String? selectedVoiceName = widget.state.speechVoiceName;
  late String? selectedVoiceLocale = widget.state.speechVoiceLocale;
  List<Map<String, dynamic>> _offlineVoices = [];
  bool _loadingOfflineVoices = false;
  bool _previewingVoice = false;
  bool _playingExpressiveVoice = false;
  bool _comparingProviders = false;
  final TextEditingController _comparisonPrompt = TextEditingController();
  late final TextEditingController name = TextEditingController(
    text: widget.state.assistantName,
  );
  @override
  void initState() {
    super.initState();
    widget.state.addListener(_stateChanged);
    _assistantAudioPlaying.addListener(_expressiveAudioChanged);
    _loadOfflineVoices(language);
  }

  void _stateChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _chooseLauncherIcon() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Home-screen app icon'),
        content: SizedBox(
          width: 360,
          height: MediaQuery.sizeOf(context).height * .6,
          child: GridView.count(
            shrinkWrap: true,
            crossAxisCount: 3,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            children: [
              for (final entry in AssistantState.launcherIconAssets.entries)
                InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => Navigator.pop(dialogContext, entry.key),
                  child: Column(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              width: widget.state.launcherIconId == entry.key
                                  ? 3
                                  : 1,
                              color: widget.state.launcherIconId == entry.key
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).dividerColor,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(13),
                            child: Image.asset(entry.value, fit: BoxFit.cover),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        AssistantState.launcherIconLabels[entry.key]!,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'nexa_1'),
            child: const Text('Restore default'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    try {
      await widget.state.saveLauncherIcon(choice);
    } catch (error) {
      if (mounted) notice(context, error);
    }
  }

  void _expressiveAudioChanged() {
    if (mounted && _playingExpressiveVoice != _assistantAudioPlaying.value) {
      setState(() => _playingExpressiveVoice = _assistantAudioPlaying.value);
    }
  }

  Future<void> _openConversationHistory() async {
    try {
      final rows = await widget.state.conversations();
      if (!mounted) return;
      final selected = await showDialog<String>(
        context: context,
        builder: (dialogContext) => SimpleDialog(
          title: const Text('Conversation history'),
          children: rows.isEmpty
              ? const [
                  Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No saved conversations yet.'),
                  ),
                ]
              : rows
                    .map(
                      (row) => SimpleDialogOption(
                        onPressed: () => Navigator.pop(
                          dialogContext,
                          row['conversation'] as String,
                        ),
                        child: Text(
                          row['title'] as String? ?? 'Conversation',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
        ),
      );
      if (selected == null || !mounted) return;
      await widget.state.selectConversation(selected);
      if (mounted) Navigator.pushReplacementNamed(context, '/chat');
    } catch (error) {
      if (mounted) notice(context, error);
    }
  }

  Future<void> _startNewConversation() async {
    try {
      await widget.state.selectConversation(
        'chat_${DateTime.now().microsecondsSinceEpoch}',
        load: false,
      );
      if (mounted) Navigator.pushReplacementNamed(context, '/chat');
    } catch (error) {
      if (mounted) notice(context, error);
    }
  }

  Future<void> _setGeminiCloudSpeech(bool enabled) async {
    if (!enabled) {
      try {
        await widget.state.saveGeminiTtsEnabled(false);
      } catch (error) {
        if (mounted) notice(context, error);
      }
      return;
    }
    if (widget.state.geminiApiKey.trim().isEmpty) {
      notice(context, 'Save a Gemini API key in API settings first.');
      return;
    }
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Enable Gemini expressive speech?'),
        content: const Text(
          'When spoken replies are played, this sends their exact text to Google Gemini TTS and receives audio. Your saved Gemini API key is used. API usage may incur charges; check your Google account’s quota and billing. Google’s current terms say unpaid Gemini API quota content and responses may be used to improve Google products; paid-quota prompts and responses are not used for that purpose. This setting is off by default and can be turned off anytime. No request is made until you enable it and ask for a spoken reply.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Enable cloud speech'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    try {
      await widget.state.saveGeminiTtsEnabled(true);
    } catch (error) {
      if (mounted) notice(context, error);
    }
  }

  Future<void> _generateLatestExpressiveVoice() async {
    final latest = widget.state.messages.reversed
        .where(
          (message) =>
              message['role'] == 'assistant' && message['state'] == 'complete',
        )
        .firstOrNull;
    final text = latest?['text'] as String?;
    if (text == null || text.trim().isEmpty) {
      notice(context, 'There is no completed assistant reply to play yet.');
      return;
    }
    var style = 'neutral';
    final approved = await showDialog<bool>(
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
                'This sends the exact selected reply text to your private service and then to ElevenLabs. ElevenLabs retains text and generated-audio history by default; Zero Retention is available only to some Enterprise accounts. Avoid private text unless you accept this retention. It may use credits from the account configured on that service. Nothing is generated until you confirm here.',
              ),
              const SizedBox(height: 12),
              const Text('Exact reply text:'),
              const SizedBox(height: 4),
              SelectableText(text),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: style,
                decoration: const InputDecoration(labelText: 'Expression'),
                items: const [
                  DropdownMenuItem(value: 'neutral', child: Text('Natural')),
                  DropdownMenuItem(value: 'curious', child: Text('Curious')),
                  DropdownMenuItem(value: 'crying', child: Text('Crying')),
                  DropdownMenuItem(
                    value: 'mischievous',
                    child: Text('Mischievous'),
                  ),
                  DropdownMenuItem(
                    value: 'whispering',
                    child: Text('Whispering'),
                  ),
                  DropdownMenuItem(value: 'shouting', child: Text('Shouting')),
                  DropdownMenuItem(value: 'laughing', child: Text('Laughing')),
                  DropdownMenuItem(value: 'sighing', child: Text('Sighing')),
                ],
                onChanged: (value) =>
                    setDialogState(() => style = value ?? 'neutral'),
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
    );
    if (approved != true || !mounted) return;
    setState(() => _playingExpressiveVoice = true);
    try {
      final audio = await widget.state.synthesizeElevenLabs(text, style);
      if (!mounted) return;
      await _playAssistantAudio(audio);
    } catch (error) {
      if (mounted) {
        setState(() => _playingExpressiveVoice = false);
        if (error is! PlatformException || error.code != 'cancelled') {
          notice(context, error);
        }
      }
    }
  }

  Future<void> _compareAisFromSettings() async {
    if (_comparingProviders) return;
    final configured = widget.state.providerProfiles
        .where((profile) => profile.isConfigured)
        .toList();
    if (configured.length < 2) {
      notice(
        context,
        'Configure at least two provider profiles in Settings > API & MCP connections first.',
      );
      return;
    }
    _comparisonPrompt.clear();
    final ids = <String>{};
    final selectedIds = await showDialog<List<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Review AI comparison'),
          scrollable: true,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Choose two or more configured providers and enter the exact prompt. Each selected provider receives it directly.',
              ),
              const SizedBox(height: 10),
              for (final profile in widget.state.providerProfiles)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: ids.contains(profile.id),
                  onChanged: profile.isConfigured
                      ? (value) => setDialogState(() {
                          if (value == true) {
                            ids.add(profile.id);
                          } else {
                            ids.remove(profile.id);
                          }
                        })
                      : null,
                  title: Text(profile.name),
                  subtitle: Text(
                    profile.isConfigured
                        ? '${profile.model} · ${Uri.tryParse(profile.origin)?.host ?? 'endpoint'}'
                        : 'Not configured',
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              TextField(
                controller: _comparisonPrompt,
                onChanged: (_) => setDialogState(() {}),
                minLines: 2,
                maxLines: 5,
                maxLength: 8000,
                decoration: const InputDecoration(
                  labelText: 'Exact prompt to send',
                ),
              ),
              const Text(
                'Provider APIs may retain this prompt and charge your account. Nothing is sent until you choose Send to selected AIs; no retries or hidden fallback.',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed:
                  ids.length >= 2 && _comparisonPrompt.text.trim().isNotEmpty
                  ? () => Navigator.pop(dialogContext, ids.toList())
                  : null,
              child: const Text('Send to selected AIs'),
            ),
          ],
        ),
      ),
    );
    if (selectedIds == null || !mounted) return;
    final prompt = _comparisonPrompt.text;
    setState(() => _comparingProviders = true);
    try {
      final results = await widget.state.compareProviders(
        providerIds: selectedIds,
        prompt: prompt,
        approvedThisRun: true,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Comparison results'),
          scrollable: true,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final result in results) ...[
                Text(
                  result.providerName,
                  style: Theme.of(dialogContext).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                SelectableText(result.answer ?? result.error ?? 'No result.'),
                const Divider(height: 24),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (mounted) notice(context, error);
    } finally {
      if (mounted) setState(() => _comparingProviders = false);
    }
  }

  Future<void> _loadOfflineVoices(String locale) async {
    if (mounted) setState(() => _loadingOfflineVoices = true);
    try {
      final voices = await _voicePreview.getVoices as List;
      final installed = installedOfflineVoices(voices, locale);
      if (mounted) setState(() => _offlineVoices = installed);
    } catch (_) {
      if (mounted) setState(() => _offlineVoices = []);
    } finally {
      if (mounted) setState(() => _loadingOfflineVoices = false);
    }
  }

  Map<String, dynamic>? get _selectedOfflineVoice {
    for (final voice in _offlineVoices) {
      if (voice['name'] == selectedVoiceName &&
          voice['locale'] == selectedVoiceLocale) {
        return voice;
      }
    }
    return null;
  }

  Future<void> _previewInstalledVoice() async {
    if (_previewingVoice) {
      try {
        await _voicePreview.stop();
      } catch (_) {}
      if (mounted) setState(() => _previewingVoice = false);
      return;
    }
    final voice =
        _selectedOfflineVoice ??
        (_offlineVoices.isEmpty ? null : _offlineVoices.first);
    if (voice == null) {
      notice(context, 'No matching installed offline voice is available.');
      return;
    }
    final sample = switch (language) {
      'as-IN' => 'নমস্কাৰ, মই আপোনাৰ সহায়ক।',
      'hi-IN' => 'नमस्ते, मैं आपका सहायक हूँ।',
      'hi-Latn-IN' => 'Namaste, main aapka sahayak hoon.',
      _ => 'Hello, I am your assistant.',
    };
    setState(() => _previewingVoice = true);
    try {
      final voices = await _voicePreview.getVoices as List;
      final verified = selectInstalledOfflineVoice(
        voices,
        language,
        preferredName: voice['name']?.toString(),
        preferredLocale: voice['locale']?.toString(),
      );
      if (verified == null ||
          verified['name'] != voice['name'] ||
          verified['locale'] != voice['locale']) {
        throw StateError('The installed offline voice is no longer available.');
      }
      await _voicePreview.setLanguage(language);
      await _voicePreview.setVoice({
        'name': verified['name'].toString(),
        'locale': verified['locale'].toString(),
      });
      await _voicePreview.setSpeechRate(speechRate);
      await _voicePreview.awaitSpeakCompletion(true);
      await _voicePreview.speak(sample);
    } catch (_) {
      if (mounted) {
        notice(
          context,
          'This installed voice could not play the sample. Availability depends on the Android speech engine.',
        );
      }
    } finally {
      if (mounted) setState(() => _previewingVoice = false);
    }
  }

  @override
  void dispose() {
    widget.state.removeListener(_stateChanged);
    _assistantAudioPlaying.removeListener(_expressiveAudioChanged);
    if (_playingExpressiveVoice) unawaited(_stopAssistantAudio());
    unawaited(_voicePreview.stop().catchError((Object _) {}));
    deepgramSecret.dispose();
    azureSpeechSecret.dispose();
    azureSpeechRegion.dispose();
    name.dispose();
    _comparisonPrompt.dispose();
    super.dispose();
  }

  Future<void> _saveChatMode(String mode) async {
    try {
      await widget.state.saveChatMode(mode);
      if (mounted) setState(() => chatMode = mode);
    } catch (error) {
      if (mounted) notice(context, error);
    }
  }

  Future<void> _saveVoiceConversationMode(String mode) async {
    try {
      await widget.state.saveVoiceConversationMode(mode);
      if (!mounted) return;
      setState(() => voiceConversationMode = mode);
    } catch (error) {
      if (!mounted) return;
      notice(context, error);
    }
  }

  Future<void> _saveAiMode(String mode) async {
    try {
      await widget.state.saveAiMode(mode);
      if (mounted) setState(() => aiMode = mode);
    } catch (error) {
      if (mounted) notice(context, error);
    }
  }

  Future<void> _setExperimentalOfflineChat(bool enabled) async {
    if (enabled) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Try experimental offline chat?'),
          content: const Text(
            'Qwen3 0.6B downloads about 614 MB; Gemma 4 E2B downloads about 2.59 GB. Neither has been qualified for answer quality, speed, memory use or heat on this phone. Select a model, then download and load it yourself. Chat prompts and local conversation history stay on this phone; errors never switch to an online provider. Replies may be inaccurate or slow, and the phone may get warm. Continue only as an experiment.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Enable experimental chat'),
            ),
          ],
        ),
      );
      if (proceed != true || !mounted) return;
    }
    try {
      await widget.state.saveExperimentalOfflineChat(enabled);
      if (mounted) {
        notice(
          context,
          enabled
              ? 'Experimental offline chat is opted in. Choose, download and load a model below before chatting.'
              : 'Experimental local chat is off. The model is not used for normal chat.',
        );
      }
    } catch (error) {
      if (mounted) notice(context, error);
    }
  }

  Future<String?> _selectLocalBackup() async {
    try {
      return await AssistantState.device.invokeMethod<String>('import_backup');
    } on PlatformException catch (error) {
      if (error.code == 'cancelled') return null;
      rethrow;
    }
  }

  Future<void> _exportLocalBackup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Export a private backup?'),
        content: const Text(
          'This creates a readable, unencrypted JSON copy of supported on-phone records and your private note and assistant name. Provider credentials and service tokens are stored separately and are not included. Choose a private save location.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.download_outlined),
            label: const Text('Continue'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final result = await AssistantState.device
          .invokeMapMethod<String, dynamic>('export', {
            'text': widget.state.exportLocalData(),
            'filename': 'personal-ai-backup.json',
          });
      if (mounted && result?['saved'] == true) {
        notice(context, 'Local backup saved to the location you chose.');
      }
    } on PlatformException catch (error) {
      if (!mounted || error.code == 'cancelled') return;
      notice(context, error.message ?? 'The local backup could not be saved.');
    } catch (error) {
      if (mounted) notice(context, error);
    }
  }

  @override
  Widget build(BuildContext context) => Shell(
    title: 'Settings',
    assistantName: widget.state.assistantName,
    actions: [
      IconButton(
        tooltip: 'Reminder activity',
        onPressed: () => Navigator.pushNamed(context, '/automations'),
        icon: const Icon(Icons.notifications_none_rounded),
      ),
    ],
    child: ListView(
      key: const Key('settings-list'),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 118),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Make it yours',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.55,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Choose how your assistant looks, speaks, connects and handles your data.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        _SettingsGroup(
          title: 'Appearance & identity',
          subtitle: 'Assistant name, app icon and color themes',
          icon: Icons.palette_outlined,
          children: [
            Glass(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: name,
                    maxLength: 40,
                    decoration: const InputDecoration(
                      labelText: 'Assistant display name',
                    ),
                  ),
                  const Text('The name shown across your assistant app.'),
                ],
              ),
            ),
            Glass(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.asset(
                    AssistantState.launcherIconAssets[widget
                        .state
                        .launcherIconId]!,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                  ),
                ),
                title: const Text('Home-screen app icon'),
                subtitle: const Text(
                  'Choose from 26 bundled designs for the Android launcher.',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: _chooseLauncherIcon,
              ),
            ),
            Glass(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FuturisticThemePicker(state: widget.state),
                  const SizedBox(height: 18),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: theme,
                    decoration: const InputDecoration(
                      labelText: 'Light or dark mode',
                    ),
                    items: [
                      for (final mode in ['system', 'light', 'dark'])
                        DropdownMenuItem(
                          value: mode,
                          child: Text(switch (mode) {
                            'system' => 'Follow device',
                            'light' => 'Light',
                            'dark' => 'Dark',
                            _ => 'Dark',
                          }),
                        ),
                    ],
                    onChanged: (value) =>
                        setState(() => theme = value ?? 'system'),
                  ),
                ],
              ),
            ),
          ],
        ),
        _SettingsGroup(
          title: 'Chat & AI',
          subtitle: 'Chat routing, answer style and on-device models',
          icon: Icons.psychology_alt_outlined,
          children: [
            Glass(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<String>(
                    key: const Key('chat-mode-setting'),
                    isExpanded: true,
                    initialValue: chatMode,
                    decoration: const InputDecoration(
                      labelText: 'Chat connection',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'offline',
                        child: Text('Offline · keep chat on this phone'),
                      ),
                      DropdownMenuItem(
                        value: 'online',
                        child: Text('Online · selected AI provider'),
                      ),
                    ],
                    onChanged: (mode) {
                      if (mode != null) unawaited(_saveChatMode(mode));
                    },
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Online sends each chat message to the selected provider. Offline keeps chat and its recent conversation history on this phone and uses the selected Qwen3 0.6B or Gemma 4 E2B model only after opt-in, download and load. If the model is unavailable, chat fails locally; it never falls back online. History and relevant memories are sent to online providers only when their separate Settings switches are on.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    key: const Key('ai-response-mode-setting'),
                    isExpanded: true,
                    initialValue: aiMode,
                    decoration: const InputDecoration(
                      labelText: 'AI response mode',
                    ),
                    items: [
                      for (final entry in AssistantState.aiModeLabels.entries)
                        DropdownMenuItem(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) unawaited(_saveAiMode(value));
                    },
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Changes how replies are presented, not what actions are allowed. Existing confirmations and reviews still apply.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: const Key('response-style-setting'),
                    isExpanded: true,
                    initialValue: responseStyle,
                    decoration: const InputDecoration(
                      labelText: 'Answer style',
                    ),
                    items: [
                      for (final entry
                          in AssistantState.responseStyleLabels.entries)
                        DropdownMenuItem(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => responseStyle = value);
                    },
                  ),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Changes answer presentation only. It does not change safety, approvals or language.',
                    ),
                  ),
                ],
              ),
            ),
            Glass(
              child: ListTile(
                leading: const Icon(Icons.compare_arrows_rounded),
                title: const Text('Compare AIs'),
                subtitle: const Text(
                  'Choose the exact prompt and configured providers in Settings; each provider request needs review.',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: _compareAisFromSettings,
              ),
            ),
            Glass(
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: widget.state.experimentalOfflineChatEnabled,
                onChanged: (enabled) => _setExperimentalOfflineChat(enabled),
                secondary: const _SettingsIconTile(icon: Icons.memory_rounded),
                title: const Text(
                  'Use an on-device model in chat · experimental',
                ),
                subtitle: const Text(
                  'Explicit opt-in. First choose Offline in Chat connection above, then select Qwen3 0.6B or Gemma 4 E2B and download/load it below. Neither model is qualified for Redmi/HyperOS; replies may be inaccurate, slow or heat the phone. There is no online fallback.',
                ),
              ),
            ),
            Glass(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'The optional model is downloaded only when you start it. You can run fixed screening prompts or, after opting in above, use it for normal chat. Neither option means the model is qualified for your phone.',
                  ),
                  const SizedBox(height: 8),
                  const OfflineModelPanel(),
                ],
              ),
            ),
          ],
        ),
        _SettingsGroup(
          title: 'Voice & conversation',
          subtitle: 'Speech input, language and spoken replies',
          icon: Icons.graphic_eq_rounded,
          children: [
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
                      DropdownMenuItem(
                        value: 'deepgram',
                        child: Text('Deepgram · online speech-to-text'),
                      ),
                    ],
                    onChanged: (v) => setState(() => speechMode = v!),
                  ),
                  const Text(
                    'Offline requires a verified installed language on Android 13+. Unsupported devices/languages stay unavailable. Online asks before microphone use. No silent network fallback.',
                  ),
                  DropdownButtonFormField<String>(
                    key: const Key('voice-conversation-mode'),
                    initialValue: voiceConversationMode,
                    decoration: const InputDecoration(
                      labelText: 'Voice conversation mode',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'push_to_talk',
                        child: Text('Push-to-talk · one turn'),
                      ),
                      DropdownMenuItem(
                        value: 'hands_free',
                        child: Text('Hands-free · transcript review'),
                      ),
                      DropdownMenuItem(
                        value: 'live_conversation',
                        child: Text('Live Conversation · background mic'),
                      ),
                    ],
                    onChanged: (mode) {
                      if (mode == null) return;
                      unawaited(_saveVoiceConversationMode(mode));
                    },
                  ),
                  const Text(
                    'Hands-free starts only when you tap the microphone, stays in the foreground, reviews each transcript before sending, speaks the reply, then listens for the next turn. Live Conversation is a separate opt-in: it streams Deepgram audio and Gemini text turns, uses the installed Android voice, and can continue when you switch apps. Start requires microphone and notification permissions; stop in chat or from its persistent notification. No background auto-start, action execution, or provider fallback.',
                  ),
                  if (speechMode == 'deepgram') ...[
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Deepgram speech-to-text · not an LLM'),
                    ),
                    Text(
                      'API key: ${widget.state.deepgramApiKey.isEmpty ? 'Not set' : 'Saved securely on this phone'}',
                    ),
                    TextField(
                      controller: deepgramSecret,
                      obscureText: true,
                      autocorrect: false,
                      enableSuggestions: false,
                      autofillHints: const [],
                      decoration: const InputDecoration(
                        labelText: 'Deepgram API key',
                        hintText: 'Enter a new key or leave blank to keep the saved one',
                      ),
                    ),
                    const Text(
                      'For one-shot dictation, Deepgram audio is sent only after you tap Stop; its transcript stays in the draft. Live Conversation instead streams audio while the explicitly started session is active and supports English, Assamese and Hindi; it requires online Gemini chat and a visible Android foreground-service notification.',
                    ),
                    if (widget.state.deepgramApiKey.isNotEmpty)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () =>
                              widget.state.clearCloudProviderKey('deepgram'),
                          icon: const Icon(Icons.key_off),
                          label: const Text('Clear Deepgram key'),
                        ),
                      ),
                  ],
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: widget.state.speakReplies,
                    onChanged: (enabled) async {
                      try {
                        await widget.state.saveSpeakReplies(enabled);
                      } catch (error) {
                        if (context.mounted) notice(context, error);
                      }
                    },
                    secondary: const Icon(Icons.volume_up_rounded),
                    title: const Text('Read replies aloud'),
                    subtitle: const Text(
                      'Off by default. Uses an installed Android voice unless an online speech option below is enabled.',
                    ),
                  ),
                  SwitchListTile(
                    key: const Key('gemini-expressive-tts-toggle'),
                    contentPadding: EdgeInsets.zero,
                    value: widget.state.geminiTtsEnabled,
                    onChanged: _setGeminiCloudSpeech,
                    secondary: const Icon(Icons.graphic_eq_rounded),
                    title: const Text('Gemini expressive cloud speech'),
                    subtitle: const Text(
                      'Off by default. For spoken replies, sends the reply text to Google Gemini TTS for expressive English, Assamese or Hindi audio. Review data use and possible charges before enabling. Android voice is the fallback.',
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 56, bottom: 8),
                    child: DropdownButtonFormField<String>(
                      key: const Key('gemini-tts-expression'),
                      initialValue: widget.state.geminiTtsExpression,
                      decoration: const InputDecoration(
                        labelText: 'Speech expression',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'natural',
                          child: Text('Match the words'),
                        ),
                        DropdownMenuItem(
                          value: 'cheerful',
                          child: Text('Cheerful'),
                        ),
                        DropdownMenuItem(
                          value: 'curious',
                          child: Text('Curious'),
                        ),
                        DropdownMenuItem(value: 'calm', child: Text('Calm')),
                        DropdownMenuItem(
                          value: 'serious',
                          child: Text('Serious'),
                        ),
                        DropdownMenuItem(value: 'angry', child: Text('Angry')),
                        DropdownMenuItem(
                          value: 'laughing',
                          child: Text('Laughing'),
                        ),
                      ],
                      onChanged: (expression) async {
                        if (expression == null) return;
                        try {
                          await widget.state.saveGeminiTtsExpression(
                            expression,
                          );
                        } catch (error) {
                          if (!context.mounted) return;
                          notice(context, error);
                        }
                      },
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.record_voice_over_rounded),
                    title: const Text('Generate online ElevenLabs voice'),
                    subtitle: Text(
                      widget.state.messages.any(
                            (message) =>
                                message['role'] == 'assistant' &&
                                message['state'] == 'complete',
                          )
                          ? 'For the latest completed assistant reply; review text and retention before each one-time generation.'
                          : 'A completed assistant reply will appear here for one-time playback.',
                    ),
                    trailing: IconButton(
                      tooltip: _playingExpressiveVoice
                          ? 'Stop voice'
                          : 'Generate voice',
                      onPressed: _playingExpressiveVoice
                          ? () async {
                              await _stopAssistantAudio();
                              if (mounted) {
                                setState(() => _playingExpressiveVoice = false);
                              }
                            }
                          : _generateLatestExpressiveVoice,
                      icon: Icon(
                        _playingExpressiveVoice
                            ? Icons.stop_circle_outlined
                            : Icons.play_circle_outline_rounded,
                      ),
                    ),
                  ),
                  const Text(
                    'The exact selected reply is sent to your private service and ElevenLabs. Review is required every time; ElevenLabs retains text and generated audio by default, and this can use account credits.',
                  ),
                  SwitchListTile(
                    key: const Key('azure-speech-opt-in'),
                    contentPadding: EdgeInsets.zero,
                    value: widget.state.azureSpeechEnabled,
                    onChanged: (enabled) async {
                      if (enabled) {
                        final approved = await showDialog<bool>(
                          context: context,
                          builder: (dialogContext) => AlertDialog(
                            title: const Text('Use Azure online speech?'),
                            content: const Text(
                              'When enabled, spoken assistant replies are sent to Microsoft Azure Speech for English or Hindi audio. Use only a Speech F0 resource: this app cannot verify your Azure tier or remaining quota. A paid-tier resource may incur charges; F0 requests may be rejected after its monthly free quota. There is no paid-provider fallback. Your key is stored in Android secure storage.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.pop(dialogContext, false),
                                child: const Text('Cancel'),
                              ),
                              FilledButton(
                                onPressed: () =>
                                    Navigator.pop(dialogContext, true),
                                child: const Text('Enable Azure speech'),
                              ),
                            ],
                          ),
                        );
                        if (approved != true) return;
                      }
                      try {
                        await widget.state.saveAzureSpeechEnabled(enabled);
                      } catch (error) {
                        if (context.mounted) notice(context, error);
                      }
                    },
                    secondary: const Icon(Icons.cloud_outlined),
                    title: const Text('Azure online natural voice'),
                    subtitle: Text(
                      widget.state.azureSpeechEnabled
                          ? 'On · spoken reply text is sent to Azure; English/Hindi only.'
                          : 'Off · uses installed Android voices unless you turn this on.',
                    ),
                  ),
                  Text(
                    'Azure key: ${widget.state.azureSpeechApiKey.isEmpty ? 'Not set' : 'Saved securely on this phone'}',
                  ),
                  TextField(
                    controller: azureSpeechSecret,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    autofillHints: const [],
                    decoration: const InputDecoration(
                      labelText: 'Azure Speech resource key',
                      hintText: 'Enter a new key or leave blank to keep the saved one',
                    ),
                  ),
                  TextField(
                    controller: azureSpeechRegion,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      labelText: 'Azure Speech resource region',
                      hintText: 'For example, centralindia',
                    ),
                  ),
                  const Text(
                    'Create an Azure Speech F0 resource and enter its key and region. The free tier has a monthly neural-speech quota; check Azure for current limits. This app cannot verify your resource tier or remaining quota. F0 quota errors stop online synthesis; there is no paid or other-provider fallback. If credentials are missing or the selected language is not English/Hindi, the app uses an installed Android voice and makes no Azure request.',
                  ),
                  if (widget.state.azureSpeechApiKey.isNotEmpty)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () async {
                          try {
                            await widget.state.clearCloudProviderKey(
                              'azure_speech',
                            );
                            azureSpeechSecret.clear();
                            if (context.mounted) {
                              notice(context, 'Azure Speech key cleared.');
                            }
                          } catch (error) {
                            if (context.mounted) notice(context, error);
                          }
                        },
                        icon: const Icon(Icons.key_off),
                        label: const Text('Clear Azure Speech key'),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Speech speed'),
                      Text(_speechRateLabel(speechRate)),
                    ],
                  ),
                  Slider(
                    key: const Key('on-device-speech-rate'),
                    value: speechRate,
                    min: 0.25,
                    max: 0.75,
                    divisions: 10,
                    label: _speechRateLabel(speechRate),
                    onChanged: (value) => setState(() => speechRate = value),
                  ),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Adjusts installed Android text-to-speech only. Expressive service audio has separate pacing.',
                    ),
                  ),
                  const SizedBox(height: 12),
                  KeyedSubtree(
                    key: ValueKey(
                      'installed-voice-$language-${selectedVoiceName ?? 'automatic'}-${_offlineVoices.length}',
                    ),
                    child: DropdownButtonFormField<String>(
                      key: const Key('natural-voice-choice'),
                      isExpanded: true,
                      initialValue: _selectedOfflineVoice == null
                          ? _automaticVoiceKey
                          : offlineVoiceOptionKey(_selectedOfflineVoice!),
                      decoration: const InputDecoration(
                        labelText: 'Installed voice',
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: _automaticVoiceKey,
                          child: Text(
                            'Automatic — best installed offline voice',
                          ),
                        ),
                        for (final voice in _offlineVoices)
                          DropdownMenuItem(
                            value: offlineVoiceOptionKey(voice),
                            child: Text(offlineVoiceOptionLabel(voice)),
                          ),
                      ],
                      onChanged: _loadingOfflineVoices
                          ? null
                          : (value) {
                              final selected = _offlineVoices.where(
                                (voice) =>
                                    offlineVoiceOptionKey(voice) == value,
                              );
                              setState(() {
                                if (value == _automaticVoiceKey ||
                                    selected.isEmpty) {
                                  selectedVoiceName = null;
                                  selectedVoiceLocale = null;
                                } else {
                                  selectedVoiceName = selected.first['name']
                                      ?.toString();
                                  selectedVoiceLocale = selected.first['locale']
                                      ?.toString();
                                }
                              });
                            },
                    ),
                  ),
                  Text(
                    _loadingOfflineVoices
                        ? 'Checking installed voices on this device…'
                        : _offlineVoices.isEmpty
                        ? 'No matching installed offline voice was found. Speech support depends on the installed Android engine; no network voice or downloaded model is used.'
                        : 'Uses installed Android offline voices only. Quality and naturalness depend on the device’s speech engine; no voice recording is uploaded.',
                  ),
                  OutlinedButton.icon(
                    key: const Key('preview-natural-voice'),
                    onPressed: _loadingOfflineVoices || _offlineVoices.isEmpty
                        ? null
                        : _previewInstalledVoice,
                    icon: Icon(
                      _previewingVoice ? Icons.stop : Icons.play_arrow_rounded,
                    ),
                    label: Text(
                      _previewingVoice ? 'Stop preview' : 'Preview voice',
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: language,
                    decoration: const InputDecoration(
                      labelText: 'Conversation / voice language',
                    ),
                    items: [
                      for (final entry in AssistantState.languageLabels.entries)
                        DropdownMenuItem(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                    ],
                    onChanged: (v) {
                      setState(() => language = v!);
                      _loadOfflineVoices(v!);
                    },
                  ),
                  const SizedBox(height: 12),
                  const SizedBox(height: 16),
                  const Text(
                    'Voice replies and recognition use your selected language where the device/provider supports it. English, Assamese, Hindi and Hinglish can be selected; this is not automatic language detection. Online providers may retain submitted content and charge your account; offline never falls back online.',
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'ElevenLabs expressive voice is on-demand per reply. It sends only that reply through your private service; each play asks first and may use your account credits. The ElevenLabs key and voice ID must be configured on the service host and are never stored in this APK. Audio tags guide delivery but do not guarantee an emotion. No provider key is bundled.',
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
            Glass(
              child: Column(
                children: [
                  const Text(
                    'The voice interaction is push-to-talk: review or correct the transcript before it enters the composer. It does not listen continuously or execute commands from raw speech.',
                  ),
                  TextButton(
                    onPressed: () async {
                      try {
                        final info = await AssistantState.device
                            .invokeMapMethod('device_status');
                        if (context.mounted) {
                          notice(
                            context,
                            'Android API ${info?['sdk']} · installed on-device recognizer: ${info?['on_device_recognizer']} · system recognizer: ${info?['system_recognizer']}. These flags do not verify speech quality or installed support for any selected language.',
                          );
                        }
                      } catch (e) {
                        if (context.mounted) notice(context, e);
                      }
                    },
                    child: const Text('Check device speech capabilities'),
                  ),
                ],
              ),
            ),
          ],
        ),
        _SettingsGroup(
          title: 'Memory & data',
          subtitle: 'Approved memories, conversation history and local backup',
          icon: Icons.storage_outlined,
          children: [
            Glass(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.lock_person_outlined),
                title: const Text('Approved memories'),
                subtitle: const Text(
                  'Review, edit or delete facts saved on this device; chat history is not silently turned into memory.',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.pushNamed(context, '/memory'),
              ),
            ),
            Glass(
              child: ListTile(
                leading: const Icon(Icons.history_rounded),
                title: const Text('Conversation history'),
                subtitle: const Text('Open a saved on-phone conversation.'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: _openConversationHistory,
              ),
            ),
            Glass(
              child: ListTile(
                leading: const Icon(Icons.add_comment_outlined),
                title: const Text('New conversation'),
                subtitle: const Text('Start a fresh on-phone chat.'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: _startNewConversation,
              ),
            ),
            Glass(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Local backup',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Export and restore are manual. Backups are readable, unencrypted JSON; keep them private. Provider credentials and service tokens are excluded, and restore leaves security settings and other app preferences alone.',
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _exportLocalBackup,
                    icon: const Icon(Icons.download_outlined),
                    label: const Text('Export local data'),
                  ),
                  const SizedBox(height: 4),
                  LocalBackupRestoreControl(
                    selectBackup: _selectLocalBackup,
                    restore: widget.state.restoreLocalBackup,
                    onResult: (message) => notice(context, message),
                  ),
                ],
              ),
            ),
            Glass(
              child: TextButton(
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
                      if (context.mounted) notice(context, e);
                    }
                  }
                },
                child: const Text('Delete current conversation history'),
              ),
            ),
          ],
        ),
        _SettingsGroup(
          title: 'Connections & workflows',
          subtitle:
              'Connected services, drafts, reviewed actions and reminders',
          icon: Icons.hub_outlined,
          children: [
            Glass(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.hub_outlined),
                title: const Text('API & MCP connections'),
                subtitle: Text(
                  '${widget.state.config.description} · ${widget.state.customMcpServers.length} MCP server${widget.state.customMcpServers.length == 1 ? '' : 's'} saved',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.pushNamed(context, '/connections'),
              ),
            ),
            Glass(
              child: ListTile(
                leading: const Icon(Icons.edit_note_rounded),
                title: const Text('Message & social drafts'),
                subtitle: const Text(
                  'Edit text, then use Android’s share sheet; nothing is sent automatically.',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.pushNamed(context, '/drafts'),
              ),
            ),
            Glass(
              child: ListTile(
                leading: const Icon(Icons.auto_awesome_outlined),
                title: const Text('Skills & actions'),
                subtitle: const Text(
                  'Reviewed local app launches and reminders; no background agent.',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.pushNamed(context, '/skills'),
              ),
            ),
            Glass(
              child: TextButton.icon(
                onPressed: () => Navigator.pushNamed(context, '/automations'),
                icon: const Icon(Icons.notifications_none_rounded),
                label: const Text('Reminder activity'),
              ),
            ),
          ],
        ),
        _SettingsGroup(
          title: 'Privacy & access',
          subtitle: 'App lock, Android permissions and device access',
          icon: Icons.shield_outlined,
          children: [
            const Glass(
              child: Text(
                'Chat mode is chosen above. Online sends each prompt to the selected provider; offline uses the selected local Qwen3 or Gemma model only after opt-in and download/load, with no online fallback. Action, purchase, permission and other safety reviews remain separate. The private FastAPI adapter remains optional.',
              ),
            ),
            Glass(
              child: SwitchListTile(
                key: const Key('online-history-sharing'),
                contentPadding: EdgeInsets.zero,
                value: widget.state.shareHistory,
                onChanged: (enabled) async {
                  try {
                    await widget.state.saveOnlineHistorySharing(enabled);
                  } catch (error) {
                    if (context.mounted) notice(context, error);
                  }
                },
                secondary: const _SettingsIconTile(icon: Icons.history_rounded),
                title: const Text('Allow current-chat history in online sends'),
                subtitle: const Text(
                  'Off by default. When on, completed messages from this chat are included in each online request without a per-message review. Turn it off to keep chat history on this phone.',
                ),
              ),
            ),
            Glass(
              child: SwitchListTile(
                key: const Key('online-memory-sharing'),
                contentPadding: EdgeInsets.zero,
                value: widget.state.shareMemories,
                onChanged: (enabled) async {
                  try {
                    await widget.state.saveOnlineMemorySharing(enabled);
                  } catch (error) {
                    if (context.mounted) notice(context, error);
                  }
                },
                secondary: const _SettingsIconTile(
                  icon: Icons.bookmark_outline_rounded,
                ),
                title: const Text(
                  'Allow relevant approved memories in online sends',
                ),
                subtitle: const Text(
                  'Off by default. Matching approved memories are included in each online request without a per-message review. Unrelated facts stay on this phone.',
                ),
              ),
            ),
            Glass(
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: widget.state.appLockEnabled,
                onChanged: widget.state.appLockBusy
                    ? null
                    : (enabled) async {
                        final saved = await widget.state.setAppLockEnabled(
                          enabled,
                        );
                        if (!context.mounted) return;
                        if (saved) {
                          notice(
                            context,
                            enabled
                                ? 'App lock enabled.'
                                : 'App lock disabled.',
                          );
                        } else {
                          notice(
                            context,
                            'Device authentication did not succeed. App lock was not changed.',
                          );
                        }
                      },
                secondary: const _SettingsIconTile(icon: Icons.lock_outline),
                title: const Text('App lock'),
                subtitle: const Text(
                  'Require your phone’s biometric or screen lock when opening or returning to the app.',
                ),
              ),
            ),
            const AndroidAccessPanel(),
            const Glass(
              child: Text(
                'Microphone access is requested only when starting voice input. Notification permission is requested when scheduling your first reminder. Neither is needed for typed chat. Android speech providers may send audio to their service. There is no background microphone or wake phrase.',
              ),
            ),
          ],
        ),
        _SettingsGroup(
          title: 'About & updates',
          subtitle: 'Check the official GitHub release',
          icon: Icons.system_update_alt_rounded,
          children: [Glass(child: const AppUpdatePanel())],
        ),
        Glass(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Save changes',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              const Text(
                'Applies your assistant name, light or dark mode, speech input, language and installed voice choices.',
              ),
              const SizedBox(height: 10),
              FilledButton(
                onPressed: () async {
                  try {
                    await widget.state.saveTheme(theme);
                    await widget.state.setAssistantName(name.text);
                    await widget.state.saveSpeechMode(speechMode);
                    await widget.state.saveSpeechRate(speechRate);
                    await widget.state.saveResponseStyle(responseStyle);
                    await widget.state.saveSpeechVoice(
                      name: selectedVoiceName,
                      locale: selectedVoiceLocale,
                    );
                    await widget.state.saveAzureSpeechRegion(
                      azureSpeechRegion.text,
                    );
                    if (azureSpeechSecret.text.trim().isNotEmpty) {
                      await widget.state.saveCloudProviderKey(
                        'azure_speech',
                        azureSpeechSecret.text,
                      );
                    }
                    azureSpeechSecret.clear();
                    if (speechMode == 'deepgram') {
                      await widget.state.saveCloudProviderKey(
                        'deepgram',
                        deepgramSecret.text,
                      );
                    }
                    deepgramSecret.clear();
                    await widget.state.saveEngine(
                      widget.state.engine,
                      widget.state.model,
                      language,
                    );
                    if (context.mounted) {
                      notice(context, 'Settings saved on this device.');
                    }
                  } catch (e) {
                    if (context.mounted) notice(context, e);
                  }
                },
                child: const Text('Save settings'),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

String _speechRateLabel(double value) => value < 0.45
    ? 'Slower'
    : value > 0.55
    ? 'Faster'
    : 'Standard';

class _SettingsGroup extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Widget> children;

  const _SettingsGroup({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) => Glass(
    padding: EdgeInsets.zero,
    bottomSpacing: 10,
    borderRadius: BorderRadius.circular(26),
    child: ExpansionTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      children: children,
    ),
  );
}

class ApiMcpSettings extends StatefulWidget {
  final AssistantState state;
  const ApiMcpSettings({super.key, required this.state});

  @override
  State<ApiMcpSettings> createState() => _ApiMcpSettingsState();
}

class _ApiMcpSettingsState extends State<ApiMcpSettings> {
  late final TextEditingController serviceUrl = TextEditingController(
    text: widget.state.privateServiceEndpoint,
  );
  late final TextEditingController compatibleUrl = TextEditingController(
    text: widget.state.compatibleApiEndpoint,
  );
  late final TextEditingController model = TextEditingController(
    text: widget.state.model,
  );
  final serviceSecret = TextEditingController();
  final compatibleSecret = TextEditingController();
  late String engine = widget.state.engine;
  bool saving = false;
  bool testing = false;
  String connectionStatus = 'Connection not tested on this device.';
  bool? connectionSucceeded;

  @override
  void dispose() {
    serviceUrl.dispose();
    compatibleUrl.dispose();
    model.dispose();
    serviceSecret.dispose();
    compatibleSecret.dispose();
    super.dispose();
  }

  Future<void> _clearCredential({
    required bool compatible,
    bool gemini = false,
    String? cloudProvider,
  }) async {
    final label = cloudProvider != null
        ? '${cloudProvider == 'openai' ? 'OpenAI' : cloudProvider} API key'
        : gemini
        ? 'Gemini API key'
        : compatible
        ? 'API key'
        : 'private service token';
    final remove =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text('Clear $label?'),
            content: const Text(
              'This removes the saved credential from this phone. It does not revoke it at the provider.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Keep'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Clear'),
              ),
            ],
          ),
        ) ??
        false;
    if (!remove || !mounted) return;
    if (cloudProvider != null) {
      await widget.state.clearCloudProviderKey(cloudProvider);
    } else {
      await widget.state.clearProviderCredential(
        compatible: compatible,
        gemini: gemini,
      );
    }
    if (mounted) {
      setState(() {
        connectionStatus = 'Credential cleared; connection is not configured.';
        connectionSucceeded = false;
      });
      notice(context, '$label cleared from this phone.');
    }
  }

  Future<void> _save({bool showNotice = true}) async {
    setState(() => saving = true);
    try {
      if (engine == 'gemini') {
        await widget.state.saveGeminiApiKey(compatibleSecret.text);
        await widget.state.saveEngine(
          'gemini',
          model.text,
          widget.state.language,
        );
      } else if (engine == 'openai') {
        await widget.state.saveCloudProviderKey(
          'openai',
          compatibleSecret.text,
        );
        await widget.state.saveEngine(
          'openai',
          model.text,
          widget.state.language,
        );
      } else {
        await widget.state.saveSettings(
          serviceUrl.text,
          serviceSecret.text,
          widget.state.theme,
          compatibleUrl: compatibleUrl.text,
          compatibleSecret: compatibleSecret.text,
        );
        await widget.state.saveEngine(
          engine,
          model.text,
          widget.state.language,
        );
      }
      serviceSecret.clear();
      compatibleSecret.clear();
      if (mounted) {
        setState(() {
          connectionStatus = 'Saved on this phone · connection not yet tested.';
          connectionSucceeded = null;
        });
        if (showNotice) notice(context, 'Connection settings saved securely.');
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          connectionStatus = 'Not saved: $error';
          connectionSucceeded = false;
        });
      }
      rethrow;
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _testConnection() async {
    setState(() {
      testing = true;
      connectionStatus = 'Testing the selected server…';
      connectionSucceeded = null;
    });
    try {
      // Persist first so the probe uses exactly the configuration now shown.
      await _save(showNotice: false);
      if (engine == 'gemini') {
        final result = await widget.state.testGeminiApi(
          modelName: widget.state.geminiModelSelection,
        );
        if (mounted) {
          setState(() {
            connectionStatus = result;
            connectionSucceeded = true;
          });
        }
      } else if (engine == 'openai') {
        final result = await widget.state.testOpenAiApi();
        if (mounted) {
          setState(() {
            connectionStatus = result;
            connectionSucceeded = true;
          });
        }
      } else if (engine == 'private_service') {
        final result = await widget.state.request('GET', '/health');
        final configured =
            result is Map && result['provider_configured'] == true;
        if (mounted) {
          setState(() {
            connectionStatus = configured
                ? 'Connected · service reachable and an AI provider is configured.'
                : 'Connected to the service, but no AI provider is configured there.';
            connectionSucceeded = true;
          });
        }
      } else if (engine == 'compatible') {
        final result = await widget.state.testCompatibleApi();
        if (mounted) {
          setState(() {
            connectionStatus = result;
            connectionSucceeded = true;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            connectionStatus = 'Offline · no server connection is used. Download and load the local model first.';
            connectionSucceeded = null;
          });
        }
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          connectionStatus = '$error';
          connectionSucceeded = false;
        });
      }
    } finally {
      if (mounted) setState(() => testing = false);
    }
  }

  @override
  Widget build(BuildContext context) => Shell(
    title: 'API & MCP connections',
    assistantName: widget.state.assistantName,
    primaryNavigation: false,
    child: ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
      children: [
        Text(
          'Connect an AI provider or inspect MCP servers',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 6),
        const Text(
          'Chat routing is chosen separately in Settings > Chat & AI. Saving settings does not connect a server. Use Test connection to verify the selected endpoint. Provider credentials stay in Android secure storage and are never displayed again.',
        ),
        const SizedBox(height: 16),
        const _SettingsSectionLabel('AI PROVIDER'),
        Glass(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: engine,
                decoration: const InputDecoration(labelText: 'AI engine'),
                items: const [
                  DropdownMenuItem(
                    value: 'gemini',
                    child: Text('Online · Gemini API'),
                  ),
                  DropdownMenuItem(
                    value: 'openai',
                    child: Text('Online · OpenAI ChatGPT'),
                  ),
                  DropdownMenuItem(
                    value: 'offline',
                    child: Text(
                      'Offline runtime · choose Offline chat separately',
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'compatible',
                    child: Text('Online · OpenAI-compatible API'),
                  ),
                  DropdownMenuItem(
                    value: 'private_service',
                    child: Text('Online · private FastAPI service'),
                  ),
                ],
                onChanged: saving || testing
                    ? null
                    : (value) => setState(() {
                        engine = value ?? 'gemini';
                        if (engine == 'openai' &&
                            widget.state.engine != 'openai') {
                          model.text = 'gpt-4o-mini';
                        }
                        if (engine == 'gemini' &&
                            !AssistantState.supportsGeminiModel(model.text)) {
                          model.text = widget.state.geminiModelSelection;
                        }
                      }),
              ),
              const SizedBox(height: 10),
              if (engine == 'gemini') ...[
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: AssistantState.supportsGeminiModel(model.text)
                      ? model.text
                      : AssistantState.geminiModel,
                  decoration: const InputDecoration(labelText: 'Gemini model'),
                  items: [
                    for (final entry
                        in AssistantState.geminiModelLabels.entries)
                      DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                  ],
                  onChanged: saving || testing
                      ? null
                      : (value) => setState(() {
                          if (value != null) model.text = value;
                        }),
                ),
                const SizedBox(height: 8),
                Text(
                  'API key: ${widget.state.geminiApiKey.isEmpty ? 'Not set' : 'Saved securely on this phone'}',
                ),
                TextField(
                  controller: compatibleSecret,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  autofillHints: const [],
                  decoration: const InputDecoration(
                    labelText: 'Gemini API key',
                    hintText: 'Paste your key from Google AI Studio',
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Start with Gemini 3.5 Flash-Lite: Google currently lists free input and output for eligible free-tier projects, subject to quotas and model access. Google says free-tier content may be used to improve its products. Gemini 2.5 Flash and Flash-Lite are also selectable, but Google limits 2.5 access to people who have actively used a 2.5 model before. A free-tier listing does not guarantee your project has access or unlimited use, and Google account billing settings still apply. Test connection sends one tiny fixed “Reply with exactly: OK” request using the selected model; it does not include chats. Online chat still waits for your explicit review. No automatic paid-model switch or fallback.',
                ),
                if (widget.state.geminiApiKey.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: saving || testing
                          ? null
                          : () => _clearCredential(
                              compatible: false,
                              gemini: true,
                            ),
                      icon: const Icon(Icons.key_off),
                      label: const Text('Clear Gemini API key'),
                    ),
                  ),
              ] else if (engine == 'openai') ...[
                Text(
                  'API key: ${widget.state.openAiApiKey.isEmpty ? 'Not set' : 'Saved securely on this phone'}',
                ),
                TextField(
                  controller: model,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    labelText: 'OpenAI model ID',
                    hintText: 'gpt-4o-mini',
                  ),
                ),
                TextField(
                  controller: compatibleSecret,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  autofillHints: const [],
                  decoration: const InputDecoration(
                    labelText: 'OpenAI API key',
                    hintText: 'Leave blank to keep the saved key',
                  ),
                ),
                const Text(
                  'The key is stored in Android secure storage. Test connection only lists models from OpenAI; chat text is sent only when you submit a prompt. OpenAI account pricing and data handling apply.',
                ),
                if (widget.state.openAiApiKey.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: saving || testing
                          ? null
                          : () => _clearCredential(
                              compatible: false,
                              cloudProvider: 'openai',
                            ),
                      icon: const Icon(Icons.key_off),
                      label: const Text('Clear OpenAI API key'),
                    ),
                  ),
              ] else if (engine == 'compatible') ...[
                TextField(
                  controller: compatibleUrl,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'API origin',
                    hintText: 'https://api.example.com',
                  ),
                ),
                TextField(
                  controller: model,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    labelText: 'Model ID',
                    hintText: 'Exact model identifier from your provider',
                  ),
                ),
                const SizedBox(height: 8),
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
                    hintText: 'Leave blank to keep the saved key',
                  ),
                ),
                const Text(
                  'Use HTTPS for remote providers; HTTP is accepted only for localhost or Android-emulator host access. Keys are never shown again. Test connection requests only the provider model-list endpoint; it does not send a chat prompt.',
                ),
                if (widget.state.compatibleApiKey.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: saving || testing
                          ? null
                          : () => _clearCredential(compatible: true),
                      icon: const Icon(Icons.key_off),
                      label: const Text('Clear API key'),
                    ),
                  ),
              ] else if (engine == 'private_service') ...[
                TextField(
                  controller: serviceUrl,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Private service origin',
                    hintText: 'https://your-private-service.example',
                  ),
                ),
                const SizedBox(height: 8),
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
                    hintText: 'Leave blank to keep the saved token',
                  ),
                ),
                const Text(
                  'On an Android phone, 127.0.0.1 and localhost point to the phone itself, not your server. Enter the server’s reachable HTTPS address. Android emulator host access uses 10.0.2.2.',
                ),
                if (widget.state.privateServiceToken.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: saving || testing
                          ? null
                          : () => _clearCredential(compatible: false),
                      icon: const Icon(Icons.key_off),
                      label: const Text('Clear service token'),
                    ),
                  ),
              ] else ...[
                const Text(
                  'Offline mode does not connect to a server. In Settings > Chat & AI, enable experimental chat, select Qwen3 0.6B or Gemma 4 E2B, then download and load it on this phone. There is no online fallback.',
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: saving || testing
                          ? null
                          : () async {
                              try {
                                await _save();
                              } catch (_) {
                                // The inline state contains the actionable error.
                              }
                            },
                      child: Text(
                        saving ? 'Saving…' : 'Save connection settings',
                      ),
                    ),
                  ),
                ],
              ),
              if (engine != 'offline') ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: saving || testing ? null : _testConnection,
                  icon: testing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.network_check_rounded),
                  label: Text(
                    testing
                        ? 'Testing connection…'
                        : engine == 'gemini'
                        ? 'Test connection'
                        : 'Save & test connection',
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Semantics(
                liveRegion: true,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      connectionSucceeded == true
                          ? Icons.check_circle_outline
                          : connectionSucceeded == false
                          ? Icons.error_outline
                          : Icons.info_outline,
                      color: connectionSucceeded == true
                          ? Theme.of(context).colorScheme.primary
                          : connectionSucceeded == false
                          ? Theme.of(context).colorScheme.error
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(connectionStatus)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Chat messages follow the persistent Online/Offline choice in Settings. This screen never runs tools automatically; action, purchase, permission and other safety reviews remain separate.',
        ),
        const SizedBox(height: 16),
        const SizedBox(height: 12),
        Glass(
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.compare_arrows_rounded),
            title: const Text('Configure multi-provider comparison'),
            subtitle: const Text(
              'Set up Gemini, OpenAI, Groq, and OpenRouter profiles. Each comparison sends your exact prompt only to the providers you select and review.',
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => showDialog<void>(
              context: context,
              builder: (_) => ProviderProfilesEditor(state: widget.state),
            ),
          ),
        ),
        const SizedBox(height: 20),
        const _SettingsSectionLabel('MCP SERVERS'),
        CustomMcpPanel(state: widget.state),
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
    assistantName: widget.state.assistantName,
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

class CustomMcpPanel extends StatefulWidget {
  final AssistantState state;
  const CustomMcpPanel({super.key, required this.state});
  @override
  State<CustomMcpPanel> createState() => _CustomMcpPanelState();
}

class _CustomMcpPanelState extends State<CustomMcpPanel> {
  bool busy = false;
  final Map<String, String> _serverStatus = {};

  Future<void> _add() async {
    final name = TextEditingController();
    final endpoint = TextEditingController();
    final token = TextEditingController();
    final formKey = GlobalKey<FormState>();
    var preset = 'custom';
    final values = await showDialog<List<String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add custom MCP server'),
          content: SizedBox(
            width: 480,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: preset,
                      decoration: const InputDecoration(
                        labelText: 'Server type',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'custom',
                          child: Text('Custom server'),
                        ),
                        DropdownMenuItem(
                          value: 'wajo',
                          child: Text('Wajo Fo · OAuth'),
                        ),
                      ],
                      onChanged: (value) {
                        setDialogState(() {
                          preset = value ?? 'custom';
                          if (preset == 'wajo') {
                            name.text = 'Wajo Fo';
                            endpoint.text = wajoMcpEndpoint;
                            token.clear();
                          } else {
                            name.clear();
                            endpoint.clear();
                            token.clear();
                          }
                        });
                      },
                    ),
                    TextFormField(
                      controller: name,
                      maxLength: 48,
                      decoration: const InputDecoration(
                        labelText: 'Server name',
                      ),
                      validator: (value) {
                        final normalized = (value ?? '').trim();
                        if (normalized.isEmpty ||
                            normalized.runes.length > 48 ||
                            normalized.contains(RegExp(r'[\x00-\x1f]'))) {
                          return 'Use 1–48 characters without control characters.';
                        }
                        return null;
                      },
                    ),
                    TextFormField(
                      controller: endpoint,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'MCP server URL',
                        hintText: 'https://mcp.example.com/mcp',
                      ),
                      validator: (value) {
                        try {
                          validateMcpEndpoint(value ?? '');
                          if (preset == 'wajo' &&
                              value?.trim() != wajoMcpEndpoint) {
                            return 'Use the exact Wajo Fo endpoint.';
                          }
                          return null;
                        } catch (e) {
                          return e.toString();
                        }
                      },
                    ),
                    if (preset == 'custom')
                      TextFormField(
                        controller: token,
                        obscureText: true,
                        autocorrect: false,
                        enableSuggestions: false,
                        autofillHints: const [],
                        decoration: const InputDecoration(
                          labelText: 'Optional bearer token',
                        ),
                      )
                    else
                      const Padding(
                        padding: EdgeInsets.only(top: 10),
                        child: Text(
                          'This only saves the preset on this phone. It does not contact Wajo. After adding it, choose Connect with OAuth to start secure sign-in; no chat or memory is sent.',
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(context, [
                    name.text,
                    endpoint.text,
                    token.text,
                    preset,
                  ]);
                }
              },
              child: const Text('Add server'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    endpoint.dispose();
    token.dispose();
    if (values == null || !mounted) return;
    try {
      final useWajoOAuth = values[3] == 'wajo';
      await widget.state.addMcpServer(
        values[0],
        values[1],
        values[2],
        authMode: useWajoOAuth ? McpAuthMode.wajoOAuth : McpAuthMode.bearer,
      );
      if (mounted) {
        notice(
          context,
          useWajoOAuth
              ? 'Wajo Fo saved locally; it is not connected. Choose Connect with OAuth to continue.'
              : 'MCP server saved on this phone.',
        );
      }
    } catch (e) {
      if (mounted) notice(context, e);
    }
  }

  Future<void> _connectOAuth(McpServer server) async {
    setState(() => busy = true);
    try {
      await widget.state.connectMcpOAuth(server.id);
      if (mounted) {
        setState(() {
          _serverStatus[server.id] = 'OAuth authorized on this phone · server reachability still needs Test & discover tools.';
        });
        notice(
          context,
          'Wajo OAuth authorized on this phone. No tools were run.',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _serverStatus[server.id] = 'OAuth not connected · $e');
        notice(context, e);
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _discover(McpServer server) async {
    setState(() => busy = true);
    try {
      final tools = await widget.state.discoverMcpTools(server.id);
      if (!mounted) return;
      setState(() {
        busy = false;
        _serverStatus[server.id] =
            'Reachable · server returned ${tools.length} tool${tools.length == 1 ? '' : 's'}. Choose Review & run for a separate confirmation before any tool call.';
      });
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('${server.name} · ${tools.length} tools'),
          content: SizedBox(
            width: 480,
            child: tools.isEmpty
                ? const Text('The server responded, but advertised no tools.')
                : SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final tool in tools)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  tool.name,
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                                if (tool.description.isNotEmpty)
                                  Text(tool.description),
                                const SizedBox(height: 6),
                                OutlinedButton.icon(
                                  onPressed: busy
                                      ? null
                                      : () async {
                                          Navigator.pop(context);
                                          await _reviewAndRunTool(server, tool);
                                        },
                                  icon: const Icon(Icons.play_arrow),
                                  label: const Text('Review & run'),
                                ),
                              ],
                            ),
                          ),
                        const Text(
                          'No tool runs until you review and confirm its exact server, tool, and JSON arguments.',
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
    } catch (e) {
      if (mounted) {
        setState(() => _serverStatus[server.id] = 'Not reachable · $e');
        notice(context, e);
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _reviewAndRunTool(McpServer server, McpToolInfo tool) async {
    final argumentsController = TextEditingController(text: '{}');
    final enteredArguments = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Prepare ${tool.name}'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${server.name} · ${server.endpoint}'),
                if (tool.description.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(tool.description),
                ],
                const SizedBox(height: 12),
                const Text('Server-provided input schema (untrusted):'),
                const SizedBox(height: 4),
                SelectableText(
                  const JsonEncoder.withIndent('  ').convert(tool.inputSchema),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: argumentsController,
                  minLines: 5,
                  maxLines: 10,
                  maxLength: maxMcpToolArgumentsBytes,
                  autocorrect: false,
                  enableSuggestions: false,
                  keyboardType: TextInputType.multiline,
                  decoration: const InputDecoration(
                    labelText: 'Tool arguments (JSON object)',
                    hintText: '{"key": "value"}',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, argumentsController.text),
            child: const Text('Review exact call'),
          ),
        ],
      ),
    );
    argumentsController.dispose();
    if (enteredArguments == null || !mounted) return;

    late final Map<String, dynamic> arguments;
    try {
      arguments = validateMcpToolArguments(enteredArguments);
    } catch (e) {
      notice(context, e);
      return;
    }

    final prettyArguments = const JsonEncoder.withIndent('  ')
        .convert(arguments);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Run this MCP tool?'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Server: ${server.name}'),
                SelectableText(server.endpoint),
                const SizedBox(height: 8),
                Text('Tool: ${tool.name}'),
                const SizedBox(height: 8),
                const Text('Exact arguments:'),
                const SizedBox(height: 4),
                SelectableText(prettyArguments),
                const SizedBox(height: 12),
                const Text(
                  'This server may use the tool to change data, send messages, make purchases, or take other actions. Only run it if you trust this server and these exact arguments. The app cannot undo the tool’s effects.',
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Run this tool'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final current = widget.state.customMcpServers
        .where((item) => item.id == server.id)
        .firstOrNull;
    if (current == null ||
        current.name != server.name ||
        current.endpoint != server.endpoint ||
        current.authMode != server.authMode) {
      notice(
        context,
        'This MCP server changed or was removed. Discover it again before running a tool.',
      );
      return;
    }

    setState(() => busy = true);
    try {
      final result = await widget.state.callMcpTool(server.id, tool, arguments);
      if (!mounted) return;
      final rendered = const JsonEncoder.withIndent('  ').convert(result);
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            result['isError'] == true
                ? 'Tool returned an error'
                : 'Tool result · ${tool.name}',
          ),
          content: SizedBox(
            width: 520,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 420),
              child: SingleChildScrollView(child: SelectableText(rendered)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) notice(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _remove(McpServer server) async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Remove ${server.name}?'),
            content: const Text(
              'This removes the saved server and credentials from this phone. If you used Wajo OAuth, its client registration may remain at Wajo; this app has no remote deregistration action.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Keep'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Remove'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    try {
      await widget.state.removeMcpServer(server.id);
      if (mounted) setState(() => _serverStatus.remove(server.id));
    } catch (e) {
      if (mounted) notice(context, e);
    }
  }

  @override
  Widget build(BuildContext context) => Glass(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Custom MCP servers',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 6),
        const Text(
          'Add a remote Model Context Protocol server, inspect its tools, and run a selected tool only after reviewing and confirming the exact server, tool, and arguments. Endpoints must use HTTPS (loopback HTTP is allowed for local testing). Treat servers and tool descriptions as untrusted.',
        ),
        if (widget.state.mcpLoadError.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(widget.state.mcpLoadError),
          ),
        for (final server in widget.state.customMcpServers)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.hub_outlined),
            title: Text(server.name),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  server.endpoint,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (server.authMode == McpAuthMode.wajoOAuth)
                  FutureBuilder<bool>(
                    future: widget.state.isMcpOAuthConnected(server),
                    builder: (context, snapshot) => Text(
                      snapshot.data == true
                          ? 'OAuth connected'
                          : 'OAuth not connected',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                Text(
                  _serverStatus[server.id] ??
                      (server.authMode == McpAuthMode.wajoOAuth
                          ? 'Saved · OAuth status shown above; server not tested'
                          : 'Saved on this phone · not tested'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            trailing: PopupMenuButton<String>(
              enabled: !busy,
              onSelected: (value) {
                if (value == 'connect') {
                  _connectOAuth(server);
                } else if (value == 'discover') {
                  _discover(server);
                } else {
                  _remove(server);
                }
              },
              itemBuilder: (context) => [
                if (server.authMode == McpAuthMode.wajoOAuth)
                  const PopupMenuItem(
                    value: 'connect',
                    child: Text('Connect with OAuth'),
                  ),
                const PopupMenuItem(
                  value: 'discover',
                  child: Text('Test & discover tools'),
                ),
                const PopupMenuItem(
                  value: 'remove',
                  child: Text('Remove server'),
                ),
              ],
            ),
          ),
        if (busy) const LinearProgressIndicator(),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: widget.state.customMcpServers.length >= 25 ? null : _add,
            icon: const Icon(Icons.add),
            label: const Text('Add MCP server'),
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Tools are never auto-run. Each invocation requires a separate review of the server, tool, and exact arguments; a tool may cause external effects that this app cannot undo.',
        ),
        const SizedBox(height: 4),
        const Text(
          'Wajo Fo OAuth is optional. Adding its preset does not connect it; the Connect with OAuth action performs discovery and native-client registration before opening sign-in.',
        ),
      ],
    ),
  );
}
