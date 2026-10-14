import 'deal_model.dart';
import 'reservation_model.dart';

enum HoldStatus {
  /// Optimistically in the bag; the reservation request is in flight.
  reserving,

  /// Stock is held until `reservation.expiresAt`.
  held,

  /// The hold ran out; the line must be re-reserved before checkout.
  expired,
}

class CartItemModel {
  final DealModel deal;
  int quantity;

  /// Stock hold for this line item, covering its whole quantity.
  ReservationModel? reservation;

  HoldStatus status;

  CartItemModel({
    required this.deal,
    this.quantity = 1,
    this.reservation,
    this.status = HoldStatus.reserving,
  });

  num get lineTotal => deal.price * quantity;
}
