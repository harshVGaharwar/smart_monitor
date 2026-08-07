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

    test('importing nothing is a no-op', () {
      final result = repo.importRows([]);

      expect(result.total, 0);
      expect(repo.count(), 0);
    });
  });
}
