import 'dart:math' as math;

import 'package:baka/api/anibaka_api.dart';
import 'package:baka/services/playback/history_repository.dart';
import 'package:baka/services/playback/playback_content.dart';
import 'package:baka/utils/json_values.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 播放页里打开的番剧详情：完整的详情页放在底部面板里，
/// 出场方式和选集弹窗一致，点暗处、Esc、右上角都能收起。
/// [page] 拿到关闭面板的方法，选集、换源前先关面板。
///
/// 宽屏（≥900）纯淡入，窄屏从底部滑入并淡入——宽屏整块位移会晃眼。
Future<void> showAnimeDetailSheet(
  BuildContext context, {
  required Widget Function(BuildContext context, VoidCallback close) page,
}) async {
  final size = MediaQuery.sizeOf(context);
  final wide = size.width >= 900;
  final reduceMotion = MediaQuery.disableAnimationsOf(context);
  final duration = reduceMotion
      ? Duration.zero
      : Duration(milliseconds: wide ? 200 : 280);

  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭番剧详情',
    barrierColor: Colors.black54,
    transitionDuration: duration,
    pageBuilder: (dialogContext, _, _) {
      void close() => Navigator.of(dialogContext).pop();
      return Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(
          width: size.width * 0.8,
          height: size.height * 0.8,
          child: Material(
            key: const ValueKey('animeDetailSheet'),
            color: Theme.of(dialogContext).scaffoldBackgroundColor,
            clipBehavior: Clip.antiAlias,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: _DetailSheetSurface(
              onClose: close,
              page: page(dialogContext, close),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (dialogContext, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      final faded = FadeTransition(opacity: curved, child: child);
      if (wide) return faded;
      return SlideTransition(
        // 只抬 6%，配合淡入，避免整块面板大幅位移。
        position: Tween<Offset>(
          begin: const Offset(0, 0.06),
          end: Offset.zero,
        ).animate(curved),
        child: faded,
      );
    },
  );
}

class _DetailSheetSurface extends StatelessWidget {
  const _DetailSheetSurface({required this.onClose, required this.page});

  final VoidCallback onClose;
  final Widget page;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): onClose},
      child: Focus(
        autofocus: true,
        child: Material(
          color: theme.scaffoldBackgroundColor,
          child: Column(
            children: [
              // 只留拖拽手柄，不放关闭按钮：拖拽、点暗处、Esc 都能收起。
              SizedBox(
                height: 30,
                child: Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.35,
                      ),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
              Expanded(child: page),
            ],
          ),
        ),
      ),
    );
  }
}

/// 详情面板里的选集区：默认只列当前集所在的 10 集，可以展开全部。
/// 点一集就交给当前播放器切，不另开播放页。
class PlayerDetailEpisodes extends StatefulWidget {
  const PlayerDetailEpisodes({
    required this.content,
    required this.onSelected,
    super.key,
  });

  final PlaybackContent content;
  final ValueChanged<int> onSelected;

  @override
  State<PlayerDetailEpisodes> createState() => _PlayerDetailEpisodesState();
}

class _PlayerDetailEpisodesState extends State<PlayerDetailEpisodes> {
  static const _pageSize = 10;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final content = widget.content;
    final total = content.videoList.length;
    if (total == 0) return const SliverToBoxAdapter(child: SizedBox.shrink());
    final current = content.currPlayIndex;
    final start = _expanded ? 0 : (current ~/ _pageSize) * _pageSize;
    final count = _expanded ? total : math.min(_pageSize, total - start);
    final theme = Theme.of(context);
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(
              children: [
                const Text(
                  '选集',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 10),
                Text(
                  _expanded
                      ? '共 $total 集'
                      : '第 ${start + 1}–${start + count} 集 · 共 $total 集',
                  style: TextStyle(
                    fontSize: 13,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                if (total > _pageSize)
                  TextButton(
                    onPressed: () => setState(() => _expanded = !_expanded),
                    child: Text(_expanded ? '只看当前集附近' : '显示全部'),
                  ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          sliver: SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 200,
              mainAxisExtent: 140,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: count,
            itemBuilder: (context, offset) {
              final index = start + offset;
              return _EpisodeCard(
                key: ValueKey(index),
                content: content,
                index: index,
                isPlaying: index == current,
                onTap: () => widget.onSelected(index),
              );
            },
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 8)),
      ],
    );
  }
}

class _EpisodeCard extends StatefulWidget {
  const _EpisodeCard({
    required this.content,
    required this.index,
    required this.isPlaying,
    required this.onTap,
    super.key,
  });

