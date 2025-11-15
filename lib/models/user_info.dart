class UserInfo {
  final int id;
  final String username;
  final String basePath;
  final int role;
  final bool disabled;
  final int permission;
  final String ssoId;
  final bool otp;

  const UserInfo({
    required this.id,
    required this.username,
    required this.basePath,
    required this.role,
    required this.disabled,
    required this.permission,
    required this.ssoId,
    required this.otp,
  });

  static bool _asBool(dynamic value) {
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    if (value is String) {
      final normalized = value.toLowerCase();
      return normalized == 'true' || normalized == '1';
    }
    return false;
  }

  factory UserInfo.fromJson(Map<String, dynamic> json) {
    return UserInfo(
      id: json['id'] as int? ?? 0,
      username: json['username'] as String? ?? '',
      basePath: json['base_path'] as String? ?? '/',
      role: json['role'] as int? ?? 0,
      disabled: _asBool(json['disabled']),
      permission: json['permission'] as int? ?? 0,
      ssoId: json['sso_id'] as String? ?? '',
      otp: _asBool(json['otp']),
    );
  }
}
