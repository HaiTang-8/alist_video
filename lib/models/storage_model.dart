class StorageModel {
  final int id;
  final String mountPath;
  final int order;
  final String driver;
  final int cacheExpiration;
  final String status;
  final String addition;
  final String remark;
  final String modified;
  final bool disabled;
  final bool enableSign;
  final String orderBy;
  final String orderDirection;
  final String extractFolder;
  final bool webProxy;
  final String webdavPolicy;
  final String downProxyUrl;

  StorageModel({
    required this.id,
    required this.mountPath,
    required this.order,
    required this.driver,
    required this.cacheExpiration,
    required this.status,
    required this.addition,
    required this.remark,
    required this.modified,
    required this.disabled,
    required this.enableSign,
    required this.orderBy,
    required this.orderDirection,
    required this.extractFolder,
    required this.webProxy,
    required this.webdavPolicy,
    required this.downProxyUrl,
  });

  factory StorageModel.fromJson(Map<String, dynamic> json) {
    return StorageModel(
      id: json['id'] ?? 0,
      mountPath: json['mount_path'] ?? '',
      order: json['order'] ?? 0,
      driver: json['driver'] ?? '',
      cacheExpiration: json['cache_expiration'] ?? 0,
      status: json['status'] ?? '',
      addition: json['addition'] ?? '',
      remark: json['remark'] ?? '',
      modified: json['modified'] ?? '',
      disabled: json['disabled'] ?? false,
      enableSign: json['enable_sign'] ?? false,
      orderBy: json['order_by'] ?? '',
      orderDirection: json['order_direction'] ?? '',
      extractFolder: json['extract_folder'] ?? '',
      webProxy: json['web_proxy'] ?? false,
      webdavPolicy: json['webdav_policy'] ?? '',
      downProxyUrl: json['down_proxy_url'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'mount_path': mountPath,
      'order': order,
      'driver': driver,
      'status': status,
      'addition': addition,
      'remark': remark,
      'modified': modified,
      'disabled': disabled,
    };
  }
}
