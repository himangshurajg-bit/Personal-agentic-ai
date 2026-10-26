import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'assistant_state.dart';
import 'feature_services.dart';

const _featureVoiceEvents = MethodChannel('personal_assistant/feature_voice');

class FeaturesScreen extends StatelessWidget {
  final AssistantState state;
  final Future<void> Function(BuildContext, String) onReminder;
  final int initialTab;

  const FeaturesScreen({
    super.key,
    required this.state,
    required this.onReminder,
    this.initialTab = 0,
  });

  @override
  Widget build(BuildContext context) => DefaultTabController(
    initialIndex: initialTab,
    length: 3,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Assistant tools'),
        bottom: const TabBar(
          isScrollable: true,
          tabs: [
            Tab(icon: Icon(Icons.description_outlined), text: 'Files'),
            Tab(icon: Icon(Icons.mic_none_rounded), text: 'Voice actions'),
            Tab(icon: Icon(Icons.travel_explore_rounded), text: 'Research'),
          ],
        ),
      ),
      body: TabBarView(
        children: [
          _DocumentFeature(state: state),
          _VoiceActionsFeature(state: state, onReminder: onReminder),
          _ResearchFeature(state: state),
        ],
      ),
    ),
  );
}

class _DocumentFeature extends StatefulWidget {
  final AssistantState state;
  const _DocumentFeature({required this.state});
  @override
  State<_DocumentFeature> createState() => _DocumentFeatureState();
}

class _DocumentFeatureState extends State<_DocumentFeature> {
  final _question = TextEditingController();
  Uint8List? _bytes;
  String _name = '';
  String _mime = '';
  String _task = 'Summarize';
  FeatureAnswer? _answer;
  bool _busy = false;
  String _error = '';

  @override
  void dispose() {
    _question.dispose();
    _bytes?.fillRange(0, _bytes!.length, 0);
    super.dispose();
  }

