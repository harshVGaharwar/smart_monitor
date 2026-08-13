// Signing a record off.
//
// The tab offers no status any more — verifying has one outcome — and the call
// behind the button names the record rather than restating it: four fields,
// not the nineteen columns the panel never edited.
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
  exceptionCode: '2287410-11930442-50301271033039',
  clientId: '2287410',
  customerName: 'NORTHGATE LOGISTICS LIMITED',
  accountNo: '11930442',
  lineNo: '50301271033039',
  status: CaseStatus.pendingWithHealthChecker,
);

late List<http.BaseRequest> _sent;

/// Records the case the panel handed back, if it handed one back at all.
CaseItem? _changed;

/// True once the panel asked to be closed.
bool _closed = false;

Api _api({int verifyStatus = 200}) => Api(
  ApiClient(
    client: MockClient((request) async {
      _sent.add(request);
      if (request.url.path.endsWith('/verify')) {
        return http.Response(
          jsonEncode(
            verifyStatus == 200
                ? {
                  'code': 0,
                  'message': 'Updated Successfully',
                  'success': true,
                  'data': 1,
                  'count': 1,
                }
                : {'success': false, 'message': 'Not allowed.'},
          ),
          verifyStatus,
        );
      }
      // The comments tab reads its thread when the drawer opens.
      return http.Response(
        jsonEncode({
          'code': 0,
          'message': 'ok',
          'success': true,
          'data': {'comments': <dynamic>[]},
        }),
        200,
      );
    }),
  ),
);

Future<void> _pump(WidgetTester tester, {Api? api}) async {
  tester.view.physicalSize = const Size(1400, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CaseDetailPanel(
          caseItem: _case,
          initialTab: CaseDetailTab.verify,
          tabs: tabsFor(UserRights.forRole('Maker')),
          currentUser: 'Maker',
          userId: 'OFF807292',
          role: 'Maker',
          onChanged: (c) => _changed = c,
          onClose: () => _closed = true,
          api: api ?? _api(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

List<http.BaseRequest> _to(String path) =>
    [for (final r in _sent) if (r.url.path.endsWith(path)) r];

void main() {
  setUp(() {
    _sent = [];
    _changed = null;
    _closed = false;
  });

  testWidgets('the tab asks for a note and nothing else', (tester) async {
    await _pump(tester);

    expect(find.text('Verification Action'), findsOneWidget);
    expect(find.text('VERIFICATION COMMENT'), findsOneWidget);
    expect(find.text('Verify Record'), findsOneWidget);
    // Gone: verifying a record into the queue it is already in was never a
    // choice worth offering.
    expect(find.text('CHANGE STATUS'), findsNothing);
    expect(find.text('Select status'), findsNothing);
  });

  testWidgets('verifying names the record and says why', (tester) async {
    await _pump(tester);

    await tester.enterText(find.byType(TextField).first, 'Lien released');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Verify Record'));
    await tester.pumpAndSettle();

    final sent = _to('/verify').single as http.Request;
    expect(sent.method, 'POST');
    expect(jsonDecode(sent.body), {
      'clientId': '2287410',
      'userId': 'OFF807292',
      'role': 'Maker',
      'comments': 'Lien released',
      // The button has one meaning, and it is this one. Approving is the CPU
      // side's decision, and this tab is never theirs.
      'isVerified': 'yes',
      // Null, not a no: approving is the CPU side's decision to make.
      'status': null,
    });
  });

  testWidgets('a note is not required to verify', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('Verify Record'));
    await tester.pumpAndSettle();

    final sent = _to('/verify').single as http.Request;
    expect((jsonDecode(sent.body) as Map)['comments'], '');
  });

  testWidgets('the verified record is handed back, and the drawer is not '
      'closed twice', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('Verify Record'));
    await tester.pumpAndSettle();

    // Confirmed in a dialog rather than a toast: the row is about to leave the
    // grid, and a message that slides away on its own is a poor place to say
    // so. Nothing is handed back until it is dismissed.
    expect(find.text('Record verified'), findsOneWidget);
    expect(_changed, isNull);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    // The status the dashboard drops the row on: it is neither queue, so the
    // grid loses it and reads itself again.
    expect(_changed?.status, CaseStatus.verified);
    // Closing is the dashboard's, off that status move. Calling onClose here
    // as well would pop at a drawer that has already gone.
    expect(_closed, isFalse);
  });

  testWidgets('a refused verify keeps the record and says why', (tester) async {
    await _pump(tester, api: _api(verifyStatus: 403));

    await tester.enterText(find.byType(TextField).first, 'Lien released');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Verify Record'));
    await tester.pumpAndSettle();

    expect(find.text('Not allowed.'), findsOneWidget);
    // Nothing claimed on screen that the server did not accept, and the note
    // is still in the box to try again with.
    expect(_changed, isNull);
    expect(find.text('Lien released'), findsOneWidget);
  });
}
