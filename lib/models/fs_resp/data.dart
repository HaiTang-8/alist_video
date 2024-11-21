import 'content.dart';

class Data {
  List<Content>? content;
  int? total;
  String? readme;
  String? header;
  bool? write;
  String? provider;

  Data({
    this.content,
    this.total,
    this.readme,
    this.header,
    this.write,
    this.provider,
  });

  factory Data.fromJson(Map<String, dynamic> json) => Data(
        content: (json['content'] as List<dynamic>?)
            ?.map((e) => Content.fromJson(e as Map<String, dynamic>))
            .toList(),
        total: json['total'] as int?,
        readme: json['readme'] as String?,
        header: json['header'] as String?,
        write: json['write'] as bool?,
        provider: json['provider'] as String?,
      );

  get length => null;

  Map<String, dynamic> toJson() => {
        'content': content?.map((e) => e.toJson()).toList(),
        'total': total,
        'readme': readme,
        'header': header,
        'write': write,
        'provider': provider,
      };
}
