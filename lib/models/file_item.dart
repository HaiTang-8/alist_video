import 'package:alist_player/models/historical_record.dart';

class FileItem {
  final String name;
  final int size;
  final DateTime modified;
  final int type;
  final String sha1;
  final String parent;
  HistoricalRecord? historyRecord; // 添加历史记录字段

  FileItem({
    required this.name,
    required this.size,
    required this.modified,
    required this.type,
    required this.sha1,
    required this.parent,
    this.historyRecord,
  });
}
