import 'dart:async';

import 'package:get/get.dart';

import '../model/cart_item_model.dart';
import '../model/deal_model.dart';
import '../util/log_service.dart';

typedef CartNotifier = void Function(String title, String message);

/// App-wide cart. Lives for the whole session.
///
/// NOTE: the starter cart is purely local — it does not reserve stock on the
/// backend. See the "Reservations" feature task in PROBLEM.md.
class CartService extends GetxService {
  CartService({CartNotifier? notify}) : _notify = notify ?? _snackbar;

  final CartNotifier _notify;

  final items = <CartItemModel>[].obs;
  final itemCount = 0.obs;

  /// Lines removed because their flash sale ended, shown in the bag until
  /// dismissed so the user cannot miss them.
  final expiredNotices = <String>[].obs;

  final _expiryTimers = <int, Timer>{};

  void add(DealModel deal) {
    if (deal.isFlashExpired) {
      LogService.log('cart: flash sale for deal ${deal.id} has ended');
      return;
    }
    final existing = items.firstWhereOrNull((i) => i.deal.id == deal.id);
    if (existing != null) {
      if (existing.quantity >= deal.quantityLeft) {
        LogService.log('cart: cannot add more of deal ${deal.id}');
        return;
      }
      existing.quantity++;
      items.refresh();
    } else {
      items.add(CartItemModel(deal: deal));
      _scheduleExpiry(deal);
    }
    _recount();
  }

  void decrement(int dealId) {
    final existing = items.firstWhereOrNull((i) => i.deal.id == dealId);
    if (existing == null) return;
    existing.quantity--;
    if (existing.quantity <= 0) {
      remove(dealId);
      return;
    }
    items.refresh();
    _recount();
  }

  void remove(int dealId) {
    _expiryTimers.remove(dealId)?.cancel();
    items.removeWhere((i) => i.deal.id == dealId);
    _recount();
  }

  void clear() {
    for (final timer in _expiryTimers.values) {
      timer.cancel();
    }
    _expiryTimers.clear();
    items.clear();
    _recount();
  }

  /// Removes lines whose flash sale already ended. Timers can fire late after
  /// the app was suspended, so call this before acting on the bag.
  void expireOverdue() {
    for (final item in items.toList()) {
      if (item.deal.isFlashExpired) _expire(item.deal);
    }
  }

  void dismissExpiredNotices() => expiredNotices.clear();

  num get total => items.fold(0, (sum, i) => sum + i.lineTotal);

  void _scheduleExpiry(DealModel deal) {
    final endsAt = deal.flashSaleEndsAt;
    if (endsAt == null) return;
    _expiryTimers[deal.id]?.cancel();
    _expiryTimers[deal.id] =
        Timer(endsAt.difference(DateTime.now()), () => _expire(deal));
  }

  void _expire(DealModel deal) {
    if (!items.any((i) => i.deal.id == deal.id)) return;
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
    for (final timer in _expiryTimers.values) {
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
