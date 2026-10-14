import 'package:flutter_test/flutter_test.dart';
import 'package:rescu/model/cart_item_model.dart';
import 'package:rescu/model/deal_model.dart';
import 'package:rescu/service/api_exception.dart';
import 'package:rescu/service/cart_service.dart';

import 'fakes/fake_order_repo.dart';

DealModel _deal(int id) => DealModel.fromJson({
      'id': id,
      'name': 'Deal $id',
      'quantityLeft': 5,
      'pickupWindow': {
        'start': '2026-01-01T10:00:00.000Z',
        'end': '2026-01-01T12:00:00.000Z',
      },
    });

const _conflict = ApiException('Could not reserve', statusCode: 409);

void main() {
  late FakeOrderRepo repo;
  late CartService cart;
  late List<String> notified;

  setUp(() {
    repo = FakeOrderRepo();
    notified = [];
    cart = CartService(
        orderRepo: repo, notify: (title, message) => notified.add(message));
  });

  CartItemModel line() => cart.items.single;

  test('adds optimistically, then holds once the reservation succeeds',
      () async {
    final adding = cart.add(_deal(1));
    expect(line().status, HoldStatus.reserving);
    expect(cart.itemCount.value, 1);
    expect(cart.canCheckout, isFalse);

    repo.pendingReserves.single.complete(repo.hold(1, 1));
    await adding;

    expect(line().status, HoldStatus.held);
    expect(line().reservation!.id, 'res_1');
    expect(cart.canCheckout, isTrue);
  });

  test('rolls a new line back with a message when the reservation fails',
      () async {
    final adding = cart.add(_deal(1));
    repo.pendingReserves.single.completeError(_conflict);
    await adding;

    expect(cart.items, isEmpty);
    expect(cart.itemCount.value, 0);
    expect(notified.single, contains('Someone just grabbed the last Deal 1'));
  });

  test('a failed increase restores the quantity and keeps the old hold',
      () async {
    final adding = cart.add(_deal(1));
    repo.pendingReserves.last.complete(repo.hold(1, 1));
    await adding;

    final increasing = cart.add(_deal(1));
    expect(line().quantity, 2);
    repo.pendingReserves.last.completeError(_conflict);
    await increasing;

    expect(line().quantity, 1);
    expect(line().status, HoldStatus.held);
    expect(line().reservation!.id, 'res_1');
    expect(repo.released, isEmpty);
  });

  test('a successful increase swaps holds and releases the old one',
      () async {
    final adding = cart.add(_deal(1));
    repo.pendingReserves.last.complete(repo.hold(1, 1));
    await adding;

    final increasing = cart.add(_deal(1));
    repo.pendingReserves.last.complete(repo.hold(1, 2));
    await increasing;

    expect(line().reservation!.quantity, 2);
    expect(repo.released, ['res_1']);
  });

  test('removing a line releases its hold', () async {
    final adding = cart.add(_deal(1));
    repo.pendingReserves.last.complete(repo.hold(1, 1));
    await adding;

    cart.remove(1);
    expect(repo.released, ['res_1']);
  });

  test('a hold that arrives after its line was removed is released',
      () async {
    final adding = cart.add(_deal(1));
    cart.remove(1);
    repo.pendingReserves.single.complete(repo.hold(1, 1));
    await adding;

    expect(cart.items, isEmpty);
    expect(repo.released, ['res_1']);
  });

  // testWidgets runs in a fake-async zone, so pump() advances Timers.
  testWidgets('an expired hold blocks checkout until it is renewed',
      (tester) async {
    final adding = cart.add(_deal(1));
    repo.pendingReserves.last.complete(repo.hold(1, 1));
    await adding;

    await tester.pump(const Duration(minutes: 5, seconds: 1));
    expect(line().status, HoldStatus.expired);
    expect(cart.canCheckout, isFalse);

    final renewing = cart.renew(1);
    repo.pendingReserves.last.complete(repo.hold(1, 1));
    await renewing;

    expect(line().status, HoldStatus.held);
    expect(cart.canCheckout, isTrue);
    cart.onClose(); // cancel the new hold's timer before the test ends
  });

  test('a 410 at checkout marks every hold as rejected', () async {
    final adding = cart.add(_deal(1));
    repo.pendingReserves.last.complete(repo.hold(1, 1));
    await adding;

    cart.markHoldsRejected();

    expect(line().status, HoldStatus.expired);
    expect(cart.canCheckout, isFalse);
  });
}
