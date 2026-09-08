import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:notchpeek/core/network/endpoints/api_endpoints.dart';
import 'package:notchpeek/core/network/errors/api_error.dart';
import 'package:notchpeek/core/network/errors/api_response.dart';
import 'package:notchpeek/core/network/interceptor/log_interceptor.dart';

/// The only place a `Dio` instance exists (architecture-playbook §5).
///
/// This is not the app's spine. NotchPeek's data comes from the OS through
/// platform channels; HTTP is here for artwork lookup and nothing else. There
/// is no auth interceptor because there are no accounts.
final apiServiceProvider = Provider<ApiService>((ref) {
  return ApiService(
    baseUrl: ApiEndpoint.itunesBaseUrl,
    logInterceptor: kDebugMode ? ApiLogInterceptor() : null,
  );
});

class ApiService {
  ApiService({required String baseUrl, Interceptor? logInterceptor}) {
    _dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
        responseType: ResponseType.json,
        headers: const {HttpHeaders.acceptHeader: 'application/json'},
      ),
    );
    if (logInterceptor != null) _dio.interceptors.add(logInterceptor);
  }

  late final Dio _dio;

  /// Test seam. Production code never assigns this.
  @visibleForTesting
  set debugAdapter(HttpClientAdapter adapter) =>
      _dio.httpClientAdapter = adapter;

  /// The only verb this app needs. Add another when a second endpoint exists,
  /// not before.
  Future<ApiResponse<Map<String, dynamic>>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        path,
        queryParameters: queryParameters,
      );
      final body = response.data;
      if (body == null) {
        return ApiResponse.error(
          message: 'Empty response.',
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.success(message: 'OK', data: body);
    } on DioException catch (e) {
      return ApiErrorHandler.handleDioError<Map<String, dynamic>>(e);
    } catch (e) {
      return ApiErrorHandler.handleGenericError<Map<String, dynamic>>(e);
    }
  }
}
