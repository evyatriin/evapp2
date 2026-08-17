import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/mapping/home_screen.dart';
import '../features/mapping/location_search_screen.dart';
import '../features/vehicle_profile/profile_screen.dart';
import '../features/vehicle_profile/vehicle_form_screen.dart';
import '../features/vehicle_profile/vehicle_model.dart';
import '../features/route_planner/route_planner_screen.dart';
import '../features/community/sos_screen.dart';
import '../features/onboarding/splash_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/navigation/main_screen.dart';
import '../features/charge/charge_screen.dart';
import '../features/charge/community_charging_screen.dart';
import '../features/community/community_screen.dart';
import '../features/route_planner/route_result_screen.dart';
import '../features/authentication/login_screen.dart';
import '../features/authentication/signup_screen.dart';
import '../features/authentication/forgot_password_screen.dart';
import '../features/profile/profile_settings_screen.dart';
import '../features/profile/edit_profile_screen.dart';
import '../features/profile/change_password_screen.dart';
import '../features/profile/statistics_screen.dart';
import '../features/route_planner/saved_routes_screen.dart';
import '../features/vehicle_profile/vehicle_selection_screen.dart';
import '../features/obd/obd_analytics_screen.dart';
import '../features/obd/obd_telemetry_screen.dart';
import '../features/beckn/beckn_network_screen.dart';
import 'app_config.dart';

final router = GoRouter(
  initialLocation: '/splash',
  routes: [
    GoRoute(path: '/splash', builder: (context, state) => const SplashScreen()),
    GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
    GoRoute(path: '/signup', builder: (context, state) => const SignupScreen()),
    GoRoute(
      path: '/forgot-password',
      builder: (context, state) => const ForgotPasswordScreen(),
    ),
    GoRoute(
      path: '/onboarding',
      builder: (context, state) => const OnboardingScreen(),
      routes: [
        GoRoute(
          path: 'vehicle-select',
          builder: (context, state) => const VehicleSelectionScreen(),
        ),
      ],
    ),
    GoRoute(
      path: '/saved-routes',
      builder: (context, state) => const SavedRoutesScreen(),
    ),
    GoRoute(
      path: '/planner/result',
      redirect:
          (context, state) =>
              state.extra is Map<String, dynamic> ? null : '/planner',
      builder: (context, state) {
        final extra = state.extra! as Map<String, dynamic>;
        return RouteResultScreen(extra: extra);
      },
    ),
    GoRoute(
      path: '/statistics',
      builder: (context, state) => const StatisticsScreen(),
    ),
    GoRoute(
      path: '/community-charging',
      builder: (context, state) => const CommunityChargingScreen(),
    ),
    GoRoute(
      path: '/search',
      builder: (context, state) => const LocationSearchScreen(),
    ),
    GoRoute(
      path: '/open-network',
      builder: (context, state) => const BecknNetworkScreen(),
    ),
    GoRoute(
      path: '/obd',
      builder: (context, state) => const _ObdPage(),
      routes: [
        GoRoute(
          path: 'analytics',
          builder: (context, state) => const ObdAnalyticsScreen(),
        ),
      ],
    ),
    GoRoute(
      path: '/profile',
      builder: (context, state) => const ProfileSettingsScreen(),
      routes: [
        GoRoute(
          path: 'edit',
          builder: (context, state) => const EditProfileScreen(),
        ),
        GoRoute(
          path: 'change-password',
          builder: (context, state) => const ChangePasswordScreen(),
        ),
      ],
    ),
    GoRoute(
      path: '/setup',
      builder: (context, state) => const ProfileScreen(),
      routes: [
        GoRoute(
          path: 'vehicle/add',
          builder: (context, state) => const VehicleSelectionScreen(),
        ),
        GoRoute(
          path: 'vehicle/edit',
          redirect:
              (context, state) =>
                  state.extra is VehicleProfile ? null : '/setup',
          builder: (context, state) {
            final vehicle = state.extra! as VehicleProfile;
            return VehicleFormScreen(vehicleToEdit: vehicle);
          },
        ),
      ],
    ),
    GoRoute(
      path: '/sos',
      redirect: (context, state) => AppConfig.sosEnabled ? null : '/',
      builder: (context, state) => const SosScreen(),
    ),
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) {
        return MainScreen(navigationShell: navigationShell);
      },
      branches: [
        // Find (Map)
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
          ],
        ),
        // Plan (Route Planner)
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/planner',
              builder: (context, state) => const RoutePlannerScreen(),
            ),
          ],
        ),
        // Charge
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/charge',
              builder: (context, state) => const ChargeScreen(),
            ),
          ],
        ),
        // Community
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/community',
              builder: (context, state) => const CommunityScreen(),
            ),
          ],
        ),
      ],
    ),
  ],
);

class _ObdPage extends StatelessWidget {
  const _ObdPage();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: ObdTelemetryScreen());
  }
}
