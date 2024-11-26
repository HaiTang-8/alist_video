class AppConstants {
  // 数据库配置
  static const String dbHost = '81.68.250.223';
  static const String dbName = 'alist_video';
  static const String dbUser = 'alist_video';
  static const String dbPassword = '2jkxXaG3pKs4P6mX';
  static const int dbPort = 5555;

  // 数据库超时设置
  static const Duration dbConnectTimeout = Duration(seconds: 30);
  static const Duration dbQueryTimeout = Duration(seconds: 30);

  // API 相关
  static const String baseUrl = 'https://alist.tt1.top';
  static const String baseDownloadUrl = 'https://alist.tt1.top/d';
  static const Duration apiConnectTimeout = Duration(seconds: 5);
  static const Duration apiReceiveTimeout = Duration(seconds: 3);

  // HTTP Headers
  static const String contentType = 'content-type';
  static const String accept = 'accept';
  static const String authorization = 'authorization';
  static const String applicationJson = 'application/json';
  static const String defaultLanguage = 'en';
  static const String tokenPrefix = 'Bearer';
  static const String token = 'Bearer token';

  // UI 相关
  static const Duration snackBarDuration = Duration(seconds: 3);
  static const Duration countdownDuration = Duration(seconds: 1);
  static const double defaultIconSize = 20.0;
  static const double defaultFontSize = 14.0;
  static const double titleFontSize = 16.0;
  static const double smallScreenWidth = 600.0;

  // 播放器相关
  static const List<double> playbackSpeeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
  static const double defaultPlaybackSpeed = 1.0;
  static const double longPressPlaybackSpeed = 2.0;
  static const defaultItemHeight = 72.0;

  // 播放速度对话框相关
  static const double speedDialogWidth = 300.0;
  static const double speedButtonWidth = 80.0;
  static const double speedButtonHeight = 32.0;
  static const double speedDialogPadding = 20.0;
  static const double speedButtonSpacing = 8.0;
  static const double speedDialogTitleSize = 18.0;
  static const double speedButtonTextSize = 14.0;
  static const double speedIndicatorTextSize = 13.0;
  static const String normalSpeedText = '正常';
  static const String speedSuffix = 'x';

  // 透明度相关
  static const double shadowOpacity = 0.1;
  static const double hoverOpacity = 0.05;

  // 颜色相关
  static const double defaultOpacity = 0.1;
  static const double defaultBlurRadius = 1.0;
  static const double defaultSpreadRadius = 1.0;

  // 分页相关
  static const int defaultPage = 1;
  static const int defaultPerPage = 0;
  static const int defaultHistoryLimit = 50;
  static const int recentHistoryLimit = 10;

  // 播放控制相关
  static const Duration defaultShortSeekDuration =
      Duration(seconds: 2); // 默认短按快进/快退时长
  static const Duration defaultLongSeekDuration =
      Duration(seconds: 10); // 默认长按快进/快退时长
  static const int minSeekDuration = 1; // 最小快进/快退时长（秒）
  static const int maxSeekDuration = 60; // 最大快进/快退时长（秒）
  static const String shortSeekKey = 'short_seek_duration'; // 短按快进时长存储键
  static const String longSeekKey = 'long_seek_duration'; // 长按快进时长存储键

  // 播放速度相关
  static const List<double> defaultPlaybackSpeeds = [
    0.5,
    0.75,
    1.0,
    1.25,
    1.5,
    2.0
  ];
  static const String playbackSpeedsKey = 'playback_speeds'; // 存储自定义播放速度的键
  static const double minPlaybackSpeed = 0.25; // 最小播放速度
  static const double maxPlaybackSpeed = 4.0; // 最大播放速度
  static const double speedStep = 0.25; // 速度调节步长
  static const int maxPlaybackSpeedCount = 10; // 最大播放速度数量
}
