class VersionUtils {
  VersionUtils._();

  /// Compares two SemVer strings (e.g. "1.0.4" vs "1.0.5", "1.0.5+7" vs "1.0.6").
  /// Returns:
  /// - < 0 if v1 < v2
  /// - 0 if v1 == v2
  /// - > 0 if v1 > v2
  static int compare(String v1, String v2) {
    final cleanV1 = _cleanVersion(v1);
    final cleanV2 = _cleanVersion(v2);

    final parts1 = cleanV1.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final parts2 = cleanV2.split('.').map((p) => int.tryParse(p) ?? 0).toList();

    final maxLen = parts1.length > parts2.length ? parts1.length : parts2.length;

    for (int i = 0; i < maxLen; i++) {
      final num1 = i < parts1.length ? parts1[i] : 0;
      final num2 = i < parts2.length ? parts2[i] : 0;

      if (num1 != num2) {
        return num1.compareTo(num2);
      }
    }

    return 0;
  }

  /// Returns true if [current] is strictly less than [target]
  static bool isBelow(String current, String target) {
    return compare(current, target) < 0;
  }

  /// Returns true if [current] is greater than or equal to [target]
  static bool isAtLeast(String current, String target) {
    return compare(current, target) >= 0;
  }

  /// Strips build number and metadata (e.g. "1.0.5+7" -> "1.0.5", "v1.2.0-beta" -> "1.2.0")
  static String _cleanVersion(String v) {
    String clean = v.trim().toLowerCase();
    if (clean.startsWith('v')) {
      clean = clean.substring(1);
    }
    if (clean.contains('+')) {
      clean = clean.split('+').first;
    }
    if (clean.contains('-')) {
      clean = clean.split('-').first;
    }
    return clean;
  }
}
