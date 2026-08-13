// The Documents tab: read from the service when the drawer opens, and read
// again after a note that carried a file, so the tab shows what is stored
// rather than what this session happened to upload.
//
// Documents are nobody's in particular — whichever side attached one, the
// other side has to be able to open it — so nothing here is gated on a role.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smart_monitor/core/api_client.dart';
import 'package:smart_monitor/models/case_item.dart';
import 'package:smart_monitor/models/user_rights.dart';
import 'package:smart_monitor/services/case_api.dart';
import 'package:smart_monitor/widgets/case_detail_panel.dart';

const _case = CaseItem(
  exceptionCode: 'EXC-1',
  clientId: '1130488',
  customerName: 'TRANSIT ELECTRONICS LTD',
  accountNo: '11264580',
  lineNo: '5',
  status: CaseStatus.pendingWithCpu,
);

late List<http.BaseRequest> _sent;

/// The files the stub answers a read with. Written to by the stub's own
/// handler, so a post is visible to the re-read that follows it.
late List<Map<String, dynamic>> _files;

Map<String, dynamic> _document({
  required String fileName,
  String userId = 'OFF807292',
  String uploadedBy = 'Maker',
}) => {
  'clientId': '1130488',
  'userID': userId,
  'fileName': fileName,
  'uploadedBy': uploadedBy,
  'uploadedDate': '2026-08-11T12:13:00.000Z',
};

String _envelope(Object? data) =>
    jsonEncode({'code': 0, 'message': 'ok', 'success': true, 'data': data});

/// A stub that behaves like the server: a note carrying a file lands on the
/// list the next read answers with.
Api _api({int documentsStatus = 200}) => Api(
  ApiClient(
    client: MockClient((request) async {
      _sent.add(request);
      if (request.url.path.endsWith('/getDocuments')) {
        if (documentsStatus != 200) {
          return http.Response(
            jsonEncode({
              'success': false,
              'message': 'The documents are offline.',
            }),
            documentsStatus,
          );
        }
        return http.Response(_envelope({'documents': _files}), 200);
      }
      if (request.url.path.endsWith('/getComments')) {
        return http.Response(_envelope({'comments': []}), 200);
      }
      return http.Response(_envelope(1), 200);
    }),
  ),
);

Future<void> _pump(
  WidgetTester tester, {
  Api? api,
  String role = 'Checker',
  String userId = 'r14878',
}) async {
  tester.view.physicalSize = const Size(1400, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CaseDetailPanel(
          caseItem: _case,
          initialTab: CaseDetailTab.documents,
          tabs: tabsFor(UserRights.forRole(role)),
          currentUser: role,
          userId: userId,
          role: role,
          onChanged: (_) {},
          onClose: () {},
          api: api ?? _api(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

List<http.BaseRequest> _to(String path) => [
  for (final r in _sent)
    if (r.url.path.endsWith(path)) r,
];

void main() {
  setUp(() {
    _sent = [];
    _files = [];
  });

  testWidgets('the files are read when the drawer opens', (tester) async {
    _files.addAll([
      _document(fileName: 'lien.xlsx'),
      _document(
        fileName: 'proof.pdf',
        userId: 'r14878',
        uploadedBy: 'Checker',
      ),
    ]);

    await _pump(tester);

    final sent = _to('/getDocuments').single;
    expect(sent.method, 'GET');
    // The case, and who is asking — the casing the service uses.
    expect(sent.url.queryParameters, {
      'clientId': '1130488',
      'userID': 'r14878',
    });

    expect(find.text('lien.xlsx'), findsOneWidget);
    expect(find.text('proof.pdf'), findsOneWidget);
    // The uploader as the service resolved them, not the signed-in reader.
    expect(find.text('Maker'), findsWidgets);
    // The tab's own count follows the list it draws.
    expect(find.textContaining('Documents (2)'), findsOneWidget);
  });

  testWidgets('a case with nothing attached says where files come from', (
    tester,
  ) async {
    await _pump(tester);

    expect(_to('/getDocuments'), hasLength(1));
    expect(find.textContaining('Attach one with a comment'), findsOneWidget);
    expect(find.textContaining('Documents (0)'), findsOneWidget);
  });

  testWidgets('a read that will not load says why, over a retry', (
    tester,
  ) async {
    await _pump(tester, api: _api(documentsStatus: 500));

    expect(find.text('The documents are offline.'), findsOneWidget);
    // The empty state would read as "this case has none", which is a different
    // and wrong thing to tell someone.
    expect(find.textContaining('Attach one with a comment'), findsNothing);

    _files.add(_document(fileName: 'lien.xlsx'));
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    // The retry goes back to the same stub, which is still failing — what
    // matters is that it asked again rather than giving up.
    expect(_to('/getDocuments'), hasLength(2));
  });

  testWidgets('both sides read the same files', (tester) async {
    // Whichever side attached a document, the other has to be able to see it.
    _files.add(
      _document(fileName: 'proof.pdf', userId: 'r14878', uploadedBy: 'Checker'),
    );

    await _pump(tester, role: 'Maker', userId: 'OFF807292');

    expect(find.text('proof.pdf'), findsOneWidget);
    expect(_to('/getDocuments').single.url.queryParameters['userID'],
        'OFF807292');
  });

  testWidgets('a template this build cannot name still reads them', (
    tester,
  ) async {
    // The Documents tab is everyone's — `tabsFor` gives it to a role with no
    // rights at all, so the read must not be gated either.
    _files.add(_document(fileName: 'lien.xlsx'));

    await _pump(tester, role: 'Auditor', userId: 'aud1');

    expect(find.text('lien.xlsx'), findsOneWidget);
  });
}
