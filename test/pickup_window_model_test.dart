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
}
