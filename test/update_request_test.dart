import 'package:flutter_test/flutter_test.dart';
import 'package:smart_monitor/models/case_item.dart';
import 'package:smart_monitor/models/pending_case.dart';
import 'package:smart_monitor/models/update_request.dart';

/// A row as `update-smartpointer` carries it, every key present.
Map<String, dynamic> _row() => {
  'client_id': '4943581',
  'customer_name': 'ACME',
  'account_no': '50200031339584',
  'line_no': '5',
  'health_check_category': 'CAM Expiry Health Check',
  'sub_category': 'Sub',
  'support_system': 'LMM',
  'core_system': 'FC',
  'exception_category': 'Exception',
  'reason': 'Renewal pending',
  'cpu': 'Mumbai',
  'team': 'Cam Renewal Team',
  'segment': 'Retail',
  'facility': 'Cash Credit',
  'sr_no': '1',
  'maker': 'mk',
  'checker': 'ck',
  'ls_srm_date': '2026-07-21',
  'status': 'Pending with CPU',
};

void main() {
  group('UpdateRequestModel', () {
    test('round-trips the body it posts', () {
      final model = UpdateRequestModel.fromJson({
        'rows': [_row()],
      });

      expect(model.rows, hasLength(1));
      expect(model.toJson(), {
        'rows': [_row()],
      });
    });

    test('a body with no rows reads as none rather than throwing', () {
      expect(UpdateRequestModel.fromJson({}).rows, isEmpty);
      expect(UpdateRequestModel.fromJson({'rows': <dynamic>[]}).rows, isEmpty);
    });

    test('every key is sent, absent ones as null', () {
      final json =
          UpdateRequestModel(rows: [UpdateRequestRow(clientId: '1')]).toJson();

      final row = (json['rows']! as List).single as Map<String, dynamic>;
      // A field the client has nothing for is stated as absent, not blanked —
      // which is how a null status leaves a stored one alone.
      expect(row, hasLength(19));
      expect(row['client_id'], '1');
      expect(row.containsKey('status'), isTrue);
      expect(row['status'], isNull);
    });

    test('numbers on the wire are read as the text they are stored as', () {
      final row = UpdateRequestRow.fromJson({'sr_no': 4, 'client_id': 12});

      expect(row.srNo, '4');
      expect(row.clientId, '12');
    });

    test('copyWith replaces only what it is given', () {
      final row = UpdateRequestRow.fromJson(_row());
      final moved = row.copyWith(cpu: 'Chennai', status: 'Verified');

      expect(moved.cpu, 'Chennai');
      expect(moved.status, 'Verified');
      expect(moved.clientId, row.clientId);
      expect(moved.team, row.team);
    });
  });

  group('from a reviewed upload row', () {
    PendingCase pending() => PendingCase(
      clientId: '4943581',
      customerName: 'ACME',
      accountNo: '50200031339584',
      lineNo: '5',
      subCategory: 'Sub',
      supportSystem: 'LMM',
      coreSystem: 'FC',
      maker: 'mk',
      checker: 'ck',
      segment: 'Retail',
      facility: 'Cash Credit',
      facilitySrNo: '1',
      lsSrmDate: '2026-07-21',
      healthCheckCategory: 'CAM Expiry Health Check',
      exceptionCategory: 'Exception',
      reason: 'Renewal pending',
      cpu: 'Mumbai',
      actionableTeam: 'Cam Renewal Team',
    );

    test('carries the columns the import expects', () {
      final row = UpdateRequestRow.fromPendingCase(pending());

      expect(row.toJson(), {..._row(), 'status': null});
    });

    test('states no status, so a reviewed case is not reset', () {
      final row = UpdateRequestRow.fromPendingCase(pending());

      // An uploaded file never carries a status. Sending one — even a blank —
      // would risk sending a case the reviewer had moved on back to the
      // default.
      expect(row.status, isNull);
    });

    test(
      'an unresolved cpu or team goes out blank rather than as raw text',
      () {
        final row = UpdateRequestRow.fromPendingCase(
          PendingCase(
            clientId: '1',
            customerName: 'ACME',
            accountNo: '2',
            lineNo: '3',
            subCategory: '',
            supportSystem: '',
            coreSystem: '',
            maker: '',
            checker: '',
            cpuRaw: 'Hyderabad',
            teamRaw: 'Limits',
          ),
        );

        expect(row.cpu, '');
        expect(row.team, '');
      },
    );
  });

  group('from a stored case', () {
    test('carries the status the Verify tab changed', () {
      final row = UpdateRequestRow.fromCaseItem(
        CaseItem(
          exceptionCode: 'EXC-1',
          clientId: '4943581',
          customerName: 'ACME',
          accountNo: '50200031339584',
          lineNo: '5',
          status: CaseStatus.verified,
          healthCheckCategory: 'CAM Expiry Health Check',
          subCategory: 'Sub',
          supportSystem: 'LMM',
          coreSystem: 'FC',
          exceptionCategory: 'Exception',
          reason: 'Renewal pending',
          segment: 'Retail',
          facility: 'Cash Credit',
          srNo: '1',
          maker: 'mk',
          checker: 'ck',
          lsrmDate: DateTime.utc(2026, 7, 21),
          cpu: 'Mumbai',
          team: 'Cam Renewal Team',
        ),
      );

      expect(row.status, 'Verified');
      expect(row.lsSrmDate, '2026-07-21T00:00:00.000Z');
      // Fields the detail screen never shows are still posted back, so saving
      // one case does not blank what is stored against it.
      expect(row.facility, 'Cash Credit');
      expect(row.srNo, '1');
    });

    test(
      'a case with no date sends a blank rather than dropping the column',
      () {
        final row = UpdateRequestRow.fromCaseItem(
          const CaseItem(
            exceptionCode: 'EXC-2',
            clientId: '1',
            customerName: 'ACME',
            accountNo: '2',
            status: CaseStatus.pendingWithCpu,
          ),
        );

        expect(row.lsSrmDate, '');
        expect(row.status, 'Pending with CPU');
      },
    );
  });
}
