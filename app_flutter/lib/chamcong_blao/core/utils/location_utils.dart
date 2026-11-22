import 'package:geolocator/geolocator.dart';
import 'package:network_info_plus/network_info_plus.dart';
import '../../models/store_model.dart';

class LocationUtils {
  /// Normalize BSSID (MAC Address): trim, replace '-' with ':', and convert to lowercase.
  static String normalizeBssid(String value) {
    return value.trim().replaceAll('-', ':').toLowerCase();
  }

  /// Normalize SSID: strip quotes, trim, and reject invalid/dummy SSID values.
  static String? normalizeSsid(String? value) {
    if (value == null) return null;
    var cleaned = value.replaceAll('"', '').replaceAll("'", '').trim();
    if (cleaned.isEmpty ||
        cleaned.toLowerCase() == '<unknown ssid>' ||
        cleaned.toLowerCase() == 'null' ||
        cleaned.toLowerCase() == '0x') {
      return null;
    }
    return cleaned;
  }

  /// Validate if a BSSID is syntactically valid and not a placeholder (e.g. Android 02:00:00:00:00:00)
  static bool isValidBssid(String? bssid) {
    if (bssid == null) return false;
    final normalized = normalizeBssid(bssid);
    if (normalized.isEmpty ||
        normalized == '02:00:00:00:00:00' ||
        normalized == '00:00:00:00:00:00' ||
        normalized == 'ff:ff:ff:ff:ff:ff') {
      return false;
    }
    final macRegex = RegExp(r'^([0-9a-f]{2}:){5}[0-9a-f]{2}$');
    return macRegex.hasMatch(normalized);
  }

  /// Fetch WiFi SSID, BSSID (MAC address), and local IP of the current network connection.
  /// Public IP is intentionally NOT fetched here because attendance authentication relies on BSSID.
  static Future<({String? ssid, String? bssid, String? localIp})>
      getCurrentWifiDetails() async {
    String? wifiSsid;
    String? wifiBssid;
    String? localIp;

    // 1. Request location permission and initialize location state
    // (Both iOS & Android strictly require active location permission + location service to read WiFi SSID/BSSID)
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (serviceEnabled) {
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        if (permission == LocationPermission.whileInUse ||
            permission == LocationPermission.always) {
          // Warm up location so OS grants network SSID & BSSID access
          try {
            await Geolocator.getCurrentPosition(
              locationSettings: const LocationSettings(
                accuracy: LocationAccuracy.low,
                timeLimit: Duration(seconds: 3),
              ),
            );
          } catch (_) {}
        }
      }
    } catch (_) {}

    // 2. Fetch WiFi details via network_info_plus
    try {
      final info = NetworkInfo();

      // Read SSID
      final rawSsid = await info.getWifiName();
      wifiSsid = normalizeSsid(rawSsid);

      // Read BSSID
      final rawBssid = await info.getWifiBSSID();
      if (rawBssid != null && isValidBssid(rawBssid)) {
        wifiBssid = normalizeBssid(rawBssid);
      }

      // Read local IP (useful for diagnostics)
      final rawLocalIp = await info.getWifiIP();
      if (rawLocalIp != null && rawLocalIp.trim().isNotEmpty) {
        localIp = rawLocalIp.trim();
      }
    } catch (_) {}

    return (ssid: wifiSsid, bssid: wifiBssid, localIp: localIp);
  }

  /// Verify if the current device's WiFi BSSID matches any in the allowed StoreWifi list.
  /// Compares normalized exact BSSID. Returns false if BSSID is invalid or not matched.
  static Future<bool> isOnStoreWifi(List<StoreWifi> allowedWifis) async {
    final validAllowedBssids = allowedWifis
        .where((w) => isValidBssid(w.bssid))
        .map((w) => normalizeBssid(w.bssid))
        .toSet();

    if (validAllowedBssids.isEmpty) return false;

    try {
      final details = await getCurrentWifiDetails();
      if (details.bssid == null || !isValidBssid(details.bssid)) {
        return false;
      }
      final currentBssidNormalized = normalizeBssid(details.bssid!);
      return validAllowedBssids.contains(currentBssidNormalized);
    } catch (_) {
      return false;
    }
  }

  @Deprecated(
      'Use isOnStoreWifi with BSSID instead. Public IP is no longer used for attendance.')
  static Future<bool> isOnStoreNetwork(List<String> allowedIPs) async {
    return false;
  }

  static Future<bool> isInStoreRange(
      double lat, double lng, double radiusMeters) async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return false;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return false;
      }
      if (permission == LocationPermission.deniedForever) return false;

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      final distance =
          Geolocator.distanceBetween(lat, lng, pos.latitude, pos.longitude);
      return distance <= radiusMeters;
    } catch (_) {
      return false;
    }
  }

  /// Check user current position against a list of StoreLocation objects.
  /// Returns inRange, matchedLocation (if any), nearestLocation, and minDistance in meters.
  static Future<
      ({
        bool inRange,
        StoreLocation? matchedLocation,
        StoreLocation? nearestLocation,
        double? minDistance,
      })> checkLocationsRange(List<StoreLocation> locations) async {
    if (locations.isEmpty) {
      return (
        inRange: false,
        matchedLocation: null,
        nearestLocation: null,
        minDistance: null,
      );
    }

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return (
          inRange: false,
          matchedLocation: null,
          nearestLocation: null,
          minDistance: null,
        );
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return (
            inRange: false,
            matchedLocation: null,
            nearestLocation: null,
            minDistance: null,
          );
        }
      }
      if (permission == LocationPermission.deniedForever) {
        return (
          inRange: false,
          matchedLocation: null,
          nearestLocation: null,
          minDistance: null,
        );
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      StoreLocation? matchedLoc;
      StoreLocation? nearestLoc;
      double? minDistance;

      for (final loc in locations) {
        final dist = Geolocator.distanceBetween(
          loc.latitude,
          loc.longitude,
          pos.latitude,
          pos.longitude,
        );

        if (minDistance == null || dist < minDistance) {
          minDistance = dist;
          nearestLoc = loc;
        }

        if (dist <= loc.radiusMeters && matchedLoc == null) {
          matchedLoc = loc;
        }
      }

      return (
        inRange: matchedLoc != null,
        matchedLocation: matchedLoc,
        nearestLocation: nearestLoc,
        minDistance: minDistance,
      );
    } catch (_) {
      return (
        inRange: false,
        matchedLocation: null,
        nearestLocation: null,
        minDistance: null,
      );
    }
  }
}
