/// Standardized API Response structure
class ApiResponse<T> {
  final bool status;
  final String message;
  final T? data;
  final int? statusCode;

  ApiResponse({
    required this.status,
    required this.message,
    this.data,
    this.statusCode,
  });

  factory ApiResponse.success({required String message, T? data}) {
    return ApiResponse(
      status: true,
      message: message,
      data: data,
      statusCode: 200,
    );
  }

  factory ApiResponse.error({required String message, int? statusCode}) {
    return ApiResponse(
      status: false,
      message: message,
      data: null,
      statusCode: statusCode ?? 500,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'status': status,
      'message': message,
      'data': data,
      'statusCode': statusCode,
    };
  }
}
