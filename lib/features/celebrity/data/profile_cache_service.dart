import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class ProfileCacheService {
  static const String _cacheKey = 'celebrity_profile_cache';
  static const Duration _cacheDuration = Duration(days: 7);

  // Save profile link to cache
  static Future<void> saveProfileLink(String galleryUrl, String profileLink) async {
    final prefs = await SharedPreferences.getInstance();
    final cacheData = await _getCacheData();

    cacheData[galleryUrl] = {
      'profileLink': profileLink,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    await prefs.setString(_cacheKey, json.encode(cacheData));
  }

  // Get profile link from cache
  static Future<String?> getProfileLink(String galleryUrl) async {
    final cacheData = await _getCacheData();

    if (cacheData.containsKey(galleryUrl)) {
      final entry = cacheData[galleryUrl];
      final timestamp = entry['timestamp'] as int;
      final cacheTime = DateTime.fromMillisecondsSinceEpoch(timestamp);

      // Check if cache is still valid
      if (DateTime.now().difference(cacheTime) < _cacheDuration) {
        return entry['profileLink'] as String;
      } else {
        // Remove expired cache
        await _removeCacheEntry(galleryUrl);
      }
    }

    return null;
  }

  // Get all cached data
  static Future<Map<String, dynamic>> _getCacheData() async {
    final prefs = await SharedPreferences.getInstance();
    final cacheString = prefs.getString(_cacheKey);

    if (cacheString != null && cacheString.isNotEmpty) {
      try {
        return json.decode(cacheString) as Map<String, dynamic>;
      } catch (e) {
        return {};
      }
    }

    return {};
  }

  // Remove single cache entry
  static Future<void> _removeCacheEntry(String galleryUrl) async {
    final prefs = await SharedPreferences.getInstance();
    final cacheData = await _getCacheData();
    cacheData.remove(galleryUrl);
    await prefs.setString(_cacheKey, json.encode(cacheData));
  }

  // Clear all cache
  static Future<void> clearAllCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cacheKey);
  }
}
