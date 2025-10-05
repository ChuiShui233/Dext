import 'dart:async';
import 'dart:convert';
import 'package:dext/services/api_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:layout/layout.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';
import 'home_main_content.dart';
import 'home_history_content.dart';
import 'home_settings_content.dart';
import '../widgets/frosted_glass_background.dart';

final contentPadding = LayoutValue(
  xs: const EdgeInsets.all(16),
  sm: const EdgeInsets.all(20),
  md: const EdgeInsets.all(24),
  lg: const EdgeInsets.all(30),
);

final sectionSpacing = LayoutValue(
  xs: 20.0,
  sm: 30.0,
  md: 40.0,
  lg: 50.0,
);

final showSidebarInDrawer = LayoutValue(xs: true, md: false);
final showSidebarInline = LayoutValue(xs: false, md: true);

class HomePage extends StatefulWidget {
  final int currentIndex;
  final int projectCount;
  final int surveyCount;
  final VoidCallback onProjectTap;
  final VoidCallback onSurveyTap;
  final VoidCallback onLogout;
  final Function(ThemeMode) onThemeModeChange;
  final Function(int)? onTabChanged;
  final ApiService apiService;
  final ValueNotifier<User?>? userNotifier;

  const HomePage({
    super.key,
    required this.currentIndex,
    required this.projectCount,
    required this.surveyCount,
    required this.onProjectTap,
    required this.onSurveyTap,
    required this.onLogout,
    required this.onThemeModeChange,
    required this.apiService,
    this.onTabChanged,
    this.userNotifier,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  
  Map<String, int>? _cachedAnalytics;
  bool _isLoadingAnalytics = false;
  
  @override
  void initState() {
    super.initState();
    _loadCachedAnalytics();
    _loadAnalytics();
  }
  
  // 立即从缓存加载数据
  Future<void> _loadCachedAnalytics() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('analytics_overview');
      if (cached != null) {
        final data = json.decode(cached) as Map<String, dynamic>;
        if (mounted) {
          setState(() {
            _cachedAnalytics = {
              'totalViews': (data['totalViews'] as num?)?.toInt() ?? 0,
              'totalSubmits': (data['totalSubmits'] as num?)?.toInt() ?? 0,
            };
          });
        }
      }
    } catch (_) {
      // 忽略错误，_loadAnalytics 会处理
    }
  }
  
  Future<void> _loadAnalytics() async {
    if (_cachedAnalytics != null || _isLoadingAnalytics) return;
    
    // 延迟显示加载状态，如果缓存存在会立即返回
    Timer? loadingTimer = Timer(const Duration(milliseconds: 150), () {
      if (mounted && _isLoadingAnalytics) {
        setState(() => _isLoadingAnalytics = true);
      }
    });
    
    try {
      final analytics = await widget.apiService.getAnalyticsOverview();
      loadingTimer.cancel();
      if (mounted) {
        setState(() {
          _cachedAnalytics = analytics;
          _isLoadingAnalytics = false;
        });
      }
    } catch (e) {
      loadingTimer.cancel();
      if (mounted) {
        setState(() {
          _cachedAnalytics = const {'totalViews': 0, 'totalSubmits': 0};
          _isLoadingAnalytics = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // 必须调用以支持 AutomaticKeepAliveClientMixin
    final bool isMobileOrTablet = showSidebarInDrawer.resolve(context);
    // 当达到桌面布局断点（md+）时，隐藏底部导航栏（跨平台统一：含 Web/其他端）
    final bool showDesktopLayout = showSidebarInline.resolve(context);
    final EdgeInsets padding = contentPadding.resolve(context);

    final totals = _cachedAnalytics ?? const {'totalViews': 0, 'totalSubmits': 0};
    Widget dashboardContent = HomeMainContent(
      projectCount: widget.projectCount,
      surveyCount: widget.surveyCount,
      totalViews: totals['totalViews'] ?? 0,
      totalSubmits: totals['totalSubmits'] ?? 0,
      onProjectTap: widget.onProjectTap,
      onSurveyTap: widget.onSurveyTap,
      fetchTrend: (range) => widget.apiService.getSubmitTrend(range: range),
      apiService: widget.apiService,
    );

    final contents = [
      dashboardContent,
      HomeHistoryContent(apiService: widget.apiService),
      HomeSettingsContent(
        onLogout: widget.onLogout,
        onThemeModeChange: widget.onThemeModeChange,
        onChangeAvatar: () {
    // 这里写修改头像的逻辑
    if (kDebugMode) {
      print('修改头像');
    }
  },
        apiService: widget.apiService,
        userNotifier: widget.userNotifier,
      ),
    ];

    return Scaffold(
      drawer: isMobileOrTablet ? _buildDrawer(context) : null,
      body: Stack(
        children: [
          // 全局毛玻璃渐变背景（包含底部导航栏区域）
          const FrostedGlassBackground(
            count: 8,
            blurSigma: 120,
            blobOpacity: 0.5,
            animated: true,
            vignette: true,
          ),
          Scaffold(
            backgroundColor: Colors.transparent,
            extendBody: true,
            bottomNavigationBar: !showDesktopLayout ? BottomNavigationBar(
              currentIndex: widget.currentIndex,
              onTap: (index) {
                widget.onTabChanged?.call(index);
              },
              items: const [
                BottomNavigationBarItem(icon: Icon(FIcons.house), label: '主页'),
                BottomNavigationBarItem(icon: Icon(FIcons.clock), label: '历史记录'),
                BottomNavigationBarItem(icon: Icon(FIcons.settings), label: '设置'),
              ],
              backgroundColor: Theme.of(context).colorScheme.surface.withValues(alpha: 0.6),
              elevation: 0,
            ) : null,
            body: LayoutBuilder(
              builder: (context, constraints) {
                return Padding(
                  padding: padding,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    switchInCurve: Curves.fastOutSlowIn,
                    switchOutCurve: Curves.fastOutSlowIn.flipped,
                    child: contents[widget.currentIndex],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawer(BuildContext context) {
    return Drawer(
      child: Column(
        children: [
          const SizedBox(height: 25),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Image.asset(
                  'assets/images/Dext.png',
                  width: 32,
                  height: 32,
                  errorBuilder: (context, error, stackTrace) => const Icon(
                    FIcons.house,
                    size: 32,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          BottomNavigationBar(
            currentIndex: widget.currentIndex,
            onTap: (index) {
              widget.onTabChanged?.call(index);
            },
            items: const [
              BottomNavigationBarItem(icon: Icon(FIcons.house), label: '主页'),
              BottomNavigationBarItem(icon: Icon(FIcons.clock), label: '历史记录'),
              BottomNavigationBarItem(icon: Icon(FIcons.settings), label: '设置'),
            ],
          ),
        ],
      ),
    );
  }
}
