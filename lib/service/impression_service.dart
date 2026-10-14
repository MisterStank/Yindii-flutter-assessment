import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../util/log_service.dart';
import 'analytics_service.dart';
import 'fake_api_service.dart';

/// Logs `deal_impression` once a deal card has been >=50% visible for one
/// continuous second, at most once per deal per session, and delivers the
/// events in batches of 10 or 15s after the first unsent one.
class ImpressionService extends GetxService with WidgetsBindingObserver {
  ImpressionService({required this.api, required this.analytics});

  final FakeApiService api;
  final AnalyticsService analytics;

  static const minVisibleFraction = 0.5;
  static const minVisibleDuration = Duration(seconds: 1);
  static const batchSize = 10;
  static const maxBatchDelay = Duration(seconds: 15);

  final _logged = <int>{};
  final _visibleTimers = <String, Timer>{};
  final _queue = <Map<String, dynamic>>[];
  Timer? _batchTimer;
  bool _sending = false;

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final timer in _visibleTimers.values) {
      timer.cancel();
    }
    _batchTimer?.cancel();
    super.onClose();
  }

  /// Called by ImpressionTracker whenever a card's visible fraction changes
  /// (including 0 when it leaves the screen or the tree).
  void onVisibilityChanged({
    required int dealId,
    required String source,
    required int position,
    required double visibleFraction,
  }) {
    final key = '$source|$dealId';
    if (visibleFraction < minVisibleFraction) {
      _visibleTimers.remove(key)?.cancel();
      return;
    }
    if (_logged.contains(dealId) || _visibleTimers.containsKey(key)) return;
    _visibleTimers[key] = Timer(minVisibleDuration, () {
      _visibleTimers.remove(key);
      _logImpression(dealId, source, position);
    });
  }

  void _logImpression(int dealId, String source, int position) {
    // Dedupe at enqueue time so a failed or slow batch can't cause repeats.
    if (!_logged.add(dealId)) return;
    final properties = {
      'deal_id': dealId,
      'source': source,
      'position': position,
    };
    analytics.logEvent('deal_impression', properties);
    _queue.add({
      'name': 'deal_impression',
      'properties': properties,
      'at': DateTime.now().toUtc().toIso8601String(),
    });
    if (_queue.length >= batchSize) {
      flush();
    } else {
      _batchTimer ??= Timer(maxBatchDelay, flush);
    }
  }

  /// Sends everything queued. Safe to call any time; also runs when the app
  /// goes to the background.
  Future<void> flush() async {
    _batchTimer?.cancel();
    _batchTimer = null;
    if (_sending || _queue.isEmpty) return;
    _sending = true;
    final batch = List<Map<String, dynamic>>.of(_queue);
    _queue.clear();
    try {
      await api.sendAnalyticsBatch(batch);
    } catch (e) {
      LogService.error('analytics batch failed, will retry', e);
      _queue.insertAll(0, batch);
    }
    _sending = false;
    // Events that arrived while sending (or a failed batch) wait for the
    // next trigger, unless a full batch is already waiting.
    if (_queue.length >= batchSize) {
      flush();
    } else if (_queue.isNotEmpty) {
      _batchTimer ??= Timer(maxBatchDelay, flush);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) flush();
  }
}
