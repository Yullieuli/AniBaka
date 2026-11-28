import 'package:baka/api/bgm.dart';
import 'package:baka/core/app_logger.dart';
import 'package:baka/services/playback/airing_status.dart';
import 'package:baka/services/playback/history_repository.dart';
import 'package:flutter/material.dart';

/// 详情页的选集列表：直接读 Bangumi 本篇分集，点哪一集就从哪一集开始匹配源。
///
/// 和播放页里的 [PlayerDetailEpisodes] 不同，这里没有已选中的源，
/// 所以只按 Bangumi 集号排序，点击后交给播放器重新匹配。
class AnimeDetailEpisodes extends StatefulWidget {
  const AnimeDetailEpisodes({
    required this.subjectId,
    required this.onEpisodeTap,
    super.key,
  });

  final int subjectId;

  /// 参数是分集在本篇列表里的下标（0 起算），播放器按它对齐目标集。
  final ValueChanged<int> onEpisodeTap;

  @override
  State<AnimeDetailEpisodes> createState() => _AnimeDetailEpisodesState();
}

class _AnimeDetailEpisodesState extends State<AnimeDetailEpisodes> {
  late Future<List<Map<String, dynamic>>> _episodes = _load();

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
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
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
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: Text('暂无分集信息')),
          );
        }

        final watched = [
          for (var i = 0; i < episodes.length; i++)
            if (HistoryRepository.watchedAt(widget.subjectId, i)) i,
        ].length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '共 ${episodes.length} 集',
                  style: TextStyle(
                    fontSize: 13,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                if (watched > 0)
                  Text(
                    '已看 $watched / ${episodes.length}',
                    style: TextStyle(
                      fontSize: 13,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = (constraints.maxWidth / 260).floor().clamp(1, 4);
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
                  itemCount: episodes.length,
                  itemBuilder: (context, index) {
                    final episode = episodes[index];
                    final sort = episode['sort'];
                    final label = sort is num
                        ? formatEpisodeSort(sort).padLeft(2, '0')
                        : '${index + 1}'.padLeft(2, '0');
                    final title =
                        _text(episode['name_cn']) ??
                        _text(episode['name']) ??
                        '第 $label 话';
                    final date = _shortDate(episode['airdate']);
                    final isWatched = HistoryRepository.watchedAt(
                      widget.subjectId,
                      index,
                    );
                    return _EpisodeTile(
                      label: label,
                      title: title,
                      date: date,
                      watched: isWatched,
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
