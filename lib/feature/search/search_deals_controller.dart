import 'package:get/get.dart';

import '../../model/deal_model.dart';
import '../../repository/deal_repo.dart';
import '../../util/log_service.dart';

class SearchDealsController extends GetxController {
  final DealRepo dealRepo;

  SearchDealsController({required this.dealRepo});

  final results = <DealModel>[].obs;
  final isLoading = false.obs;
  final hasSearched = false.obs;

  int _latestRequest = 0;

  void onQueryChanged(String query) {
    search(query);
  }

  Future<void> search(String query) async {
    // Responses can arrive out of order; only the latest request may apply.
    final request = ++_latestRequest;
    if (query.trim().isEmpty) {
      results.clear();
      hasSearched.value = false;
      isLoading.value = false;
      return;
    }
    isLoading.value = true;
    hasSearched.value = true;
    try {
      final found = await dealRepo.search(query);
      if (request != _latestRequest) return;
      results.assignAll(found);
    } catch (e) {
      if (request != _latestRequest) return;
      LogService.error('search failed', e);
    }
    isLoading.value = false;
  }
}
