import 'dart:io';

import 'package:dio/dio.dart';
import 'package:notchpeek/core/network/errors/api_response.dart'
    show ApiResponse;

class ApiErrorHandler {
  /// Handles Dio transport-level errors (timeouts, network, bad HTTP status).
  static ApiResponse<T> handleDioError<T>(
    DioException error, {
    String fallbackMessage = 'Something went wrong',
  }) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return ApiResponse.error(
          message: 'Request timed out. Please try again.',
          statusCode: 504,
        );

      case DioExceptionType.connectionError:
        return ApiResponse.error(
          message: 'No internet connection. Please check your network.',
          statusCode: 503,
        );

      case DioExceptionType.badResponse:
        return _handleBadResponse<T>(error);

      case DioExceptionType.cancel:
        return ApiResponse.error(
          message: 'Request was cancelled.',
          statusCode: 0,
        );

      case DioExceptionType.unknown:
      default:
        // SocketException surfaces here on Android
        if (error.error is SocketException) {
          return ApiResponse.error(
            message: 'No internet connection. Please check your network.',
            statusCode: 503,
          );
        }
        return ApiResponse.error(message: fallbackMessage, statusCode: 500);
    }
  }

  static ApiResponse<T> _handleBadResponse<T>(DioException error) {
    final statusCode = error.response?.statusCode ?? 500;

    switch (statusCode) {
      case 401:
        return ApiResponse.error(message: 'Not authorized.', statusCode: 401);
      case 403:
        return ApiResponse.error(
          message: "You don't have permission to perform this action.",
          statusCode: 403,
        );
      case 404:
        return ApiResponse.error(
          message: 'Resource not found.',
          statusCode: 404,
        );
      case 413:
        return ApiResponse.error(
          message: 'File too large. Maximum allowed size is 5MB.',
          statusCode: 413,
        );
      case 429:
        return ApiResponse.error(
          message: 'Too many requests. Please try again later.',
          statusCode: 429,
        );
      case 502:
      case 503:
      case 504:
        return ApiResponse.error(
          message:
              'Server is currently undergoing maintenance. Please try again in a few moments.',
          statusCode: statusCode,
        );
      default:
        if (statusCode >= 500) {
          return ApiResponse.error(
            message: 'Server error. Please try again later.',
            statusCode: statusCode,
          );
        }
        return ApiResponse.error(
          message:
              error.response?.data?.toString() ?? 'Unexpected error occurred.',
          statusCode: statusCode,
        );
    }
  }

  /// Handles GraphQL errors returned in the response body at HTTP 200.
  /// Shape: `{"errors": [{"message": "...", "extensions": {"code": "..."}}]}`
  static ApiResponse<T> handleGraphQLBodyErrors<T>(
    List<dynamic> errors, {
    String fallbackMessage = 'Something went wrong',
  }) {
    if (errors.isEmpty) {
      return ApiResponse.error(message: fallbackMessage, statusCode: 500);
    }

    final first = errors.first;
    if (first is! Map) {
      return ApiResponse.error(message: fallbackMessage, statusCode: 500);
    }

    final errorMap = first as Map<String, dynamic>;
    final rawMessage = errorMap['message']?.toString() ?? fallbackMessage;
    final extensions = errorMap['extensions'];
    final code = (extensions is Map)
        ? (extensions['code']?.toString().toUpperCase())
        : null;

    // Map code to status + user-friendly message
    switch (code) {
      case 'UNAUTHENTICATED':
      case 'UNAUTHORIZED':
        return ApiResponse.error(message: 'Not authorized.', statusCode: 401);
      case 'FORBIDDEN':
        return ApiResponse.error(
          message: "You don't have permission to perform this action.",
          statusCode: 403,
        );
      case 'NOT_FOUND':
        return ApiResponse.error(
          message: 'Resource not found.',
          statusCode: 404,
        );
      case 'BAD_REQUEST':
      case 'BAD_USER_INPUT':
      case 'VALIDATION_ERROR':
      case 'GRAPHQL_VALIDATION_FAILED':
        final detail = _extractValidationDetail(extensions);
        return ApiResponse.error(
          message: detail ?? rawMessage,
          statusCode: 400,
        );
      case 'RATE_LIMIT_EXCEEDED':
        return ApiResponse.error(
          message: 'Too many requests. Please try again later.',
          statusCode: 429,
        );
      case 'TIMEOUT':
        return ApiResponse.error(
          message: 'The request timed out. Please try again.',
          statusCode: 504,
        );
      case 'INTERNAL_SERVER_ERROR':
      case 'SERVER_ERROR':
        return ApiResponse.error(
          message: 'Server error. Please try again later.',
          statusCode: 500,
        );
      default:
        // Fall back to message-text pattern matching
        return _inferFromMessage<T>(rawMessage, fallbackMessage);
    }
  }

  /// Handles any non-Dio exception (parse errors, null checks, etc.)
  static ApiResponse<T> handleGenericError<T>(
    Object error, {
    String fallbackMessage = 'Something went wrong',
  }) {
    if (error is DioException) {
      return handleDioError<T>(error, fallbackMessage: fallbackMessage);
    }
    if (error is Exception) {
      return ApiResponse.error(
        message: error.toString().replaceAll('Exception: ', ''),
        statusCode: 500,
      );
    }
    return ApiResponse.error(message: fallbackMessage, statusCode: 500);
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  /// Extracts structured validation messages from GraphQL error extensions.
  /// Supports the `messages: [{ constraints: [...] }]` shape used by the backend.
  static String? _extractValidationDetail(dynamic extensions) {
    if (extensions is! Map) return null;

    final messages = extensions['messages'];
    if (messages is List && messages.isNotEmpty) {
      final constraints = <String>[];
      for (final msg in messages) {
        if (msg is Map && msg['constraints'] != null) {
          final c = msg['constraints'];
          if (c is List) constraints.addAll(c.map((e) => e.toString()));
        }
      }
      if (constraints.isNotEmpty) return constraints.join('\n');
    }

    return null;
  }

  static ApiResponse<T> _inferFromMessage<T>(
    String message,
    String fallbackMessage,
  ) {
    final lower = message.toLowerCase();
    if (lower.contains('unauthorized') ||
        lower.contains('unauthenticated') ||
        lower.contains('invalid token') ||
        lower.contains('token expired')) {
      return ApiResponse.error(message: 'Not authorized.', statusCode: 401);
    }
    if (lower.contains('not found')) {
      return ApiResponse.error(message: 'Resource not found.', statusCode: 404);
    }
    if (lower.contains('timeout') || lower.contains('timed out')) {
      return ApiResponse.error(
        message: 'The request timed out. Please try again.',
        statusCode: 504,
      );
    }
    if (lower.contains('network') || lower.contains('connection')) {
      return ApiResponse.error(
        message: 'Network error. Please check your internet connection.',
        statusCode: 503,
      );
    }
    return ApiResponse.error(
      message: message.isNotEmpty ? message : fallbackMessage,
      statusCode: 500,
    );
  }
}
