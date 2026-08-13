// The comment composer, and where a supporting document is attached.
//
// A file goes up with the comment that explains it: the note is required and
// the file is not, so evidence never lands on a record with nothing saying
// what it shows. The Documents tab lists what arrived that way and takes
// nothing of its own.
//
// The CPU side decides from this box too, so for them the action is a second
// thing the post waits on. `case_comments_test.dart` drives what goes out.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smart_monitor/core/api_client.dart';
import 'package:smart_monitor/core/constants.dart';
import 'package:smart_monitor/models/case_item.dart';
import 'package:smart_monitor/models/user_rights.dart';
import 'package:smart_monitor/services/case_api.dart';
import 'package:smart_monitor/widgets/case_detail_panel.dart';

const _case = CaseItem(
  exceptionCode: 'EXC-1',
  clientId: '3332125',
  customerName: 'ACME',
  accountNo: '11424036',
  lineNo: '5',
  status: CaseStatus.pendingWithCpu,
);

Future<void> _pump(
  WidgetTester tester,
  CaseDetailTab tab, {
  String role = 'Checker',
}) async {
  tester.view.physicalSize = const Size(1400, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CaseDetailPanel(
          caseItem: _case,
          initialTab: tab,
          tabs: tabsFor(UserRights.forRole(role)),
          currentUser: 'Someone',
          userId: 'r14878',
          role: role,
          onChanged: (_) {},
          onClose: () {},
          api: Api(
            ApiClient(
              client: MockClient(
                (_) async => http.Response('{"updated":1}', 200),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Whether Send is live. The button is an [InkWell] whose `onTap` is null
/// while the comment is empty, not a disabled [FilledButton].
bool _sendEnabled(WidgetTester tester) =>
    tester
        .widget<InkWell>(
          find.ancestor(
            of: find.text('Post Comment'),
            matching: find.byType(InkWell),
          ),
        )
        .onTap !=
    null;

void main() {
  testWidgets('the composer carries a comment, documents and send', (
    tester,
  ) async {
    await _pump(tester, CaseDetailTab.comments);

    expect(find.text('COMMENTS'), findsOneWidget);
    expect(find.text('SUPPORT DOCUMENTS'), findsOneWidget);
    expect(find.text('Post Comment'), findsOneWidget);
  });

  testWidgets('send stays disabled until the comment has text', (tester) async {
    // The health check side has no action to pick here — signing off is its
    // own tab — so text is the only thing the post waits on.
    await _pump(tester, CaseDetailTab.comments, role: 'Maker');

    // A file on its own cannot post: there would be nothing saying what it is.
    expect(_sendEnabled(tester), isFalse);

    await tester.enterText(find.byType(TextField).last, 'Checked in core');
    await tester.pumpAndSettle();

    expect(_sendEnabled(tester), isTrue);
  });

  testWidgets('the CPU side waits on the action as well as the text', (
    tester,
  ) async {
    await _pump(tester, CaseDetailTab.comments);

    await tester.enterText(find.byType(TextField).last, 'Documents in order');
    await tester.pumpAndSettle();

    // Text alone is not enough for them: passing a record on is not something
    // to do by not noticing a dropdown.
    expect(find.text('ACTION'), findsOneWidget);
    expect(find.text('Select an action'), findsWidgets);
    expect(_sendEnabled(tester), isFalse);

    await tester.tap(find.text('Select an action').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Approve').last);
    await tester.pumpAndSettle();

    expect(_sendEnabled(tester), isTrue);
  });

  testWidgets('the health check side is offered no action here', (
    tester,
  ) async {
    await _pump(tester, CaseDetailTab.comments, role: 'Maker');

    expect(find.text('ACTION'), findsNothing);
  });

  testWidgets('whitespace alone does not count as a comment', (tester) async {
    await _pump(tester, CaseDetailTab.comments, role: 'Maker');

    await tester.enterText(find.byType(TextField).last, '   ');
    await tester.pumpAndSettle();

    expect(_sendEnabled(tester), isFalse);
  });

  testWidgets('the documents tab lists but does not upload', (tester) async {
    await _pump(tester, CaseDetailTab.documents);

    expect(find.text('SUPPORTING DOCUMENTS'), findsOneWidget);
    // Says where they come from, so an empty tab does not read as broken.
    expect(find.textContaining('Attach one with a comment'), findsOneWidget);
  });

  test('excel is an accepted supporting document', () {
    // The picker filters on this list, so a format missing here cannot be
    // attached however the field is drawn.
    expect(
      AppConstants.documentExtensions,
      containsAll(<String>['png', 'jpg', 'jpeg', 'pdf', 'xlsx', 'xls']),
    );
  });
}
