import 'package:alist_player/constants/app_constants.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 统一管理登录态相关信息，避免在各个界面重复读取偏好。
class UserIdentity {
  const UserIdentity({
    this.username,
    this.userId,
    this.legacyUserId,
  });

  final String? username;
  final int? userId;
  final int? legacyUserId;

  int? get effectiveUserId => userId ?? legacyUserId;
}

class UserSession {
  const UserSession._();

  static const String _usernameKey = 'current_username';

  static Future<UserIdentity> loadIdentity() async {
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString(_usernameKey);
    final storedUserId = prefs.getInt(AppConstants.currentUserIdKey);
    final legacyUserId = username?.hashCode;
    return UserIdentity(
      username: username,
      userId: storedUserId,
      legacyUserId: legacyUserId,
    );
  }

  static Future<void> persistIdentity({
    required String username,
    required int userId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_usernameKey, username);
    await prefs.setInt(AppConstants.currentUserIdKey, userId);
  }

  static Future<void> clearIdentity() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_usernameKey);
    await prefs.remove(AppConstants.currentUserIdKey);
  }
}
