import 'package:dio/dio.dart';
import 'package:notchpeek/core/logging/notch_logger.dart';

/// Debug-only request logging for the one endpoint this app has.
///
/// Deliberately logs **shapes, not values**: the artwork search term is the
/// user's track and album, and the response body is somebody's listening
/// history. Playbook §6 says log ids, counts and states — so that is what
/// crosses, even though the endpoint itself is public.
class ApiLogInterceptor extends Interceptor {
  ApiLogInterceptor() : logger = NotchLogger.forTag('ApiLogInterceptor');

  final NotchLogger logger;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final keys = options.queryParameters.keys.join(', ');
    logger.debug(
      '${options.method} ${options.path}${keys.isEmpty ? '' : ' ?$keys'}',
    );
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final data = response.data;
    final count = data is Map ? data['resultCount'] : null;
    logger.success(
      '${response.statusCode} ${response.requestOptions.path}'
      '${count == null ? '' : ' ($count results)'}',
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    logger.error(
      '${err.response?.statusCode ?? '-'} ${err.requestOptions.path} '
      '(${err.type.name})',
      error: err.message,
    );
    handler.next(err);
  }
}
