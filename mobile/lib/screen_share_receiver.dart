import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'assistant_state.dart';

const int _maxFrameBytes = 1500000;
const int _maxFrameWidth = 4096;
const int _maxFrameHeight = 4096;
const int _maxFramePixels = 8294400;

class JpegDimensions {
  final int width;
  final int height;
  const JpegDimensions(this.width, this.height);
}

/// Finds a bounded JPEG SOF header before handing untrusted bytes to Flutter's
/// image decoder. It rejects malformed segments and oversized dimensions.
Future<Uint8List> readBoundedScreenFrame(http.StreamedResponse response) async {
  final declaredLength = response.contentLength;
  if (declaredLength != null && declaredLength > _maxFrameBytes) {
    throw ServiceException('A screen frame exceeded the size limit.');
  }
  final bytes = BytesBuilder(copy: false);
  var length = 0;
  await for (final chunk in response.stream.timeout(
    const Duration(seconds: 8),
  )) {
    if (chunk.length > _maxFrameBytes - length) {
      throw ServiceException('A screen frame exceeded the size limit.');
    }
    length += chunk.length;
    bytes.add(chunk);
  }
  return bytes.takeBytes();
}

JpegDimensions? boundedJpegDimensions(Uint8List bytes) {
  if (bytes.length < 12 ||
      bytes.length > _maxFrameBytes ||
      bytes[0] != 0xff ||
      bytes[1] != 0xd8 ||
      bytes[bytes.length - 2] != 0xff ||
      bytes[bytes.length - 1] != 0xd9) {
    return null;
  }

  const sofMarkers = <int>{
    0xc0,
    0xc1,
    0xc2,
    0xc3,
    0xc5,
    0xc6,
    0xc7,
    0xc9,
    0xca,
    0xcb,
    0xcd,
    0xce,
    0xcf,
  };
  var offset = 2;
  while (offset < bytes.length - 2) {
    if (bytes[offset] != 0xff) return null;
    while (offset < bytes.length && bytes[offset] == 0xff) {
      offset++;
    }
    if (offset >= bytes.length) return null;
    final marker = bytes[offset++];
    if (marker == 0x00 || marker == 0xd9) return null;
    if (marker == 0xd8 ||
        marker == 0x01 ||
        (marker >= 0xd0 && marker <= 0xd7)) {
      continue;
    }
    if (offset + 2 > bytes.length - 2) return null;
    final segmentLength = (bytes[offset] << 8) | bytes[offset + 1];
    if (segmentLength < 2 || offset + segmentLength > bytes.length - 2) {
      return null;
    }
    if (sofMarkers.contains(marker)) {
      if (segmentLength < 8) return null;
      final height = (bytes[offset + 3] << 8) | bytes[offset + 4];
      final width = (bytes[offset + 5] << 8) | bytes[offset + 6];
      if (width < 1 ||
          height < 1 ||
          width > _maxFrameWidth ||
          height > _maxFrameHeight ||
          width * height > _maxFramePixels) {
        return null;
      }
      return JpegDimensions(width, height);
    }
    offset += segmentLength;
  }
  return null;
}

class ScreenShareReceiverScreen extends StatefulWidget {
  final AssistantState state;
  const ScreenShareReceiverScreen({super.key, required this.state});

  @override
  State<ScreenShareReceiverScreen> createState() =>
      _ScreenShareReceiverScreenState();
}

