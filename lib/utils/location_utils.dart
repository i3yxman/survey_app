// lib/utils/location_utils.dart

import 'package:geolocator/geolocator.dart';

/// 统一封装定位：
/// - 不抛异常，失败时返回 null
/// - 内部处理好权限 & 服务开关
Future<Position?> determineUserPosition() async {
  // debugPrint('LOC UTIL: start determineUserPosition()');

  try {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    // debugPrint('LOC UTIL: serviceEnabled = $serviceEnabled');
    if (!serviceEnabled) {
      return null;
    }

    var permission = await Geolocator.checkPermission();
    // debugPrint('LOC UTIL: permission(before) = $permission');

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      // debugPrint('LOC UTIL: permission(after request) = $permission');
      if (permission == LocationPermission.denied) {
        return null;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      // debugPrint('LOC UTIL: permission = deniedForever');
      return null;
    }

    final pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
    // debugPrint(
    //     'LOC UTIL: got position = (${pos.latitude}, ${pos.longitude})');
    return pos;
  } catch (e) {
    // debugPrint('LOC UTIL ERROR: $e');
    return null;
  }
}

/// 把门店坐标转换成 “123 m” / “1.2 km”
/// currentPosition 为空 or 门店坐标为空时，返回 null
String? formatStoreDistance(
  Position? currentPosition,
  double? storeLat,
  double? storeLng,
) {
  if (currentPosition == null || storeLat == null || storeLng == null) {
    return null;
  }

  final d = Geolocator.distanceBetween(
    currentPosition.latitude,
    currentPosition.longitude,
    storeLat,
    storeLng,
  ); // 米

  if (d < 1000) {
    return '${d.toStringAsFixed(0)} m';
  } else {
    return '${(d / 1000).toStringAsFixed(1)} km';
  }
}
