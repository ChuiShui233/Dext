import 'package:flutter/material.dart';

typedef FetchTrend = Future<Map<String, dynamic>> Function(String range);

class DashboardChart extends StatefulWidget {
  final FetchTrend? fetchTrend; // 父级提供的获取趋势方法（B 方案）
  const DashboardChart({super.key, this.fetchTrend});

  @override
  State<DashboardChart> createState() => _DashboardChartState();
}

class _DashboardChartState extends State<DashboardChart> {
  String _range = '7d';
  bool _loading = false;
  List<String> _labels = const [];
  List<int> _counts = const [];
  double _prevTotalForRange = 0;

  @override
  void initState() {
    super.initState();
    _loadTrend();
  }

  Future<void> _loadTrend() async {
    if (widget.fetchTrend == null) return; // 兼容占位
    setState(() => _loading = true);
    try {
      // 记录加载前的总数，供动画起点使用
      final oldTotal = _counts.isNotEmpty ? _counts.fold<int>(0, (a, b) => a + b) : 0;
      final data = await widget.fetchTrend!.call(_range);
      final labels = (data['labels'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
      final counts = (data['counts'] as List<dynamic>?)?.map((e) => (e as num).toInt()).toList() ?? [];
      setState(() {
        _prevTotalForRange = oldTotal.toDouble();
        _labels = labels;
        _counts = counts;
      });
    } catch (_) {
      // 忽略，保持占位
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _setRange(String r) {
    if (_range == r) return;
    // 切换范围前，记录当前合计作为动画起点
    final oldTotal = _counts.isNotEmpty ? _counts.fold<int>(0, (a, b) => a + b) : 0;
    setState(() {
      _prevTotalForRange = oldTotal.toDouble();
      _range = r;
    });
    _loadTrend();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final hasData = _labels.isNotEmpty && _counts.isNotEmpty && _labels.length == _counts.length;
    final maxCount = hasData ? (_counts.reduce((a, b) => a > b ? a : b)) : 100;
    // 规范化标签显示：7日用 周几，月用 YY-MM（去掉前缀 20）
    final displayLabels = hasData
        ? _labels.map((s) {
            if (_range == '7d') {
              // 期望 YYYY-MM-DD -> 解析为周几
              try {
                final dt = DateTime.parse(s);
                // Dart: Monday=1 ... Sunday=7
                const names = ['周一','周二','周三','周四','周五','周六','周日'];
                final idx = (dt.weekday - 1).clamp(0, 6);
                return names[idx];
              } catch (_) {
                // 回退：若无法解析，保留原串
              }
            } else if (_range == 'month') {
              // 期望 YYYY-MM -> 去掉前缀 "20" 为 YY-MM
              if (s.length >= 7 && s.startsWith('20')) {
                return s.substring(2, 7);
              }
            }
            return s;
          }).toList()
        : const <String>[];

    // 按范围展示合计：7日显示“近7日合计”，按月显示“当月合计”
    final int? totalForRange = hasData ? _counts.fold<int>(0, (a, b) => a + b) : null;
    final String totalLabel = _range == 'month' ? '当月合计' : '近7日合计';

    return LayoutBuilder(
      builder: (context, constraints) {
        // 根据可用空间自适应高度：移动端更紧凑，桌面端略高；并限制在合理范围内
        final screenH = MediaQuery.of(context).size.height;
        final isCompact = constraints.maxWidth < 800;
        final target = (screenH * (isCompact ? 0.28 : 0.36));
        final chartHeight = target.clamp(220.0, 420.0);
        // 柱体最大高度：扣除顶部标题与内边距后的视觉高度
        final barMaxHeight = chartHeight - 50; // 约留出标题、间距

        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDark ? theme.colorScheme.surface.withValues(alpha: 0.6) : Colors.white.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isDark ? theme.colorScheme.outline.withValues(alpha: 0.2) : Colors.grey[200]!,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '答卷提交趋势',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        if (totalForRange != null) ...[
                          const SizedBox(height: 6),
                          TweenAnimationBuilder<double>(
                            tween: Tween<double>(
                              begin: _prevTotalForRange,
                              end: totalForRange.toDouble(),
                            ),
                            duration: const Duration(milliseconds: 600),
                            curve: Curves.easeOutCubic,
                            builder: (context, value, child) {
                              return Text(
                                '$totalLabel ${value.round()}',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: theme.colorScheme.onSurface.withValues(alpha: 0.70),
                                  fontWeight: FontWeight.w500,
                                ),
                              );
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                  Flexible(
                    child: Align(
                      alignment: Alignment.topRight,
                      child: SegmentedButton<String>(
                        showSelectedIcon: false,
                        style: ButtonStyle(
                          visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
                          padding: WidgetStatePropertyAll(
                            const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          ),
                          foregroundColor: WidgetStateProperty.resolveWith((states) {
                            if (states.contains(WidgetState.selected)) {
                              return Theme.of(context).colorScheme.onPrimaryContainer;
                            }
                            return Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7);
                          }),
                          backgroundColor: WidgetStateProperty.resolveWith((states) {
                            if (states.contains(WidgetState.selected)) {
                              return Theme.of(context).colorScheme.primaryContainer;
                            }
                            return null;
                          }),
                          side: WidgetStateProperty.resolveWith((states) {
                            final color = Theme.of(context).colorScheme.outline.withValues(
                              alpha: states.contains(WidgetState.selected) ? 0.0 : 0.3,
                            );
                            return BorderSide(color: color, width: 1);
                          }),
                        ),
                        segments: const <ButtonSegment<String>>[
                          ButtonSegment<String>(value: '7d', label: Text('7日')),
                          ButtonSegment<String>(value: 'month', label: Text('月')),
                        ],
                        selected: <String>{_range},
                        onSelectionChanged: (selection) {
                          if (selection.isNotEmpty) {
                            _setRange(selection.first);
                          }
                        },
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              SizedBox(
                height: chartHeight,
                child: _loading
                    ? Center(child: CircularProgressIndicator(color: theme.colorScheme.primary))
                    : hasData
                        ? _buildBars(context, displayLabels, _counts, maxCount, barMaxHeight)
                        : _buildPlaceholder(context, barMaxHeight),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBars(BuildContext context, List<String> labels, List<int> counts, int maxCount, double barMaxHeight) {
    final theme = Theme.of(context);
    final barColor = theme.colorScheme.primary;
    final onSurface60 = theme.colorScheme.onSurface.withValues(alpha: 0.6);
    final onSurface80 = theme.colorScheme.onSurface.withValues(alpha: 0.8);

    // 动态计算柱子宽度，避免溢出
    final itemCount = labels.length;
    final availableWidth = MediaQuery.of(context).size.width - 80; // 减去padding
    final maxItemWidth = (availableWidth / itemCount).clamp(20.0, 60.0);
    final barWidth = (maxItemWidth * 0.4).clamp(12.0, 24.0);
    final labelWidth = maxItemWidth;

    final items = <Widget>[];
    for (int i = 0; i < labels.length; i++) {
      final ratio = maxCount > 0 ? (counts[i] / maxCount) : 0.0;
      items.add(Expanded(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            // 顶部显示数值
            Text(
              '${counts[i]}',
              style: TextStyle(color: onSurface80, fontSize: 10, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Container(
              width: barWidth,
              height: barMaxHeight * ratio,
              decoration: BoxDecoration(color: barColor, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: labelWidth,
              child: Text(
                labels[i],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(color: onSurface60, fontSize: 10),
              ),
            ),
          ],
        ),
      ));
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: items,
    );
  }

  Widget _buildPlaceholder(BuildContext context, double barMaxHeight) {
    // 原静态示例作为占位
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _placeholderBar(context, 'Mon', 0.4, barMaxHeight),
        _placeholderBar(context, 'Tue', 0.7, barMaxHeight),
        _placeholderBar(context, 'Wed', 0.6, barMaxHeight),
        _placeholderBar(context, 'Thu', 0.5, barMaxHeight),
        _placeholderBar(context, 'Fri', 0.9, barMaxHeight),
        _placeholderBar(context, 'Sat', 0.4, barMaxHeight),
        _placeholderBar(context, 'Sun', 0.6, barMaxHeight),
      ],
    );
  }

  Widget _placeholderBar(BuildContext context, String label, double heightRatio, double barMaxHeight) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Container(
          width: 24,
          height: barMaxHeight * heightRatio,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: 48,
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 11),
          ),
        ),
      ],
    );
  }
}
