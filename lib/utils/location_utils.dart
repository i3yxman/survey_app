// lib/utils/location_utils.dart

import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

Future<Position?> determineUserPosition() async {
  try {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return null;
    }

    if (permission == LocationPermission.deniedForever) return null;

    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
  } catch (_) {
    return null;
  }
}

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
  );

  if (d < 1000) {
    return '${d.toStringAsFixed(0)} m';
  } else {
    return '${(d / 1000).toStringAsFixed(1)} km';
  }
}

double? calcDistanceKm(
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
  );

  return d / 1000.0;
}

Future<String?> reverseGeocodeCity(double lat, double lng) async {
  final placemarks = await placemarkFromCoordinates(lat, lng);
  if (placemarks.isEmpty) return null;

  final p = placemarks.first;

  // iOS/Android 一般会给 locality；直辖市/部分地区可能在 administrativeArea
  final city = (p.locality ?? '').trim();
  if (city.isNotEmpty) return city.endsWith('市') ? city : '$city市';

  final admin = (p.administrativeArea ?? '').trim();
  if (admin.isNotEmpty) return admin.endsWith('市') ? admin : '$admin市';

  return null;
}
