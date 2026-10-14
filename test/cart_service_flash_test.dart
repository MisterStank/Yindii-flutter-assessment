import 'package:flutter_test/flutter_test.dart';
import 'package:rescu/model/deal_model.dart';
import 'package:rescu/service/cart_service.dart';

DealModel _deal(int id, {Duration? flashEndsIn}) => DealModel.fromJson({
      'id': id,
      'name': 'Deal $id',
      'quantityLeft': 5,
      'pickupWindow': {
        'start': '2026-01-01T10:00:00.000Z',
        'end': '2026-01-01T12:00:00.000Z',
      },
      'flashSaleEndsAt': flashEndsIn == null
          ? null
          : DateTime.now().toUtc().add(flashEndsIn).toIso8601String(),
    });

void main() {
  late CartService cart;
  late List<String> notified;

  setUp(() {
    notified = [];
    cart = CartService(notify: (title, message) => notified.add(message));
  });

  // testWidgets runs in a fake-async zone, so pump() advances Timers.
  testWidgets('removes a flash line with a notice when the sale ends',
      (tester) async {
    cart.add(_deal(1, flashEndsIn: const Duration(seconds: 5)));
    cart.add(_deal(2));
    expect(cart.itemCount.value, 2);

    await tester.pump(const Duration(seconds: 6));

    expect(cart.items.map((i) => i.deal.id), [2]);
    expect(cart.itemCount.value, 1);
    expect(cart.expiredNotices, hasLength(1));
    expect(notified, hasLength(1));
  });

  testWidgets('no notice for a flash line removed before it expires',
      (tester) async {
    cart.add(_deal(1, flashEndsIn: const Duration(seconds: 5)));
    cart.remove(1);

    await tester.pump(const Duration(seconds: 6));

    expect(cart.expiredNotices, isEmpty);
    expect(notified, isEmpty);
  });

  test('refuses to add a deal whose flash sale has ended', () {
    cart.add(_deal(1, flashEndsIn: const Duration(seconds: -1)));
    expect(cart.items, isEmpty);
  });
}
