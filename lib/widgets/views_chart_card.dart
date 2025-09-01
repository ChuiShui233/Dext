import 'package:flutter/material.dart';
import 'line_chart.dart';

class ViewsChartCard extends StatefulWidget {
  const ViewsChartCard({super.key});

  @override
  State<ViewsChartCard> createState() => _ViewsChartCardState();
}

class _ViewsChartCardState extends State<ViewsChartCard> {
  List<Point> _viewsData = [];
  int _totalViews = 0;
  double _growthRate = 0.0;

  @override
  void initState() {
    super.initState();
    _generateSampleData();
  }

  void _generateSampleData() {
    // 生成模拟的浏览量数据（最近7天）
    final now = DateTime.now();
    final random = List.generate(7, (index) {
      now.subtract(Duration(days: 6 - index));
      final views = 100 + (index * 50) + (index * 20); // 模拟增长趋势
      return Point(index.toDouble(), views.toDouble());
    });

    setState(() {
      _viewsData = random;
      _totalViews = random.map((p) => p.y.toInt()).reduce((a, b) => a + b);
      
      // 计算增长率（与前一天相比）
      if (random.length >= 2) {
        final today = random.last.y;
        final yesterday = random[random.length - 2].y;
        _growthRate = ((today - yesterday) / yesterday * 100);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
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
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题和统计信息
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '浏览量统计',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '最近7天',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withValues(
                          alpha: 0.6,
                          red: Theme.of(context).colorScheme.onSurface.r,
                          green: Theme.of(context).colorScheme.onSurface.g,
                          blue: Theme.of(context).colorScheme.onSurface.b,
                        ),
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _totalViews.toString(),
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _growthRate >= 0 ? Icons.trending_up : Icons.trending_down,
                          size: 16,
                          color: _growthRate >= 0 ? Colors.green : Colors.red,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${_growthRate >= 0 ? '+' : ''}${_growthRate.toStringAsFixed(1)}%',
                          style: TextStyle(
                            fontSize: 12,
                            color: _growthRate >= 0 ? Colors.green : Colors.red,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
            
            const SizedBox(height: 20),
            
            // 图表区域
            SizedBox(
              height: 120,
              width: double.infinity,
              child: LineChart(
                points: _viewsData,
                color: Theme.of(context).colorScheme.primary,
                gradient: true,
                duration: const Duration(milliseconds: 1500),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // 底部统计信息
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem('今日', _viewsData.isNotEmpty ? _viewsData.last.y.toInt().toString() : '0'),
                _buildStatItem('昨日', _viewsData.length >= 2 ? _viewsData[_viewsData.length - 2].y.toInt().toString() : '0'),
                _buildStatItem('平均', (_totalViews / 7).round().toString()),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurface.withValues(
              alpha: 0.6,
              red: Theme.of(context).colorScheme.onSurface.r,
              green: Theme.of(context).colorScheme.onSurface.g,
              blue: Theme.of(context).colorScheme.onSurface.b,
            ),
          ),
        ),
      ],
    );
  }
} 