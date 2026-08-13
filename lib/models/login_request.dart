/// The body of `POST /login` — the credentials, in the shape the service wants.
///
/// Only [name] and [password] are ever filled in by the sign-in form. The rest
/// are part of the contract and go out empty: the service reads them back off
/// the stored profile, and omitting a key it expects is riskier than sending a
/// blank one.
///
/// The key casing in [toJson] is the service's, not this app's — `Id`, `Name`,
/// `LOCATIONCODE` and a lowercase `password` all sit side by side. It is
/// mirrored exactly rather than tidied, because the server matches on it.
class LoginRequest {
  final int id;
  final String name;
  final String employeeCode;
  final String email;
  final String password;
  final String location;
  final String locationCode;
  final String city;
  final String department;
  final String contactNumber;
  final String role;
  final String ipAddress;
  final String profileDescription;
  final String profileId;

  // Static employee code until dynamic resolution is implemented.
  static const String _staticEmployeeCode = 'n2346';

  const LoginRequest({
    required this.name,
    required this.password,
    this.id = 0,
    this.employeeCode = _staticEmployeeCode,
    this.email = '',
    this.location = '',
    this.locationCode = '',
    this.city = '',
    this.department = '',
    this.contactNumber = '',
    this.role = '',
    this.ipAddress = '',
    this.profileDescription = '',
    this.profileId = '',
  });

  Map<String, dynamic> toJson() => {
    'Id': id,
    'Name': name,
    'EmployeeCode': employeeCode,
    'Email': email,
    'password': password,
    'Location': location,
    'LOCATIONCODE': locationCode,
    'City': city,
    'Department': department,
    'ContactNumber': contactNumber,
    'Role': role,
    'IPAddress': ipAddress,
    'ProfileDescription': profileDescription,
    'ProfileId': profileId,
  };
}