  Future<void> _pickFile() async {
    setState(() {
      _error = '';
    });
    try {
      final result = await AssistantState.device
          .invokeMapMethod<String, dynamic>('pick_file', {'ai_document': true});
      if (result == null) return;
      final mime = result['mime'];
      final encoded = result['content_base64'];
      final name = result['name'];
      if (mime is! String || encoded is! String || name is! String) {
        throw FeatureServiceException(
          (result['unsupported'] as String?) ??
              'Choose a PDF or image on Android.',
        );
      }
      final bytes = base64Decode(encoded);
      if (!supportedAiDocumentMimes.contains(mime) ||
          bytes.isEmpty ||
          bytes.length > maxAiDocumentBytes) {
        bytes.fillRange(0, bytes.length, 0);
        throw const FeatureServiceException(
          'That file is not supported or exceeds 12 MB.',
        );
      }
      _bytes?.fillRange(0, _bytes!.length, 0);
      setState(() {
        _bytes = bytes;
        _mime = mime;
        _name = name;
        _answer = null;
        _error = '';
        _task = 'Summarize';
        _question.clear();
      });
    } on PlatformException catch (error) {
      if (error.code != 'cancelled' && mounted) {
        setState(
          () => _error =
              error.message ?? 'Could not open the Android document picker.',
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  GeminiFeatureClient? _client() {
    if (widget.state.engine != 'gemini') {
      setState(
        () => _error = 'Choose Gemini in Settings to use file understanding. Qwen offline chat is text-only and will not receive this file.',
      );
      return null;
    }
    return GeminiFeatureClient(
      model: widget.state.geminiModelSelection,
      apiKey: widget.state.geminiApiKey,
      clientFactory: widget.state.clientFactory,
    );
  }

  Future<void> _ask() async {
    final bytes = _bytes;
    if (bytes == null) {
      setState(() => _error = 'Choose a PDF or image first.');
      return;
    }
    final client = _client();
    if (client == null) return;
    final prompt = _question.text.trim().isNotEmpty
        ? _question.text.trim()
        : switch (_task) {
            'Explain' => 'Explain this file clearly, step by step. Define difficult terms and mention uncertainty.',
            'Make a quiz' => 'Create a short quiz about this file. Give questions first, then a separate answer key.',
            _ => 'Summarize this file. Highlight the main ideas and important details.',
          };
    if (client.apiKey.trim().isEmpty) {
      setState(
        () => _error =
            'Add a Gemini API key in Settings first. No file was sent.',
      );
      return;
    }
    final approved =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Send this file to Gemini?'),
            content: Text(
              '“$_name” and your question will be sent online to Google Gemini (${client.model}) for analysis. Google handles the content under its service terms. This feature does not add the file or answer to chat history; the selected file is held temporarily on this screen.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Send to Gemini'),
              ),
            ],
          ),
        ) ??
        false;
    if (!approved || !mounted) return;
    setState(() {
      _busy = true;
      _error = '';
      _answer = null;
    });
    try {
      final answer = await client.askDocument(
        mimeType: _mime,
        bytes: bytes,
        prompt: prompt,
      );
      if (mounted) setState(() => _answer = answer);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(18),
    children: [
      const _FeatureNotice(
        icon: Icons.privacy_tip_outlined,
        text: 'Choose a PDF or photo, then ask Gemini to summarize, explain or quiz you. The file is not sent until you review the online-send prompt. Qwen offline chat cannot inspect images or PDFs.',
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: _busy ? null : _pickFile,
        icon: const Icon(Icons.attach_file_rounded),
        label: Text(
          _bytes == null ? 'Choose PDF or photo' : 'Choose a different file',
        ),
      ),
      if (_name.isNotEmpty) ...[
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: Icon(
              _mime == 'application/pdf'
                  ? Icons.picture_as_pdf_outlined
                  : Icons.image_outlined,
            ),
            title: Text(_name, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              '$_mime · ${(_bytes!.lengthInBytes / 1024 / 1024).toStringAsFixed(1)} MB · kept temporarily on this screen',
            ),
            trailing: IconButton(
              tooltip: 'Remove file',
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _bytes?.fillRange(0, _bytes!.length, 0);
                      _bytes = null;
                      _name = '';
                      _mime = '';
                      _answer = null;
                      _question.clear();
                    }),
              icon: const Icon(Icons.close_rounded),
            ),
          ),
        ),
      ],
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        children: [
          for (final task in ['Summarize', 'Explain', 'Make a quiz'])
            ChoiceChip(
              label: Text(task),
              selected: _task == task,
              onSelected: _busy
                  ? null
                  : (_) => setState(() {
                      _task = task;
                      _question.clear();
                    }),
            ),
        ],
      ),
      const SizedBox(height: 10),
      TextField(
        controller: _question,
        minLines: 2,
        maxLines: 5,
        maxLength: 8000,
        decoration: const InputDecoration(
          labelText: 'Ask a follow-up (optional)',
          hintText: 'For example: explain the diagram on page 2',
          border: OutlineInputBorder(),
        ),
      ),
      FilledButton.icon(
        onPressed: _busy || _bytes == null ? null : _ask,
        icon: const Icon(Icons.auto_awesome),
        label: Text(_busy ? 'Analyzing…' : 'Ask Gemini about this file'),
      ),
      if (_busy)
        const Padding(
          padding: EdgeInsets.all(16),
          child: LinearProgressIndicator(),
        ),
      if (_error.isNotEmpty) _ErrorPanel(_error),
      if (_answer != null) ...[
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: MarkdownBody(data: _answer!.text),
          ),
        ),
        if (_answer!.sources.isNotEmpty) _SourceList(sources: _answer!.sources),
      ],
    ],
  );
}

class _VoiceActionsFeature extends StatefulWidget {
  final AssistantState state;
  final Future<void> Function(BuildContext, String) onReminder;
  const _VoiceActionsFeature({required this.state, required this.onReminder});
  @override
  State<_VoiceActionsFeature> createState() => _VoiceActionsFeatureState();
}

