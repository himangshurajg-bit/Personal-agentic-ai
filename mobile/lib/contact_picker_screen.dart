import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const _device = MethodChannel('personal_assistant/device');

/// A one-contact, user-initiated Android picker. The selected details remain
/// only in this widget's memory and are never persisted or sent to a service.
class ContactPickerScreen extends StatefulWidget {
  const ContactPickerScreen({super.key});

  @override
  State<ContactPickerScreen> createState() => _ContactPickerScreenState();
}

class _ContactPickerScreenState extends State<ContactPickerScreen> {
  bool _busy = false;
  String? _name;
  String? _phone;
  String _status = 'Choose one contact only when you need it.';

  Future<void> _pickContact() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = 'Opening Android contacts…';
    });
    try {
      final picked = await _device.invokeMapMethod<String, Object?>(
        'pick_one_contact',
      );
      if (!mounted) return;
      if (picked == null) {
        setState(() => _status = 'Selection canceled. No contact was kept.');
        return;
      }
      final name = picked['display_name'];
      final phone = picked['phone_number'];
      if (name is! String || phone is! String || !_valid(name, phone)) {
        setState(() => _status = 'No usable contact was returned.');
        return;
      }
      setState(() {
        _name = name;
        _phone = phone;
        _status = 'Selected for this screen only; not saved or shared.';
      });
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Review selected contact'),
          content: Text(
            'Name: $name\nPhone: $phone\n\nThese details stay on this screen only. They are not saved or sent anywhere.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } on PlatformException {
      if (mounted) {
        setState(() => _status = 'Android could not open the contact picker.');
      }
    } on MissingPluginException {
      if (mounted) {
        setState(() => _status = 'The contact picker is available on Android.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _status = 'No contact details were returned.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _valid(String name, String phone) {
    if (name.trim().isEmpty ||
        name.length > 120 ||
        phone.trim().isEmpty ||
        phone.length > 48) {
      return false;
    }
    if (name.contains(RegExp(r'[\x00-\x1F\x7F]')) ||
        phone.contains(RegExp(r'[\x00-\x1F\x7F]'))) {
      return false;
    }
    final digits = RegExp(r'\d').allMatches(phone).length;
    return digits >= 3 &&
        digits <= 20 &&
        !RegExp(
          r'[^\d+\-(). /#*extEXT,;]',
          caseSensitive: false,
        ).hasMatch(phone);
  }

  void _clear() => setState(() {
    _name = null;
    _phone = null;
    _status = 'Selected contact cleared from this screen.';
  });

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.contact_phone_outlined, size: 32),
              const SizedBox(height: 12),
              Text(
                'Choose one contact',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'Android opens its system picker. Personal AI reads only the contact you select; it does not scan your address book, request broad Contacts access, save the details, or send them online.',
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const Key('pick-one-contact'),
                onPressed: _busy ? null : _pickContact,
                icon: _busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.person_search_outlined),
                label: Text(
                  _busy ? 'Waiting for selection…' : 'Choose a contact',
                ),
              ),
              if (_name != null && _phone != null) ...[
                const SizedBox(height: 16),
                const Divider(),
                Text(_name!, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                SelectableText(_phone!),
                const SizedBox(height: 8),
                TextButton.icon(
                  key: const Key('clear-selected-contact'),
                  onPressed: _clear,
                  icon: const Icon(Icons.close),
                  label: const Text('Clear from screen'),
                ),
              ],
              const SizedBox(height: 8),
              Text(_status, key: const Key('contact-status')),
            ],
          ),
        ),
      ),
    ],
  );
}
