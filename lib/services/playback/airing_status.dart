import 'package:baka/api/bgm.dart';
import 'package:baka/core/app_logger.dart';

/// 一部番在放送时间上的事实：哪一集已经播了、下一集什么时候播。
///
/// 这些全部由 Bangumi 分集的 `airdate` 推出来，不看每周放送日历。
/// 日历只说明「这部番通常排在这天」，遇到停播、延期、总集篇时
/// 仍然会把条目列在当天，于是首页会误报「今日更新」。
class AiringFacts {
  const AiringFacts({
    required this.episodeCount,
    this.todaySort,
    this.latestAiredSort,
    this.latestAiredDate,
    this.nextSort,
    this.nextAirDate,
  });

  const AiringFacts.empty() : this(episodeCount: 0);

  /// 本篇集数（只有带 airdate 的才算）。
  final int episodeCount;

  /// 今天播出的那一集的集号。
  final num? todaySort;

  /// 最近一次已播出的集号与日期。
  final num? latestAiredSort;
  final DateTime? latestAiredDate;

  /// 下一集（尚未播出）的集号与日期。
  final num? nextSort;
  final DateTime? nextAirDate;

  bool get isEmpty => episodeCount == 0;

  /// 已经播完：有分集，但没有待播的下一集。
  bool get finished => episodeCount > 0 && nextAirDate == null;
}

const _ttl = Duration(minutes: 30);
const _maxCachedSubjects = 400;

final _facts = <int, AiringFacts>{};
final _fetchedAt = <int, DateTime>{};
final _loading = <int, Future<AiringFacts?>>{};

/// 取一部番的放送事实。结果在内存里缓存半小时，失败不缓存。
Future<AiringFacts?> loadAiringFacts(int bgmId, {bool force = false}) {
  if (bgmId <= 0) return Future.value(null);
  final cached = _facts[bgmId];
  final fetchedAt = _fetchedAt[bgmId];
  if (!force && cached != null && fetchedAt != null) {
    if (DateTime.now().difference(fetchedAt) < _ttl) return Future.value(cached);
  }
  final pending = _loading[bgmId];
  if (pending != null) return pending;

  final future = _fetch(bgmId);
  _loading[bgmId] = future;
  return future.whenComplete(() => _loading.remove(bgmId));
}

/// 同步读缓存，用于排序；没加载过时返回 null。
AiringFacts? peekAiringFacts(int bgmId) => _facts[bgmId];

Future<AiringFacts?> _fetch(int bgmId) async {
  try {
    final episodes = await getBgmEpisodes(bgmId);
    final facts = buildAiringFacts(episodes);
    if (_facts.length >= _maxCachedSubjects) {
      _facts.clear();
      _fetchedAt.clear();
    }
    _facts[bgmId] = facts;
    _fetchedAt[bgmId] = DateTime.now();
    return facts;
  } catch (error, stackTrace) {
    Log.w('Airing', '读取分集放送时间失败: $bgmId', error, stackTrace);
    return null;
  }
}

/// 从分集列表算出放送事实，独立于任何用户进度。
AiringFacts buildAiringFacts(List<Map<String, dynamic>> episodes) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  var count = 0;
  num? todaySort;
  num? latestAiredSort;
  DateTime? latestAiredDate;
  num? nextSort;
  DateTime? nextAirDate;

  for (final episode in episodes) {
    final date = _parseAirDate(episode['airdate']);
    if (date == null) continue;
    final sort = episode['sort'];
    if (sort is! num) continue;
    count++;

    if (date.isAfter(today)) {
      if (nextAirDate == null ||
          date.isBefore(nextAirDate) ||
          (date == nextAirDate && sort < (nextSort ?? sort))) {
        nextAirDate = date;
        nextSort = sort;
      }
      continue;
    }
    if (date == today) {
      if (todaySort == null || sort > todaySort) todaySort = sort;
    }
    if (latestAiredDate == null ||
        date.isAfter(latestAiredDate) ||
        (date == latestAiredDate && sort > (latestAiredSort ?? sort))) {
      latestAiredDate = date;
      latestAiredSort = sort;
    }
  }

  return AiringFacts(
    episodeCount: count,
    todaySort: todaySort,
    latestAiredSort: latestAiredSort,
    latestAiredDate: latestAiredDate,
    nextSort: nextSort,
    nextAirDate: nextAirDate,
  );
}

/// 卡片上要显示的两个位置：左上角角标、标题下方的一句提示。
/// [watchedSort] 是用户看到第几话（Bangumi 集号），未知时传 null。
({String? badge, String? hint}) describeAiring(
  AiringFacts facts, {
  num? watchedSort,
}) {
  if (facts.isEmpty) return (badge: null, hint: null);

  final todaySort = facts.todaySort;
  if (todaySort != null) {
    return (badge: '今日更新', hint: '第 ${formatEpisodeSort(todaySort)} 话已播出');
  }

  final latest = facts.latestAiredSort;
  final latestDate = facts.latestAiredDate;
  final fresh =
      latestDate != null &&
      DateTime.now().difference(latestDate).inDays <= 7;
  if (latest != null &&
      fresh &&
      (watchedSort == null || latest > watchedSort)) {
    return (badge: '有新集', hint: '第 ${formatEpisodeSort(latest)} 话已更新');
  }

  final next = facts.nextAirDate;
  if (next != null) {
    return (badge: null, hint: '${formatNextAirDate(next)}更新');
  }

  return (badge: null, hint: '已完结');
}

String formatEpisodeSort(num sort) =>
    sort == sort.round() ? sort.toInt().toString() : '$sort';

/// 今天为正，往后数到 7 天用口语，再远就给日期。
String formatNextAirDate(DateTime date, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final start = DateTime(today.year, today.month, today.day);
  final day = DateTime(date.year, date.month, date.day);
  final diff = day.difference(start).inDays;
  if (diff <= 0) return '今天';
  if (diff == 1) return '明天';
  if (diff < 7) return _weekdayName(day.weekday);
  if (diff == 7) return '下${_weekdayName(day.weekday)}';
  return '${day.month}月${day.day}日';
}

String _weekdayName(int weekday) =>
    const ['周一', '周二', '周三', '周四', '周五', '周六', '周日'][weekday - 1];

final _airDatePattern = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})');

DateTime? _parseAirDate(Object? raw) {
  if (raw is! String) return null;
  final match = _airDatePattern.firstMatch(raw.trim());
  if (match == null) return null;
  final year = int.tryParse(match.group(1)!);
  final month = int.tryParse(match.group(2)!);
  final day = int.tryParse(match.group(3)!);
  if (year == null || month == null || day == null) return null;
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  return DateTime(year, month, day);
}
