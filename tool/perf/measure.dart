// ignore_for_file: avoid_print
// Scroll-performance probe for RES-105 / F-1 evidence.
// Talks to the app's VM service (same protocol DevTools uses):
//   dart measure.dart <vm-service-http-uri> <label> [swipes]
// Records the timeline while adb scrolls the home feed, then prints
// UI/raster frame stats, per-widget build counts and process memory.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

const adb = r'C:\Users\chakk\AppData\Local\Android\Sdk\platform-tools\adb.exe';

late WebSocket _ws;
var _nextId = 0;
final _pending = <String, Completer<Map<String, dynamic>>>{};
// source -> latest ImageSizeInfo json, from Flutter.ImageSizesForFrame.
final _imageSizes = <String, Map<String, dynamic>>{};
final _kinds = <String, int>{};

Future<Map<String, dynamic>> call(String method,
    [Map<String, dynamic> params = const {}]) {
  final id = '${_nextId++}';
  final c = Completer<Map<String, dynamic>>();
  _pending[id] = c;
  _ws.add(jsonEncode(
      {'jsonrpc': '2.0', 'id': id, 'method': method, 'params': params}));
  return c.future;
}

Future<String> sh(List<String> args) async =>
    (await Process.run(adb, args)).stdout as String;

Future<Map<String, int>> meminfo() async {
  final out = await sh(['shell', 'dumpsys', 'meminfo', 'dev.rescu.rescu']);
  int grab(String label) {
    final m =
        RegExp('^\\s*${RegExp.escape(label)}:?\\s+(\\d+)', multiLine: true)
            .firstMatch(out);
    return m == null ? -1 : int.parse(m.group(1)!);
  }

  return {
    'totalPssKb': grab('TOTAL PSS'),
    'nativeHeapKb': grab('Native Heap'),
    'graphicsKb': grab('Graphics'),
    'glMtrackKb': grab('GL mtrack'),
  };
}

Map<String, num> stats(List<int> durUs) {
  if (durUs.isEmpty) return {'count': 0};
  durUs.sort();
  num pct(double p) => durUs[((durUs.length - 1) * p).round()] / 1000;
  final avg = durUs.reduce((a, b) => a + b) / durUs.length / 1000;
  return {
    'count': durUs.length,
    'avgMs': double.parse(avg.toStringAsFixed(2)),
    'p50Ms': pct(0.5),
    'p90Ms': pct(0.9),
    'p99Ms': pct(0.99),
    'maxMs': durUs.last / 1000,
    'over16ms': durUs.where((d) => d > 16667).length,
  };
}

