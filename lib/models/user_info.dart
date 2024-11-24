class UserInfo {
  final int id;
  final String username;
  final String basePath;
  final int role;
  final bool disabled;
  final int permission;
  final String ssoId;
  final bool otp;

  UserInfo({
    required this.id,
    required this.username,
    required this.basePath,
    required this.role,
    required this.disabled,
    required this.permission,
    required this.ssoId,
    required this.otp,
  });

  factory UserInfo.fromJson(Map<String, dynamic> json) {
    return UserInfo(
      id: json['id'],
      username: json['username'],
      basePath: json['base_path'],
      role: json['role'],
      disabled: json['disabled'],
      permission: json['permission'],
      ssoId: json['sso_id'],
      otp: json['otp'],
    );
  }
}
