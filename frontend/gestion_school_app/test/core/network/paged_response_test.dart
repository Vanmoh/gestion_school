import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/core/network/paged_response.dart';

/// Adaptateur qui sert des pages preparees, et retient ce qui lui a ete demande.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.pages);

  /// url -> corps JSON renvoye.
  final Map<String, Map<String, dynamic>> pages;
  final List<String> requested = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final url = options.uri.toString();
    requested.add(url);
    final body = pages[url];
    if (body == null) {
      return ResponseBody.fromString('{"detail":"absent"}', 404, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      });
    }
    return ResponseBody.fromString(jsonEncode(body), 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

Response<dynamic> _envelope(
  Dio dio, {
  required List<dynamic> results,
  String? next,
  Map<String, dynamic>? query,
  String path = '/classrooms/',
}) {
  return Response<dynamic>(
    requestOptions: RequestOptions(
      path: path,
      baseUrl: 'https://api.test',
      queryParameters: query ?? const {},
    ),
    data: {'count': 999, 'next': next, 'previous': null, 'results': results},
  );
}

void main() {
  late _FakeAdapter adapter;
  late Dio dio;

  setUp(() {
    adapter = _FakeAdapter({
      'https://api.test/classrooms/?page=2': {
        'count': 999,
        'next': 'https://api.test/classrooms/?page=3',
        'previous': null,
        'results': ['b1', 'b2'],
      },
      'https://api.test/classrooms/?page=3': {
        'count': 999,
        'next': null,
        'previous': null,
        'results': ['c1'],
      },
    });
    dio = Dio(BaseOptions(baseUrl: 'https://api.test'))
      ..httpClientAdapter = adapter;
  });

  test('recolle toutes les pages quand l_appelant n_en demande aucune', () async {
    final merged = await followRemainingPages(
      dio,
      _envelope(
        dio,
        results: ['a1', 'a2'],
        next: 'https://api.test/classrooms/?page=2',
      ),
    );

    final data = merged.data as Map;
    expect(data['results'], ['a1', 'a2', 'b1', 'b2', 'c1']);
    expect(data['next'], isNull, reason: 'la liste est complete');
    expect(adapter.requested, [
      'https://api.test/classrooms/?page=2',
      'https://api.test/classrooms/?page=3',
    ]);
  });

  test('ne touche a rien quand l_appelant pagine lui-meme', () async {
    final merged = await followRemainingPages(
      dio,
      _envelope(
        dio,
        results: ['a1'],
        next: 'https://api.test/classrooms/?page=2',
        query: {'page': 1, 'page_size': 100},
      ),
    );

    expect((merged.data as Map)['results'], ['a1']);
    expect(adapter.requested, isEmpty, reason: 'aucune page supplementaire');
  });

  test('reconnait aussi la pagination inscrite dans le chemin', () async {
    final merged = await followRemainingPages(
      dio,
      _envelope(
        dio,
        results: ['a1'],
        next: 'https://api.test/classrooms/?page=2',
        path: '/classrooms/?page=1',
      ),
    );

    expect((merged.data as Map)['results'], ['a1']);
    expect(adapter.requested, isEmpty);
  });

  test('une page suivante en echec laisse next renseigne', () async {
    final merged = await followRemainingPages(
      dio,
      _envelope(
        dio,
        results: ['a1'],
        next: 'https://api.test/classrooms/?page=inconnue',
      ),
    );

    final data = merged.data as Map;
    expect(data['results'], ['a1'], reason: 'les donnees deja obtenues restent');
    expect(
      data['next'],
      'https://api.test/classrooms/?page=inconnue',
      reason: 'la liste est incomplete et doit rester reconnaissable comme telle',
    );
  });

  test('une reponse non paginee traverse sans modification', () async {
    final response = Response<dynamic>(
      requestOptions: RequestOptions(path: '/permissions/'),
      data: {'role': 'censor', 'modules': {}},
    );

    final merged = await followRemainingPages(dio, response);

    expect(merged.data, {'role': 'censor', 'modules': {}});
    expect(adapter.requested, isEmpty);
  });

  test('une liste brute traverse sans modification', () async {
    final response = Response<dynamic>(
      requestOptions: RequestOptions(path: '/etablissements/'),
      data: ['a', 'b'],
    );

    final merged = await followRemainingPages(dio, response);

    expect(merged.data, ['a', 'b']);
    expect(adapter.requested, isEmpty);
  });
}
