import 'package:flutter/material.dart';

import '../models/report_record.dart';

class ReportDetailScreen extends StatefulWidget {
  const ReportDetailScreen({super.key, required this.record});

  final ReportRecord record;

  @override
  State<ReportDetailScreen> createState() => _ReportDetailScreenState();
}

class _ReportDetailScreenState extends State<ReportDetailScreen> {
  late final TextEditingController _noteController;

  @override
  void initState() {
    super.initState();
    _noteController = TextEditingController(text: widget.record.note);
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  void _saveNote() {
    setState(() {
      widget.record.note = _noteController.text;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('備註已儲存')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final record = widget.record;
    return Scaffold(
      appBar: AppBar(title: const Text('報表詳情')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${record.createdAt.year}/${record.createdAt.month}/${record.createdAt.day} '
              '${record.createdAt.hour.toString().padLeft(2, '0')}:${record.createdAt.minute.toString().padLeft(2, '0')}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(record.reportContent),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '量表分數：${record.totalScore}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text('評估結果：${record.resultAnalysis}'),
            const SizedBox(height: 24),
            Text('新增備註', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            TextField(
              controller: _noteController,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: '例如：今天因為專案截止日所以特別焦慮',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _saveNote,
                child: const Text('儲存備註'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
