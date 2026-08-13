// What each template may do inside a screen.
//
// Screens themselves are the menu's job (`sidebar_menu_test.dart`), and which
// records a template works is the server's (`dashboard_request_test.dart`).
// This is the third part — the summary cards, the row tick and the two tabs
// that change a record, none of which either of those says anything about.
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_monitor/models/user_rights.dart';

void main() {
  test('a maker verifies, reassigns and ticks records off', () {
    final rights = UserRights.forRole('Maker');

    expect(rights.canVerify, isTrue);
    expect(rights.canReassign, isTrue);
    expect(rights.canTick, isTrue);
  });

  test('a checker only comments', () {
    final rights = UserRights.forRole('Checker');

    // Commenting is not gated, so a checker carrying no right at all is
    // exactly right — every action belongs to the maker.
    expect(rights.canVerify, isFalse);
    expect(rights.canReassign, isFalse);
    expect(rights.canTick, isFalse);
  });

  test('neither template sees the summary', () {
    // It is a supervisor's right, and no supervisor template is issued yet.
    for (final template in AppRole.templates) {
      expect(
        UserRights.forRole(template.label).canViewSummary,
        isFalse,
        reason: template.label,
      );
    }
  });

  test('casing and punctuation in the template name do not matter', () {
    // The role text is the service's, not this app's.
    expect(UserRights.forRole('maker').canVerify, isTrue);
    expect(UserRights.forRole('MAKER').canTick, isTrue);
    expect(UserRights.forRole('  maker  ').canReassign, isTrue);
  });

  test('the two templates resolve to two distinct roles', () {
    final parsed = {
      for (final template in AppRole.templates) AppRole.parse(template.label),
    };
    expect(parsed, {AppRole.maker, AppRole.checker});
    expect(parsed, isNot(contains(AppRole.unknown)));
  });

  test('a template this build does not know is granted nothing', () {
    // A typo in free-form role text must not hand out the verify button.
    for (final role in ['CPU User', 'Health Check User', 'Supervisor', '']) {
      final rights = UserRights.forRole(role);
      expect(rights.canViewSummary, isFalse, reason: role);
      expect(rights.canTick, isFalse, reason: role);
      expect(rights.canVerify, isFalse, reason: role);
      expect(rights.canReassign, isFalse, reason: role);
    }
  });
}
