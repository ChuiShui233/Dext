import 'dart:async';
import 'package:flutter/material.dart';
import '../components/loading_indicator.dart';

typedef FetchTrend = Future<Map<String, dynamic>> Function(String range);

class DashboardChart extends StatefulWidget {
  final FetchTrend? fetchTrend;
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

  String _formatLabelForWidth(String label, bool compact) {
    if (!compact) return label;

    if (_range == 'month') {
      final parts = label.split(RegExp(r'[-/]'));
      if (parts.isNotEmpty) {
        final monthPart = parts.last;
        final monthNumber = int.tryParse(monthPart);
        if (monthNumber != null) {
          return '$monthNumber月';
        }
        if (monthPart.length >= 2 && int.tryParse(monthPart.substring(monthPart.length - 2)) != null) {
          final parsed = int.parse(monthPart.substring(monthPart.length - 2));
          return '$parsed月';
        }
        return monthPart;
      }
    }

    if (_range != '7d') {
      final match = RegExp(r'(\d{1,2})$').firstMatch(label);
      if (match != null) {
        return match.group(1)!;
      }
    }

    return label;
  }

  Future<void> _loadTrend() async {
    if (widget.fetchTrend == null) return;
    
    Timer? loadingTimer = Timer(const Duration(milliseconds: 150), () {
      if (mounted && _loading) {
        setState(() => _loading = true);
      }
    });
    
    try {
      final oldTotal = _counts.isNotEmpty ? _counts.fold<int>(0, (a, b) => a + b) : 0;
      final data = await widget.fetchTrend!.call(_range);
      loadingTimer.cancel();
      
      if (!mounted) return;
      final labels = (data['labels'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
      final counts = (data['counts'] as List<dynamic>?)?.map((e) => (e as num).toInt()).toList() ?? [];
      setState(() {
        _prevTotalForRange = oldTotal.toDouble();
        _labels = labels;
        _counts = counts;
        _loading = false;
      });
    } catch (_) {
      loadingTimer.cancel();
      if (mounted) setState(() => _loading = false);
    }
  }

  void _setRange(String r) {
    if (_range == r) return;
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
    
    final displayLabels = hasData
        ? _labels.map((s) {
            if (_range == '7d') {
              try {
                final dt = DateTime.parse(s);
                const names = ['周一','周二','周三','周四','周五','周六','周日'];
                final idx = (dt.weekday - 1).clamp(0, 6);
                return names[idx];
              } catch (_) {}
            } else if (_range == 'month') {
              if (s.length >= 7 && s.startsWith('20')) {
                return s.substring(2, 7);
              }
            }
            return s;
          }).toList()
        : const <String>[];

    final int? totalForRange = hasData ? _counts.fold<int>(0, (a, b) => a + b) : null;
    final String totalLabel = _range == 'month' ? '当月合计' : '近7日合计';

    return LayoutBuilder(
      builder: (context, constraints) {
        final screenH = MediaQuery.of(context).size.height;
        final isCompact = constraints.maxWidth < 800;
        final target = (screenH * (isCompact ? 0.28 : 0.36));
        final chartHeight = target.clamp(220.0, 420.0);
        final barMaxHeight = chartHeight - 50;

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
                    ? const Center(child: LoadingIndicator())
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

    final itemCount = labels.length;
    final availableWidth = MediaQuery.of(context).size.width - 80;
    final maxItemWidth = (availableWidth / itemCount).clamp(20.0, 60.0);
    final barWidth = (maxItemWidth * 0.4).clamp(12.0, 24.0);
    final labelWidth = maxItemWidth;

    final items = <Widget>[];
    final compactLabels = labelWidth < 48;
    for (int i = 0; i < labels.length; i++) {
      final ratio = maxCount > 0 ? (counts[i] / maxCount) : 0.0;
      items.add(Expanded(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
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
                _formatLabelForWidth(labels[i], compactLabels),
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
    final theme = Theme.of(context);
    final onSurface60 = theme.colorScheme.onSurface.withValues(alpha: 0.6);
    final barColor = theme.colorScheme.primary.withValues(alpha: 0.4);
    final availableWidth = MediaQuery.of(context).size.width - 80;

    List<_PlaceholderDatum> data;
    if (_range == 'month') {
      data = const [
        _PlaceholderDatum(label: '第1周', ratio: 0.4),
        _PlaceholderDatum(label: '第2周', ratio: 0.7),
        _PlaceholderDatum(label: '第3周', ratio: 0.6),
        _PlaceholderDatum(label: '第4周', ratio: 0.5),
      ];
    } else {
      data = const [
        _PlaceholderDatum(label: '周一', ratio: 0.4),
        _PlaceholderDatum(label: '周二', ratio: 0.7),
        _PlaceholderDatum(label: '周三', ratio: 0.6),
        _PlaceholderDatum(label: '周四', ratio: 0.5),
        _PlaceholderDatum(label: '周五', ratio: 0.9),
        _PlaceholderDatum(label: '周六', ratio: 0.4),
        _PlaceholderDatum(label: '周日', ratio: 0.6),
      ];
    }

    final itemCount = data.length;
    final maxItemWidth = (availableWidth / itemCount).clamp(20.0, 60.0);
    final barWidth = (maxItemWidth * 0.4).clamp(12.0, 24.0);
    final labelWidth = maxItemWidth;
    final compactLabels = labelWidth < 48;

    final items = data.map((d) {
      return Expanded(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            const Text(
              '--',
              style: TextStyle(color: Colors.transparent, fontSize: 10, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Container(
              width: barWidth,
              height: barMaxHeight * d.ratio,
              decoration: BoxDecoration(color: barColor, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: labelWidth,
              child: Text(
                compactLabels ? d.compactLabel : d.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(color: onSurface60, fontSize: 10),
              ),
            ),
          ],
        ),
      );
    }).toList();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: items,
    );
  }
}

class _PlaceholderDatum {
  final String label;
  final double ratio;

  const _PlaceholderDatum({required this.label, required this.ratio});

  String get compactLabel {
    final match = RegExp(r'([\u4e00-\u9fa5]+)').firstMatch(label);
    return match?.group(1) ?? label;
  }
}
