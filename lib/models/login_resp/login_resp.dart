import 'data.dart';

class LoginResp {
  int? code;
  String? message;
  Data? data;

  LoginResp({this.code, this.message, this.data});

  factory LoginResp.fromJson(Map<String, dynamic> json) => LoginResp(
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
