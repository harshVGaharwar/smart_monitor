// A scratch harness for a captured `login` response.
//
// Paste a payload into [_response], run, and read what the app made of it:
//
//     flutter test test/login_response_test.dart
//
// It passes either way — a refused sign-in is printed rather than thrown, so
// any response can be dropped in without rewriting an assertion. The real
// assertions live in `case_api_test.dart` and `sidebar_menu_test.dart`.
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smart_monitor/core/api_client.dart';
import 'package:smart_monitor/services/case_api.dart';
import 'package:smart_monitor/widgets/app_sidebar.dart';

// ---------------------------------------------------------------------------
// PASTE YOUR RESPONSE HERE
// ---------------------------------------------------------------------------
const _response = '''
{
    "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.local",
    "refreshToken": "local-refresh",
    "user": {
        "id": 1,
        "name": "Ninad Thakur",
        "employeeCode": "n2346",
        "email": "ninad.thakur@example.internal",
        "location": "Mumbai",
        "locationCode": "MUM",
        "city": "Mumbai",
        "contactNumber": "",
        "role": "Supervisor",
        "profileDescription": "Supervisor",
        "profileId": "P1",
        "menuList": [
            { "id": 1, "menuName": "Dashboard", "profileId": "P1", "isActive": "Y" },
            { "id": 2, "menuName": "MIS", "profileId": "P1", "isActive": "Y" },
            { "id": 3, "menuName": "Upload Document", "profileId": "P1", "isActive": "Y" }
        ]
    }
}
''';

void main() {
  test('the pasted response, as the app reads it', () async {
    final api = Api(
      ApiClient(client: MockClient((_) async => http.Response(_response, 200))),
    );

    try {
      final session = await api.login(name: 'ninad.thakur', password: 'x');
      final user = session.user;
      // The rail this user would actually see, which is the whole point of
      // reading the menu at all.
      final rail = [for (final item in navItemsFor(user.menuList)) item.label];

      // ignore: avoid_print
      print('''

  token     ${session.token.isEmpty ? '(none)' : '${session.token.substring(0, session.token.length.clamp(0, 12))}…'}
  name      ${user.name}
  role      ${user.role}
  profile   ${user.profileId}
  rail      ${rail.join(' · ')}
''');
      for (final menu in user.menuList) {
        // ignore: avoid_print
        print('  ${menu.isEnabled ? 'Y' : 'N'}  ${menu.menuName}');
      }
      // ignore: avoid_print
      print('');
    } on ApiException catch (e) {
      // Printed, not rethrown: a refused sign-in is worth pasting in too.
      // ignore: avoid_print
      print('\n  rejected  ${e.message}\n');
    }
  });
}
