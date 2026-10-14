import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../../service/impression_service.dart';

/// Reports how much of [child] is on screen to [ImpressionService].
class ImpressionTracker extends StatelessWidget {
  final int dealId;
  final String source;
  final int position;
  final Widget child;

  const ImpressionTracker({
    super.key,
    required this.dealId,
    required this.source,
    required this.position,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      key: ValueKey('impression-$source-$dealId'),
      onVisibilityChanged: (info) =>
          Get.find<ImpressionService>().onVisibilityChanged(
        dealId: dealId,
        source: source,
        position: position,
        visibleFraction: info.visibleFraction,
      ),
      child: child,
    );
  }
}
