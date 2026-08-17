import '../models/report_record.dart';

List<ReportRecord> buildFakeReportRecords() {
  return [
    ReportRecord(
      id: '1',
      createdAt: DateTime(2026, 8, 15, 21, 10),
      reportContent:
          '問題一 睡眠困難 回答:非常難入睡，一直做夢 =>分數：3\n'
          '問題二 焦慮不安 回答:最近工作壓力大，常常心悸 =>分數：2\n'
          '問題三 易怒情緒 回答:還好，沒有特別生氣 =>分數：0\n'
          '問題四 低落沮喪 回答:覺得提不起勁 =>分數：1\n'
          '問題五 自信心低落 回答:覺得自己表現很差 =>分數：2\n'
          '問題六 負面念頭 回答:完全沒有 =>分數：0',
      totalScore: 8,
      resultAnalysis: '中度情緒困擾。建議您適度安排放鬆活動，若持續不適可考慮尋求專業諮詢。',
    ),
    ReportRecord(
      id: '2',
      createdAt: DateTime(2026, 8, 10, 9, 30),
      reportContent:
          '問題一 睡眠困難 回答:睡得還算安穩 =>分數：0\n'
          '問題二 焦慮不安 回答:偶爾會緊張 =>分數：1\n'
          '問題三 易怒情緒 回答:沒有特別煩躁 =>分數：0\n'
          '問題四 低落沮喪 回答:心情大致平穩 =>分數：0\n'
          '問題五 自信心低落 回答:對自己還算有信心 =>分數：0\n'
          '問題六 負面念頭 回答:完全沒有 =>分數：0',
      totalScore: 1,
      resultAnalysis: '情緒狀態良好，無明顯困擾，請持續保持良好的生活習慣。',
    ),
  ];
}
