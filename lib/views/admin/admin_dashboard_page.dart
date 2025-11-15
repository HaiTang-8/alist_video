import 'package:alist_player/apis/admin_user_api.dart';
import 'package:alist_player/models/admin_dashboard_metrics.dart';
import 'package:alist_player/models/historical_record.dart';
import 'package:alist_player/models/user_info.dart';
import 'package:alist_player/services/admin_analytics_service.dart';
import 'package:alist_player/utils/logger.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage>
    with AutomaticKeepAliveClientMixin {
  final AdminAnalyticsService _analyticsService = AdminAnalyticsService();
  final NumberFormat _numberFormat = NumberFormat.compact(locale: 'zh_CN');
  bool _isLoading = false;
  AdminDashboardData? _data;
  String? _errorMessage;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  Future<void> _loadDashboard() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final data = await _analyticsService.loadDashboardData(
        userLimit: 8,
        directoryLimit: 8,
        trendDays: 10,
      );
      if (!mounted) return;
      setState(() {
        _data = data;
      });
    } catch (e, stack) {
      await AppLogger().error(
        'AdminDashboardPage',
        'loadDashboard failed',
        e,
        stack,
      );
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('全局运营面板'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新数据',
            onPressed: _isLoading ? null : _loadDashboard,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadDashboard,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final horizontalPadding = constraints.maxWidth > 1200
                ? (constraints.maxWidth - 1000) / 2
                : 16.0;
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                24,
                horizontalPadding,
                48,
              ),
              children: [
                if (_isLoading && _data == null)
                  const Padding(
                    padding: EdgeInsets.only(top: 120),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_errorMessage != null)
                  _buildErrorPlaceholder(_errorMessage!)
                else if (_data != null) ...[
                  _buildSummarySection(_data!.summary),
                  const SizedBox(height: 24),
                  _buildTrendSection(_data!.dailyActivity),
                  const SizedBox(height: 24),
                  _buildUserLeaderboard(_data!.topUsers),
                  const SizedBox(height: 24),
                  _buildDirectoryHeat(_data!.directoryHeat),
                  const SizedBox(height: 24),
                  _buildFavoriteOverview(_data!.favoriteSummary),
                ] else
                  _buildErrorPlaceholder('暂无可用数据'),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildErrorPlaceholder(String message) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: SelectableText.rich(
          TextSpan(
            text: '加载失败\n',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.bold,
                ),
            children: [
              TextSpan(
                text: message,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummarySection(AdminWatchSummary summary) {
    final cards = [
      _MetricCardData(
        title: '累计观看',
        value: _numberFormat.format(summary.totalSessions),
        subtitle: '总记录',
        color: AdminDashboardPalette.kpiCardColors[0],
      ),
      _MetricCardData(
        title: '活跃用户',
        value: _numberFormat.format(summary.uniqueUsers),
        subtitle: '${summary.sessionsLast24h} 条记录 / 24h',
        color: AdminDashboardPalette.kpiCardColors[1],
      ),
      _MetricCardData(
        title: '观看总时长',
        value: _formatDuration(summary.totalWatchDuration),
        subtitle:
            '平均完成度 ${(summary.averageCompletion * 100).toStringAsFixed(1)}%',
        color: AdminDashboardPalette.kpiCardColors[2],
      ),
      _MetricCardData(
        title: '覆盖内容',
        value: _numberFormat.format(summary.uniqueVideos),
        subtitle: '最近活跃 ${_formatDate(summary.lastActivityAt)}',
        color: AdminDashboardPalette.kpiCardColors[3],
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 640;
        final cardWidth =
            isWide ? (constraints.maxWidth - 16) / 2 : constraints.maxWidth;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            for (final data in cards)
              SizedBox(
                width: cardWidth,
                child: _buildMetricCard(data),
              ),
          ],
        );
      },
    );
  }

  Widget _buildMetricCard(_MetricCardData data) {
    final theme = Theme.of(context);
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              data.title,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Text(
              data.value,
              style: theme.textTheme.displaySmall?.copyWith(
                color: data.color,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              data.subtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrendSection(List<DailyActivityPoint> points) {
    final theme = Theme.of(context);
    if (points.isEmpty) {
      return _buildEmptyCard('最近没有新的观影记录');
    }
    final maxSessions =
        points.map((e) => e.sessionCount).fold<int>(0, (prev, value) {
      return value > prev ? value : prev;
    });

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '近${points.length}日活跃',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            for (final point in points)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _formatShortDate(point.day),
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                        Text(
                          '${point.sessionCount} 次 | ${_formatDuration(point.watchDuration)}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    LinearProgressIndicator(
                      value: maxSessions == 0
                          ? 0
                          : point.sessionCount / maxSessions,
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _openUserDetail(UserActivitySummary user) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _UserDetailSheet(
        userSummary: user,
        analyticsService: _analyticsService,
      ),
    );
  }

  Widget _buildUserLeaderboard(List<UserActivitySummary> users) {
    if (users.isEmpty) {
      return _buildEmptyCard('暂无用户观看记录');
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '观影活跃用户',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            ...users.map((user) {
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: AdminDashboardPalette
                      .kpiCardColors[user.userId % 5]
                      .withOpacity(0.15),
                  child: Text(
                    user.userId.toString(),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                title: Text(user.displayName),
                subtitle: Text(
                  '会话 ${user.sessionCount} · 覆盖 ${user.uniqueVideos} · 完成度 ${(user.averageCompletion * 100).toStringAsFixed(1)}%',
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _formatDuration(user.totalWatchDuration),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '最近 ${_formatDate(user.lastActiveAt)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                onTap: () => _openUserDetail(user),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildDirectoryHeat(List<DirectoryHeatEntry> directories) {
    if (directories.isEmpty) {
      return _buildEmptyCard('暂无目录访问数据');
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '热门内容目录',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            ...directories.map((entry) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            entry.directoryPath,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Text('用户 ${entry.uniqueUsers}'),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '记录 ${entry.sessionCount} · 完成度 ${(entry.averageCompletion * 100).toStringAsFixed(1)}% · 最近 ${_formatDate(entry.lastActiveAt)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 6),
                    Container(
                      height: 4,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AdminDashboardPalette.kpiCardColors[4],
                            AdminDashboardPalette.kpiCardColors[3],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildFavoriteOverview(FavoriteStatSummary summary) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '操作与收藏概览',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '共 ${summary.totalFavorites} 条收藏，${summary.uniqueUsers} 位用户参与，最近 ${_formatDate(summary.lastFavoritedAt)}',
            ),
            const SizedBox(height: 16),
            if (summary.topDirectories.isEmpty)
              _buildEmptyInnerMessage('暂无收藏目录记录')
            else
              ...summary.topDirectories.map((dir) {
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.bookmarks_outlined),
                  title: Text(dir.path),
                  subtitle: Text(
                    '${dir.bookmarkCount} 次收藏 · ${dir.uniqueUsers} 位用户 · 最近 ${_formatDate(dir.lastFavoritedAt)}',
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyCard(String message) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: _buildEmptyInnerMessage(message),
      ),
    );
  }

  Widget _buildEmptyInnerMessage(String message) {
    return Row(
      children: [
        const Icon(Icons.info_outline),
        const SizedBox(width: 8),
        Expanded(child: Text(message)),
      ],
    );
  }

  String _formatDuration(Duration duration) {
    if (duration.inMinutes == 0) {
      return '${duration.inSeconds}s';
    }
    if (duration.inHours == 0) {
      return '${duration.inMinutes}min';
    }
    return '${duration.inHours}h${duration.inMinutes.remainder(60)}m';
  }

  String _formatDate(DateTime? dateTime) {
    if (dateTime == null) {
      return '暂无';
    }
    final local = dateTime.toLocal();
    return DateFormat('MM-dd HH:mm').format(local);
  }

  String _formatShortDate(DateTime dateTime) {
    return DateFormat('MM/dd').format(dateTime.toLocal());
  }
}

class _MetricCardData {
  const _MetricCardData({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.color,
  });

  final String title;
  final String value;
  final String subtitle;
  final Color color;
}

class _UserDetailSheet extends StatefulWidget {
  const _UserDetailSheet({
    required this.userSummary,
    required this.analyticsService,
  });

  final UserActivitySummary userSummary;
  final AdminAnalyticsService analyticsService;

  @override
  State<_UserDetailSheet> createState() => _UserDetailSheetState();
}

class _UserDetailSheetState extends State<_UserDetailSheet> {
  UserDetailDashboardData? _data;
  UserInfo? _userProfile;
  bool _isLoading = false;
  bool _isUserProfileLoading = false;
  String? _errorMessage;
  String? _userProfileError;
  final AdminUserApi _adminUserApi = AdminUserApi();

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _isUserProfileLoading = true;
      _userProfileError = null;
    });
    try {
      final detailFuture = widget.analyticsService.loadUserDetail(
        userId: widget.userSummary.userId,
        recentLimit: 30,
      );
      final profileFuture = _adminUserApi.getUserById(
        widget.userSummary.userId,
      );

      final detail = await detailFuture;
      if (!mounted) return;
      setState(() {
        _data = detail;
        _isLoading = false;
      });

      final profile = await profileFuture;
      if (!mounted) return;
      setState(() {
        _userProfile = profile;
        if (profile == null) {
          _userProfileError = '远端未找到该用户，可能是本地记录残留';
        }
        _isUserProfileLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (_data == null) {
          _errorMessage = e.toString();
        }
        if (_userProfile == null) {
          _userProfileError = e.toString();
        }
        _isLoading = false;
        _isUserProfileLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return SafeArea(
      child: AnimatedPadding(
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        duration: const Duration(milliseconds: 180),
        child: SizedBox(
          height: media.size.height * 0.85,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Text(
                      '用户 #${widget.userSummary.userId} 详情',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: '刷新',
                      onPressed: _isLoading ? null : _loadDetail,
                      icon: const Icon(Icons.refresh),
                    ),
                    IconButton(
                      tooltip: '关闭',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(child: _buildBody(context)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_isLoading && _data == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SelectableText.rich(
            TextSpan(
              text: '加载失败\n',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
              children: [
                TextSpan(
                  text: _errorMessage,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (_data == null) {
      return const SizedBox.shrink();
    }

    final detail = _data!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      children: [
        _buildUserProfileSection(),
        const SizedBox(height: 16),
        _buildOverviewSection(detail.overview),
        const SizedBox(height: 16),
        _buildDirectorySection(detail.topDirectories),
        const SizedBox(height: 16),
        _buildFavoriteSection(detail.favoriteDirectories),
        const SizedBox(height: 16),
        _buildHistorySection(detail.recentRecords),
      ],
    );
  }

  Widget _buildOverviewSection(UserDetailOverview overview) {
    final tiles = <Widget>[
      _buildStatTile('会话数', overview.sessionCount.toString()),
      _buildStatTile('覆盖视频', overview.uniqueVideos.toString()),
      _buildStatTile('总时长', _formatDuration(overview.totalWatchDuration)),
      _buildStatTile(
        '平均完成度',
        '${(overview.averageCompletion * 100).toStringAsFixed(1)}%',
      ),
      _buildStatTile('24h 新增', overview.sessionsLast24h.toString()),
      _buildStatTile('收藏', overview.favoriteCount.toString()),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              overview.displayName,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: tiles,
            ),
            const SizedBox(height: 12),
            Text(
              '首次观看：${_formatDate(overview.firstWatchAt)}  ·  最近活动：${_formatDate(overview.lastWatchAt)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatTile(String label, String value) {
    return Container(
      width: 120,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildDirectorySection(List<UserDirectoryStat> directories) {
    if (directories.isEmpty) {
      return _buildEmptyMessage('暂无目录热度');
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '常看目录',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            ...directories.map(
              (dir) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(dir.directoryPath),
                subtitle: Text(
                  '记录 ${dir.sessionCount} · 总时长 ${_formatDuration(dir.totalWatchDuration)} · 最近 ${_formatDate(dir.lastActiveAt)}',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFavoriteSection(List<UserFavoriteEntry> favorites) {
    if (favorites.isEmpty) {
      return _buildEmptyMessage('暂无收藏记录');
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '最近收藏',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            ...favorites.map(
              (fav) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.bookmark_added_outlined),
                title: Text(fav.path),
                subtitle: Text('时间 ${_formatDate(fav.createdAt)}'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistorySection(List<HistoricalRecord> records) {
    if (records.isEmpty) {
      return _buildEmptyMessage('暂无最近观看记录');
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '最近观看',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemBuilder: (context, index) {
                final record = records[index];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(record.videoName),
                  subtitle: Text(
                    '${record.videoPath}/${record.videoName}\n进度 ${record.progressText} · 更新时间 ${_formatDate(record.changeTime)}',
                  ),
                  trailing: Text(_formatDuration(
                    Duration(seconds: record.videoSeek),
                  )),
                );
              },
              separatorBuilder: (_, __) => const Divider(),
              itemCount: records.length,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyMessage(String message) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            const Icon(Icons.info_outline),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    if (duration.inMinutes == 0) {
      return '${duration.inSeconds}s';
    }
    if (duration.inHours == 0) {
      return '${duration.inMinutes}min';
    }
    return '${duration.inHours}h${duration.inMinutes.remainder(60)}m';
  }

  String _formatDate(DateTime? dateTime) {
    if (dateTime == null) {
      return '暂无';
    }
    return DateFormat('MM-dd HH:mm').format(dateTime.toLocal());
  }

  Widget _buildUserProfileSection() {
    if (_isUserProfileLoading) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (_userProfileError != null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: SelectableText.rich(
            TextSpan(
              text: '获取用户信息失败\n',
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.bold,
              ),
              children: [
                TextSpan(
                  text: _userProfileError,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
      );
    }

    final info = _userProfile;
    if (info == null) {
      return const SizedBox.shrink();
    }

    Chip buildStatusChip(String label, bool enabled) => Chip(
          label: Text(label),
          backgroundColor: enabled
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.errorContainer,
          labelStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: enabled
                    ? Theme.of(context).colorScheme.onPrimaryContainer
                    : Theme.of(context).colorScheme.onErrorContainer,
              ),
        );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '账户资料',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _buildProfileTile('用户 ID', info.id.toString()),
                _buildProfileTile('用户名', info.username),
                _buildProfileTile('角色', info.role.toString()),
                _buildProfileTile('基础路径', info.basePath),
                _buildProfileTile('权限值', info.permission.toString()),
                _buildProfileTile('SSO ID', info.ssoId.isEmpty ? '-' : info.ssoId),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              children: [
                buildStatusChip('启用状态', !info.disabled),
                buildStatusChip('OTP', info.otp),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileTile(String label, String value) {
    return Container(
      constraints: const BoxConstraints(minWidth: 120),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

}
