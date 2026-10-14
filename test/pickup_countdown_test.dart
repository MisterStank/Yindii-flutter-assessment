import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rescu/feature/order/widget/pickup_countdown.dart';

void main() {
  testWidgets('stops ticking after it is removed from the tree',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: PickupCountdown(
        pickupStart: DateTime.now().add(const Duration(minutes: 10)),
      ),
    ));
    await tester.pump(const Duration(seconds: 1));

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump(const Duration(seconds: 3));

    expect(tester.takeException(), isNull);
  });
}
