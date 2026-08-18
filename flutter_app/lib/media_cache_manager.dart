import 'package:flutter/painting.dart';

/// Manages explicit GPU texture lifecycle and LRU eviction for tool attachments
/// and media assets across active and inactive agent sessions.
class MediaCacheManager {
  MediaCacheManager._();

  static final MediaCacheManager instance = MediaCacheManager._();

  final Map<String, Set<Object>> _sessionMediaKeys = {};
  final List<String> _sessionLruOrder = [];

  /// Maximum inactive sessions whose media textures remain in memory.
  int maxRetainedInactiveSessions = 3;

  /// Registers an image cache key or ImageProvider with a given session.
  void registerMedia(String sessionId, Object key) {
    _sessionMediaKeys.putIfAbsent(sessionId, () => {}).add(key);
    _touchSession(sessionId);
    _trimInactiveSessions();
  }

  /// Called when a session becomes active in the viewport.
  void onSessionActivated(String sessionId) {
    _touchSession(sessionId);
    _trimInactiveSessions();
  }

  /// Evicts all media textures associated with [sessionId] from Flutter's ImageCache.
  void evictSession(String sessionId) {
    final keys = _sessionMediaKeys.remove(sessionId);
    _sessionLruOrder.remove(sessionId);
    if (keys != null) {
      for (final key in keys) {
        if (key is ImageProvider) {
          key.evict();
        } else {
          try {
            PaintingBinding.instance.imageCache.evict(key);
          } catch (_) {
            // Binding not initialized in unit tests
          }
        }
      }
    }
  }

  /// Evicts all registered media textures across all sessions.
  void evictAll() {
    for (final keys in _sessionMediaKeys.values) {
      for (final key in keys) {
        if (key is ImageProvider) {
          key.evict();
        } else {
          try {
            PaintingBinding.instance.imageCache.evict(key);
          } catch (_) {
            // Binding not initialized in unit tests
          }
        }
      }
    }
    _sessionMediaKeys.clear();
    _sessionLruOrder.clear();
    try {
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    } catch (_) {
      // Binding not initialized in unit tests
    }
  }

  void _touchSession(String sessionId) {
    _sessionLruOrder.remove(sessionId);
    _sessionLruOrder.add(sessionId);
  }

  void _trimInactiveSessions() {
    while (_sessionLruOrder.length > maxRetainedInactiveSessions + 1) {
      final oldestInactive = _sessionLruOrder.removeAt(0);
      evictSession(oldestInactive);
    }
  }

  /// Count of tracked sessions with media.
  int get trackedSessionsCount => _sessionMediaKeys.length;

  /// Total count of tracked media objects.
  int get totalTrackedMediaCount =>
      _sessionMediaKeys.values.fold(0, (acc, set) => acc + set.length);
}
