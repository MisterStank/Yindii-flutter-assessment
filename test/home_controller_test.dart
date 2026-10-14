import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rescu/feature/home/home_controller.dart';
import 'package:rescu/model/deal_model.dart';
import 'package:rescu/model/paged_response_model.dart';
import 'package:rescu/repository/deal_repo.dart';

class _FakeDealRepo implements DealRepo {
  Completer<PagedResponseModel<DealModel>>? _pending;

  @override
  Future<PagedResponseModel<DealModel>> fetchDeals({int page = 1}) =>
      (_pending = Completer()).future;

  /// The latest request, so tests can answer requests in any order.
  Completer<PagedResponseModel<DealModel>> takeLast() {
    final c = _pending!;
    _pending = null;
    return c;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

PagedResponseModel<DealModel> _page(int page, {int size = 2, int total = 3}) {
  final start = (page - 1) * size;
  return PagedResponseModel(
    items: [
      for (var id = start + 1; id <= start + size; id++)
        DealModel.fromJson({
          'id': id,
          'pickupWindow': {
            'start': '2026-01-01T10:00:00.000Z',
            'end': '2026-01-01T12:00:00.000Z',
          },
        }),
    ],
    page: page,
    totalPages: total,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeDealRepo repo;
  late HomeController controller;

  setUp(() async {
    repo = _FakeDealRepo();
    controller = HomeController(dealRepo: repo);
    final first = controller.refreshDeals();
    repo.takeLast().complete(_page(1));
    await first;
  });

  List<int> ids() => controller.deals.map((d) => d.id).toList();

  test('a page load that finishes after a refresh is discarded', () async {
    final more = controller.loadMore();
    final page2 = repo.takeLast();
    final refresh = controller.refreshDeals();
    final page1 = repo.takeLast();

    page1.complete(_page(1));
    await refresh;
    page2.complete(_page(2));
    await more;

    expect(ids(), [1, 2]);

    final next = controller.loadMore();
    repo.takeLast().complete(_page(2));
    await next;
    expect(ids(), [1, 2, 3, 4]);
  });

  test('a page load that finishes before a refresh is replaced by it',
      () async {
    final more = controller.loadMore();
    final page2 = repo.takeLast();
    final refresh = controller.refreshDeals();
    final page1 = repo.takeLast();

    page2.complete(_page(2));
    await more;
    page1.complete(_page(1));
    await refresh;

    expect(ids(), [1, 2]);
  });
}
