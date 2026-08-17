import 'package:flutter/material.dart';

import '../data/fake_reports.dart';
import '../models/report_record.dart';
import 'report_detail_screen.dart';

class ReportHistoryScreen extends StatefulWidget {
  const ReportHistoryScreen({super.key});

  @override
  State<ReportHistoryScreen> createState() => _ReportHistoryScreenState();
}

class _ReportHistoryScreenState extends State<ReportHistoryScreen> {
  late final List<ReportRecord> _records;

  @override
  void initState() {
    super.initState();
    _records = buildFakeReportRecords()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('歷史報表與備註')),
      body: _records.isEmpty
          ? const Center(child: Text('尚無測驗紀錄'))
          : ListView.separated(
              itemCount: _records.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final record = _records[index];
                return ListTile(
                  leading: const Icon(Icons.assignment_outlined),
                  title: Text(
                    '${record.createdAt.year}/${record.createdAt.month}/${record.createdAt.day} '
                    '${record.createdAt.hour.toString().padLeft(2, '0')}:${record.createdAt.minute.toString().padLeft(2, '0')}',
                  ),
                  subtitle: Text('量表分數：${record.totalScore}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ReportDetailScreen(record: record),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
