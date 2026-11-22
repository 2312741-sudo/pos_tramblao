import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:network_info_plus/network_info_plus.dart';
import '../../store/providers/store_provider.dart';
import '../../../core/utils/location_utils.dart';
import '../../../models/store_model.dart';

// ---------- Location permission ----------

final locationPermissionProvider = FutureProvider<bool>((ref) async {
  try {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return false;
    }
    if (permission == LocationPermission.deniedForever) return false;
    return true;
  } catch (_) {
    return false;
  }
});

// ---------- Current position ----------

final currentPositionProvider = FutureProvider<Position?>((ref) async {
  final hasPermission = await ref.watch(locationPermissionProvider.future);
  if (!hasPermission) return null;

  try {
    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 10),
      ),
    );
  } catch (_) {
    return null;
  }
});

// ---------- Current WiFi IP ----------

final currentWifiIPProvider = FutureProvider<String?>((ref) async {
  try {
    final info = NetworkInfo();
    final ip = await info.getWifiIP();
    return ip?.trim();
  } catch (_) {
    return null;
  }
});

// ---------- Can check-in composite ----------

typedef CheckInStatus = ({bool canCheck, bool isWifi, bool isGps});

final canCheckInProvider = FutureProvider<CheckInStatus>((ref) async {
  final store = ref.watch(currentStoreProvider).whenOrNull(data: (s) => s);
  if (store == null) {
    return (canCheck: false, isWifi: false, isGps: false);
  }

  // WiFi check
  bool isWifi = false;
  if (store.hasWifi) {
    try {
      final validWifis = store.wifis.where((w) => w.hasValidBssid).toList();
      if (validWifis.isNotEmpty) {
        isWifi = await LocationUtils.isOnStoreWifi(validWifis);
      }
    } catch (_) {
      isWifi = false;
    }
  }

  // GPS check
  bool isGps = false;
  if (store.hasLocation) {
    try {
      final position = await ref.watch(currentPositionProvider.future);
      if (position != null) {
        if (store.locations.isNotEmpty) {
          isGps = store.locations.any((loc) {
            final distanceMeters = Geolocator.distanceBetween(
              position.latitude,
              position.longitude,
              loc.latitude,
              loc.longitude,
            );
            return distanceMeters <= loc.radiusMeters;
          });
        } else if (store.latitude != null && store.longitude != null) {
          final distanceMeters = Geolocator.distanceBetween(
            position.latitude,
            position.longitude,
            store.latitude!,
            store.longitude!,
          );
          isGps = distanceMeters <= store.radiusMeters;
        }
      }
    } catch (_) {
      isGps = false;
    }
  }

  final canCheck = isWifi || isGps;
  return (canCheck: canCheck, isWifi: isWifi, isGps: isGps);
});

// ---------- Distance to store (meters) ----------

final distanceToStoreProvider = FutureProvider<double?>((ref) async {
  try {
    final store = ref.watch(currentStoreProvider).whenOrNull(data: (s) => s);
    if (store == null || !store.hasLocation) return null;

    final position = await ref.watch(currentPositionProvider.future);
    if (position == null) return null;

    if (store.locations.isNotEmpty) {
      double? minDistance;
      for (final loc in store.locations) {
        final dist = Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          loc.latitude,
          loc.longitude,
        );
        if (minDistance == null || dist < minDistance) {
          minDistance = dist;
        }
      }
      return minDistance;
    }

    if (store.latitude != null && store.longitude != null) {
      return Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        store.latitude!,
        store.longitude!,
      );
    }

    return null;
  } catch (_) {
    return null;
  }
});

// ---------- Nearest Store Location ----------

final nearestStoreLocationProvider =
    FutureProvider<StoreLocation?>((ref) async {
  try {
    final store = ref.watch(currentStoreProvider).whenOrNull(data: (s) => s);
    if (store == null || !store.hasLocation || store.locations.isEmpty)
      return null;

    final position = await ref.watch(currentPositionProvider.future);
    if (position == null) return null;

    StoreLocation? nearest;
    double? minDistance;
    for (final loc in store.locations) {
      final dist = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        loc.latitude,
        loc.longitude,
      );
      if (minDistance == null || dist < minDistance) {
        minDistance = dist;
        nearest = loc;
      }
    }
    return nearest;
  } catch (_) {
    return null;
  }
});
