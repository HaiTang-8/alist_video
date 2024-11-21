class HashInfo {
  String? sha1;

  HashInfo({this.sha1});

  factory HashInfo.fromJson(Map<String, dynamic> json) => HashInfo(
        sha1: json['sha1'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'sha1': sha1,
      };
}
