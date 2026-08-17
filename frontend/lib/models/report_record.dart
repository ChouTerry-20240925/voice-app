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
