import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../common_widgets/app_text_field.dart';
import '../../common_widgets/app_button.dart';
import 'oauth_buttons.dart';
import 'user_provider.dart';

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _acceptedTerms = false;

  String _formatSignupError(Object error) {
    final raw = error.toString().toLowerCase();
    debugPrint('Signup error details: $error');

    if (raw.contains('failed host lookup') || raw.contains('socketexception')) {
      return 'Could not reach the authentication server. Please update the app or try again on a stable network.';
    }
    if (raw.contains('email') &&
        (raw.contains('invalid') || raw.contains('format'))) {
      return 'Please enter a valid email address.';
    }
    if (raw.contains('already registered') || raw.contains('already exists')) {
      return 'An account with this email already exists.';
    }
    if (raw.contains('email confirmation') || raw.contains('verify email')) {
      return 'Please check your email to verify your account before logging in.';
    }
    if (raw.contains('password') &&
        (raw.contains('weak') || raw.contains('length'))) {
      return 'Password must be at least 6 characters.';
    }
    return error.toString();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleSignup() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_acceptedTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please accept the Terms of Service and Privacy Policy.',
          ),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await ref
          .read(userProvider.notifier)
          .signUp(
            email: _emailController.text.trim(),
            password: _passwordController.text,
            name: _nameController.text.trim(),
            termsAccepted: _acceptedTerms,
          );

      if (mounted) {
        // Show email confirmation message
        showDialog(
          context: context,
          barrierDismissible: false,
          builder:
              (context) => AlertDialog(
                title: const Text('Check Your Email'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.email, size: 64, color: Colors.green),
                    const Gap(16),
                    Text(
                      'We\'ve sent a confirmation email to ${_emailController.text.trim()}',
                      textAlign: TextAlign.center,
                    ),
                    const Gap(8),
                    const Text(
                      'Please check your email and click the confirmation link to activate your account.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                  ],
                ),
                actions: [
                  FilledButton(
                    onPressed: () {
                      Navigator.pop(context);
                      context.go('/login');
                    },
                    child: const Text('Go to Login'),
                  ),
                ],
              ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_formatSignupError(e)),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _openLegalPage(String path) async {
    final uri = Uri.parse('https://evraahein.app/$path');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the legal page.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watch the provider to keep it alive during async operations
    ref.watch(userProvider);
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    PhosphorIcons.lightning(PhosphorIconsStyle.duotone),
                    size: 80,
                    color: theme.colorScheme.primary,
                  ),
                  const Gap(16),
                  Text(
                    'EVraahein',
                    style: theme.textTheme.headlineLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const Gap(8),
                  Text(
                    'Plan EV trips, find live chargers, and never stress '
                    'about range.',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const Gap(48),
                  AppTextField(
                    controller: _nameController,
                    label: 'Name',
                    prefixIcon: Icons.person_outline,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter your name';
                      }
                      return null;
                    },
                  ),
                  const Gap(16),
                  AppTextField(
                    controller: _emailController,
                    label: 'Email',
                    prefixIcon: Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter your email';
                      }
                      if (!value.contains('@')) {
                        return 'Please enter a valid email';
                      }
                      return null;
                    },
                  ),
                  const Gap(16),
                  AppTextField(
                    controller: _passwordController,
                    label: 'Password',
                    prefixIcon: Icons.lock_outline,
                    obscureText: _obscurePassword,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed:
                          () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter a password';
                      }
                      if (value.length < 6) {
                        return 'Password must be at least 6 characters';
                      }
                      return null;
                    },
                  ),
                  const Gap(16),
                  AppTextField(
                    controller: _confirmPasswordController,
                    label: 'Confirm Password',
                    prefixIcon: Icons.lock_outline,
                    obscureText: _obscureConfirmPassword,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirmPassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed:
                          () => setState(
                            () =>
                                _obscureConfirmPassword =
                                    !_obscureConfirmPassword,
                          ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please confirm your password';
                      }
                      if (value != _passwordController.text) {
                        return 'Passwords do not match';
                      }
                      return null;
                    },
                  ),
                  const Gap(12),
                  CheckboxListTile(
                    value: _acceptedTerms,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    onChanged:
                        _isLoading
                            ? null
                            : (value) {
                              setState(() => _acceptedTerms = value ?? false);
                            },
                    title: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Text('I agree to the '),
                        TextButton(
                          onPressed: () => _openLegalPage('terms.html'),
                          child: const Text('Terms of Service'),
                        ),
                        const Text(' and '),
                        TextButton(
                          onPressed: () => _openLegalPage('privacy.html'),
                          child: const Text('Privacy Policy'),
                        ),
                      ],
                    ),
                  ),
                  const Gap(24),
                  AppButton(
                    label: 'Sign Up',
                    onPressed: _handleSignup,
                    isLoading: _isLoading,
                    isFullWidth: true,
                  ),
                  const Gap(12),
                  const OAuthButtons(),
                  const Gap(8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Already have an account? ',
                        style: theme.textTheme.bodyMedium,
                      ),
                      TextButton(
                        onPressed: () => context.go('/login'),
                        child: const Text('Login'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
