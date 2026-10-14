import 'dart:async';

import 'package:get/get.dart';

/// App-wide one-second tick shared by every live countdown, so 100+
/// countdowns cost one timer instead of one each.
class ClockService extends GetxService {
  final now = DateTime.now().obs;

  Timer? _timer;

  @override
  void onInit() {
    super.onInit();
    _timer = Timer.periodic(
        const Duration(seconds: 1), (_) => now.value = DateTime.now());
  }

  @override
  void onClose() {
    _timer?.cancel();
    super.onClose();
  }
}
