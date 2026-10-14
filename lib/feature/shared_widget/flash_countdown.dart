import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../service/clock_service.dart';

/// `mm:ss`, or `hh:mm:ss` from one hour up. Rounds up so it shows 00:01
/// until the very end, then "Expired".
String formatCountdown(Duration remaining) {
  if (remaining <= Duration.zero) return 'Expired';
  final total = (remaining.inMilliseconds + 999) ~/ 1000;
  String two(int n) => n.toString().padLeft(2, '0');
  final h = total ~/ 3600;
  final m = total % 3600 ~/ 60;
  final s = total % 60;
  return h > 0 ? '${two(h)}:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}

/// Live countdown text. Only this Text rebuilds every second.
class FlashCountdownText extends StatelessWidget {
  final DateTime endsAt;
  final TextStyle? style;

  const FlashCountdownText({super.key, required this.endsAt, this.style});

  @override
  Widget build(BuildContext context) {
    final clock = Get.find<ClockService>();
    return Obx(() => Text(
          formatCountdown(endsAt.difference(clock.now.value)),
          style: style,
        ));
  }
}
