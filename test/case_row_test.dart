// The envelope model itself: every field the service sends, and what the row
// model makes of the values it leaves implicit.
//
// The other suites go through the dashboard or the API; this one pins the
// contract directly, since CasesResponse is what a captured payload is read
// against and a field quietly dropped here is invisible everywhere else.
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_monitor/models/case_item.dart';
import 'package:smart_monitor/models/case_row.dart';
import 'package:smart_monitor/models/pending_case.dart';
import 'package:smart_monitor/models/cases_response.dart';
import 'package:smart_monitor/models/upload_response.dart';

Map<String, dynamic> _row({
  Object? srNo = '3',
  Object? status = 'In Review',
  Object? segment = 'Corporate',
  Object? lsSrmDate = '2026-07-21',
}) => {
  'client_id': '3332125',
  'customer_name': 'LEHRY INSTRUMENTATION AND VALVES PVT LTD',
  'account_no': '11424036',
  'line_no': '50301271033004',
  'health_check_category': 'FD Exceptions',
  'sub_category': 'Excess lien marked in Core',
  'support_system': '787920',
  'core_system': '986920',
  'exception_category': 'Exception',
  'reason': 'Fd Lien Amount Mismatch Between Lmm And Core',
  'cpu': 'Chennai',
  'team': 'Disbursement Team',
  'segment': segment,
  'facility': null,
  'sr_no': srNo,
  'maker': 'OFF550975',
  'checker': 'r14878',
  'ls_srm_date': lsSrmDate,
  'status': status,
  'imported_at': '2026-08-08T11:18:08.918901Z',
};

Map<String, dynamic> _envelope({List<Map<String, dynamic>>? rows}) => {
  'code': 0,
  'message': 'Upload Successful',
  'body': null,
  'success': true,
  'data': {
    'rows': rows ?? [_row()],
  },
  'count': 0,
  'userName': 'ninad.thakur',
  'userCode': 'OFF550975',
  'branchName': 'Chennai Main',
  'branchCode': '0042',
  'menu': null,
};

