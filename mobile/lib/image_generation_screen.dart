import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'assistant_state.dart';

/// An isolated, explicit prompt-to-image flow. It never reads chat or memory.
class ImageGenerationScreen extends StatefulWidget {
  final String endpoint;
  final String token;
  final http.Client Function() clientFactory;

  const ImageGenerationScreen({
    super.key,
    required this.endpoint,
    required this.token,
    this.clientFactory = http.Client.new,
  });

  @override
  State<ImageGenerationScreen> createState() => _ImageGenerationScreenState();
}

class _ImageGenerationScreenState extends State<ImageGenerationScreen> {
  final _prompt = TextEditingController();
  Uint8List? _image;
  String? _imageType;
  String _error = '';
  bool _busy = false;

  @override
  void dispose() {
    _prompt.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final prompt = _prompt.text.trim();
    if (prompt.isEmpty || prompt.length > 1000 || _busy) return;
    setState(() {
      _busy = true;
      _error = '';
      _image = null;
      _imageType = null;
    });
    final client = widget.clientFactory();
    try {
      final uri = checkedEndpoint(widget.endpoint).resolve('/images/generate');
      final request = http.Request('POST', uri)
        ..followRedirects = false
        ..headers.addAll({
          'Authorization': 'Bearer ${widget.token}',
          'Content-Type': 'application/json',
          'Accept': 'image/png, image/jpeg, image/webp',
        })
        // Deliberately only the typed prompt; no chat, memory or file context.
        ..body = jsonEncode({'prompt': prompt});
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 105));
      if (response.statusCode != 200) {
        final message = switch (response.statusCode) {
          401 => 'The private service token was rejected. Check Settings.',
          429 =>
            'Image generation is rate-limited. Wait a minute before retrying.',
          503 => 'Image generation is not configured on the private service.',
          504 => 'Image generation timed out. Nothing was retried.',
          _ =>
            'Image generation failed (${response.statusCode}). Nothing was retried.',
        };
        throw ServiceException(message);
      }
      final type = (response.headers['content-type'] ?? '')
          .split(';')
          .first
          .trim()
          .toLowerCase();
      if (!const {'image/png', 'image/jpeg', 'image/webp'}.contains(type)) {
        throw ServiceException(
          'The service returned an unsupported image format.',
        );
      }
      final bytes = BytesBuilder(copy: false);
      var length = 0;
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 100),
      )) {
        length += chunk.length;
        if (length > 10_000_000) {
          throw ServiceException(
            'The generated image exceeded the 10 MB limit.',
          );
        }
        bytes.add(chunk);
      }
      if (length == 0) {
        throw ServiceException('The service returned an empty image.');
      }
      if (!mounted) return;
      setState(() {
        _image = bytes.takeBytes();
        _imageType = type;
      });
    } on TimeoutException {
      if (mounted) {
        setState(
          () => _error = 'Image generation timed out. Nothing was retried.',
        );
      }
    } on http.ClientException {
      if (mounted) {
        setState(
          () => _error =
              'Could not reach the private service. Nothing was retried.',
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      client.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Create an image')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Describe one image',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text(
          'Only the prompt you type here is sent to your private service and Cloudflare. Your chat and saved memories are not included.',
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _prompt,
          minLines: 3,
          maxLines: 7,
          maxLength: 1000,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Image prompt',
            hintText: 'A small glass greenhouse among ferns at dawn',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _busy ? null : _generate,
          icon: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.auto_awesome),
          label: Text(_busy ? 'Generating…' : 'Generate image'),
        ),
        if (_error.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            _error,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        if (_image != null) ...[
          const SizedBox(height: 24),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Image.memory(
              _image!,
              fit: BoxFit.contain,
              semanticLabel: 'Generated ${_imageType ?? 'image'} preview',
              errorBuilder: (_, _, _) => const Padding(
                padding: EdgeInsets.all(20),
                child: Text('The returned image could not be displayed.'),
              ),
            ),
          ),
        ],
      ],
    ),
  );
}
