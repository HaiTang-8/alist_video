import 'hash_info.dart';

class Content {
  String? name;
  int? size;
  bool? isDir;
  String? modified;
  String? created;
  String? sign;
  String? thumb;
  int? type;
  String? hashinfo;
  HashInfo? hashInfo;

  Content({
    this.name,
    this.size,
    this.isDir,
    this.modified,
    this.created,
    this.sign,
    this.thumb,
    this.type,
    this.hashinfo,
    this.hashInfo,
  });

  factory Content.fromJson(Map<String, dynamic> json) => Content(
        name: json['name'] as String?,
        size: json['size'] as int?,
        isDir: json['is_dir'] as bool?,
        modified: json['modified'] as String?,
        created: json['created'] as String?,
        sign: json['sign'] as String?,
        thumb: json['thumb'] as String?,
        type: json['type'] as int?,
        hashinfo: json['hashinfo'] as String?,
        hashInfo: json['hash_info'] == null
            ? null
            : HashInfo.fromJson(json['hash_info'] as Map<String, dynamic>),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'size': size,
        'is_dir': isDir,
        'modified': modified,
        'created': created,
        'sign': sign,
        'thumb': thumb,
        'type': type,
        'hashinfo': hashinfo,
        'hash_info': hashInfo?.toJson(),
      };
}
