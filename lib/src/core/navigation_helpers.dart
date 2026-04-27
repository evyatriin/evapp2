import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

Future<void> openObdScanner(BuildContext context) async {
  await GoRouter.of(context).push('/obd');
}

Future<void> openObdAnalytics(BuildContext context) async {
  await GoRouter.of(context).push('/obd/analytics');
}
