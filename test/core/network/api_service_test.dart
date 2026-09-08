import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notchpeek/core/network/endpoints/api_endpoints.dart';
import 'package:notchpeek/core/services/api_service.dart';

/// Answers every request from a canned map. Keeps the test off the network.
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.statusCode, this.body);

  final int statusCode;
  final String body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      body,
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test(
    'a 200 with a JSON body comes back as a successful ApiResponse',
    () async {
      final service = ApiService(baseUrl: ApiEndpoint.itunesBaseUrl);
      service.debugAdapter = _StubAdapter(
        200,
        '{"resultCount":1,"results":[{"artworkUrl100":"https://x/a.jpg"}]}',
      );

      final result = await service.get(
        ApiEndpoint.search,
        queryParameters: {'term': 'x'},
      );

      expect(result.status, isTrue);
      expect(result.statusCode, 200);
      expect((result.data!['results'] as List), hasLength(1));
    },
  );

  test(
    'a transport failure comes back as an error ApiResponse, never a throw',
    () async {
      final service = ApiService(baseUrl: ApiEndpoint.itunesBaseUrl);
      service.debugAdapter = _StubAdapter(503, '');

      final result = await service.get(ApiEndpoint.search);

      expect(result.status, isFalse);
      expect(result.message, isNotEmpty);
    },
  );

  test('the iTunes lookup path is a constant, not a literal', () {
    expect(ApiEndpoint.itunesBaseUrl, 'https://itunes.apple.com');
    expect(ApiEndpoint.search, '/search');
  });
}
