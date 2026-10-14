import 'package:flutter_test/flutter_test.dart';
import 'package:rescu/model/pickup_window_model.dart';

// Only catches RES-106 when run in a non-UTC timezone (e.g. Asia/Bangkok).
PickupWindowModel windowLocal(DateTime startLocal, DateTime endLocal) =>
    PickupWindowModel.fromJson({
      'start': startLocal.toUtc().toIso8601String(),
      'end': endLocal.toUtc().toIso8601String(),
    });

void main() {
  group('label', () {
    test('shows local wall-clock time, not UTC', () {
      final w = windowLocal(
          DateTime(2026, 1, 15, 6, 0), DateTime(2026, 1, 15, 9, 30));
      expect(w.label, '06:00 – 09:30');
    });

    test('formats overnight windows', () {
      final w = windowLocal(
          DateTime(2026, 1, 15, 22, 0), DateTime(2026, 1, 16, 1, 0));
      expect(w.label, '22:00 – 01:00');
    });
  });

  group('isTodayAt', () {
    final now = DateTime(2026, 1, 15, 4, 0);

    test('early-morning window today is today', () {
      final w = windowLocal(
          DateTime(2026, 1, 15, 6, 0), DateTime(2026, 1, 15, 9, 30));
      expect(w.isTodayAt(now), isTrue);
    });

    test('window tomorrow is not today', () {
      final w = windowLocal(
          DateTime(2026, 1, 16, 6, 0), DateTime(2026, 1, 16, 9, 30));
      expect(w.isTodayAt(now), isFalse);
    });

    test('same day-of-month in another month is not today', () {
      final w = windowLocal(
          DateTime(2026, 2, 15, 6, 0), DateTime(2026, 2, 15, 9, 30));
      expect(w.isTodayAt(now), isFalse);
    });

    test('overnight window that opened yesterday and is still open is today',
        () {
      final w = windowLocal(
          DateTime(2026, 1, 14, 22, 0), DateTime(2026, 1, 15, 1, 0));
      expect(w.isTodayAt(DateTime(2026, 1, 15, 0, 30)), isTrue);
    });

    test('overnight window starting tonight is today', () {
      final w = windowLocal(
          DateTime(2026, 1, 15, 22, 0), DateTime(2026, 1, 16, 1, 0));
      expect(w.isTodayAt(now), isTrue);
    });

    test('accepts a UTC "now"', () {
      final w = windowLocal(
          DateTime(2026, 1, 15, 6, 0), DateTime(2026, 1, 15, 9, 30));
      expect(w.isTodayAt(now.toUtc()), isTrue);
    });
  });
}
