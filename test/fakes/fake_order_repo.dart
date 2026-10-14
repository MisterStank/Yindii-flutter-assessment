import 'dart:async';

import 'package:rescu/model/reservation_model.dart';
import 'package:rescu/repository/order_repo.dart';

/// OrderRepo whose reservations are answered by the test. With
/// [autoReserve], reserve() succeeds immediately with a 5 minute hold.
class FakeOrderRepo implements OrderRepo {
  FakeOrderRepo({this.autoReserve = false});

  final bool autoReserve;
  final pendingReserves = <Completer<ReservationModel>>[];
  final released = <String>[];
  var _seq = 0;

  ReservationModel hold(int dealId, int quantity,
          {Duration ttl = const Duration(minutes: 5)}) =>
      ReservationModel(
        id: 'res_${++_seq}',
        dealId: dealId,
        quantity: quantity,
        expiresAt: DateTime.now().toUtc().add(ttl),
      );

  @override
  Future<ReservationModel> reserve(int dealId, {int quantity = 1}) {
    if (autoReserve) return Future.value(hold(dealId, quantity));
    final c = Completer<ReservationModel>();
    pendingReserves.add(c);
    return c.future;
  }

  @override
  Future<void> releaseReservation(String reservationId) async {
    released.add(reservationId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
