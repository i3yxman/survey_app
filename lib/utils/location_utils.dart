// lib/utils/location_utils.dart

import 'package:geolocator/geolocator.dart';

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
