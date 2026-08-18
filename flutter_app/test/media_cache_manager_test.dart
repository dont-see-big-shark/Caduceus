import 'package:flutter_test/flutter_test.dart';
import 'package:caduceus/media_cache_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('MediaCacheManager tracks and evicts session media', () {
    final manager = MediaCacheManager.instance;
    manager.maxRetainedInactiveSessions = 2;

    // Register media for 4 sessions
    manager.registerMedia('sess-1', 'key-1-a');
    manager.registerMedia('sess-1', 'key-1-b');
    manager.registerMedia('sess-2', 'key-2-a');
    manager.registerMedia('sess-3', 'key-3-a');
    manager.registerMedia('sess-4', 'key-4-a');

    // With max 2 inactive + 1 active (3 total), sess-1 should have been evicted
    expect(manager.trackedSessionsCount, lessThanOrEqualTo(3));

    // Manually evict sess-4
    manager.evictSession('sess-4');
    expect(manager.totalTrackedMediaCount, lessThanOrEqualTo(2));

    // Evict all
    manager.evictAll();
    expect(manager.trackedSessionsCount, equals(0));
    expect(manager.totalTrackedMediaCount, equals(0));
  });
}
