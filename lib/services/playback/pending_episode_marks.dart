import 'dart:convert';

import 'package:baka/core/app_logger.dart';
import 'package:baka/services/account/bangumi_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Bangumi 单集「看过」上报失败时的补推队列。
///
/// 只记录 (条目, 集号)，同一集重复失败只留一条；补推成功后删除。
/// 存在 SharedPreferences 里，登出不清空，换号后由 [flush] 前的
/// `isConnected` 判断兜底。
class PendingEpisodeMarks {
  PendingEpisodeMarks._();

  static const _key = 'bangumi_pending_episode_marks';

  static List<({int bgmId, num sort})> load(SharedPreferences prefs) {
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      return [
        for (final item in list)
          if (item is Map)
            (
              bgmId: (item['bgmId'] as num?)?.toInt() ?? 0,
              sort: (item['sort'] as num?) ?? 0,
            ),
      ].where((entry) => entry.bgmId > 0 && entry.sort > 0).toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> add(
    SharedPreferences prefs,
    int bgmId,
    num sort,
  ) async {
    if (bgmId <= 0 || sort <= 0) return;
    final current = load(prefs);
    if (current.any((e) => e.bgmId == bgmId && e.sort == sort)) return;
    final next = [...current, (bgmId: bgmId, sort: sort)];
    await prefs.setString(_key, _encode(next));
  }

  static Future<void> remove(
    SharedPreferences prefs,
    int bgmId,
    num sort,
  ) async {
    final current = load(prefs);
    final next = current
        .where((e) => !(e.bgmId == bgmId && e.sort == sort))
        .toList();
    if (next.length == current.length) return;
    await prefs.setString(_key, _encode(next));
  }

  /// 逐条补推；失败的留在队列里等下次启动或下次播放。
  /// 返回补推成功的条数。
  static Future<int> flush(BangumiSession session) async {
    if (!session.isConnected) return 0;
    final pending = load(session.preferences);
    if (pending.isEmpty) return 0;
    var done = 0;
    for (final item in pending) {
      try {
        final ok = await session.setEpisodeWatched(
          subjectId: item.bgmId,
          episodeNumber: item.sort,
          watched: true,
        );
        // 返回 false 表示 Bangumi 上没有这一集，重试也不会成功，直接丢弃。
        await remove(session.preferences, item.bgmId, item.sort);
        if (ok) done++;
      } catch (error) {
        Log.w('History', '补推第 ${item.sort} 集失败，留到下次', error);
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    if (done > 0) Log.i('History', '补推 Bangumi 单集标记 $done 条');
    return done;
  }

  static String _encode(List<({int bgmId, num sort})> items) => jsonEncode([
    for (final item in items) {'bgmId': item.bgmId, 'sort': item.sort},
  ]);
}
