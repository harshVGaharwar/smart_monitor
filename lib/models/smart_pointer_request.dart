import 'login_response.dart';

/// The query of `GET /get-smartpointer` — whose queue to read.
///
/// Both values come off the sign-in response and neither is optional: the pair
/// is what makes the call a queue rather than the whole table. The role names
/// the side of the handover the user works, the employee code narrows that to
/// the records that are theirs, and the server answers with nothing else. The
/// dashboard therefore shows what it is given — there is no second filter on
/// the client, and a row this reader may not open never reaches the app.
///
/// The key casing is the service's, as in [LoginRequest] — mirrored rather
/// than tidied, because the server matches on it.
class SmartPointerRequest {
  /// Whose records to read, matched against the case's own `maker` or
  /// `checker` column — whichever [role] answers for.
  final String employeeCode;

  /// The signed-in template, verbatim as the service sent it. Read forgivingly
  /// at the other end, so its casing does not decide the result.
  final String role;

  const SmartPointerRequest({required this.employeeCode, required this.role});

  /// The queue belonging to [user], straight off the session.
  factory SmartPointerRequest.forUser(LoginUser user) =>
      SmartPointerRequest(employeeCode: user.employeeCode, role: user.role);

  /// The query string. Not `toJson` — these ride on the URL, and `ApiClient`
  /// takes them as a map.
  Map<String, dynamic> toQuery() => {
    'employeeCode': employeeCode,
    'role': role,
  };
}
