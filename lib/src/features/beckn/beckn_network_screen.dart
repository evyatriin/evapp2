import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// Open Network (Beckn · UEI) — "Discover & Charge" preview.
///
/// This is a forward-looking showcase of EVraahein connecting to India's
/// Unified Energy Interface (UEI), built on the open Beckn protocol. Instead of
/// juggling a separate app for every charge point operator (CPO), a driver will
/// be able to *discover* every charger on the open network and *charge* — start
/// a session and pay over UPI — from inside EVraahein.
///
/// The feature is not live yet, so this screen presents the vision, the
/// discover → charge flow, the participating-network story, and a waitlist CTA.
class BecknNetworkScreen extends StatefulWidget {
  const BecknNetworkScreen({super.key});

  @override
  State<BecknNetworkScreen> createState() => _BecknNetworkScreenState();
}

class _BecknNetworkScreenState extends State<BecknNetworkScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _joined = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _joinWaitlist() {
    setState(() => _joined = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          "You're on the list — we'll notify you when the open network goes live.",
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Open Network')),
      body: FadeTransition(
        opacity: _controller,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            const _HeroCard(),
            const SizedBox(height: 20),
            _SectionTitle(
              icon: PhosphorIcons.compass(PhosphorIconsStyle.duotone),
              title: 'How Discover & Charge works',
              subtitle: 'One open protocol, four simple steps',
            ),
            const SizedBox(height: 12),
            const _FlowStepper(),
            const SizedBox(height: 24),
            _SectionTitle(
              icon: PhosphorIcons.plugsConnected(PhosphorIconsStyle.duotone),
              title: 'One app. Every network.',
              subtitle:
                  'UEI unifies charge point operators behind a single interface — '
                  'no more app-hopping.',
            ),
            const SizedBox(height: 12),
            const _NetworkGrid(),
            const SizedBox(height: 24),
            _SectionTitle(
              icon: PhosphorIcons.sparkle(PhosphorIconsStyle.duotone),
              title: 'Why it changes everything',
              subtitle: null,
            ),
            const SizedBox(height: 12),
            const _BenefitList(),
            const SizedBox(height: 24),
            _WaitlistCard(joined: _joined, onJoin: _joinWaitlist),
            const SizedBox(height: 20),
            _AboutBeckn(theme: theme),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Hero
// ---------------------------------------------------------------------------

class _HeroCard extends StatelessWidget {
  const _HeroCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [cs.primary, cs.primaryContainer],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: cs.onPrimary.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      PhosphorIcons.rocketLaunch(PhosphorIconsStyle.fill),
                      size: 14,
                      color: cs.onPrimary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'COMING SOON',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: cs.onPrimary,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Discover & Charge on the open network',
            style: theme.textTheme.headlineSmall?.copyWith(
              color: cs.onPrimary,
              fontWeight: FontWeight.w800,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Soon, EVraahein will connect to the Unified Energy Interface (UEI) — '
            'India’s open charging network built on the Beckn protocol. Find any '
            'charger, start a session, and pay over UPI, without installing a '
            'separate app for every operator.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onPrimary.withValues(alpha: 0.92),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _HeroChip(
                icon: PhosphorIcons.magnifyingGlass(PhosphorIconsStyle.bold),
                label: 'Discover',
              ),
              _HeroChip(
                icon: PhosphorIcons.lightning(PhosphorIconsStyle.bold),
                label: 'Charge',
              ),
              _HeroChip(
                icon: PhosphorIcons.currencyInr(PhosphorIconsStyle.bold),
                label: 'Pay via UPI',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _HeroChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: cs.onPrimary.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: cs.onPrimary),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: cs.onPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section title
// ---------------------------------------------------------------------------

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  const _SectionTitle({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: theme.colorScheme.primary, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Discover -> Charge flow stepper
// ---------------------------------------------------------------------------

class _FlowStep {
  final IconData icon;
  final String title;
  final String description;
  final String becknTerm;
  const _FlowStep(this.icon, this.title, this.description, this.becknTerm);
}

class _FlowStepper extends StatelessWidget {
  const _FlowStepper();

  static const _steps = <_FlowStep>[
    _FlowStep(
      PhosphorIconsDuotone.magnifyingGlass,
      'Discover',
      'Search every charger on the open network at once — across all operators, live availability and price.',
      'search',
    ),
    _FlowStep(
      PhosphorIconsDuotone.slidersHorizontal,
      'Select',
      'Compare speed, connector type and ₹/kWh, then pick the charger that fits your trip.',
      'select · init',
    ),
    _FlowStep(
      PhosphorIconsDuotone.lightning,
      'Charge',
      'Confirm and start the session in-app, then pay seamlessly over UPI — no operator app required.',
      'confirm · status',
    ),
    _FlowStep(
      PhosphorIconsDuotone.receipt,
      'Done',
      'Get a unified receipt and rate the charger — your feedback flows back to the whole network.',
      'rating · support',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          for (var i = 0; i < _steps.length; i++)
            _StepRow(
              step: _steps[i],
              index: i + 1,
              isLast: i == _steps.length - 1,
            ),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  final _FlowStep step;
  final int index;
  final bool isLast;
  const _StepRow({
    required this.step,
    required this.index,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(step.icon, color: cs.primary, size: 22),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: cs.outlineVariant,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        step.title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: cs.secondaryContainer,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          step.becknTerm,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: cs.onSecondaryContainer,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    step.description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                  // Guarantees the text column is strictly taller than the
                  // icon+connector column, avoiding a sub-pixel IntrinsicHeight
                  // tie that renders a 1px overflow stripe in debug builds.
                  const SizedBox(height: 2),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Participating networks grid
// ---------------------------------------------------------------------------

class _NetworkGrid extends StatelessWidget {
  const _NetworkGrid();

  static const _networks = <String>[
    'ChargeZone',
    'Statiq',
    'Tata Power EZ',
    'Ather Grid',
    'Jio-bp pulse',
    'Kazam',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: [
              for (final n in _networks) _NetworkPill(name: n),
              _NetworkPill(name: '& more', muted: true),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                PhosphorIcons.arrowsInLineVertical(PhosphorIconsStyle.bold),
                size: 16,
                color: cs.primary,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Unified under one interface via UEI',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: cs.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Illustrative of the open-network vision. Operator participation is '
            'subject to their onboarding onto UEI.',
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _NetworkPill extends StatelessWidget {
  final String name;
  final bool muted;
  const _NetworkPill({required this.name, this.muted = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: muted
            ? cs.surfaceContainerHighest
            : cs.primaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!muted) ...[
            Icon(
              PhosphorIcons.chargingStation(PhosphorIconsStyle.duotone),
              size: 16,
              color: cs.primary,
            ),
            const SizedBox(width: 6),
          ],
          Text(
            name,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: muted ? cs.onSurfaceVariant : cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Benefits
// ---------------------------------------------------------------------------

class _BenefitList extends StatelessWidget {
  const _BenefitList();

  static const _benefits = <List<String>>[
    [
      'No more app-hopping',
      'Stop installing a wallet for every operator. Discover and charge everywhere from EVraahein.',
    ],
    [
      'Real interoperability',
      'Beckn is an open protocol — the same one behind ONDC — so any compliant operator can plug in.',
    ],
    [
      'Transparent pricing',
      'See live ₹/kWh and availability across networks before you commit to a stop.',
    ],
    [
      'Pay the way India pays',
      'Settle sessions instantly over UPI, with a single unified receipt.',
    ],
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      children: [
        for (final b in _benefits)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    PhosphorIcons.checkCircle(PhosphorIconsStyle.fill),
                    color: cs.primary,
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          b[0],
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          b[1],
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Waitlist CTA
// ---------------------------------------------------------------------------

class _WaitlistCard extends StatelessWidget {
  final bool joined;
  final VoidCallback onJoin;
  const _WaitlistCard({required this.joined, required this.onJoin});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: cs.secondaryContainer.withValues(alpha: 0.5),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        children: [
          Icon(
            joined
                ? PhosphorIcons.bellRinging(PhosphorIconsStyle.duotone)
                : PhosphorIcons.bell(PhosphorIconsStyle.duotone),
            size: 34,
            color: cs.primary,
          ),
          const SizedBox(height: 10),
          Text(
            joined ? "You're on the list!" : 'Be first to charge on the network',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            joined
                ? "We'll let you know the moment Discover & Charge goes live in your city."
                : 'Join the waitlist and get early access when the open network launches.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: joined ? null : onJoin,
              icon: Icon(
                joined
                    ? PhosphorIcons.check(PhosphorIconsStyle.bold)
                    : PhosphorIcons.bellSimpleRinging(PhosphorIconsStyle.bold),
                size: 18,
              ),
              label: Text(joined ? 'Added to waitlist' : 'Notify me at launch'),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// About Beckn / UEI footer
// ---------------------------------------------------------------------------

class _AboutBeckn extends StatelessWidget {
  final ThemeData theme;
  const _AboutBeckn({required this.theme});

  @override
  Widget build(BuildContext context) {
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                PhosphorIcons.info(PhosphorIconsStyle.duotone),
                size: 18,
                color: cs.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                'What is Beckn & UEI?',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Beckn is an open protocol for decentralised commerce — the same '
            'foundation behind ONDC. The Unified Energy Interface (UEI) applies '
            'Beckn to energy, so any charge point operator can be discovered and '
            'transacted with through a single app. EVraahein is building toward '
            'becoming a UEI-compliant discovery and charging experience.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
