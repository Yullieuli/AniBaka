import 'package:baka/core/app_logger.dart';
import 'package:baka/core/content_filter.dart';
import 'package:baka/source/models/source_search_result.dart';
import 'package:baka/services/source/source_repository.dart';
import 'dart:async';

import 'package:baka/instance.dart';
import 'package:baka/pages/source/source_management_page.dart';
import 'package:baka/pages/search/search_controller.dart';
import 'package:baka/app/navigation.dart';
import 'package:baka/widgets/anime/post_card.dart';
import 'package:baka/widgets/anime_detail/anime_detail_placeholder.dart';
import 'package:flutter/material.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key, this.k, this.initialSource});

  final String? k;
  final int? initialSource;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  static const _debounceDuration = Duration(milliseconds: 300);
  final _searchController = TextEditingController();
  late final AnimeSearchController _searchService;
  Timer? _debounce;
  late final _sourceChanges = Listenable.merge([
    _searchService.sourceLabelsNotifier,
    _searchService.selectedSourceIndexNotifier,
  ]);
  late final _resultChanges = Listenable.merge([
    _searchService.isLoadingNotifier,
    _searchService.resultsNotifier,
    contentFilter,
  ]);

  bool get _isWindows => Instances.isDesktopPlatform;

  /// 桌面端右侧展开的详情；null 表示还在看结果网格。
  Map<String, dynamic>? _selected;

  /// 左侧结果列占的宽度比例，可拖动分隔条调整。
  double _splitFraction = 0.42;

  @override
  void initState() {
    super.initState();
    _searchService = AnimeSearchController();
    _init();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _searchService.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    await _searchService.init(
      initialSource: widget.initialSource,
      initialKeyword: widget.k,
    );
    if (!mounted || widget.k == null) return;

    _searchController.text = _searchService.keywordNotifier.value;
    await _search(_searchService.keywordNotifier.value);
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    // A response for the previous text must not replace the current query.
    _searchService.invalidateSearch();
    _searchService.keywordNotifier.value = value;

    if (value.trim().isEmpty) {
      _searchService.resetSearch();
      if (_selected != null) setState(() => _selected = null);
      return;
    }

    _debounce = Timer(_debounceDuration, () => _search(value));
  }

  Future<void> _search(String value) async {
    _debounce?.cancel();
    if (_selected != null) setState(() => _selected = null);
    await _searchService.search(value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ValueListenableBuilder<bool>(
          valueListenable: _searchService.isVerticalLayoutNotifier,
          builder: (context, isVertical, _) {
            if (isVertical) {
              return Column(
                children: [
                  _buildHeaderBar(),
                  Expanded(
                    child: Row(
                      children: [
                        _buildVerticalSourceSidebar(),
                        Expanded(
                          child: ValueListenableBuilder<bool>(
                            valueListenable: _searchService.showResultsNotifier,
                            builder: (context, showResults, _) {
                              if (showResults) {
                                if (_isWindows && _selected != null) {
                                  return _buildSplitArea();
                                }
                                return _buildResultsArea(isVertical: true);
                              }
                              return ValueListenableBuilder<List<String>>(
                                valueListenable:
                                    _searchService.searchHistoryNotifier,
                                builder: (context, history, _) =>
                                    CustomScrollView(
                                      physics: const BouncingScrollPhysics(),
                                      slivers: [
                                        _buildHistory(
                                          history,
                                          isVertical: true,
                                        ),
                                      ],
                                    ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }

            return CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                _buildSearchBar(),
                ValueListenableBuilder<bool>(
                  valueListenable: _searchService.showResultsNotifier,
                  builder: (context, showResults, _) {
                    if (!showResults) {
                      return ValueListenableBuilder<List<String>>(
                        valueListenable: _searchService.searchHistoryNotifier,
                        builder: (context, history, _) =>
                            _buildHistory(history),
                      );
                    }
                    return SliverMainAxisGroup(
                      slivers: [_buildSourceSelector(), _buildResultsArea()],
                    );
                  },
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 40)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildResultsArea({bool isVertical = false}) {
    return ListenableBuilder(
      listenable: _resultChanges,
      builder: (context, _) {
        final isLoading = _searchService.isLoadingNotifier.value;
        final items = contentFilter.visibleItems(
          _searchService.resultsNotifier.value,
        );
        if (isLoading && items.isEmpty) {
          if (isVertical) {
            return const Center(child: CircularProgressIndicator());
          }
          return const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final results = SliverMainAxisGroup(
          slivers: [
            if (isLoading)
              const SliverToBoxAdapter(child: LinearProgressIndicator()),
            _buildResults(items, isVertical: isVertical),
          ],
        );
        return isVertical
            ? CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  results,
                  const SliverToBoxAdapter(child: SizedBox(height: 40)),
                ],
              )
            : results;
      },
    );
  }

  /// 桌面端的分屏：结果收成一列放左边，点中的条目详情放右边。
  /// 分隔条可以拖动，比例记在 [_splitFraction]。
  Widget _buildSplitArea() {
    final selected = _selected;
    if (selected == null) return _buildResultsArea(isVertical: true);
    return LayoutBuilder(
      builder: (context, constraints) {
        final total = constraints.maxWidth;
        final left = (total * _splitFraction).clamp(300.0, 620.0).toDouble();
        return Row(
          children: [
            SizedBox(width: left, child: _buildCompactResults()),
            _SplitHandle(
              onDrag: (dx) {
                if (total <= 0) return;
                setState(() {
                  _splitFraction = ((_splitFraction * total + dx) / total)
                      .clamp(0.25, 0.65)
                      .toDouble();
                });
              },
            ),
            Expanded(
              child: ClipRect(
                child: MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    size: Size(
                      (total - left - _SplitHandle.width)
                          .clamp(240.0, double.infinity)
                          .toDouble(),
                      constraints.maxHeight,
                    ),
                  ),
                  child: AnimeDetailPlaceholder(
                    key: ValueKey(
                      'search_detail_${selected['bgmId'] ?? selected['title']}',
                    ),
                    data: selected,
                    onClose: () => setState(() => _selected = null),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCompactResults() {
    return ListenableBuilder(
      listenable: _resultChanges,
      builder: (context, _) {
        final loading = _searchService.isLoadingNotifier.value;
        final items = contentFilter.visibleItems(
          _searchService.resultsNotifier.value,
        );
        if (loading && items.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        if (items.isEmpty) {
          return const Center(child: Text('没有找到结果'));
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(10, 8, 6, 24),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final data = items[index];
            return _SearchResultRow(
              data: data,
              selected: _isSelected(data),
              onTap: () => _selectResult(data),
            );
          },
        );
      },
    );
  }

  bool _isSelected(Map<String, dynamic> data) {
    final selected = _selected;
    if (selected == null) return false;
    final a = selected['bgmId'];
    final b = data['bgmId'];
    if (a != null && b != null) return a.toString() == b.toString();
    return selected['title'] == data['title'];
  }

  /// 点搜索结果：Bangumi 条目在右侧展开详情，其他源仍然直接开播。
  void _selectResult(Map<String, dynamic> data) {
    final source = data['source']?.toString();
    if (source == 'bgm') {
      setState(() {
        _selected = {
          'title': data['title'],
          if (data['bgmId'] != null) 'bgmId': data['bgmId'],
          if (data['bgmImageUrl'] != null) 'bgmImageUrl': data['bgmImageUrl'],
          if (data['score'] != null) 'score': data['score'],
        };
      });
      return;
    }
    if (source != null && source.isNotEmpty) {
      _openSeries(data);
    }
  }

  Widget _buildSearchBarContent() {
    final theme = Theme.of(context);

    return Center(
      child: Container(
        constraints: BoxConstraints(
          maxWidth: _isWindows ? 600 : double.infinity,
        ),
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: theme.dividerColor.withValues(alpha: 0.1)),
        ),
        child: Row(
          children: [
            Icon(Icons.search, color: theme.hintColor, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  hintText: '搜索...',
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
                textInputAction: TextInputAction.search,
                onChanged: _onSearchChanged,
                onSubmitted: _search,
              ),
            ),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _searchController,
              builder: (context, value, _) {
                if (value.text.isEmpty) return const SizedBox.shrink();
                return IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () {
                    _searchController.clear();
                    _debounce?.cancel();
                    _searchService.resetSearch();
                  },
                );
              },
            ),
            const SizedBox(width: 4),
            ValueListenableBuilder<bool>(
              valueListenable: _searchService.isVerticalLayoutNotifier,
              builder: (context, isVertical, _) {
                return IconButton(
                  tooltip: isVertical ? '切换为横向源列表' : '切换为竖向源列表',
                  icon: Icon(
                    isVertical
                        ? Icons.view_day_outlined
                        : Icons.view_sidebar_outlined,
                    size: 20,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  color: isVertical
                      ? theme.colorScheme.primary
                      : theme.hintColor,
                  onPressed: () {
                    _searchService.isVerticalLayout = !isVertical;
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderBar() {
    final theme = Theme.of(context);
    final height = _isWindows ? 80.0 : 70.0;

    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: theme.scaffoldBackgroundColor,
      child: Row(
        children: [
          if (_isWindows)
            IconButton(
              icon: const Icon(Icons.arrow_back),
              color: theme.colorScheme.primary,
              onPressed: () => Navigator.of(context).pop(),
            ),
          Expanded(child: _buildSearchBarContent()),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    final theme = Theme.of(context);

    return SliverAppBar(
      floating: true,
      pinned: true,
      automaticallyImplyLeading: false,
      toolbarHeight: _isWindows ? 80 : 70,
      leading: _isWindows
          ? IconButton(
              icon: const Icon(Icons.arrow_back),
              color: theme.colorScheme.primary,
              onPressed: () => Navigator.of(context).pop(),
            )
          : null,
      title: _buildSearchBarContent(),
    );
  }

  Future<void> _openSourceManagement() async {
    _debounce?.cancel();
    _searchService.invalidateSearch();
    await NavigationService.push<void>(context, const SourceManagementPage());
    if (!mounted) return;

    await _searchService.reloadCustomSources();
    if (!mounted) return;
    final query = _searchService.keywordNotifier.value.trim();
    if (query.isNotEmpty) await _search(query);
  }

  Widget _buildVerticalSourceSidebar() {
    final theme = Theme.of(context);
    final sidebarWidth = _isWindows ? 120.0 : 96.0;

    return ListenableBuilder(
      listenable: _sourceChanges,
      builder: (context, _) {
        final sources = _searchService.sourceLabelsNotifier.value;
        final selectedSource = _searchService.selectedSourceIndexNotifier.value;
        return Container(
          width: sidebarWidth,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow.withValues(alpha: 0.4),
            border: Border(
              right: BorderSide(
                color: theme.dividerColor.withValues(alpha: 0.08),
              ),
            ),
          ),
          child: ListView.builder(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            itemCount: sources.length,
            itemBuilder: (context, index) {
              final isSelected = selectedSource == index;
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () {
                    if (_searchService.selectedSourceIndexNotifier.value ==
                        index) {
                      return;
                    }
                    _searchService.selectedSourceIndexNotifier.value = index;
                    if (_searchService.keywordNotifier.value
                        .trim()
                        .isNotEmpty) {
                      _search(_searchService.keywordNotifier.value);
                    }
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? theme.colorScheme.primaryContainer.withValues(
                              alpha: 0.65,
                            )
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected
                            ? theme.colorScheme.primary.withValues(alpha: 0.35)
                            : Colors.transparent,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: 3,
                          height: isSelected ? 14 : 0,
                          margin: EdgeInsets.only(right: isSelected ? 5 : 0),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            borderRadius: BorderRadius.circular(1.5),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            sources[index],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                              color: isSelected
                                  ? theme.colorScheme.primary
                                  : theme.textTheme.bodyMedium?.color,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildSourceSelector() {
    return SliverPersistentHeader(
      pinned: true,
      delegate: _PinnedHeaderDelegate(
        height: 56,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        child: ListenableBuilder(
          listenable: _sourceChanges,
          builder: (context, _) {
            final sources = _searchService.sourceLabelsNotifier.value;
            final selectedSource =
                _searchService.selectedSourceIndexNotifier.value;
            return ListView.builder(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.symmetric(horizontal: _isWindows ? 24 : 16),
              itemCount: sources.length + 2,
              itemBuilder: (context, index) {
                if (index < sources.length) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(sources[index]),
                        selected: selectedSource == index,
                        showCheckmark: false,
                        onSelected: (selected) {
                          if (!selected) return;
                          _searchService.selectedSourceIndexNotifier.value =
                              index;
                          if (_searchService.keywordNotifier.value
                              .trim()
                              .isNotEmpty) {
                            _search(_searchService.keywordNotifier.value);
                          }
                        },
                      ),
                    ),
                  );
                }
                if (index == sources.length) {
                  return IconButton(
                    tooltip: '管理搜索源',
                    icon: const Icon(Icons.settings_outlined, size: 19),
                    onPressed: _openSourceManagement,
                  );
                }
                return IconButton(
                  tooltip: '切换为竖向源列表',
                  icon: const Icon(Icons.view_sidebar_outlined, size: 19),
                  onPressed: () => _searchService.isVerticalLayout = true,
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildHistory(List<String> history, {bool isVertical = false}) {
    if (history.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    final theme = Theme.of(context);
    final horizontalPadding = isVertical
        ? (_isWindows ? 20.0 : 12.0)
        : (_isWindows ? 32.0 : 24.0);

    return SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          horizontalPadding,
          _isWindows ? 16 : 8,
          horizontalPadding,
          0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '最近搜索',
                  style: TextStyle(
                    fontSize: _isWindows ? 18 : 16,
                    fontWeight: FontWeight.bold,
                    color: theme.textTheme.titleLarge?.color,
                  ),
                ),
                TextButton(
                  onPressed: _searchService.clearSearchHistory,
                  child: Text(
                    '清除',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              ],
            ),
            Wrap(
              spacing: _isWindows ? 10 : 8,
              runSpacing: _isWindows ? 10 : 8,
              children: [
                for (final item in history)
                  InputChip(
                    label: Text(item),
                    onPressed: () {
                      _searchController.text = item;
                      _search(item);
                    },
                    onDeleted: () => _searchService.removeSearchHistory(item),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResults(
    List<Map<String, dynamic>> results, {
    bool isVertical = false,
  }) {
    if (results.isEmpty) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Text('未找到结果', style: TextStyle(color: Colors.grey)),
        ),
      );
    }

    final isTablet = MediaQuery.sizeOf(context).shortestSide >= 600;
    final wideLayout = _isWindows || isTablet;

    final double maxExtent;
    final double childAspectRatio;
    final EdgeInsets padding;
    final double crossSpacing;
    final double mainSpacing;

    if (isVertical) {
      padding = EdgeInsets.symmetric(
        horizontal: wideLayout ? 16 : 8,
        vertical: 12,
      );
      maxExtent = _isWindows ? 220 : (isTablet ? 180 : 140);
      childAspectRatio = _isWindows ? 0.68 : (isTablet ? 0.65 : 0.62);
      crossSpacing = isTablet ? 12 : 8;
      mainSpacing = isTablet ? 16 : 10;
    } else {
      padding = EdgeInsets.symmetric(
        horizontal: wideLayout ? 24 : 16,
        vertical: 16,
      );
      maxExtent = _isWindows ? 280 : (isTablet ? 250 : 220);
      childAspectRatio = _isWindows ? 0.65 : 0.58;
      crossSpacing = isTablet ? 20 : 16;
      mainSpacing = isTablet ? 28 : 24;
    }

    return SliverPadding(
      padding: padding,
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: maxExtent,
          childAspectRatio: childAspectRatio,
          crossAxisSpacing: crossSpacing,
          mainAxisSpacing: mainSpacing,
        ),
        delegate: SliverChildBuilderDelegate((context, index) {
          final data = results[index];
          final source = data['source']?.toString();
          VoidCallback? onTap;

          if (source == 'bgm') {
            onTap = () {
              // 桌面竖向布局用右侧分屏，不再整页跳转。
              if (_isWindows && _searchService.isVerticalLayoutNotifier.value) {
                _selectResult(data);
                return;
              }
              NavigationService.toDetail(context, {
                'title': data['title'],
                'bgmId': data['bgmId'],
                if (data['bgmImageUrl'] != null)
                  'bgmImageUrl': data['bgmImageUrl'],
                if (data['score'] != null) 'score': data['score'],
              }, heroTag: coverHeroTag(data));
            };
          } else if (source != null && source.isNotEmpty) {
            onTap = () => _openSeries(data);
          }

          return PostCard(data, onTap: onTap);
        }, childCount: results.length),
      ),
    );
  }

  Future<void> _openSeries(Map<String, dynamic> item) async {
    final source =
        item['sourceDisplayName']?.toString() ??
        item['source']?.toString() ??
        '';

    try {
      final playerData = await sourceRepository.buildPlaybackRequest(
        SourceSearchResult.fromLegacy(item),
      );
      if (!mounted) return;
      if (playerData != null) {
        NavigationService.toPlayback(context, playerData, autoMatch: false);
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('未找到剧集数据: $source'),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (error) {
      Log.w('Search', 'Error opening $source: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('打开失败: $source'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }
}

class _SearchResultRow extends StatefulWidget {
  const _SearchResultRow({
    required this.data,
    required this.selected,
    required this.onTap,
  });

  final Map<String, dynamic> data;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_SearchResultRow> createState() => _SearchResultRowState();
}

class _SearchResultRowState extends State<_SearchResultRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final data = widget.data;
    final score = data['score'];
    final scoreText = score is num && score > 0
        ? score.toStringAsFixed(1)
        : null;
    final subtitle = [
      if ((data['subtitle']?.toString().trim() ?? '').isNotEmpty)
        data['subtitle'],
      if ((data['info']?.toString().trim() ?? '').isNotEmpty) data['info'],
      if ((data['sourceDisplayName']?.toString().trim() ?? '').isNotEmpty)
        data['sourceDisplayName'],
    ].join(' · ');

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: widget.selected
                ? colors.primary.withValues(alpha: 0.12)
                : _hovered
                ? colors.onSurface.withValues(alpha: 0.05)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: widget.selected
                  ? colors.primary.withValues(alpha: 0.45)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 54,
                  height: 78,
                  child: buildCachedImage(data, 54, 78),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data['title']?.toString() ?? '未知标题',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                        color: widget.selected
                            ? colors.primary
                            : colors.onSurface,
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.35,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (scoreText != null) ...[
                const SizedBox(width: 6),
                Text(
                  scoreText,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: colors.primary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 分屏之间的拖动条。
class _SplitHandle extends StatelessWidget {
  const _SplitHandle({required this.onDrag});

  static const double width = 7;

  final ValueChanged<double> onDrag;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).dividerColor.withValues(alpha: 0.35);
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (details) => onDrag(details.delta.dx),
        child: SizedBox(
          width: width,
          child: Center(child: Container(width: 1, color: color)),
        ),
      ),
    );
  }
}

class _PinnedHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _PinnedHeaderDelegate({
    required this.child,
    required this.height,
    required this.backgroundColor,
  });

  final Widget child;
  final double height;
  final Color backgroundColor;

  @override
  double get maxExtent => height;

  @override
  double get minExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return ColoredBox(
      color: backgroundColor,
      child: SizedBox(
        height: height,
        child: Center(child: child),
      ),
    );
  }

  @override
  bool shouldRebuild(_PinnedHeaderDelegate oldDelegate) {
    return oldDelegate.child != child ||
        oldDelegate.height != height ||
        oldDelegate.backgroundColor != backgroundColor;
  }
}
