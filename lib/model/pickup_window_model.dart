import 'package:intl/intl.dart';

/// A store's pickup window. The API sends instants as ISO-8601 UTC strings.
/// Convert to local time for anything wall-clock based (labels, "today").
class PickupWindowModel {
  final DateTime start;
  final DateTime end;

  const PickupWindowModel({required this.start, required this.end});

  factory PickupWindowModel.fromJson(Map<String, dynamic> json) {
    return PickupWindowModel(
      start: DateTime.parse(json['start'] as String? ?? ''),
      end: DateTime.parse(json['end'] as String? ?? ''),
    );
  }

  /// Human readable label in local time, e.g. "17:30 – 21:00".
  String get label =>
      '${DateFormat('HH:mm').format(start.toLocal())} – '
      '${DateFormat('HH:mm').format(end.toLocal())}';

  /// Whether pickup is possible at some point today (local time).
  bool get isToday => isTodayAt(DateTime.now());

  /// Overlap, not "starts today", so overnight windows still open count.
  bool isTodayAt(DateTime now) {
    final local = now.toLocal();
    final startOfToday = DateTime(local.year, local.month, local.day);
    final startOfTomorrow = DateTime(local.year, local.month, local.day + 1);
    return start.isBefore(startOfTomorrow) && end.isAfter(startOfToday);
  }

  /// Whether the store is currently accepting pickups.
  bool get isOpenNow {
    final now = DateTime.now();
    return now.isAfter(start) && now.isBefore(end);
  }

  Duration get untilStart => start.difference(DateTime.now());
}
