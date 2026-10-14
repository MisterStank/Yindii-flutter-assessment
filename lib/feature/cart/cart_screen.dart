import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../app_config.dart';
import '../../model/cart_item_model.dart';
import '../../service/cart_service.dart';
import '../../service/clock_service.dart';
import '../shared_widget/flash_countdown.dart';
import '../shared_widget/the_network_image.dart';
import 'cart_controller.dart';

class CartScreen extends GetView<CartController> {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cart = controller.cartService;
    return Scaffold(
      appBar: AppBar(title: const Text('My bag')),
      body: Column(
        children: [
          Obx(() => cart.expiredNotices.isEmpty
              ? const SizedBox.shrink()
              : _ExpiredNotices(
                  messages: cart.expiredNotices.toList(),
                  onDismiss: cart.dismissExpiredNotices,
                )),
          Expanded(child: _buildItems(cart)),
        ],
      ),
      bottomNavigationBar: Obx(() {
        if (cart.items.isEmpty) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          color: Colors.white,
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Total', style: TextStyle(fontSize: 13)),
                  Text('฿${cart.total.toStringAsFixed(0)}',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (cart.hasExpiredHolds)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 6),
                        child: Text(
                            'Re-reserve or remove expired items to check out',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12)),
                      ),
                    FilledButton(
                      onPressed:
                          controller.isCheckingOut.value || !cart.canCheckout
                              ? null
                              : controller.checkout,
                      child: controller.isCheckingOut.value || cart.isReserving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Checkout'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildItems(CartService cart) {
    return Obx(() {
      if (cart.items.isEmpty) {
        return const Center(child: Text('Your bag is empty'));
      }
      return ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: cart.items.length,
        itemBuilder: (context, index) {
          final item = cart.items[index];
          final busy = item.status == HoldStatus.reserving;
          final expired = item.status == HoldStatus.expired;
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            color: expired ? Colors.grey.shade100 : Colors.white,
            elevation: 0.5,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  TheNetworkImage(
                    url: item.deal.imageUrl,
                    width: 64,
                    height: 64,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.deal.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 14.5, fontWeight: FontWeight.w600)),
                        Text(item.deal.storeName,
                            style: TextStyle(
                                fontSize: 12.5, color: Colors.grey.shade600)),
                        Text('฿${item.deal.price.toStringAsFixed(0)} each',
                            style: const TextStyle(
                                fontSize: 13,
                                color: AppConfig.primaryGreen,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        _HoldStatus(
                          item: item,
                          onRenew: () => cart.renew(item.deal.id),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed:
                            busy ? null : () => cart.decrement(item.deal.id),
                      ),
                      Text('${item.quantity}',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed:
                            busy || expired ? null : () => cart.add(item.deal),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
    });
  }
}

class _ExpiredNotices extends StatelessWidget {
  final List<String> messages;
  final VoidCallback onDismiss;

  const _ExpiredNotices({required this.messages, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Icon(Icons.timer_off_outlined,
                size: 20, color: Colors.orange.shade800),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(messages.join('\n'),
                  style: const TextStyle(fontSize: 13)),
            ),
          ),
          TextButton(onPressed: onDismiss, child: const Text('Dismiss')),
        ],
      ),
    );
  }
}

/// "Reserving…", a live "Held for mm:ss" (orange in the last minute), or
/// "Hold expired" with a Re-reserve action.
class _HoldStatus extends StatelessWidget {
  final CartItemModel item;
  final VoidCallback onRenew;

  const _HoldStatus({required this.item, required this.onRenew});

  @override
  Widget build(BuildContext context) {
    switch (item.status) {
      case HoldStatus.reserving:
        return Text('Reserving…',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600));
      case HoldStatus.expired:
        return Row(
          children: [
            Text('Hold expired',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.red.shade700)),
            const SizedBox(width: 8),
            InkWell(
              onTap: onRenew,
              child: const Text('Re-reserve',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppConfig.primaryGreen,
                      decoration: TextDecoration.underline)),
            ),
          ],
        );
      case HoldStatus.held:
        final expiresAt = item.reservation!.expiresAt;
        final clock = Get.find<ClockService>();
        return Obx(() {
          final left = expiresAt.difference(clock.now.value);
          final warn = left < const Duration(minutes: 1);
          return Text('Held for ${formatCountdown(left)}',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: warn ? FontWeight.w600 : FontWeight.normal,
                  color: warn ? Colors.orange.shade800 : Colors.grey.shade600,
                  fontFeatures: const [FontFeature.tabularFigures()]));
        });
    }
  }
}
