import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import '../../core/backend_service.dart';
import '../authentication/user_provider.dart';
import '../authentication/auth_service.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();
  late TextEditingController _nameController;
  late TextEditingController _emailController;
  late TextEditingController _phoneController;
  bool _isLoading = false;
  bool _isPhoneVerified = false;
  String? _verifiedPhoneNumber;

  @override
  void initState() {
    super.initState();
    final user = ref.read(userProvider);
    _nameController = TextEditingController(text: user?.name ?? '');
    _emailController = TextEditingController(text: user?.email ?? '');
    _phoneController = TextEditingController(text: user?.phoneNumber ?? '');
    _isPhoneVerified = user?.isPhoneVerified ?? false;
    _verifiedPhoneNumber =
        _isPhoneVerified
            ? _authService.normalizePhoneNumber(user?.phoneNumber ?? '')
            : null;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _verifyPhone() async {
    final normalizedPhone = _authService.normalizePhoneNumber(
      _phoneController.text.trim(),
    );
    if (normalizedPhone == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Enter a valid phone number first. Indian 10-digit numbers are supported automatically.',
          ),
        ),
      );
      return;
    }

    final otpController = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);
    var isSendingOtp = false;
    var isVerifyingOtp = false;

    await showDialog<void>(
      context: context,
      builder:
          (dialogContext) => StatefulBuilder(
            builder:
                (context, setDialogState) => AlertDialog(
                  title: const Text('Verify Phone'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'We will send a real verification code to $normalizedPhone.',
                      ),
                      const Gap(16),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed:
                              isSendingOtp
                                  ? null
                                  : () async {
                                    try {
                                      setDialogState(() => isSendingOtp = true);
                                      await _authService
                                          .requestPhoneVerification(
                                            normalizedPhone,
                                          );
                                      if (!mounted) return;
                                      messenger.showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'OTP sent to $normalizedPhone',
                                          ),
                                        ),
                                      );
                                    } catch (e) {
                                      if (!mounted) return;
                                      messenger.showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Could not send OTP: $e',
                                          ),
                                          backgroundColor: Colors.red,
                                        ),
                                      );
                                    } finally {
                                      if (dialogContext.mounted) {
                                        setDialogState(
                                          () => isSendingOtp = false,
                                        );
                                      }
                                    }
                                  },
                          icon:
                              isSendingOtp
                                  ? const SizedBox(
                                    height: 16,
                                    width: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                  : const Icon(Icons.sms_outlined),
                          label: Text(isSendingOtp ? 'Sending...' : 'Send OTP'),
                        ),
                      ),
                      const Gap(16),
                      TextField(
                        controller: otpController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'OTP',
                          hintText: 'Enter the 6-digit code',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed:
                          isVerifyingOtp
                              ? null
                              : () async {
                                try {
                                  setDialogState(() => isVerifyingOtp = true);
                                  await _authService.verifyPhoneOtp(
                                    phoneNumber: normalizedPhone,
                                    otp: otpController.text,
                                  );
                                  if (!mounted) return;
                                  setState(() {
                                    _isPhoneVerified = true;
                                    _verifiedPhoneNumber = normalizedPhone;
                                  });
                                  if (dialogContext.mounted) {
                                    Navigator.of(dialogContext).pop();
                                  }
                                  messenger.showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Phone verified successfully',
                                      ),
                                    ),
                                  );
                                } catch (e) {
                                  if (!mounted) return;
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: Text('Verification failed: $e'),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                } finally {
                                  if (dialogContext.mounted) {
                                    setDialogState(
                                      () => isVerifyingOtp = false,
                                    );
                                  }
                                }
                              },
                      child:
                          isVerifyingOtp
                              ? const SizedBox(
                                height: 16,
                                width: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                              : const Text('Verify'),
                    ),
                  ],
                ),
          ),
    );
    otpController.dispose();
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final user = ref.read(userProvider);
      if (user == null) {
        throw Exception('Please log in again to update your profile.');
      }

      await _authService.updateProfile(
        name: _nameController.text.trim(),
        email: _emailController.text.trim(),
      );

      await BackendService.put(
        '/api/users/profile',
        body: {
          'user_id': user.id,
          'phone_number': _phoneController.text.trim(),
          'is_phone_verified':
              _isPhoneVerified &&
              _verifiedPhoneNumber != null &&
              _verifiedPhoneNumber ==
                  _authService.normalizePhoneNumber(
                    _phoneController.text.trim(),
                  ),
        },
        headers: {
          if (_authService.getAuthToken() case final token?)
            'Authorization': 'Bearer $token',
        },
      );

      await ref.read(userProvider.notifier).refresh();

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Profile updated')));
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit Profile'), centerTitle: true),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Name',
                prefixIcon: Icon(Icons.person_outline),
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter your name';
                }
                return null;
              },
            ),
            const Gap(16),
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.email_outlined),
                border: OutlineInputBorder(),
              ),
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
            TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone Number',
                prefixIcon: Icon(Icons.phone_outlined),
                border: OutlineInputBorder(),
                helperText:
                    'Include a country code, or enter a 10-digit Indian mobile number and we will format it.',
              ),
              onChanged: (value) {
                // Only invalidate verification when the *normalized* number
                // actually differs from the one we already verified. Cosmetic
                // edits (spaces, formatting) shouldn't drop verified status.
                if (!_isPhoneVerified) return;
                final normalized = _authService.normalizePhoneNumber(value);
                if (normalized != _verifiedPhoneNumber) {
                  setState(() {
                    _isPhoneVerified = false;
                    _verifiedPhoneNumber = null;
                  });
                }
              },
            ),
            const Gap(12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(
                    _isPhoneVerified ? Icons.check_circle : Icons.info_outline,
                    color:
                        _isPhoneVerified
                            ? Colors.green
                            : Theme.of(context).colorScheme.primary,
                  ),
                  const Gap(12),
                  Expanded(
                    child: Text(
                      _isPhoneVerified
                          ? 'Phone verified for SOS and community support.'
                          : 'Phone not verified yet. Verify it here whenever you want faster help from nearby drivers and hosts.',
                    ),
                  ),
                  const Gap(12),
                  FilledButton.tonal(
                    onPressed: _isLoading ? null : _verifyPhone,
                    child: Text(_isPhoneVerified ? 'Verified' : 'Verify'),
                  ),
                ],
              ),
            ),
            const Gap(32),
            FilledButton(
              onPressed: _isLoading ? null : _saveProfile,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child:
                  _isLoading
                      ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                      : const Text('Save Changes'),
            ),
          ],
        ),
      ),
    );
  }
}
