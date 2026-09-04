import 'package:equatable/equatable.dart';

// Failures represent errors at the domain/use case level
abstract class Failure extends Equatable {
  final String message;
  const Failure(this.message);

  @override
  List<Object?> get props => [message];
}

// Server-related failures (API errors, 5xx errors)
class ServerFailure extends Failure {
  const ServerFailure([super.message = 'Server error occurred']);
}

// Network-related failures (no internet, timeout)
class NetworkFailure extends Failure {
  const NetworkFailure([
    super.message = 'Network error. Please check your connection',
  ]);
}

// Cache-related failures (local storage errors)
class CacheFailure extends Failure {
  const CacheFailure([super.message = 'Cache error occurred']);
}

// Validation failures (invalid input)
class ValidationFailure extends Failure {
  const ValidationFailure(super.message);
}

// Authentication failures (unauthorized, token expired)
class AuthFailure extends Failure {
  const AuthFailure([super.message = 'Authentication failed']);
}

// General failures (unknown errors)
class GeneralFailure extends Failure {
  const GeneralFailure([super.message = 'An error occurred']);
}
