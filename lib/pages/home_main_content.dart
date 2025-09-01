import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:layout/layout.dart';
import '../widgets/views_chart_card.dart';

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
          Text(
            '问卷调查平台',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          SizedBox(height: sectionSpacing.resolve(context)),
          Row(
            children: [
              Expanded(
                child: _buildCard(
                  context,
                  '项目管理',
                  projectCount.toString(),
                  FIcons.folderArchive,
                  Theme.of(context).brightness == Brightness.dark
                      ? Colors.white.withAlpha(255)
                      : Colors.black.withAlpha(255),
                  onProjectTap,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildCard(
                  context,
                  '问卷管理',
                  surveyCount.toString(),
                  FIcons.notebookPen,
                  Theme.of(context).brightness == Brightness.dark
                      ? Colors.white.withAlpha(255)
                      : Colors.black.withAlpha(255),
                  onSurveyTap,
                ),
              ),
            ],
          ),
          SizedBox(height: sectionSpacing.resolve(context)),
          // 添加浏览量统计卡片
          const ViewsChartCard(),
        ],
      ),
    );
  }

  Widget _buildCard(BuildContext context, String title, String count, IconData icon, Color color, VoidCallback onTap) {
    return Card(
      elevation: 2,
      color: Theme.of(context).brightness == Brightness.dark 
          ? Colors.transparent
          : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: Theme.of(context).brightness == Brightness.dark 
            ? Colors.white.withValues(alpha: 0.1)
            : Colors.black.withValues(alpha: 0.1),
          width: 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48, color: color),
              const SizedBox(height: 16),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                count,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
} 