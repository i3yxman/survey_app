// lib/providers/location_provider.dart

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

import '../utils/location_utils.dart';

class LocationProvider extends ChangeNotifier {
  Position? _position;
  String? _city; // ✅ 新增：当前城市（如 “上海市”）
  bool _isLoading = false;
  String? _error;

  Position? get position => _position;
  String? get city => _city;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> ensureLocation() async {
    if (_position != null || _isLoading) return;

    _isLoading = true;
    _error = null;
    notifyListeners();

    final pos = await determineUserPosition();

    if (pos == null) {
      _position = null;
      _city = null;
      _error = '定位不可用：请开启定位服务并授予权限';
      _isLoading = false;
      notifyListeners();
      return;
    }

    _position = pos;

    // ✅ 反地理编码：经纬度 -> 城市
    try {
      final places = await placemarkFromCoordinates(
        pos.latitude,
        pos.longitude,
      );

      final p = places.isNotEmpty ? places.first : null;

      // iOS/Android 返回字段不完全一致：locality / subAdministrativeArea / administrativeArea
      final raw = (p?.locality ?? p?.subAdministrativeArea ?? '').trim();
      if (raw.isNotEmpty) {
        _city = raw.endsWith('市') ? raw : '$raw市';
      } else {
        _city = null;
      }
    } catch (_) {
      _city = null; // 失败就保持未知，不影响其它功能
    }

    _error = null;
    _isLoading = false;
    notifyListeners();
  }

  Future<void> refresh() async {
    _position = null;
    _city = null;
    await ensureLocation();
  }
}
