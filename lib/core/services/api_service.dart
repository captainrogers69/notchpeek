import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:gohomes/core/network/endpoints/api_method.dart';
import 'package:gohomes/core/network/errors/api_error.dart';
import 'package:gohomes/core/network/errors/api_response.dart' show ApiResponse;
import 'package:gohomes/core/network/interceptor/dio_interceptor.dart';
import 'package:gohomes/core/network/interceptor/log_interceptor.dart';
import 'package:gohomes/data/manager/service_base.dart' show ServiceBase;
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// REST client for this backend, per docs/playbook/architecture-playbook.md
/// §3. Every endpoint responds with the same envelope:
/// `{"success": bool, "data": ..., "message": "..."}` — no GraphQL.
final apiServiceProvider = Provider<ApiService>((ref) {
  return ApiService(
    baseUrl: ServiceBase.apiBaseUrl,
    interceptor: ApiInterceptor(ref),
    logInterceptor: kDebugMode ? ApiLogInterceptor() : null,
  );
});

class ApiService {
  late final Dio _dio;

  ApiService({
    required String baseUrl,
    required ApiInterceptor interceptor,
    ApiLogInterceptor? logInterceptor,
  }) {
    _dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(minutes: 2),
        sendTimeout: const Duration(seconds: 30),
        responseType: ResponseType.json,
        headers: const {
          HttpHeaders.acceptHeader: 'application/json',
          HttpHeaders.contentTypeHeader: 'application/json',
        },
      ),
    );

    _dio.interceptors.add(interceptor);
    if (kDebugMode && logInterceptor != null) {
      _dio.interceptors.add(logInterceptor);
    }
  }

  Future<ApiResponse<dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? headers,
  }) {
    return _send(ApiMethod.getr, path,
        queryParameters: queryParameters, headers: headers);
  }

  Future<ApiResponse<dynamic>> post(
    String path, {
    Map<String, dynamic>? data,
    Map<String, dynamic>? headers,
  }) {
    return _send(ApiMethod.post, path, data: data, headers: headers);
  }

  Future<ApiResponse<dynamic>> put(
    String path, {
    Map<String, dynamic>? data,
    Map<String, dynamic>? headers,
  }) {
    return _send(ApiMethod.put, path, data: data, headers: headers);
  }

  Future<ApiResponse<dynamic>> delete(
    String path, {
    Map<String, dynamic>? data,
    Map<String, dynamic>? headers,
  }) {
    return _send(ApiMethod.delete, path, data: data, headers: headers);
  }

  /// Multipart upload — single file plus optional extra form fields (e.g.
  /// the `folder` field the media upload endpoints expect).
  Future<ApiResponse<dynamic>> multipart(
    String path, {
    required String fieldName,
    required String filePath,
    Map<String, String>? fields,
    Map<String, dynamic>? headers,
  }) async {
    final formData = FormData.fromMap({
      ...?fields,
      fieldName: await MultipartFile.fromFile(filePath),
    });
    return _send(ApiMethod.post, path, data: formData, headers: headers);
  }

  Future<ApiResponse<dynamic>> _send(
    ApiMethod method,
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? headers,
  }) async {
    try {
      final response = await _dio.request<Map<String, dynamic>>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: Options(method: method.value, headers: headers),
      );
      return _unwrap(response);
    } on DioException catch (e) {
      return ApiErrorHandler.handleDioError(e);
    } catch (e) {
      return ApiErrorHandler.handleGenericError(e);
    }
  }

  /// For endpoints that don't follow this backend's standard `{success,
  /// data, message}` envelope — e.g. the legacy `api/auth/*` endpoints,
  /// which return the payload directly at the top level and signal
  /// success via HTTP status only, not a `success` field. Callers own
  /// their own status/parsing logic.
  Future<Response<Map<String, dynamic>>> postRaw(
    String path, {
    Map<String, dynamic>? data,
    Map<String, dynamic>? headers,
  }) {
    return _dio.post<Map<String, dynamic>>(
      path,
      data: data,
      options: Options(headers: headers),
    );
  }

  /// GET counterpart to [postRaw] — for endpoints whose envelope doesn't
  /// match `{success, data, message}` (e.g. `api/profile/myProfile`, which
  /// uses `status` instead of `success` — see
  /// docs/superpowers/specs/2026-08-14-profile-completion-design.md).
  /// Callers own their own status/parsing logic.
  Future<Response<Map<String, dynamic>>> getRaw(
    String path, {
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? headers,
  }) {
    return _dio.get<Map<String, dynamic>>(
      path,
      queryParameters: queryParameters,
      options: Options(headers: headers),
    );
  }

  /// Unwraps this backend's REST envelope: `{success, data, message}`.
  ApiResponse<dynamic> _unwrap(Response<Map<String, dynamic>> response) {
    final body = response.data;
    if (body == null) {
      return ApiResponse.error(
        message: 'Empty response from server.',
        statusCode: response.statusCode,
      );
    }

    final success = body['success'] == true;
    final message = body['message']?.toString() ??
        (success ? 'Success' : 'Something went wrong');

    if (!success) {
      return ApiResponse.error(
          message: message, statusCode: response.statusCode);
    }

    return ApiResponse.success(message: message, data: body['data']);
  }
}
