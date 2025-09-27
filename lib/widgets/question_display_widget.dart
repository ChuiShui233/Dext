import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/question.dart';
import '../components/glass_card.dart';
import '../components/media_gallery.dart';
import '../pages/fullscreen_media_viewer.dart';

/// 问题显示模式
enum QuestionDisplayMode {
  interactive,  // 交互模式（可点击选择）
  preview,      // 预览模式（可点击但仅用于预览）
  readonly,     // 只读模式（显示已选择的答案）
}

/// 统一的问题显示Widget
class QuestionDisplayWidget extends StatefulWidget {
  final Question question;
  final QuestionDisplayMode mode;
  final Map<String, bool> optionStates;
  final List<String> selectedAnswers;
  final Map<int, double?> hoverRatings;
  final Function(int questionId, String selectedOption, int optionIndex)? onSingleChoiceChanged;
  final Function(int questionId, String option, int optionIndex, bool isSelected)? onMultipleChoiceChanged;
  final Function(int questionId, String value)? onRatingChanged;
  final Function(String mediaUrl, List<String> allMediaUrls, int currentIndex)? onMediaOpen;

  const QuestionDisplayWidget({
    super.key,
    required this.question,
    required this.mode,
    required this.optionStates,
    this.selectedAnswers = const [],
    this.hoverRatings = const {},
    this.onSingleChoiceChanged,
    this.onMultipleChoiceChanged,
    this.onRatingChanged,
    this.onMediaOpen,
  });

  @override
  State<QuestionDisplayWidget> createState() => _QuestionDisplayWidgetState();
}

class _QuestionDisplayWidgetState extends State<QuestionDisplayWidget> {
  late Map<int, double?> _localHoverRatings;

