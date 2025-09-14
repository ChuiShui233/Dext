import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/survey.dart';
import '../models/question.dart';
import '../services/api_service.dart';
import '../controllers/survey_runtime.dart';

class SurveyPreviewPage extends StatefulWidget {
  final Survey survey;
  final String token;
  final List<Question> questions;

  const SurveyPreviewPage({
    super.key,
    required this.survey,
    required this.token,
    required this.questions,
  });

  @override
  State<SurveyPreviewPage> createState() => _SurveyPreviewPageState();
}

class _SurveyPreviewPageState extends State<SurveyPreviewPage> {
  late final ApiService _apiService;
  String? _desktopBackground;
  String? _mobileBackground;
  // 共享控制器
  late final SurveyRuntimeController _runtime;

  @override
  void initState() {
    super.initState();
    _apiService = ApiService(authToken: widget.token);
    _loadBackground();
    // 初始化共享控制器（默认 first 策略）并计算可见题
    _runtime = SurveyRuntimeController(
      questions: widget.questions,
      multiJumpStrategy: MultiJumpStrategy.first,
    );
    _runtime.recomputeVisible();
  }

  Future<void> _loadBackground() async {
    try {
      final backgroundData =
          await _apiService.getSurveyBackground(widget.survey.id);
      setState(() {
        _desktopBackground = backgroundData['desktopBackground'] as String?;
        _mobileBackground = backgroundData['mobileBackground'] as String?;
      });
    } catch (e) {
      debugPrint('获取问卷背景失败: $e');
      setState(() {
        _desktopBackground = null;
        _mobileBackground = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth > 800;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Stack(
        children: [
          // 背景层
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                image: DecorationImage(
                  image: NetworkImage(isWide
                      ? (_desktopBackground ?? '')
                      : (_mobileBackground ?? '')),
                  fit: BoxFit.cover,
                  onError: (_, __) {},
                ),
              ),
              child: isDark
                  ? Container(
                      color: Colors.black.withValues(alpha: 0.4),
                    )
                  : null,
            ),
          ),

          // 内容层
          Column(
            children: [
              const SizedBox(height: 40),
              FHeader.nested(
                title: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('问卷预览 - ${widget.survey.surveyName}'),
                  ],
                ),
                prefixes: [
                  FHeaderAction(
                    icon: const Icon(Icons.close, size: 20),
                    onPress: () => Navigator.pop(context),
                  ),
                ],
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // 问卷信息卡片
                    _buildGlassCard(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.survey.surveyName,
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white70 : Colors.black54,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              widget.survey.description,
                              style: TextStyle(
                                color: isDark ? Colors.white70 : Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 问题列表（仅渲染可见题，且支持点击模拟）
                    ...widget.questions
                        .where((q) => _runtime.visibleQuestionIds.contains(q.id) || _runtime.visibleQuestionIds.isEmpty && q.order == 0)
                        .map((q) => _buildGlassCard(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            q.title,
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                              color: isDark ? Colors.white : Colors.black87,
                                            ),
                                          ),
                                        ),
                                        if (q.required) const Text(' *', style: TextStyle(color: Colors.red)),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    if (q.mediaUrls.isNotEmpty)
                                      _buildGlassCard(
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
                                              _buildMediaWidgets(q.mediaUrls),
                                            ],
                                          ),
                                        ),
                                      ),
                                    const SizedBox(height: 12),
                                    _buildInteractivePreviewWidget(q),
                                  ],
                                ),
                              ),
                            )),

                    if (_runtime.ended)
                      _buildGlassCard(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text('问卷已结束', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                              SizedBox(height: 8),
                              Text('根据当前选择，问卷在此结束。'),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 玻璃卡片封装
  Widget _buildGlassCard({required Widget child}) {
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
              color: CupertinoColors.white.withAlpha(51),
              border: Border.all(
                color: CupertinoColors.white.withAlpha(51),
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

  Widget _buildMediaWidgets(List<String> mediaUrls) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: mediaUrls.map((url) {
        final isImage = url.toLowerCase().endsWith('.jpg') ||
            url.toLowerCase().endsWith('.jpeg') ||
            url.toLowerCase().endsWith('.png') ||
            url.toLowerCase().endsWith('.gif');
        final isVideo = url.toLowerCase().endsWith('.mp4') ||
            url.toLowerCase().endsWith('.avi') ||
            url.toLowerCase().endsWith('.mov');
        final isAudio = url.toLowerCase().endsWith('.mp3') ||
            url.toLowerCase().endsWith('.wav') ||
            url.toLowerCase().endsWith('.aac');

        return Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: isImage
                ? CachedNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.cover,
                    placeholder: (context, url) =>
                        const Center(child: CircularProgressIndicator()),
                    errorWidget: (context, url, error) =>
                        Container(color: Colors.grey.shade200, child: const Icon(Icons.error)),
                  )
                : isVideo
                    ? const Icon(Icons.video_file, size: 40)
                    : isAudio
                        ? const Icon(Icons.audio_file, size: 40)
                        : const Icon(Icons.file_present, size: 40),
          ),
        );
      }).toList(),
    );
  }
  // 交互式预览（可点击模拟跳题）
  Widget _buildInteractivePreviewWidget(Question q) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final borderColor = isDark ? Colors.grey[700]! : Colors.grey.shade300;
    final textColor = isDark ? Colors.white : Colors.black87;

    switch (q.type) {
      case QuestionType.singleChoice:
        final selected = (((_runtime.answers[q.id]?.isNotEmpty) ?? false) ? _runtime.answers[q.id]!.first : null);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: q.options.map((opt) {
            final isChecked = selected == opt.text;
            return InkWell(
              onTap: () {
                _runtime.setAnswerSingle(q.id, opt.text);
                _runtime.recomputeVisible();
                setState(() {});
              },
              child: _buildGlassCard(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      Radio<bool>(value: true, groupValue: isChecked, onChanged: (_) {}),
                      Expanded(child: Text(opt.text, style: TextStyle(color: textColor))),
                      if (opt.mediaUrl != null && opt.mediaUrl!.isNotEmpty)
                        Container(
                          width: 40,
                          height: 40,
                          margin: const EdgeInsets.only(left: 8),
                          decoration: BoxDecoration(
                            border: Border.all(color: borderColor),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: CachedNetworkImage(
                              imageUrl: opt.mediaUrl!,
                              fit: BoxFit.cover,
                              placeholder: (context, url) => const Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))),
                              errorWidget: (context, url, error) => const Icon(Icons.error, size: 16),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        );

      case QuestionType.multipleChoice:
        final current = _runtime.answers[q.id] ?? <String>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: q.options.map((opt) {
            final isOn = current.contains(opt.text);
            return InkWell(
              onTap: () {
                _runtime.toggleMultiple(q.id, opt.text, !isOn);
                _runtime.recomputeVisible();
                setState(() {});
              },
              child: _buildGlassCard(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      Checkbox(value: isOn, onChanged: (_) {}),
                      Expanded(child: Text(opt.text, style: TextStyle(color: textColor))),
                      if (opt.mediaUrl != null && opt.mediaUrl!.isNotEmpty)
                        Container(
                          width: 40,
                          height: 40,
                          margin: const EdgeInsets.only(left: 8),
                          decoration: BoxDecoration(
                            border: Border.all(color: borderColor),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: CachedNetworkImage(
                              imageUrl: opt.mediaUrl!,
                              fit: BoxFit.cover,
                              placeholder: (context, url) => const Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))),
                              errorWidget: (context, url, error) => const Icon(Icons.error, size: 16),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        );

      case QuestionType.slider:
        double min = 0, max = 100, initial = 50;
        String minLabel = '最小值', maxLabel = '最大值';
        if (q.options.length >= 5) {
          min = double.tryParse(q.options[0].text) ?? 0;
          max = double.tryParse(q.options[1].text) ?? 100;
          initial = double.tryParse(q.options[2].text) ?? 50;
          minLabel = q.options[3].text;
          maxLabel = q.options[4].text;
        }
        final current = ((_runtime.answers[q.id]?.isNotEmpty ?? false)
            ? double.tryParse(_runtime.answers[q.id]!.first) ?? initial
            : initial);
        final value = current.clamp(min, max);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Slider(
              value: value,
              min: min,
              max: max,
              onChanged: (v) {
                _runtime.setAnswerSingle(q.id, v.round().toString());
                _runtime.recomputeVisible();
                setState(() {});
              },
              activeColor: theme.colorScheme.primary,
              inactiveColor: theme.colorScheme.onSurface.withValues(alpha: 0.3),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(minLabel, style: TextStyle(color: textColor)),
                Text(maxLabel, style: TextStyle(color: textColor)),
              ],
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                '当前值: ${value.round()}',
                style: TextStyle(color: textColor, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        );

      case QuestionType.matrix:
        return Text('矩阵题暂不支持预览', style: TextStyle(color: textColor));
    }
  }
}
