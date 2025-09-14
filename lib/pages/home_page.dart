import 'package:dext/services/api_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:layout/layout.dart';
import '../models/user.dart';
import 'home_main_content.dart';
import 'home_history_content.dart';
import 'home_settings_content.dart';

// 定義不同斷點下的內容邊距值
final contentPadding = LayoutValue(
  xs: const EdgeInsets.all(16),
  sm: const EdgeInsets.all(20),
  md: const EdgeInsets.all(24),
  lg: const EdgeInsets.all(30),
);

// 定義不同斷點下的組件間距
final sectionSpacing = LayoutValue(
  xs: 20.0,
  sm: 30.0,
  md: 40.0,
  lg: 50.0,
);

// 定義側邊欄顯示邏輯
final showSidebarInDrawer = LayoutValue(xs: true, md: false);
final showSidebarInline = LayoutValue(xs: false, md: true);

class HomePage extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final bool isMobileOrTablet = showSidebarInDrawer.resolve(context);
    // 当达到桌面布局断点（md+）时，隐藏底部导航栏（跨平台统一：含 Web/其他端）
    final bool showDesktopLayout = showSidebarInline.resolve(context);
    final EdgeInsets padding = contentPadding.resolve(context);

    final contents = [
      HomeMainContent(
        projectCount: projectCount,
        surveyCount: surveyCount,
        onProjectTap: onProjectTap,
        onSurveyTap: onSurveyTap,
      ),
      const HomeHistoryContent(),
      HomeSettingsContent(
        onLogout: onLogout,
        onThemeModeChange: onThemeModeChange,
        onChangeAvatar: () {
    // 这里写修改头像的逻辑
    if (kDebugMode) {
      print('修改头像');
    }
  },
        apiService: apiService,
        userNotifier: userNotifier,
      ),
    ];

    return Scaffold(
      drawer: isMobileOrTablet ? _buildDrawer(context) : null,
      body: Stack(
        children: [
          Scaffold(
            bottomNavigationBar: !showDesktopLayout ? BottomNavigationBar(
              currentIndex: currentIndex,
              onTap: (index) {
                onTabChanged?.call(index);
              },
              items: const [
                BottomNavigationBarItem(icon: Icon(FIcons.house), label: '主页'),
                BottomNavigationBarItem(icon: Icon(FIcons.clock), label: '历史记录'),
                BottomNavigationBarItem(icon: Icon(FIcons.settings), label: '设置'),
              ],
              backgroundColor: Theme.of(context).colorScheme.surface,
            ) : null,
            body: LayoutBuilder(
              builder: (context, constraints) {
                return Padding(
                  padding: padding,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    switchInCurve: Curves.fastOutSlowIn,
                    switchOutCurve: Curves.fastOutSlowIn.flipped,
                    child: contents[currentIndex],
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
            currentIndex: currentIndex,
            onTap: (index) {
              onTabChanged?.call(index);
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
