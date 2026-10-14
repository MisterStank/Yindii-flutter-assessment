import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rescu/model/deal_model.dart';
import 'package:rescu/repository/deal_repo.dart';
import 'package:rescu/feature/search/search_deals_controller.dart';

class _FakeDealRepo implements DealRepo {
  final pending = <String, Completer<List<DealModel>>>{};

  @override
  Future<List<DealModel>> search(String query) =>
      (pending[query] = Completer<List<DealModel>>()).future;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

DealModel _deal(int id, String name) => DealModel.fromJson({
      'id': id,
      'name': name,
      'pickupWindow': {
        'start': '2026-01-01T10:00:00.000Z',
        'end': '2026-01-01T12:00:00.000Z',
      },
    });

void main() {
  late _FakeDealRepo repo;
  late SearchDealsController controller;

  setUp(() {
    repo = _FakeDealRepo();
    controller = SearchDealsController(dealRepo: repo);
  });

  test('a slower, older response does not overwrite the latest one', () async {
    final shortQuery = controller.search('s');
    final longQuery = controller.search('sushi');

    repo.pending['sushi']!.complete([_deal(1, 'Sushi Set')]);
    await longQuery;
    repo.pending['s']!.complete([_deal(1, 'Sushi Set'), _deal(2, 'Salad')]);
    await shortQuery;

    expect(controller.results.map((d) => d.name), ['Sushi Set']);
    expect(controller.isLoading.value, isFalse);
  });

  test('stays loading until the latest request finishes', () async {
    final shortQuery = controller.search('s');
    controller.search('sushi');

    repo.pending['s']!.complete([_deal(2, 'Salad')]);
    await shortQuery;

    expect(controller.isLoading.value, isTrue);
    expect(controller.results, isEmpty);
  });

  test('clearing the query discards in-flight results', () async {
    final query = controller.search('sushi');
    await controller.search('');

    repo.pending['sushi']!.complete([_deal(1, 'Sushi Set')]);
    await query;

    expect(controller.results, isEmpty);
    expect(controller.hasSearched.value, isFalse);
  });
}