class _VoiceActionsFeatureState extends State<_VoiceActionsFeature> {
  final _command = TextEditingController();
  bool _listening = false;
  String _partial = '';
  String _error = '';

  @override
  void initState() {
    super.initState();
    _featureVoiceEvents.setMethodCallHandler(_onVoiceEvent);
  }

  @override
  void dispose() {
    _command.dispose();
    _featureVoiceEvents.setMethodCallHandler(null);
    unawaited(
      AssistantState.device
          .invokeMethod<void>('voice_cancel')
          .catchError((_) {}),
    );
    super.dispose();
  }

  Future<void> _onVoiceEvent(MethodCall call) async {
    if (call.method != 'voice_event' || call.arguments is! Map) return;
    final event = Map<String, dynamic>.from(call.arguments as Map);
    final kind = event['kind'];
    if (!mounted) return;
    if (kind == 'text') {
      setState(() {
        _listening = false;
        _partial = '';
      });
      final text = (event['value'] as String? ?? '').trim();
      if (text.isNotEmpty) {
        await _reviewTranscript(text);
      } else {
        setState(
          () =>
              _error = 'No words were recognized. Try again or type a command.',
        );
      }
    } else if (kind == 'partial') {
      setState(() => _partial = event['value'] as String? ?? '');
    } else if (kind == 'listening') {
      setState(() {
        _listening = true;
        _error = '';
      });
    } else if (kind == 'stopped') {
      setState(() => _listening = false);
    } else if (kind == 'error') {
      setState(() {
        _listening = false;
        _error =
            event['value']?.toString() ??
            'Speech recognition failed. Type instead.';
      });
    }
  }

