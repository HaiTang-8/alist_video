import 'package:alist_player/models/admin_dashboard_metrics.dart';
import 'package:alist_player/utils/db.dart';
import 'package:alist_player/utils/logger.dart';

/// 负责拼装管理员仪表盘所需的全部数据，避免界面层分散处理多个Future。
class AdminAnalyticsService {
  AdminAnalyticsService({
    DatabaseHelper? databaseHelper,
    AppLogger? logger,
  })  : _db = databaseHelper ?? DatabaseHelper.instance,
        _logger = logger ?? AppLogger();

  final DatabaseHelper _db;
  final AppLogger _logger;

  Future<AdminDashboardData> loadDashboardData({
    int userLimit = 6,
    int directoryLimit = 6,
    int trendDays = 8,
    int favoriteLimit = 5,
  }) async {
    try {
      final results = await Future.wait<dynamic>([
        _db.getAdminWatchSummary(),
        _db.getTopUserActivities(limit: userLimit),
        _db.getDirectoryHeatEntries(limit: directoryLimit),
        _db.getDailyActivityPoints(days: trendDays),
        _db.getFavoriteStatSummary(limit: favoriteLimit),
      ]);

      return AdminDashboardData(
        summary: results[0] as AdminWatchSummary,
        topUsers: results[1] as List<UserActivitySummary>,
        directoryHeat: results[2] as List<DirectoryHeatEntry>,
        dailyActivity: results[3] as List<DailyActivityPoint>,
        favoriteSummary: results[4] as FavoriteStatSummary,
      );
    } catch (e, stack) {
      await _logger.error(
        'AdminAnalyticsService',
        'loadDashboardData failed',
        e,
        stack,
      );
      rethrow;
    }
  }

  /// 加载指定用户的明细仪表盘。
  Future<UserDetailDashboardData> loadUserDetail({
    required int userId,
    int recentLimit = 30,
    int directoryLimit = 6,
    int favoriteLimit = 6,
  }) async {
    try {
      return await _db.getUserDetailDashboard(
        userId: userId,
        recentLimit: recentLimit,
        directoryLimit: directoryLimit,
        favoriteLimit: favoriteLimit,
      );
    } catch (e, stack) {
      await _logger.error(
        'AdminAnalyticsService',
        'loadUserDetail failed for $userId',
        e,
        stack,
      );
      rethrow;
    }
  }
}
