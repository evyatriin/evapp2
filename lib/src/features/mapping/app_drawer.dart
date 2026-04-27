import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/navigation_helpers.dart';
import '../authentication/user_provider.dart';
import '../community/gamification_widgets.dart';

class AppDrawer extends ConsumerStatefulWidget {
  const AppDrawer({super.key});

  @override
  ConsumerState<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends ConsumerState<AppDrawer> {
  static const _supportEmail = 'hey@evraahein.app';
  static const _websiteUrl = 'https://www.evraahein.app/';
  static const _termsText =
      'Terms of Use\n\n'
      'Effective date: April 27, 2026\n\n'
      'EVraahein helps electric-vehicle drivers plan routes, discover charging stations, submit community check-ins, and manage vehicle information.\n\n'
      'By using the app, you agree to use it lawfully and only when it is safe to do so. You are responsible for confirming charging availability, pricing, station compatibility, and road conditions before acting on route guidance or community reports.\n\n'
      'You may submit content such as profile details, charger listings, check-ins, photos, and charging slips. You confirm that you have the right to share that content and that it does not violate another person’s privacy or rights.\n\n'
      'EVraahein may remove abusive, misleading, unsafe, or fraudulent content, restrict access to community features, or suspend accounts that misuse the service.\n\n'
      'Routing, charger, and availability data may come from third parties and community submissions. EVraahein does not guarantee uninterrupted service, complete coverage, or real-time station accuracy.\n\n'
      'To the maximum extent allowed by law, EVraahein is provided on an as-available basis and is not liable for indirect losses, missed charging opportunities, or damages arising from reliance on route, charger, or community information.\n\n'
      'If you delete your account, EVraahein will attempt to remove your profile, vehicles, saved items, check-ins, and other account-linked data from active systems, subject to legal, security, fraud-prevention, and backup-retention needs.\n\n'
      'Questions about these terms can be sent to hey@evraahein.app.';
  static const _privacyText =
      'Privacy Policy\n\n'
      'Effective date: April 27, 2026\n\n'
      'EVraahein collects the information needed to operate the app, including account details, vehicle details, route and charger preferences, community submissions, optional photos, and device-generated location data when you request location-based features.\n\n'
      'Location is used to center maps, search nearby chargers, plan trips, and support SOS-style community assistance. Camera and photo library access are only used when you choose to capture or attach images.\n\n'
      'The app uses Supabase for authentication, database storage, and file storage, and it uses third-party mapping and routing providers such as Google and HERE to fulfill search, map, and route requests.\n\n'
      'Community content such as check-ins, ratings, charger listings, and uploaded media may be visible to other users depending on the feature where it was shared.\n\n'
      'EVraahein retains operational data for as long as needed to provide the service, maintain security, resolve disputes, enforce policies, and meet legal obligations. When you delete your account, EVraahein will attempt to delete or de-identify account-linked content from active systems, while some logs, backups, or legally required records may be retained for a limited period.\n\n'
      'You can request support or ask privacy questions at hey@evraahein.app.\n\n'
      'Website: https://www.evraahein.app/';
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

  Future<void> _launchWebsite() async {
    final uri = Uri.parse(_websiteUrl);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Could not open website')));
      }
    }
  }

  void _showDocumentDialog(BuildContext context, String title, String body) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(title),
            content: SingleChildScrollView(child: Text(body)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
    );
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
                user?.name.isNotEmpty == true
                    ? user!.name[0].toUpperCase()
                    : 'U',
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
                  PointsBadge(
                    points: user.points,
                    compact: true,
                    color: Colors.white,
                  ),
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

          ListTile(
            leading: Icon(PhosphorIcons.houseLine(PhosphorIconsStyle.duotone)),
            title: const Text('Community Charging'),
            subtitle: const Text('Host your charger or manage requests'),
            onTap: () {
              Navigator.pop(context);
              context.push('/community-charging');
            },
          ),

          ListTile(
            leading: Icon(PhosphorIcons.carBattery(PhosphorIconsStyle.duotone)),
            title: const Text('OBD Scanner'),
            subtitle: const Text('Scan, connect, and open live analytics'),
            onTap: () {
              Navigator.pop(context);
              openObdScanner(context);
            },
          ),

          ListTile(
            leading: Icon(
              PhosphorIcons.warningCircle(PhosphorIconsStyle.duotone),
              color: theme.colorScheme.error,
            ),
            title: Text(
              'Emergency SOS',
              style: TextStyle(color: theme.colorScheme.error),
            ),
            subtitle: const Text('Get help fast in an emergency'),
            onTap: () {
              Navigator.pop(context);
              context.push('/sos');
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
                builder:
                    (context) => AlertDialog(
                      title: const Text('About EVraahein'),
                      content: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'EVraahein is your ultimate companion for electric vehicle route planning and charging station discovery.',
                              style: TextStyle(fontSize: 16),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Features:',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              '• Smart EV route planning with charging stops',
                            ),
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
            leading: Icon(
              PhosphorIcons.chatCircleDots(PhosphorIconsStyle.duotone),
            ),
            title: const Text('Send Feedback'),
            onTap: () {
              Navigator.pop(context);
              _launchEmail(_supportEmail, 'EVraahein Feedback');
            },
          ),

          // Support
          ListTile(
            leading: Icon(PhosphorIcons.lifebuoy(PhosphorIconsStyle.duotone)),
            title: const Text('Support'),
            onTap: () {
              Navigator.pop(context);
              _launchEmail(_supportEmail, 'EVraahein Support Request');
            },
          ),

          ListTile(
            leading: Icon(PhosphorIcons.globe(PhosphorIconsStyle.duotone)),
            title: const Text('Website'),
            subtitle: const Text('www.evraahein.app'),
            onTap: () {
              Navigator.pop(context);
              _launchWebsite();
            },
          ),

          ListTile(
            leading: Icon(PhosphorIcons.fileText(PhosphorIconsStyle.duotone)),
            title: const Text('Terms of Use'),
            onTap: () {
              Navigator.pop(context);
              _showDocumentDialog(context, 'Terms of Use', _termsText);
            },
          ),

          ListTile(
            leading: Icon(
              PhosphorIcons.shieldCheck(PhosphorIconsStyle.duotone),
            ),
            title: const Text('Privacy Policy'),
            onTap: () {
              Navigator.pop(context);
              _showDocumentDialog(context, 'Privacy Policy', _privacyText);
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
