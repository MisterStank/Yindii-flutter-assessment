import 'dart:async';

import 'package:get/get.dart';

import '../model/cart_item_model.dart';
import '../model/deal_model.dart';
import '../repository/order_repo.dart';
import '../util/log_service.dart';
import 'api_exception.dart';

typedef CartNotifier = void Function(String title, String message);

/// Why a line is being (re)reserved; decides how a failure is rolled back.
enum _ReserveReason { add, increase, decrease, renew }

/// App-wide cart. Lives for the whole session.
///
/// Every line holds one backend reservation for its whole quantity. Changes
/// are applied optimistically and rolled back if the reservation fails.
class CartService extends GetxService {
  CartService({required this.orderRepo, CartNotifier? notify})
      : _notify = notify ?? _snackbar;

  final OrderRepo orderRepo;
  final CartNotifier _notify;

  final items = <CartItemModel>[].obs;
  final itemCount = 0.obs;

  /// Lines removed because their flash sale ended, shown in the bag until
  /// dismissed so the user cannot miss them.
  final expiredNotices = <String>[].obs;

  final _flashTimers = <int, Timer>{};
  final _holdTimers = <int, Timer>{};

  bool get hasExpiredHolds => items.any((i) => i.status == HoldStatus.expired);

  bool get isReserving => items.any((i) => i.status == HoldStatus.reserving);

  bool get canCheckout =>
      items.isNotEmpty && items.every((i) => i.status == HoldStatus.held);

  Future<void> add(DealModel deal) async {
    if (deal.isFlashExpired) {
      LogService.log('cart: flash sale for deal ${deal.id} has ended');
      return;
    }
    final existing = _line(deal.id);
    if (existing == null) {
      final item = CartItemModel(deal: deal);
      items.add(item);
      _scheduleFlashExpiry(deal);
      _recount();
      await _reserve(item, _ReserveReason.add);
      return;
    }
    if (existing.status != HoldStatus.held) return;
    if (existing.quantity >= deal.quantityLeft) {
      LogService.log('cart: cannot add more of deal ${deal.id}');
      return;
    }
    existing.quantity++;
    await _reserve(existing, _ReserveReason.increase);
  }

  Future<void> decrement(int dealId) async {
    final existing = _line(dealId);
    if (existing == null || existing.status == HoldStatus.reserving) return;
    if (existing.quantity <= 1) {
      remove(dealId);
      return;
    }
    existing.quantity--;
    if (existing.status == HoldStatus.expired) {
      // Nothing held to adjust; the next renew reserves the new quantity.
      items.refresh();
      _recount();
      return;
    }
    await _reserve(existing, _ReserveReason.decrease);
  }

  /// Re-reserves a line whose hold expired.
  Future<void> renew(int dealId) async {
    final existing = _line(dealId);
    if (existing == null || existing.status != HoldStatus.expired) return;
    await _reserve(existing, _ReserveReason.renew);
  }

  void remove(int dealId) {
    final item = _line(dealId);
    _flashTimers.remove(dealId)?.cancel();
    _holdTimers.remove(dealId)?.cancel();
    if (item == null) return;
    items.remove(item);
    final reservation = item.reservation;
    if (reservation != null) _release(reservation.id);
    _recount();
  }

  /// Empties the bag after a successful checkout. Holds are not released:
  /// checkout consumed them.
  void clear() {
    for (final timer in [..._flashTimers.values, ..._holdTimers.values]) {
      timer.cancel();
    }
    _flashTimers.clear();
    _holdTimers.clear();
    items.clear();
    _recount();
  }

  /// Removes lines whose flash sale already ended. Timers can fire late after
  /// the app was suspended, so call this before acting on the bag.
  void expireOverdue() {
    for (final item in items.toList()) {
      if (item.deal.isFlashExpired) _expireFlash(item.deal);
    }
    for (final item in items) {
      if (item.status == HoldStatus.held &&
          (item.reservation?.isExpired ?? true)) {
        _expireHold(item);
      }
    }
  }

  /// Checkout was rejected with 410: mark lines whose hold has run out, or
  /// every line if the server no longer knows a hold we think is valid.
  void markHoldsRejected() {
    final overdue =
        items.where((i) => i.reservation?.isExpired ?? true).toList();
    for (final item in overdue.isEmpty ? items.toList() : overdue) {
      _expireHold(item);
    }
  }

