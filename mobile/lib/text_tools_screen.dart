import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'text_tools.dart';

class TextToolsScreen extends StatefulWidget {
  const TextToolsScreen({super.key});

  @override
  State<TextToolsScreen> createState() => _TextToolsScreenState();
}

class _TextToolsScreenState extends State<TextToolsScreen> {
  final _input = TextEditingController();
  TextToolOperation _operation = TextToolOperation.base64Encode;
  String? _output;
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _run() {
    try {
      final output = TextTools.transform(_input.text, _operation);
      setState(() {
        _output = output;
        _error = null;
      });
    } on FormatException catch (error) {
      setState(() {
        _output = null;
        _error = error.message;
      });
    } catch (_) {
      setState(() {
        _output = null;
        _error = 'Could not transform that text.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(18),
    children: [
      const Card(
        child: Padding(
          padding: EdgeInsets.all(14),
          child: Text(
            'These bounded transformations run on this device. Text is not saved or sent online; clear the fields or leave this screen when finished.',
          ),
        ),
      ),
      const SizedBox(height: 14),
      DropdownButtonFormField<TextToolOperation>(
        initialValue: _operation,
        decoration: const InputDecoration(
          labelText: 'Transformation',
          border: OutlineInputBorder(),
        ),
        items: [
          for (final operation in TextToolOperation.values)
            DropdownMenuItem(value: operation, child: Text(operation.label)),
        ],
        onChanged: (value) {
          if (value != null) {
            setState(() {
              _operation = value;
              _output = null;
              _error = null;
            });
          }
        },
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _input,
        onChanged: (_) => setState(() {
          _output = null;
          _error = null;
        }),
        minLines: 4,
        maxLines: 10,
        maxLength: maxTextToolsInputBytes,
        decoration: const InputDecoration(
          labelText: 'Input text',
          border: OutlineInputBorder(),
          alignLabelWithHint: true,
        ),
      ),
      Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: _run,
              icon: const Icon(Icons.transform_rounded),
              label: const Text('Transform locally'),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () {
              _input.clear();
              setState(() {
                _output = null;
                _error = null;
              });
            },
            child: const Text('Clear'),
          ),
        ],
      ),
      if (_error != null) ...[
        const SizedBox(height: 12),
        Semantics(liveRegion: true, child: Text(_error!)),
      ],
      if (_output != null) ...[
        const SizedBox(height: 16),
        Text('Output', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        SelectableText(_output!),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => Clipboard.setData(ClipboardData(text: _output!)),
            icon: const Icon(Icons.copy_rounded),
            label: const Text('Copy output'),
          ),
        ),
      ],
    ],
  );
}
