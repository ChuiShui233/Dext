import 'dart:async';
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import 'submission_detail_page.dart';
import '../main.dart' show isDesktop;
import '../widgets/top_safe_spacer.dart';
import '../utils/error_formatter.dart';
import '../components/flexible_pagination.dart';
import '../components/skeleton_loading.dart';
import '../widgets/route_transition.dart';

class CustomPagePhysics extends BouncingScrollPhysics {
  const CustomPagePhysics({super.parent});

  @override
  CustomPagePhysics applyTo(ScrollPhysics? ancestor) {
    return CustomPagePhysics(parent: buildParent(ancestor));
  }

  @override
  double get minFlingVelocity => 200.0;

  @override
  double get maxFlingVelocity => 8000.0;

  @override
  Simulation? createBallisticSimulation(
      ScrollMetrics position, double velocity) {
    return super.createBallisticSimulation(position, velocity * 0.8);
  }
}

class HomeHistoryContent extends StatefulWidget {
  final ApiService apiService;
  const HomeHistoryContent({super.key, required this.apiService});

  @override
  State<HomeHistoryContent> createState() => _HomeHistoryContentState();
}

class _HomeHistoryContentState extends State<HomeHistoryContent> with TickerProviderStateMixin {
  final _searchController = TextEditingController();
  late final FSelectController<int> _typeSelectController;

  bool _loading = false;
  int? _selectedType;
  int _page = 1;
  final int _pageSize = 50;
  int _total = 0;
  List<Map<String, dynamic>> _items = [];
  final Map<int, List<Map<String, dynamic>>> _pageCache = {};
  final Map<int, bool> _pageLoading = {};
  Timer? _debounce;
  bool _isProgrammaticPageChange = false; // 防止程序化更新触发回调
  
