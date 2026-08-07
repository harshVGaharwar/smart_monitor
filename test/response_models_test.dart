import 'package:flutter_test/flutter_test.dart';
import 'package:smart_monitor/models/import_response.dart';
import 'package:smart_monitor/models/upload_response.dart';

Map<String, dynamic> _row({
  String cpu = 'Mumbai',
  String team = 'Cam Renewal Team',
  String category = 'CAM Expiry Health Check',
}) => {
  'client_id': '4943581',
  'customer_name': 'ACME',
  'account_no': '50200031339584',
  'line_no': '5',
  'health_check_category': category,
  'sub_category': 'Sub',
  'support_system': 'LMM',
  'core_system': 'FC',
  'segment': 'Retail',
  'facility_sr_no': '1',
  'maker': 'mk',
  'checker': 'ck',
  'ls_srm_date': '2026-07-21',
  'exception_category': 'Exception',
  'reason': 'Renewal pending',
  'cpu': cpu,
  'team': team,
};

void main() {
  group('UploadCasesResponse', () {
    test('reads the rows envelope and the count', () {
      final res = UploadCasesResponse.fromJson({
        'count': 2,
        'rows': [_row(), _row()],
      });

      expect(res.count, 2);
      expect(res.rows, hasLength(2));
      expect(res.rows.first.clientId, '4943581');
      expect(res.isEmpty, isFalse);
    });

    test('resolves master-data values, leaving unknowns as the file wrote', () {
      final res = UploadCasesResponse.fromJson({
        'rows': [_row(cpu: 'mumbai', team: 'Atlantis Team')],
      });

      final row = res.rows.single;
      // Case and punctuation are ignored, and the master spelling wins.
      expect(row.cpu, 'Mumbai');
      // Unrecognised: null, with the file's text kept for the report.
      expect(row.actionableTeam, isNull);
      expect(row.teamRaw, 'Atlantis Team');
      expect(row.hasErrors, isTrue);
      expect(row.errorFields, contains('Actionable Team'));
    });

    test('accepts a bare array as well as the envelope', () {
      final res = UploadCasesResponse.fromJson([_row()]);

      expect(res.rows, hasLength(1));
      // No count in the body, so it falls back to what was parsed.
      expect(res.count, 1);
    });

    test('accepts the data and items envelopes', () {
      expect(
        UploadCasesResponse.fromJson({
          'data': [_row()],
        }).rows,
        hasLength(1),
      );
      expect(
        UploadCasesResponse.fromJson({
          'items': [_row()],
        }).rows,
        hasLength(1),
      );
    });

    test('numbers the rows when the server does not', () {
      final res = UploadCasesResponse.fromJson({
        'rows': [_row(), _row(), _row()],
      });

      expect(res.rows.map((r) => r.id), [1, 2, 3]);
    });

    test('the id is the row position, never something the server sent', () {
      final res = UploadCasesResponse.fromJson({
        'rows': [
          {..._row(), 'id': 47},
          _row(),
        ],
      });

      // Display numbering only. A case is identified by client id / account
      // no / line no, so a stray id in the response is ignored rather than
      // becoming an identity the app might act on.
      expect(res.rows.map((r) => r.id), [1, 2]);
    });

    test('still reads the old actionable_team spelling', () {
      final row = _row()..remove('team');
      final res = UploadCasesResponse.fromJson({
        'rows': [
          {...row, 'actionable_team': 'Cam Renewal Team'},
        ],
      });

      expect(res.rows.single.actionableTeam, 'Cam Renewal Team');
    });

    test('spreadsheet stand-ins for empty do not become text', () {
      final res = UploadCasesResponse.fromJson({
        'rows': [
          {..._row(), 'core_system': 'nan', 'segment': 'null'},
        ],
      });

      expect(res.rows.single.coreSystem, '');
      expect(res.rows.single.segment, '');
    });

    test('an unusable body reads as empty rather than throwing', () {
      expect(UploadCasesResponse.fromJson(null).isEmpty, isTrue);
      expect(UploadCasesResponse.fromJson('nope').isEmpty, isTrue);
      expect(UploadCasesResponse.fromJson({'rows': <dynamic>[]}).isEmpty, true);
    });

    test('toOutcome hands the screen a fresh, editable outcome', () {
      final res = UploadCasesResponse.fromJson({
        'rows': [_row(), _row(team: 'Ghost Team')],
      });

      final outcome = res.toOutcome();
      expect(outcome.processed, 2);
      expect(outcome.uploaded, 1);
      expect(outcome.failed, hasLength(1));
      // Separate outcomes, so one screen's removals cannot touch another's.
      expect(res.toOutcome(), isNot(same(outcome)));
    });
  });

  group('ImportCasesResponse', () {
    test('reads the counts the server reported', () {
      final res = ImportCasesResponse.fromJson({
        'inserted': 11,
        'updated': 3,
        'total': 14,
      }, sentCount: 14);

      expect(res.inserted, 11);
      expect(res.updated, 3);
      expect(res.total, 14);
      expect(res.hasUpdates, isTrue);
    });

    test('sums a total the server left out', () {
      final res = ImportCasesResponse.fromJson({
        'inserted': 11,
        'updated': 3,
      }, sentCount: 14);

      // Regression: a missing total used to read as zero and claim nothing
      // had been imported.
      expect(res.total, 14);
    });

    test('falls back to what was sent when the server reports nothing', () {
      final res = ImportCasesResponse.fromJson(null, sentCount: 7);

      expect(res.total, 7);
      expect(res.inserted, 7);
    });

    test('numbers arriving as strings are still read', () {
      final res = ImportCasesResponse.fromJson({
        'inserted': '5',
        'updated': '2',
      }, sentCount: 7);

      expect(res.total, 7);
    });

    group('summary', () {
      test('states the total on a clean import', () {
        final res = ImportCasesResponse(inserted: 11, updated: 0);

        expect(res.summary(), '11 case(s) imported');
      });

      test('calls out overwrites, since a silent replace surprises', () {
        final res = ImportCasesResponse(inserted: 8, updated: 3);

        expect(res.summary(), '11 case(s) imported · 3 updated');
      });

      test('mentions rows left behind in the report', () {
        final res = ImportCasesResponse(inserted: 11, updated: 0);

        expect(
          res.summary(unresolved: 2),
          '11 case(s) imported · 2 left unresolved',
        );
      });
    });
  });
}
