import 'dart:async';
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import 'submission_detail_page.dart';
import '../main.dart' show isDesktop;
import '../widgets/top_safe_spacer.dart';
import '../utils/error_formatter.dart';
import '../components/loading_indicator.dart';
import '../components/flexible_pagination.dart';

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
  final int _pageSize = 10;
  int _total = 0;
  List<Map<String, dynamic>> _items = [];
  Timer? _debounce;
  
  FPaginationController _paginationController = FPaginationController(pages: 1);

  @override
  void initState() {
    super.initState();
    _typeSelectController = FSelectController<int>(vsync: this);
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
        setState(() {
          _items = items;
          _total = total;
          _loading = false;
        });
        if (!mounted) return;
        
        final totalPages = (_total / _pageSize).ceil().clamp(1, 999999);
        // 只在页数变化时才重新创建控制器
        if (_paginationController.pages != totalPages) {
          _paginationController.dispose();
          _paginationController = FPaginationController(pages: totalPages);
        }
        _paginationController.page = (_page - 1).clamp(0, totalPages - 1);
      }
    } catch (_) {
    }
  }

  String _buildCacheKey() {
    final q = _searchController.text.trim();
    final type = _selectedType?.toString() ?? 'all';
    return 'history_${q}_${type}_${_page}_$_pageSize';
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _typeSelectController.dispose();
    _searchController.dispose();
    _paginationController.dispose();
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
      if (mounted) {
        _paginationController.page = 0; // 同步重置分页控制器
      }
    }
    try {
      final resp = await widget.apiService.getSubmissionHistory(
        query: _searchController.text.trim().isEmpty ? null : _searchController.text.trim(),
        type: _selectedType,
        page: _page,
        pageSize: _pageSize,
      );
      loadingTimer.cancel();
      if (!mounted) return;
      final items = (resp['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      setState(() {
        _items = items;
        _total = (resp['total'] as num?)?.toInt() ?? items.length;
        _loading = false;
      });
      try {
        final prefs = await SharedPreferences.getInstance();
        final key = _buildCacheKey();
        await prefs.setString(key, json.encode({'items': items, 'total': _total}));
      } catch (_) {}
      
      if (!mounted) return;
      
      final totalPages = (_total / _pageSize).ceil().clamp(1, 999999);
      // 只在页数变化时才重新创建控制器
      if (_paginationController.pages != totalPages) {
        _paginationController.dispose();
        _paginationController = FPaginationController(pages: totalPages);
      }
      // 同步当前页码到分页控制器（转换为0-based）
      _paginationController.page = (_page - 1).clamp(0, totalPages - 1);
    } catch (e) {
      loadingTimer.cancel();
      if (!mounted) return;
      setState(() => _loading = false);
      showFToast(
        context: context,
        alignment: FToastAlignment.bottomRight,
        title: const Text('加载失败'),
        description: Text(ErrorFormatter.format(e)),
        suffixBuilder: (context, entry, _) => IntrinsicHeight(
          child: FButton(
            style: context.theme.buttonStyles.primary.copyWith(
              contentStyle: context.theme.buttonStyles.primary.contentStyle.copyWith(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7.5),
                textStyle: FWidgetStateMap.all(
                  context.theme.typography.xs.copyWith(color: context.theme.colors.primaryForeground),
                ),
              ),
            ),
            onPress: entry.dismiss,
            child: const Text('关闭'),
          ),
        ),
      );
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
    setState(() {
      _page = page + 1; // FPagination 是 0-based，但 API 是 1-based
    });
    _fetch(); // _fetch() 会在加载完成后自动同步 controller.page
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
        Expanded(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(context),
                  const SizedBox(height: 24),
                  _buildFilters(context),
                  const SizedBox(height: 32),
                  _buildTimelineContent(context),
                ],
              ),
            ),
          ),
        ),
        _buildPagination(context),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark 
          ? Colors.white.withValues(alpha: 0.05)
          : Colors.white.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark 
            ? Colors.white.withValues(alpha: 0.1)
            : Colors.black.withValues(alpha: 0.1),
        ),
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
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark 
          ? Colors.white.withValues(alpha: 0.05)
          : Colors.white.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark 
            ? Colors.white.withValues(alpha: 0.1)
            : Colors.black.withValues(alpha: 0.1),
        ),
      ),
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
                  format: (v) => _typeText(v),
                  onChange: (v) {
                    setState(() => _selectedType = v);
                    _fetch(resetPage: true);
                  },
                  children: [
                    FSelectItem('普通问卷', 0),
                    FSelectItem('限时问卷', 1),
                    FSelectItem('限次问卷', 2),
                    FSelectItem('自选风格', 3),
                  ],
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
                      style: FButtonStyle.ghost,
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
      return Container(
        padding: const EdgeInsets.all(48),
        decoration: BoxDecoration(
          color: isDark 
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.white.withValues(alpha: 0.5),
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
              LoadingIndicator(
                size: LoadingSize.medium,
              ),
              const SizedBox(height: 16),
              Text(
                '加载中...',
                style: TextStyle(
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
            ],
          ),
        ),
      );
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
    
    return Column(
      children: _items.asMap().entries.map((entry) {
        final index = entry.key;
        final item = entry.value;
        return _buildTimelineItem(context, item, index);
      }).toList(),
    );
  }
  
  Widget _buildTimelineItem(BuildContext context, Map<String, dynamic> item, int index) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final answerId = (item['answerId'] as num?)?.toInt();
    final surveyId = (item['surveyId'] as num?)?.toInt();
    final surveyType = (item['surveyType'] as num?)?.toInt() ?? 0;
    final surveyStatus = (item['surveyStatus'] as num?)?.toInt() ?? 0;
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark 
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.white.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark 
              ? Colors.white.withValues(alpha: 0.1)
              : Colors.black.withValues(alpha: 0.1),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    (item['surveyName'] ?? '') as String,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
                _buildStatusBadge(surveyStatus, isDark),
              ],
            ),
            const SizedBox(height: 8),
            if ((item['description'] ?? '').toString().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  (item['description'] ?? '') as String,
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.white.withValues(alpha: 0.7) : Colors.black54,
                    height: 1.4,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _buildInfoChip(
                  FIcons.tag,
                  '类型',
                  _typeText(surveyType),
                  isDark,
                ),
                _buildInfoChip(
                  FIcons.user,
                  '创建人',
                  (item['creator'] ?? '') as String,
                  isDark,
                ),
                _buildInfoChip(
                  FIcons.clock,
                  '提交时间',
                  (item['submitTime'] ?? '') as String,
                  isDark,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                SizedBox(
                  child: FButton(
                    onPress: answerId == null ? null : () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => SubmissionDetailPage(
                            apiService: widget.apiService,
                            answerId: answerId,
                            surveyId: surveyId,
                          ),
                        ),
                      );
                    },
                    child: const Text('查看详细'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPagination(BuildContext context) {
    final totalPages = (_total / _pageSize).ceil();
    final bool isCompactWidth = MediaQuery.of(context).size.width < 1025;
    // 同步 controller 的页码（0-based）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_paginationController.page != _page - 1) {
        _paginationController.page = (_page - 1).clamp(0, (totalPages - 1).clamp(0, double.infinity).toInt());
      }
    });

    return Column(
      children: [
        FlexiblePagination(
          controller: _paginationController,
          currentPage: _page,
          totalPages: totalPages,
          totalItems: _total,
          onPageChange: _handlePageChange,
          margin: const EdgeInsets.fromLTRB(0, 16, 0, 16),
          padding: const EdgeInsets.all(16.0),
        ),
        if (isCompactWidth) const SizedBox(height: 40),
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

  Widget _buildInfoChip(IconData icon, String label, String value, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark 
          ? Colors.white.withValues(alpha: 0.05)
          : Colors.black.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark 
            ? Colors.white.withValues(alpha: 0.1)
            : Colors.black.withValues(alpha: 0.1),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: isDark ? Colors.white60 : Colors.black54,
          ),
          const SizedBox(width: 6),
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white60 : Colors.black54,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white.withValues(alpha: 0.8) : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}
