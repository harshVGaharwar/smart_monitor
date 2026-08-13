import 'pending_case.dart';

/// The user templates the service issues, and what each may do.
///
/// Two today: the health-check side raises and verifies records, the CPU side
/// routes and comments on them. The supervisor templates the rights matrix
/// describes are not issued yet.
///
/// Which *screens* a user reaches is not decided here — the sign-in response
/// carries a `menuList` for that, and `navItemsFor` in
/// `widgets/app_sidebar.dart` reads it. This covers only what happens inside a
/// screen the user already has.
enum AppRole {
  /// The health-check side. Verifies records, routes them onward, and ticks
  /// them off in the grid.
  maker('Maker'),

  /// The CPU side. Reads and comments; the actions belong to the maker.
  checker('Checker'),

  /// A template this build does not know. Granted nothing.
  unknown('');

  /// The text the service sends in `role`.
  final String label;
  const AppRole(this.label);

  /// The two the service actually issues; [unknown] is this app's own.
  static const templates = [maker, checker];

  /// What the dashboard calls itself for this template.
  ///
  /// The two sides work the same grid from opposite ends, and the heading is
  /// the only thing on the screen that says which end the reader is at. A
  /// template this build cannot name gets the plain word: better an unadorned
  /// heading than one claiming a side they may not be on.
  String get dashboardTitle => switch (this) {
    maker => 'Health Check Dashboard',
    checker => 'CPU Check Dashboard',
    unknown => 'Dashboard',
  };

  /// [role] as a template, matched forgivingly — the text is the service's,
  /// not this app's, so `maker` and `MAKER` both land on [maker].
  static AppRole parse(String role) {
    final matched = PendingCase.matchOption(role, [
      for (final template in templates) template.label,
    ]);
    for (final template in templates) {
      if (template.label == matched) return template;
    }
    return unknown;
  }
}

/// What the signed-in user may do inside the screens they can reach.
class UserRights {
  /// The stat cards above the grid — "view the summary".
  final bool canViewSummary;

  /// The per-row checkbox in the dashboard grid — "tick in dashboard".
  final bool canTick;

  /// The Verify tab of the case drawer — "verify the records".
  final bool canVerify;

  /// The Reassign tab of the case drawer — handing a record to another CPU
  /// and team. The health-check side owns that routing, so the maker carries
  /// it alongside the verify.
  final bool canReassign;

  const UserRights({
    this.canViewSummary = false,
    this.canTick = false,
    this.canVerify = false,
    this.canReassign = false,
  });

  /// The rights [role] carries.
  ///
  /// Commenting and uploading are not gated: both templates have both. An
  /// unrecognised template gets nothing — the role text is free-form, and a
  /// typo in it should not hand someone the verify button.
  ///
  /// [canViewSummary] goes to neither: it is a supervisor's right, and no
  /// supervisor template is issued yet. The flag stays as the place one would
  /// attach rather than something to rediscover later.
  factory UserRights.forRole(String role) => switch (AppRole.parse(role)) {
    AppRole.maker => const UserRights(
      canTick: true,
      canVerify: true,
      canReassign: true,
    ),
    // Commenting is its only action, and that is not gated.
    AppRole.checker || AppRole.unknown => const UserRights(),
  };
}
