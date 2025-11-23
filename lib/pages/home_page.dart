import 'dart:async';
import 'dart:convert';
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
  bool _showMobileNav = false; // 控制移动端导航张开动画
  
  @override
  void initState() {
    super.initState();
    _loadCachedAnalytics();
    _loadAnalytics();
    // 等首帧完成后触发展开动画
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() => _showMobileNav = true);
      }
    });
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


  @override
  Widget build(BuildContext context) {
    super.build(context);
    showSidebarInDrawer.resolve(context);
    final bool showDesktopLayout = showSidebarInline.resolve(context);
    final EdgeInsets padding = contentPadding.resolve(context);

    final overview = _cachedAnalytics ?? const {'totalViews': 0, 'totalSubmits': 0, 'totalSurveys': 0, 'activeSurveys': 0};
    Widget dashboardContent = HomeMainContent(
      projectCount: overview['totalSurveys'] ?? 0,
      surveyCount: overview['activeSurveys'] ?? 0,
      totalViews: overview['totalViews'] ?? 0,
      totalSubmits: overview['totalSubmits'] ?? 0,
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
          if (widget.currentIndex == 2)
            Container(color: Theme.of(context).colorScheme.surface)
          else
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
                
                if (showDesktopLayout) {
                  return contentWidget;
                }
                
                final double safeBottom = MediaQuery.of(context).padding.bottom;
                final double fullHeight = 64 + safeBottom; // 导航栏期望高度
                return Scaffold(
                  backgroundColor: Colors.transparent,
                  body: contentWidget,
                  bottomNavigationBar: TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: _showMobileNav ? fullHeight : 0),
                    duration: const Duration(milliseconds: 320),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, child) {
                      final double t = (value / (fullHeight == 0 ? 1 : fullHeight)).clamp(0.0, 1.0);
                      return SizedBox(
                        height: value,
                        child: Opacity(
                          opacity: t,
                          child: Transform.translate(
                            offset: Offset(0, (1 - t) * 12),
                            child: child,
                          ),
                        ),
                      );
                    },
                    child: NavigationBarTheme(
                      data: NavigationBarThemeData(
                        indicatorColor: Theme.of(context).brightness == Brightness.light
                            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.24)
                            : Theme.of(context).colorScheme.primary.withValues(alpha: 0.20),
                        iconTheme: WidgetStateProperty.resolveWith<IconThemeData>((states) {
                          if (states.contains(WidgetState.selected)) {
                            return IconThemeData(color: Theme.of(context).colorScheme.primary);
                          }
                          return IconThemeData(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6));
                        }),
                        labelTextStyle: WidgetStateProperty.resolveWith<TextStyle>((states) {
                          if (states.contains(WidgetState.selected)) {
                            return TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            );
                          }
                          return TextStyle(
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                            fontWeight: FontWeight.w500,
                          );
                        }),
                      ),
                      child: NavigationBar(
                        selectedIndex: widget.currentIndex,
                        onDestinationSelected: (index) => widget.onTabChanged?.call(index),
                        destinations: const [
                          NavigationDestination(icon: Icon(FIcons.house), label: '主页', tooltip: ''),
                          NavigationDestination(icon: Icon(FIcons.clock), label: '历史', tooltip: ''),
                          NavigationDestination(icon: Icon(FIcons.settings), label: '设置', tooltip: ''),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}