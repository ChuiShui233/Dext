import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:layout/layout.dart';
import 'package:flutter_speed_dial/flutter_speed_dial.dart';
import '../widgets/top_safe_spacer.dart';
import '../widgets/dashboard_stats_card.dart';
import '../widgets/dashboard_chart.dart';
import '../widgets/recent_survey_responses_list.dart';
import 'public_access_page.dart';

final sectionSpacing = LayoutValue(
  xs: 20.0,
  sm: 30.0,
  md: 40.0,
  lg: 50.0,
);

class HomeMainContent extends StatelessWidget {
  final int projectCount;
  final int surveyCount;
  final int totalSubmits; // 总回复数
  final int totalViews;   // 总浏览数
  final VoidCallback onProjectTap;
  final VoidCallback onSurveyTap;
  final FetchTrend? fetchTrend;

  const HomeMainContent({
    super.key,
    required this.projectCount,
    required this.surveyCount,
    this.totalSubmits = 0,
    this.totalViews = 0,
    required this.onProjectTap,
    required this.onSurveyTap,
    this.fetchTrend,
  });

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 800;
    return Stack(
      children: [
        ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 仅为移动端添加顶部留白，避免与页面级留白叠加
                const TopSafeSpacer(desktop: 0, web: 0, mobile: 24),
                
                // Dashboard标题
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '问卷数据概览',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (!isMobile)
                      Row(
                            children: [
                              FButton(
                                onPress: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => const PublicAccessPage(),
                                    ),
                                  );
                                },
                                child: const Text('填写问卷'),
                              ),
                          const SizedBox(width: 12),
                              FButton(
                                onPress: onProjectTap,
                                child: const Text('管理项目'),
                              ),
                          const SizedBox(width: 12),
                              FButton(
                                onPress: onSurveyTap,
                                child: const Text('管理问卷'),
                              ),
                            ],
                      ),
                  ],
                ),
                const SizedBox(height: 32),
                
                // 统计卡片行 - 响应式布局
                LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth < 800) {
                      // 移动端：2x2 网格布局
                      return Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: DashboardStatsCard(
                                  title: '总问卷数',
                                  value: projectCount.toString(),
                                  subtitle: '本月新增 ${(projectCount * 0.15).round()} 个',
                                  icon: FIcons.folderArchive,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: DashboardStatsCard(
                                  title: '活跃问卷',
                                  value: surveyCount.toString(),
                                  subtitle: '正在收集回复',
                                  icon: FIcons.notebookPen,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: DashboardStatsCard(
                                  title: '总回复数',
                                  value: totalSubmits.toString(),
                                  subtitle: '按所有问卷统计',
                                  icon: FIcons.messageSquare,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: DashboardStatsCard(
                                  title: '总浏览数',
                                  value: totalViews.toString(),
                                  subtitle: '按所有问卷统计',
                                  icon: FIcons.eye,
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                    } else {
                      // 桌面端：单行布局
                      return Row(
                        children: [
                          Expanded(
                            child: DashboardStatsCard(
                              title: '总问卷数',
                              value: projectCount.toString(),
                              subtitle: '本月新增 ${(projectCount * 0.15).round()} 个',
                              icon: FIcons.folderArchive,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: DashboardStatsCard(
                              title: '活跃问卷',
                              value: surveyCount.toString(),
                              subtitle: '正在收集回复',
                              icon: FIcons.notebookPen,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: DashboardStatsCard(
                              title: '总回复数',
                              value: totalSubmits.toString(),
                              subtitle: '按所有问卷统计',
                              icon: FIcons.messageSquare,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: DashboardStatsCard(
                              title: '总浏览数',
                              value: totalViews.toString(),
                              subtitle: '按所有问卷统计',
                              icon: FIcons.eye,
                            ),
                          ),
                        ],
                      );
                    }
                  },
                ),
                const SizedBox(height: 32),
                
                // 图表和回复记录 - 响应式布局
                LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth < 800) {
                      // 移动端：垂直堆叠
                      return Column(
                        children: [
                          DashboardChart(fetchTrend: fetchTrend),
                          const SizedBox(height: 24),
                          const RecentSurveyResponsesList(),
                        ],
                      );
                    } else {
                      // 桌面端：水平排列
                      // 计算与图表一致的内容高度，供右侧卡片内部滚动使用
                      final screenH = MediaQuery.of(context).size.height;
                      final isCompact = constraints.maxWidth < 800;
                      final target = (screenH * (isCompact ? 0.28 : 0.36));
                      final chartHeight = target.clamp(220.0, 420.0);

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 左侧图表区域
                          Expanded(
                            flex: 2,
                            child: DashboardChart(fetchTrend: fetchTrend),
                          ),
                          const SizedBox(width: 24),
                          // 右侧问卷回复记录
                          Expanded(
                            flex: 1,
                            child: RecentSurveyResponsesList(fixedHeight: chartHeight),
                          ),
                        ],
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        ),
        if (isMobile)
          Positioned(
            right: 4,
            bottom: 62,
            child: Builder(
              builder: (context) {
                final screenWidth = MediaQuery.of(context).size.width;
                final isLargeScreen = screenWidth > 600; // 大屏幕阈值
                
                final mainButtonSize = isLargeScreen ? 72.0 : 64.0;
                final childButtonSize = isLargeScreen ? 64.0 : 56.0;
                final iconSize = isLargeScreen ? 30.0 : 26.0;
                
                return SpeedDial(
                  icon: Icons.add,
                  activeIcon: Icons.close,
                  foregroundColor: Colors.white,
                  backgroundColor: const Color(0xFF121212), // 高级黑，深浅色模式不变
                  buttonSize: Size(mainButtonSize, mainButtonSize),
                  childrenButtonSize: Size(childButtonSize, childButtonSize),
                  overlayOpacity: 0.1,
                  spacing: 6,
                  spaceBetweenChildren: 6,
                  children: [
                    SpeedDialChild(
                      child: Icon(Icons.edit_note_outlined, size: iconSize),
                      label: '填写问卷',
                      backgroundColor: const Color(0xFF121212),
                      foregroundColor: Colors.white,
                      labelBackgroundColor: Colors.white,
                      labelStyle: const TextStyle(color: Colors.black87),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const PublicAccessPage(),
                          ),
                        );
                      },
                    ),
                    SpeedDialChild(
                      child: Icon(Icons.folder_outlined, size: iconSize),
                      label: '管理项目',
                      backgroundColor: const Color(0xFF121212),
                      foregroundColor: Colors.white,
                      labelBackgroundColor: Colors.white,
                      labelStyle: const TextStyle(color: Colors.black87),
                      onTap: onProjectTap,
                    ),
                    SpeedDialChild(
                      child: Icon(Icons.notes_outlined, size: iconSize),
                      label: '管理问卷',
                      backgroundColor: const Color(0xFF121212),
                      foregroundColor: Colors.white,
                      labelBackgroundColor: Colors.white,
                      labelStyle: const TextStyle(color: Colors.black87),
                      onTap: onSurveyTap,
                    ),
                  ],
                );
              },
            ),
          ),
      ],
    );
  }
}