// End-to-end cover for row removal: drives the real UploadCasesView through a
// real upload — picker, parse, results table — then deletes rows and undoes.
//
// Worth the setup: the delete path spans the table, the view and the outcome
// model, and the failure it caught (an undo restoring a row onto a page the
// table had navigated away from) was invisible to any of them tested alone.
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
// The only seam the package offers for standing in for the platform picker.
// ignore: implementation_imports
import 'package:file_picker/src/platform/file_picker_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_monitor/widgets/upload_cases_view.dart';

const _headers = [
  'Client id',
  'Customer name',
  'Account no',
  'Line no',
  'Health Check Category',
  'Sub category',
  'Support system',
  'Core system',
  'Segment',
  'Facility Sr. no',
  'Maker',
  'Checker',
  'LS SRM Date',
  'Exception category',
  'Reason',
  'CPU',
  'Actionable Team',
];

Uint8List _csv(int rowCount) {
  final rows = [
    _headers.join(','),
    for (var i = 1; i <= rowCount; i++)
      'CL$i,Cust$i,ACC$i,L$i,FD Exceptions,Sub,LMM,FC,Retail,1,mk,ck,'
          '2026-07-21,Exception,Reason$i,Mumbai,LMS Team',
  ];
  return Uint8List.fromList(utf8.encode(rows.join('\n')));
}

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
  testWidgets('real view: delete a row then undo', (tester) async {
    FilePickerPlatform.instance = _FakePicker(_csv(12));

    tester.view.physicalSize = const Size(3200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: UploadCasesView())),
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
    FilePickerPlatform.instance = _FakePicker(_csv(11));

    tester.view.physicalSize = const Size(3200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: UploadCasesView())),
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
    FilePickerPlatform.instance = _FakePicker(_csv(12));

    tester.view.physicalSize = const Size(3200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: UploadCasesView())),
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
}
