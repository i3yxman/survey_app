// lib/providers/location_provider.dart

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../utils/location_utils.dart';

/// 统一管理当前用户定位的全局 Provider
///
/// - 整个 App 只负责拿一次定位，存在这里
/// - 各个页面（任务大厅 / 我的任务等）只读这个 Provider，不自己去调 Geolocator
class LocationProvider extends ChangeNotifier {
  Position? _position;
  bool _isLoading = false;
  String? _error;

  Position? get position => _position;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// 确保有一次定位：
  /// - 如果已经有 position 了，就不会重复请求
  /// - 如果正在请求，就直接返回
  Future<void> ensureLocation() async {
    if (_position != null || _isLoading) {
      return;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final pos = await determineUserPosition();
      _position = pos;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 手动刷新定位（比如用户下拉刷新时）
  Future<void> refresh() async {
    _position = null;
    await ensureLocation();
  }
}