class _ScreenShareReceiverScreenState extends State<ScreenShareReceiverScreen>
    with WidgetsBindingObserver {
  List<Map<String, dynamic>> _pairings = [];
  List<Map<String, dynamic>> _sessions = [];
  String? _pairingCode;
  String? _pairingId;
  DateTime? _pairingDeadline;
  String? _viewSessionId;
  Uint8List? _frame;
  int _frameSequence = 0;
  String? _error;
  String? _frameError;
  bool _loading = false;
  bool _refreshing = false;
  bool _loadingFrame = false;
  Timer? _refreshTimer;
  Timer? _frameTimer;

  AssistantState get _state => widget.state;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => unawaited(_refresh()),
    );
    unawaited(_refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      // Leaving the foreground ends every live/approved session we know about.
      // The sender must also stop MediaProjection when its socket closes.
      unawaited(_stopLiveSessions(quiet: true));
    } else if (state == AppLifecycleState.resumed) {
      unawaited(_refresh());
    }
  }

  List<Map<String, dynamic>> _rows(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  Future<void> _refresh() async {
    if (_refreshing || !mounted) return;
    _refreshing = true;
    try {
      final results = await Future.wait([
        _state.request('GET', '/screen-share/pairings'),
        _state.request('GET', '/screen-share/sessions'),
      ]);
      if (!mounted) return;
      final pairings = _rows(results[0]);
      final sessions = _rows(results[1]);
      final approvedOrActive = sessions.where((session) {
        final status = session['state'];
        return status == 'active' || status == 'approved';
      }).toList();
      final currentView = _viewSessionId;
      final currentStillActive =
          currentView != null &&
          sessions.any(
            (session) =>
                session['session_id'] == currentView &&
                session['state'] == 'active',
          );
      final nextView = currentStillActive
          ? currentView
          : (approvedOrActive
                .where((session) => session['state'] == 'active')
                .map((session) => session['session_id']?.toString())
                .whereType<String>()
                .firstOrNull);
      final currentPairingCode = _pairingCode;
      final pendingPairingStillWaiting =
          currentPairingCode != null &&
          pairings.any(
            (pairing) =>
                pairing['pairing_id'] == _pairingId &&
                pairing['state'] == 'waiting_for_sender',
          );
      setState(() {
        _pairings = pairings;
        _sessions = sessions;
        _viewSessionId = nextView;
        if (currentPairingCode != null && !pendingPairingStillWaiting) {
          // Once redeemed, expired or revoked, the one-time capability is no
          // longer displayed or retained by this screen.
          _pairingCode = null;
          _pairingId = null;
          _pairingDeadline = null;
        }
        _error = null;
      });
      _syncFrameTimer();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _createPairing() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
      _pairingCode = null;
      _pairingId = null;
      _pairingDeadline = null;
    });
    try {
      final result = await _state.request('POST', '/screen-share/pairings');
      if (result is! Map ||
          result['pairing_id'] is! String ||
          result['pairing_code'] is! String ||
          !RegExp(r'^[A-Za-z0-9_-]{32,64}$')
              .hasMatch(result['pairing_code'] as String) ||
          result['expires_in_seconds'] is! int ||
          (result['expires_in_seconds'] as int) < 1 ||
          (result['expires_in_seconds'] as int) > 300 ||
          !RegExp(r'^[a-f0-9]{32}$').hasMatch(result['pairing_id'] as String)) {
        throw const FormatException(
          'The service returned an invalid pairing response.',
        );
      }
      if (!mounted) return;
      setState(() {
        _pairingId = result['pairing_id'] as String;
        _pairingCode = result['pairing_code'] as String;
        _pairingDeadline = DateTime.now().add(
          Duration(seconds: result['expires_in_seconds'] as int),
        );
      });
    } catch (error) {
      if (mounted) {
        // Do not retry a POST automatically: the service may have created a
        // code even if the response was lost. Refresh reveals revocable state.
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    if (mounted) await _refresh();
  }

  String? get _pairingInvitation {
    final id = _pairingId;
    final code = _pairingCode;
    if (id == null || code == null) return null;
    return '{"pairing_id":"$id","pairing_code":"$code"}';
  }

  Future<void> _copyPairingInvitation() async {
    final invitation = _pairingInvitation;
    if (invitation == null) return;
    await Clipboard.setData(ClipboardData(text: invitation));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Temporary pairing invitation copied. Paste it only into MYRA on the device you intend to pair.',
          ),
        ),
      );
    }
  }

  Future<void> _approveSession(Map<String, dynamic> session) async {
    final id = session['session_id']?.toString();
    if (id == null || !RegExp(r'^[a-f0-9]{32}$').hasMatch(id) || _loading) {
      return;
    }
    final sender = _senderLabel(session['pairing_id']?.toString());
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Allow this screen share?'),
        content: Text(
          'Allow $sender to send one live screen-share session? This approval applies only to this request. The sender must still receive Android’s own screen-capture consent and start its foreground service.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Approve this session'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    await _mutate('POST', '/screen-share/sessions/$id/approve');
  }

  Future<void> _stopSession(String id) async {
    if (_loading || !RegExp(r'^[a-f0-9]{32}$').hasMatch(id)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Stop screen sharing?'),
        content: const Text(
          'This ends the selected session and asks the sender to stop its stream. The sender must stop Android MediaProjection and its foreground service when the socket closes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep sharing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Stop this session'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _mutate('POST', '/screen-share/sessions/$id/stop');
    }
  }

  Future<void> _revokePairing(Map<String, dynamic> pairing) async {
    final id = pairing['pairing_id']?.toString();
    if (id == null || !RegExp(r'^[a-f0-9]{32}$').hasMatch(id) || _loading) {
      return;
    }
    final label = _senderLabel(id);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove paired device?'),
        content: Text(
          'Revoke $label? Its sender token will stop working, and any share session from it will be ended.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Revoke device'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _mutate('POST', '/screen-share/pairings/$id/revoke');
    }
  }

  Future<void> _mutate(String method, String path) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _state.request(method, path);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    // For a timed-out write, inspect authoritative state before exposing any
    // retry. The user can refresh manually if this read also fails.
    if (mounted) await _refresh();
  }

  Future<void> _stopLiveSessions({bool quiet = false}) async {
    final liveIds = _sessions
        .where(
          (session) =>
              session['state'] == 'active' || session['state'] == 'approved',
        )
        .map((session) => session['session_id']?.toString())
        .whereType<String>()
        .where((id) => RegExp(r'^[a-f0-9]{32}$').hasMatch(id))
        .toList(growable: false);
    _frameTimer?.cancel();
    _frameTimer = null;
    if (liveIds.isEmpty) return;
    for (final id in liveIds) {
      try {
        await _state.request('POST', '/screen-share/sessions/$id/stop');
      } catch (error) {
        if (!quiet && mounted) setState(() => _error = error.toString());
      }
    }
    if (mounted) {
      setState(() {
        _frame = null;
        _viewSessionId = null;
      });
      if (!quiet) await _refresh();
    }
  }

  String _senderLabel(String? pairingId) {
    if (pairingId == null) return 'Unknown paired sender';
    for (final pairing in _pairings) {
      if (pairing['pairing_id'] == pairingId) {
        final label = pairing['sender_label']?.toString().trim();
        if (label != null && label.isNotEmpty) {
          return label.replaceAll(
            RegExp(r'[\u0000-\u001f\u007f-\u009f\u202a-\u202e\u2066-\u2069]'),
            ' ',
          );
        }
      }
    }
    return 'Unknown paired sender';
  }

  void _syncFrameTimer() {
    final selected = _viewSessionId;
    final active =
        selected != null &&
        _sessions.any(
          (session) =>
              session['session_id'] == selected && session['state'] == 'active',
        );
    if (active && _frameTimer == null) {
      _frameTimer = Timer.periodic(
        const Duration(milliseconds: 350),
        (_) => unawaited(_fetchFrame()),
      );
      unawaited(_fetchFrame());
    } else if (!active) {
      _frameTimer?.cancel();
      _frameTimer = null;
      if (_frame != null && mounted) setState(() => _frame = null);
    }
  }

  Future<void> _fetchFrame() async {
    if (_loadingFrame || !mounted) return;
    final sessionId = _viewSessionId;
    if (sessionId == null || !RegExp(r'^[a-f0-9]{32}$').hasMatch(sessionId)) {
      return;
    }
    _loadingFrame = true;
    final client = _state.clientFactory();
    try {
      final endpoint = checkedEndpoint(_state.privateServiceEndpoint);
      final uri = endpoint.replace(
        path: '/screen-share/sessions/$sessionId/frame',
        queryParameters: {'after_sequence': '$_frameSequence'},
      );
      final request = http.Request('GET', uri)..followRedirects = false;
      request.headers.addAll(_state.headers);
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 204) return;
      if (response.statusCode != 200) {
        throw ServiceException(
          'The frame request was refused (${response.statusCode}). Refresh the session status before continuing.',
        );
      }
      final mediaType = response.headers['content-type']
          ?.split(';')
          .first
          .trim()
          .toLowerCase();
      final sequence = int.tryParse(response.headers['x-frame-sequence'] ?? '');
      if (mediaType != 'image/jpeg' ||
          sequence == null ||
          sequence <= _frameSequence) {
        throw ServiceException('The service returned an invalid screen frame.');
      }
      final bytes = await readBoundedScreenFrame(response);
      final dimensions = boundedJpegDimensions(bytes);
      if (dimensions == null) {
        throw ServiceException(
          'A frame was rejected because its JPEG header or dimensions were invalid.',
        );
      }
      if (!mounted || _viewSessionId != sessionId) return;
      setState(() {
        _frame = bytes;
        _frameSequence = sequence;
        _frameError = null;
      });
    } catch (error) {
      if (mounted && _viewSessionId == sessionId) {
        setState(() => _frameError = error.toString());
      }
    } finally {
      client.close();
      _loadingFrame = false;
    }
  }

  void _selectSession(String id) {
    if (!mounted || !RegExp(r'^[a-f0-9]{32}$').hasMatch(id)) return;
    setState(() {
      _viewSessionId = id;
      _frame = null;
      _frameError = null;
      _frameSequence = 0;
    });
    _syncFrameTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _frameTimer?.cancel();
    // Navigation away is a stop action for this foreground-only viewer.
    unawaited(_stopLiveSessions(quiet: true));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasToken = _state.privateServiceToken.isNotEmpty;
    final endpoint = Uri.tryParse(_state.privateServiceEndpoint.trim());
    final loopbackHttp = endpoint?.scheme == 'http';
    final hasLiveSession = _sessions.any(
      (session) =>
          session['state'] == 'active' || session['state'] == 'approved',
    );
    final waitingSessions = _sessions
        .where((session) => session['state'] == 'awaiting_receiver_approval')
        .toList(growable: false);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Screen-share receiver'),
        actions: [
          IconButton(
            tooltip: 'Refresh session status',
            onPressed: _refreshing ? null : () => unawaited(_refresh()),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.shield_outlined),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Pair first. Approve each share.',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'A paired device cannot view your screen until you approve its specific request. This viewer keeps the latest frame in memory only and sends a stop request for known sessions when you leave this screen or the app goes to the background. If the network is unavailable, use Stop when connected; the sender must also stop when its stream closes.',
                  ),
                  if (loopbackHttp) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'The service uses plain HTTP on a local address and cannot be reached from another phone. Cross-device sharing needs an owner-controlled HTTPS/WSS service. Do not expose the development server directly to the Internet.',
                    ),
                  ],
                  if (!hasToken) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Set the private service endpoint and owner token in Settings → API & MCP connections before pairing.',
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (_error != null)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_error!),
              ),
            ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pair a sender',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Create a one-time code that expires after five minutes. Share it only with the device you intend to pair; anyone holding it can claim that pairing.',
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: !hasToken || _loading ? null : _createPairing,
                    icon: const Icon(Icons.add_link_rounded),
                    label: Text(_loading ? 'Working…' : 'Create pairing code'),
                  ),
                  if (_pairingCode != null) ...[
                    const SizedBox(height: 12),
                    Text('Pairing ID: ${_pairingId ?? ''}'),
                    SelectableText(
                      _pairingCode!,
                      key: const Key('screen-share-pairing-code'),
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(letterSpacing: 2),
                    ),
                    Text(
                      'One-time code · expires ${_pairingDeadline?.toLocal().toString().substring(11, 16) ?? 'soon'}',
                    ),
                    TextButton.icon(
                      onPressed: _copyPairingInvitation,
                      icon: const Icon(Icons.copy_rounded),
                      label: const Text('Copy invitation for MYRA'),
                    ),
                  ],
                ],
              ),
            ),
          ),
          _sectionTitle(context, 'Paired devices'),
          if (_pairings.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(14),
                child: Text('No paired sender is available yet.'),
              ),
            ),
          for (final pairing in _pairings)
            Card(
              child: ListTile(
                leading: Icon(
                  pairing['state'] == 'paired'
                      ? Icons.devices_rounded
                      : Icons.hourglass_empty_rounded,
                ),
                title: Text(_senderLabel(pairing['pairing_id']?.toString())),
                subtitle: Text(
                  pairing['state'] == 'paired'
                      ? 'Paired · each screen share still needs approval'
                      : 'Pairing code ${pairing['state'] ?? 'pending'}',
                ),
                trailing: pairing['state'] == 'paired'
                    ? IconButton(
                        tooltip: 'Revoke paired device',
                        onPressed: _loading
                            ? null
                            : () => _revokePairing(pairing),
                        icon: const Icon(Icons.link_off_rounded),
                      )
                    : null,
              ),
            ),
          _sectionTitle(context, 'Share requests'),
          if (waitingSessions.isEmpty && !hasLiveSession)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(14),
                child: Text('No pending or active screen-share sessions.'),
              ),
            ),
          for (final session in _sessions)
            if (const {
              'awaiting_receiver_approval',
              'approved',
              'active',
            }.contains(session['state']))
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: [
                      ListTile(
                        leading: Icon(
                          session['state'] == 'active'
                              ? Icons.screen_share_rounded
                              : Icons.pending_actions_rounded,
                        ),
                        title: Text(
                          _senderLabel(session['pairing_id']?.toString()),
                        ),
                        subtitle: Text(switch (session['state']) {
                          'awaiting_receiver_approval' =>
                            'Waiting for your approval',
                          'approved' =>
                            'Approved · waiting for the sender to start',
                          _ => 'Screen share is active',
                        }),
                      ),
                      if (session['state'] == 'awaiting_receiver_approval')
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                          child: FilledButton.icon(
                            onPressed: _loading || hasLiveSession
                                ? null
                                : () => _approveSession(session),
                            icon: const Icon(Icons.visibility_outlined),
                            label: const Text('Review and approve'),
                          ),
                        ),
                      if (session['state'] == 'approved')
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                          child: OutlinedButton.icon(
                            onPressed: _loading
                                ? null
                                : () => _stopSession(
                                    session['session_id'].toString(),
                                  ),
                            icon: const Icon(Icons.stop_circle_outlined),
                            label: const Text('Cancel approval'),
                          ),
                        ),
                      if (session['state'] == 'active')
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              OutlinedButton.icon(
                                onPressed:
                                    _viewSessionId == session['session_id']
                                    ? null
                                    : () => _selectSession(
                                        session['session_id'].toString(),
                                      ),
                                icon: const Icon(Icons.visibility_outlined),
                                label: Text(
                                  _viewSessionId == session['session_id']
                                      ? 'Viewing'
                                      : 'View latest frame',
                                ),
                              ),
                              const SizedBox(width: 8),
                              FilledButton.tonalIcon(
                                onPressed: _loading
                                    ? null
                                    : () => _stopSession(
                                        session['session_id'].toString(),
                                      ),
                                icon: const Icon(Icons.stop_rounded),
                                label: const Text('Stop'),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          if (_viewSessionId != null &&
              _sessions.any(
                (session) =>
                    session['session_id'] == _viewSessionId &&
                    session['state'] == 'active',
              )) ...[
            _sectionTitle(context, 'Live preview'),
            Card(
              clipBehavior: Clip.antiAlias,
              child: AspectRatio(
                aspectRatio: 9 / 16,
                child: ColoredBox(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: _frame == null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Text(
                              _frameError ??
                                  'Waiting for a fresh screen frame…',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : Image.memory(
                          _frame!,
                          key: ValueKey(_frameSequence),
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.low,
                          cacheWidth: 960,
                          gaplessPlayback: true,
                          errorBuilder: (_, _, _) => const Center(
                            child: Text(
                              'The received image could not be decoded.',
                            ),
                          ),
                        ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          const Text(
            'Frames are not saved by this app. The current service stores only its latest frame in memory; restarting the service clears it. A trusted sender must still implement Android MediaProjection consent, a foreground service and stop-on-disconnect behavior.',
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 18, 8, 8),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
