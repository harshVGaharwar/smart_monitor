/// The body of `POST /login` — the session, and who it belongs to.
///
/// Raw rather than enveloped: this endpoint answers `{token, refreshToken,
/// user}` at the top level, unlike the three case endpoints which wrap
/// everything in `ApiEnvelope`. A wrong password arrives as a non-2xx, so
/// there is no success flag to read here.
///
/// Every field is read defensively — a missing key yields a default rather
/// than throwing — the same rule the case models follow.
class LoginResponse {
  final String token;
  final String refreshToken;
  final LoginUser user;

  const LoginResponse({
    required this.token,
    required this.refreshToken,
    required this.user,
  });

  factory LoginResponse.fromJson(Map<String, dynamic> json) {
    return LoginResponse(
      token: json['token'] ?? '',
      refreshToken: json['refreshToken'] ?? '',
      user: LoginUser.fromJson(json['user'] ?? {}),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'token': token,
      'refreshToken': refreshToken,
      'user': user.toJson(),
    };
  }
}

/// The signed-in user, as the service describes them.
///
/// [menuList] is what decides which screens they see — see `navItemsFor` in
/// `widgets/app_sidebar.dart`. [role] is carried for display; the menu, not the
/// role name, is the authority on access.
class LoginUser {
  final int id;
  final String name;
  final String employeeCode;
  final String email;
  final String location;
  final String locationCode;
  final String city;
  final String contactNumber;
  final String role;
  final String profileDescription;
  final String profileId;

  final List<MenuPermission> menuList;

  LoginUser({
    this.id = 0,
    this.name = '',
    this.employeeCode = '',
    this.email = '',
    this.location = '',
    this.locationCode = '',
    this.city = '',
    this.contactNumber = '',
    this.role = '',
    this.profileDescription = '',
    this.profileId = '',
    this.menuList = const [],
  });

  factory LoginUser.fromJson(Map<String, dynamic> json) {
    final menuJson = json['menuList'] ?? [];

    return LoginUser(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      employeeCode: json['employeeCode'] ?? '',
      email: json['email'] ?? '',
      location: json['location'] ?? '',
      locationCode: json['locationCode'] ?? '',
      city: json['city'] ?? '',
      contactNumber: json['contactNumber'] ?? '',
      role: json['role'] ?? '',
      profileDescription: json['profileDescription'] ?? '',
      profileId: json['profileId'] ?? '',
      menuList: [
        if (menuJson is List)
          for (final entry in menuJson)
            if (entry is Map<String, dynamic>) MenuPermission.fromJson(entry),
      ],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'employeeCode': employeeCode,
      'email': email,
      'location': location,
      'locationCode': locationCode,
      'city': city,
      'contactNumber': contactNumber,
      'role': role,
      'profileDescription': profileDescription,
      'profileId': profileId,
      'menuList': menuList.map((m) => m.toJson()).toList(),
    };
  }
}

/// One screen this user's profile may or may not open.
class MenuPermission {
  final int id;
  final String menuName;
  final String profileId;
  final String isActive;

  const MenuPermission({
    required this.id,
    required this.menuName,
    required this.profileId,
    required this.isActive,
  });

  factory MenuPermission.fromJson(Map<String, dynamic> json) {
    return MenuPermission(
      id: json['id'] ?? 0,
      menuName: json['menuName'] ?? '',
      profileId: json['profileId'] ?? '',
      isActive: json['isActive'] ?? 'N',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'menuName': menuName,
      'profileId': profileId,
      'isActive': isActive,
    };
  }

  /// Anything other than a `Y` is a no — an absent flag defaults to `N`.
  bool get isEnabled => isActive.toUpperCase() == 'Y';
}
