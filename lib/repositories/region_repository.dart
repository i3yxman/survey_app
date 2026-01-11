// lib/repositories/region_repository.dart

import '../services/api_service.dart';

class RegionRepository {
  final ApiService _api;

  RegionRepository({ApiService? apiService})
      : _api = apiService ?? ApiService();

  Future<List<Map<String, dynamic>>> fetchRegions() async {
    return _api.getRegions();
  }
}
