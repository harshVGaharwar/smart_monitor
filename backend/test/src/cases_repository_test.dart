import 'package:backend/src/cases_repository.dart';
import 'package:test/test.dart';

Map<String, dynamic> _row({
  String clientId = '4943581',
  String accountNo = '50200031339584',
  String lineNo = '5',
  String customerName = 'ACME',
  String cpu = 'Mumbai',
  String team = 'Cam Renewal Team',
  String reason = 'Renewal pending',
}) => {
  'client_id': clientId,
  'customer_name': customerName,
  'account_no': accountNo,
  'line_no': lineNo,
  'health_check_category': 'CAM Expiry Health Check',
  'sub_category': 'Sub',
  'support_system': 'LMM',
  'core_system': 'FC',
  'segment': 'Retail',
  'facility_sr_no': '1',
  'maker': 'mk',
  'checker': 'ck',
  'ls_srm_date': '2026-07-21',
  'exception_category': 'Exception',
  'reason': reason,
  'cpu': cpu,
  'team': team,
};

void main() {
  late CasesRepository repo;

  setUp(() => repo = CasesRepository(':memory:'));
  tearDown(() => repo.close());

  group('CasesRepository', () {
    test('stores the rows it is given', () {
      final result = repo.importRows([_row(), _row(lineNo: '6')]);

      expect(result.inserted, 2);
      expect(result.updated, 0);
      expect(result.total, 2);
      expect(repo.count(), 2);
    });

    test('re-importing the same case updates it instead of duplicating', () {
      repo.importRows([_row()]);
      final again = repo.importRows([_row(reason: 'Corrected reason')]);

      expect(again.inserted, 0);
      expect(again.updated, 1);
      // The point of the natural key: one case, not two.
      expect(repo.count(), 1);
      expect(repo.allCases().single['reason'], 'Corrected reason');
    });

    test('a corrected CPU overwrites what was stored', () {
      repo
        ..importRows([_row()])
        ..importRows([_row(cpu: 'Kolkata')]);

      expect(repo.allCases().single['cpu'], 'Kolkata');
      expect(repo.count(), 1);
    });

    test('cases differing only in line no are separate records', () {
      repo.importRows([_row(lineNo: '1'), _row(lineNo: '2')]);

      expect(repo.count(), 2);
    });

    test('a mixed submit reports inserts and updates apart', () {
      repo.importRows([_row(lineNo: '1')]);

      final result = repo.importRows([
        _row(lineNo: '1', reason: 'Updated'),
        _row(lineNo: '2'),
      ]);

      expect(result.updated, 1);
      expect(result.inserted, 1);
      expect(repo.count(), 2);
    });

    test('reports the rows as stored, not as they were posted', () {
      repo.importRows([
        {..._row(lineNo: '1'), 'status': 'Verified'},
      ]);

      final result = repo.importRows([
        {..._row(lineNo: '1'), 'facility_sr_no': '7'},
        _row(lineNo: '2'),
      ]);

      expect(result.rows, hasLength(2));
      // The alias resolved and the status kept — neither is visible in what
      // the caller sent, which is why the rows are read back.
      expect(result.rows.first['sr_no'], '7');
      expect(result.rows.first['status'], 'Verified');
      expect(result.rows.last['status'], 'Pending with CPU');
      expect(result.rows.last['imported_at'], isNotEmpty);
    });

    test('missing optional columns are stored as empty, not null', () {
      final sparse = _row()..remove('segment');
      repo.importRows([sparse]);

      expect(repo.allCases().single['segment'], '');
    });

    test('an account number is kept as text, never rounded', () {
      repo.importRows([_row()]);

      expect(repo.allCases().single['account_no'], '50200031339584');
    });

    test('every stored case is stamped with when it was imported', () {
      repo.importRows([_row()]);

      final stamp = repo.allCases().single['imported_at'] as String;
      expect(DateTime.tryParse(stamp), isNotNull);
    });

    group('status', () {
      test('defaults for a case nobody has reviewed yet', () {
        repo.importRows([_row()]);

        expect(repo.allCases().single['status'], 'Pending with CPU');
      });

      test('a stated status is stored', () {
        repo.importRows([
          {..._row(), 'status': 'Pending with Health Checker'},
        ]);

        expect(
          repo.allCases().single['status'],
          'Pending with Health Checker',
        );
      });

      test('a stated status overwrites the stored one', () {
        repo
          ..importRows([_row()])
          ..importRows([
            {..._row(), 'status': 'Pending with Health Checker'},
          ]);

        expect(
          repo.allCases().single['status'],
          'Pending with Health Checker',
        );
        expect(repo.count(), 1);
      });

      test('a row stating no status leaves the stored one alone', () {
        repo
          ..importRows([
            {..._row(), 'status': 'Pending with Health Checker'},
          ])
          // What re-uploading the spreadsheet looks like: no status column.
          ..importRows([_row(reason: 'Corrected reason')]);

        final stored = repo.allCases().single;
        // Regression: this used to reset a reviewed case back to the default.
        expect(stored['status'], 'Pending with Health Checker');
        expect(stored['reason'], 'Corrected reason');
      });
    });

    test('importing nothing is a no-op', () {
      final result = repo.importRows([]);

      expect(result.total, 0);
      expect(repo.count(), 0);
    });

    test('the older facility_sr_no spelling still lands in sr_no', () {
      // A client that has not been rebuilt posts the old key; it has to keep
      // working rather than silently blanking the column.
      repo.importRows([_row()]);

      expect(repo.allCases().single['sr_no'], '1');
    });

    group('setStatusForClient', () {
      test('moves that client\u2019s cases and reports how many', () {
        repo.importRows([
          _row(lineNo: '1'),
          _row(lineNo: '2'),
          _row(clientId: 'someone-else'),
        ]);

        final moved = repo.setStatusForClient(
          clientId: '4943581',
          status: 'Verified',
        );

        expect(moved, 2);
        expect(
          {
            for (final row in repo.allCases())
              row['client_id'] as String: row['status'],
          },
          {'4943581': 'Verified', 'someone-else': 'Pending with CPU'},
        );
      });

      test('a client nobody stored moves nothing', () {
        repo.importRows([_row()]);

        // Not an error — the count is the answer, and 0 is a fine one.
        expect(
          repo.setStatusForClient(clientId: 'not-here', status: 'Verified'),
          0,
        );
        expect(repo.allCases().single['status'], 'Pending with CPU');
      });

      test('with a from, only rows in that status move', () {
        repo.importRows([
          {..._row(lineNo: '1'), 'status': 'Pending with CPU'},
          {..._row(lineNo: '2'), 'status': 'Verified'},
        ]);

        final moved = repo.setStatusForClient(
          clientId: '4943581',
          status: 'Pending with Health Checker',
          from: 'Pending with CPU',
        );

        // Each side of the handover only moves a record out of its own queue,
        // so a finished case cannot be dragged back into the maker's grid.
        expect(moved, 1);
        expect(
          {for (final row in repo.allCases()) row['line_no']: row['status']},
          {'1': 'Pending with Health Checker', '2': 'Verified'},
        );
      });

      test('the client id is matched however it was typed', () {
        repo.importRows([_row(clientId: 'CL22156')]);

        expect(
          repo.setStatusForClient(clientId: 'cl22156', status: 'Verified'),
          1,
        );
      });
    });

    group('reassignForClient', () {
      test('cpu, team and status move together', () {
        repo.importRows([
          {..._row(), 'status': 'Pending with Health Checker'},
        ]);

        final moved = repo.reassignForClient(
          clientId: '4943581',
          cpu: 'Chennai',
          team: 'Disbursement Team',
          status: 'Pending with CPU',
          assignedBy: 'OFF807292',
        );

        expect(moved, 1);
        final stored = repo.allCases().single;
        // One act: a case that changed hands but kept its status would sit in
        // the wrong queue under the right team.
        expect(stored['cpu'], 'Chennai');
        expect(stored['team'], 'Disbursement Team');
        expect(stored['status'], 'Pending with CPU');
      });

      test('with a from, a record outside that queue is left alone', () {
        repo.importRows([
          {..._row(), 'status': 'Verified'},
        ]);

        final moved = repo.reassignForClient(
          clientId: '4943581',
          cpu: 'Chennai',
          team: 'Disbursement Team',
          status: 'Pending with CPU',
          assignedBy: 'OFF807292',
          from: 'Pending with Health Checker',
        );

        expect(moved, 0);
        expect(repo.allCases().single['cpu'], 'Mumbai');
      });
    });

    group('casesForOwner', () {
      // What the dashboard reads: one person's side of one handover. Both
      // halves have to bite — the status alone is the whole team's work, and
      // the employee code alone is every record they have ever touched.
      setUp(() {
        repo.importRows([
          {..._row(lineNo: '1'), 'status': 'Pending with Health Checker'},
          {..._row(lineNo: '2'), 'status': 'Pending with CPU'},
          {
            ..._row(lineNo: '3'),
            'maker': 'someone-else',
            'status': 'Pending with Health Checker',
          },
        ]);
      });

      List<String> lineNosFor({
        required String status,
        required String ownerColumn,
        required String employeeCode,
      }) => [
        for (final row in repo.casesForOwner(
          status: status,
          ownerColumn: ownerColumn,
          employeeCode: employeeCode,
        ))
          row['line_no'] as String,
      ];

      test("is the rows in the status that are also this owner's", () {
        expect(
          lineNosFor(
            status: 'Pending with Health Checker',
            ownerColumn: 'maker',
            employeeCode: 'mk',
          ),
          ['1'],
        );
      });

      test('the same code in the other column is a different person', () {
        // `ck` checks every one of these and makes none of them.
        expect(
          lineNosFor(
            status: 'Pending with Health Checker',
            ownerColumn: 'maker',
            employeeCode: 'ck',
          ),
          isEmpty,
        );
        expect(
          lineNosFor(
            status: 'Pending with CPU',
            ownerColumn: 'checker',
            employeeCode: 'ck',
          ),
          ['2'],
        );
      });

      test('casing decides nothing', () {
        // The code comes from the sign-in service and the column was written
        // from a spreadsheet; neither settles how an officer code is typed.
        expect(
          lineNosFor(
            status: 'pending with health checker',
            ownerColumn: 'maker',
            employeeCode: 'MK',
          ),
          ['1'],
        );
      });

      test('a code nobody carries is empty, not everything', () {
        expect(
          lineNosFor(
            status: 'Pending with CPU',
            ownerColumn: 'checker',
            employeeCode: 'n2346',
          ),
          isEmpty,
        );
      });
    });

    group('seedIfEmpty', () {
      test('fills an empty table', () {
        final seeded = repo.seedIfEmpty([_row(lineNo: '1'), _row(lineNo: '2')]);

        expect(seeded, 2);
        expect(repo.count(), 2);
      });

      test('leaves a table that already holds cases alone', () {
        repo.importRows([_row(reason: 'Real import')]);

        final seeded = repo.seedIfEmpty([_row(lineNo: '9')]);

        // Nothing is written once there is real data — a sample case that was
        // deleted must not come back on the next restart.
        expect(seeded, 0);
        expect(repo.count(), 1);
        expect(repo.allCases().single['reason'], 'Real import');
      });
    });
  });
}
