import 'dart:async';
import 'dart:convert';

import 'package:dext/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:layout/layout.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/frosted_glass_background.dart';
import 'home_history_content.dart';
import 'home_main_content.dart';
import 'settings/home_settings_content.dart';

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

class HomeTabProvider extends ChangeNotifier {
  int _index;

  HomeTabProvider({int initialIndex = 0}) : _index = initialIndex;

  int get index => _index;

  void setIndex(int value) {
    if (_index == value) return;

    _index = value;
    notifyListeners();
  }
}

class HomePage extends StatefulWidget {
  final int projectCount;
  final int surveyCount;
  final VoidCallback onProjectTap;
  final VoidCallback onSurveyTap;
  final VoidCallback onFillSurveyTab;
  final VoidCallback onLogout;
  final Function(ThemeMode)? onThemeModeChange;
  final Function(double)? onDpiScaleChange;
  final ApiService apiService;
  final int currentIndex;
  final void Function(int index) onTabChanged;

  const HomePage({
    super.key,
    required this.projectCount,
    required this.surveyCount,
    required this.onProjectTap,
    required this.onSurveyTap,
    required this.onFillSurveyTab,
    required this.onLogout,
    this.onThemeModeChange,
    this.onDpiScaleChange,
    required this.apiService,
    required this.currentIndex,
    required this.onTabChanged,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with AutomaticKeepAliveClientMixin {
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

        if (!data.containsKey('totalSurveys') ||
            !data.containsKey('activeSurveys')) {
          await prefs.remove('analytics_overview');
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
    } catch (_) {}
  }

  Future<void> _loadAnalytics() async {
    if (_isLoadingAnalytics) return;
    if (_cachedAnalytics != null) return;

    Timer? loadingTimer = Timer(
      const Duration(milliseconds: 150),
      () {
        if (mounted && _isLoadingAnalytics) {
          setState(() => _isLoadingAnalytics = true);
        }
      },
    );

    try {
      final analytics =
          await widget.apiService.getAnalyticsOverview();

      loadingTimer.cancel();

      if (mounted) {
        setState(() {
          _cachedAnalytics = analytics;
          _isLoadingAnalytics = false;
        });
      }
    } catch (_) {
      loadingTimer.cancel();

      if (mounted) {
        setState(() {
          _cachedAnalytics = const {
            'totalViews': 0,
            'totalSubmits': 0,
            'totalSurveys': 0,
            'activeSurveys': 0,
          };

          _isLoadingAnalytics = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final bool showDesktopLayout =
        showSidebarInline.resolve(context);

    final EdgeInsets padding =
        contentPadding.resolve(context);

    final overview = _cachedAnalytics ??
        const {
          'totalViews': 0,
          'totalSubmits': 0,
          'totalSurveys': 0,
          'activeSurveys': 0,
        };

    return ChangeNotifierProvider(
      create: (_) => HomeTabProvider(initialIndex: widget.currentIndex),
      child: Consumer<HomeTabProvider>(
        builder: (context, tabProvider, _) {
          final currentIndex = tabProvider.index;

          final contents = [
            HomeMainContent(
              projectCount:
                  overview['totalSurveys'] ?? 0,
              surveyCount:
                  overview['activeSurveys'] ?? 0,
              totalViews:
                  overview['totalViews'] ?? 0,
              totalSubmits:
                  overview['totalSubmits'] ?? 0,
              onProjectTap: widget.onProjectTap,
              onSurveyTap: widget.onSurveyTap,
              onFillSurveyTab:
                  widget.onFillSurveyTab,
              fetchTrend: (range) => widget.apiService
                  .getSubmitTrend(range: range),
              apiService: widget.apiService,
            ),

            HomeHistoryContent(
              apiService: widget.apiService,
            ),

            HomeSettingsContent(
              onLogout: widget.onLogout,
              onChangeAvatar: () {},
              apiService: widget.apiService,
            ),
          ];

          final Widget current = IndexedStack(
            index: currentIndex,
            children: contents,
          );

          final contentWidget = currentIndex == 2
              ? current
              : Padding(
                  padding: padding.copyWith(
                    bottom: padding.bottom + 48,
                  ),
                  child: current,
                );

          return Scaffold(
            backgroundColor:
                Theme.of(context).brightness ==
                        Brightness.dark
                    ? const Color(0xFF09090B)
                    : const Color(0xFFF7F7F8),
            body: Stack(
              children: [
                if (currentIndex == 0)
                  const FrostedGlassBackground(
                    count: 8,
                    blurSigma: 120,
                    blobOpacity: 0.28,
                    animated: true,
                    vignette: true,
                  )
                else
                  Container(
                    color:
                        Theme.of(context).brightness ==
                                Brightness.dark
                            ? const Color(0xFF09090B)
                            : const Color(
                                0xFFF7F7F8,
                              ),
                  ),

                Scaffold(
                  backgroundColor: Colors.transparent,
                  extendBody: true,
                  body:
                      showDesktopLayout
                          ? contentWidget
                          : Scaffold(
                              backgroundColor:
                                  Colors.transparent,
                              extendBody: true,
                              body: contentWidget,
                              bottomNavigationBar:
                                  const _AnimatedBottomBar(),
                            ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _AnimatedBottomBar extends StatelessWidget {
  const _AnimatedBottomBar();

  @override
  Widget build(BuildContext context) {
    final provider =
        context.watch<HomeTabProvider>();

    final currentIndex = provider.index;

    final dark =
        Theme.of(context).brightness ==
        Brightness.dark;

    final activeColor =
        dark
            ? Colors.white
            : const Color(0xFF111111);

    return Container(
      height: 64 + MediaQuery.of(context).padding.bottom,
      decoration: BoxDecoration(
        color:
            dark
                ? const Color(0xFF0B0B0C)
                : Colors.white,
        border: Border(
          top: BorderSide(
            color:
                dark
                    ? Colors.white.withValues(
                        alpha: 0.05,
                      )
                    : Colors.black.withValues(
                        alpha: 0.05,
                      ),
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final itemWidth =
                constraints.maxWidth / 3;

            return Stack(
              children: [
                AnimatedPositioned(
                  duration: const Duration(
                    milliseconds: 380,
                  ),
                  curve: Curves.easeOutExpo,
                  top: 1,
                  left:
                      itemWidth * currentIndex +
                      (itemWidth - 24) / 2,
                  child: Container(
                    width: 24,
                    height: 2,
                    decoration: BoxDecoration(
                      color: activeColor,
                      borderRadius:
                          BorderRadius.circular(999),
                    ),
                  ),
                ),

                Row(
                  children: [
                    Expanded(
                      child: _EdgeNavItem(
                        icon: FIcons.house,
                        label: '主页',
                        selected:
                            currentIndex == 0,
                        onTap:
                            () => provider
                                .setIndex(0),
                      ),
                    ),
                    Expanded(
                      child: _EdgeNavItem(
                        icon: FIcons.clock,
                        label: '历史',
                        selected:
                            currentIndex == 1,
                        onTap:
                            () => provider
                                .setIndex(1),
                      ),
                    ),
                    Expanded(
                      child: _EdgeNavItem(
                        icon: FIcons.settings,
                        label: '设置',
                        selected:
                            currentIndex == 2,
                        onTap:
                            () => provider
                                .setIndex(2),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _EdgeNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _EdgeNavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dark =
        Theme.of(context).brightness ==
        Brightness.dark;

    final activeColor =
        dark
            ? Colors.white
            : const Color(0xFF111111);

    final inactiveColor =
        dark
            ? Colors.white.withValues(
                alpha: 0.42,
              )
            : Colors.black.withValues(
                alpha: 0.42,
              );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        child: SizedBox(
          height: 64,
          child: Column(
            mainAxisAlignment:
                MainAxisAlignment.center,
            children: [
              AnimatedScale(
                duration: const Duration(
                  milliseconds: 180,
                ),
                curve: Curves.easeOutCubic,
                scale: selected ? 1.05 : 1,
                child: AnimatedSlide(
                  duration: const Duration(
                    milliseconds: 180,
                  ),
                  curve: Curves.easeOutCubic,
                  offset:
                      selected
                          ? const Offset(
                            0,
                            -0.03,
                          )
                          : Offset.zero,
                  child: Icon(
                    icon,
                    size: 20,
                    color:
                        selected
                            ? activeColor
                            : inactiveColor,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              AnimatedDefaultTextStyle(
                duration: const Duration(
                  milliseconds: 180,
                ),
                curve: Curves.easeOutCubic,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight:
                      selected
                          ? FontWeight.w600
                          : FontWeight.w500,
                  letterSpacing: -0.1,
                  color:
                      selected
                          ? activeColor
                          : inactiveColor,
                ),
                child: Text(label),
              ),
            ],
          ),
        ),
      ),
    );
  }
}