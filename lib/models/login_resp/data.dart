class Data {
  String? token;

  Data({this.token});

  factory Data.fromJson(Map<String, dynamic> json) => Data(
        token: json['token'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'token': token,
      };
}
