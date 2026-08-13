// Which tabs of the case drawer each template's rights unlock.
//
// The rights themselves are covered in `user_rights_test.dart`; this is the
// step after — the two tabs that change a record appearing only for the
// template granted each one.
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_monitor/models/user_rights.dart';
import 'package:smart_monitor/widgets/case_detail_panel.dart';

List<String> _labels(String role) => [
  for (final tab in tabsFor(UserRights.forRole(role))) tab.label,
];

/// The three that only read. Both templates get these — commenting is a right
/// each carries, and the rest show what is already stored.
///
/// Activity is not among them: it is switched off for both templates for now,
/// which is why no list here names it.
const _readOnly = ['Basic Info', 'Comments', 'Documents'];

void main() {
  test('a maker gets both Verify and Reassign', () {
    expect(_labels('Maker'), [
      'Basic Info',
      'Verify',
      'Reassign',
      'Comments',
      'Documents',
    ]);
  });

  test('a checker gets neither', () {
    // Its one action is commenting, which every template may do.
    expect(_labels('Checker'), _readOnly);
  });

  test('an unknown template still reads the record', () {
    // Nothing to action, but locking someone out of the detail entirely would
    // be a worse answer to an unrecognised role.
    expect(_labels('Regional Head'), _readOnly);
  });

  test('only the maker is offered a tab that changes the record', () {
    // Verify and Reassign are the two that write; everything else reads.
    const writing = [CaseDetailTab.verify, CaseDetailTab.reassign];
    for (final template in AppRole.templates) {
      final tabs = tabsFor(UserRights.forRole(template.label));
      final writes = tabs.where(writing.contains);
      expect(
        writes,
        template == AppRole.maker ? writing : isEmpty,
        reason: template.label,
      );
    }
  });

  test('tabs stay in enum order for every template', () {
    for (final template in AppRole.values) {
      final tabs = tabsFor(UserRights.forRole(template.label));
      final ordered = [
        for (final tab in CaseDetailTab.values)
          if (tabs.contains(tab)) tab,
      ];
      expect(tabs, ordered, reason: template.label);
    }
  });
}
