import 'package:flutter_test/flutter_test.dart';
import 'package:smart_monitor/models/cases_response.dart';
import 'package:smart_monitor/models/import_response.dart';
import 'package:smart_monitor/models/upload_response.dart';

/// A response as the service sends it: the payload under `data`, wrapped in
/// the envelope every endpoint shares.
Map<String, dynamic> _envelope(
  Object? data, {
  int code = 0,
  bool success = true,
  String message = 'Upload Successful',
  int count = 0,
}) => {
  'code': code,
  'message': message,
  'body': null,
  'success': success,
  'data': data,
  'count': count,
  'userName': null,
  'userCode': null,
  'branchName': null,
  'branchCode': null,
  'menu': null,
};

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

Map<String, dynamic> _caseRow() => {
  'client_id': '3332125',
  'customer_name': 'LEHRY INSTRUMENTATION AND VALVES PVT LTD',
  'account_no': '11424036',
  'line_no': '50301271033004',
  'status': 'Pending with CPU',
};

void main() {
  group('the response envelope', () {
    test('read-excel rows are read from data.rows', () {
      final res = UploadResponse.fromJson(
        _envelope({
          'rows': [_row(), _row()],
        }),
      );

      expect(res.rows, hasLength(2));
      expect(res.isSuccess, isTrue);
      expect(res.message, 'Upload Successful');
    });

    test('get-smartpointer rows are read from data.rows', () {
      final res = CasesResponse.fromJson(
        _envelope({
          'rows': [
            {..._row(), 'status': 'In Review'},
          ],
        }),
      );

      expect(res.cases, hasLength(1));
      expect(res.cases.single.status.label, 'In Review');
      expect(res.isSuccess, isTrue);
    });

    test('a failure reported on a 200 is still a failure', () {
      // The envelope carries the outcome, not the status line: `success` and
      // a non-zero `code` each mean the call was refused.
      final refused = _envelope(
        null,
        code: 1,
        success: false,
        message: 'The file is missing required column(s): CPU.',
      );

      expect(
        UploadResponse.fromJson(refused).failure,
        'The file is missing required column(s): CPU.',
      );
      expect(CasesResponse.fromJson(refused).isSuccess, isFalse);
      expect(
        UpdatedCasesResponse.fromJson(refused, sentCount: 3).isSuccess,
        isFalse,
      );
    });

    test('the envelope count of 0 does not claim rows were not read', () {
      // Regression: the service sends count: 0 alongside rows it plainly
      // returned, and the upload card reported "0 rows read" from it.
      final res = UploadResponse.fromJson(
        _envelope({
          'rows': [_row(), _row()],
        }),
      );

      // `count` is the field as the service stated it; `rowCount` is what the
      // card reports, so it can never claim a file was not read.
      expect(res.count, 0);
      expect(res.rowCount, 2);
    });

    test('sr_no and facility are read from the shape the service sends', () {
      final res = UploadResponse.fromJson(
        _envelope({
          'rows': [
            {..._row(), 'facility': 'Cash Credit', 'sr_no': 4},
          ],
        }),
      );

      final row = res.rows.single;
      expect(row.facility, 'Cash Credit');
      // A number on the wire, text in the model.
      expect(row.facilitySrNo, '4');
    });

    test('an unnumbered row reads as blank rather than serial 0', () {
      final res = UploadResponse.fromJson(
        _envelope({
          'rows': [
            {..._row(), 'sr_no': 0},
          ],
        }),
      );

      expect(res.rows.single.facilitySrNo, '');
    });

    test('the .NET minimum date reads as no date', () {
      final res = CasesResponse.fromJson(
        _envelope({
          'rows': [
            {..._row(), 'ls_srm_date': '0001-01-01'},
          ],
        }),
      );

      // Sent where a date was never set; taking it literally would put year 1
      // in front of the user.
      expect(res.cases.single.lsrmDate, isNull);
    });

    test('a plain rows body is still read, envelope or not', () {
      // The server this app talks to locally may be older than the envelope.
      expect(
        UploadResponse.fromJson({
          'rows': [_row()],
        }).rows,
        hasLength(1),
      );
      expect(CasesResponse.fromBody([_row()]).cases, hasLength(1));
    });
  });

  group('UploadResponse', () {
    test('reads the rows envelope and the count', () {
      final res = UploadResponse.fromJson({
        'count': 2,
        'rows': [_row(), _row()],
      });

      expect(res.count, 2);
      expect(res.rows, hasLength(2));
      expect(res.rows.first.clientId, '4943581');
      expect(res.isEmpty, isFalse);
    });

    test('resolves master-data values, leaving unknowns as the file wrote', () {
      final res = UploadResponse.fromJson({
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
      final res = UploadResponse.fromBody([_row()]);

      expect(res.rows, hasLength(1));
      // No count in the body, so the rows that arrived are what is reported.
      expect(res.rowCount, 1);
    });

    test('accepts the data and items envelopes', () {
      expect(
        UploadResponse.fromJson({
          'data': [_row()],
        }).rows,
        hasLength(1),
      );
      expect(
        UploadResponse.fromJson({
          'items': [_row()],
        }).rows,
        hasLength(1),
      );
    });

    test('numbers the rows when the server does not', () {
      final res = UploadResponse.fromJson({
        'rows': [_row(), _row(), _row()],
      });

      expect(res.rows.map((r) => r.id), [1, 2, 3]);
    });

    test('the id is the row position, never something the server sent', () {
      final res = UploadResponse.fromJson({
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
      final res = UploadResponse.fromJson({
        'rows': [
          {...row, 'actionable_team': 'Cam Renewal Team'},
        ],
      });

      expect(res.rows.single.actionableTeam, 'Cam Renewal Team');
    });

    test('spreadsheet stand-ins for empty do not become text', () {
      final res = UploadResponse.fromJson({
        'rows': [
          {..._row(), 'core_system': 'nan', 'segment': 'null'},
        ],
      });

      expect(res.rows.single.coreSystem, '');
      expect(res.rows.single.segment, '');
    });

    test('an unusable body reads as empty rather than throwing', () {
      expect(UploadResponse.fromBody(null).isEmpty, isTrue);
      expect(UploadResponse.fromBody('nope').isEmpty, isTrue);
      expect(UploadResponse.fromJson({'rows': <dynamic>[]}).isEmpty, true);
    });

    test('toOutcome hands the screen a fresh, editable outcome', () {
      final res = UploadResponse.fromJson({
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
    test('reads the row count from the data integer', () {
      // What a server that has not been updated answers with: a bare number
      // instead of the rows object. Still read, and still reports the total.
      final res = UpdatedCasesResponse.fromJson(
        _envelope(3, message: 'Updated Successfully'),
        sentCount: 3,
      );

      expect(res.updatedCount, 3);
      expect(res.total, 3);
      expect(res.message, 'Updated Successfully');
      expect(res.isSuccess, isTrue);
    });

    test('reads the stored rows the server echoes back', () {
      final res = UpdatedCasesResponse.fromJson(
        _envelope({
          'rows': [
            {..._row(), 'sr_no': '1', 'status': 'Pending with CPU'},
            {..._row(cpu: 'Chennai'), 'line_no': '6', 'status': 'Verified'},
          ],
          'inserted': 1,
          'updated': 1,
          'total': 2,
        }, message: 'Updated Successfully'),
        sentCount: 2,
      );

      expect(res.total, 2);
      expect(res.hasRows, isTrue);
      expect(res.rows, hasLength(2));
      expect(res.rows.first.clientId, '4943581');
      expect(res.rows.first.srNo, '1');
      // The status the store settled on, which is the reason for echoing at
      // all — the submit that wrote the second row did not state one.
      expect(res.rows.last.status, 'Verified');
      expect(res.rows.last.cpu, 'Chennai');
    });

    test(
      'a count-only response leaves the rows empty rather than guessing',
      () {
        final res = UpdatedCasesResponse.fromJson(
          _envelope(3, message: 'Updated Successfully'),
          sentCount: 3,
        );

        expect(res.hasRows, isFalse);
        expect(res.rows, isEmpty);
      },
    );

    test('falls back to what was sent when the server reports nothing', () {
      final res = UpdatedCasesResponse.fromJson(null, sentCount: 7);

      // The rows were written; claiming zero would be worse than trusting
      // what went out.
      expect(res.updatedCount, isNull);
      expect(res.total, 7);
    });

    test('a count arriving as a string is still read', () {
      final res = UpdatedCasesResponse.fromJson(
        _envelope('5', message: 'Updated Successfully'),
        sentCount: 7,
      );

      expect(res.total, 5);
    });

    test('a server reporting zero is believed', () {
      final res = UpdatedCasesResponse.fromJson(
        _envelope(0, message: 'Updated Successfully'),
        sentCount: 7,
      );

      // Distinct from reporting nothing: 0 means nothing was written.
      expect(res.total, 0);
    });

    test('the older inserted/updated object is still read', () {
      final res = UpdatedCasesResponse.fromJson({
        'inserted': 11,
        'updated': 3,
      }, sentCount: 14);

      // Regression: a missing total used to read as zero and claim nothing
      // had been imported.
      expect(res.total, 14);
    });

    group('summary', () {
      test('states the total on a clean import', () {
        const res = UpdatedCasesResponse(sentCount: 11, updatedCount: 11);

        expect(res.summary(), '11 case(s) imported');
      });

      test('mentions rows left behind in the report', () {
        const res = UpdatedCasesResponse(sentCount: 11, updatedCount: 11);

        expect(
          res.summary(unresolved: 2),
          '11 case(s) imported · 2 left unresolved',
        );
      });
    });
  });

  group('envelope reading', () {
    Map<String, dynamic> envelope({
      Object? success,
      Object? code,
      String message = 'Upload Successful',
      Object? data,
    }) => {
      'code': code,
      'message': message,
      'body': null,
      'success': success,
      'data': data,
      'count': 0,
      'userName': null,
      'menu': null,
    };

    test('an explicit success outranks a non-zero code', () {
      // Regression: a gateway answering `success: true` with an HTTP-style
      // code of 200 was read as a failure, and its rows thrown away.
      final res = CasesResponse.fromJson(
        envelope(
          success: true,
          code: 200,
          message: 'OK',
          data: {
            'rows': [_caseRow()],
          },
        ),
      );

      expect(res.isSuccess, isTrue);
      expect(res.failure, isNull);
      expect(res.cases, hasLength(1));
    });

    test('code decides only when success is absent', () {
      final failed = CasesResponse.fromJson(
        envelope(code: 1, message: 'Session expired'),
      );
      final fine = CasesResponse.fromJson(
        envelope(
          code: 0,
          data: {
            'rows': [_caseRow()],
          },
        ),
      );

      expect(failed.failure, 'Session expired');
      expect(fine.isSuccess, isTrue);
    });

    test('success false is a failure whatever the code says', () {
      final res = CasesResponse.fromJson(
        envelope(success: false, code: 0, message: 'Not authorised'),
      );

      expect(res.failure, 'Not authorised');
    });

    test('a text body is a failure, not an empty result', () {
      // Regression: a gateway's plain-text error page read as "success with
      // zero rows", so the dashboard showed an empty grid saying nothing.
      final res = CasesResponse.fromBody('Service Unavailable');

      expect(res.isSuccess, isFalse);
      expect(res.failure, 'Service Unavailable');
    });

    test('an empty body is a failure, not an empty result', () {
      final res = CasesResponse.fromBody(null);

      expect(res.isSuccess, isFalse);
      expect(res.failure, contains('empty response'));
    });

    test('a genuinely empty result set is still a success', () {
      // Nothing stored yet is the grid's empty state, not an error.
      final res = CasesResponse.fromJson(
        envelope(success: true, code: 0, data: {'rows': <dynamic>[]}),
      );

      expect(res.isSuccess, isTrue);
      expect(res.isEmpty, isTrue);
    });

    test('a stated count never exceeds the rows that arrived', () {
      final res = CasesResponse.fromJson(
        envelope(
          success: true,
          code: 0,
          data: {
            'rows': [_caseRow()],
          },
        )..['count'] = 50,
      );

      // `count` is the field as the service stated it — it says 50 here,
      // and 0 on responses plainly carrying rows, so nothing counts with it.
      expect(res.count, 50);
      // What the grid's footer reads, so it never claims records it cannot
      // show.
      expect(res.rowCount, 1);
    });
  });
}
