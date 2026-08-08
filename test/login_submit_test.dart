// Signing in pushes the dashboard, and the dashboard fetches the case list
// from its initState. So a second submit landing while the first is still in
// its delay does not just push a spare route — it builds two dashboards and
// sends two GETs for the same rows.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_monitor/pages/dashboard_page.dart';
import 'package:smart_monitor/pages/login_page.dart';

/// Counts the routes sign-in puts on the stack.
///
/// Both callbacks are watched: the login page swaps itself out with
/// `pushReplacement`, which reports through `didReplace`, and a second submit
/// that slipped past the guard reports through whichever one matches how far
/// the first had got. Counting routes rather than looking for the dashboard is
/// the point — the spare one is disposed again as the next replacement lands,
/// so by the time the tree settles only its fetch is left behind as evidence.
class _RouteCounter extends NavigatorObserver {
  int added = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previous) {
    // The login route arrives with nothing under it; only what sign-in adds
    // is being counted here.
    if (previous != null) added++;
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    added++;
  }
}

void main() {
  // The sign-in button disables itself for the 700ms the submit spends
  // waiting, but the password field's own submit action does not go through
  // it: clicking back into the field and pressing Enter again reaches
  // `_submit` a second time while the first is still in flight.
  testWidgets('a second Enter while signing in pushes only one dashboard', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final observer = _RouteCounter();
    await tester.pumpWidget(
      MaterialApp(home: const LoginPage(), navigatorObservers: [observer]),
    );

    final password = find.byType(TextFormField).last;
    await tester.enterText(find.byType(TextFormField).first, 'ninad.thakur');
    await tester.enterText(password, 'hunter2');
    await tester.pump();

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump(const Duration(milliseconds: 100));
    // Enter takes the focus off the field, so reaching the action twice means
    // clicking back into it first.
    await tester.tap(password);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(observer.added, 1);
    expect(find.byType(DashboardPage), findsOneWidget);
  });
}