Future<void> main(List<String> args) async {
  final httpUri = Uri.parse(args[0]);
  final label = args.length > 1 ? args[1] : 'run';
  final swipes = args.length > 2 ? int.parse(args[2]) : 12;
  // 'builds' = per-widget build counts (floods the timeline, so frame stats
  // are unreliable); 'frames' = frame timings only.
  final mode = args.length > 3 ? args[3] : 'frames';
  final wsUri = httpUri.replace(
      scheme: 'ws', path: '${httpUri.path.replaceAll(RegExp(r'/$'), '')}/ws');
  _ws = await WebSocket.connect(wsUri.toString());
  _ws.listen((msg) {
    final m = jsonDecode(msg as String) as Map<String, dynamic>;
    if (m['method'] == 'streamNotify') {
      final event = (m['params'] as Map)['event'] as Map;
      _kinds.update('${event['extensionKind'] ?? event['kind']}', (n) => n + 1,
          ifAbsent: () => 1);
      if (event['extensionKind'] == 'Flutter.ImageSizesForFrame') {
        (event['extensionData'] as Map).forEach((k, v) =>
            _imageSizes[k as String] = (v as Map).cast<String, dynamic>());
      }
      return;
    }
    final c = _pending.remove(m['id']);
    if (c == null) return;
    if (m['error'] != null) {
      c.completeError(m['error'] as Object);
    } else {
      c.complete(m['result'] as Map<String, dynamic>);
    }
  });

  final vm = await call('getVM');
  final isolate = (vm['isolates'] as List)
      .cast<Map<String, dynamic>>()
      .firstWhere((i) => (i['name'] as String).contains('main'));
  final isolateId = isolate['id'] as String;

  await call('streamListen', {'streamId': 'Extension'});
  await call('ext.flutter.profileWidgetBuilds',
      {'isolateId': isolateId, 'enabled': '${mode == 'builds'}'});
  if (mode == 'oversized') {
    // Same switch as DevTools' "Highlight oversized images" (debug builds).
    await call('ext.flutter.invertOversizedImages',
        {'isolateId': isolateId, 'enabled': 'true'});
  }
  await call('setVMTimelineFlags', {
    'recordedStreams': ['Dart', 'Embedder', 'GC']
  });
  await call('clearVMTimeline');

  final memBefore = await meminfo();
  final sw = Stopwatch()..start();
  for (var i = 0; i < swipes; i++) {
    // Slow, steady drag: ~1100px over 700ms.
    await sh(['shell', 'input', 'swipe', '540', '1900', '540', '800', '700']);
  }
  sw.stop();
  // With 0 swipes this is an idle window (e.g. countdown ticks only).
  await Future<void>.delayed(Duration(seconds: swipes == 0 ? 5 : 2));
  final memAfter = await meminfo();

  final timeline = await call('getVMTimeline');
  final events = (timeline['traceEvents'] as List).cast<Map<String, dynamic>>();

  // Pair B/E events per (tid, name) and collect X events.
  final open = <String, List<int>>{};
  final durations = <String, List<int>>{};
  for (final e in events) {
    final name = e['name'] as String? ?? '';
    final ph = e['ph'];
    final key = '${e['tid']}|$name';
    if (ph == 'X') {
      durations.putIfAbsent(name, () => []).add((e['dur'] as num).toInt());
    } else if (ph == 'B') {
      open.putIfAbsent(key, () => []).add((e['ts'] as num).toInt());
    } else if (ph == 'E') {
      final stack = open[key];
      if (stack != null && stack.isNotEmpty) {
        final start = stack.removeLast();
        durations
            .putIfAbsent(name, () => [])
            .add((e['ts'] as num).toInt() - start);
      }
    }
  }

  final ts = [
    for (final e in events)
      if (e['ts'] is num && e['ph'] != 'M') (e['ts'] as num).toInt()
  ]..sort();
  final coveredSeconds = ts.isEmpty ? 0 : (ts.last - ts.first) / 1e6;

  List<int> pick(List<String> names) =>
      [for (final n in names) ...?durations[n]];

  const widgets = [
    'HomeScreen',
    'Obx',
    'Scaffold',
    'AppBar',
    'SmartRefresher',
    'ListView',
    'FlashDealsSection',
    'DealCard',
    'TheNetworkImage',
    'CachedNetworkImage',
    'FlashCountdownText',
    'FlashExpiryBuilder',
    '_FlashDealTile',
    'Text',
  ];

  final result = {
    'label': label,
    'mode': mode,
    'scrollSeconds': sw.elapsedMilliseconds / 1000,
    'timelineCoveredSeconds': coveredSeconds,
    'uiFrame(Animator::BeginFrame)': stats(pick(['Animator::BeginFrame'])),
    'build(BUILD)': stats(pick(['BUILD'])),
    'raster(Rasterizer::DoDraw)':
        stats(pick(['Rasterizer::DoDraw', 'GPURasterizer::Draw'])),
    'widgetBuilds': {
      for (final w in widgets) w: durations[w]?.length ?? 0,
    },
    'imagesPainted': _imageSummary(),
    'extensionEvents': _kinds,
    'memoryBefore': memBefore,
    'memoryAfter': memAfter,
  };
  print(const JsonEncoder.withIndent('  ').convert(result));

  await call('ext.flutter.profileWidgetBuilds',
      {'isolateId': isolateId, 'enabled': 'false'});
  await _ws.close();
}

Map<String, Object> _imageSummary() {
  if (_imageSizes.isEmpty) return {'count': 0};
  final infos = _imageSizes.values.toList();
  num sum(String k) => infos.fold<num>(0, (a, i) => a + (i[k] as num));
  final first = infos.first;
  return {
    'count': infos.length,
    'exampleDecode':
        '${(first['imageSize'] as Map)['width']}x${(first['imageSize'] as Map)['height']}',
    'exampleDisplay':
        '${((first['displaySize'] as Map)['width'] as num).round()}x${((first['displaySize'] as Map)['height'] as num).round()}',
    'avgDecodedKB': (sum('decodedSizeInBytes') / infos.length / 1024).round(),
    'avgDisplayKB': (sum('displaySizeInBytes') / infos.length / 1024).round(),
    'totalDecodedMB':
        double.parse((sum('decodedSizeInBytes') / 1048576).toStringAsFixed(1)),
  };
}
