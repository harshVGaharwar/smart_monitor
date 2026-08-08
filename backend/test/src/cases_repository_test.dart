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
