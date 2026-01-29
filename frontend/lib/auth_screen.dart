import 'package:flutter/material.dart';

import 'auth_service.dart';

class AuthScreen extends StatefulWidget {
  final String baseUrl;
  final Future<void> Function(Map<String, dynamic> me) onLoggedIn;

  const AuthScreen({
    super.key,
    required this.baseUrl,
    required this.onLoggedIn,
  });

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _auth = AuthService();

  int _tabIndex = 0;
  bool _isLoading = false;

  bool _loginPasswordVisible = false;
  bool _registerPasswordVisible = false;

  final _loginFormKey = GlobalKey<FormState>();
  final _loginEmail = TextEditingController();
  final _loginPassword = TextEditingController();

  final _registerFormKey = GlobalKey<FormState>();
  final _registerFirstName = TextEditingController();
  final _registerLastName = TextEditingController();
  final _registerEmail = TextEditingController();
  final _registerPassword = TextEditingController();

  @override
  void dispose() {
    _loginEmail.dispose();
    _loginPassword.dispose();
    _registerFirstName.dispose();
    _registerLastName.dispose();
    _registerEmail.dispose();
    _registerPassword.dispose();
    super.dispose();
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  Future<void> _submitLogin() async {
    if (!_loginFormKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final loginRes = await _auth.login(
        baseUrl: widget.baseUrl,
        email: _loginEmail.text.trim(),
        password: _loginPassword.text,
      );

      final token = loginRes['token'];
      if (token is! String || token.isEmpty) {
        throw Exception('Missing token from server');
      }

      final me = await _auth.me(baseUrl: widget.baseUrl, token: token);
      await widget.onLoggedIn(me);
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _submitRegister() async {
    if (!_registerFormKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      await _auth.register(
        baseUrl: widget.baseUrl,
        firstName: _registerFirstName.text.trim(),
        lastName: _registerLastName.text.trim(),
        email: _registerEmail.text.trim(),
        password: _registerPassword.text,
      );

      final loginRes = await _auth.login(
        baseUrl: widget.baseUrl,
        email: _registerEmail.text.trim(),
        password: _registerPassword.text,
      );

      final token = loginRes['token'];
      if (token is! String || token.isEmpty) {
        throw Exception('Missing token from server');
      }

      final me = await _auth.me(baseUrl: widget.baseUrl, token: token);
      await widget.onLoggedIn(me);
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String? _validateEmail(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Email is required';
    if (!v.contains('@')) return 'Enter a valid email';
    return null;
  }

  String? _validatePassword(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Password is required';
    if (v.length < 6) return 'Password must be at least 6 characters';
    return null;
  }

  InputDecoration _fieldDecoration({
    required String label,
    required IconData icon,
    String? hint,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon),
      suffixIcon: suffixIcon,
      border: const OutlineInputBorder(),
      filled: true,
      fillColor: Theme.of(context).colorScheme.surface,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isCompact = MediaQuery.of(context).size.width < 420;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                colorScheme.primaryContainer.withOpacity(0.55),
                colorScheme.surface,
              ],
            ),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: isCompact ? 16 : 24,
                  vertical: 24,
                ),
                child: Card(
                  elevation: 2,
                  shadowColor: colorScheme.shadow.withOpacity(0.2),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: isCompact ? 16 : 24,
                      vertical: isCompact ? 20 : 24,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Header(
                          title: 'Calling System',
                          subtitle: _tabIndex == 0
                              ? 'Sign in to continue'
                              : 'Create your account',
                        ),
                        const SizedBox(height: 20),
                        SegmentedButton<int>(
                          segments: const [
                            ButtonSegment<int>(
                              value: 0,
                              label: Text('Login'),
                              icon: Icon(Icons.login),
                            ),
                            ButtonSegment<int>(
                              value: 1,
                              label: Text('Register'),
                              icon: Icon(Icons.person_add_alt_1),
                            ),
                          ],
                          selected: {_tabIndex},
                          onSelectionChanged: _isLoading
                              ? null
                              : (selection) {
                                  setState(() {
                                    _tabIndex = selection.first;
                                  });
                                },
                          style: ButtonStyle(
                            visualDensity: VisualDensity.comfortable,
                            shape: WidgetStatePropertyAll(
                              RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        _tabIndex == 0 ? _buildLogin() : _buildRegister(),
                        const SizedBox(height: 16),
                        Text(
                          'By continuing you agree to keep your credentials secure.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
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

  Widget _buildLogin() {
    final colorScheme = Theme.of(context).colorScheme;
    return Form(
      key: _loginFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _loginEmail,
            decoration: _fieldDecoration(
              label: 'Email',
              hint: 'name@example.com',
              icon: Icons.email_outlined,
            ),
            keyboardType: TextInputType.emailAddress,
            validator: _validateEmail,
            enabled: !_isLoading,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _loginPassword,
            decoration: _fieldDecoration(
              label: 'Password',
              icon: Icons.lock_outline,
              suffixIcon: IconButton(
                onPressed: _isLoading
                    ? null
                    : () {
                        setState(() {
                          _loginPasswordVisible = !_loginPasswordVisible;
                        });
                      },
                icon: Icon(
                  _loginPasswordVisible
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
                tooltip: _loginPasswordVisible ? 'Hide password' : 'Show password',
              ),
            ),
            obscureText: !_loginPasswordVisible,
            validator: _validatePassword,
            enabled: !_isLoading,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _submitLogin(),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 50,
            child: FilledButton(
              onPressed: _isLoading ? null : _submitLogin,
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isLoading
                  ? SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colorScheme.onPrimary,
                      ),
                    )
                  : const Text('Sign in'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRegister() {
    final colorScheme = Theme.of(context).colorScheme;
    return Form(
      key: _registerFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _registerFirstName,
            decoration: _fieldDecoration(
              label: 'First name',
              icon: Icons.badge_outlined,
            ),
            enabled: !_isLoading,
            validator: (v) {
              if ((v ?? '').trim().isEmpty) return 'First name is required';
              return null;
            },
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _registerLastName,
            decoration: _fieldDecoration(
              label: 'Last name',
              icon: Icons.badge_outlined,
            ),
            enabled: !_isLoading,
            validator: (v) {
              if ((v ?? '').trim().isEmpty) return 'Last name is required';
              return null;
            },
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _registerEmail,
            decoration: _fieldDecoration(
              label: 'Email',
              hint: 'name@example.com',
              icon: Icons.email_outlined,
            ),
            keyboardType: TextInputType.emailAddress,
            validator: _validateEmail,
            enabled: !_isLoading,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _registerPassword,
            decoration: _fieldDecoration(
              label: 'Password',
              icon: Icons.lock_outline,
              suffixIcon: IconButton(
                onPressed: _isLoading
                    ? null
                    : () {
                        setState(() {
                          _registerPasswordVisible = !_registerPasswordVisible;
                        });
                      },
                icon: Icon(
                  _registerPasswordVisible
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
                tooltip:
                    _registerPasswordVisible ? 'Hide password' : 'Show password',
              ),
            ),
            obscureText: !_registerPasswordVisible,
            validator: _validatePassword,
            enabled: !_isLoading,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _submitRegister(),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 50,
            child: FilledButton(
              onPressed: _isLoading ? null : _submitRegister,
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isLoading
                  ? SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colorScheme.onPrimary,
                      ),
                    )
                  : const Text('Create account'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String title;
  final String subtitle;

  const _Header({
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Container(
          height: 54,
          width: 54,
          decoration: BoxDecoration(
            color: colorScheme.primary,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(
            Icons.phone_in_talk,
            color: colorScheme.onPrimary,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
