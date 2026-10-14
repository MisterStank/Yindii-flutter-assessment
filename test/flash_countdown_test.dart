import 'package:flutter_test/flutter_test.dart';
import 'package:rescu/feature/shared_widget/flash_countdown.dart';

void main() {
  test('formats under an hour as mm:ss', () {
    expect(formatCountdown(const Duration(minutes: 8, seconds: 5)), '08:05');
    expect(formatCountdown(const Duration(seconds: 59)), '00:59');
  });

  test('formats from an hour up as hh:mm:ss', () {
    expect(formatCountdown(const Duration(hours: 1)), '01:00:00');
    expect(formatCountdown(const Duration(hours: 1, minutes: 15, seconds: 3)),
        '01:15:03');
  });

  test('rounds partial seconds up so 00:00 is never shown', () {
    expect(formatCountdown(const Duration(milliseconds: 300)), '00:01');
    expect(formatCountdown(const Duration(milliseconds: 59001)), '01:00');
  });

  test('shows Expired at or after the end', () {
    expect(formatCountdown(Duration.zero), 'Expired');
    expect(formatCountdown(const Duration(seconds: -3)), 'Expired');
  });
}
