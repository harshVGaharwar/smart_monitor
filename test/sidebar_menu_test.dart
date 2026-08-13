// What the navigation rail shows a given user.
//
// The menu comes from the sign-in response, so this is the one place where a
// permission the service sends turns into a screen the user can reach — and a
// mistake here either hides work from someone who has to do it, or opens a
// screen they should not see.
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_monitor/models/login_response.dart';
import 'package:smart_monitor/widgets/app_sidebar.dart';

MenuPermission _menu(String name, {String isActive = 'Y'}) =>
    MenuPermission(id: 1, menuName: name, profileId: 'P1', isActive: isActive);

List<String> _labels(List<MenuPermission> menu) => [
  for (final item in navItemsFor(menu)) item.label,
];

void main() {
  test('a supervisor with every menu open sees the whole rail', () {
    expect(
      _labels([_menu('Dashboard'), _menu('MIS'), _menu('Upload Document')]),
      ['Dashboard', 'MIS', 'Upload Document'],
    );
  });

  test('a closed menu is left out', () {
    // Sent as `N` rather than omitted, which is how the service reports it.
    expect(
      _labels([
        _menu('Dashboard'),
        _menu('MIS', isActive: 'N'),
        _menu('Upload Document'),
      ]),
      ['Dashboard', 'Upload Document'],
    );
  });

  test('items keep catalogue order, not the order they arrived in', () {
    // The rail reads the same for everyone, so a user does not have to hunt
    // for the item that moved.
    expect(_labels([_menu('Upload Document'), _menu('Dashboard')]), [
      'Dashboard',
      'Upload Document',
    ]);
  });

  test('casing and punctuation in the menu name do not matter', () {
    // The name is the service's text, not this app's label.
    expect(_labels([_menu('upload_document'), _menu('  MIS  ')]), [
      'MIS',
      'Upload Document',
    ]);
  });

  test('a name with no screen behind it is ignored', () {
    expect(_labels([_menu('Dashboard'), _menu('Reconciliation Admin')]), [
      'Dashboard',
    ]);
  });

  test('a user the service sent nothing for still gets the dashboard', () {
    // An empty rail locks someone out of the whole app, which is a worse
    // answer to a mismatched menu name than a read-only grid.
    expect(_labels(const []), ['Dashboard']);
    expect(_labels([_menu('Dashboard', isActive: 'N')]), ['Dashboard']);
  });
}
