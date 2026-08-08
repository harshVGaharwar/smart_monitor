// The read-excel response exactly as UAT sends it, driven through the model
// and onto the screen.
//
// The payload here is a captured response, pasted unchanged — nulls, the
// numeric `sr_no`, the .NET minimum date and all. The other tests build
// convenient bodies; this one exists so a change to the envelope, the model or
// the results table is caught against the real thing rather than against a
// body written to suit the code.
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
// The only seam the package offers for standing in for the platform picker.
// ignore: implementation_imports
import 'package:file_picker/src/platform/file_picker_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smart_monitor/core/api_client.dart';
import 'package:smart_monitor/models/upload_response.dart';
import 'package:smart_monitor/services/case_api.dart';
import 'package:smart_monitor/widgets/upload_cases_view.dart';

/// `POST /SmartAPI/read-excel`, captured verbatim.
const _uatResponse = '''
{
    "code": 0,
    "message": "Upload Successful",
    "body": null,
    "success": true,
    "data": {
        "rows": [
            {
                "client_id": "3332125",
                "customer_name": "LEHRY INSTRUMENTATION AND VALVES PVT LTD",
                "account_no": "11424036",
                "line_no": "50301271033004",
                "health_check_category": "FD Exceptions",
                "sub_category": "Excess lien marked in Core",
                "support_system": "787920",
                "core_system": "986920",
                "exception_category": "Exception",
                "reason": "Fd Lien Amount Mismatch Between Lmm And Core; To Be Reviewed And Rectified",
                "cpu": "Chennai",
                "team": "Disbursement Team",
                "segment": null,
                "facility": null,
                "sr_no": 0,
                "maker": "OFF550975",
                "checker": "r14878",
                "ls_srm_date": "0001-01-01"
            }
        ]
    },
    "count": 0,
    "userName": null,
    "userCode": null,
    "branchName": null,
    "branchCode": null,
    "menu": null
}
''';

/// A backend answering any upload with [_uatResponse].
CaseApi _api() => CaseApi(
  ApiClient(
    client: MockClient((_) async => http.Response(_uatResponse, 200)),
  ),
);

class _FakePicker extends FilePickerPlatform {
  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
    bool cancelUploadOnWindowBlur = true,
  }) async {
    // The workbook is parsed server-side, so the bytes are never read.
    final bytes = Uint8List.fromList(utf8.encode('ignored'));
    return FilePickerResult([
      PlatformFile(name: 'HealthCheck.xlsx', size: bytes.length, bytes: bytes),
    ]);
  }
}

void main() {
  group('the UAT read-excel response', () {
    test('reads into the upload model', () {
      final response = UploadResponse.fromJson(jsonDecode(_uatResponse));

      expect(response.isSuccess, isTrue);
      expect(response.message, 'Upload Successful');
      // `count` is the field as the service stated it — 0 even here, on a
      // response plainly carrying a row — so the card counts the rows it got.
      expect(response.count, 0);
      expect(response.rowCount, 1);
      expect(response.rows, hasLength(1));

      final row = response.rows.single;
      expect(row.id, 1);
      expect(row.clientId, '3332125');
      expect(row.customerName, 'LEHRY INSTRUMENTATION AND VALVES PVT LTD');
      expect(row.accountNo, '11424036');
      expect(row.lineNo, '50301271033004');
      expect(row.subCategory, 'Excess lien marked in Core');
      expect(row.supportSystem, '787920');
      expect(row.coreSystem, '986920');
      expect(row.maker, 'OFF550975');
      expect(row.checker, 'r14878');
      // A null column is blank, not the text "null".
      expect(row.segment, '');
      expect(row.facility, '');
      // The service's stand-in for "not numbered" — serial numbers start at 1.
      expect(row.facilitySrNo, '');
    });

    test('every validated field resolves against the master data', () {
      final response = UploadResponse.fromJson(jsonDecode(_uatResponse));
      final row = response.rows.single;

      expect(row.cpu, 'Chennai');
      expect(row.actionableTeam, 'Disbursement Team');
      expect(row.healthCheckCategory, 'FD Exceptions');
      expect(row.exceptionCategory, 'Exception');
      // So the row lands in "Ready to Import" rather than the error set.
      expect(row.hasErrors, isFalse);
      expect(response.toOutcome().valid, hasLength(1));
    });

    testWidgets('the row reaches the results table', (tester) async {
      FilePickerPlatform.instance = _FakePicker();

      tester.view.physicalSize = const Size(3200, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: UploadCasesView(api: _api()))),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Upload Health Check Excel'));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(find.text('3332125'), findsOneWidget);
      expect(
        find.text('LEHRY INSTRUMENTATION AND VALVES PVT LTD'),
        findsOneWidget,
      );
      expect(find.text('Chennai'), findsWidgets);
      // The counts above the table, from the one clean row. They are spans of
      // a RichText — the number and its label are styled apart — so the finder
      // has to be told to look inside one.
      expect(
        find.textContaining('1 Processed', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('1 Ready to Import', findRichText: true),
        findsOneWidget,
      );
    });
  });
}