  void dismissExpiredNotices() => expiredNotices.clear();

  num get total => items.fold(0, (sum, i) => sum + i.lineTotal);

  CartItemModel? _line(int dealId) =>
      items.firstWhereOrNull((i) => i.deal.id == dealId);

  Future<void> _reserve(CartItemModel item, _ReserveReason reason) async {
    final previousStatus = item.status;
    final oldHold = item.reservation;
    item.status = HoldStatus.reserving;
    items.refresh();
    _recount();
    try {
      final hold =
          await orderRepo.reserve(item.deal.id, quantity: item.quantity);
      if (!items.contains(item)) {
        // Removed while the request was in flight: don't leak the hold.
        _release(hold.id);
        return;
      }
      item.reservation = hold;
      item.status = HoldStatus.held;
      _scheduleHoldExpiry(item);
      if (oldHold != null) _release(oldHold.id);
    } catch (e) {
      LogService.error('reserve deal ${item.deal.id} failed', e);
      if (!items.contains(item)) return;
      _rollBack(item, reason, previousStatus, e);
    }
    items.refresh();
    _recount();
  }

  void _rollBack(CartItemModel item, _ReserveReason reason,
      HoldStatus previousStatus, Object error) {
    final name = item.deal.name;
    switch (reason) {
      case _ReserveReason.add:
        items.remove(item);
        _flashTimers.remove(item.deal.id)?.cancel();
        _notify("Couldn't add to bag", _failureMessage(name, error));
      case _ReserveReason.increase:
        item.quantity--;
        item.status = previousStatus;
        _notify("Couldn't add another", _failureMessage(name, error));
      case _ReserveReason.decrease:
        // The old, larger hold is still valid; keep it rather than risk
        // losing the items the user still wants.
        item.status = previousStatus;
      case _ReserveReason.renew:
        item.status = HoldStatus.expired;
        _notify("Couldn't hold $name again",
            'It may have sold out. You can try again or remove it.');
    }
    // The previous hold may have run out while the request was in flight.
    if (item.status == HoldStatus.held &&
        (item.reservation?.isExpired ?? true)) {
      item.status = HoldStatus.expired;
    }
  }

  String _failureMessage(String name, Object error) {
    if (error is ApiException && error.statusCode == 409) {
      return 'Someone just grabbed the last $name. Please try again.';
    }
    return "We couldn't reach the store to hold $name. Please try again.";
  }

  void _release(String reservationId) {
    orderRepo.releaseReservation(reservationId).catchError(
        (Object e) => LogService.error('release $reservationId failed', e));
  }

  void _scheduleHoldExpiry(CartItemModel item) {
    final expiresAt = item.reservation?.expiresAt;
    if (expiresAt == null) return;
    _holdTimers[item.deal.id]?.cancel();
    _holdTimers[item.deal.id] =
        Timer(expiresAt.difference(DateTime.now()), () => _expireHold(item));
  }

  void _expireHold(CartItemModel item) {
    _holdTimers.remove(item.deal.id)?.cancel();
    if (!items.contains(item) || item.status != HoldStatus.held) return;
    item.status = HoldStatus.expired;
    items.refresh();
  }

  void _scheduleFlashExpiry(DealModel deal) {
    final endsAt = deal.flashSaleEndsAt;
    if (endsAt == null) return;
    _flashTimers[deal.id]?.cancel();
    _flashTimers[deal.id] =
        Timer(endsAt.difference(DateTime.now()), () => _expireFlash(deal));
  }

  void _expireFlash(DealModel deal) {
    if (_line(deal.id) == null) return;
    remove(deal.id);
    final message =
        '${deal.name} was removed from your bag because its flash sale ended.';
    expiredNotices.add(message);
    _notify('Flash sale ended', message);
  }

  void _recount() {
    itemCount.value = items.fold(0, (sum, i) => sum + i.quantity);
  }

  @override
  void onClose() {
    for (final timer in [..._flashTimers.values, ..._holdTimers.values]) {
      timer.cancel();
    }
    super.onClose();
  }

  static void _snackbar(String title, String message) => Get.snackbar(
        title,
        message,
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 4),
      );
}
