import 'dart:async';
import 'dart:ui';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../widgets/top_safe_spacer.dart';
import '../utils/csv_download_stub.dart'
  if (dart.library.html) '../utils/csv_download_web.dart'
  if (dart.library.io) '../utils/csv_download_io.dart';
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
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xls;
import '../utils/date_format.dart';
import 'dart:ui' as ui;
import '../widgets/markdown_text_widget.dart';
import '../widgets/downscaled_blur.dart';
import '../services/config.dart';
import '../components/loading_indicator.dart';
import '../components/adaptive_message_card.dart';
import '../components/glass_button.dart';
import 'recycle_bin_page.dart';

String _bgThumbUrl(String? url) {
  if (url == null || url.isEmpty) return '';
  final abs = url.startsWith('/') ? toAbsoluteUrl(url) : url;
  return abs.contains('?') ? '$abs&type=thumb' : '$abs?type=thumb';
}

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

class _SurveyResultsPageState extends State<SurveyResultsPage> with TickerProviderStateMixin {
  // 壁纸缓存：surveyId -> {desktopBackground, mobileBackground}
  static final Map<String, Map<String, String?>> _backgroundCache = {};
  
  List<SurveyResult> _results = [];
  List<Question> _questions = [];
  bool _isLoading = true;
  bool _isBgLoading = true;
  String? _errorMessage;
  Set<int> _selectedResults = {};
  bool _isSelectionMode = false;
  bool _usePieChart = false;
  late final AnimationController _exportFmtCtl;
  late final Animation<double> _exportFmtAnim;
  bool _exportFmtExpanded = false;
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final chartType = _usePieChart ? 'pie' : 'bar';
    return '$lenR-$lenQ-$firstId-$lastId-$isDark-$chartType';
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
      Colors.lightGreen,
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
                _stripMarkdown(title),
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
                                    var optionText = optionIndex < options.length
                                        ? options[optionIndex].text
                                        : '选项 ${optionIndex + 1}';
                                    
                                    // 如果是自定义填写选项，显示为"自定义答案"
                                    if (optionText == '__custom_input__') {
                                      optionText = '自定义答案';
                                    }
                                    
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
                    var optionText = optionIndex < options.length ? options[optionIndex].text : '选项 ${optionIndex + 1}';
                    
                    // 如果是自定义填写选项，显示为"自定义答案"
                    if (optionText == '__custom_input__') {
                      optionText = '自定义答案';
                    }
                    
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
                    var optionText = optionIndex < options.length ? options[optionIndex].text : '选项 ${optionIndex + 1}';
                    
                    // 如果是自定义填写选项，显示为"自定义答案"
                    if (optionText == '__custom_input__') {
                      optionText = '自定义答案';
                    }
                    
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

