// The master lists, from the wire to the cache the screens read.
//
// Five lists arrive in one response and land in a static holder every screen
// reads synchronously — the dropdowns in the case drawer, and the validation
// behind the upload table. What matters here is that a bad response leaves the
// cache alone rather than half-filling it: a dropdown that lost its options
// mid-session is worse than one that never had them, because the user has
// already seen it working.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smart_monitor/core/api_client.dart';
import 'package:smart_monitor/data/master_data.dart';
import 'package:smart_monitor/models/master_data_response.dart';
import 'package:smart_monitor/services/case_api.dart';

import 'master_data_fixture.dart';

late List<http.BaseRequest> _sent;

Api _api(http.Response Function(http.Request request) respond) => Api(
  ApiClient(
    baseUrl: 'https://example.test/api',
    client: MockClient((request) async {
      _sent.add(request);
      return respond(request);
    }),
  ),
);

http.Response _ok(Object? data) => http.Response(
  jsonEncode({
    'code': 0,
    'message': 'Master Data Loaded',
    'body': null,
    'success': true,
    'data': data,
    'count': 0,
  }),
  200,
  headers: {'content-type': 'application/json'},
);

void main() {
  setUp(() => _sent = []);
  tearDown(MasterData.reset);

  group('GET /getMasterData', () {
    test('reads all five lists', () async {
      final response =
          await _api((_) => _ok(masterDataPayload)).fetchMasterData();

      expect(response.isSuccess, isTrue);
      expect(response.cpus, masterCpus);
      expect(response.teams, masterTeams);
      expect(response.exceptionCategories, masterExceptionCategories);
      expect(response.healthCheckCategories, masterHealthCheckCategories);
      expect(response.reassignReasons, masterReassignReasons);
    });

    test('asks with no parameters', () async {
      await _api((_) => _ok(masterDataPayload)).fetchMasterData();

      // The lists do not depend on who is asking, so nothing narrows them.
      expect(_sent.single.method, 'GET');
      expect(_sent.single.url.path, '/api/getMasterData');
      expect(_sent.single.url.queryParameters, isEmpty);
    });

    test('a missing key is an empty list, not a crash', () async {
      final response =
          await _api(
            (_) => _ok({'cpus': masterCpus, 'teams': masterTeams}),
          ).fetchMasterData();

      expect(response.cpus, masterCpus);
      // The three the payload never mentioned.
      expect(response.exceptionCategories, isEmpty);
      expect(response.healthCheckCategories, isEmpty);
      expect(response.reassignReasons, isEmpty);
      expect(response.isEmpty, isFalse);
    });

    test('blanks and nulls are dropped rather than offered', () async {
      // An empty entry in a dropdown is something a user can pick by accident.
      final response =
          await _api(
            (_) => _ok({
              'cpus': ['Chennai', '', '  ', null, 'Mumbai'],
            }),
          ).fetchMasterData();

      expect(response.cpus, ['Chennai', 'Mumbai']);
    });

    test('non-string entries are read as their text', () async {
      final response =
          await _api((_) => _ok({'cpus': [1, 'Chennai']})).fetchMasterData();

      expect(response.cpus, ['1', 'Chennai']);
    });

    test('a failure reported on a 200 still throws', () async {
      // The envelope, not the status line, is what reports a refusal here.
      final call =
          _api(
            (_) => http.Response(
              jsonEncode({
                'code': 1,
                'message': 'Master data is unavailable.',
                'success': false,
                'data': null,
              }),
              200,
              headers: {'content-type': 'application/json'},
            ),
          ).fetchMasterData();

      await expectLater(
        call,
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            'Master data is unavailable.',
          ),
        ),
      );
    });

    test('a 500 throws', () async {
      await expectLater(
        _api((_) => http.Response('nope', 500)).fetchMasterData(),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('MasterData cache', () {
    test('starts empty, so nothing is offered before the call lands', () {
      // The lists are not bundled: a dropdown showing options the server never
      // sent would let a user pick a CPU that does not exist.
      expect(MasterData.isLoaded, isFalse);
      expect(MasterData.cpus, isEmpty);
      expect(MasterData.teams, isEmpty);
      expect(MasterData.exceptionCategories, isEmpty);
      expect(MasterData.healthCheckCategories, isEmpty);
      expect(MasterData.reassignReasons, isEmpty);
    });

    test('applying a response fills it', () async {
      MasterData.apply(
        await _api((_) => _ok(masterDataPayload)).fetchMasterData(),
      );

      expect(MasterData.isLoaded, isTrue);
      expect(MasterData.cpus, masterCpus);
      expect(MasterData.reassignReasons, masterReassignReasons);
    });

    test('an empty response does not blank what is already loaded', () {
      seedMasterData();

      // A refresh that came back with nothing must not take the working lists
      // away — the user has been picking from them all session.
      MasterData.apply(const MasterDataResponse());

      expect(MasterData.cpus, masterCpus);
      expect(MasterData.isLoaded, isTrue);
    });

    test('an empty response on a cold cache leaves it unloaded', () {
      MasterData.apply(const MasterDataResponse());

      // Not loaded rather than loaded-and-empty: the caller shows a warning
      // for the first and says nothing for a genuinely empty master list.
      expect(MasterData.isLoaded, isFalse);
      expect(MasterData.cpus, isEmpty);
    });

    test('reset empties it for the next session', () {
      seedMasterData();
      MasterData.reset();

      expect(MasterData.isLoaded, isFalse);
      expect(MasterData.cpus, isEmpty);
    });
  });
}
