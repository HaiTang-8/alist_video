import 'package:alist_player/models/historical_record.dart';
import 'package:flutter/material.dart';

/// 管理员全局概览统计，统一描述播放与互动高阶指标。
class AdminWatchSummary {
  const AdminWatchSummary({
    required this.totalSessions,
    required this.uniqueUsers,
    required this.uniqueVideos,
    required this.totalWatchDuration,
    required this.averageCompletion,
    required this.sessionsLast24h,
    required this.lastActivityAt,
  });

  final int totalSessions;
  final int uniqueUsers;
  final int uniqueVideos;
  final Duration totalWatchDuration;
  final double averageCompletion;
  final int sessionsLast24h;
  final DateTime? lastActivityAt;

  double get totalWatchHours =>
      totalWatchDuration.inSeconds / Duration.secondsPerHour;
}

/// TOP 用户榜单摘要。
class UserActivitySummary {
  const UserActivitySummary({
    required this.userId,
    required this.displayName,
    required this.sessionCount,
    required this.uniqueVideos,
    required this.totalWatchDuration,
    required this.averageCompletion,
    required this.lastActiveAt,
  });

  final int userId;
  final String displayName;
  final int sessionCount;
  final int uniqueVideos;
  final Duration totalWatchDuration;
  final double averageCompletion;
  final DateTime? lastActiveAt;
}

/// 目录热度信息，帮助管理员聚焦热门内容目录。
class DirectoryHeatEntry {
  const DirectoryHeatEntry({
    required this.directoryPath,
    required this.sessionCount,
    required this.uniqueUsers,
    required this.totalWatchDuration,
    required this.averageCompletion,
    required this.lastActiveAt,
  });

  final String directoryPath;
  final int sessionCount;
  final int uniqueUsers;
  final Duration totalWatchDuration;
  final double averageCompletion;
  final DateTime? lastActiveAt;
}

/// 日维度活跃度，用于渲染折线/柱状概览。
class DailyActivityPoint {
  const DailyActivityPoint({
    required this.day,
    required this.sessionCount,
    required this.uniqueUsers,
    required this.watchDuration,
  });

  final DateTime day;
  final int sessionCount;
  final int uniqueUsers;
  final Duration watchDuration;
}

/// 收藏使用概览。
class FavoriteStatSummary {
  const FavoriteStatSummary({
    required this.totalFavorites,
    required this.uniqueUsers,
    required this.lastFavoritedAt,
    required this.topDirectories,
  });

  final int totalFavorites;
  final int uniqueUsers;
  final DateTime? lastFavoritedAt;
  final List<FavoriteDirectoryStat> topDirectories;
}

/// 收藏目录排名。
class FavoriteDirectoryStat {
  const FavoriteDirectoryStat({
    required this.path,
    required this.bookmarkCount,
    required this.uniqueUsers,
    required this.lastFavoritedAt,
  });

  final String path;
  final int bookmarkCount;
  final int uniqueUsers;
  final DateTime? lastFavoritedAt;
}

/// 单用户目录热度。
class UserDirectoryStat {
  const UserDirectoryStat({
    required this.directoryPath,
    required this.sessionCount,
    required this.totalWatchDuration,
    required this.lastActiveAt,
  });

  final String directoryPath;
  final int sessionCount;
  final Duration totalWatchDuration;
  final DateTime? lastActiveAt;
}

/// 单用户收藏记录。
class UserFavoriteEntry {
  const UserFavoriteEntry({
    required this.path,
    required this.createdAt,
  });

  final String path;
  final DateTime? createdAt;
}

/// 单用户概要统计。
class UserDetailOverview {
  const UserDetailOverview({
    required this.userId,
    required this.displayName,
    required this.sessionCount,
    required this.uniqueVideos,
    required this.totalWatchDuration,
    required this.averageCompletion,
    required this.sessionsLast24h,
    required this.firstWatchAt,
    required this.lastWatchAt,
    required this.favoriteCount,
  });

  final int userId;
  final String displayName;
  final int sessionCount;
  final int uniqueVideos;
  final Duration totalWatchDuration;
  final double averageCompletion;
  final int sessionsLast24h;
  final DateTime? firstWatchAt;
  final DateTime? lastWatchAt;
  final int favoriteCount;
}

/// 单用户仪表盘数据聚合。
class UserDetailDashboardData {
  const UserDetailDashboardData({
    required this.overview,
    required this.topDirectories,
    required this.favoriteDirectories,
    required this.recentRecords,
  });

  final UserDetailOverview overview;
  final List<UserDirectoryStat> topDirectories;
  final List<UserFavoriteEntry> favoriteDirectories;
  final List<HistoricalRecord> recentRecords;
}

/// 统一聚合后的仪表盘数据载体，便于一次性刷新。
class AdminDashboardData {
  const AdminDashboardData({
    required this.summary,
    required this.topUsers,
    required this.directoryHeat,
    required this.dailyActivity,
    required this.favoriteSummary,
  });

  final AdminWatchSummary summary;
  final List<UserActivitySummary> topUsers;
  final List<DirectoryHeatEntry> directoryHeat;
  final List<DailyActivityPoint> dailyActivity;
  final FavoriteStatSummary favoriteSummary;
}

/// 用于在 UI 中复用柔性颜色，没有业务含义。
class AdminDashboardPalette {
  const AdminDashboardPalette._();

  static const List<Color> kpiCardColors = <Color>[
    Color(0xFF4C6EF5),
    Color(0xFF845EF7),
    Color(0xFF2FB344),
    Color(0xFF228BE6),
    Color(0xFFF5972F),
  ];
}
