import 'package:hive_flutter/hive_flutter.dart';

import '../models/report_record.dart';

/// Thin wrapper around the local Hive box that persists [ReportRecord]s.
///
/// [init] must be awaited once, before runApp — every other method assumes
/// the box is already open.
class ReportStore {
  ReportStore._();

  static const _boxName = 'reports';

  static Future<void> init() async {
    await Hive.initFlutter();
    Hive.registerAdapter(ReportRecordAdapter());
    await Hive.openBox<ReportRecord>(_boxName);
  }

  static Box<ReportRecord> get _box => Hive.box<ReportRecord>(_boxName);

  static List<ReportRecord> getAll() {
    return _box.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  static Future<void> save(ReportRecord record) {
    return _box.put(record.id, record);
  }
}
