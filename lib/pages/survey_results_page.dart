import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../widgets/top_safe_spacer.dart';
import 'package:flutter/material.dart' as vmath;
import 'package:forui/forui.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import '../models/survey.dart';
import '../models/survey_result.dart';
import '../models/question.dart';
import '../services/api_service.dart';
import '../main.dart' show isDesktop;
import '../utils/date_format.dart';
import 'dart:ui' as ui;
import '../widgets/frosted_glass_background.dart';
import '../services/config.dart';

class SurveyResultsPage extends StatefulWidget {
  final String token;
  final Survey survey;

  const SurveyResultsPage({
    super.key,
    required this.token,
    required this.survey,
  });

  @override
  State<SurveyResultsPage> createState() => _SurveyResultsPageState();
}

class _SlideGradientTransform extends GradientTransform {
  const _SlideGradientTransform({required this.slide});
  final double slide;
  @override
  vmath.Matrix4 transform(Rect bounds, {TextDirection? textDirection}) {
    final dx = bounds.width * slide;
    return vmath.Matrix4.translationValues(dx, 0.0, 0.0);
  }
}

class _SurveyResultsPageState extends State<SurveyResultsPage> with SingleTickerProviderStateMixin {
  List<SurveyResult> _results = [];
  List<Question> _questions = [];
  bool _isLoading = true;
  String? _errorMessage;
  Set<int> _selectedResults = {};
  bool _isSelectionMode = false;
  bool _usePieChart = false;
  late final ApiService _apiService;
  String? _desktopBackground;
  String? _mobileBackground;
  int? _hoveredResultId;
  final ScrollController _scrollController = ScrollController();
  Widget? _statisticsCache;
  String _statisticsCacheKey = '';
  late final AnimationController _rainbowCtl;

  String _computeStatsKey() {

    final lenR = _results.length;
    final lenQ = _questions.length;
    final firstId = lenR > 0 ? _results.first.id : -1;
    final lastId = lenR > 0 ? _results.last.id : -1;
    return '$lenR-$lenQ-$firstId-$lastId';
  }

