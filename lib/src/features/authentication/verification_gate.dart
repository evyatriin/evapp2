import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';

import '../../core/backend_service.dart';
import 'auth_service.dart';
import 'user_provider.dart';

/// Gate a community-help action behind email + phone verification.
///
/// Returns `true` only if the signed-in user is double-verified (email AND
/// phone). Otherwise it shows a sheet explaining what's missing, lets them
/// verify their phone inline, and returns whether they finished verified.
///
/// Server-side enforcement still exists on the backend — this is the friendly
/// front door so users aren't hit with a raw 403.
Future<bool> ensureVerifiedForHelp(
  BuildContext context,
  WidgetRef ref, {
  String action = 'use community help',
}) async {
  // Pull the freshest verification status before deciding.
  await ref.read(userProvider.notifier).refresh();
  final user = ref.read(userProvider);

  if (user == null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to continue.')),
      );
    }
    return false;
  }

  if (user.isDoubleVerified) return true;
  if (!context.mounted) return false;

  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _VerificationGateSheet(action: action),
  );
  return result ?? false;
}

class _VerificationGateSheet extends ConsumerWidget {
  const _VerificationGateSheet({required this.action});

  final String action;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final user = ref.watch(userProvider);
    final emailOk = user?.isEmailVerified ?? false;
    final phoneOk = user?.isPhoneVerified ?? false;
    final allOk = emailOk && phoneOk;

    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 8,
        bottom: 24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.verified_user_outlined,
              size: 40, color: theme.colorScheme.primary),
          const Gap(12),
          Text(
            'Verify to $action',
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const Gap(6),
          Text(
            'Community help is for verified drivers only. This keeps SOS and '
            'charger sharing safe for everyone.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const Gap(20),
          _CheckRow(
            done: emailOk,
            title: 'Email verified',
            subtitle: emailOk
                ? user?.email ?? 'Your email is confirmed.'
                : 'Check your inbox and tap the confirmation link.',
          ),
          const Gap(12),
          _CheckRow(
            done: phoneOk,
            title: 'Phone verified',
            subtitle: phoneOk
                ? user?.phoneNumber ?? 'Your phone is confirmed.'
                : 'Verify your mobile number with a one-time code.',
            action: phoneOk
                ? null
                : FilledButton.tonal(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () async {
                      final verified = await showModalBottomSheet<bool>(
                        context: context,
                        isScrollControlled: true,
                        showDragHandle: true,
                        builder: (_) => const PhoneVerificationSheet(),
                      );
                      if (verified == true && context.mounted) {
                        // Refresh so the row flips to verified.
                        await ref.read(userProvider.notifier).refresh();
                      }
                    },
                    child: const Text('Verify'),
                  ),
          ),
          const Gap(24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed:
                  allOk ? () => Navigator.of(context).pop(true) : null,
              child: Text(allOk ? 'Continue' : 'Complete verification'),
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({
    required this.done,
    required this.title,
    required this.subtitle,
    this.action,
  });

  final bool done;
  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          done ? Icons.check_circle : Icons.radio_button_unchecked,
          color: done ? Colors.green : theme.colorScheme.outline,
        ),
        const Gap(12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const Gap(2),
              Text(subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  )),
            ],
          ),
        ),
        if (action != null) ...[const Gap(8), action!],
      ],
    );
  }
}

/// Bottom sheet that verifies a phone number end-to-end: enter number → send
/// OTP → verify → persist `is_phone_verified` on the profile. Pops `true` on
/// success.
class PhoneVerificationSheet extends ConsumerStatefulWidget {
  const PhoneVerificationSheet({super.key});

  @override
  ConsumerState<PhoneVerificationSheet> createState() =>
      _PhoneVerificationSheetState();
}

class _PhoneVerificationSheetState
    extends ConsumerState<PhoneVerificationSheet> {
  final _authService = AuthService();
  late final TextEditingController _phoneController;
  final _otpController = TextEditingController();

  bool _sending = false;
  bool _verifying = false;
  bool _otpSent = false;
  String? _normalizedPhone;

  @override
  void initState() {
    super.initState();
    final user = ref.read(userProvider);
    _phoneController = TextEditingController(text: user?.phoneNumber ?? '');
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.red : null,
      ),
    );
  }

  Future<void> _sendOtp() async {
    final normalized =
        _authService.normalizePhoneNumber(_phoneController.text.trim());
    if (normalized == null) {
      _snack(
        'Enter a valid phone number. Indian 10-digit numbers are formatted '
        'automatically.',
        error: true,
      );
      return;
    }
    setState(() => _sending = true);
    try {
      await _authService.requestPhoneVerification(normalized);
      if (!mounted) return;
      setState(() {
        _otpSent = true;
        _normalizedPhone = normalized;
      });
      _snack('Code sent to $normalized');
    } catch (e) {
      _snack('Could not send code: ${_clean(e)}', error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _verifyOtp() async {
    final normalized = _normalizedPhone;
    if (normalized == null) return;
    if (_otpController.text.trim().isEmpty) {
      _snack('Enter the code we sent you.', error: true);
      return;
    }
    setState(() => _verifying = true);
    try {
      await _authService.verifyPhoneOtp(
        phoneNumber: normalized,
        otp: _otpController.text.trim(),
      );

      // Persist the verified flag on the profile.
      final user = ref.read(userProvider);
      if (user != null) {
        await BackendService.put(
          '/api/users/profile',
          body: {
            'user_id': user.id,
            'phone_number': normalized,
            'is_phone_verified': true,
          },
          headers: {
            if (_authService.getAuthToken() case final token?)
              'Authorization': 'Bearer $token',
          },
        );
        await ref.read(userProvider.notifier).refresh();
      }

      if (!mounted) return;
      _snack('Phone verified');
      Navigator.of(context).pop(true);
    } catch (e) {
      _snack('Verification failed: ${_clean(e)}', error: true);
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  String _clean(Object e) => e.toString().replaceFirst('Exception: ', '');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 8,
        bottom: 24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Verify your phone',
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const Gap(6),
          Text(
            "We'll text you a one-time code to confirm this number.",
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const Gap(20),
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            enabled: !_otpSent,
            decoration: const InputDecoration(
              labelText: 'Mobile number',
              prefixIcon: Icon(Icons.phone_outlined),
            ),
          ),
          if (_otpSent) ...[
            const Gap(16),
            TextField(
              controller: _otpController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Verification code',
                prefixIcon: Icon(Icons.sms_outlined),
              ),
            ),
            const Gap(8),
            TextButton(
              onPressed: _sending ? null : _sendOtp,
              child: const Text('Resend code'),
            ),
          ],
          const Gap(20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _otpSent
                  ? (_verifying ? null : _verifyOtp)
                  : (_sending ? null : _sendOtp),
              child: (_sending || _verifying)
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(_otpSent ? 'Verify' : 'Send code'),
            ),
          ),
        ],
      ),
    );
  }
}
