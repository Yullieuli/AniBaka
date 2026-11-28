import 'package:baka/core/content_filter.dart';
import 'package:flutter/material.dart';

import 'package:baka/api/bgm.dart';
import 'package:baka/widgets/anime/post_card.dart';
import 'package:baka/widgets/common/skeletonizer.dart';

/// 详情页的相关动画。只读取关系列表，不为每个条目额外预取详情。
///
/// 参考 Animeko：每张卡片标出关系（续集 / 剧场版 / 外传…），
/// 按「主线 → 外传 → 其他」排，同组按年份，比一张无标注的海报墙好认。
class AnimeDetailRelatedSection extends StatefulWidget {
  const AnimeDetailRelatedSection({
    required this.subjectId,
    required this.onAnimeTap,
    super.key,
  });

  final int subjectId;
  final ValueChanged<Map<String, dynamic>> onAnimeTap;

  @override
  State<AnimeDetailRelatedSection> createState() =>
      _AnimeDetailRelatedSectionState();
}

class _AnimeDetailRelatedSectionState extends State<AnimeDetailRelatedSection>
    with AutomaticKeepAliveClientMixin {
  late Future<List<Map<String, dynamic>>> _items = _load(widget.subjectId);

  @override
  bool get wantKeepAlive => true;

  @override
  void didUpdateWidget(covariant AnimeDetailRelatedSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.subjectId != widget.subjectId) {
      _items = _load(widget.subjectId);
    }
  }

  static Future<List<Map<String, dynamic>>> _load(int subjectId) async {
    final response = await getBgmRelatedSubjects(subjectId);
    final items = [
      for (final raw in response)
        if (raw['type'] == 2)
          {
            'id': raw['id'],
            'bgmId': raw['id'],
            'nsfw': raw['nsfw'] == true,
            'title': ((raw['name_cn'] as String?) ?? '').isEmpty
                ? raw['name']
                : raw['name_cn'],
            'bgmImageUrl': (raw['images'] as Map)['large'],
            'sort': '番剧',
            'tag': raw['relation'],
            'info': raw['relation'],
            'date': raw['date'],
            'source': 'bgm',
          },
    ];
    items.sort(_compare);
    return items;
  }

  /// 主线优先，其次外传 / 总集篇，最后其他；同组按放送日期。
  static int _compare(Map<String, dynamic> a, Map<String, dynamic> b) {
    final rank = _relationRank(a['tag']).compareTo(_relationRank(b['tag']));
    if (rank != 0) return rank;
    return _dateKey(a['date']).compareTo(_dateKey(b['date']));
  }

  static int _relationRank(Object? relation) {
    return switch (relation?.toString() ?? '') {
      '主线故事' || '前传' || '续集' => 0,
      '番外篇' || '总集篇' => 1,
      '衍生' || '不同演绎' || '角色出演' => 2,
      _ => 3,
    };
  }

  static String _dateKey(Object? date) =>
      date is String && date.isNotEmpty ? date : '9999-99-99';

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ListenableBuilder(
      listenable: contentFilter,
      builder: (context, _) => FutureBuilder<List<Map<String, dynamic>>>(
        future: _items,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done &&
              snapshot.hasError) {
            return const Center(child: Text('相关动画加载失败'));
          }
          final loading = snapshot.connectionState != ConnectionState.done;
          final items = contentFilter.visibleItems(
            snapshot.data ?? const <Map<String, dynamic>>[],
          );
          if (!loading && items.isEmpty) {
            return const Center(child: Text('暂无相关动画'));
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!loading)
                Padding(
                  padding: const EdgeInsets.only(left: 2, bottom: 12),
                  child: Text(
                    '共 ${items.length} 部 · 按系列顺序排列',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              SizedBox(
                height: 286,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: loading ? 5 : items.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 14),
                  itemBuilder: (context, index) {
                    final item = loading
                        ? const <String, dynamic>{
                            'title': '相关动画标题占位',
                            'image': '',
                          }
                        : items[index];
                    return SizedBox(
                      width: 140,
                      child: AppSkeletonizer(
                        enabled: loading,
                        child: _RelatedCard(
                          item: item,
                          onTap: () {
                            if (!loading) widget.onAnimeTap(item);
                          },
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _RelatedCard extends StatefulWidget {
  const _RelatedCard({required this.item, required this.onTap});

  final Map<String, dynamic> item;
  final VoidCallback onTap;

  @override
  State<_RelatedCard> createState() => _RelatedCardState();
}

class _RelatedCardState extends State<_RelatedCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final relation = widget.item['tag']?.toString() ?? '';
    final year = _yearOf(widget.item['date']);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedScale(
              scale: _hovered ? 1.03 : 1,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              child: AspectRatio(
                aspectRatio: 2 / 3,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      buildCachedImage(widget.item, 140, 210),
                      if (relation.isNotEmpty)
                        Positioned(
                          left: 6,
                          top: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.62),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              relation,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                height: 1.2,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.item['title']?.toString() ?? '',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.25,
                fontWeight: FontWeight.w600,
                color: _hovered ? colors.primary : colors.onSurface,
              ),
            ),
            if (year != null) ...[
              const SizedBox(height: 2),
              Text(
                year,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.2,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String? _yearOf(Object? date) {
    if (date is! String) return null;
    final match = RegExp(r'^(\d{4})').firstMatch(date.trim());
    return match?.group(1);
  }
}