void main() {
  group('CasesResponse', () {
    test('carries every field of the envelope, not only the rows', () {
      final res = CasesResponse.fromJson(_envelope());

      expect(res.code, 0);
      expect(res.message, 'Upload Successful');
      expect(res.body, isNull);
      expect(res.success, isTrue);
      expect(res.count, 0);
      // The session fields this app has no use for are still carried: they are
      // part of the contract, and a screen that starts needing one should find
      // it here rather than reaching back into a decoded map.
      expect(res.userName, 'ninad.thakur');
      expect(res.userCode, 'OFF550975');
      expect(res.branchName, 'Chennai Main');
      expect(res.branchCode, '0042');
      expect(res.menu, isNull);
    });

    test('the data block holds the rows in the order they arrived', () {
      final res = CasesResponse.fromJson(
        _envelope(
          rows: [
            _row(),
            {..._row(), 'client_id': '1130488'},
          ],
        ),
      );

      expect(res.data, isNotNull);
      expect(res.rows.map((r) => r.clientId), ['3332125', '1130488']);
      expect(res.rowCount, 2);
    });

    test('a failure carries no data block', () {
      final res = CasesResponse.fromJson({
        'code': 1,
        'message': 'Not authorised',
        'success': false,
        'data': null,
        'count': 0,
      });

      expect(res.data, isNull);
      expect(res.rows, isEmpty);
      expect(res.isSuccess, isFalse);
      expect(res.failure, 'Not authorised');
    });
  });

  group('CaseRow', () {
    test('reads the row as the service wrote it, without interpreting it', () {
      final row = CasesResponse.fromJson(_envelope()).rows.single;

      expect(row.clientId, '3332125');
      expect(row.customerName, 'LEHRY INSTRUMENTATION AND VALVES PVT LTD');
      expect(row.accountNo, '11424036');
      expect(row.lineNo, '50301271033004');
      expect(row.healthCheckCategory, 'FD Exceptions');
      expect(row.subCategory, 'Excess lien marked in Core');
      expect(row.supportSystem, '787920');
      expect(row.coreSystem, '986920');
      expect(row.exceptionCategory, 'Exception');
      expect(row.cpu, 'Chennai');
      expect(row.team, 'Disbursement Team');
      expect(row.maker, 'OFF550975');
      expect(row.checker, 'r14878');
      expect(row.status, 'In Review');
      // Untouched: the date stays text, and the serial stays the number the
      // service sent. Reading them is toCaseItem's job.
      expect(row.srNo, 3);
      expect(row.lsSrmDate, '2026-07-21');
      expect(row.importedAt, '2026-08-08T11:18:08.918901Z');
      // A column the service left empty is null, not "".
      expect(row.facility, isNull);
    });

    test('sr_no reads the same whether it is a number or text', () {
      // The service sends a number; this server sent text for a while, and a
      // spreadsheet reader hands over 3.0 for a cell showing 3. None of them
      // may change what the cell shows.
      expect(CaseRow.fromJson(_row(srNo: '4')).toCaseItem().srNo, '4');
      expect(CaseRow.fromJson(_row(srNo: 4)).toCaseItem().srNo, '4');
      // The stand-in for "never numbered", either way.
      expect(CaseRow.fromJson(_row(srNo: '0')).toCaseItem().srNo, '');
      expect(CaseRow.fromJson(_row(srNo: 0)).toCaseItem().srNo, '');
    });

    test('toCaseItem resolves what the wire leaves implicit', () {
      final item = CaseRow.fromJson(_row()).toCaseItem();

      // The workflow status onto its enum, so the badge and the filter agree.
      expect(item.status, CaseStatus.inReview);
      expect(item.lsrmDate, DateTime.parse('2026-07-21'));
      expect(item.updatedAt, DateTime.parse('2026-08-08T11:18:08.918901Z'));
      // No id on the wire, so the natural key is the reference.
      expect(item.exceptionCode, '3332125-11424036-50301271033004');
    });

    test('the .NET minimum date is no date, not the year 1', () {
      final item = CaseRow.fromJson(_row(lsSrmDate: '0001-01-01')).toCaseItem();

      expect(item.lsrmDate, isNull);
    });

    test('an unknown status still reaches the grid', () {
      // In a bucket the STATUS filter actually offers, rather than being
      // dropped from the response.
      final item = CaseRow.fromJson(_row(status: 'Whatever')).toCaseItem();

      expect(item.status, CaseStatus.pendingWithCpu);
    });

    test('a row of nulls is blank cells, not a crash', () {
      // One odd row must not take the whole grid down — which a raw cast on
      // every field would do.
      final row = CaseRow.fromJson({
        'client_id': '3332125',
        'customer_name': null,
        'reason': null,
        'cpu': null,
        'status': null,
      });

      expect(row.customerName, '');
      expect(row.reason, '');
      expect(row.cpu, '');
      expect(row.status, '');

      final item = row.toCaseItem();
      expect(item.clientId, '3332125');
      expect(item.status, CaseStatus.pendingWithCpu);
      expect(item.lsrmDate, isNull);
    });

    test('the stand-ins an export writes for empty do not become text', () {
      final row = CaseRow.fromJson({
        ..._row(segment: 'nan'),
        'facility': 'null',
      });

      expect(row.segment, isNull);
      expect(row.facility, isNull);
      expect(row.toCaseItem().segment, '');
    });
  });

  group('UploadResponse', () {
    // The same envelope and the same row model as the dashboard's — an upload
    // row is a stored one without `status` and `imported_at`.
    Map<String, dynamic> upload({List<Map<String, dynamic>>? rows}) {
      final row = {..._row(status: null)}..remove('imported_at');
      return {
        ..._envelope(rows: rows ?? [row]),
        'data': {
          'rows': rows ?? [row],
        },
      };
    }

    test('carries every field of the envelope, not only the rows', () {
      final res = UploadResponse.fromJson(upload());

      expect(res.code, 0);
      expect(res.message, 'Upload Successful');
      expect(res.body, isNull);
      expect(res.success, isTrue);
      expect(res.count, 0);
      expect(res.userName, 'ninad.thakur');
      expect(res.userCode, 'OFF550975');
      expect(res.branchName, 'Chennai Main');
      expect(res.branchCode, '0042');
      expect(res.menu, isNull);
      expect(res.rowCount, 1);
    });

    test('a rejected file is a failure carrying the message', () {
      // Shown verbatim on the upload card, so it has to survive the read.
      final res = UploadResponse.fromJson({
        'code': 1,
        'message': 'The file is missing required column(s): CPU.',
        'success': false,
        'data': null,
        'count': 0,
      });

      expect(res.isSuccess, isFalse);
      expect(res.isEmpty, isTrue);
      expect(res.failure, 'The file is missing required column(s): CPU.');
    });

    test('a body that never came from the service is a failure', () {
      // A gateway's error page read as zero rows would leave the card with
      // nothing to say.
      expect(
        UploadResponse.fromBody('Service Unavailable').failure,
        'Service Unavailable',
      );
      expect(UploadResponse.fromBody(null).failure, contains('empty response'));
    });

    test('rows are numbered by their position in the file', () {
      // The response carries no id, and the number has to survive filtering
      // and the errors-only export.
      final res = UploadResponse.fromJson(
        upload(
          rows: [
            {..._row(status: null)},
            {..._row(status: null), 'client_id': '1130488'},
          ],
        ),
      );

      expect(res.rows.map((r) => r.id), [1, 2]);
      expect(res.rows.map((r) => r.clientId), ['3332125', '1130488']);
    });
  });

  group('toPendingCase', () {
    PendingCase pending(Map<String, dynamic> json) =>
        CaseRow.fromJson(json).toPendingCase(sequence: 1);

    test('resolves the validated fields against the master data', () {
      final row = pending(_row());

      expect(row.cpu, 'Chennai');
      expect(row.actionableTeam, 'Disbursement Team');
      expect(row.healthCheckCategory, 'FD Exceptions');
      expect(row.exceptionCategory, 'Exception');
      // So it lands in "Ready to Import" rather than the error set.
      expect(row.hasErrors, isFalse);
    });

    test('a value the master data rejects is kept as the file wrote it', () {
      // The results table shows it back in a red, editable cell — it cannot do
      // that from a value that was dropped.
      final row = pending({..._row(), 'cpu': 'Hyderabad', 'team': 'Limits'});

      expect(row.cpu, isNull);
      expect(row.cpuRaw, 'Hyderabad');
      expect(row.actionableTeam, isNull);
      expect(row.teamRaw, 'Limits');
      expect(row.hasErrors, isTrue);
      expect(row.errorFields, containsAll(['CPU', 'Actionable Team']));
    });

    test('the wire conventions read the same as they do for the grid', () {
      final row = pending({..._row(srNo: 0), 'ls_srm_date': '0001-01-01'});

      // Serial numbers start at 1, so the stand-in for "unset" is blank.
      expect(row.facilitySrNo, '');
      // The upload screen shows the date as text, so .NET's minimum stays as
      // it arrived rather than becoming the year 1 in a parsed form.
      expect(row.lsSrmDate, '0001-01-01');
      expect(pending(_row(srNo: 7)).facilitySrNo, '7');
    });

    test('the editable fields are the ones the table writes to', () {
      final row = pending(_row());

      // Not a compile-time property to assert, so it is asserted by doing it:
      // the results table sets these directly from its dropdowns.
      row
        ..cpu = 'Mumbai'
        ..actionableTeam = 'LMS Team'
        ..reason = 'Corrected';

      expect(row.cpu, 'Mumbai');
      expect(row.actionableTeam, 'LMS Team');
      expect(row.reason, 'Corrected');
      expect(row.hasErrors, isFalse);
    });
  });
}