  final PlaybackContent content;
  final int index;
  final bool isPlaying;
  final VoidCallback onTap;

  @override
  State<_EpisodeCard> createState() => _EpisodeCardState();
}

class _EpisodeCardState extends State<_EpisodeCard> {
  Map<String, dynamic>? _still;
  int _stillToken = 0;

  @override
  void initState() {
    super.initState();
    _loadStill();
  }

  @override
  void didUpdateWidget(_EpisodeCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index ||
        oldWidget.content != widget.content) {
      _loadStill();
    }
  }

  Future<Map<String, dynamic>?>? _stillFuture() {
    final bgmId = widget.content.bgmInfo.subjectId;
    if (bgmId == null || bgmId <= 0) return null;
    return AniBakaApi.getEpisodeStills(
      bgmId: bgmId,
      season: 1,
      episode: widget.index + 1,
    );
  }

  /// 只接受最后一次请求的结果；缓存过期或换集都不会写回旧图。
  void _loadStill() {
    final token = ++_stillToken;
    _still = null;
    final future = _stillFuture();
    if (future == null) return;
    future.then(
      (data) {
        if (!mounted || token != _stillToken) return;
        setState(() => _still = data);
      },
      onError: (Object _) {},
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = widget.content;
    final index = widget.index;
    final theme = Theme.of(context);
    final isPlaying = widget.isPlaying;
    final bgmEpisodes = content.bgmEpisodes;
    final episode = index < bgmEpisodes.length ? bgmEpisodes[index] : null;
    final rawTitle = content.videoList[index].title;
    final name =
        trimmed(episode?['name_cn']) ??
        trimmed(episode?['name']) ??
        trimmed(_still?['name']) ??
        rawTitle.trim();
    final number = content.episodeNumbering.numberAt(index) ?? index + 1;
    final title = name.isEmpty || name == '$number' ? '第 $number 集' : name;
    final stillUrl =
        trimmed(_still?['still_thumb']) ??
        trimmed(_still?['still_url']) ??
        content.coverImageUrl ??
        '';
    final watched = HistoryRepository.isEpisodeWatched(
      content.watchedVideoId,
      index,
      legacyVideoId: '${content.data['id']}',
      bgmId: content.bgmInfo.subjectId,
    );
    // 进度条只按当前源的播放入口统计；换源后靠已看标记兜底。
    final playProgress = HistoryRepository.episodePlayProgress(
      '${content.data['id']}',
      index,
    );
    final borderColor = isPlaying
        ? theme.colorScheme.primary
        : theme.colorScheme.outlineVariant.withValues(alpha: 0.6);

    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: borderColor, width: isPlaying ? 2 : 1),
          ),
          padding: const EdgeInsets.all(6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: stillUrl.isNotEmpty
                            ? CachedNetworkImage(
                                memCacheWidth: 320,
                                imageUrl: stillUrl,
                                fit: BoxFit.cover,
                                errorWidget: (_, _, _) => const SizedBox.expand(),
                              )
                            : null,
                      ),
                      Positioned(
                        left: 6,
                        bottom: 6,
                        child: _EpisodeBadge(text: number.toString()),
                      ),
                      if (watched && !isPlaying)
                        const Positioned(
                          top: 6,
                          right: 6,
                          child: _EpisodeBadge(icon: Icons.check_rounded),
                        ),
                      if (isPlaying)
                        const Positioned(
                          top: 6,
                          right: 6,
                          child: _EpisodeBadge(
                            icon: Icons.play_arrow_rounded,
                            accent: true,
                          ),
                        ),
                      // 看了一半的集在封面底边留一条进度，已经看完的不再画。
                      if (!watched && playProgress != null && playProgress > 0.01)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: playProgress.clamp(0.0, 1.0),
                            child: Container(
                              height: 3,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isPlaying ? FontWeight.w700 : FontWeight.w500,
                  color: isPlaying
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EpisodeBadge extends StatelessWidget {
  const _EpisodeBadge({this.text, this.icon, this.accent = false});

  final String? text;
  final IconData? icon;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final accent = this.accent;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: icon == null ? 6 : 3,
        vertical: icon == null ? 2 : 1,
      ),
      decoration: BoxDecoration(
        color: accent
            ? Theme.of(context).colorScheme.primary
            : Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(5),
      ),
      child: icon == null
          ? Text(
              text!,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: accent
                    ? Theme.of(context).colorScheme.onPrimary
                    : Colors.white,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            )
          : Icon(
              icon,
              size: 14,
              color: accent
                  ? Theme.of(context).colorScheme.onPrimary
                  : Colors.white,
            ),
    );
  }
}
