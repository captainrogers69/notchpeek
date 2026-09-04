/// Base exception class
class AppException implements Exception {
  final String message;
  final int? statusCode;

  AppException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

// Legacy exception classes (for backward compatibility)
class AppServerException extends AppException {
  AppServerException(super.message) : super(statusCode: 500);
}

class AppNetworkException extends AppException {
  AppNetworkException(super.message) : super(statusCode: 503);
}

class AppCacheException extends AppException {
  AppCacheException(super.message) : super(statusCode: 500);
}

class AppAuthException extends AppException {
  AppAuthException(super.message) : super(statusCode: 401);
}

class AppValidationException extends AppException {
  AppValidationException(super.message) : super(statusCode: 400);
}

// New cleaner exception classes (recommended for new code)
class UnauthorizedException extends AppException {
  UnauthorizedException([super.message = 'Unauthorized'])
      : super(statusCode: 401);
}

class NotFoundException extends AppException {
  NotFoundException([super.message = 'Resource not found'])
      : super(statusCode: 404);
}

class ValidationException extends AppException {
  ValidationException([super.message = 'Validation failed'])
      : super(statusCode: 400);
}

class ServerException extends AppException {
  ServerException([super.message = 'Server error']) : super(statusCode: 500);
}

class NetworkException extends AppException {
  NetworkException([super.message = 'Network error']) : super(statusCode: 503);
}
