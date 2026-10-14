import 'dart:async';

import 'package:flutter/material.dart';

/// Builds with `expired == false` until [endsAt], then rebuilds exactly once
/// with `true`. A null [endsAt] (not a flash deal) never expires.
class FlashExpiryBuilder extends StatefulWidget {
  final DateTime? endsAt;
  final Widget Function(BuildContext context, bool expired) builder;

  const FlashExpiryBuilder(
      {super.key, required this.endsAt, required this.builder});

  @override
  State<FlashExpiryBuilder> createState() => _FlashExpiryBuilderState();
}

class _FlashExpiryBuilderState extends State<FlashExpiryBuilder> {
  Timer? _timer;
  bool _expired = false;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(FlashExpiryBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.endsAt != widget.endsAt) _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    final endsAt = widget.endsAt;
    if (endsAt == null) {
      _expired = false;
      return;
    }
    final remaining = endsAt.difference(DateTime.now());
    _expired = remaining <= Duration.zero;
    if (!_expired) {
      _timer = Timer(remaining, () => setState(() => _expired = true));
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _expired);
}
