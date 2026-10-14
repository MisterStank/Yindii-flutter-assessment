import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rescu/feature/shared_widget/flash_expiry_builder.dart';

void main() {
  testWidgets('rebuilds once when the deal expires', (tester) async {
    var builds = 0;
    await tester.pumpWidget(MaterialApp(
      home: FlashExpiryBuilder(
        endsAt: DateTime.now().add(const Duration(seconds: 5)),
        builder: (context, expired) {
          builds++;
          return Text(expired ? 'expired' : 'live');
        },
      ),
    ));
    expect(find.text('live'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    expect(find.text('live'), findsOneWidget);
    expect(builds, 1);

    await tester.pump(const Duration(seconds: 2));
    expect(find.text('expired'), findsOneWidget);
    expect(builds, 2);
  });

  testWidgets('a deal without a flash sale never expires', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: FlashExpiryBuilder(
        endsAt: null,
        builder: (context, expired) => Text(expired ? 'expired' : 'live'),
      ),
    ));
    await tester.pump(const Duration(hours: 1));
    expect(find.text('live'), findsOneWidget);
  });
}
