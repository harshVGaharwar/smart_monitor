// End-to-end cover for row removal: drives the real UploadCasesView through a
// real upload — picker, upload response, results table — then deletes rows and
// undoes.
//
// Worth the setup: the delete path spans the table, the view and the outcome
// model, and the failure it caught (an undo restoring a row onto a page the
// table had navigated away from) was invisible to any of them tested alone.
//
// The workbook is parsed server-side, so the backend is stubbed and the bytes
// the picker hands over are never read — only the response shape matters.
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
import 'package:smart_monitor/core/constants.dart';
import 'package:smart_monitor/services/case_api.dart';
import 'package:smart_monitor/widgets/upload_cases_view.dart';

/// Requests the stub backend received, newest last, so a test can assert on
/// what the submit actually sent.
final _sent = <http.Request>[];

/// A backend that answers any upload with [rowCount] clean rows, and any
/// import with a count of what it was given.
CaseApi _api(int rowCount) {
  final body = jsonEncode({
    'rows': [
      for (var i = 1; i <= rowCount; i++)
        {
          'client_id': 'CL$i',
          'customer_name': 'Cust$i',
          'account_no': 'ACC$i',
          'line_no': 'L$i',
          'health_check_category': 'FD Exceptions',
          'sub_category': 'Sub',
          'support_system': 'LMM',
          'core_system': 'FC',
          'segment': 'Retail',
          'facility_sr_no': '1',
          'maker': 'mk',
          'checker': 'ck',
          'ls_srm_date': '2026-07-21',
          'exception_category': 'Exception',
          'reason': 'Reason$i',
          'cpu': 'Mumbai',
          'team': 'LMS Team',
        },
    ],
  });
  return CaseApi(
    ApiClient(
      client: MockClient((request) async {
        if (!request.url.path.endsWith(ApiEndpoints.upddateCase)) {
          return http.Response(body, 200);
        }
        _sent.add(request);
        final rows =
            (jsonDecode(request.body) as Map<String, dynamic>)['rows'] as List;
        return http.Response(
          jsonEncode({'inserted': rows.length, 'updated': 0}),
          200,
        );
      }),
    ),
  );
}

/// The rows the last submit sent to the import endpoint.
List<Map<String, dynamic>> _importedRows() {
  final body = jsonDecode(_sent.last.body) as Map<String, dynamic>;
  return [for (final row in body['rows'] as List) row as Map<String, dynamic>];
}

/// The picker only has to produce bytes; the stub ignores them.
Uint8List _bytes() => Uint8List.fromList(utf8.encode('ignored'));

class _FakePicker extends FilePickerPlatform {
  final Uint8List bytes;
  _FakePicker(this.bytes);

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
    return FilePickerResult([
      PlatformFile(name: 'cases.csv', size: bytes.length, bytes: bytes),
    ]);
  }
}

