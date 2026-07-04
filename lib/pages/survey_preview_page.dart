import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../widgets/top_safe_spacer.dart';
import 'package:forui/forui.dart';
import '../models/survey.dart';
import '../models/question.dart';
import '../services/api_service.dart';
import '../controllers/survey_runtime.dart';
import '../components/survey_continuous_layout.dart';
import '../components/survey_wizard_layout.dart';
import 'fullscreen_media_viewer.dart';
import '../widgets/frosted_glass_background.dart';
import '../services/config.dart';
import '../services/settings_service.dart';

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
  late final SurveyRuntimeController _runtime;
  final Map<String, bool> _optionStates = {};
  final Map<int, double?> _hoverRatings = {};
  final ScrollController _scrollController = ScrollController();
  bool _bgReady = false;

  @override
  void initState() {
    super.initState();
    _apiService = ApiService(authToken: widget.token);
    _loadBackground();
    _runtime = SurveyRuntimeController(
      questions: widget.questions,
      multiJumpStrategy: MultiJumpStrategy.first,
    );
    _runtime.recomputeVisible();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  Future<void> _loadBackground() async {
    try {
      final backgroundData =
          await _apiService.getSurveyBackground(widget.survey.id);
      if (!mounted) return;
      
      _desktopBackground = backgroundData['desktopBackground'] as String?;
      _mobileBackground = backgroundData['mobileBackground'] as String?;
      
      await _preloadBackground();
      
      if (!mounted) return;
      setState(() {
        _bgReady = true;
      });
    } catch (e) {
      debugPrint('获取问卷背景失败: $e');
      if (!mounted) return;
      setState(() {
        _desktopBackground = null;
        _mobileBackground = null;
        _bgReady = true;
      });
    }
  }

  Future<void> _preloadBackground() async {
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth > 800;
    final backgroundUrl = isWide ? _desktopBackground : _mobileBackground;
    
    if (backgroundUrl == null || backgroundUrl.isEmpty) {
      return;
    }
    
    try {
      final imageProvider = NetworkImage(toAbsoluteUrl(backgroundUrl));
      final completer = Completer<void>();
      final ImageStream stream = imageProvider.resolve(ImageConfiguration(
        devicePixelRatio: MediaQuery.of(context).devicePixelRatio,
      ));
      
      late ImageStreamListener listener;
      listener = ImageStreamListener(
        (ImageInfo info, bool synchronousCall) {
          completer.complete();
          stream.removeListener(listener);
        },
        onError: (exception, stackTrace) {
          if (kDebugMode) {
            print('背景图片加载失败: $exception');
          }
          completer.complete();
          stream.removeListener(listener);
        },
      );
      
      stream.addListener(listener);
      
      await completer.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          if (kDebugMode) {
            print('背景图片加载超时');
          }
          stream.removeListener(listener);
        },
      );
    } catch (e) {
      // 背景加载失败不影响问卷显示
      if (kDebugMode) {
        print('背景图片预加载失败: $e');
      }
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
          Positioned.fill(
            child: (_desktopBackground != null && _desktopBackground!.isNotEmpty) ||
                   (_mobileBackground != null && _mobileBackground!.isNotEmpty)
                ? TweenAnimationBuilder<double>(
                    duration: const Duration(milliseconds: 800),
                    curve: Curves.easeOutCubic,
                    tween: Tween(begin: _bgReady ? 0.0 : 1.0, end: 0.0),
                    builder: (context, value, child) {
                      return Transform.translate(
                        offset: Offset(MediaQuery.of(context).size.width * value, 0),
                        child: child,
                      );
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        image: DecorationImage(
                          image: NetworkImage(isWide
                              ? toAbsoluteUrl(_desktopBackground)
                              : toAbsoluteUrl(_mobileBackground)),
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
                  )
                : const FrostedGlassBackground(),
          ),

          Column(
            children: [
              const TopSafeSpacer(showBackground: true),
              Container(
                decoration: BoxDecoration(
                  color: isDark 
                      ? Colors.black.withAlpha(102).withAlpha(120)
                      : Colors.white.withAlpha(102).withAlpha(120),
                ),
                child: FHeader.nested(
                  title: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '问卷预览 - ${widget.survey.surveyName}',
                        style: TextStyle(
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                  prefixes: [
                    FHeaderAction(
                      icon: Icon(Icons.close, size: 20, color: isDark ? Colors.white70 : Colors.black87),
                      onPress: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _buildSurveyLayout(isDark),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 根据设置服务选择问卷布局
  Widget _buildSurveyLayout(bool isDark) {
    final useWizard =
        SettingsService().questionnaireLayout == SettingsService.layoutWizard;

    if (useWizard) {
      return SurveyWizardLayout(
        surveyName: widget.survey.surveyName,
        description: widget.survey.description,
        questions: widget.questions,
        runtime: _runtime,
        optionStates: _optionStates,
        hoverRatings: _hoverRatings,
        authToken: widget.token,
        isDark: isDark,
        onSingleChoiceChanged: _onSingleChoiceChanged,
        onMultipleChoiceChanged: _onMultipleChoiceChanged,
        onRatingChanged: _onRatingChanged,
        onTextInputChanged: _onTextInputChanged,
        onMediaOpen: _openFullscreenViewer,
      );
    }
    return SurveyContinuousLayout(
      surveyName: widget.survey.surveyName,
      description: widget.survey.description,
      questions: widget.questions,
      runtime: _runtime,
      optionStates: _optionStates,
      hoverRatings: _hoverRatings,
      authToken: widget.token,
      isDark: isDark,
      scrollController: _scrollController,
      onSingleChoiceChanged: _onSingleChoiceChanged,
      onMultipleChoiceChanged: _onMultipleChoiceChanged,
      onRatingChanged: _onRatingChanged,
      onTextInputChanged: _onTextInputChanged,
      onMediaOpen: _openFullscreenViewer,
    );
  }

  // === 答案变更回调 ===

  void _onSingleChoiceChanged(
      int questionId, String selectedOption, int optionIndex) {
    final q = widget.questions.firstWhere((q) => q.id == questionId);
    for (int i = 0; i < q.options.length; i++) {
      _optionStates[_getOptionKey(questionId, i)] = false;
    }
    _optionStates[_getOptionKey(questionId, optionIndex)] = true;
    _runtime.setAnswerSingle(questionId, q.options[optionIndex].id.toString());
    _runtime.recomputeVisible();
    setState(() {});
    _scrollToBottom();
  }

  void _onMultipleChoiceChanged(
      int questionId, String option, int optionIndex, bool isSelected) {
    final q = widget.questions.firstWhere((q) => q.id == questionId);
    _optionStates[_getOptionKey(questionId, optionIndex)] = !isSelected;
    final texts = <String>[];
    for (int i = 0; i < q.options.length; i++) {
      if (_optionStates[_getOptionKey(questionId, i)] ?? false) {
        texts.add(q.options[i].id.toString());
      }
    }
    _runtime.setAnswerMultiple(questionId, texts);
    _runtime.recomputeVisible();
    setState(() {});
    _scrollToBottom();
  }

  void _onRatingChanged(int questionId, String value) {
    _runtime.setAnswerSingle(questionId, value);
    _runtime.recomputeVisible();
    setState(() {});
    _scrollToBottom();
  }

  void _onTextInputChanged(int questionId, String value) {
    _runtime.setAnswerSingle(questionId, value);
    _runtime.recomputeVisible();
    setState(() {});
    _scrollToBottom();
  }


  void _openFullscreenViewer(String mediaUrl, List<String> allMediaUrls, int currentIndex, {VideoPlayerController? controller}) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false, // 允许下层页面透出
        barrierColor: Colors.black54, // 半透明黑色背景
        transitionDuration: const Duration(milliseconds: 400),
        reverseTransitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (context, animation, secondaryAnimation) => FullscreenMediaViewer(
          mediaUrl: mediaUrl,
          title: '问卷媒体',
          allMediaUrls: allMediaUrls,
          currentIndex: currentIndex,
          authToken: widget.token,
          externalVideoController: controller,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          // 组合动画：缩放 + 淡入 + 轻微位移
          final scaleAnimation = Tween<double>(
            begin: 0.8,
            end: 1.0,
          ).animate(CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          ));

          final fadeAnimation = Tween<double>(
            begin: 0.0,
            end: 1.0,
          ).animate(CurvedAnimation(
            parent: animation,
            curve: const Interval(0.0, 0.8, curve: Curves.easeOut),
          ));

          final slideAnimation = Tween<Offset>(
            begin: const Offset(0.0, 0.1),
            end: Offset.zero,
          ).animate(CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          ));

          return SlideTransition(
            position: slideAnimation,
            child: ScaleTransition(
              scale: scaleAnimation,
              child: FadeTransition(
                opacity: fadeAnimation,
                child: child,
              ),
            ),
          );
        },
      ),
    );
  }


  // 选项键：题目ID + 索引
  String _getOptionKey(int questionId, int optionIndex) => 'q${questionId}_opt$optionIndex';
}
