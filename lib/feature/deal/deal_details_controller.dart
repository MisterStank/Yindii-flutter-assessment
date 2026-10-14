import 'package:get/get.dart';

import '../../model/deal_model.dart';
import '../../repository/deal_repo.dart';
import '../../service/analytics_service.dart';
import '../../service/cart_service.dart';
import '../../util/log_service.dart';

class DealDetailsController extends GetxController {
  final DealRepo dealRepo;
  final CartService cartService;
  final AnalyticsService analytics;

  DealDetailsController({
    required this.dealRepo,
    required this.cartService,
    required this.analytics,
  });

  /// From the route's `?id=`; `arguments` is only an optional preloaded copy.
  late final int? dealId;

  final _deal = Rxn<DealModel>();
  DealModel? get deal => _deal.value;

  final loadFailed = false.obs;

  late final Worker _cartWorker;

  final _quantityLeft = RxnInt();
  int? get quantityLeft => _quantityLeft.value;

  @override
  void onInit() {
    super.onInit();
    final preloaded = Get.arguments;
    if (preloaded is DealModel) {
      dealId = preloaded.id;
      _setDeal(preloaded);
    } else {
      dealId = int.tryParse(Get.parameters['id'] ?? '');
      loadDeal();
    }
    analytics.logEvent('deal_details_view', {
      'deal_id': dealId,
      'source': Get.parameters['source'] ?? 'unknown',
    });
    // Whenever the cart changes, re-check this deal's remaining stock so the
    // details screen never shows stale availability.
    _cartWorker = ever(cartService.itemCount, (_) => _recheckAvailability());
  }

  @override
  void onClose() {
    // CartService outlives this controller, so the subscription must be
    // cancelled explicitly.
    _cartWorker.dispose();
    super.onClose();
  }

  Future<void> loadDeal() async {
    final id = dealId;
    if (id == null) {
      loadFailed.value = true;
      return;
    }
    loadFailed.value = false;
    try {
      _setDeal(await dealRepo.fetchById(id));
    } catch (e) {
      LogService.error('load deal $id failed', e);
      loadFailed.value = true;
    }
  }

  void _setDeal(DealModel deal) {
    _deal.value = deal;
    _quantityLeft.value = deal.quantityLeft;
  }

  Future<void> _recheckAvailability() async {
    final id = dealId;
    if (id == null) return;
    LogService.log('re-checking availability for deal $id');
    final fresh = await dealRepo.fetchById(id);
    _quantityLeft.value = fresh.quantityLeft;
  }

  void addToCart() {
    final deal = this.deal;
    if (deal == null || deal.isFlashExpired) return;
    cartService.add(deal);
    Get.snackbar(
      'Added to bag',
      '${deal.name} — pick up ${deal.pickupWindow.label}',
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 2),
    );
  }
}
