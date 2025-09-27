import 'dart:async';
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:layout/layout.dart';
import '../services/api_service.dart';
import 'submission_detail_page.dart';
import '../main.dart' show isDesktop;

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
  int? _selectedType; // 0 普通 1 限时 2 限次 3 自选
  int _page = 1;
  final int _pageSize = 10;
  int _total = 0;
  List<Map<String, dynamic>> _items = [];
  Timer? _debounce;
  
  // 分页相关
  FPaginationController _paginationController = FPaginationController(pages: 1);

  @override
  void initState() {
    super.initState();
    _typeSelectController = FSelectController<int>(vsync: this);
    _fetch();
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
    setState(() => _loading = true);
    if (resetPage) {
      _page = 1;
      _paginationController.page = 0; // 同步重置分页控制器
    }
    try {
      final resp = await widget.apiService.getSubmissionHistory(
        query: _searchController.text.trim().isEmpty ? null : _searchController.text.trim(),
        type: _selectedType,
        page: _page,
        pageSize: _pageSize,
      );
      if (!mounted) return;
      final items = (resp['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      setState(() {
        _items = items;
        _total = (resp['total'] as num?)?.toInt() ?? items.length;
        _loading = false;
      });
      
      // 更新分页控制器
      final totalPages = (_total / _pageSize).ceil();
      _paginationController.dispose();
      _paginationController = FPaginationController(pages: totalPages > 0 ? totalPages : 1);
      // 同步当前页码到分页控制器（转换为0-based）
      _paginationController.page = (_page - 1).clamp(0, (totalPages - 1).clamp(0, double.infinity).toInt());
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showFToast(
        context: context,
        alignment: FToastAlignment.bottomRight,
        title: const Text('加载失败'),
        description: Text('获取提交记录失败: $e'),
      );
    }
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _fetch(resetPage: true));
  }

  // 分页处理方法
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final value = PageStorage.maybeOf(context)?.readState(context) ?? 0;
    _paginationController.page = value;
  }

  void _handlePageChange(int page) {
    setState(() {
      _page = page + 1; // FPagination 是 0-based，但 API 是 1-based
    });
    _fetch();
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

  String _statusText(int s) {
    switch (s) {
      case 0: return '未发布';
      case 1: return '发布中';
      case 2: return '已完结';
      default: return '未知状态';
    }
  }

  @override
  Widget build(BuildContext context) {
    final EdgeInsets outerPadding = LayoutValue(
      xs: const EdgeInsets.all(16),
      sm: const EdgeInsets.all(20),
      md: const EdgeInsets.all(24),
      lg: const EdgeInsets.all(30),
    ).resolve(context);

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Padding(
              padding: outerPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('提交记录', style: Theme.of(context).textTheme.headlineMedium),
                  SizedBox(height: LayoutValue(xs: 16.0, sm: 20.0, md: 24.0, lg: 28.0).resolve(context)),
                  _buildFilters(context),
                  const SizedBox(height: 12),
                  _buildListCard(context),
                ],
              ),
            ),
          ),
        ),
        _buildFPagination(context),
      ],
    );
  }

  Widget _buildFilters(BuildContext context) {
    return _glass(
      context,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: isDesktop ? 320 : 260,
                  child: FTextFormField(
                    controller: _searchController,
                    label: const Text('问卷名称关键字'),
                    hint: '输入名称搜索',
                    onChange: _onSearchChanged,
                  ),
                ),
                SizedBox(
                  width: isDesktop ? 220 : 200,
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
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FButton(
                      onPress: () => _fetch(resetPage: true),
                      child: const Text('搜索'),
                    ),
                    const SizedBox(width: 8),
                    FButton(
                      style: FButtonStyle.ghost,
                      onPress: () {
                        setState(() {
                          _selectedType = null;
                          // 尝试清空选择器的值（若组件支持）
                          try { _typeSelectController.value = null; } catch (_) {}
                        });
                        _fetch(resetPage: true);
                      },
                      child: const Text('重置筛选'),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListCard(BuildContext context) {
    return _glass(
      context,
      child: _loading
          ? const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          : (_items.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('暂无提交记录')),
                )
              : ListView.separated(
                  physics: const NeverScrollableScrollPhysics(),
                  shrinkWrap: true,
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final it = _items[index];
                    final answerId = (it['answerId'] as num?)?.toInt();
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 18,
                            child: Text(((it['surveyName'] ?? '?') as String).characters.first),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        (it['surveyName'] ?? '') as String,
                                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 4,
                                  children: [
                                    _kv('类型', _typeText((it['surveyType'] as num?)?.toInt() ?? -1)),
                                    _kv('状态', _statusText((it['surveyStatus'] as num?)?.toInt() ?? -1)),
                                    _kv('创建人', (it['creator'] ?? '') as String),
                                    _kv('提交时间', (it['submitTime'] ?? '') as String),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          FButton(
                            onPress: answerId == null ? null : () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => SubmissionDetailPage(
                                    apiService: widget.apiService,
                                    answerId: answerId,
                                  ),
                                ),
                              );
                            },
                            child: const Text('查看详细'),
                          ),
                        ],
                      ),
                    );
                  },
                )),
    );
  }

  Widget _buildFPagination(BuildContext context) {
    final totalPages = (_total / _pageSize).ceil();
    if (totalPages <= 1) return const SizedBox.shrink();
    
    // 确保分页控制器显示正确的当前页
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_paginationController.page != _page - 1) {
        _paginationController.page = (_page - 1).clamp(0, (totalPages - 1).clamp(0, double.infinity).toInt());
      }
    });
    
    final bool isMobile = LayoutValue(xs: true, md: false).resolve(context);

    return Padding(
      padding: EdgeInsets.only(bottom: isMobile ? 46 : 0),
      child: _glass(
        context,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '共 $_total 条记录，第 $_page / $totalPages 页',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
              FPagination(
                controller: _paginationController,
                onChange: _handlePageChange,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _glass(BuildContext context, {required Widget child}) {
    return Card(
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      color: Theme.of(context).brightness == Brightness.dark
          ? Colors.white.withValues(alpha: 0.04)
          : Colors.white.withValues(alpha: 0.8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.06),
          width: 1,
        ),
      ),
      child: child,
    );
  }

  Widget _kv(String k, String v) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$k: ', style: const TextStyle(fontWeight: FontWeight.w600)),
        Text(v),
      ],
    );
  }
}
