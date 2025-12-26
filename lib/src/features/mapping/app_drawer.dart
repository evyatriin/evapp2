import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../authentication/user_provider.dart';
import '../community/gamification_widgets.dart';

class AppDrawer extends ConsumerStatefulWidget {
  const AppDrawer({super.key});

  @override
  ConsumerState<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends ConsumerState<AppDrawer> {
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _loadAppVersion();
  }

  Future<void> _loadAppVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    setState(() {
      _appVersion = '${packageInfo.version}+${packageInfo.buildNumber}';
    });
  }

  Future<void> _launchEmail(String email, String subject) async {
    final uri = Uri(
      scheme: 'mailto',
      path: email,
      query: 'subject=${Uri.encodeComponent(subject)}',
    );
    if (!await launchUrl(uri)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open email app')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = ref.watch(userProvider);

    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          // User Header
          UserAccountsDrawerHeader(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  theme.colorScheme.primary,
                  theme.colorScheme.primaryContainer,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            currentAccountPicture: CircleAvatar(
              backgroundColor: theme.colorScheme.surface,
              child: Text(
                user?.name.isNotEmpty == true ? user!.name[0].toUpperCase() : 'U',
                style: TextStyle(
                  fontSize: 32,
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            accountName: Row(
              children: [
                Text(
                  user?.name ?? 'Guest',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                if (user != null) ...[
                  const SizedBox(width: 8),
                  PointsBadge(points: user.points, compact: true, color: Colors.white),
                ],
              ],
            ),
            accountEmail: Text(user?.email ?? ''),
          ),

          // Profile
          ListTile(
            leading: Icon(PhosphorIcons.user(PhosphorIconsStyle.duotone)),
            title: const Text('Profile & Settings'),
            onTap: () {
              Navigator.pop(context);
              context.push('/profile');
            },
          ),

          // Statistics
          ListTile(
            leading: Icon(PhosphorIcons.chartBar(PhosphorIconsStyle.duotone)),
            title: const Text('My Statistics'),
            subtitle: const Text('km, CO₂ saved, & more'),
            onTap: () {
              Navigator.pop(context);
              context.push('/statistics');
            },
          ),

          const Divider(),

          // About
          ListTile(
            leading: Icon(PhosphorIcons.info(PhosphorIconsStyle.duotone)),
            title: const Text('About'),
            onTap: () {
              Navigator.pop(context);
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('About EV-Ranger'),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'EV-Ranger is your ultimate companion for electric vehicle route planning and charging station discovery.',
                          style: TextStyle(fontSize: 16),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Features:',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        const Text('• Smart EV route planning with charging stops'),
                        const Text('• Real-time charging station finder'),
                        const Text('• Community check-ins and reviews'),
                        const Text('• SOS assistance for emergencies'),
                        const Text('• Multi-vehicle support'),
                        const SizedBox(height: 16),
                        Text(
                          'Version: $_appVersion',
                          style: TextStyle(
                            color: theme.colorScheme.secondary,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              );
            },
          ),

          // Feedback
          ListTile(
            leading: Icon(PhosphorIcons.chatCircleDots(PhosphorIconsStyle.duotone)),
            title: const Text('Send Feedback'),
            onTap: () {
              Navigator.pop(context);
              _launchEmail(
                'feedback@evranger.app',
                'EV-Ranger Feedback',
              );
            },
          ),

          // Support
          ListTile(
            leading: Icon(PhosphorIcons.lifebuoy(PhosphorIconsStyle.duotone)),
            title: const Text('Support'),
            onTap: () {
              Navigator.pop(context);
              _launchEmail(
                'support@evranger.app',
                'EV-Ranger Support Request',
              );
            },
          ),

          // Terms and Conditions
          ListTile(
            leading: Icon(PhosphorIcons.fileText(PhosphorIconsStyle.duotone)),
            title: const Text('Terms & Conditions'),
            onTap: () {
              Navigator.pop(context);
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Terms & Conditions'),
                  content: const SingleChildScrollView(
                    child: Text(
                      'Terms of Service\n\n'
                      '1. Acceptance of Terms\n'
                      'By using EV-Ranger, you agree to these terms and conditions.\n\n'
                      '2. Use of Service\n'
                      'EV-Ranger provides route planning and charging station information. '
                      'We strive for accuracy but cannot guarantee real-time availability.\n\n'
                      '3. User Responsibilities\n'
                      '• Provide accurate vehicle information\n'
                      '• Use the app responsibly while driving\n'
                      '• Respect charging station etiquette\n\n'
                      '4. Privacy\n'
                      'We collect location data to provide routing services. '
                      'Your data is handled according to our Privacy Policy.\n\n'
                      '5. Limitation of Liability\n'
                      'EV-Ranger is not responsible for route accuracy, '
                      'charging station availability, or any damages incurred.\n\n'
                      '6. Changes to Terms\n'
                      'We reserve the right to modify these terms at any time.\n\n'
                      'Last updated: December 2025',
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              );
            },
          ),

          const Divider(),

          // App Version (Footer)
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Center(
              child: Text(
                'Version $_appVersion',
                style: TextStyle(
                  color: theme.colorScheme.secondary,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
