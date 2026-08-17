import 'package:ev_router_app2/src/core/app_config.dart';
import 'package:ev_router_app2/src/core/backend_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('backend exceptions expose a user-safe message', () {
    const error = BackendException(statusCode: 401, message: 'Sign in again.');

    expect(error.toString(), 'Sign in again.');
    expect(error.statusCode, 401);
  });

  test('dangerous launch features default to disabled', () {
    expect(AppConfig.sosEnabled, isFalse);
    expect(AppConfig.releaseAdsEnabled, isFalse);
  });
}
