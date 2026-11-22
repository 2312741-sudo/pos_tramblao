import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../store/providers/store_provider.dart';
import '../repositories/production_repository.dart';
import '../../../models/production_model.dart';

final productionRepositoryProvider = Provider<ProductionRepository>((ref) {
  return ProductionRepository();
});

final activeProductionTasksProvider = StreamProvider<List<ProductionTask>>((ref) {
  final storeId = ref.watch(currentStoreIdProvider);
  if (storeId == null || storeId.isEmpty) return Stream.value([]);
  
  final repo = ref.watch(productionRepositoryProvider);
  return repo.watchActiveTasks(storeId);
});

final allProductionTasksProvider = StreamProvider<List<ProductionTask>>((ref) {
  final storeId = ref.watch(currentStoreIdProvider);
  if (storeId == null || storeId.isEmpty) return Stream.value([]);
  
  final repo = ref.watch(productionRepositoryProvider);
  return repo.watchAllTasks(storeId);
});