  FPaginationController _paginationController = FPaginationController(pages: 1);
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _typeSelectController = FSelectController<int>(vsync: this);
    _pageController = PageController(initialPage: _page - 1);
    _loading = true;
    _loadCachedHistory();
    _fetch();
  }

  Future<void> _loadCachedHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _buildCacheKey();
      final cached = prefs.getString(key);
      if (cached != null) {
        final data = json.decode(cached) as Map<String, dynamic>;
        final items = (data['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        final total = (data['total'] as num?)?.toInt() ?? items.length;
        if (!mounted) return;
        _pageCache[_page] = items;
        setState(() {
          _items = items;
          _total = total;
          _loading = false;
        });
        if (!mounted) return;
        _syncPaginationController();
      }
    } catch (_) {
    }
  }

  String _buildCacheKey([int? page]) {
    final q = _searchController.text.trim();
    final type = _selectedType?.toString() ?? 'all';
    final pageNum = page ?? _page;
    return 'history_${q}_${type}_${pageNum}_$_pageSize';
  }

  void _syncPaginationController() {
    final int totalPages = ((_total + _pageSize - 1) ~/ _pageSize).clamp(1, 999999);
    if (_page > totalPages) {
      _page = totalPages;
    }
    if (_paginationController.pages != totalPages) {
      _paginationController.dispose();
      _paginationController = FPaginationController(pages: totalPages);
    }
    _isProgrammaticPageChange = true;
    _paginationController.page = (_page - 1).clamp(0, totalPages - 1);
    _isProgrammaticPageChange = false;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _typeSelectController.dispose();
    _searchController.dispose();
    _paginationController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _fetch({bool resetPage = false}) async {
    if (!mounted) return;
    
    Timer? loadingTimer = Timer(const Duration(milliseconds: 150), () {
      if (mounted && _loading) {
        setState(() => _loading = true);
      }
    });
    
    if (resetPage) {
      _page = 1;
      _pageCache.clear();
      _pageLoading.clear();
      if (mounted) {
        _paginationController.page = 0; // 同步重置分页控制器
      }
    }
    
    await _loadPage(_page, isCurrentPage: true);
    
    loadingTimer.cancel();
  }

  Future<void> _loadPage(int page, {bool isCurrentPage = false}) async {
    if (!mounted) return;
    
    if (_pageLoading[page] == true) return;
    
    _pageLoading[page] = true;
    
    try {
      final resp = await widget.apiService.getSubmissionHistory(
        query: _searchController.text.trim().isEmpty ? null : _searchController.text.trim(),
        type: _selectedType,
        page: page,
        pageSize: _pageSize,
      );
      
      if (!mounted) return;
      final items = (resp['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final total = (resp['total'] as num?)?.toInt() ?? items.length;
      
      _pageCache[page] = items;
      
      try {
        final prefs = await SharedPreferences.getInstance();
        final key = _buildCacheKey(page);
        await prefs.setString(key, json.encode({'items': items, 'total': total}));
      } catch (_) {}
      
      if (isCurrentPage || page == _page) {
        setState(() {
          _items = items;
          _total = total;
          _loading = false;
        });
        _syncPaginationController();
      }
    } catch (e) {
      if (!mounted) return;
      if (isCurrentPage || page == _page) {
        setState(() => _loading = false);
        showFToast(
          context: context,
          alignment: FToastAlignment.bottomRight,
          title: const Text('加载失败'),
          description: Text(ErrorFormatter.format(e)),
          suffixBuilder: (context, entry) => IntrinsicHeight(
            child: FButton(
              style: context.theme.buttonStyles.primary.call,
              onPress: entry.dismiss.call,
              child: const Text('关闭'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        _pageLoading[page] = false;
      }
    }
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _fetch(resetPage: true));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 只在首次构建时从PageStorage读取状态
    if (_items.isEmpty && !_loading) {
      final value = PageStorage.maybeOf(context)?.readState(context) ?? 0;
      _paginationController.page = value;
    }
  }

  void _handlePageChange(int page) {
    // 忽略程序化更新触发的回调
    if (_isProgrammaticPageChange) return;

    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
    
    final newPage = page + 1; // FPagination 是 0-based，但 API 是 1-based
    setState(() {
      _page = newPage;
    });
    
    _loadPage(newPage, isCurrentPage: true);
    
    final totalPages = ((_total + _pageSize - 1) ~/ _pageSize).clamp(1, 999999);
    if (newPage + 1 <= totalPages) {
      _loadPage(newPage + 1);
    }
    if (newPage - 1 >= 1) {
      _loadPage(newPage - 1);
    }
  }

  String _typeText(int t) {
    switch (t) {
      case 0: return '普通问卷';
      case 1: return '限时问卷';
      case 2: return '限次问卷';
      case 3: return '自选风格';
      default: return '未知类型';
    }
  }


  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    
    return Column(
      children: [
        const TopSafeSpacer(desktop: 20, web: 16, mobile: 8),
        _buildHeader(context),
        const SizedBox(height: 12),
        _buildFilters(context),
        Expanded(
          child: _buildTimelineContent(context),
        ),
        _buildPagination(context),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Padding(
      padding: const EdgeInsets.only(
        top: 8,
        left: 8,
        right: 8,
      ),
      child: Row(
        children: [
          Icon(
            FIcons.clock,
            color: theme.colorScheme.primary,
            size: 24,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '提交记录',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '查看所有问卷提交的历史记录和详细信息',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: isDark ? Colors.white70 : Colors.black54,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.filter_list,
                size: 20,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                '筛选条件',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              SizedBox(
                width: isDesktop ? 300 : 250,
                child: FTextFormField(
                  controller: _searchController,
                  label: const Text('搜索问卷'),
                  hint: '输入问卷名称关键字',
                  onChange: _onSearchChanged,
                ),
              ),
              SizedBox(
                width: isDesktop ? 200 : 180,
                child: FSelect<int>(
                  controller: _typeSelectController,
                  label: const Text('问卷类型'),
                  hint: _selectedType == null ? '全部类型' : _typeText(_selectedType!),
                  onChange: (v) {
                    setState(() => _selectedType = v);
                    _fetch(resetPage: true);
                  },
                  items: const {
                    '普通问卷': 0,
                    '限时问卷': 1,
                    '限次问卷': 2,
                    '自选风格': 3,
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FButton(
                      onPress: () => _fetch(resetPage: true),
                      child: const Text('搜索'),
                    ),
                    const SizedBox(width: 12),
                    FButton(
                      style: context.theme.buttonStyles.ghost.call,
                      onPress: () {
                        _searchController.clear();
                        setState(() {
                          _selectedType = null;
                          try { _typeSelectController.value = null; } catch (_) {}
                        });
                        _fetch(resetPage: true);
                      },
                      child: const Text('重置'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineContent(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    if (_loading) {
      return const SkeletonList();
    }
    
    if (_items.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(48),
        decoration: BoxDecoration(
          color: isDark 
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.white.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark 
              ? Colors.white.withValues(alpha: 0.1)
              : Colors.black.withValues(alpha: 0.1),
          ),
        ),
        child: Center(
          child: Column(
            children: [
              Icon(
                FIcons.fileText,
                size: 48,
                color: isDark ? Colors.white30 : Colors.black26,
              ),
              const SizedBox(height: 16),
              Text(
                '暂无提交记录',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '尝试调整筛选条件或创建新的问卷',
                style: TextStyle(
                  color: isDark ? Colors.white.withValues(alpha: 0.5) : Colors.black38,
                ),
              ),
            ],
          ),
        ),
      );
    }
    
    final totalPages = ((_total + _pageSize - 1) ~/ _pageSize).clamp(1, 999999);
    
    return PageView.builder(
      controller: _pageController,
      physics: const CustomPagePhysics(),
      itemCount: totalPages,
        onPageChanged: (index) {
          if (_isProgrammaticPageChange) return;
          HapticFeedback.selectionClick();
          _handlePageChange(index);
        },
        itemBuilder: (context, pageIndex) {
          final pageNumber = pageIndex + 1;
          final items = _pageCache[pageNumber];
          final isLoading = _pageLoading[pageNumber] == true;
          
          if (items != null) {
            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, anim) {
                return SlideTransition(
                  position: Tween(
                    begin: const Offset(0.1, 0),
                    end: Offset.zero,
                  ).animate(anim),
                  child: FadeTransition(opacity: anim, child: child),
                );
              },
              child: ListView.builder(
                key: ValueKey(pageIndex),
                physics: const ClampingScrollPhysics(),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  return _buildTimelineItem(context, items[index], index);
                },
              ),
            );
          } else {
            if (!isLoading) {
              _loadPage(pageNumber);
            }
            return const SkeletonList();
          }
        },
      );
  }

  Future<bool> _showDeleteConfirmationDialog(BuildContext context) async {
    bool animateIn = false;
    bool isClosing = false;
    const animationDuration = Duration(milliseconds: 200);

    return await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            if (!animateIn && !isClosing) {
              Future.microtask(() {
                if (dialogContext.mounted) setState(() => animateIn = true);
              });
            }

            Future<void> close([bool? result]) async {
              if (!dialogContext.mounted) return;
              setState(() {
                animateIn = false;
                isClosing = true;
              });
              await Future.delayed(animationDuration);
              if (dialogContext.mounted) Navigator.of(dialogContext).pop(result);
            }

            return AnimatedOpacity(
              opacity: animateIn ? 1.0 : 0.0,
              duration: animationDuration,
              child: Center(
                child: Material(
                  color: Colors.transparent,
                  child: FDialog(
                    title: const Text('确认删除'),
                    body: const Text('确定要删除该记录吗？删除后记录将进入回收站。'),
                    actions: [
                      FButton(
                        style: context.theme.buttonStyles.ghost.call,
                        onPress: () => close(false),
                        child: const Text('取消'),
                      ),
                      FButton(
                        style: context.theme.buttonStyles.primary.call,
                        onPress: () => close(true),
                        child: const Text('删除'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    ) ?? false;
  }

  Future<bool> _deleteHistoryItem(BuildContext context, int? answerId, int index) async {
    if (answerId == null) {
      showFToast(
        context: context,
        alignment: FToastAlignment.bottomRight,
        title: const Text('无法删除'),
        description: const Text('该记录缺少答案ID，无法执行删除操作。'),
        suffixBuilder: (ctx, entry) => IntrinsicHeight(
          child: FButton(
            style: ctx.theme.buttonStyles.primary.call,
            onPress: entry.dismiss.call,
            child: const Text('关闭'),
          ),
        ),
      );
      return false;
    }

    try {
      await widget.apiService.deleteAnswer(answerId);
    } catch (e) {
      final error = ErrorFormatter.format(e);
      if (!mounted || !context.mounted) return false;
      showFToast(
        context: context,
        alignment: FToastAlignment.bottomRight,
        title: const Text('删除失败'),
        description: Text(error),
        suffixBuilder: (ctx, entry) => IntrinsicHeight(
          child: FButton(
            style: ctx.theme.buttonStyles.primary.call,
            onPress: entry.dismiss.call,
            child: const Text('关闭'),
          ),
        ),
      );
      return false;
    }

    if (!mounted) return false;

    final int newTotal = _total > 0 ? _total - 1 : 0;
    final int totalPages = ((newTotal + _pageSize - 1) ~/ _pageSize).clamp(1, 999999);
    int newPage = _page;
    if (newPage > totalPages) {
      newPage = totalPages;
    }
    if (newPage < 1) {
      newPage = 1;
    }

    setState(() {
      if (index >= 0 && index < _items.length) {
        _items.removeAt(index);
      }
      _total = newTotal;
      _page = newPage;
    });

    _syncPaginationController();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_buildCacheKey());
    } catch (_) {}

    if (!context.mounted) return false;
    showFToast(
      context: context,
      alignment: FToastAlignment.bottomRight,
      title: const Text('删除成功'),
      description: const Text('提交记录已被删除。'),
      suffixBuilder: (ctx, entry) => IntrinsicHeight(
        child: FButton(
          style: ctx.theme.buttonStyles.primary.call,
          onPress: entry.dismiss.call,
          child: const Text('关闭'),
        ),
      ),
    );

    // 刷新当前页数据，确保补齐后续记录
    Future.microtask(() {
      if (!mounted) return;
      if (_total > 0) {
        _fetch();
      }
    });

    return true;
  }
  
  Widget _buildTimelineItem(BuildContext context, Map<String, dynamic> item, int index) {
    final answerId = (item['answerId'] as num?)?.toInt();
    final surveyId = (item['surveyId'] as num?)?.toInt();

    return FPopover(
      popoverAnchor: Alignment.topLeft,
      childAnchor: Alignment.bottomLeft,
      offset: const Offset(10, 0),
      popoverBuilder: (context, _) => Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildPopoverMenuItem(
              icon: FIcons.eye,
              text: '查看详情',
              onTap: () {
                if (answerId != null) {
                  final width = MediaQuery.of(context).size.width;
                  final bool isDesktopLayout = width >= 1025;

                  if (isDesktopLayout) {
                    Navigator.of(context).push(
                      fadePageRoute(
                        SubmissionDetailPage(
                          apiService: widget.apiService,
                          answerId: answerId,
                          surveyId: surveyId,
                        ),
                      ),
                    );
                  } else {
                    Navigator.of(context).push(
                      slideFadePageRoute(SubmissionDetailPage(
                        apiService: widget.apiService,
                        answerId: answerId,
                        surveyId: surveyId,
                      )),
                    );
                  }
                }
              },
            ),
            const SizedBox(height: 4),
            _buildPopoverMenuItem(
              icon: Icons.delete,
              text: '删除',
              onTap: () async {
                if (answerId != null) {
                  final ok = await _showDeleteConfirmationDialog(context);
                  if (ok) {
                    _deleteHistoryItem(context, answerId, index);
                  }
                }
              },
            ),
          ],
        ),
      ),
      builder: (_, controller, child) {
        return GestureDetector(
          onLongPress: answerId == null ? null : () {
            HapticFeedback.mediumImpact();
            controller.toggle();
          },
          onSecondaryTapDown: answerId == null ? null : (_) {
            controller.toggle();
          },
          child: _buildCardContent(context, item, index),
        );
      },
    );
  }

  Widget _buildPopoverMenuItem({
    required IconData icon,
    required String text,
    Color? textColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 12),
            Text(
              text,
              style: TextStyle(
                fontSize: 14,
                color: textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

Widget _buildCardContent(BuildContext context, Map<String, dynamic> item, int index) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final answerId = (item['answerId'] as num?)?.toInt();
    final surveyId = (item['surveyId'] as num?)?.toInt();
    final surveyType = (item['surveyType'] as num?)?.toInt() ?? 0;
    final surveyStatus = (item['surveyStatus'] as num?)?.toInt() ?? 0;

    final String title = (item['surveyName'] ?? '') as String;
    final String description = (item['description'] ?? '') as String;
    final String creator = (item['creator'] ?? '') as String;
    final String submitTime = (item['submitTime'] ?? '') as String;

    final heroTag = 'history_${answerId ?? index}';

    return Hero(
      tag: heroTag,
      child: Material(
        type: MaterialType.transparency,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
            boxShadow: [
              BoxShadow(
                color: isDark ? Colors.black.withValues(alpha: 0.3) : Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            leading: Icon(
              FIcons.fileText,
              color: theme.colorScheme.primary,
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _buildStatusBadge(surveyStatus, isDark),
              ],
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (description.isNotEmpty)
                    Text(
                      description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.3,
                        color: isDark ? Colors.white70 : Colors.black54,
                      ),
                    ),
                  const SizedBox(height: 6),
                  DefaultTextStyle(
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white60 : Colors.black54,
                    ),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(FIcons.tag, size: 12),
                            const SizedBox(width: 4),
                            Text(_typeText(surveyType)),
                          ],
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(FIcons.user, size: 12),
                            const SizedBox(width: 4),
                            Text(creator),
                          ],
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(FIcons.clock, size: 12),
                            const SizedBox(width: 4),
                            Text(submitTime),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            onTap: answerId == null
                ? null
                : () {
                    final width = MediaQuery.of(context).size.width;
                    final bool isDesktopLayout = width >= 1025;

                    if (isDesktopLayout) {
                      Navigator.of(context).push(
                        fadePageRoute(
                          SubmissionDetailPage(
                            apiService: widget.apiService,
                            answerId: answerId,
                            surveyId: surveyId,
                          ),
                        ),
                      );
                    } else {
                      Navigator.of(context).push(
                        slideFadePageRoute(SubmissionDetailPage(
                          apiService: widget.apiService,
                          answerId: answerId,
                          surveyId: surveyId,
                        )),
                      );
                    }
                  },
          ),
        ),
      ),
    );
  }

  Widget _buildPagination(BuildContext context) {
    final totalPages = (_total / _pageSize).ceil();

    return Column(
      children: [
        FlexiblePagination(
          controller: _paginationController,
          currentPage: _page,
          totalPages: totalPages,
          totalItems: _total,
          onPageChange: _handlePageChange,
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        ),
      ],
    );
  }


  Widget _buildStatusBadge(int status, bool isDark) {
    Color color;
    String text;

    switch (status) {
      case 0:
        color = Colors.orange;
        text = '未发布';
        break;
      case 1:
        color = Colors.green;
        text = '发布中';
        break;
      case 2:
        color = Colors.blue;
        text = '已完结';
        break;
      default:
        color = Colors.grey;
        text = '未知';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: color.withValues(alpha: 0.3),
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

}
