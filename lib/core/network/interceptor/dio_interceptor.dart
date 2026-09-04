import 'dart:io';

import 'package:dio/dio.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '/data/services/local_service.dart';
import '/data/services/routing_service.dart';
import '/features/auth_revamp/presentation/screens/login_screen.dart';
import '/features/profile_revamp/presentation/notifier/profile_notifier.dart';

/// Injects the stored bearer token into every request, and on a 401 clears
/// the session and routes to login.
///
/// No refresh-token flow exists in this backend (see
/// docs/playbook/architecture-playbook.md §3) — there's nothing to silently
/// retry, so a 401 is treated as a hard session expiry, same as the manual
/// logout flow in settings_screen.dart.
class ApiInterceptor extends Interceptor {
  final Ref _ref;
  ApiInterceptor(this._ref);

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token =
        await _ref.read(localStorageProvider).fetch(Keys.accessaccessToken);
    if (token.isNotEmpty) {
      options.headers[HttpHeaders.authorizationHeader] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.response?.statusCode == 401) {
      _handleSessionExpired();
    }
    handler.next(err);
  }

  void _handleSessionExpired() {
    final storage = _ref.read(localStorageProvider);
    storage.clear(Keys.accessaccessToken);
    storage.clear(Keys.useruserId);
    _ref.read(profileNotifierProvider.notifier).setUser(null);
    _ref.read(routingService).pushReplacement(LoginScreen.id);
  }
}