  @override
  void initState() {
    super.initState();
    _localHoverRatings = Map.from(widget.hoverRatings);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 问题标题
        Row(
          children: [
            Expanded(
              child: Text(
                widget.question.title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ),
            if (widget.question.required)
              const Text(' *', style: TextStyle(color: Colors.red)),
          ],
        ),
        const SizedBox(height: 12),

        // 媒体区域
        if (widget.question.mediaUrls.isNotEmpty)
          _buildMediaSection(),
        
        const SizedBox(height: 12),
        
        // 答案区域
        _buildAnswerWidget(),
      ],
    );
  }

  Widget _buildMediaSection() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '媒体文件',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white70 : Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
            MediaGallery(
              mediaUrls: widget.question.mediaUrls,
              imageItemSize: 120,
              videoItemSize: const Size(240, 180),
              enableVideoPlayer: true,
              showVideoOverlay: true,
              onOpen: widget.onMediaOpen != null 
                ? (index, url, all) => widget.onMediaOpen!(url, all, index)
                : _defaultMediaOpen,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnswerWidget() {
    switch (widget.question.type) {
      case QuestionType.singleChoice:
        return _buildSingleChoiceWidget();
      case QuestionType.multipleChoice:
        return _buildMultipleChoiceWidget();
      case QuestionType.slider:
        return _buildRatingWidget();
      case QuestionType.matrix:
        return _buildMatrixWidget();
    }
  }

  Widget _buildSingleChoiceWidget() {

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widget.question.options.asMap().entries.map((entry) {
        final int index = entry.key;
        final opt = entry.value;
        final optionKey = _getOptionKey(widget.question.id, index);
        final isSelected = widget.optionStates[optionKey] ?? false;
        
        return _buildOptionCard(
          option: opt,
          index: index,
          isSelected: isSelected,
          isMultiple: false,
          onTap: widget.mode == QuestionDisplayMode.readonly 
              ? null 
              : () => widget.onSingleChoiceChanged?.call(widget.question.id, opt.text, index),
        );
      }).toList(),
    );
  }

  Widget _buildMultipleChoiceWidget() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widget.question.options.asMap().entries.map((entry) {
        final int index = entry.key;
        final opt = entry.value;
        final optionKey = _getOptionKey(widget.question.id, index);
        final isSelected = widget.optionStates[optionKey] ?? false;
        
        return _buildOptionCard(
          option: opt,
          index: index,
          isSelected: isSelected,
          isMultiple: true,
          onTap: widget.mode == QuestionDisplayMode.readonly 
              ? null 
              : () => widget.onMultipleChoiceChanged?.call(widget.question.id, opt.text, index, isSelected),
        );
      }).toList(),
    );
  }

  Widget _buildOptionCard({
    required QuestionOption option,
    required int index,
    required bool isSelected,
    required bool isMultiple,
    VoidCallback? onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    Widget leadingWidget;
    if (widget.mode == QuestionDisplayMode.readonly) {
      // 只读模式显示选中状态
      leadingWidget = Icon(
        isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
        color: isSelected
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.35),
        size: 18,
      );
    } else {
      // 交互模式显示正常的选择控件
      leadingWidget = isMultiple
          ? Checkbox(
              value: isSelected,
              onChanged: onTap != null ? (_) => onTap() : null,
            )
          : GestureDetector(
              onTap: onTap,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected 
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.35),
                    width: 2,
                  ),
                ),
                child: AnimatedScale(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  scale: isSelected ? 1.0 : 0.0,
                  child: Center(
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ),
              ),
            );
    }

    return GlassCard(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              leadingWidget,
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  option.text,
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
              if (option.mediaUrl != null && option.mediaUrl!.isNotEmpty)
                _buildOptionMedia(option.mediaUrl!),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOptionMedia(String mediaUrl) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return GestureDetector(
      onTap: () {
        if (widget.onMediaOpen != null) {
          widget.onMediaOpen!(mediaUrl, [mediaUrl], 0);
        } else {
          _defaultMediaOpen(0, mediaUrl, [mediaUrl]);
        }
      },
      child: Container(
        width: 40,
        height: 40,
        margin: const EdgeInsets.only(left: 8),
        decoration: BoxDecoration(
          border: Border.all(color: isDark ? Colors.grey[700]! : Colors.grey.shade300),
          borderRadius: BorderRadius.circular(4),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Stack(
            children: [
              CachedNetworkImage(
                imageUrl: mediaUrl,
                fit: BoxFit.cover,
                placeholder: (context, url) => const Center(
                  child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                ),
                errorWidget: (context, url, error) => const Icon(Icons.error, size: 16),
              ),
              // 放大图标覆盖层
              Positioned(
                top: 2,
                right: 2,
                child: Container(
                  padding: const EdgeInsets.all(1),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: const Icon(
                    Icons.zoom_in,
                    color: Colors.white,
                    size: 6,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRatingWidget() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    const double starIconSize = 38.0;

    // 读取当前评分值
    String currentStr = '';
    if (widget.selectedAnswers.isNotEmpty) {
      currentStr = widget.selectedAnswers.first;
    }
    double current = double.tryParse(currentStr) ?? widget.question.ratingInitial;

    // 配置参数
    final int stars = widget.question.ratingStars;
    final bool allowHalf = widget.question.ratingAllowHalf;
    final String iconType = widget.question.ratingIcon;
    final String style = widget.question.ratingStyle;
    final String minLabel = widget.question.ratingMinLabel;
    final String maxLabel = widget.question.ratingMaxLabel;
    final String midLabel = widget.question.ratingMidLabel;
    final Map<double, String> labelsMap = widget.question.ratingLabels;

    // 评分值限制
    double value = current;
    if (allowHalf) {
      value = value.clamp(0.5, stars.toDouble());
    } else {
      value = value.clamp(1.0, stars.toDouble());
    }
    final int filledFull = value.floor();
    final bool hasHalf = allowHalf && (value - filledFull).abs() >= 0.5 && filledFull < stars;

    // 构建图标函数
    Widget buildFilledIcon(double size) {
      switch (iconType) {
        case 'favorite': return Icon(Icons.favorite, size: size, color: theme.colorScheme.primary);
        case 'circle': return Icon(Icons.circle, size: size, color: theme.colorScheme.primary);
        case 'heart_broken': return Icon(Icons.heart_broken, size: size, color: theme.colorScheme.primary);
        case 'star':
        default: return Icon(Icons.star, size: size, color: theme.colorScheme.primary);
      }
    }

    Widget buildOutlineIcon(double size) {
      final Color inactive = theme.colorScheme.onSurface.withValues(alpha: 0.35);
      switch (iconType) {
        case 'favorite': return Icon(Icons.favorite_border, size: size, color: inactive);
        case 'circle': return Icon(Icons.circle_outlined, size: size, color: inactive);
        case 'heart_broken': return Icon(Icons.heart_broken, size: size, color: inactive);
        case 'star':
        default: return Icon(Icons.star_border, size: size, color: inactive);
      }
    }

    Widget buildHalfIcon(double size) {
      if (iconType == 'star') return Icon(Icons.star_half, size: size, color: theme.colorScheme.primary);
      // 其他图标用 ShaderMask 显示左半
      return Stack(
        alignment: Alignment.center,
        children: [
          buildOutlineIcon(size),
          SizedBox(
            width: size,
            height: size,
            child: ShaderMask(
              shaderCallback: (Rect bounds) {
                return LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    theme.colorScheme.primary,
                    theme.colorScheme.primary,
                    Colors.transparent,
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.5, 0.5, 1.0],
                ).createShader(bounds);
              },
              blendMode: BlendMode.srcIn,
              child: buildFilledIcon(size),
            ),
          ),
        ],
      );
    }

    // 构建星星或面包屑
    Widget buildRatingItem(int index) {
      if (style == 'crumb') {
        return _buildCrumb(index, stars, filledFull, hasHalf, allowHalf, theme);
      } else {
        return _buildStar(index, stars, filledFull, hasHalf, allowHalf, starIconSize, buildFilledIcon, buildOutlineIcon, buildHalfIcon);
      }
    }

    final bool useCrumb = (style == 'crumb');
    final double? hoverVal = _localHoverRatings[widget.question.id];
    String hoverLabel = '';
    if (hoverVal != null) {
      final double key = (hoverVal * 2).round() / 2.0;
      final String? mapped = labelsMap[key];
      hoverLabel = mapped ?? (key % 1 == 0 ? '${key.toInt()} 星' : '${key.toStringAsFixed(1)} 星');
    }

    final items = List<Widget>.generate(stars, (i) => buildRatingItem(i));
    final double barUnitWidth = useCrumb ? 24.0 : starIconSize;
    final double barWidth = barUnitWidth * stars;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ...items,
            if (hoverLabel.isNotEmpty) ...[
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  hoverLabel,
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
          ],
        ),
        if (useCrumb) ...[
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ...List.generate(stars, (i) {
                final int segIndex = i + 1;
                final double key = segIndex.toDouble();
                final String text = labelsMap[key] ?? segIndex.toString();
                return SizedBox(
                  width: 24,
                  child: Center(
                    child: Text(
                      text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: isDark ? Colors.white : Colors.black87),
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
              Text(minLabel, style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
              Text(midLabel, style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.w500)),
              Text(maxLabel, style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStar(int index, int stars, int filledFull, bool hasHalf, bool allowHalf, double starIconSize, 
      Widget Function(double) buildFilledIcon, Widget Function(double) buildOutlineIcon, Widget Function(double) buildHalfIcon) {
    final int starIndex = index + 1;
    Theme.of(context);

    return MouseRegion(
      onExit: widget.mode == QuestionDisplayMode.readonly ? null : (_) {
        setState(() => _localHoverRatings[widget.question.id] = null);
      },
      onHover: widget.mode == QuestionDisplayMode.readonly ? null : (e) {
        double hv = starIndex.toDouble();
        if (allowHalf) {
          final dx = e.localPosition.dx;
          if (dx <= starIconSize / 2) hv = starIndex - 0.5;
        }
        setState(() => _localHoverRatings[widget.question.id] = hv.clamp(allowHalf ? 0.5 : 1.0, stars.toDouble()));
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: widget.mode == QuestionDisplayMode.readonly ? null : (details) {
          double nextVal = starIndex.toDouble();
          if (allowHalf) {
            final dx = details.localPosition.dx;
            if (dx <= starIconSize / 2) nextVal = (starIndex - 0.5).clamp(0.5, stars.toDouble());
          }
          widget.onRatingChanged?.call(widget.question.id, nextVal.toString());
        },
        child: SizedBox(
          width: starIconSize,
          height: starIconSize,
          child: () {
            if (starIndex <= filledFull) return buildFilledIcon(starIconSize);
            if (starIndex == filledFull + 1 && hasHalf) return buildHalfIcon(starIconSize);
            return buildOutlineIcon(starIconSize);
          }(),
        ),
      ),
    );
  }

  Widget _buildCrumb(int index, int stars, int filledFull, bool hasHalf, bool allowHalf, ThemeData theme) {
    final int segIndex = index + 1;
    const double width = 24;
    const double height = 12;
    final Color base = theme.colorScheme.onSurface.withValues(alpha: 0.25);
    final Color active = theme.colorScheme.primary;

    final bool full = segIndex <= filledFull;
    final bool half = !full && (segIndex == filledFull + 1) && hasHalf;

    return MouseRegion(
      onExit: widget.mode == QuestionDisplayMode.readonly ? null : (_) {
        setState(() => _localHoverRatings[widget.question.id] = null);
      },
      onHover: widget.mode == QuestionDisplayMode.readonly ? null : (e) {
        double hv = segIndex.toDouble();
        if (allowHalf && e.localPosition.dx <= width / 2) hv = segIndex - 0.5;
        setState(() => _localHoverRatings[widget.question.id] = hv.clamp(allowHalf ? 0.5 : 1.0, stars.toDouble()));
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: widget.mode == QuestionDisplayMode.readonly ? null : (details) {
          double nextVal = segIndex.toDouble();
          if (allowHalf && details.localPosition.dx <= width / 2) {
            nextVal = (segIndex - 0.5).clamp(0.5, stars.toDouble());
          }
          widget.onRatingChanged?.call(widget.question.id, nextVal.toString());
        },
        child: SizedBox(
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
        ),
      ),
    );
  }

  Widget _buildMatrixWidget() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Text(
      '矩阵题暂不支持预览',
      style: TextStyle(color: isDark ? Colors.white : Colors.black87),
    );
  }

  String _getOptionKey(int questionId, int optionIndex) {
    return 'q${questionId}_opt$optionIndex';
  }

  void _defaultMediaOpen(int index, String url, List<String> allUrls) {
    Navigator.push(
      context,
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.transparent,
        transitionDuration: const Duration(milliseconds: 150),
        reverseTransitionDuration: const Duration(milliseconds: 150),
        pageBuilder: (context, animation, secondaryAnimation) => FullscreenMediaViewer(
          mediaUrl: url,
          title: '问卷媒体',
          allMediaUrls: allUrls,
          currentIndex: index,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: child,
          );
        },
      ),
    );
  }
}
