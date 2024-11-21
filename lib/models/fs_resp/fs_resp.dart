import 'data.dart';

class FsResp {
  int? code;
  String? message;
  Data? data;

  FsResp({this.code, this.message, this.data});

  factory FsResp.fromJson(Map<String, dynamic> json) => FsResp(
        code: json['code'] as int?,
        message: json['message'] as String?,
        data: json['data'] == null
            ? null
            : Data.fromJson(json['data'] as Map<String, dynamic>),
      );

  Map<String, dynamic> toJson() => {
        'code': code,
        'message': message,
        'data': data?.toJson(),
      };
}
