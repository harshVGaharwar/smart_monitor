import 'dart:io';

import 'package:dart_frog/dart_frog.dart';

/// POST /api/login — sign in, and say which screens this user may open.
///
/// Deliberately **not** wrapped in the `SmartEnvelope` the other routes use:
/// unlike the three case endpoints, the real sign-in service answers
/// `{token, refreshToken, user}` at the top level, and a client written
/// against it would not find the payload under `data`.
///
/// Two fixed accounts stand in for a directory this server has no access to.
/// What it models faithfully is the part the app depends on: the `menuList`
/// that decides the navigation rail, and a role the case panel gates its tabs
/// on.
///
/// The username picks the template; **any non-empty password is accepted**.
/// There is nothing to authenticate against here, and demoing the templates
/// should not mean remembering passwords.
///
/// | username  | template | employee code | rights                        |
/// |-----------|----------|---------------|-------------------------------|
/// | `maker`   | Maker    | `OFF807292`   | verify records, tick them off |
/// | `checker` | Checker  | `r14878`      | comment, reassign to a CPU    |
///
/// Both templates are given every menu, MIS included. The real service decides
/// this per profile; here it is the difference between a screen being
/// developable and being unreachable.
///
/// The employee codes are not decoration: `/get-smartpointer` reads a queue by
/// employee code and role, so these are codes the seeded cases actually carry
/// in their `maker` and `checker` columns. An account issued a code no record
/// names would sign in to an empty dashboard.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response.json(
      statusCode: HttpStatus.methodNotAllowed,
      body: {'message': 'Use POST to sign in.'},
    );
  }

  final dynamic payload;
  try {
    payload = await context.request.json();
  } catch (_) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'message': 'Expected a JSON body with a name and password.'},
    );
  }

  // The client sends the service's casing — `Name`, and a lowercase
  // `password`. Both spellings are read so a hand-rolled curl still works.
  final map = payload is Map ? payload : const <String, dynamic>{};
  final name = '${map['Name'] ?? map['name'] ?? ''}'.trim();
  final password = '${map['password'] ?? map['Password'] ?? ''}';

  if (name.isEmpty || password.isEmpty) {
    return Response.json(
      statusCode: HttpStatus.unauthorized,
      body: {'message': 'Enter your username and password.'},
    );
  }

  final account = _accounts[name.toLowerCase()];
  // The password is not checked — see the note above. The message still speaks
  // of both halves, because the client shows it verbatim and naming the
  // username alone would tell an attacker which ones exist.
  if (account == null) {
    return Response.json(
      statusCode: HttpStatus.unauthorized,
      body: {'message': 'That username and password did not match.'},
    );
  }

  return Response.json(
    body: {
      // Not a real JWT — nothing here validates it. It exists so the client's
      // `Authorization: Bearer …` header has something to carry, and so the
      // request log shows whether the app actually sent one.
      'token': 'local-${DateTime.now().millisecondsSinceEpoch}',
      'refreshToken': 'local-refresh',
      'user': {
        'id': 1,
        'name': _titleCase(name),
        'employeeCode': account.employeeCode,
        'email': '$name@example.internal',
        'location': 'Mumbai',
        'locationCode': 'MUM',
        'city': 'Mumbai',
        'contactNumber': '',
        'role': account.role,
        'profileDescription': account.role,
        'profileId': account.id,
        'menuList': [
          for (final (index, menu) in _allMenus.indexed)
            {
              'id': index + 1,
              'menuName': menu,
              'profileId': account.id,
              'isActive': account.menus.contains(menu) ? 'Y' : 'N',
            },
        ],
      },
    },
  );
}

/// Every screen the client knows about, sent whether or not it is allowed —
/// the real service reports the closed ones too, as `isActive: "N"`.
const _allMenus = ['Dashboard', 'MIS', 'Upload Document'];

typedef _Account = ({
  String id,
  String role,

  /// Whose records these are, matched against the case's own `maker` or
  /// `checker` column when the dashboard reads its queue.
  String employeeCode,
  List<String> menus,
});

/// Keyed on the lowercased username, so casing at the sign-in form does not
/// decide whether someone gets in.
const _accounts = <String, _Account>{
  // The health-check side: verifies records and ticks them off.
  'maker': (
    id: 'P1',
    role: 'Maker',
    // A code the seed data names in the maker queue, so a fresh checkout opens
    // on rows rather than on an empty grid. A database that has been worked in
    // may hold none: verifying a case is what moves it out of this queue.
    employeeCode: 'OFF807292',
    menus: ['Dashboard', 'MIS', 'Upload Document'],
  ),
  // The CPU side: reads, comments, and routes a record onward.
  'checker': (
    id: 'P2',
    role: 'Checker',
    employeeCode: 'r14878',
    menus: ['Dashboard', 'MIS', 'Upload Document'],
  ),
};

String _titleCase(String name) => name
    .replaceAll('.', ' ')
    .split(' ')
    .where((word) => word.isNotEmpty)
    .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
    .join(' ');