  Widget _buildPieChart(Map<int, int> stats, List<QuestionOption> options, int total, {String? title}) {
    if (stats.isEmpty || total == 0) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text('暂无数据'),
        ),
      );
    }

    final List<Color> pieColors = [
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.red,
      Colors.teal,
      Colors.pink,
      Colors.amber,
      Colors.cyan,
      Colors.indigo,
    ];

    stats.entries.map((entry) {
      final optionIndex = entry.key;
      final count = entry.value;
      final percentage = (count / total * 100);
      final color = pieColors[optionIndex % pieColors.length];
      
      return PieChartSectionData(
        value: count.toDouble(),
        title: '${percentage.toStringAsFixed(1)}%',
        color: color,
        radius: 100,
        titleStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
        badgeWidget: null,
        titlePositionPercentageOffset: 0.6,
      );
    }).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final double maxW = constraints.maxWidth;

        final double hPad = (maxW * 0.04).clamp(8.0, 16.0);
        return Padding(
          padding: EdgeInsets.fromLTRB(hPad, 12, hPad, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            if (title != null) ...[
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            Builder(
              builder: (context) {
                final availableWidth = MediaQuery.sizeOf(context).width - hPad * 2;
                final pieSize = (availableWidth * 0.9).clamp(200.0, 280.0);
                final centerRadius = pieSize / 280 * 40; 
                final bool placeLegendUnderTitle = availableWidth >= 560; 

                final entries = stats.entries.toList();
                int? touchedIndex;
                Offset? touchPos;  
                final Widget pie = StatefulBuilder(
                  builder: (context, setInnerState) {
                    return SizedBox(
                      height: pieSize,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Center(
                            child: OverflowBox(
                              minWidth: 0,
                              minHeight: 0,
                              maxWidth: double.infinity,
                              maxHeight: double.infinity,
                              alignment: Alignment.center,
                              child: SizedBox(
                                width: pieSize,
                                height: pieSize,
                                child: PieChart(
                                  PieChartData(
                                    sectionsSpace: 6,
                                    centerSpaceRadius: centerRadius,
                                    borderData: FlBorderData(show: false),
                                    sections: List.generate(entries.length, (i) {
                                      final optionIndex = entries[i].key;
                                      final count = entries[i].value;
                                      final percentage = (count / total * 100);
                                      final color = pieColors[optionIndex % pieColors.length];
                                      final isTouched = touchedIndex == i;
                                      return PieChartSectionData(
                                        value: count.toDouble(),
                                        title: '${percentage.toStringAsFixed(1)}%',
                                        color: color,
                                        radius: isTouched ? 118 : 100,
                                        titleStyle: TextStyle(
                                          fontSize: isTouched ? 13 : 12,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                        titlePositionPercentageOffset: isTouched ? 0.55 : 0.60,
                                      );
                                    }),
                                    pieTouchData: PieTouchData(
                                      touchCallback: (FlTouchEvent event, pieTouchResponse) {
                                        setInnerState(() {
                                          // 无兴趣或无命中 -> 清空
                                          if (!event.isInterestedForInteractions ||
                                              pieTouchResponse == null ||
                                              pieTouchResponse.touchedSection == null) {
                                            touchedIndex = null;
                                            touchPos = null;
                                            return;
                                          }
                                          final idx = pieTouchResponse.touchedSection!.touchedSectionIndex;
                                          if (idx < 0 || idx >= entries.length) {
                                            touchedIndex = null;
                                            touchPos = null;
                                          } else {
                                            touchedIndex = idx;
                                            touchPos = event.localPosition;
                                          }
                                        });
                                      },
                                    ),
                                  ),
                                  duration: const Duration(milliseconds: 220),
                                  curve: Curves.easeOutCubic,
                                ),
                              ),
                            ),
                          ),
                          if (touchedIndex != null && touchedIndex! >= 0 && touchedIndex! < entries.length && touchPos != null) ...[
                            // Tooltip 气泡，位置基于触点，做边界夹取
                            Positioned(
                              left: (touchPos!.dx - 80).clamp(0.0, (pieSize - 160) > 0 ? (pieSize - 160) : 0.0),
                              top: (touchPos!.dy - 44).clamp(0.0, (pieSize - 64) > 0 ? (pieSize - 64) : 0.0),
                              child: Material(
                                color: Colors.transparent,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.black87,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Builder(builder: (_) {
                                    final e = entries[touchedIndex!];
                                    final optionIndex = e.key;
                                    final count = e.value;
                                    final percentage = (count / total * 100).toStringAsFixed(1);
                                    final optionText = optionIndex < options.length
                                        ? options[optionIndex].text
                                        : '选项 ${optionIndex + 1}';
                                    return Text(
                                      '$optionText  $count次  ($percentage%)',
                                      style: const TextStyle(color: Colors.white, fontSize: 12),
                                    );
                                  }),
                                ),
                              ),
                            ),
                          ]
                        ],
                      ),
                    );
                  },
                );

                final Widget legendTop = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: stats.entries.map((entry) {
                    final optionIndex = entry.key;
                    final count = entry.value;
                    final optionText = optionIndex < options.length ? options[optionIndex].text : '选项 ${optionIndex + 1}';
                    final percentage = (count / total * 100).toStringAsFixed(1);
                    final color = pieColors[optionIndex % pieColors.length];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '$optionText: $count次 ($percentage%)',
                              style: const TextStyle(fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                );

                // 底部标识：按 1/2/3 列自适应换行，保证空间不足时一定换行
                final int cols = availableWidth >= 720 ? 3 : (availableWidth >= 480 ? 2 : 1);
                final double gap = 12.0;
                final double maxItemWidth = cols == 1
                    ? availableWidth
                    : (availableWidth - gap * (cols - 1)) / cols;
                final Widget legendBottom = Wrap(
                  spacing: gap,
                  runSpacing: 6,
                  alignment: WrapAlignment.center,
                  children: stats.entries.map((entry) {
                    final optionIndex = entry.key;
                    final count = entry.value;
                    final optionText = optionIndex < options.length ? options[optionIndex].text : '选项 ${optionIndex + 1}';
                    final percentage = (count / total * 100).toStringAsFixed(1);
                    final color = pieColors[optionIndex % pieColors.length];
                    return SizedBox(
                      width: maxItemWidth,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: color,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '$optionText: $count次 ($percentage%)',
                                style: const TextStyle(fontSize: 11),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                );

                if (placeLegendUnderTitle) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 2,
                        child: legendTop,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 3,
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: pie,
                        ),
                      ),
                    ],
                  );
                } else {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      pie,
                      const SizedBox(height: 12),
                      legendBottom,
                    ],
                  );
                }
              },
            ),
          ],
        ),
      );
      },
    );
  }

  Widget _buildPercentBar(double ratio) {
    final clamped = ratio.clamp(0.0, 1.0);
    const double h = 18.0;
    final bg = Colors.grey.withValues(alpha: 0.2);
    final Color fg = Theme.of(context).colorScheme.primary.withValues(alpha: 0.70);

    if (clamped >= 0.999) {
      const rainbow = [
        Color(0xFFFF0040),
        Color(0xFFFF8000),
        Color(0xFFFFFF00),
        Color(0xFF80FF00),
        Color(0xFF00FFFF),
        Color(0xFF0080FF),
        Color(0xFF8000FF),
        Color(0xFFFF00FF),
        Color(0xFFFF0040),
      ];

      return Opacity(
        opacity: 0.35,
        child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: AnimatedBuilder(
          animation: _rainbowCtl,
          builder: (context, _) {

            return Stack(
              children: [
                Container(
                  height: h,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: rainbow,
                      tileMode: TileMode.repeated,
                      transform: _SlideGradientTransform(slide: _rainbowCtl.value),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Opacity(
                    opacity: 0.55,
                    child: ImageFiltered(
                      imageFilter: ui.ImageFilter.blur(sigmaX: 10.0, sigmaY: 8.0),
                      child: Container(
                        height: h,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: rainbow,
                            tileMode: TileMode.repeated,
                            transform: _SlideGradientTransform(slide: _rainbowCtl.value),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
      );
    }

    return Stack(
      children: [
        Container(
          height: h,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        FractionallySizedBox(
          widthFactor: clamped,
          child: Container(
            height: h,
            decoration: BoxDecoration(
              color: fg,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ),
      ],
    );
  }

  
  Widget _buildRatingRow(Question q, String selectChoices) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    const double starIconSize = 38.0;

    double min = q.ratingMin;
    double max = q.ratingMax;
    int stars = q.ratingStars;
    bool allowHalf = q.ratingAllowHalf;
    final String style = q.ratingStyle; // star | crumb
    final String iconType = q.ratingIcon.isNotEmpty ? q.ratingIcon : 'star';
    final String minLabel = q.ratingMinLabel.isNotEmpty ? q.ratingMinLabel : '最小值';
    final String midLabel = q.ratingMidLabel.isNotEmpty ? q.ratingMidLabel : '一般';
    final String maxLabel = q.ratingMaxLabel.isNotEmpty ? q.ratingMaxLabel : '最大值';
    final labelsMap = q.ratingLabels; // Map<double,String>

    if (selectChoices.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(left: 16, top: 4),
        child: Text(
          '未评分',
          style: TextStyle(
            fontSize: 14,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
      );
    }

    double v;
    final parsed = double.tryParse(selectChoices);
    if (parsed != null) {
      // 判断是否已经是 1..stars 范围
      if (parsed >= 0.5 && parsed <= stars + 0.001) {
        v = parsed;
      } else {
        // 旧数据：按 min..max 映射到 1..stars
        final clamped = parsed.clamp(min, max);
        final ratio = (max > min) ? ((clamped - min) / (max - min)).clamp(0.0, 1.0) : 0.0;
        v = 1.0 + ratio * (stars - 1);
      }
    } else {
      return Padding(
        padding: const EdgeInsets.only(left: 16, top: 4),
        child: Text(
          '未评分',
          style: TextStyle(
            fontSize: 14,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
      );
    }

    if (allowHalf) {
      v = v.clamp(0.5, stars.toDouble());
    } else {
      v = v.clamp(1.0, stars.toDouble());
    }
    final int filledFull = v.floor();
    final bool hasHalf = allowHalf && (v - filledFull).abs() >= 0.5 && filledFull < stars;

    final Color activeColor = theme.colorScheme.primary;
    // 与 PublicSurveyPage 保持一致：未激活态使用统一透明度
    final Color inactiveColor = theme.colorScheme.onSurface.withValues(alpha: 0.35);

    Widget buildFilled(double size) {
      switch (iconType) {
        case 'favorite':
          return Icon(Icons.favorite, size: size, color: activeColor);
        case 'circle':
          return Icon(Icons.circle, size: size, color: activeColor);
        case 'heart_broken':
          return Icon(Icons.heart_broken, size: size, color: activeColor);
        case 'star':
        default:
          return Icon(Icons.star, size: size, color: activeColor);
      }
    }

    Widget buildOutline(double size) {
      switch (iconType) {
        case 'favorite':
          return Icon(Icons.favorite_border, size: size, color: inactiveColor);
        case 'circle':
          return Icon(Icons.circle_outlined, size: size, color: inactiveColor);
        case 'heart_broken':
          // 没有 outline 版本，使用低透明度的同一图标模拟
          return Icon(Icons.heart_broken, size: size, color: inactiveColor);
        case 'star':
        default:
          return Icon(Icons.star_border, size: size, color: inactiveColor);
      }
    }

    Widget buildHalf(double size) {
      if (iconType == 'star') {
        return Icon(Icons.star_half, size: size, color: activeColor);
      }
      // 其他图标无半态：使用 ShaderMask 将填充图标的左半边显示，右半边透明
      return Stack(
        alignment: Alignment.center,
        children: [
          buildOutline(size),
          SizedBox(
            width: size,
            height: size,
            child: ShaderMask(
              shaderCallback: (Rect bounds) {
                return LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    activeColor,
                    activeColor,
                    Colors.transparent,
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.5, 0.5, 1.0],
                ).createShader(bounds);
              },
              blendMode: BlendMode.srcIn,
              child: buildFilled(size),
            ),
          ),
        ],
      );
    }

    List<Widget> starRow = List.generate(stars, (i) {
      final idx = i + 1;
      Widget starWidget;
      if (idx <= filledFull) {
        starWidget = buildFilled(starIconSize);
      } else if (idx == filledFull + 1 && hasHalf) {
        starWidget = buildHalf(starIconSize);
      } else {
        starWidget = buildOutline(starIconSize);
      }
      
      return SizedBox(
        width: starIconSize,
        height: starIconSize,
        child: Center(child: starWidget),
      );
    });

    Widget crumbRow() {
      const double width = 24.0;
      const double height = 12.0;
      final Color base = theme.colorScheme.onSurface.withValues(alpha: 0.25);
      final Color active = theme.colorScheme.primary;
      
      return Row(
        children: List.generate(stars, (i) {
          final seg = i + 1;
          final full = seg <= filledFull;
          final half = !full && (seg == filledFull + 1) && hasHalf;
          
          return SizedBox(
            width: width,
            height: 20,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Container(
                  width: width,
                  height: height,
                  decoration: BoxDecoration(
                    color: base,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                if (full || half)
                  ClipRect(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      widthFactor: full ? 1.0 : 0.5,
                      child: Container(
                        width: width,
                        height: height,
                        decoration: BoxDecoration(
                          color: active,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        }),
      );
    }

    final bool useCrumb = (style == 'crumb');
    final double barUnitWidth = useCrumb ? 24.0 : starIconSize;
    final double barWidth = barUnitWidth * stars;

    final double key = (v * 2).round() / 2.0;
    final String? mappedLabel = labelsMap[key];
    final String currentLabel = mappedLabel ?? (key % 1 == 0 ? '${key.toInt()} 星' : '${key.toStringAsFixed(1)} 星');

    return Padding(
      padding: const EdgeInsets.only(left: 12, top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ...(useCrumb ? [crumbRow()] : starRow),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  currentLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
          if (useCrumb) ...[
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ...List.generate(stars, (i) {
                  final int segIndex = i + 1;
                  final double labelKey = segIndex.toDouble();
                  final String text = labelsMap[labelKey] ?? segIndex.toString();
                  return SizedBox(
                    width: 24,
                    child: Center(
                      child: Text(
                        text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12, 
                          color: isDark ? Colors.white70 : Colors.black54
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ],
          const SizedBox(height: 8),
          SizedBox(
            width: barWidth,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  minLabel, 
                  // 与 PublicSurveyPage 颜色保持一致
                  style: TextStyle(color: isDark ? Colors.white : Colors.black87)
                ),
                Text(
                  midLabel, 
                  style: TextStyle(
                    // 与 PublicSurveyPage 颜色保持一致
                    color: isDark ? Colors.white : Colors.black87, 
                    fontWeight: FontWeight.w500
                  )
                ),
                Text(
                  maxLabel, 
                  // 与 PublicSurveyPage 颜色保持一致
                  style: TextStyle(color: isDark ? Colors.white : Colors.black87)
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _apiService = ApiService(authToken: widget.token);
    _loadBackground();
    _loadData();
    _rainbowCtl = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();
  }

  Widget _getStatisticsCard() {
    if (_results.isEmpty) return const SizedBox.shrink();
    final key = _computeStatsKey();
    if (_statisticsCacheKey == key && _statisticsCache != null) {
      return _statisticsCache!;
    }
    final card = _buildStatistics();
    _statisticsCacheKey = key;
    _statisticsCache = card;
    return card;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _rainbowCtl.dispose();
    super.dispose();
  }

  Widget _buildGlassCard({required Widget child, bool highlighted = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Material(
        color: Colors.transparent,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            decoration: BoxDecoration(
              color: highlighted
                  ? Colors.white.withAlpha(68)
                  : Colors.white.withAlpha(51),
              border: Border.all(
                color: highlighted
                    ? Colors.white.withAlpha(102)
                    : Colors.white.withAlpha(51),
                width: 0.8,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: child,
          ),
        ),
      ),
    );
  }

  Future<void> _loadData() async {
    Timer? loadingTimer = Timer(const Duration(milliseconds: 150), () {
      if (mounted && _isLoading) {
        setState(() {
          _isLoading = true;
          _errorMessage = null;
        });
      }
    });

    try {
      final apiService = _apiService;
      final futures = await Future.wait([
        apiService.getSurveyResults(widget.survey.id),
        apiService.getSurveyQuestions(widget.survey.id),
      ]);

      final resultsData = futures[0];
      final questionsData = futures[1];

      final List<SurveyResult> results = resultsData is List<SurveyResult> 
          ? resultsData 
          : <SurveyResult>[];
      
      final List<Question> questions = questionsData is List<Question>
          ? questionsData
          : <Question>[];

      loadingTimer.cancel();
      if (!mounted) return;
      
      setState(() {
        _results = results;
        _questions = questions;
        _isLoading = false;
        _selectedResults.clear();
        _isSelectionMode = false;
        _statisticsCache = null;
        _statisticsCacheKey = '';
      });
    } catch (e) {
      setState(() {
        if (e.toString().contains('Null') && e.toString().contains('List')) {
          _errorMessage = '暂无答案提交';
          _results = [];
          _questions = [];
        } else {
          _errorMessage = '加载数据失败: $e';
        }
        _isLoading = false;
      });
    }
  }

  // 加载问卷壁纸（桌面/移动）
  Future<void> _loadBackground() async {
    try {
      final data = await _apiService.getSurveyBackground(widget.survey.id);
      if (!mounted) return;
      setState(() {
        _desktopBackground = data['desktopBackground'] as String?;
        _mobileBackground = data['mobileBackground'] as String?;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _desktopBackground = null;
        _mobileBackground = null;
      });
    }
  }

  Future<void> _deleteAnswer(int answerId) async {
    try {
      final apiService = ApiService(authToken: widget.token);
      await apiService.deleteAnswer(answerId);
      
      if (mounted) {
        showFToast(
          context: context,
          title: const Text('删除成功'),
        );
      }
      
      _loadData(); // 重新加载数据
    } catch (e) {
      if (mounted) {
        showFToast(
          context: context,
          title: Text('删除失败: $e'),
        );
      }
    }
  }

  Future<void> _batchDeleteAnswers() async {
    if (_selectedResults.isEmpty) return;
    
    try {
      final apiService = ApiService(authToken: widget.token);
      await apiService.batchDeleteAnswers(_selectedResults.toList());
      
      if (mounted) {
        showFToast(
          context: context,
          title: Text('成功删除 ${_selectedResults.length} 条记录'),
        );
      }
      
      _loadData(); // 重新加载数据
    } catch (e) {
      if (mounted) {
        showFToast(
          context: context,
          title: Text('批量删除失败: $e'),
        );
      }
    }
  }

  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      if (!_isSelectionMode) {
        _selectedResults.clear();
      }
    });
  }

  void _toggleSelection(int answerId) {
    setState(() {
      if (_selectedResults.contains(answerId)) {
        _selectedResults.remove(answerId);
      } else {
        _selectedResults.add(answerId);
      }
    });
  }

  void _selectAll() {
    setState(() {
      if (_selectedResults.length == _results.length) {
        _selectedResults.clear();
      } else {
        _selectedResults = _results.map((r) => r.id).toSet();
      }
    });
  }

  Future<void> _showDeleteConfirmDialog(int answerId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => FDialog(
        direction: Axis.horizontal,
        title: const Text('确认删除'),
        body: const Text('确定要删除这条作答记录吗？此操作不可撤销。'),
        actions: [
          FButton(
            style: FButtonStyle.outline,
            onPress: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FButton(
            style: FButtonStyle.destructive,
            onPress: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      await _deleteAnswer(answerId);
    }
  }

  Future<void> _showBatchDeleteConfirmDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => FDialog(
        direction: Axis.horizontal,
        title: const Text('确认批量删除'),
        body: Text('确定要删除选中的 ${_selectedResults.length} 条作答记录吗？此操作不可撤销。'),
        actions: [
          FButton(
            style: FButtonStyle.outline,
            onPress: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FButton(
            style: FButtonStyle.destructive,
            onPress: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      await _batchDeleteAnswers();
    }
  }

  String _getQuestionTitle(int questionId) {
    final question = _questions.firstWhere(
      (q) => q.id == questionId,
      orElse: () => Question(
        id: questionId,
        title: '未知问题',
        type: QuestionType.singleChoice,
        options: [],
        required: false,
        order: 0,
      ),
    );
    return question.title;
  }

  String _getOptionText(int questionId, int optionIndex) {
    final question = _questions.firstWhere(
      (q) => q.id == questionId,
      orElse: () => Question(
        id: questionId,
        title: '未知问题',
        type: QuestionType.singleChoice,
        options: [],
        required: false,
        order: 0,
      ),
    );
    
    if (optionIndex >= 0 && optionIndex < question.options.length) {
      return question.options[optionIndex].text;
    }
    return '选项 ${optionIndex + 1}';
  }

  Widget _buildResultCard(SurveyResult result) {
    final isSelected = _selectedResults.contains(result.id);

    final isHovered = _hoveredResultId == result.id && isDesktop;

    return MouseRegion(
      onEnter: (_) => setState(() => _hoveredResultId = result.id),
      onExit: (_) => setState(() => _hoveredResultId = null),
      cursor: _isSelectionMode ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: RepaintBoundary(
        child: _buildGlassCard(
          highlighted: isHovered || isSelected,
          child: InkWell(
            onTap: _isSelectionMode ? () => _toggleSelection(result.id) : null,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_isSelectionMode)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Checkbox(
                            value: isSelected,
                            onChanged: (_) => _toggleSelection(result.id),
                          ),
                        ),
                      Expanded(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              '作答者: ${result.userAccount}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              DateFormatUtils.formatIsoString(result.createTime),
                              style: const TextStyle(
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!_isSelectionMode)
                        FButton(
                          style: FButtonStyle.ghost,
                          onPress: () => _showDeleteConfirmDialog(result.id),
                          child: Icon(
                            Icons.delete,
                            size: 18,
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                  ],
                ),
                const SizedBox(height: 16),
                ...result.questions.map((answer) {
                  final questionTitle = _getQuestionTitle(answer.questionId);
                  final question = _questions.firstWhere(
                    (q) => q.id == answer.questionId,
                    orElse: () => Question(
                      id: answer.questionId,
                      title: questionTitle,
                      type: QuestionType.singleChoice,
                      options: const [],
                      required: false,
                      order: 0,
                    ),
                  );
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          questionTitle,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        if (question.type == QuestionType.slider)
                          _buildRatingRow(question, answer.selectChoices)
                        else if (answer.selectedOptions.isNotEmpty)
                          ...answer.selectedOptions.map((optionIndex) {
                            final optionText = _getOptionText(answer.questionId, optionIndex);
                            return Padding(
                              padding: const EdgeInsets.only(left: 16, top: 2),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.check_circle,
                                    size: 16,
                                    color: Colors.green[600],
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      optionText,
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          })
                        else
                          Padding(
                            padding: const EdgeInsets.only(left: 16),
                            child: Text(
                              '未作答',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[600],
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }

  Widget _buildStatistics() {
    if (_results.isEmpty) return const SizedBox.shrink();

    final totalResponses = _results.length;
    final responsesByQuestion = <int, Map<int, int>>{};

    for (final result in _results) {
      for (final answer in result.questions) {
        responsesByQuestion[answer.questionId] ??= {};
        for (final option in answer.selectedOptions) {
          responsesByQuestion[answer.questionId]![option] =
              (responsesByQuestion[answer.questionId]![option] ?? 0) + 1;
        }
      }
    }

    return _buildGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '统计概览',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: FSwitch(
                    label: const Text('饼图'),
                    value: _usePieChart,
                    onChange: (value) {
                      setState(() {
                        _usePieChart = value;
                        _statisticsCache = null; // 清除缓存
                      });
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              '总回答数: $totalResponses',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            if (_usePieChart)
              LayoutBuilder(builder: (context, constraints) {
                final w = constraints.maxWidth;
                final cols = w >= 750 ? 2 : 1; // 屏幕够宽显示2列
                const gap = 16.0;
                final pieCards = <Widget>[];
                
                for (final question in _questions) {
                  if (question.type != QuestionType.slider) {
                    final questionStats = responsesByQuestion[question.id] ?? {};
                    pieCards.add(SizedBox(
                      width: cols > 1 ? (w - gap) / 2 : w,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: _buildPieChart(questionStats, question.options, totalResponses, title: question.title),
                      ),
                    ));
                  } else {
                    final int stars = question.ratingStars;
                    final bool allowHalf = question.ratingAllowHalf;
                    final double min = question.ratingMin;
                    final double max = question.ratingMax;
                    final Map<double, int> bins = {};
                    final step = allowHalf ? 0.5 : 1.0;
                    for (double v = 1.0; v <= stars; v += step) {
                      bins[double.parse(v.toStringAsFixed(1))] = 0;
                    }
                    int answered = 0;
                    for (final r in _results) {
                      final a = r.questions.firstWhere(
                        (d) => d.questionId == question.id,
                        orElse: () => AnswerDetail(
                          id: 0,
                          answerId: r.id,
                          questionId: question.id,
                          selectedOptions: const [],
                          selectChoices: '',
                        ),
                      );
                      if (a.selectChoices.isEmpty) continue;
                      final parsed = double.tryParse(a.selectChoices);
                      if (parsed == null) continue;
                      answered++;
                      double val;
                      if (parsed >= 0.5 && parsed <= stars + 0.001) {
                        val = parsed;
                      } else {
                        final clamped = parsed.clamp(min, max);
                        final ratio = (max > min) ? ((clamped - min) / (max - min)).clamp(0.0, 1.0) : 0.0;
                        val = 1.0 + ratio * (stars - 1);
                      }
                      final double rounded = allowHalf ? ( (val * 2).round() / 2.0 ) : val.roundToDouble();
                      final key = double.parse(rounded.toStringAsFixed(1));
                      bins[key] = (bins[key] ?? 0) + 1;
                    }
                    final entries = bins.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
                    if (answered > 0) {
                      final mappedStats = <int, int>{};
                      final labels = <QuestionOption>[];
                      for (int i = 0; i < entries.length; i++) {
                        final e = entries[i];
                        mappedStats[i] = e.value;
                        final label = (e.key % 1 == 0)
                            ? '${e.key.toInt()} 星'
                            : '${e.key.toStringAsFixed(1)} 星';
                        labels.add(QuestionOption(id: i, text: label));
                      }
                      pieCards.add(SizedBox(
                        width: cols > 1 ? (w - gap) / 2 : w,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: _buildPieChart(mappedStats, labels, answered, title: question.title),
                        ),
                      ));
                    }
                  }
                }
                return Wrap(spacing: gap, runSpacing: 0, children: pieCards);
              })
            else
            ..._questions.map((question) {
              if (question.type != QuestionType.slider) {
                final questionStats = responsesByQuestion[question.id] ?? {};
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        question.title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      LayoutBuilder(builder: (context, constraints) {
                        final w = constraints.maxWidth;
                        final cols = w >= 1200 ? 3 : (w >= 800 ? 2 : 1);
                        const gap = 12.0;
                        final itemW = cols > 1 ? (w - gap * (cols - 1)) / cols : w;
                        final tiles = question.options.asMap().entries.map((entry) {
                        final optionIndex = entry.key;
                        final optionText = entry.value.text;
                        final count = questionStats[optionIndex] ?? 0;
                        final percentage = totalResponses > 0
                            ? (count / totalResponses * 100).toStringAsFixed(1)
                            : '0.0';
                          final ratio = totalResponses > 0 ? (count / totalResponses) : 0.0;
                          return SizedBox(
                            width: itemW,
                            child: Padding(
                              padding: const EdgeInsets.only(left: 16, bottom: 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(child: _buildPercentBar(ratio)),
                                      const SizedBox(width: 10),
                                      SizedBox(
                                        width: 110,
                                        child: Text(
                                          '$count 次 ($percentage%)',
                                          style: const TextStyle(fontSize: 12),
                                          textAlign: TextAlign.right,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    optionText,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.80),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList();
                        return Wrap(spacing: gap, runSpacing: 8, children: tiles);
                      }),
                    ],
                  ),
                );
              }

              final int stars = question.ratingStars;
              final bool allowHalf = question.ratingAllowHalf;
              final double min = question.ratingMin;
              final double max = question.ratingMax;

              // 收集该题的所有回答（从 _results 的 answer.selectChoices）
              final Map<double, int> bins = {};
              // 初始化 bin（按 0.5 或 1 颗粒度）
              final step = allowHalf ? 0.5 : 1.0;
              for (double v = 1.0; v <= stars; v += step) {
                bins[double.parse(v.toStringAsFixed(1))] = 0;
              }
              int answered = 0;
              for (final r in _results) {
                final a = r.questions.firstWhere(
                  (d) => d.questionId == question.id,
                  orElse: () => AnswerDetail(
                    id: 0,
                    answerId: r.id,
                    questionId: question.id,
                    selectedOptions: const [],
                    selectChoices: '',
                  ),
                );
                if (a.selectChoices.isEmpty) continue;
                final parsed = double.tryParse(a.selectChoices);
                if (parsed == null) continue;
                answered++;
                // 判断是新范畴(1..stars)还是旧范畴(min..max)
                double val;
                if (parsed >= 0.5 && parsed <= stars + 0.001) {
                  val = parsed;
                } else {
                  final clamped = parsed.clamp(min, max);
                  final ratio = (max > min) ? ((clamped - min) / (max - min)).clamp(0.0, 1.0) : 0.0;
                  val = 1.0 + ratio * (stars - 1);
                }
                // 归一化到 bin
                final double rounded = allowHalf
                    ? ( (val * 2).round() / 2.0 )
                    : val.roundToDouble();
                final key = double.parse(rounded.toStringAsFixed(1));
                bins[key] = (bins[key] ?? 0) + 1;
              }

              final entries = bins.entries.toList()
                ..sort((a, b) => a.key.compareTo(b.key));

              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!_usePieChart) ...[
                      Text(
                        question.title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                      if (answered == 0)
                        Padding(
                          padding: const EdgeInsets.only(left: 16),
                          child: Text(
                          '暂无作答',
                          style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.70),
                          ),
                          ),
                        )
                    else if (_usePieChart) ...[
                      Builder(builder: (_) {
                        final mappedStats = <int, int>{};
                        final labels = <QuestionOption>[];
                        for (int i = 0; i < entries.length; i++) {
                          final e = entries[i];
                          mappedStats[i] = e.value;
                          final label = (e.key % 1 == 0)
                              ? '${e.key.toInt()} 星'
                              : '${e.key.toStringAsFixed(1)} 星';
                          labels.add(QuestionOption(id: i, text: label));
                        }
                        return Padding(
                          padding: const EdgeInsets.only(left: 8.0, right: 8.0),
                          child: _buildPieChart(mappedStats, labels, answered, title: question.title),
                        );
                      })
                    ] else LayoutBuilder(builder: (context, constraints) {
                      final w = constraints.maxWidth;
                      final cols = w >= 1200 ? 3 : (w >= 800 ? 2 : 1);
                      const gap = 12.0;
                      final itemW = cols > 1 ? (w - gap * (cols - 1)) / cols : w;
                      return Wrap(
                        spacing: gap,
                        runSpacing: 8,
                        children: entries.map((e) {
                          final pct = answered > 0 ? (e.value / answered * 100).toStringAsFixed(1) : '0.0';
                          final ratio = answered > 0 ? (e.value / answered) : 0.0;
                          final label = (e.key % 1 == 0)
                              ? '${e.key.toInt()} 星'
                              : '${e.key.toStringAsFixed(1)} 星';
                          return SizedBox(
                            width: itemW,
                            child: Padding(
                              padding: const EdgeInsets.only(left: 16, bottom: 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(child: _buildPercentBar(ratio)),
                                      const SizedBox(width: 10),
                                      SizedBox(
                                        width: 110,
                                        child: Text(
                                          '${e.value} 次 ($pct%)',
                                          style: const TextStyle(fontSize: 12),
                                          textAlign: TextAlign.right,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    label,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.80),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      );
                    }),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth > 800;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: (_desktopBackground != null && _desktopBackground!.isNotEmpty) ||
                   (_mobileBackground != null && _mobileBackground!.isNotEmpty)
                ? Container(
                    decoration: BoxDecoration(
                      image: DecorationImage(
                        image: CachedNetworkImageProvider(
                          isWide
                              ? toAbsoluteUrl(_desktopBackground)
                              : toAbsoluteUrl(_mobileBackground),
                        ),
                        fit: BoxFit.cover,
                        onError: (_, __) {},
                      ),
                    ),
                    child: isDark
                        ? Container(color: Colors.black.withValues(alpha: 0.4))
                        : null,
                  )
                : const FrostedGlassBackground(),
          ),
          Column(
            children: [
              const TopSafeSpacer(),
              FHeader.nested(
                title: Text('${widget.survey.surveyName} - 作答结果'),
                prefixes: [
                  FHeaderAction(
                    icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                    onPress: () => Navigator.pop(context),
                  ),
                ],
                suffixes: [
                  if (_results.isNotEmpty && !_isSelectionMode)
                    FHeaderAction(
                      icon: const Icon(Icons.select_all, size: 20),
                      onPress: _toggleSelectionMode,
                    ),
                  if (_isSelectionMode) ...[
                    FHeaderAction(
                      icon: Icon(
                        _selectedResults.length == _results.length
                            ? Icons.deselect
                            : Icons.select_all,
                        size: 20,
                      ),
                      onPress: _selectAll,
                    ),
                    if (_selectedResults.isNotEmpty)
                      FButton(
                        style: FButtonStyle.ghost,
                        onPress: _showBatchDeleteConfirmDialog,
                        child: Icon(
                          Icons.delete,
                          size: 18,
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    FHeaderAction(
                      icon: const Icon(Icons.close, size: 20),
                      onPress: _toggleSelectionMode,
                    ),
                  ],
                  FHeaderAction(
                    icon: const Icon(Icons.refresh, size: 20),
                    onPress: _loadData,
                  ),
                ],
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _errorMessage != null
                          ? Center(
                              child: _buildGlassCard(
                                child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.error_outline,
                                        size: 64,
                                        color: Colors.red[400],
                                      ),
                                      const SizedBox(height: 16),
                                      const Text(
                                        '加载失败',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        _errorMessage!,
                                        style: const TextStyle(fontSize: 14),
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: 16),
                                      FButton(
                                        onPress: _loadData,
                                        child: const Text('重试'),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            )
                          : _results.isEmpty
                              ? Center(
                                  child: _buildGlassCard(
                                    child: Padding(
                                      padding: const EdgeInsets.all(32),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Image.asset(
                                            'assets/images/loading.gif',
                                            width: 64,
                                            height: 64,
                                            color: isDark ? Colors.white54 : Colors.grey,
                                          ),
                                          const SizedBox(height: 16),
                                          Text(
                                            '暂无作答结果',
                                            style: TextStyle(
                                              fontSize: 18,
                                              color: isDark ? Colors.white : Colors.black87,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            '还没有人填写这份问卷哦~',
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: isDark ? Colors.white70 : Colors.grey[600],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                )
                              : Builder(
                                  builder: (context) {
                                    final width = MediaQuery.of(context).size.width;
                                    final double target = isDesktop ? 2000 : width;
                                    final double side = width > target ? (width - target) / 2 : 0;
                                    return ScrollConfiguration(
                                      behavior: ScrollConfiguration.of(context).copyWith(
                                        scrollbars: false,
                                        dragDevices: {
                                          PointerDeviceKind.touch,
                                          PointerDeviceKind.mouse,
                                          PointerDeviceKind.trackpad,
                                          PointerDeviceKind.stylus,
                                        },
                                      ),
                                      child: CustomScrollView(
                                        controller: _scrollController,
                                        cacheExtent: 800.0,
                                        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                                        slivers: [
                                          SliverPadding(
                                            padding: EdgeInsets.fromLTRB(side + 16, 0, side + 16, 0),
                                            sliver: SliverToBoxAdapter(child: _getStatisticsCard()),
                                          ),
                                          SliverPadding(
                                            padding: EdgeInsets.fromLTRB(side + 16, 16, side + 16, 0),
                                            sliver: SliverToBoxAdapter(
                                              child: _buildGlassCard(
                                                child: const Padding(
                                                  padding: EdgeInsets.all(16),
                                                  child: Text(
                                                    '详细回答',
                                                    style: TextStyle(
                                                      fontSize: 18,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          if (_isSelectionMode && _results.isNotEmpty)
                                            SliverPadding(
                                              padding: EdgeInsets.fromLTRB(side + 16, 0, side + 16, 0),
                                              sliver: SliverToBoxAdapter(
                                                child: _buildGlassCard(
                                                  child: Padding(
                                                    padding: const EdgeInsets.all(12),
                                                    child: Row(
                                                      children: [
                                                        Icon(
                                                          Icons.info_outline,
                                                          size: 20,
                                                          color: isDark ? Colors.white70 : Colors.grey[600],
                                                        ),
                                                        const SizedBox(width: 8),
                                                        Expanded(
                                                          child: Text(
                                                            '已选择 ${_selectedResults.length} 条记录',
                                                            style: TextStyle(
                                                              fontSize: 14,
                                                              color: isDark ? Colors.white : Colors.black87,
                                                            ),
                                                          ),
                                                        ),
                                                        if (_selectedResults.isNotEmpty)
                                                          FButton(
                                                            style: FButtonStyle.destructive,
                                                            onPress: _showBatchDeleteConfirmDialog,
                                                            child: const Text('删除选中'),
                                                          ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          if (_isSelectionMode && _results.isNotEmpty)
                                            SliverToBoxAdapter(child: SizedBox(height: 16 + 0.0)),

                                          // Masonry 瀑布流（桌面端两列），移动端单列
                                          SliverPadding(
                                            padding: EdgeInsets.fromLTRB(side + 16, 0, side + 16, 0),
                                            sliver: SliverLayoutBuilder(
                                              builder: (context, constraints) {
                                                // 根据可用宽度自适应列数（上限 4 列，门槛更温和）
                                                final width = constraints.crossAxisExtent;
                                                final desired = isDesktop ? 330.0 : 300.0; // 目标卡片宽度（含间距）
                                                int crossAxisCount = (width / desired).floor();
                                                if (crossAxisCount < 1) crossAxisCount = 1;
                                                if (crossAxisCount > 4) crossAxisCount = 4; // 最高 4 列

                                                if (crossAxisCount > 1) {
                                                  return SliverMasonryGrid.count(
                                                    crossAxisCount: crossAxisCount,
                                                    mainAxisSpacing: 16,
                                                    crossAxisSpacing: 16,
                                                    childCount: _results.length,
                                                    itemBuilder: (context, index) => _buildResultCard(_results[index]),
                                                  );
                                                }
                                                return SliverList.separated(
                                                  itemCount: _results.length,
                                                  separatorBuilder: (_, __) => const SizedBox(height: 0),
                                                  itemBuilder: (context, index) => _buildResultCard(_results[index]),
                                                );
                                              },
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