  Future<void> _listen() async {
    final mode = widget.state.speechMode;
    if (mode == 'deepgram') {
      setState(
        () => _error = 'This command screen uses Android on-device or system speech recognition, not Deepgram. Change speech mode in Settings, or type a command.',
      );
      return;
    }
    var onlineApproved = false;
    if (mode == 'online') {
      onlineApproved =
          await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Use online speech recognition?'),
              content: Text(
                'Android’s speech service may send microphone audio to its provider to recognize ${widget.state.language}. This is separate from Gemini; audio is not sent to this app’s AI model. No automatic fallback will be used.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Start microphone'),
                ),
              ],
            ),
          ) ??
          false;
      if (!onlineApproved || !mounted) return;
    }
    try {
      setState(() {
        _error = '';
        _partial = '';
      });
      await AssistantState.device.invokeMethod<void>('voice_start', {
        'mode': mode,
        'feature_voice': true,
        'locale': widget.state.language,
        'approved_online': onlineApproved,
      });
    } on PlatformException catch (error) {
      if (mounted) {
        setState(() {
          _listening = false;
          _error =
              error.message ?? 'Speech unavailable. Type a command instead.';
        });
      }
    } on MissingPluginException {
      if (mounted) {
        setState(() {
          _listening = false;
          _error = 'Voice commands are supported by the Android build; type a command here instead.';
        });
      }
    }
  }

  Future<void> _stop() async {
    try {
      await AssistantState.device.invokeMethod<void>('voice_cancel');
    } catch (_) {}
    if (mounted) {
      setState(() {
        _listening = false;
        _partial = '';
      });
    }
  }

  Future<void> _reviewTranscript(String raw) async {
    final editor = TextEditingController(text: raw);
    final reviewed = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Review recognized words'),
        content: TextField(
          controller: editor,
          autofocus: true,
          minLines: 2,
          maxLines: 5,
          maxLength: 500,
          decoration: const InputDecoration(labelText: 'Command'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, editor.text.trim()),
            child: const Text('Review command'),
          ),
        ],
      ),
    );
    editor.dispose();
    if (reviewed == null || reviewed.trim().isEmpty || !mounted) return;
    await _confirmCommand(reviewed);
  }

  Future<void> _confirmCommand(String raw) async {
    final parsed = VoiceFeatureCommand.parse(raw);
    if (parsed.kind == VoiceFeatureCommandKind.unsupported) {
      setState(
        () => _error = 'I don’t recognize that as a supported command. Try “open settings,” “open study,” or “remind me to revise chemistry.” Nothing was changed.',
      );
      return;
    }
    final isReminder = parsed.kind == VoiceFeatureCommandKind.reminder;
    final approved =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(
              isReminder ? 'Review reminder request' : 'Review app navigation',
            ),
            content: Text(
              isReminder
                  ? 'Recognized: “Remind me to ${parsed.title}.” Next you’ll choose a date and time, then see the app’s normal reminder approval. Nothing will be scheduled until that final approval.'
                  : 'Recognized: “Open ${parsed.title}.” This will open the ${parsed.title} section after you confirm.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(
                  isReminder ? 'Choose reminder time' : 'Open section',
                ),
              ),
            ],
          ),
        ) ??
        false;
    if (!approved || !mounted) return;
    if (isReminder) {
      await widget.onReminder(context, parsed.title);
    } else if (parsed.route != null) {
      Navigator.of(context).pushNamed(parsed.route!);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(18),
    children: [
      const _FeatureNotice(
        icon: Icons.verified_user_outlined,
        text: 'Say “open settings,” “open study,” or “remind me to revise chemistry.” Speech is reviewed before anything happens. Reminders still need a chosen time and the usual approval; unsupported commands do nothing.',
      ),
      const SizedBox(height: 14),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Speech mode: ${widget.state.speechMode}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                widget.state.speechMode == 'offline'
                    ? 'Uses Android’s verified on-device recognizer when the selected language is installed. No online fallback.'
                    : widget.state.speechMode == 'online'
                    ? 'Uses Android system recognition only after the microphone disclosure.'
                    : 'Deepgram mode is not used by this command screen.',
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pushNamed(context, '/settings'),
                  child: const Text('Speech settings'),
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: _listening ? _stop : _listen,
        icon: Icon(_listening ? Icons.stop_rounded : Icons.mic_rounded),
        label: Text(_listening ? 'Stop listening' : 'Speak a command'),
      ),
      if (_listening)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: LinearProgressIndicator(),
        ),
      if (_partial.isNotEmpty)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Text(_partial),
          ),
        ),
      const SizedBox(height: 18),
      TextField(
        controller: _command,
        maxLength: 500,
        decoration: const InputDecoration(
          labelText: 'Or type a command',
          hintText: 'open study / remind me to review physics',
          border: OutlineInputBorder(),
        ),
      ),
      FilledButton.tonalIcon(
        onPressed: () => _confirmCommand(_command.text),
        icon: const Icon(Icons.fact_check_outlined),
        label: const Text('Review command'),
      ),
      if (_error.isNotEmpty) _ErrorPanel(_error),
    ],
  );
}

class _ResearchFeature extends StatefulWidget {
  final AssistantState state;
  const _ResearchFeature({required this.state});
  @override
  State<_ResearchFeature> createState() => _ResearchFeatureState();
}

