enum ApiMethod {
  delete(value: "DELETE"),
  getr(value: "GET"),
  patch(value: "PATCH"),
  post(value: "POST"),
  put(value: "PUT");

  final String value;
  const ApiMethod({required this.value});

  /// Strict version (throws if not found)
  static ApiMethod fromValue(String method) {
    return ApiMethod.values.firstWhere(
      (e) => e.value.toUpperCase() == method.toUpperCase(),
      orElse: () => throw ArgumentError('Invalid ApiMethod value: $method'),
    );
  }
}
