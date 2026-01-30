import 'package:flutter/material.dart';

import 'auth_service.dart';

class SetCallIdScreen extends StatefulWidget {
  final String baseUrl;
  final VoidCallback? onSkip;

  const SetCallIdScreen({
    super.key,
    required this.baseUrl,
    this.onSkip,
  });

  @override
  State<SetCallIdScreen> createState() => _SetCallIdScreenState();
}

class _SetCallIdScreenState extends State<SetCallIdScreen> {
  final _formKey = GlobalKey<FormState>();
  final _callIdController = TextEditingController();
  final _auth = AuthService();

  bool _isLoading = false;

  @override
  void dispose() {
    _callIdController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final callId = _callIdController.text.trim();
      await _auth.setCallUserId(baseUrl: widget.baseUrl, callUserId: callId);
      if (mounted) {
        Navigator.of(context).pop(callId);
      }
    } catch (e) {
      final msg = e.toString();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              msg.contains('already taken')
                  ? 'This Call ID is already taken. Please choose another one.'
                  : msg,
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String? _validateCallId(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Call ID is required';
    if (v.length < 3) return 'Call ID must be at least 3 characters';
    if (v.length > 30) return 'Call ID must be 30 characters or less';
    if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(v)) {
      return 'Use only letters, numbers, and underscores';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('Choose Call ID'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          if (widget.onSkip != null)
            TextButton(
              onPressed: _isLoading
                  ? null
                  : () {
                      widget.onSkip?.call();
                    },
              child: const Text('Skip'),
            ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Set your public Call ID',
                          style: Theme.of(context).textTheme.titleLarge,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'People will use this ID to call you.',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _callIdController,
                          enabled: !_isLoading,
                          decoration: const InputDecoration(
                            labelText: 'Call ID',
                            hintText: 'e.g. hiba_01',
                            prefixIcon: Icon(Icons.alternate_email),
                            border: OutlineInputBorder(),
                          ),
                          validator: _validateCallId,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _submit(),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 50,
                          child: FilledButton(
                            onPressed: _isLoading ? null : _submit,
                            child: _isLoading
                                ? SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: colorScheme.onPrimary,
                                    ),
                                  )
                                : const Text('Save Call ID'),
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
    );
  }
}
