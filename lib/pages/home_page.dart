import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:dext/services/api_service.dart';
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
  final Function(double)? onDpiScaleChange;
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
    this.onDpiScaleChange,
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
  
  Future<void> _loadCachedAnalytics() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('analytics_overview');
      if (cached != null) {
        final data = json.decode(cached) as Map<String, dynamic>;
        // 检查缓存是否包含新字段，如果没有则清除旧缓存并强制刷新
        if (!data.containsKey('totalSurveys') || !data.containsKey('activeSurveys')) {
          await prefs.remove('analytics_overview');
          // 不设置 _cachedAnalytics，让 _loadAnalytics 重新获取
          return;
        }
        if (mounted) {
          setState(() {
            _cachedAnalytics = {
              'totalViews': (data['totalViews'] as num?)?.toInt() ?? 0,
              'totalSubmits': (data['totalSubmits'] as num?)?.toInt() ?? 0,
              'totalSurveys': (data['totalSurveys'] as num?)?.toInt() ?? 0,
              'activeSurveys': (data['activeSurveys'] as num?)?.toInt() ?? 0,
            };
          });
        }
      }
    } catch (_) {
      // 忽略错误，_loadAnalytics 会处理
    }
  }
  
  Future<void> _loadAnalytics() async {
    if (_isLoadingAnalytics) return;
    if (_cachedAnalytics != null) return;
    
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
          _cachedAnalytics = const {'totalViews': 0, 'totalSubmits': 0, 'totalSurveys': 0, 'activeSurveys': 0};
          _isLoadingAnalytics = false;
        });
      }
    }
  }

  Widget _buildNavItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required int index,
    required bool isSelected,
  }) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => widget.onTabChanged?.call(index),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 24,
                  color: isSelected
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // 必须调用以支持 AutomaticKeepAliveClientMixin
    showSidebarInDrawer.resolve(context);
    final bool showDesktopLayout = showSidebarInline.resolve(context);
    final EdgeInsets padding = contentPadding.resolve(context);

    final totals = _cachedAnalytics ?? const {'totalViews': 0, 'totalSubmits': 0, 'totalSurveys': 0, 'activeSurveys': 0};
    Widget dashboardContent = HomeMainContent(
      projectCount: totals['totalSurveys'] ?? 0,
      surveyCount: totals['activeSurveys'] ?? 0,
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
        onDpiScaleChange: widget.onDpiScaleChange,
        onChangeAvatar: () {
  },
        apiService: widget.apiService,
        userNotifier: widget.userNotifier,
      ),
    ];

    return Scaffold(
      body: Stack(
        children: [
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
            body: LayoutBuilder(
              builder: (context, constraints) {
                final Widget current = AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  switchInCurve: Curves.fastOutSlowIn,
                  switchOutCurve: Curves.fastOutSlowIn.flipped,
                  child: contents[widget.currentIndex],
                );
                
                final contentWidget = widget.currentIndex == 2
                    ? current
                    : Padding(
                        padding: padding,
                        child: current,
                      );
                
                // 桌面端不显示底部导航栏
                if (showDesktopLayout) {
                  return contentWidget;
                }
                
                // 手机端：使用覆盖式底部导航栏
                return Stack(
                  children: [
                    // 主内容（全屏显示，可以滚动到导航栏后面）
                    contentWidget,
                    
                    // 覆盖式导航栏
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        height: 68 + MediaQuery.of(context).padding.bottom,
                        padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
                        child: ClipRRect(
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(24),
                            topRight: Radius.circular(24),
                          ),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                            child: Container(
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.6),
                                  borderRadius: const BorderRadius.only(
                                    topLeft: Radius.circular(24),
                                    topRight: Radius.circular(24),
                                  ),
                                  border: Border.all(
                                    color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
                                    width: 1,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.15),
                                      blurRadius: 40,
                                      offset: const Offset(0, -6),
                                    ),
                                  ],
                                ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceAround,
                                children: [
                                  _buildNavItem(
                                    context,
                                    icon: FIcons.house,
                                    label: '主页',
                                    index: 0,
                                    isSelected: widget.currentIndex == 0,
                                  ),
                                  _buildNavItem(
                                    context,
                                    icon: FIcons.clock,
                                    label: '历史',
                                    index: 1,
                                    isSelected: widget.currentIndex == 1,
                                  ),
                                  _buildNavItem(
                                    context,
                                    icon: FIcons.settings,
                                    label: '设置',
                                    index: 2,
                                    isSelected: widget.currentIndex == 2,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}