void main() {
  setUp(_sent.clear);

  testWidgets('real view: submit posts the reviewed rows to the backend', (
    tester,
  ) async {
    FilePickerPlatform.instance = _FakePicker(_bytes());
    final api = _api(12);

    tester.view.physicalSize = const Size(3200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: UploadCasesView(api: api))),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Upload Health Check Excel'));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // A row dropped in the review must not reach the database.
    await tester.tap(find.byIcon(Icons.delete_outline_rounded).first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Submit Data'));
    await tester.pumpAndSettle();

    expect(_sent, hasLength(1), reason: 'submit did not call the import');
    final rows = _importedRows();
    expect(rows, hasLength(11));
    expect(
      rows.map((r) => r['customer_name']),
      isNot(contains('Cust1')),
      reason: 'a deleted row was still imported',
    );
    // The resolved value is what gets stored, not the file's raw text.
    expect(rows.first['cpu'], 'Mumbai');
    expect(rows.first['team'], 'LMS Team');
    expect(find.textContaining('11 case(s) imported'), findsOneWidget);
  });

  testWidgets('real view: ticking rows submits only those', (tester) async {
    FilePickerPlatform.instance = _FakePicker(_bytes());
    final api = _api(12);

    tester.view.physicalSize = const Size(3200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: UploadCasesView(api: api))),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Upload Health Check Excel'));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // Row checkboxes follow the header's select-all box.
    final boxes = find.byType(Checkbox);
    await tester.tap(boxes.at(1));
    await tester.pumpAndSettle();
    await tester.tap(boxes.at(3));
    await tester.pumpAndSettle();

    // The button commits to the count before it is pressed.
    expect(find.text('Submit 2 Selected'), findsOneWidget);

    await tester.tap(find.text('Submit 2 Selected'));
    await tester.pumpAndSettle();

    final rows = _importedRows();
    expect(rows, hasLength(2), reason: 'the whole file was sent, not the tick');
    expect(
      rows.map((r) => r['customer_name']),
      containsAll(<String>['Cust1', 'Cust3']),
    );
  });

  testWidgets('real view: a failed submit keeps the report on screen', (
    tester,
  ) async {
    FilePickerPlatform.instance = _FakePicker(_bytes());
    final rows = jsonEncode({
      'rows': [
        {
          'client_id': 'CL1',
          'customer_name': 'Cust1',
          'account_no': 'ACC1',
          'line_no': 'L1',
          'health_check_category': 'FD Exceptions',
          'exception_category': 'Exception',
          'cpu': 'Mumbai',
          'team': 'LMS Team',
        },
      ],
    });
    final api = CaseApi(
      ApiClient(
        client: MockClient((request) async {
          if (!request.url.path.endsWith(ApiEndpoints.upddateCase)) {
            return http.Response(rows, 200);
          }
          return http.Response(
            jsonEncode({'message': 'The database is unavailable.'}),
            503,
          );
        }),
      ),
    );

    tester.view.physicalSize = const Size(3200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: UploadCasesView(api: api))),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Upload Health Check Excel'));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    await tester.tap(find.text('Submit Data'));
    await tester.pumpAndSettle();

    // The server's message reaches the user, and the reviewed rows are still
    // there to retry rather than reset away under a failure.
    expect(find.text('The database is unavailable.'), findsOneWidget);
    expect(find.text('Cust1'), findsOneWidget);
    expect(find.text('Submit Data'), findsOneWidget);
  });

  testWidgets('real view: delete a row then undo', (tester) async {
    FilePickerPlatform.instance = _FakePicker(_bytes());
    final api = _api(12);

    tester.view.physicalSize = const Size(3200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: UploadCasesView(api: api))),
    );
    await tester.pumpAndSettle();

    // Idle → pick a file → validating → results.
    await tester.tap(find.text('Upload Health Check Excel'));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    expect(find.text('Cust9'), findsOneWidget, reason: 'results not shown');

    // Row 9's own delete button.
    await tester.tap(find.byIcon(Icons.delete_outline_rounded).at(8));
    await tester.pumpAndSettle();

    expect(find.text('Row 9 removed'), findsOneWidget);
    expect(find.text('Cust9'), findsNothing);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(find.text('Cust9'), findsOneWidget, reason: 'UNDO DID NOT RESTORE');
  });

  testWidgets('real view: delete the only row on the last page, then undo', (
    tester,
  ) async {
    // 11 rows at 10 per page: page 2 holds exactly one row.
    FilePickerPlatform.instance = _FakePicker(_bytes());
    final api = _api(11);

    tester.view.physicalSize = const Size(3200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: UploadCasesView(api: api))),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Upload Health Check Excel'));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    await tester.tap(find.byIcon(Icons.chevron_right_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Cust11'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.delete_outline_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Row 11 removed'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(
      find.text('Cust11'),
      findsOneWidget,
      reason: 'UNDO LEFT THE ROW ON A PAGE THE USER IS NOT LOOKING AT',
    );
  });

  testWidgets('real view: two deletes in a row, then undo', (tester) async {
    FilePickerPlatform.instance = _FakePicker(_bytes());
    final api = _api(12);

    tester.view.physicalSize = const Size(3200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: UploadCasesView(api: api))),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Upload Health Check Excel'));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    await tester.tap(find.byIcon(Icons.delete_outline_rounded).at(1));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.delete_outline_rounded).at(1));
    await tester.pumpAndSettle();

    expect(find.text('Row 3 removed'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(find.text('Cust3'), findsOneWidget, reason: 'second undo failed');
    expect(find.text('Cust2'), findsNothing, reason: 'first delete came back');
  });

  testWidgets('an unexpected response shape says so, not "no rows"', (
    tester,
  ) async {
    FilePickerPlatform.instance = _FakePicker(_bytes());
    // A 200 that is not this app's contract — a proxy page, another backend.
    final api = CaseApi(
      ApiClient(
        client: MockClient(
          (_) async =>
              http.Response(jsonEncode({'ok': true, 'data2': []}), 200),
        ),
      ),
    );

    tester.view.physicalSize = const Size(3200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: UploadCasesView(api: api))),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Upload Health Check Excel'));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // Names the shape, so the reader looks at the endpoint rather than the
    // spreadsheet.
    expect(find.textContaining('returned no rows'), findsOneWidget);
    expect(find.textContaining('ok, data2'), findsOneWidget);
  });
}
