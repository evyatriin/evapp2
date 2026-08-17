import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'user_model.dart';
import 'user_provider.dart';

/// "Continue with Google / Apple" buttons plus an "or" divider.
///
/// The OAuth session comes back asynchronously through a deep link, so instead
/// of awaiting a result we listen for the user becoming available and route
/// then. Navigation only fires when *this widget* started the flow, so it never
/// competes with the email/password screens' own navigation.
class OAuthButtons extends ConsumerStatefulWidget {
  const OAuthButtons({super.key});

  @override
  ConsumerState<OAuthButtons> createState() => _OAuthButtonsState();
}

class _OAuthButtonsState extends ConsumerState<OAuthButtons> {
  bool _initiated = false;
  OAuthProvider? _pending;

  bool get _appleAvailable =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  Future<void> _start(OAuthProvider provider) async {
    setState(() {
      _initiated = true;
      _pending = provider;
    });
    try {
      final launched =
          await ref.read(userProvider.notifier).signInWithOAuth(provider);
      if (!launched && mounted) {
        setState(() => _pending = null);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _pending = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not start sign-in: ${_friendly(e)}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _friendly(Object e) {
    final msg = e.toString();
    if (msg.contains('provider is not enabled') ||
        msg.contains('Unsupported provider') ||
        msg.contains('validation_failed')) {
      return 'this sign-in option is not enabled yet.';
    }
    return msg.replaceFirst('Exception: ', '');
  }

  Future<void> _routeAfterAuth() async {
    final prefs = await SharedPreferences.getInstance();
    final done = prefs.getBool('onboarding_completed') ?? false;
    if (mounted) context.go(done ? '/' : '/onboarding');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // When our OAuth flow completes, the user becomes non-null — route then.
    ref.listen<UserProfile?>(userProvider, (previous, next) {
      if (_initiated && previous == null && next != null) {
        _routeAfterAuth();
      }
    });

    return Column(
      children: [
        Row(
          children: [
            const Expanded(child: Divider()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'or',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const Expanded(child: Divider()),
          ],
        ),
        const Gap(16),
        _ProviderButton(
          icon: PhosphorIcons.googleLogo(PhosphorIconsStyle.bold),
          label: 'Continue with Google',
          loading: _pending == OAuthProvider.google,
          onPressed: _pending != null
              ? null
              : () => _start(OAuthProvider.google),
        ),
        if (_appleAvailable) ...[
          const Gap(12),
          _ProviderButton(
            icon: PhosphorIcons.appleLogo(PhosphorIconsStyle.fill),
            label: 'Continue with Apple',
            loading: _pending == OAuthProvider.apple,
            onPressed: _pending != null
                ? null
                : () => _start(OAuthProvider.apple),
          ),
        ],
      ],
    );
  }
}

class _ProviderButton extends StatelessWidget {
  const _ProviderButton({
    required this.icon,
    required this.label,
    required this.loading,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool loading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: loading
          ? const SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon, size: 20),
      label: Text(label),
    );
  }
}
