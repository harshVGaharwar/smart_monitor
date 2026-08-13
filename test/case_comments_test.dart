// The comment thread: read from the service when the drawer opens, written
// back through /verify when one is posted, and re-read after so the panel
// shows what is stored rather than what it hoped would be.
//
// One write for the whole box — the note, the document and, for the CPU side,
// what they decided about the record all go up as the one act they were.
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

/// Every request the panel made.
late List<http.BaseRequest> _sent;

/// The thread the stub answers a read with. Written to by the stub's own
/// handler, so a post is visible to the re-read that follows it.
late List<Map<String, dynamic>> _thread;

Map<String, dynamic> _comment({
  required String userId,
  required String role,
  required String text,
  String reason = '',
}) => {
  'clientId': '1130488',
  'userId': userId,
  'role': role,
  'comments': text,
  'reason': reason,
  'createdAt': '2026-08-11T12:13:00.000Z',
};

String _envelope(Object? data) =>
    jsonEncode({'code': 0, 'message': 'ok', 'success': true, 'data': data});

/// A stub that behaves like the server: a post lands on the thread the next
/// read answers with.
Api _api({int status = 200}) => Api(
  ApiClient(
    client: MockClient((request) async {
      _sent.add(request);
      if (status != 200) {
        return http.Response(
          jsonEncode({'success': false, 'message': 'The thread is offline.'}),
          status,
        );
      }
      if (request.url.path.endsWith('/verify')) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final text = '${body['comments']}';
        if (text.isNotEmpty) {
          _thread.add(
            _comment(
              userId: '${body['userId']}',
              role: '${body['role']}',
              text: text,
            ),
          );
        }
        return http.Response(_envelope(1), 200);
      }
      return http.Response(_envelope({'comments': _thread}), 200);
    }),
  ),
);

