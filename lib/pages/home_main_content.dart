import 'package:dext/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:flutter_speed_dial/flutter_speed_dial.dart';
import '../widgets/top_safe_spacer.dart';
import '../widgets/dashboard_stats_card.dart';
import '../widgets/dashboard_chart.dart';
import '../widgets/recent_survey_responses_list.dart';
import 'public_access_page.dart';

class HomeMainContent extends StatelessWidget {
  final int projectCount;
  final int surveyCount;
  final int totalSubmits;
  final int totalViews;
  final VoidCallback onProjectTap;
  final VoidCallback onSurveyTap;
  final FetchTrend? fetchTrend;
  final ApiService? apiService;

  const HomeMainContent({
    super.key,
    required this.projectCount,
    required this.surveyCount,
    this.totalSubmits = 0,
    this.totalViews = 0,
    required this.onProjectTap,
    required this.onSurveyTap,
    this.fetchTrend,
    this.apiService,
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
                const TopSafeSpacer(),
                
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
                      return Row(
                        children: [
                          Expanded(
                            child: DashboardStatsCard(
                              title: '总问卷数',
                              value: projectCount.toString(),
                              subtitle: '新建问卷数',
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
                      return Column(
                        children: [
                          DashboardChart(fetchTrend: fetchTrend),
                          const SizedBox(height: 24),
                          RecentSurveyResponsesList(apiService: apiService),
                        ],
                      );
                    } else {
                      final screenH = MediaQuery.of(context).size.height;
                      final isCompact = constraints.maxWidth < 800;
                      final target = (screenH * (isCompact ? 0.28 : 0.36));
                      final chartHeight = target.clamp(220.0, 420.0);

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 2,
                            child: DashboardChart(fetchTrend: fetchTrend),
                          ),
                          const SizedBox(width: 24),
                          Expanded(
                            flex: 1,
                            child: RecentSurveyResponsesList(fixedHeight: chartHeight, apiService: apiService),
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
                      labelBackgroundColor: const Color(0xFF121212),
                      labelStyle: const TextStyle(color: Colors.white),
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
                      labelBackgroundColor: const Color(0xFF121212),
                      labelStyle: const TextStyle(color: Colors.white),
                      onTap: onProjectTap,
                    ),
                    SpeedDialChild(
                      child: Icon(Icons.notes_outlined, size: iconSize),
                      label: '管理问卷',
                      backgroundColor: const Color(0xFF121212),
                      foregroundColor: Colors.white,
                      labelBackgroundColor: const Color(0xFF121212),
                      labelStyle: const TextStyle(color: Colors.white),
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