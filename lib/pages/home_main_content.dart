import 'package:dext/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
// Removed flutter_speed_dial; we now use a custom glass-style menu
import '../components/glass_fab_menu.dart';
import '../widgets/top_safe_spacer.dart';
import '../widgets/dashboard_stats_card.dart';
import '../widgets/dashboard_chart.dart';
import '../widgets/recent_survey_responses_list.dart';

class HomeMainContent extends StatelessWidget {
  final int projectCount;
  final int surveyCount;
  final int totalSubmits;
  final int totalViews;
  final VoidCallback onProjectTap;
  final VoidCallback onSurveyTap;
  final VoidCallback onFillSurveyTab;
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
    required this.onFillSurveyTab,
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
                const TopSafeSpacer(mobile:20),
                
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
                                onPress: onFillSurveyTab,
                                style: context.theme.buttonStyles.primary.call,
                                child: const Text('填写问卷'),
                              ),
                          const SizedBox(width: 12),
                              FButton(
                                onPress: onProjectTap,
                                style: context.theme.buttonStyles.secondary.call,
                                child: const Text('管理项目'),
                              ),
                          const SizedBox(width: 12),
                              FButton(
                                onPress: onSurveyTap,
                                style: context.theme.buttonStyles.outline.call,
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
          Positioned.fill(
            child: GlassFabMenu(
              padding: const EdgeInsets.only(right: 12, bottom: 24),
              onFillSurvey: onFillSurveyTab,
              onProjectTap: onProjectTap,
              onSurveyTap: onSurveyTap,
            ),
          ),
      ],
    );
  }
}