/// The record as the panel handed it back, when it handed one back.
CaseItem? _changed;

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
          initialTab: CaseDetailTab.comments,
          tabs: tabsFor(UserRights.forRole(role)),
          currentUser: role,
          userId: userId,
          role: role,
          onChanged: (c) => _changed = c,
          onClose: () {},
          api: api ?? _api(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The requests that went to [path].
List<http.BaseRequest> _to(String path) => [
  for (final r in _sent)
    if (r.url.path.endsWith(path)) r,
];

void main() {
  setUp(() {
    _sent = [];
    _thread = [];
    _changed = null;
  });

  /// Fills the box and posts, picking [action] first when one is offered.
  Future<void> post(
    WidgetTester tester,
    String text, {
    String? action,
  }) async {
    await tester.enterText(find.byType(TextField).last, text);
    await tester.pumpAndSettle();
    if (action != null) {
      await tester.tap(find.text('Select an action').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text(action).last);
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Post Comment'));
    await tester.pumpAndSettle();
    // A decision confirms in a dialog; the record is not handed back until
    // the reader has dismissed it.
    if (action != null) {
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
    }
  }

  testWidgets('the thread is read when the drawer opens', (tester) async {
    _thread.add(
      _comment(userId: 'r14878', role: 'Checker', text: 'asd'),
    );

    await _pump(tester);

    expect(_to('/getComments').single.url.queryParameters, {
      'clientId': '1130488',
      'userId': 'r14878',
    });
    // Drawn as the screenshot has it: the template that wrote it, then the
    // note.
    expect(find.text('Checker'), findsWidgets);
    expect(find.text('asd'), findsOneWidget);
    // The tab counts what the service holds, not what this session posted.
    expect(find.textContaining('Comments (1)'), findsOneWidget);
  });

  testWidgets('the newest note is at the top', (tester) async {
    // The service answers oldest first — the order the thread was written in.
    _thread.addAll([
      _comment(userId: 'r14878', role: 'Checker', text: 'oldest'),
      _comment(userId: 'r14878', role: 'Checker', text: 'middle'),
      _comment(userId: 'r14878', role: 'Checker', text: 'newest'),
    ]);

    await _pump(tester);

    // A reader opening a record wants the last thing said, and a long thread
    // would bury it below the fold.
    final tops =
        tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data)
            .whereType<String>()
            .where((text) => ['oldest', 'middle', 'newest'].contains(text))
            .toList();
    expect(tops, ['newest', 'middle', 'oldest']);
  });

  testWidgets('a reassignment shows why, beside who', (tester) async {
    _thread.add(
      _comment(
        userId: 'OFF807292',
        role: 'Maker',
        text: 'Wrong team, sending this back.',
        reason: 'Incorrect CPU mapping',
      ),
    );

    await _pump(tester);

    // The first thing the CPU side wants when a record lands back with them,
    // and the note is still exactly what was typed.
    expect(find.text('· Incorrect CPU mapping'), findsOneWidget);
    expect(find.text('Wrong team, sending this back.'), findsOneWidget);
  });

  testWidgets('a case with no thread yet says so', (tester) async {
    await _pump(tester);

    expect(find.text('No comments yet.'), findsOneWidget);
    expect(find.textContaining('Comments (0)'), findsOneWidget);
  });

  testWidgets('an approval is the note and the decision in one write', (
    tester,
  ) async {
    await _pump(tester);

    await post(tester, 'Documents in order', action: 'Approve');

    // One call, not a comment and then a decision.
    expect(_to('/addComment'), isEmpty);
    final sent = _to('/verify').single as http.Request;
    expect(jsonDecode(sent.body), {
      'clientId': '1130488',
      'userId': 'r14878',
      'role': 'Checker',
      'comments': 'Documents in order',
      // Null, not a no: verifying is the health check side's decision, and
      // the CPU side has none to make about it.
      'isVerified': null,
      'status': 'Approved',
    });
    // The record is the health check side's now, so the row leaves this
    // reader's grid — the dashboard closes the drawer off this status move.
    expect(_changed?.status, CaseStatus.pendingWithHealthChecker);
  });

  testWidgets('a rejection says so and leaves the record where it is', (
    tester,
  ) async {
    await _pump(tester);

    await post(tester, 'Sending this back', action: 'Reject');

    final sent = _to('/verify').single as http.Request;
    final posted = jsonDecode(sent.body) as Map;
    expect(posted['status'], 'Reject');
    expect(posted['isVerified'], isNull);
    // The note lands, the record does not move, and the drawer stays open.
    expect(find.text('Sending this back'), findsOneWidget);
    expect(_changed?.status, CaseStatus.pendingWithCpu);
  });

  testWidgets('the health check side posts a note that decides nothing', (
    tester,
  ) async {
    await _pump(tester, role: 'Maker', userId: 'OFF807292');

    await post(tester, 'Waiting on the branch');

    final sent = _to('/verify').single as http.Request;
    expect(jsonDecode(sent.body), {
      'clientId': '1130488',
      'userId': 'OFF807292',
      'role': 'Maker',
      'comments': 'Waiting on the branch',
      // A no, not null: this side could have verified and did not. Signing off
      // is the Verify tab's; this box only ever leaves a note.
      'isVerified': 'no',
      // Null, not a no: approving is the CPU side's decision, and the health
      // check side has none to make here.
      'status': null,
    });
    expect(_changed?.status, CaseStatus.pendingWithCpu);
  });

  testWidgets('each side reads what the other wrote', (tester) async {
    _thread.addAll([
      _comment(userId: 'r14878', role: 'Checker', text: 'From the CPU'),
      _comment(
        userId: 'OFF807292',
        role: 'Maker',
        text: 'From the health check',
      ),
    ]);

    // The thread is one thread: it is narrowed to the record, never to who is
    // asking, or the two sides would be talking past each other.
    await _pump(tester, role: 'Maker', userId: 'OFF807292');
    expect(find.text('From the CPU'), findsOneWidget);
    expect(find.text('From the health check'), findsOneWidget);
  });

  testWidgets('the thread is re-read after a post, and the box cleared', (
    tester,
  ) async {
    await _pump(tester);

    await post(tester, 'Checked in core', action: 'Reject');

    // Twice: once on open, once after the write — what is on screen is what
    // the service holds, not what the panel assumed it would.
    expect(_to('/getComments'), hasLength(2));
    expect(find.text('Checked in core'), findsOneWidget);
    expect(find.textContaining('Comments (1)'), findsOneWidget);
    // Cleared, so the same note cannot be sent twice by a second tap.
    expect(
      tester.widget<TextField>(find.byType(TextField).last).controller?.text,
      '',
    );
  });

  testWidgets('a thread that will not load says why, over a retry', (
    tester,
  ) async {
    await _pump(tester, api: _api(status: 500));

    expect(find.text('The thread is offline.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    // The composer stays: the failure is in reading the thread, not in
    // writing to it.
    expect(find.text('Post Comment'), findsOneWidget);
  });
}
