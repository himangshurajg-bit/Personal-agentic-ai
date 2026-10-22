import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

const homeOrbDisclosure =
    'Decorative generative art. It does not show AI activity or connect to a model.';

/// Restrict the WebView to its one bundled page; there is no JS bridge.
bool homeOrbAllowsNavigation(String rawUrl) {
  final uri = Uri.tryParse(rawUrl);
  return uri != null &&
      uri.scheme == 'file' &&
      uri.host.isEmpty &&
      uri.path.endsWith('/assets/home_orb.html') &&
      uri.query.isEmpty &&
      uri.fragment.isEmpty;
}

class DecorativeHomeOrb extends StatefulWidget {
  const DecorativeHomeOrb({super.key});

  @override
  State<DecorativeHomeOrb> createState() => _DecorativeHomeOrbState();
}

class _DecorativeHomeOrbState extends State<DecorativeHomeOrb> {
  WebViewController? _controller;
  bool _failed = false;

  bool get _supportsWebView =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void initState() {
    super.initState();
    if (_supportsWebView) _initializeWebView();
  }

  Future<void> _initializeWebView() async {
    try {
      final controller = WebViewController();
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) => homeOrbAllowsNavigation(request.url)
              ? NavigationDecision.navigate
              : NavigationDecision.prevent,
          onWebResourceError: (error) {
            if (error.isForMainFrame == true && mounted) {
              setState(() => _failed = true);
            }
          },
        ),
      );
      await controller.setBackgroundColor(Colors.transparent);
      if (!mounted) return;
      setState(() => _controller = controller);
      await controller.loadFlutterAsset('assets/home_orb.html');
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMobile = _supportsWebView;
    final controller = _controller;
    return Semantics(
      container: true,
      label: homeOrbDisclosure,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: .48,
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.blur_on_rounded, color: theme.colorScheme.primary),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'Home orb',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: SizedBox(
                height: 238,
                width: double.infinity,
                child: isMobile && !_failed && controller != null
                    ? WebViewWidget(controller: controller)
                    : _fallback(theme),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              homeOrbDisclosure,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fallback(ThemeData theme) => Container(
    decoration: const BoxDecoration(
      gradient: RadialGradient(
        colors: [Color(0xff174b4b), Color(0xff091c20), Color(0xff081414)],
      ),
    ),
    child: Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 174,
            height: 174,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0x777af6e3)),
              boxShadow: const [
                BoxShadow(color: Color(0x5545dbd1), blurRadius: 28),
              ],
            ),
          ),
          Container(
            width: 106,
            height: 106,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  Color(0xffe3fff8),
                  Color(0xff4bcac5),
                  Color(0xff125165),
                ],
              ),
            ),
          ),
          Icon(
            Icons.auto_awesome_rounded,
            size: 34,
            color: theme.colorScheme.onPrimary,
          ),
        ],
      ),
    ),
  );
}
