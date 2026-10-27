import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'assistant_state.dart';
import 'feature_services.dart';
import 'text_tools_screen.dart';
import 'local_web_projects_screen.dart';
import 'system_monitor_screen.dart';
import 'focus_timer_screen.dart';
import 'system_clock_timer_screen.dart';
import 'journal_screen.dart';
import 'office_document.dart';

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
    length: 9,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Assistant tools'),
        bottom: const TabBar(
          isScrollable: true,
          tabs: [
            Tab(icon: Icon(Icons.description_outlined), text: 'Files'),
            Tab(icon: Icon(Icons.mic_none_rounded), text: 'Voice actions'),
            Tab(icon: Icon(Icons.travel_explore_rounded), text: 'Research'),
            Tab(icon: Icon(Icons.transform_rounded), text: 'Text tools'),
            Tab(icon: Icon(Icons.code_rounded), text: 'Web projects'),
            Tab(
              icon: Icon(Icons.monitor_heart_outlined),
              text: 'System monitor',
            ),
            Tab(icon: Icon(Icons.timer_outlined), text: 'Focus timer'),
            Tab(icon: Icon(Icons.edit_note_rounded), text: 'Journal'),
            Tab(icon: Icon(Icons.alarm_add_rounded), text: 'Clock timer'),
          ],
        ),
      ),
      body: TabBarView(
        children: [
          _DocumentFeature(state: state),
          _VoiceActionsFeature(state: state, onReminder: onReminder),
          _ResearchFeature(state: state),
          const TextToolsScreen(),
          LocalWebProjectsScreen(state: state),
          const SystemMonitorScreen(),
          FocusTimerScreen(state: state),
          JournalScreen(state: state),
          const SystemClockTimerScreen(),
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
  String _extractedText = '';
  bool _extractedTextTruncated = false;
  String _task = 'Summarize';
  FeatureAnswer? _answer;
  String? _ocrText;
  String _ocrSummary = '';
  bool _ocrBusy = false;
  bool _busy = false;
  String _error = '';

  @override
  void dispose() {
    _question.dispose();
    _bytes?.fillRange(0, _bytes!.length, 0);
    super.dispose();
  }

  Future<void> _openLocalMedia(String kind) async {
    setState(() => _error = '');
    try {
      await AssistantState.device.invokeMethod<void>('open_local_media', {
        'kind': kind,
      });
    } on PlatformException catch (error) {
      if (error.code != 'cancelled' && mounted) {
        setState(
          () => _error = error.message ?? 'Could not open a local viewer.',
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _capturePhoto() async {
    setState(() => _error = '');
    try {
      final result = await AssistantState.device
          .invokeMapMethod<String, dynamic>('capture_photo');
      if (result == null) return;
      final mime = result['mime'];
      final encoded = result['content_base64'];
      final name = result['name'];
      if (mime is! String || encoded is! String || name is! String) {
        throw const FeatureServiceException(
          'The camera did not return a usable photo.',
        );
      }
      final bytes = base64Decode(encoded);
      if (mime != 'image/jpeg' ||
          bytes.isEmpty ||
          bytes.length > 2 * 1024 * 1024) {
        bytes.fillRange(0, bytes.length, 0);
        throw const FeatureServiceException(
          'The camera photo is invalid or exceeds 2 MB.',
        );
      }
      _bytes?.fillRange(0, _bytes!.length, 0);
      setState(() {
        _bytes = bytes;
        _mime = mime;
        _name = name;
        _extractedText = '';
        _extractedTextTruncated = false;
        _answer = null;
        _ocrText = null;
        _ocrSummary = '';
        _error = '';
        _task = 'Summarize';
        _question.clear();
      });
    } on PlatformException catch (error) {
      if (error.code != 'cancelled' && mounted) {
        setState(() => _error = error.message ?? 'Could not capture a photo.');
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _pickFile() async {
    setState(() {
      _error = '';
    });
    try {
      final result = await AssistantState.device
          .invokeMapMethod<String, dynamic>('pick_file', {
            'ai_document': true,
            'office_docx': true,
          });
      if (result == null) return;
      final mime = result['mime'];
      final encoded = result['content_base64'];
      final name = result['name'];
      if (mime is! String || encoded is! String || name is! String) {
        throw FeatureServiceException(
          (result['unsupported'] as String?) ??
              'Choose a PDF, DOCX or image on Android.',
        );
      }
      final bytes = base64Decode(encoded);
      final isDocx = mime == docxMime && name.toLowerCase().endsWith('.docx');
      if ((!supportedAiDocumentMimes.contains(mime) && !isDocx) ||
          bytes.isEmpty ||
          bytes.length > maxAiDocumentBytes) {
        bytes.fillRange(0, bytes.length, 0);
        throw const FeatureServiceException(
          'That file is not supported or exceeds 12 MB.',
        );
      }
      ExtractedOfficeText? extracted;
      if (isDocx) {
        try {
          extracted = extractDocxText(bytes);
        } catch (_) {
          bytes.fillRange(0, bytes.length, 0);
          rethrow;
        }
      }
      _bytes?.fillRange(0, _bytes!.length, 0);
      setState(() {
        _bytes = bytes;
        _mime = mime;
        _name = name;
        _extractedText = extracted?.text ?? '';
        _extractedTextTruncated = extracted?.truncated ?? false;
        _answer = null;
        _ocrText = null;
        _ocrSummary = '';
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

  Future<void> _extractImageTextLocally() async {
    final bytes = _bytes;
    if (bytes == null || !(_mime.startsWith('image/'))) {
      setState(() => _error = 'Choose a JPEG, PNG or WebP image first.');
      return;
    }
    setState(() {
      _ocrBusy = true;
      _ocrText = null;
      _error = '';
    });
    try {
      final text = await AssistantState.device.invokeMethod<String>(
        'extract_image_text_locally',
        {'image_bytes': bytes, 'mime': _mime},
      );
      if (mounted) setState(() => _ocrText = text ?? '');
    } on PlatformException catch (error) {
      if (mounted) {
        setState(
          () => _error = error.message ?? 'Local text extraction failed.',
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _ocrBusy = false);
    }
  }

  Future<void> _extractPdfTextLocally() async {
    final bytes = _bytes;
    if (bytes == null || _mime != 'application/pdf') {
      setState(() => _error = 'Choose a PDF first.');
      return;
    }
    setState(() {
      _ocrBusy = true;
      _ocrText = null;
      _ocrSummary = '';
      _error = '';
    });
    try {
      final result = await AssistantState.device
          .invokeMapMethod<String, dynamic>('extract_pdf_text_locally', {
            'pdf_bytes': bytes,
            'mime': _mime,
          });
      if (result == null) {
        throw const FeatureServiceException(
          'Local PDF text extraction returned no result.',
        );
      }
      final text = result['text'];
      final processed = result['pages_processed'];
      final total = result['page_count'];
      final truncated = result['truncated'];
      if (text is! String ||
          processed is! int ||
          total is! int ||
          truncated is! bool) {
        throw const FeatureServiceException(
          'Local PDF text extraction returned an invalid result.',
        );
      }
      if (mounted) {
        setState(() {
          _ocrText = text;
          _ocrSummary =
              'Read $processed of $total pages locally${truncated ? ' · partial result' : ''}.';
        });
      }
    } on PlatformException catch (error) {
      if (mounted) {
        setState(
          () => _error = error.message ?? 'Local PDF text extraction failed.',
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _ocrBusy = false);
    }
  }

  Future<void> _ask() async {
    final bytes = _bytes;
    if (bytes == null) {
      setState(() => _error = 'Choose a PDF, DOCX or image first.');
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
            title: Text(
              _mime == docxMime
                  ? 'Send extracted text to Gemini?'
                  : 'Send this file to Gemini?',
            ),
            content: Text(
              _mime == docxMime
                  ? 'Text extracted locally from “$_name” and your question will be sent online to Google Gemini (${client.model}) for analysis. The DOCX itself is not sent. Google handles the text under its service terms. The text and answer are not added to chat history and are held temporarily on this screen.'
                  : '“$_name” and your question will be sent online to Google Gemini (${client.model}) for analysis. Google handles the content under its service terms. This feature does not add the file or answer to chat history; the selected file is held temporarily on this screen.',
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
      final answer = _mime == docxMime
          ? await client.askExtractedText(text: _extractedText, prompt: prompt)
          : await client.askDocument(
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
        text: 'Choose a PDF, DOCX or photo, or take a photo with Android’s camera app. PDF and image text can also be extracted on-device (Latin script), without sending the file online. Gemini analysis still needs your review, and Qwen offline chat is text-only.',
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _openLocalMedia('pdf'),
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('Open PDF locally'),
          ),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _openLocalMedia('video'),
            icon: const Icon(Icons.video_library_outlined),
            label: const Text('Open video locally'),
          ),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _openLocalMedia('audio'),
            icon: const Icon(Icons.queue_music_rounded),
            label: const Text('Local audio queue'),
          ),
        ],
      ),
      const Padding(
        padding: EdgeInsets.only(top: 6),
        child: Text(
          'PDFs and videos open in local viewers with page and playback controls. Audio files can be queued temporarily (up to 25) and play only when you tap Play. Selected media stays on this device; nothing is sent to Gemini.',
        ),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: _busy ? null : _capturePhoto,
            icon: const Icon(Icons.photo_camera_outlined),
            label: const Text('Take a photo'),
          ),
          OutlinedButton.icon(
            onPressed: _busy ? null : _pickFile,
            icon: const Icon(Icons.attach_file_rounded),
            label: Text(
              _bytes == null
                  ? 'Choose PDF, DOCX or photo'
                  : 'Choose a different file',
            ),
          ),
        ],
      ),
      const Padding(
        padding: EdgeInsets.only(top: 6),
        child: Text(
          'Personal AI keeps a captured photo only temporarily on this screen. Remove it when finished; online analysis still requires your review.',
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
                      _extractedText = '';
                      _extractedTextTruncated = false;
                      _answer = null;
                      _ocrText = null;
                      _ocrSummary = '';
                      _question.clear();
                    }),
              icon: const Icon(Icons.close_rounded),
            ),
          ),
        ),
      ],
      if (_bytes != null && _mime == docxMime) ...[
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Text extracted locally'),
                const SizedBox(height: 6),
                Text(
                  _extractedTextTruncated
                      ? 'Preview limited to $maxExtractedDocxChars characters. Gemini will receive only this extracted text.'
                      : 'Gemini will receive only the extracted text after you approve.',
                ),
                const SizedBox(height: 8),
                SelectableText(_extractedText),
              ],
            ),
          ),
        ),
      ],
      if (_bytes != null && _mime.startsWith('image/')) ...[
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _busy || _ocrBusy ? null : _extractImageTextLocally,
          icon: _ocrBusy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.document_scanner_outlined),
          label: Text(
            _ocrBusy ? 'Extracting locally…' : 'Extract text on device',
          ),
        ),
        const Text(
          'Uses a bundled Latin-script OCR model. Extracted text stays on this screen and is not added to chat.',
        ),
        if (_ocrText != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: _ocrText!.isEmpty
                  ? const Text('No text was recognized.')
                  : SelectableText(_ocrText!),
            ),
          ),
      ],
      if (_bytes != null && _mime == 'application/pdf') ...[
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _busy || _ocrBusy ? null : _extractPdfTextLocally,
          icon: _ocrBusy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.document_scanner_outlined),
          label: Text(
            _ocrBusy ? 'Extracting locally…' : 'Extract PDF text on device',
          ),
        ),
        const Text(
          'Only the first 8 pages are checked with the bundled Latin-script OCR model. Text stays on this screen; the PDF is not uploaded by this action.',
        ),
        if (_ocrSummary.isNotEmpty) Text(_ocrSummary),
        if (_ocrText != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: _ocrText!.isEmpty
                  ? const Text('No text was recognized.')
                  : SelectableText(_ocrText!),
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