  // 毛玻璃样式按钮
  Widget _buildActionButton({
    required VoidCallback onTap,
    required IconData icon,
    required String label,
    required List<Color> colors,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          height: 44,
          decoration: BoxDecoration(
            color: colors.first.withValues(alpha: isDark ? 0.35 : 0.2),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: (isDark ? colors.first : Colors.white).withValues(alpha: isDark ? 0.4 : 0.2),
              width: 1,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 18, color: isDark ? Colors.white : colors.first),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      color: isDark ? Colors.white : colors.first,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'PingFangSuper',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
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
    _exportFmtCtl = AnimationController(duration: const Duration(milliseconds: 250), vsync: this);
    _exportFmtAnim = CurvedAnimation(parent: _exportFmtCtl, curve: Curves.easeInOut);
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
    _exportFmtCtl.dispose();
    super.dispose();
  }

  Widget _buildListCard({required Widget child, bool highlighted = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Card(
      elevation: 0,
      color: highlighted
          ? (isDark ? Colors.white.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.65))
          : (isDark ? Colors.white.withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.55)),
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: highlighted
            ? BorderSide(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
                width: 2,
              )
            : BorderSide.none,
      ),
      child: child,
    );
  }

  Widget _buildGlassCard({required Widget child, bool highlighted = false}) {
    // 兼容旧的调用，直接转到新的 _buildListCard
    return _buildListCard(child: child, highlighted: highlighted);
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
    final surveyId = widget.survey.id.toString();
    
    // 检查缓存
    if (_backgroundCache.containsKey(surveyId)) {
      final cached = _backgroundCache[surveyId]!;
      if (mounted) {
        setState(() {
          _desktopBackground = cached['desktopBackground'];
          _mobileBackground = cached['mobileBackground'];
          _isBgLoading = false;
        });
      }
      return;
    }
    
    // 从 API 加载
    try {
      final data = await _apiService.getSurveyBackground(widget.survey.id);
      if (!mounted) return;
      
      final desktop = data['desktopBackground'] as String?;
      final mobile = data['mobileBackground'] as String?;
      
      // 存入缓存
      _backgroundCache[surveyId] = {
        'desktopBackground': desktop,
        'mobileBackground': mobile,
      };
      
      setState(() {
        _desktopBackground = desktop;
        _mobileBackground = mobile;
        _isBgLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      
      // 即使加载失败也缓存 null 值，避免重复请求
      _backgroundCache[surveyId] = {
        'desktopBackground': null,
        'mobileBackground': null,
      };
      
      setState(() {
        _desktopBackground = null;
        _mobileBackground = null;
        _isBgLoading = false;
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

  // 生成 CSV 字符串（包含表头）
  String _generateCsv() {
    final headers = <String>['作答ID', '用户账号', '提交时间'];
    final sortedQuestions = [..._questions]..sort((a, b) => a.order.compareTo(b.order));
    headers.addAll(sortedQuestions.map((q) => _stripMarkdown(q.title)));

    final rows = <List<String>>[];
    for (final r in _results) {
      final base = <String>[r.id.toString(), r.userAccount, DateFormatUtils.formatIsoString(r.createTime)];
      final Map<int, AnswerDetail> answerMap = { for (final a in r.questions) a.questionId: a };
      final List<String> answers = [];
      for (final q in sortedQuestions) {
        final a = answerMap[q.id];
        if (a == null) { answers.add(''); continue; }
        String cell = '';
        switch (q.type) {
          case QuestionType.textInput:
            cell = _stripMarkdown(a.selectChoices);
            break;
          case QuestionType.slider:
            final v = a.selectChoices;
            final parsed = double.tryParse(v);
            if (parsed != null) {
              final key = (parsed * 2).round() / 2.0;
              final label = q.ratingLabels[key];
              cell = (label != null && label.isNotEmpty) ? '$v (${_stripMarkdown(label)})' : v;
            } else {
              cell = v;
            }
            break;
          case QuestionType.singleChoice:
          case QuestionType.multipleChoice:
            if (a.selectedOptions.isNotEmpty) {
              final texts = <String>[];
              for (final idx in a.selectedOptions) {
                var optionText = _getOptionText(q.id, idx);
                
                // 如果是自定义填写选项，提取实际填写内容
                if (optionText == '__custom_input__') {
                  if (a.selectChoices.contains('__custom_input__:')) {
                    final parts = a.selectChoices.split('__custom_input__:');
                    for (final part in parts) {
                      if (part.isEmpty) continue;
                      final colonIndex = part.indexOf(':');
                      if (colonIndex != -1) {
                        final optionIndexStr = part.substring(0, colonIndex);
                        final parsedIndex = int.tryParse(optionIndexStr);
                        if (parsedIndex == idx) {
                          final customInput = part.substring(colonIndex + 1);
                          optionText = '自定义填写: $customInput';
                          break;
                        }
                      }
                    }
                  }
                  if (optionText == '__custom_input__') {
                    optionText = '自定义填写';
                  }
                }
                
                texts.add(_stripMarkdown(optionText));
              }
              cell = texts.join('; ');
            } else {
              cell = _stripMarkdown(a.selectChoices);
            }
            break;
        }
        answers.add(_escapeCsv(cell));
      }
      rows.add([...base.map(_escapeCsv), ...answers]);
    }

    final csvLines = <String>[];
    csvLines.add(headers.map(_escapeCsv).join(','));
    for (final row in rows) {
      csvLines.add(row.join(','));
    }
    final content = csvLines.join('\r\n');
    const bom = '\uFEFF';
    return bom + content;
  }

  String _escapeCsv(String value) {
    var v = value.replaceAll('\r', ' ').replaceAll('\n', ' ');
    v = v.replaceAll('"', '""');
    return '"$v"';
  }

  // 简单的 Markdown 符号屏蔽/去除
  String _stripMarkdown(String input) {
    if (input.isEmpty) return input;
    var s = input;
    // 图片与链接: ![alt](url) / [text](url) -> alt 或 text
    s = s.replaceAllMapped(RegExp(r'!\[([^\]]*)\]\([^\)]*\)'), (m) => m.group(1) ?? '');
    s = s.replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^\)]*\)'), (m) => m.group(1) ?? '');
    // 行首标题、引用、列表标记（多行匹配）
    s = s.replaceAll(RegExp(r'^\s{0,3}#{1,6}\s*', multiLine: true), '');
    s = s.replaceAll(RegExp(r'^\s{0,3}>\s?', multiLine: true), '');
    s = s.replaceAll(RegExp(r'^\s{0,3}[-+*]\s+', multiLine: true), '');
    s = s.replaceAll(RegExp(r'^\s{0,3}\d+\.\s+', multiLine: true), '');
    // 强调、行内代码、删除线（全部改为映射，避免出现 "$1" 文本）
    s = s.replaceAllMapped(RegExp(r'\*\*([^*]+)\*\*'), (m) => m.group(1) ?? '');
    s = s.replaceAllMapped(RegExp(r'__([^_]+)__'), (m) => m.group(1) ?? '');
    s = s.replaceAllMapped(RegExp(r'\*([^*]+)\*'), (m) => m.group(1) ?? '');
    s = s.replaceAllMapped(RegExp(r'_([^_]+)_'), (m) => m.group(1) ?? '');
    s = s.replaceAllMapped(RegExp(r'`([^`]+)`'), (m) => m.group(1) ?? '');
    s = s.replaceAllMapped(RegExp(r'~~([^~]+)~~'), (m) => m.group(1) ?? '');
    // 表格分隔符与多余的竖线
    s = s.replaceAll(RegExp(r'\|'), ' ');
    // 多个空白压缩
    s = s.replaceAll(RegExp(r'[\t ]+'), ' ');
    return s.trim();
  }

  Future<void> _exportCsv() async {
    try {
      final csv = _generateCsv();
      final bytes = utf8.encode(csv);
      final safeName = widget.survey.surveyName.replaceAll(RegExp(r'[\\/:*?\"<>|]'), '_');
      final ts = DateTime.now().toIso8601String().replaceAll(':', '-');
      final fileName = '${safeName}_$ts.csv';
      final savedPath = await downloadCsv(fileName, bytes);
      if (!mounted) return;
      if (savedPath != null && savedPath.isNotEmpty) {
        showFToast(context: context, title: Text('已导出到: $savedPath'));
      } else if (kIsWeb) {
        // Web 平台为浏览器下载，提示开始下载
        showFToast(context: context, title: Text('开始下载: $fileName'));
      } else {
        // 非 Web 且返回 null，一般为用户取消保存，不提示
      }
    } catch (e) {
      if (mounted) {
        showFToast(context: context, title: Text('导出失败: $e'));
      }
    }
  }

  Future<void> _exportXlsx() async {
    try {
      // 1) 创建工作簿与工作表
      final workbook = xls.Workbook();
      final sheet = workbook.worksheets[0];
      sheet.name = '作答结果';

      // 2) 构建表头：作答ID, 用户账号, 提交时间, 每个问题标题（按 order）
      final headers = <String>['作答ID', '用户账号', '提交时间'];
      final sortedQuestions = [..._questions]..sort((a, b) => a.order.compareTo(b.order));
      headers.addAll(sortedQuestions.map((q) => _stripMarkdown(q.title)));

      // 写入表头
      for (int c = 0; c < headers.length; c++) {
        sheet.getRangeByIndex(1, c + 1).setText(headers[c]);
      }

      // 样式：表头加粗、居中、边框
      final headerStyle = workbook.styles.add('header');
      headerStyle.bold = true;
      headerStyle.hAlign = xls.HAlignType.center;
      headerStyle.vAlign = xls.VAlignType.center;
      headerStyle.borders.all.lineStyle = xls.LineStyle.thin;
      sheet.getRangeByIndex(1, 1, 1, headers.length).cellStyle = headerStyle;

      // 3) 数据行
      for (int r = 0; r < _results.length; r++) {
        final rowIndex = r + 2; // 第2行开始
        final result = _results[r];
        // 基本列
        sheet.getRangeByIndex(rowIndex, 1).setNumber(result.id.toDouble());
        sheet.getRangeByIndex(rowIndex, 2).setText(result.userAccount);
        // 日期列：写 ISO 文本并设置格式
        final dateCell = sheet.getRangeByIndex(rowIndex, 3);
        dateCell.setText(DateFormatUtils.formatIsoString(result.createTime));
        dateCell.numberFormat = 'yyyy-mm-dd hh:mm:ss';

        // questionId -> AnswerDetail
        final map = { for (final a in result.questions) a.questionId: a };
        for (int qi = 0; qi < sortedQuestions.length; qi++) {
          final colIndex = 4 + qi; // 从第4列开始写题目
          final q = sortedQuestions[qi];
          final a = map[q.id];
          String cell = '';
          if (a != null) {
            switch (q.type) {
              case QuestionType.textInput:
                cell = _stripMarkdown(a.selectChoices);
                break;
              case QuestionType.slider:
                final v = a.selectChoices;
                final parsed = double.tryParse(v);
                if (parsed != null) {
                  final key = (parsed * 2).round() / 2.0;
                  final label = q.ratingLabels[key];
                  cell = (label != null && label.isNotEmpty) ? '$v (${_stripMarkdown(label)})' : v;
                } else {
                  cell = v;
                }
                break;
              case QuestionType.singleChoice:
              case QuestionType.multipleChoice:
                if (a.selectedOptions.isNotEmpty) {
                  final texts = <String>[];
                  for (final idx in a.selectedOptions) {
                    var optionText = _getOptionText(q.id, idx);
                    
                    // 如果是自定义填写选项，提取实际填写内容
                    if (optionText == '__custom_input__') {
                      if (a.selectChoices.contains('__custom_input__:')) {
                        final parts = a.selectChoices.split('__custom_input__:');
                        for (final part in parts) {
                          if (part.isEmpty) continue;
                          final colonIndex = part.indexOf(':');
                          if (colonIndex != -1) {
                            final optionIndexStr = part.substring(0, colonIndex);
                            final parsedIndex = int.tryParse(optionIndexStr);
                            if (parsedIndex == idx) {
                              final customInput = part.substring(colonIndex + 1);
                              optionText = '自定义填写: $customInput';
                              break;
                            }
                          }
                        }
                      }
                      if (optionText == '__custom_input__') {
                        optionText = '自定义填写';
                      }
                    }
                    
                    texts.add(_stripMarkdown(optionText));
                  }
                  cell = texts.join('; ');
                } else {
                  cell = _stripMarkdown(a.selectChoices);
                }
                break;
            }
          }
          sheet.getRangeByIndex(rowIndex, colIndex).setText(cell);
        }
      }

      // 4) 通用数据区域样式：边框、垂直居中（不换行，减小行高）
      if (_results.isNotEmpty) {
        final dataStyle = workbook.styles.add('data');
        dataStyle.borders.all.lineStyle = xls.LineStyle.thin;
        dataStyle.vAlign = xls.VAlignType.center;
        dataStyle.wrapText = false;
        sheet.getRangeByIndex(2, 1, 1 + _results.length, headers.length).cellStyle = dataStyle;
      }

      // 5) 自动列宽（根据内容）
      for (int c = 1; c <= headers.length; c++) {
        sheet.autoFitColumn(c);
      }

      // 5.1) 调整行高，让表格更加紧凑
      // 表头行高（约 22 像素）
      sheet.getRangeByIndex(1, 1, 1, headers.length).rowHeight = 22;
      // 数据行固定较小行高（约 18 像素）
      if (_results.isNotEmpty) {
        sheet.getRangeByIndex(2, 1, 1 + _results.length, headers.length).rowHeight = 18;
      }

      // 6) 冻结首行（使用 Range.freezePanes API）
      sheet.getRangeByIndex(2, 1).freezePanes();

      // 7) 导出为字节并下载
      final list = workbook.saveAsStream();
      workbook.dispose();
      
      // 确保字节数据完整性
      final bytes = Uint8List.fromList(list);
      
      final safeName = widget.survey.surveyName.replaceAll(RegExp(r'[\\/:*?\"<>|]'), '_');
      final ts = DateTime.now().toIso8601String().replaceAll(':', '-').substring(0, 19);
      final fileName = '${safeName}_$ts.xlsx';
      
      final savedPath = await downloadBytes(
        fileName,
        bytes,
        mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
      if (!mounted) return;
      if (savedPath != null && savedPath.isNotEmpty) {
        showFToast(context: context, title: Text('已导出到: $savedPath'));
      } else if (kIsWeb) {
        showFToast(context: context, title: Text('开始下载: $fileName'));
      } else {
      }
    } catch (e) {
      if (mounted) {
        showFToast(context: context, title: Text('导出 Excel 失败: $e'));
      }
    }
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
            style: context.theme.buttonStyles.outline.call,
            onPress: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FButton(
            style: context.theme.buttonStyles.destructive.call,
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
            style: context.theme.buttonStyles.outline.call,
            onPress: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FButton(
            style: context.theme.buttonStyles.destructive.call,
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
                          style: context.theme.buttonStyles.ghost.call,
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
                        MarkdownTextWidget(
                          text: questionTitle,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        if (question.type == QuestionType.slider)
                          _buildRatingRow(question, answer.selectChoices)
                        else if (question.type == QuestionType.textInput && answer.selectChoices.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(left: 16, top: 2),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Text(
                                answer.selectChoices,
                                style: const TextStyle(fontSize: 14),
                              ),
                            ),
                          )
                        else if (answer.selectedOptions.isNotEmpty)
                          ...answer.selectedOptions.map((optionIndex) {
                            var optionText = _getOptionText(answer.questionId, optionIndex);
                            String? customInput;
                            
                            // 检查是否是自定义填写选项
                            if (optionText == '__custom_input__') {
                              optionText = '自定义填写';
                              // 从 selectChoices 中提取自定义输入内容
                              if (answer.selectChoices.contains('__custom_input__:')) {
                                final parts = answer.selectChoices.split('__custom_input__:');
                                for (final part in parts) {
                                  if (part.isEmpty) continue;
                                  final colonIndex = part.indexOf(':');
                                  if (colonIndex != -1) {
                                    final optionIndexStr = part.substring(0, colonIndex);
                                    final parsedIndex = int.tryParse(optionIndexStr);
                                    if (parsedIndex == optionIndex) {
                                      customInput = part.substring(colonIndex + 1);
                                      break;
                                    }
                                  }
                                }
                              }
                            }
                            
                            return Padding(
                              padding: const EdgeInsets.only(left: 16, top: 2),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.check_circle,
                                        size: 16,
                                        color: Colors.lightGreen,
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
                                  // 显示自定义填写的内容
                                  if (customInput != null && customInput.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Container(
                                      width: double.infinity,
                                      margin: const EdgeInsets.only(left: 24),
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
                                        ),
                                      ),
                                      child: Text(
                                        customInput,
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                    ),
                                  ],
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
    // 存储自定义填写的数据：key = questionId_optionIndex, value = List<Map<userAccount, content>>
    final customInputAnswers = <String, List<Map<String, String>>>{};

    for (final result in _results) {
      for (final answer in result.questions) {
        responsesByQuestion[answer.questionId] ??= {};
        for (final option in answer.selectedOptions) {
          responsesByQuestion[answer.questionId]![option] =
              (responsesByQuestion[answer.questionId]![option] ?? 0) + 1;
        }
        
        if (answer.selectChoices.isNotEmpty && answer.selectChoices.contains('__custom_input__:')) {
          final parts = answer.selectChoices.split('__custom_input__:');
          for (final part in parts) {
            if (part.isEmpty) continue;
            final colonIndex = part.indexOf(':');
            if (colonIndex > 0) {
              final optionIndex = int.tryParse(part.substring(0, colonIndex));
              final userInput = part.substring(colonIndex + 1);
              if (optionIndex != null && userInput.isNotEmpty) {
                final key = '${answer.questionId}_$optionIndex';
                customInputAnswers[key] ??= [];
                // 存储用户账号和填写内容
                customInputAnswers[key]!.add({
                  'userAccount': result.userAccount,
                  'content': userInput,
                });
              }
            }
          }
        }
      }
    }

    return _buildGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 16,
              runSpacing: 12,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '统计概览',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 12),
                    FButton(
                      style: context.theme.buttonStyles.ghost.call,
                      onPress: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => RecycleBinPage(
                              token: widget.token,
                              surveyId: widget.survey.id,
                              surveyName: widget.survey.surveyName,
                              desktopBackground: _desktopBackground,
                              mobileBackground: _mobileBackground,
                            ),
                          ),
                        ).then((_) => _loadData()); // 返回时刷新数据
                      },
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.delete_outline, size: 18),
                          SizedBox(width: 4),
                          Text('回收站', style: TextStyle(fontSize: 14)),
                        ],
                      ),
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FButton(
                      style: context.theme.buttonStyles.ghost.call,
                      onPress: () {
                        setState(() => _exportFmtExpanded = !_exportFmtExpanded);
                        _exportFmtCtl.toggle();
                      },
                      child: Row(
                        children: [
                          const Icon(FIcons.arrowBigUpDash, size: 24),
                          const SizedBox(width: 6),
                          const Text('导出为...'),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    FSwitch(
                      label: const Text('饼图'),
                      value: _usePieChart,
                      onChange: (value) {
                        setState(() {
                          _usePieChart = value;
                          _statisticsCache = null;
                        });
                      },
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            AnimatedBuilder(
              animation: _exportFmtAnim,
              builder: (context, child) => FCollapsible(
                value: _exportFmtAnim.value,
                child: _buildGlassCard(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '导出文件格式',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8,),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final isNarrow = constraints.maxWidth < 420;
                            final csvBtn = _buildActionButton(
                              onTap: _exportCsv,
                              icon: Icons.table_rows,
                              label: '导出 CSV',
                              colors: const [Color(0xFF4CAF50), Color(0xFF2E7D32)],
                            );
                            final xlsxBtn = _buildActionButton(
                              onTap: _exportXlsx,
                              icon: Icons.table_chart,
                              label: '导出 Excel',
                              colors: const [Color(0xFF1976D2), Color(0xFF0D47A1)],
                            );

                            return isNarrow
                                ? Column(
                                    children: [
                                      csvBtn,
                                      const SizedBox(height: 12),
                                      xlsxBtn,
                                    ],
                                  )
                                : Row(
                                    children: [
                                      Expanded(child: csvBtn),
                                      const SizedBox(width: 12),
                                      Expanded(child: xlsxBtn),
                                    ],
                                  );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
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
                final cols = w >= 750 ? 2 : 1;
                const gap = 16.0;
                final pieCards = <Widget>[];
                
                for (final question in _questions) {
                  if (question.type == QuestionType.textInput) {
                    // 填写题统计
                    final textAnswers = _results
                        .map((r) => r.questions.firstWhere(
                              (d) => d.questionId == question.id,
                              orElse: () => AnswerDetail(
                                id: 0,
                                answerId: r.id,
                                questionId: question.id,
                                selectedOptions: const [],
                                selectChoices: '',
                              ),
                            ))
                        .where((a) => a.selectChoices.isNotEmpty)
                        .toList();
                    
                    pieCards.add(SizedBox(
                      width: cols > 1 ? (w - gap) / 2 : w,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: _buildTextInputSummary(question, textAnswers),
                      ),
                    ));
                  } else if (question.type != QuestionType.slider) {
                    final questionStats = responsesByQuestion[question.id] ?? {};
                    
                    // 检查是否有自定义填写选项，并统计自定义答案数量
                    final hasCustomInput = question.options.any((opt) => opt.text == '__custom_input__');
                    Map<int, int> adjustedStats = Map.from(questionStats);
                    
                    if (hasCustomInput) {
                      final customInputIndex = question.options.indexWhere((opt) => opt.text == '__custom_input__');
                      if (customInputIndex != -1) {
                        final customKey = '${question.id}_$customInputIndex';
                        final customAnswersCount = customInputAnswers[customKey]?.length ?? 0;
                        if (customAnswersCount > 0) {
                          adjustedStats[customInputIndex] = customAnswersCount;
                        }
                      }
                    }
                    
                    pieCards.add(SizedBox(
                      width: cols > 1 ? (w - gap) / 2 : w,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: _buildPieChart(adjustedStats, question.options, totalResponses, title: question.title),
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
              if (question.type == QuestionType.textInput) {
                // 填写题统计
                final textAnswers = _results
                    .map((r) => r.questions.firstWhere(
                          (d) => d.questionId == question.id,
                          orElse: () => AnswerDetail(
                            id: 0,
                            answerId: r.id,
                            questionId: question.id,
                            selectedOptions: const [],
                            selectChoices: '',
                          ),
                        ))
                    .where((a) => a.selectChoices.isNotEmpty)
                    .toList();
                
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _buildTextInputSummary(question, textAnswers),
                );
              } else if (question.type != QuestionType.slider) {
                final questionStats = responsesByQuestion[question.id] ?? {};
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      MarkdownTextWidget(
                        text: question.title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      LayoutBuilder(builder: (context, constraints) {
                        final w = constraints.maxWidth;
                        final cols = w >= 2000 ? 5 : (w >= 1600 ? 4 : (w >= 1200 ? 3 : (w >= 800 ? 2 : 1)));
                        const gap = 12.0;
                        final itemW = cols > 1 ? (w - gap * (cols - 1)) / cols : w;
                        final tiles = question.options.asMap().entries.map((entry) {
                        final optionIndex = entry.key;
                        final option = entry.value;
                        final optionText = option.text == '__custom_input__' ? '自定义填写' : option.text;
                        final count = questionStats[optionIndex] ?? 0;
                        final percentage = totalResponses > 0
                            ? (count / totalResponses * 100).toStringAsFixed(1)
                            : '0.0';
                          final ratio = totalResponses > 0 ? (count / totalResponses) : 0.0;
                          
                          // 检查是否有自定义填写的答案
                          final customKey = '${question.id}_$optionIndex';
                          final customAnswers = customInputAnswers[customKey];
                          
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
                                  // 显示自定义填写的答案
                                  if (customAnswers != null && customAnswers.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    InkWell(
                                      onTap: () => _showCustomInputDetails(question, optionIndex, customAnswers),
                                      borderRadius: BorderRadius.circular(6),
                                      child: Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(
                                            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Text(
                                                  '填写内容：',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.70),
                                                  ),
                                                ),
                                                const Spacer(),
                                                Icon(
                                                  Icons.open_in_new,
                                                  size: 14,
                                                  color: Theme.of(context).colorScheme.primary,
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            ...customAnswers.take(3).map((answerData) => Padding(
                                              padding: const EdgeInsets.only(bottom: 2),
                                              child: Text(
                                                '• ${answerData['content'] ?? ''}',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
                                                ),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            )),
                                            if (customAnswers.length > 3)
                                              Text(
                                                '…及其他 ${customAnswers.length - 3} 条（点击查看全部）',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontStyle: FontStyle.italic,
                                                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.70),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
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
                      MarkdownTextWidget(
                        text: question.title,
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
                      final cols = w >= 2000 ? 5 : (w >= 1600 ? 4 : (w >= 1200 ? 3 : (w >= 800 ? 2 : 1)));
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

    if (_isBgLoading) {
      return Scaffold(
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? [Colors.grey[900]!, Colors.black]
                  : [Colors.blue[50]!, Colors.purple[50]!],
            ),
          ),
          child: Column(
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
              ),
              const Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 50,
                        height: 50,
                        child: CircularProgressIndicator(strokeWidth: 3),
                      ),
                      SizedBox(height: 24),
                      Text(
                        '加载背景中...',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          // 全屏模糊背景
          Positioned.fill(
            child: DownscaledBlur(
              sigma: 30,
              downscale: 0.4,
              child: (_desktopBackground != null && _desktopBackground!.isNotEmpty) ||
                     (_mobileBackground != null && _mobileBackground!.isNotEmpty)
                  ? Container(
                      decoration: BoxDecoration(
                        image: DecorationImage(
                          image: CachedNetworkImageProvider(
                            isWide
                                ? _bgThumbUrl(_desktopBackground)
                                : _bgThumbUrl(_mobileBackground),
                          ),
                          fit: BoxFit.cover,
                          onError: (_, __) {},
                        ),
                      ),
                      child: Container(
                        color: (isDark ? Colors.black : Colors.white).withValues(alpha: 0.3),
                      ),
                    )
                  : Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: isDark
                              ? [Colors.grey[900]!, Colors.black]
                              : [Colors.blue[50]!, Colors.purple[50]!],
                        ),
                      ),
                    ),
            ),
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
                      ? const LoadingIndicator.page()
                      : _errorMessage != null
                          ? TweenAnimationBuilder<double>(
                              duration: const Duration(milliseconds: 600),
                              curve: Curves.easeOutCubic,
                              tween: Tween(begin: 0.0, end: 1.0),
                              builder: (context, value, child) {
                                return Transform.translate(
                                  offset: Offset(0, 50 * (1 - value)),
                                  child: Transform.scale(
                                    scale: 0.8 + (0.2 * value),
                                    child: Opacity(
                                      opacity: value,
                                      child: child,
                                    ),
                                  ),
                                );
                              },
                              child: AdaptiveMessageCard(
                                cardWrapper: (content) => _buildGlassCard(child: content),
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
                                    GlassButton(
                                      text: '重试',
                                      color: Colors.blue,
                                      onPressed: _loadData,
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : _results.isEmpty
                              ? TweenAnimationBuilder<double>(
                                  duration: const Duration(milliseconds: 600),
                                  curve: Curves.easeOutCubic,
                                  tween: Tween(begin: 0.0, end: 1.0),
                                  builder: (context, value, child) {
                                    return Transform.translate(
                                      offset: Offset(0, 50 * (1 - value)),
                                      child: Transform.scale(
                                        scale: 0.8 + (0.2 * value),
                                        child: Opacity(
                                          opacity: value,
                                          child: child,
                                        ),
                                      ),
                                    );
                                  },
                                  child: AdaptiveMessageCard(
                                    cardWrapper: (content) => _buildGlassCard(child: content),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.inbox_outlined,
                                          size: 64,
                                          color: isDark ? Colors.white38 : Colors.grey[400],
                                        ),
                                        const SizedBox(height: 16),
                                        Text(
                                          '暂无作答结果',
                                          style: TextStyle(
                                            fontSize: 18,
                                            color: isDark ? Colors.white : Colors.black87,
                                            fontWeight: FontWeight.w500,
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
                                )
                              : LayoutBuilder(
                                  builder: (context, box) {
                                    final width = box.maxWidth;
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
                                            padding: EdgeInsets.fromLTRB(side + 16, 8, side + 16, 0),
                                            sliver: SliverToBoxAdapter(child: _getStatisticsCard()),
                                          ),
                                          SliverPadding(
                                            padding: EdgeInsets.fromLTRB(side + 16, 0, side + 16, 0),
                                            sliver: SliverToBoxAdapter(
                                              child: _buildListCard(
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
                                                            style: context.theme.buttonStyles.destructive.call,
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

  Widget _buildTextInputSummary(Question question, List<AnswerDetail> textAnswers) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return _buildGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MarkdownTextWidget(
              text: question.title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  Icons.edit_note,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  '填写题统计',
                  style: TextStyle(
                    fontSize: 14,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: theme.colorScheme.outline.withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '回复数量: ${textAnswers.length}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        '回复率: ${textAnswers.isEmpty ? '0' : (textAnswers.length / _results.length * 100).toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  if (textAnswers.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Text(
                      '最近回复预览:',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...textAnswers.take(3).map((answer) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.grey[800] : Colors.grey[100],
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          answer.selectChoices.length > 50 
                              ? '${answer.selectChoices.substring(0, 50)}...'
                              : answer.selectChoices,
                          style: const TextStyle(fontSize: 12),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FButton(
                        style: context.theme.buttonStyles.outline.call,
                        onPress: () => _showTextInputDetails(question, textAnswers),
                        child: const Text('查看所有回复'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCustomInputDetails(Question question, int optionIndex, List<Map<String, String>> customAnswers) {
    
    final optionText = question.options[optionIndex].text == '__custom_input__' 
        ? '自定义填写' 
        : question.options[optionIndex].text;
    
    showFDialog(
      context: context,
      builder: (context, style, animation) => FDialog(
        style: style.call,
        animation: animation,
        direction: Axis.vertical,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MarkdownTextWidget(
              text: question.title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '选项: $optionText',
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        body: SizedBox(
          width: MediaQuery.of(context).size.width * 0.8,
          height: MediaQuery.of(context).size.height * 0.6,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '共 ${customAnswers.length} 条自定义填写',
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.builder(
                  itemCount: customAnswers.length,
                  itemBuilder: (context, index) {
                    final answerData = customAnswers[index];
                    final userAccount = answerData['userAccount'] ?? '匿名用户';
                    final content = answerData['content'] ?? '';
                    
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.person,
                                  size: 16,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '$userAccount 的填写',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                content,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          FButton(
            style: context.theme.buttonStyles.outline.call,
            onPress: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  void _showTextInputDetails(Question question, List<AnswerDetail> textAnswers) {
    // 创建一个映射，将每个答案与其对应的结果关联
    final answerToResult = <AnswerDetail, SurveyResult>{};
    for (final answer in textAnswers) {
      for (final result in _results) {
        if (result.questions.any((q) => q.id == answer.id)) {
          answerToResult[answer] = result;
          break;
        }
      }
    }
    
    showFDialog(
      context: context,
      builder: (context, style, animation) => FDialog(
        style: style.call,
        animation: animation,
        direction: Axis.vertical,
        title: MarkdownTextWidget(
          text: question.title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        body: SizedBox(
          width: MediaQuery.of(context).size.width * 0.8,
          height: MediaQuery.of(context).size.height * 0.6,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '共 ${textAnswers.length} 条回复',
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.builder(
                  itemCount: textAnswers.length,
                  itemBuilder: (context, index) {
                    final answer = textAnswers[index];
                    final result = answerToResult[answer] ?? SurveyResult(
                      id: 0,
                      surveyId: 0,
                      userId: '',
                      userAccount: '未知用户',
                      createTime: '',
                      questions: [],
                    );
                    
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.person,
                                  size: 16,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  result.userAccount.isEmpty ? '匿名用户' : result.userAccount,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  DateFormatUtils.formatIsoString(result.createTime),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Text(
                                answer.selectChoices,
                                style: const TextStyle(fontSize: 14),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          FButton(
            style: context.theme.buttonStyles.outline.call,
            onPress: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}

