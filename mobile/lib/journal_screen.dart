import 'package:flutter/material.dart';

import 'assistant_state.dart';

/// A private, on-device journal. Entry text is never submitted to an AI service.
class JournalScreen extends StatefulWidget {
  final AssistantState state;
  const JournalScreen({super.key, required this.state});

  @override
  State<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends State<JournalScreen> {
  List<Map<String, dynamic>> get _entries {
    final entries = widget.state.local.rows('journal_entries');
    entries.sort((a, b) {
      final byDate = (b['date'] as String).compareTo(a['date'] as String);
      if (byDate != 0) return byDate;
      return (b['updated_at'] as String? ?? '').compareTo(
        a['updated_at'] as String? ?? '',
      );
    });
    return entries;
  }

  Future<void> _editEntry([Map<String, dynamic>? entry]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _JournalEntryEditor(state: widget.state, entry: entry),
    );
    if (saved == true && mounted) setState(() {});
  }

  Future<void> _deleteEntry(Map<String, dynamic> entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this entry?'),
        content: const Text('This removes it from this device.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep entry'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.state.local.deleteJournalEntry(entry['id'] as String);
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not delete this entry.')),
        );
      }
    }
  }

  String _displayDate(String value) {
    final parts = value.split('-');
    return '${parts[2]}/${parts[1]}/${parts[0]}';
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    final today = DateTime.now();
    final todayKey =
        '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    final todaysEntries = entries.where((e) => e['date'] == todayKey).length;
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.edit_note_rounded,
                        color: Theme.of(context).colorScheme.primary,
                        size: 28,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Your journal',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      Text(
                        '${entries.length} ${entries.length == 1 ? 'entry' : 'entries'}',
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    todaysEntries == 0
                        ? 'A quiet place for notes and reflections.'
                        : '$todaysEntries ${todaysEntries == 1 ? 'entry' : 'entries'} for today.',
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Saved on this device only · never sent to AI or synced.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => _editEntry(),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Write an entry'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (entries.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(
                      Icons.menu_book_outlined,
                      size: 36,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 8),
                    const Text('Your entries will appear here.'),
                    const SizedBox(height: 4),
                    const Text('Nothing has been added for you.'),
                  ],
                ),
              ),
            )
          else
            for (final entry in entries)
              Card(
                key: ValueKey('journal-${entry['id']}'),
                child: ListTile(
                  contentPadding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                  title: Text(_displayDate(entry['date'] as String)),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      entry['text'] as String,
                      maxLines: 5,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  onTap: () => _editEntry(entry),
                  trailing: PopupMenuButton<String>(
                    tooltip: 'Entry actions',
                    onSelected: (action) {
                      if (action == 'edit') _editEntry(entry);
                      if (action == 'delete') _deleteEntry(entry);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _JournalEntryEditor extends StatefulWidget {
  final AssistantState state;
  final Map<String, dynamic>? entry;
  const _JournalEntryEditor({required this.state, this.entry});

  @override
  State<_JournalEntryEditor> createState() => _JournalEntryEditorState();
}

class _JournalEntryEditorState extends State<_JournalEntryEditor> {
  late final TextEditingController _text;
  late DateTime _date;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final entry = widget.entry;
    _date = entry == null
        ? DateTime.now()
        : DateTime.parse(entry['date'] as String);
    _text = TextEditingController(text: entry?['text'] as String? ?? '');
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  String get _dateKey =>
      '${_date.year.toString().padLeft(4, '0')}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}';

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'Choose entry date',
    );
    if (selected != null && mounted) setState(() => _date = selected);
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.state.local.saveJournalEntry(
        id: widget.entry?['id'] as String?,
        date: _dateKey,
        text: _text.text,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error is ArgumentError
              ? error.message.toString()
              : 'Could not save this entry on the device.';
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.entry == null ? 'Write an entry' : 'Edit entry'),
    scrollable: true,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OutlinedButton.icon(
          onPressed: _saving ? null : _pickDate,
          icon: const Icon(Icons.calendar_today_outlined),
          label: Text('Date: ${_date.day}/${_date.month}/${_date.year}'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _text,
          autofocus: true,
          minLines: 5,
          maxLines: 10,
          maxLength: 10000,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Entry',
            hintText: 'Write what you want to remember…',
            alignLabelWithHint: true,
            border: OutlineInputBorder(),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context, false),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: Text(_saving ? 'Saving…' : 'Save entry'),
      ),
    ],
  );
}
