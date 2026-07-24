import 'dart:convert';
import 'dart:io';

import 'package:arth/services/server_api_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bodyless DELETE does not claim to contain JSON', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    final handled = server.first.then((request) async {
      expect(request.method, 'DELETE');
      expect(request.headers.contentType, isNull);
      expect(await utf8.decoder.bind(request).join(), isEmpty);
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
    });
    final api = ServerApiService(
      baseUrl: 'http://${server.address.host}:${server.port}',
    );

    await api.delete('/documents/test', bearerToken: 'token');
    await handled;
  });

  test('bodyless POST does not claim to contain JSON', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    final handled = server.first.then((request) async {
      expect(request.method, 'POST');
      expect(request.headers.contentType, isNull);
      expect(await utf8.decoder.bind(request).join(), isEmpty);
      request.response.headers.contentType = ContentType.json;
      request.response.write('{"ok":true}');
      await request.response.close();
    });
    final api = ServerApiService(
      baseUrl: 'http://${server.address.host}:${server.port}',
    );

    expect(await api.postJson('/documents/test/confirm'), {'ok': true});
    await handled;
  });

  test('multipart uploads use a fixed length and preserve UTF-8 OCR', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    const ocrText = 'वेतन PAYSLIP ₹ 58,443';
    final handled = server.first.then((request) async {
      expect(request.method, 'POST');
      expect(request.headers.contentLength, greaterThan(0));
      expect(request.headers.value(HttpHeaders.transferEncodingHeader), isNull);
      final body = await request.fold<List<int>>(
        <int>[],
        (buffer, chunk) => buffer..addAll(chunk),
      );
      expect(utf8.decode(body), contains(ocrText));
      request.response.headers.contentType = ContentType.json;
      request.response.write('{"document":{"id":"test"}}');
      await request.response.close();
    });
    final api = ServerApiService(
      baseUrl: 'http://${server.address.host}:${server.port}',
    );

    final response = await api.uploadMultipart(
      '/documents',
      bearerToken: 'token',
      fields: const {'documentType': 'payslip', 'ocrText': ocrText},
      fieldName: 'file',
      filename: 'payslip.jpg',
      contentType: 'image/jpeg',
      bytes: const [1, 2, 3],
    );

    expect(response['document'], {'id': 'test'});
    await handled;
  });
}
