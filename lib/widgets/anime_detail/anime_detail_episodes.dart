import 'package:baka/api/bgm.dart';
import 'package:baka/core/app_logger.dart';
import 'package:baka/services/playback/airing_status.dart';
import 'package:baka/services/playback/history_repository.dart';
import 'package:flutter/material.dart';

/// 详情页的选集区，对齐 Animeko：直接铺在概览里，不藏在分页后面。
///
/// - 标题旁给出真实放送状态（今日更新 / 下周六更新 / 已完结），来自分集 airdate；
/// - 一页 8 集，超过一页给翻页控件，避免长篇把详情页拉得很长；
/// - 点某一集就从这一集重新匹配源，没这一集的源会被跳过。
class AnimeDetailEpisodes extends StatefulWidget {
  const AnimeDetailEpisodes({
    required this.subjectId,
    required this.onEpisodeTap,
    this.pageSize = 8,
    super.key,
  });

  final int subjectId;

  /// 参数是分集在本篇列表里的下标（0 起算），播放器按它对齐目标集。
  final ValueChanged<int> onEpisodeTap;
  final int pageSize;

  @override
  State<AnimeDetailEpisodes> createState() => _AnimeDetailEpisodesState();
}

class _AnimeDetailEpisodesState extends State<AnimeDetailEpisodes> {
  late Future<List<Map<String, dynamic>>> _episodes = _load();
  int _page = 0;

  Future<List<Map<String, dynamic>>> _load() async {
    try {
      return await getBgmEpisodes(widget.subjectId);
    } catch (error, stackTrace) {
      Log.w('Detail', '读取分集失败: ${widget.subjectId}', error, stackTrace);
      rethrow;
    }
  }

  @override
  void didUpdateWidget(covariant AnimeDetailEpisodes oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.subjectId != widget.subjectId) {
      _episodes = _load();
      _page = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _episodes,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: TextButton(
                onPressed: () => setState(() => _episodes = _load()),
                child: const Text('分集加载失败，点击重试'),
              ),
            ),
          );
        }
        final episodes = snapshot.data ?? const <Map<String, dynamic>>[];
        if (episodes.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text('暂无分集信息')),
          );
        }

        final watchedIndexes = <int>[
          for (var i = 0; i < episodes.length; i++)
            if (HistoryRepository.watchedAt(widget.subjectId, i)) i,
        ];
        final facts = buildAiringFacts(episodes);
        final lastWatchedSort = watchedIndexes.isEmpty
            ? null
            : _sortOf(episodes[watchedIndexes.last]);
        final status = describeAiring(facts, watchedSort: lastWatchedSort);
        final statusText = status.hint ?? status.badge;

        final pageCount = (episodes.length / widget.pageSize).ceil();
        final page = _page.clamp(0, pageCount - 1);
        final start = page * widget.pageSize;
        final end = (start + widget.pageSize).clamp(0, episodes.length);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '选集',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: colors.onSurface,
                  ),
                ),
                if (statusText != null) ...[
                  const SizedBox(width: 10),
                  Text(
                    statusText,
                    style: TextStyle(
                      fontSize: 13,
                      color: status.badge != null
                          ? colors.primary
                          : colors.onSurfaceVariant,
                    ),
                  ),
                ],
                const Spacer(),
                if (watchedIndexes.isNotEmpty)
                  Text(
                    '已看 ${watchedIndexes.length} / ${episodes.length}',
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                if (pageCount > 1) ...[
                  const SizedBox(width: 12),
                  _PageButton(
                    icon: Icons.chevron_left_rounded,
                    enabled: page > 0,
                    onPressed: () => setState(() => _page = page - 1),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Text(
                      '${start + 1}–$end / ${episodes.length}',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                  _PageButton(
                    icon: Icons.chevron_right_rounded,
                    enabled: page < pageCount - 1,
                    onPressed: () => setState(() => _page = page + 1),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = (constraints.maxWidth / 240).floor().clamp(1, 4);
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    mainAxisExtent: 62,
                  ),
                  itemCount: end - start,
                  itemBuilder: (context, offset) {
                    final index = start + offset;
                    final episode = episodes[index];
                    final sort = _sortOf(episode);
                    final label = sort != null
                        ? formatEpisodeSort(sort).padLeft(2, '0')
                        : '${index + 1}'.padLeft(2, '0');
                    final title =
                        _text(episode['name_cn']) ??
                        _text(episode['name']) ??
                        '第 $label 话';
                    return _EpisodeTile(
                      label: label,
                      title: title,
                      date: _shortDate(episode['airdate']),
                      watched: watchedIndexes.contains(index),
                      onTap: () => widget.onEpisodeTap(index),
                      cardColor: isDark
                          ? Colors.white.withValues(alpha: 0.05)
                          : const Color(0xFFF2F2F7),
                      accent: colors.primary,
                      muted: colors.onSurfaceVariant,
                      textColor: colors.onSurface,
                    );
                  },
                );
              },
            ),
          ],
        );
      },
    );
  }

  static num? _sortOf(Map<String, dynamic> episode) {
    final sort = episode['sort'];
    return sort is num ? sort : null;
  }

  static String? _text(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static String? _shortDate(Object? raw) {
    if (raw is! String) return null;
    final match = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(raw.trim());
    if (match == null) return null;
    return '${match.group(2)!.padLeft(2, '0')}/${match.group(3)!.padLeft(2, '0')}';
  }
}

class _PageButton extends StatelessWidget {
  const _PageButton({
    required this.icon,
    required this.enabled,
    required this.onPressed,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return IconButton(
      icon: Icon(icon, size: 20),
      onPressed: enabled ? onPressed : null,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      visualDensity: VisualDensity.compact,
      color: colors.onSurfaceVariant,
      disabledColor: colors.onSurfaceVariant.withValues(alpha: 0.3),
    );
  }
}

class _EpisodeTile extends StatefulWidget {
  const _EpisodeTile({
    required this.label,
    required this.title,
    required this.date,
    required this.watched,
    required this.onTap,
    required this.cardColor,
    required this.accent,
    required this.muted,
    required this.textColor,
  });

  final String label;
  final String title;
  final String? date;
  final bool watched;
  final VoidCallback onTap;
  final Color cardColor;
  final Color accent;
  final Color muted;
  final Color textColor;

  @override
  State<_EpisodeTile> createState() => _EpisodeTileState();
}

class _EpisodeTileState extends State<_EpisodeTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final muted = widget.watched ? widget.muted : widget.textColor;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _hovered
                ? widget.accent.withValues(alpha: 0.12)
                : widget.cardColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _hovered
                  ? widget.accent.withValues(alpha: 0.55)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 26,
                child: Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: widget.watched ? widget.muted : widget.accent,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.2,
                        color: muted,
                        decoration: widget.watched
                            ? TextDecoration.lineThrough
                            : null,
                        decorationColor: widget.muted,
                      ),
                    ),
                    if (widget.date != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        widget.date!,
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.2,
                          color: widget.muted.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (widget.watched)
                Icon(Icons.done_rounded, size: 16, color: widget.muted),
            ],
          ),
        ),
      ),
    );
  }
}
