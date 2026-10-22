import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter/services.dart';

import 'assistant_state.dart';
import 'mcp_servers.dart';
import 'wajo_oauth.dart';
import 'offline_model.dart';
import 'phone_screens.dart';
import 'safe_workflows.dart';
import 'ui_motion.dart';
import 'visual_theme.dart';

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
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.state,
    builder: (context, _) => MaterialApp(
      title: widget.state.assistantName,
      debugShowCheckedModeBanner: false,
      theme: _assistantTheme(Brightness.light, widget.state.visualTheme),
      darkTheme: _assistantTheme(Brightness.dark, widget.state.visualTheme),
      themeAnimationDuration: const Duration(milliseconds: 520),
      themeAnimationCurve: Curves.easeInOutCubic,
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
          ? WelcomeSplash(assistantName: widget.state.assistantName)
          : widget.state.onboarded
          ? Home(state: widget.state)
          : Onboarding(state: widget.state),
      routes: {
        '/home': (_) => Home(state: widget.state),
        '/chat': (context) {
          final draft = ModalRoute.of(context)?.settings.arguments;
          return ChatScreen(
            state: widget.state,
            initialDraft: draft is String ? draft : null,
          );
        },
        '/voice': (_) => ChatScreen(state: widget.state, startWithVoice: true),
        '/settings': (_) => Settings(state: widget.state),
        '/memory': (_) => Memories(state: widget.state),
        '/library': (_) => PhoneLibrary(state: widget.state),
        '/study': (_) => StudyScreen(state: widget.state),
        '/files': (_) => SelectedFiles(state: widget.state),
        '/automations': (_) => ActionHistory(state: widget.state),
        '/drafts': (_) => const OutboundDraftsScreen(),
        '/skills': (_) => SafeSkillsScreen(state: widget.state),
      },
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
  final String? assistantName;
  final Widget child;
  final List<Widget>? actions;
  final bool primaryNavigation;
  const Shell({
    super.key,
    required this.title,
    required this.child,
    this.assistantName,
    this.actions,
    this.primaryNavigation = true,
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
      bottomNavigationBar: primaryNavigation
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
                constraints: const BoxConstraints(maxWidth: 700),
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
                  const _SettingsSectionLabel('TOOLS'),
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
                  const _SettingsSectionLabel('PREFERENCES'),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
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
              gradient: selected
                  ? LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        colors.primary.withValues(alpha: .18),
                        colors.secondary.withValues(alpha: .10),
                      ],
                    )
                  : null,
              border: selected
                  ? Border.all(color: colors.primary.withValues(alpha: .22))
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
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
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
    final home = currentRoute == null || currentRoute == '/home';
    final chat = currentRoute == '/chat' || currentRoute == '/voice';
    final memory =
        currentRoute == '/memory' ||
        currentRoute == '/library' ||
        currentRoute == '/files';
    final settings = currentRoute == '/settings';
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              height: 78,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
              decoration: BoxDecoration(
                color: colors.surface.withValues(alpha: dark ? .76 : .72),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: Colors.white.withValues(alpha: dark ? .16 : .78),
                ),
                boxShadow: [
                  BoxShadow(
                    color: colors.primary.withValues(alpha: dark ? .12 : .10),
                    blurRadius: 28,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  _DockItem(
                    icon: Icons.home_outlined,
                    selectedIcon: Icons.home_rounded,
                    label: 'Home',
                    selected: home,
                    onTap: () => _navigate(context, '/home'),
                  ),
                  _DockItem(
                    icon: Icons.chat_bubble_outline_rounded,
                    selectedIcon: Icons.chat_bubble_rounded,
                    label: 'Chat',
                    selected: chat,
                    onTap: () => _navigate(context, '/chat'),
                  ),
                  Expanded(
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
                                onTap: () => _navigate(context, '/voice'),
                                child: Container(
                                  width: 47,
                                  height: 47,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        colors.primary,
                                        colors.secondary,
                                      ],
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: colors.primary.withValues(
                                          alpha: .32,
                                        ),
                                        blurRadius: 17,
                                        offset: const Offset(0, 5),
                                      ),
                                    ],
                                  ),
                                  child: Icon(
                                    Icons.mic_rounded,
                                    color: colors.onPrimary,
                                    size: 23,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          'Voice',
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontSize: 9,
                            height: 1.1,
                            fontWeight: FontWeight.w600,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _DockItem(
                    icon: Icons.psychology_alt_outlined,
                    selectedIcon: Icons.psychology_alt_rounded,
                    label: 'Memory',
                    selected: memory,
                    onTap: () => _navigate(context, '/memory'),
                  ),
                  _DockItem(
                    icon: Icons.tune_rounded,
                    selectedIcon: Icons.tune_rounded,
                    label: 'Settings',
                    selected: settings,
                    onTap: () => _navigate(context, '/settings'),
                  ),
                ],
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
  const _DockItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: AnimatedContainer(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.symmetric(horizontal: 1),
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              color: selected ? colors.primary.withValues(alpha: .09) : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  selected ? selectedIcon : icon,
                  size: 21,
                  color: selected ? colors.primary : colors.onSurfaceVariant,
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 9,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? colors.primary : colors.onSurfaceVariant,
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

ThemeData _assistantTheme(Brightness brightness, String paletteId) {
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
  final outline = OutlineInputBorder(
    borderRadius: fieldRadius,
    borderSide: BorderSide(
      color: scheme.outlineVariant.withValues(alpha: dark ? .48 : .54),
    ),
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
        alpha: dark ? .42 : .52,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      border: outline,
      enabledBorder: outline,
      focusedBorder: OutlineInputBorder(
        borderRadius: fieldRadius,
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
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
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            textStyle: const TextStyle(fontWeight: FontWeight.w600),
          ).copyWith(
            animationDuration: const Duration(milliseconds: 220),
            splashFactory: InkSparkle.splashFactory,
          ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style:
          OutlinedButton.styleFrom(
            minimumSize: const Size(0, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
          ).copyWith(
            animationDuration: const Duration(milliseconds: 220),
            splashFactory: InkSparkle.splashFactory,
          ),
    ),
    textButtonTheme: TextButtonThemeData(
      style:
          TextButton.styleFrom(
            minimumSize: const Size(40, 44),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
          ).copyWith(
            animationDuration: const Duration(milliseconds: 220),
            splashFactory: InkSparkle.splashFactory,
          ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style:
          IconButton.styleFrom(
            foregroundColor: scheme.onSurfaceVariant,
            shape: const CircleBorder(),
          ).copyWith(
            animationDuration: const Duration(milliseconds: 200),
            splashFactory: InkSparkle.splashFactory,
          ),
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      minVerticalPadding: 10,
      horizontalTitleGap: 12,
      enableFeedback: true,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
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

class Home extends StatelessWidget {
  final AssistantState state;
  const Home({super.key, required this.state});
  Future<void> action(
    BuildContext context,
    Map<String, dynamic> action, {
    LaunchableApp? selectedApp,
  }) async {
    try {
      final draft = action['kind'] == 'open_app'
          ? await state.prepareSelectedAppLaunch(
              selectedApp ??
                  (throw ServiceException(
                    'Choose an app from the installed-app list.',
                  )),
            )
          : await state.prepareAction(action);
      if (!context.mounted) {
        return;
      }
      final description = action['kind'] == 'reminder'
          ? 'Schedule “${action['title']}” for ${DateTime.fromMillisecondsSinceEpoch(action['at_ms'])}. Android delivery is approximate; battery restrictions may delay it.'
          : 'Open ${selectedApp!.label} (${selectedApp.packageName}) on this device.';
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final openTasks = state.local
        .rows('tasks')
        .where((row) => !row['done'])
        .toList();
    final attempts = state.local.rows('attempts');
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
    final modeLabel = state.engine == 'offline'
        ? state.experimentalOfflineChatEnabled
            ? 'Experimental Gemma · local only'
            : 'Gemma opt-in needed'
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
                        state.engine == 'offline'
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

class ChatScreen extends StatefulWidget {
  final AssistantState state;
  final String? initialDraft;
  final bool startWithVoice;
  const ChatScreen({
    super.key,
    required this.state,
    this.initialDraft,
    this.startWithVoice = false,
  });
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final input = TextEditingController();
  static const voiceEvents = MethodChannel('personal_assistant/voice');
  static const audioEvents = MethodChannel('personal_assistant/audio');
  final tts = FlutterTts();
  bool listening = false, speaking = false;
  bool _draftApplied = false;
  bool _initialVoiceStarted = false;
  double level = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_draftApplied && widget.initialDraft != null) {
      input.text = widget.initialDraft!;
      _draftApplied = true;
    }
    if (widget.startWithVoice && !_initialVoiceStarted) {
      _initialVoiceStarted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) listen();
      });
    }
  }

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
        assistantName: state.assistantName,
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
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Glass(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                bottomSpacing: 2,
                child: Row(
                  children: [
                    Icon(
                      Icons.shield_outlined,
                      size: 18,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${state.config.description} · ${state.language} · ${state.specialist}. No automatic online fallback. Memory scope: ${state.conversation}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
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
                          constraints: const BoxConstraints(maxWidth: 560),
                          child: Glass(
                            tintColor: m['role'] == 'user'
                                ? Theme.of(context).colorScheme.primary
                                : null,
                            padding: const EdgeInsets.all(16),
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
                                    onPressed: () => playExpressiveVoice(
                                      m['text'] as String,
                                    ),
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
            if (listening || state.busy || speaking)
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
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Glass(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                bottomSpacing: 0,
                borderRadius: BorderRadius.circular(28),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    ActivityHalo(
                      active: listening,
                      color: Theme.of(context).colorScheme.primary,
                      child: IconButton.filledTonal(
                        tooltip: listening
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
                            listening
                                ? Icons.mic_rounded
                                : Icons.mic_none_rounded,
                            key: ValueKey(listening),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: TextField(
                        controller: input,
                        minLines: 1,
                        maxLines: 5,
                        maxLength: 8000,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          hintText: 'Message your assistant…',
                          filled: false,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 14,
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
                        onPressed: state.busy || speaking ? stopAll : send,
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
        Row(
          children: [
            for (var i = 0; i < FuturisticPalette.all.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: _FuturisticThemeChoice(
                  palette: FuturisticPalette.all[i],
                  selected: state.visualTheme == FuturisticPalette.all[i].id,
                  onTap: () => _choose(context, FuturisticPalette.all[i].id),
                ),
              ),
            ],
          ],
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

  Future<void> _setExperimentalOfflineChat(bool enabled) async {
    if (enabled) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Try experimental Gemma chat?'),
          content: const Text(
            'Gemma 4 E4B has not passed answer-quality or Redmi/HyperOS memory, speed and heat testing. It may give wrong answers, run slowly, or make the phone warm. You must download and load the 3.66 GB model yourself. Typed chat prompts will stay on this phone; errors never switch to an online provider. Continue only as an experiment.',
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
              ? 'Experimental local chat is opted in. Download and load Gemma below; it is still unqualified.'
              : 'Experimental local chat is off. The model is not used for normal chat.',
        );
      }
    } catch (error) {
      if (mounted) notice(context, error);
    }
  }

  Future<void> _exportLocalBackup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Export a private backup?'),
        content: const Text(
          'This creates a readable, unencrypted JSON copy of your on-phone chats, approved memories, notes, tasks, study records and action receipts. Provider API keys and service tokens are stored separately and are not included. Choose a private save location. Restore is not available in this build.',
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
      final result = await AssistantState.device.invokeMapMethod<String, dynamic>(
        'export',
        {
          'text': widget.state.exportLocalData(),
          'filename': 'personal-ai-backup.json',
        },
      );
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
                'Choose how your assistant looks, speaks and connects.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const _SettingsSectionLabel('PRIVACY & ACCESS'),
        const Glass(
          child: Text(
            'Your chats, approved memories, notes, tasks and study records stay on this phone. Gemma is an experimental offline option that requires your opt-in, a manual download and load; it is not qualified for this phone. Online requests require explicit payload review. The private FastAPI adapter remains optional.',
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
            secondary: const _SettingsIconTile(icon: Icons.lock_outline),
            title: const Text('App lock'),
            subtitle: const Text(
              'Require your phone’s biometric or screen lock when opening or returning to the app.',
            ),
          ),
        ),
        const _SettingsSectionLabel('DEVICE ACCESS'),
        const AndroidAccessPanel(),
        const _SettingsSectionLabel('APPEARANCE'),
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
                        _ => 'Dark',
                      }),
                    ),
                ],
                onChanged: (value) => setState(() => theme = value ?? 'system'),
              ),
            ],
          ),
        ),
        const _SettingsSectionLabel('AI & VOICE'),
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
                    'offline': 'Offline · Gemma (experimental)',
                    'compatible': 'Online · OpenAI-compatible',
                    'private_service': 'Online · private FastAPI',
                  }.entries)
                    DropdownMenuItem(value: item.key, child: Text(item.value)),
                ],
                onChanged: (v) => setState(() => engine = v!),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: widget.state.experimentalOfflineChatEnabled,
                onChanged: (enabled) => _setExperimentalOfflineChat(enabled),
                secondary: const _SettingsIconTile(icon: Icons.memory_rounded),
                title: const Text('Use Gemma in normal chat · experimental'),
                subtitle: const Text(
                  'Explicit opt-in. Select Offline · Gemma and save settings to use it. It only runs locally after you download and load the model. Not qualified for Redmi/HyperOS; replies may be inaccurate, slow or heat the phone. There is no online fallback.',
                ),
              ),
              const SizedBox(height: 16),
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
                Text(
                  widget.state.experimentalOfflineChatEnabled
                      ? 'Experimental local chat is opted in. Download and load Gemma in the model panel below; it will not contact a network service.'
                      : 'Offline chat needs your explicit experimental opt-in and a downloaded, loaded Gemma model. No online fallback is used.',
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
        const _SettingsSectionLabel('WORKFLOWS'),
        Glass(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.edit_note_rounded),
                title: const Text('Message & social drafts'),
                subtitle: const Text('Edit text, then use Android’s share sheet; nothing is sent automatically.'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.pushNamed(context, '/drafts'),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.auto_awesome_outlined),
                title: const Text('Skills & actions'),
                subtitle: const Text('Reviewed local app launches and reminders; no background agent.'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.pushNamed(context, '/skills'),
              ),
            ],
          ),
        ),
        const _SettingsSectionLabel('CONNECTED TOOLS'),
        CustomMcpPanel(state: widget.state),
        const _SettingsSectionLabel('OFFLINE MODEL & EXPERIMENTAL CHAT'),
        const Text('The optional model is downloaded only when you start it. You can run fixed screening prompts or, after opting in above, use it for normal chat. Neither option means the model is qualified for your phone.'),
        const SizedBox(height: 8),
        const OfflineModelPanel(),
        const _SettingsSectionLabel('VOICE CAPABILITIES'),
        TextButton(
          onPressed: () async {
            try {
              final info = await AssistantState.device.invokeMapMethod(
                'device_status',
              );
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
        const _SettingsSectionLabel('DATA & PRIVACY'),
        Glass(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Local backup', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              const Text('Export is manual and owner-confirmed. The JSON file is readable and unencrypted; save it somewhere private. Provider keys and service tokens are excluded. Import/restore is not implemented.'),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _exportLocalBackup,
                icon: const Icon(Icons.download_outlined),
                label: const Text('Export local data'),
              ),
            ],
          ),
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
        notice(
          context,
          'Wajo OAuth connected on this phone. No tools were run.',
        );
      }
    } catch (e) {
      if (mounted) notice(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _discover(McpServer server) async {
    setState(() => busy = true);
    try {
      final tools = await widget.state.discoverMcpTools(server.id);
      if (!mounted) return;
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
                              ],
                            ),
                          ),
                        const Text(
                          'Discovery only. Tools cannot be invoked by this app yet.',
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
          'Add a remote Model Context Protocol server and inspect its advertised tools. Endpoints must use HTTPS (loopback HTTP is allowed for local testing). Treat servers and tool descriptions as untrusted.',
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
          'No tool is automatically invoked. MCP tool execution and per-action approval integration are not implemented in this version.',
        ),
        const SizedBox(height: 4),
        const Text(
          'Wajo Fo OAuth is optional. Adding its preset does not connect it; the Connect with OAuth action performs discovery and native-client registration before opening sign-in.',
        ),
      ],
    ),
  );
}
