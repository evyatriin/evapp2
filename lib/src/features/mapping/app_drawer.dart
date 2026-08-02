import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:gap/gap.dart';
import '../../core/navigation_helpers.dart';
import '../../core/theme.dart';
import '../authentication/user_model.dart';
import '../authentication/user_provider.dart';
import '../authentication/verification_gate.dart';
import '../community/gamification_widgets.dart';
import '../vehicle_profile/vehicle_model.dart';
import '../vehicle_profile/vehicle_provider.dart';

class AppDrawer extends ConsumerStatefulWidget {
  const AppDrawer({super.key});

  @override
  ConsumerState<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends ConsumerState<AppDrawer> {
  static const _supportEmail = 'hey@evraahein.app';
  static const _websiteUrl = 'https://www.evraahein.app/';
  static const _hostGuidelinesText =
      'Host Guidelines\n\n'
      'Private hosted chargers on EVraahein are meant for temporary EV charging access between users. Hosts should share only chargers they control, keep access instructions accurate, and respond clearly before travellers arrive.\n\n'
      'Hosts should avoid presenting listings as public charging stations, should use manual UPI or direct payment for MVP coordination, and should disclose parking limits, visitor access requirements, and connector details honestly.\n\n'
      'Apartment or gated-community hosts should ensure visitors are actually permitted before listing.\n\n'
      'Upload charger and parking photos when possible to improve traveller trust.';
  static const _chargingSafetyPolicyText =
      'Charging Safety Policy\n\n'
      'Hosted chargers should be properly earthed, protected by MCB/RCCB devices, protected from unsafe water exposure, and free from loose extension wiring.\n\n'
      'Hosts are responsible for maintaining safe parking access, avoiding cable obstruction across public roads, and ensuring travellers can approach and charge without creating obvious hazards.\n\n'
      'EVraahein may remove or flag listings that appear unsafe, misleading, inaccessible, or non-compliant with community rules.';
  static const _termsText =
      'Terms of Use\n\n'
      'Effective date: April 27, 2026\n\n'
      'EVraahein helps electric-vehicle drivers plan routes, discover charging stations, submit community check-ins, and manage vehicle information.\n\n'
      'By using the app, you agree to use it lawfully and only when it is safe to do so. You are responsible for confirming charging availability, pricing, station compatibility, and road conditions before acting on route guidance or community reports.\n\n'
      'You may submit content such as profile details, charger listings, check-ins, photos, and charging slips. You confirm that you have the right to share that content and that it does not violate another person’s privacy or rights.\n\n'
      'EVraahein may remove abusive, misleading, unsafe, or fraudulent content, restrict access to community features, or suspend accounts that misuse the service.\n\n'
      'Routing, charger, and availability data may come from third parties and community submissions. EVraahein does not guarantee uninterrupted service, complete coverage, or real-time station accuracy.\n\n'
      'Community Charging listings are privately hosted chargers shared by individual users. EVraahein facilitates discovery and request coordination only, and does not act as a regulated public charging operator, guaranteed charging network, or electricity reseller.\n\n'
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

  Widget _sectionLabel(ThemeData theme, String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(
        children: [
          Container(
            width: 16,
            height: 3,
            decoration: BoxDecoration(
              color: AppTheme.electricLime, // deliberate lime accent
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Gap(8),
          Text(
            label.toUpperCase(),
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerChip(
    ThemeData theme, {
    required IconData icon,
    required String label,
    required Color bg,
    required Color fg,
    bool border = false,
    VoidCallback? onTap,
  }) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: border
            ? Border.all(color: Colors.white.withValues(alpha: 0.5))
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: fg),
          const Gap(5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 170),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: fg,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return chip;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: chip,
    );
  }

  Widget _buildHeader(
    BuildContext context,
    ThemeData theme,
    UserProfile? user,
    VehicleProfile? vehicle,
  ) {
    final topPad = MediaQuery.of(context).padding.top;
    final name = (user?.name.isNotEmpty ?? false) ? user!.name : 'Guest';
    final initial = name != 'Guest' ? name[0].toUpperCase() : 'U';

    return Container(
      width: double.infinity,
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
      padding: EdgeInsets.fromLTRB(20, topPad + 22, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: user == null
                ? null
                : () {
                    Navigator.pop(context);
                    context.push('/profile');
                  },
            borderRadius: BorderRadius.circular(12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: theme.colorScheme.surface,
                  child: Text(
                    initial,
                    style: TextStyle(
                      fontSize: 28,
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Gap(14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                          ),
                          if (user != null) ...[
                            const Gap(8),
                            PointsBadge(
                              points: user.points,
                              compact: true,
                              color: Colors.white,
                            ),
                          ],
                        ],
                      ),
                      const Gap(2),
                      Text(
                        user?.email ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (user != null) ...[
            const Gap(16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (user.isDoubleVerified)
                  _headerChip(
                    theme,
                    icon: Icons.verified,
                    label: 'Verified',
                    bg: AppTheme.electricLime,
                    fg: const Color(0xFF0A2E14),
                  )
                else
                  _headerChip(
                    theme,
                    icon: Icons.gpp_maybe_outlined,
                    label: 'Verify phone',
                    bg: Colors.white.withValues(alpha: 0.18),
                    fg: Colors.white,
                    border: true,
                    onTap: () async {
                      final ok = await showModalBottomSheet<bool>(
                        context: context,
                        isScrollControlled: true,
                        showDragHandle: true,
                        builder: (_) => const PhoneVerificationSheet(),
                      );
                      if (ok == true) {
                        ref.read(userProvider.notifier).refresh();
                      }
                    },
                  ),
                if (vehicle != null)
                  _headerChip(
                    theme,
                    icon: Icons.directions_car,
                    label: '${vehicle.brand} ${vehicle.model}',
                    bg: Colors.white.withValues(alpha: 0.18),
                    fg: Colors.white,
                  )
                else
                  _headerChip(
                    theme,
                    icon: Icons.add,
                    label: 'Add your EV',
                    bg: Colors.white.withValues(alpha: 0.18),
                    fg: Colors.white,
                    border: true,
                    onTap: () {
                      Navigator.pop(context);
                      context.push('/setup/vehicle/add');
                    },
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  void _showLegalSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(PhosphorIcons.fileText(PhosphorIconsStyle.duotone)),
              title: const Text('Terms of Use'),
              onTap: () {
                Navigator.pop(sheetContext);
                _showDocumentDialog(context, 'Terms of Use', _termsText);
              },
            ),
            ListTile(
              leading:
                  Icon(PhosphorIcons.handshake(PhosphorIconsStyle.duotone)),
              title: const Text('Host Guidelines'),
              onTap: () {
                Navigator.pop(sheetContext);
                _showDocumentDialog(
                    context, 'Host Guidelines', _hostGuidelinesText);
              },
            ),
            ListTile(
              leading: Icon(
                  PhosphorIcons.shieldWarning(PhosphorIconsStyle.duotone)),
              title: const Text('Charging Safety Policy'),
              onTap: () {
                Navigator.pop(sheetContext);
                _showDocumentDialog(
                    context, 'Charging Safety Policy', _chargingSafetyPolicyText);
              },
            ),
            ListTile(
              leading:
                  Icon(PhosphorIcons.shieldCheck(PhosphorIconsStyle.duotone)),
              title: const Text('Privacy Policy'),
              onTap: () {
                Navigator.pop(sheetContext);
                _showDocumentDialog(context, 'Privacy Policy', _privacyText);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = ref.watch(userProvider);
    final vehicles = ref.watch(vehicleProvider);
    final primaryVehicle = vehicles.isEmpty
        ? null
        : vehicles.firstWhere((v) => v.isPrimary,
            orElse: () => vehicles.first);

    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          _buildHeader(context, theme, user, primaryVehicle),

          _sectionLabel(theme, 'Account'),

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

          _sectionLabel(theme, 'Tools'),

          ListTile(
            leading: Icon(PhosphorIcons.houseLine(PhosphorIconsStyle.duotone)),
            title: const Text('Community Charging'),
            subtitle: const Text('Share or request a charger'),
            onTap: () {
              Navigator.pop(context);
              context.push('/community-charging');
            },
          ),

          ListTile(
            leading: Icon(PhosphorIcons.carBattery(PhosphorIconsStyle.duotone)),
            title: const Text('OBD Scanner'),
            subtitle: const Text('Live data from your car'),
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

          _sectionLabel(theme, 'Help & legal'),

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
            leading: Icon(PhosphorIcons.scales(PhosphorIconsStyle.duotone)),
            title: const Text('Legal & policies'),
            subtitle: const Text('Terms, privacy, host & safety'),
            onTap: () {
              Navigator.pop(context);
              _showLegalSheet(context);
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
                  color: theme.colorScheme.onSurfaceVariant,
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
