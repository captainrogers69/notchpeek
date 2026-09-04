import 'dart:convert';

// import 'dart:developer';

import 'package:dio/dio.dart';
import 'package:gohomes/utils/helpers/app_logger.dart';

class _ApiConfiguration {
  // static const Duration timeout = Duration(seconds: 60);
  static const logRequest = true;
  static const logRequestHeader = false;
  static const logRequestBody = false;
  static const logResponseHeader = false;
  static const logResponseBody = true;
  // static const logGetPresignedUrlRequest = false;
  // static const logGetPresignedUrlResponse = true;
  static const logError = true;
}

/* final apiLogInterceptorProvider = Provider<_ApiLogInterceptor>((ref) {
  return _ApiLogInterceptor();
}); */

class ApiLogInterceptor extends Interceptor {
  final AppLogger logger;
  ApiLogInterceptor() : logger = AppLogger.forTag('ApiLogInterceptor');

  String _cURLRepresentation(RequestOptions options) {
    final components = <String>["curl -i"];

    components.add("-X ${options.method}");

    options.headers.forEach((k, v) {
      if (k.toLowerCase() != "cookie" &&
          k.toLowerCase() != 'x-api-key' &&
          k.toLowerCase() != 'x-device-id' &&
          k.toLowerCase() != 'x-fingerprint' &&
          k.toLowerCase() != 'authorization') {
        components.add('-H "$k: $v"');
      }
    });

    if (options.data != null) {
      if (options.data is FormData) {
        final formData = options.data as FormData;
        final fields =
            formData.fields.map((e) => '"${e.key}": "${e.value}"').join(',');
        components.add('-d "{$fields}"');
      } else {
        final jsonData = json.encode(options.data);
        components.add("-d '$jsonData'");
      }
    }

    components.add('"${options.uri}"');

    return components.join(' \\\n\t');
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (_ApiConfiguration.logRequest) {
      if (!options.data.toString().contains('Get_Presigned_Url')) {
        logger.debug(_cURLRepresentation(options));
      } /*  else {
        logger.debug("Skipped Get_Presigned_Url");
      } */

      if (_ApiConfiguration.logRequestHeader) {
        // !TO be kept hidden
        logger.debug("Headers: ${options.headers}");
      }

      if (_ApiConfiguration.logRequestBody && options.data != null) {
        logger.debug("Body: ${options.data}");
      }
    }

    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (_ApiConfiguration.logResponseHeader) {
      logger.debug("Response Headers: ${response.headers}");
    }

    if (_ApiConfiguration.logResponseBody) {
      //  if (!response.data.toString().contains('Get_Presigned_Url')) {
      logger.success("Response{${response.statusCode}}:: ${response.data}");
      // } else {
      //   logger.debug("Skipped Get_Presigned_Url Response");
      // }
    }

    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (_ApiConfiguration.logError) {
      logger.error(
          "Error{${err.response?.statusCode}}: URI: ${err.requestOptions.uri.toString().trim()}\n Type: ${err.type.toString().trim()}\n Message: ${err.message.toString().trim()}\n error data:${err.response?.data.toString().trim()}");
    }

    handler.next(err);
  }
}