class _ResearchFeatureState extends State<_ResearchFeature> {
  final _query = TextEditingController();
  bool _busy = false;
  String _error = '';
  FeatureAnswer? _answer;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _research() async {
    final query = _query.text.trim();
    if (query.isEmpty) {
      setState(() => _error = 'Enter a question to research.');
      return;
    }
    if (widget.state.engine != 'gemini') {
      setState(
        () => _error = 'Choose Gemini in Settings to use web research. Offline Qwen does not search the web, and no provider switch was made.',
      );
      return;
    }
    final client = GeminiFeatureClient(
      model: widget.state.geminiModelSelection,
      apiKey: widget.state.geminiApiKey,
      clientFactory: widget.state.clientFactory,
    );
    if (client.apiKey.trim().isEmpty) {
      setState(
        () => _error =
            'Add a Gemini API key in Settings first. No query was sent.',
      );
      return;
    }
    final proceed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Search the web with Gemini?'),
            content: Text(
              'Your question will be sent online to Google Gemini (${client.model}) with Google Search grounding enabled. The response will include source links only when the API returns citation metadata; model-written URLs are not treated as sources.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Search with Gemini'),
              ),
            ],
          ),
        ) ??
        false;
    if (!proceed || !mounted) return;
    setState(() {
      _busy = true;
      _error = '';
      _answer = null;
    });
    try {
      final result = await client.research(query);
      if (mounted) setState(() => _answer = result);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(18),
    children: [
      const _FeatureNotice(
        icon: Icons.link_rounded,
        text: 'Ask a question for a broad, web-grounded summary. Gemini can run several related searches, but no web search is exhaustive. Source links and search queries appear only when Google returns them; if citations are missing, the app says so rather than inventing links.',
      ),
      const SizedBox(height: 14),
      TextField(
        controller: _query,
        minLines: 2,
        maxLines: 5,
        maxLength: 4000,
        onSubmitted: (_) => _busy ? null : _research(),
        decoration: const InputDecoration(
          labelText: 'What should I research?',
          hintText: 'Compare current options, explain a topic, or check a recent claim',
          border: OutlineInputBorder(),
        ),
      ),
      FilledButton.icon(
        onPressed: _busy ? null : _research,
        icon: const Icon(Icons.travel_explore_rounded),
        label: Text(_busy ? 'Researching…' : 'Search and summarize'),
      ),
      if (_busy)
        const Padding(
          padding: EdgeInsets.all(16),
          child: LinearProgressIndicator(),
        ),
      if (_error.isNotEmpty) _ErrorPanel(_error),
      if (_answer != null) ...[
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: MarkdownBody(data: _answer!.text),
          ),
        ),
        if (_answer!.searchQueries.isNotEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Google Search queries used'),
                  for (final query in _answer!.searchQueries)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('· $query'),
                    ),
                ],
              ),
            ),
          ),
        if (_answer!.sources.isNotEmpty)
          _SourceList(sources: _answer!.sources)
        else
          const _FeatureNotice(
            icon: Icons.info_outline_rounded,
            text: 'Gemini returned no source citations for this answer. Treat it as an uncited model response, not verified web research.',
          ),
      ],
    ],
  );
}

class _SourceList extends StatelessWidget {
  final List<FeatureSource> sources;
  const _SourceList({required this.sources});

  @override
  Widget build(BuildContext context) => Card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 14, 16, 4),
          child: Text('Sources from Gemini grounding'),
        ),
        for (final source in sources)
          ListTile(
            leading: const Icon(Icons.open_in_new_rounded),
            title: Text(
              source.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              source.supportingText.isEmpty
                  ? source.uri.host
                  : '${source.supportingText}\n${source.uri.host}',
              maxLines: source.supportingText.isEmpty ? 1 : 3,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => _SourcePage(source: source),
              ),
            ),
          ),
      ],
    ),
  );
}

class _SourcePage extends StatefulWidget {
  final FeatureSource source;
  const _SourcePage({required this.source});
  @override
  State<_SourcePage> createState() => _SourcePageState();
}

class _SourcePageState extends State<_SourcePage> {
  late final WebViewController _controller = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.disabled)
    ..loadRequest(widget.source.uri);

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.source.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    ),
    body: WebViewWidget(controller: _controller),
  );
}

class _FeatureNotice extends StatelessWidget {
  final IconData icon;
  final String text;
  const _FeatureNotice({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.secondaryContainer
        .withValues(alpha: .55),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    ),
  );
}

class _ErrorPanel extends StatelessWidget {
  final String text;
  const _ErrorPanel(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(padding: const EdgeInsets.all(12), child: Text(text)),
    ),
  );
}
