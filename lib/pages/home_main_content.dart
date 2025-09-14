import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:layout/layout.dart';
import '../widgets/dashboard_stats_card.dart';
import '../widgets/dashboard_chart.dart';
import '../widgets/recent_survey_responses_list.dart';

// 定义不同斷點下的組件間距
final sectionSpacing = LayoutValue(
  xs: 20.0,
  sm: 30.0,
  md: 40.0,
  lg: 50.0,
);

class HomeMainContent extends StatelessWidget {
  final int projectCount;
  final int surveyCount;
  final VoidCallback onProjectTap;
  final VoidCallback onSurveyTap;

  const HomeMainContent({
    super.key,
    required this.projectCount,
    required this.surveyCount,
    required this.onProjectTap,
    required this.onSurveyTap,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 添加顶部安全区域间距，避免与系统标题栏重叠
          SizedBox(height: MediaQuery.of(context).padding.top + 16),
          
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
              Row(
                children: [
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
                            value: '1,234',
                            subtitle: '本周新增 89 个',
                            icon: FIcons.messageSquare,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: DashboardStatsCard(
                            title: '完成率',
                            value: '87.5%',
                            subtitle: '较上月提升 5.2%',
                            icon: FIcons.check,
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
                        value: '1,234',
                        subtitle: '本周新增 89 个',
                        icon: FIcons.messageSquare,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: DashboardStatsCard(
                        title: '完成率',
                        value: '87.5%',
                        subtitle: '较上月提升 5.2%',
                        icon: FIcons.check,
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
                    const DashboardChart(),
                    const SizedBox(height: 24),
                    const RecentSurveyResponsesList(),
                  ],
                );
              } else {
                // 桌面端：水平排列
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 左侧图表区域
                    Expanded(
                      flex: 2,
                      child: const DashboardChart(),
                    ),
                    const SizedBox(width: 24),
                    // 右侧问卷回复记录
                    Expanded(
                      flex: 1,
                      child: const RecentSurveyResponsesList(),
                    ),
                  ],
                );
              }
            },
          ),
        ],
      ),
    );
  }

} 