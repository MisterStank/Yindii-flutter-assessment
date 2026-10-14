import 'package:flutter_test/flutter_test.dart';
import 'package:rescu/service/analytics_service.dart';
import 'package:rescu/service/fake_api_service.dart';
import 'package:rescu/service/impression_service.dart';

class _FakeApi implements FakeApiService {
  final batches = <List<Map<String, dynamic>>>[];
  var failNext = false;

  @override
  Future<void> sendAnalyticsBatch(List<Map<String, dynamic>> events) async {
    if (failNext) {
      failNext = false;
      throw Exception('network');
    }
    batches.add(events);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _FakeApi api;
  late AnalyticsService analytics;
  late ImpressionService service;

  setUp(() {
    api = _FakeApi();
    analytics = AnalyticsService();
    service = ImpressionService(api: api, analytics: analytics);
  });

  void see(int dealId, double fraction,
          {String source = 'home_feed', int position = 0}) =>
      service.onVisibilityChanged(
          dealId: dealId,
          source: source,
          position: position,
          visibleFraction: fraction);

  List<Map<String, dynamic>> impressions() => analytics.events
      .where((e) => e.name == 'deal_impression')
      .map((e) => e.properties)
      .toList();

  // testWidgets runs in a fake-async zone, so pump() advances Timers.
  testWidgets('logs after one continuous second at >=50%', (tester) async {
    see(1, 0.6, position: 3);
    await tester.pump(const Duration(milliseconds: 999));
    expect(impressions(), isEmpty);
    await tester.pump(const Duration(milliseconds: 2));
    expect(impressions(), [
      {'deal_id': 1, 'source': 'home_feed', 'position': 3}
    ]);
    service.onClose(); // cancel timers before the pending-timer check
  });

  testWidgets('does not log when visibility drops before one second',
      (tester) async {
    see(1, 0.6);
    await tester.pump(const Duration(milliseconds: 600));
    see(1, 0.4);
    await tester.pump(const Duration(milliseconds: 600));
    see(1, 0.6);
    await tester.pump(const Duration(milliseconds: 600));
    expect(impressions(), isEmpty);
    service.onClose();
  });

  testWidgets('logs each deal once per session across sources', (tester) async {
    see(1, 1, source: 'flash_rail');
    await tester.pump(const Duration(seconds: 2));
    see(1, 0);
    see(1, 1, source: 'home_feed');
    await tester.pump(const Duration(seconds: 2));
    see(1, 0, source: 'home_feed');
    see(1, 1, source: 'search');
    await tester.pump(const Duration(seconds: 2));
    expect(impressions(), hasLength(1));
    expect(impressions().single['source'], 'flash_rail');
    service.onClose();
  });

  testWidgets('sends a batch as soon as 10 events accumulate', (tester) async {
    for (var id = 1; id <= 10; id++) {
      see(id, 1, position: id);
    }
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(api.batches.map((b) => b.length), [10]);
    service.onClose();
  });

  testWidgets('sends a partial batch 15s after the first unsent event',
      (tester) async {
    see(1, 1);
    await tester.pump(const Duration(seconds: 1)); // event 1 queued at t=1s
    see(2, 1);
    await tester.pump(const Duration(seconds: 14)); // t=15s
    expect(api.batches, isEmpty);
    await tester.pump(const Duration(seconds: 1)); // t=16s
    await tester.pump();
    expect(api.batches.map((b) => b.length), [2]);
    service.onClose();
  });

  testWidgets('re-queues a failed batch and retries it', (tester) async {
    api.failNext = true;
    see(1, 1);
    await tester.pump(const Duration(seconds: 16));
    await tester.pump();
    expect(api.batches, isEmpty);

    await tester.pump(const Duration(seconds: 15));
    await tester.pump();
    expect(api.batches.map((b) => b.length), [1]);
    service.onClose();
  });
}
