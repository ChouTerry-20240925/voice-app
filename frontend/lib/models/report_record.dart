import 'package:hive/hive.dart';

class ReportRecord {
  ReportRecord({
    required this.id,
    required this.createdAt,
    required this.reportContent,
    required this.totalScore,
    required this.resultAnalysis,
    this.note = '',
  });

  final String id;
  final DateTime createdAt;
  final String reportContent;
  final int totalScore;
  final String resultAnalysis;
  String note;
}

/// Hand-written Hive adapter — the model is small and stable enough that
/// pulling in hive_generator/build_runner for code-gen isn't worth it.
class ReportRecordAdapter extends TypeAdapter<ReportRecord> {
  @override
  final int typeId = 0;

  @override
  ReportRecord read(BinaryReader reader) {
    return ReportRecord(
      id: reader.readString(),
      createdAt: DateTime.fromMillisecondsSinceEpoch(reader.readInt()),
      reportContent: reader.readString(),
      totalScore: reader.readInt(),
      resultAnalysis: reader.readString(),
      note: reader.readString(),
    );
  }

  @override
  void write(BinaryWriter writer, ReportRecord obj) {
    writer
      ..writeString(obj.id)
      ..writeInt(obj.createdAt.millisecondsSinceEpoch)
      ..writeString(obj.reportContent)
      ..writeInt(obj.totalScore)
      ..writeString(obj.resultAnalysis)
      ..writeString(obj.note);
  }
}
