import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import '../utils/error_formatter.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../services/api_service.dart';
import '../models/question.dart';
import '../controllers/survey_runtime.dart';
import '../components/glass_card.dart';
import '../components/adaptive_message_card.dart';
import '../components/glass_button.dart';
import '../widgets/question_display_widget.dart';
import 'fullscreen_media_viewer.dart';
import '../widgets/frosted_glass_background.dart';
import '../widgets/top_safe_spacer.dart';
import '../components/loading_indicator.dart';
import '../services/config.dart';

class PublicSurveyPage extends StatefulWidget {
  final String surveyUID;

  const PublicSurveyPage({
    super.key,
    required this.surveyUID,
  });

  @override
  State<PublicSurveyPage> createState() => _PublicSurveyPageState();
}

class _PublicSurveyPageState extends State<PublicSurveyPage> {
  late ApiService _apiService;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final ScrollController _scrollController = ScrollController();
  
  String surveyName = '';
  String description = '';
  List<Question> questions = [];
  SurveyRuntimeController? _runtime;
  final Map<String, bool> _optionStates = {};
  String? _desktopBackground;
  String? _mobileBackground;
  bool autoSubmit = false;
  bool allowAnonymous = false;
  
  bool isLoading = true;
  bool isSubmitting = false;
  String? errorMessage;
  bool isSubmitted = false;
  final Map<int, double?> _hoverRatings = {};
  bool _backgroundLoaded = false;
  
  // 存储自定义填写选项的输入内容：key: questionId_optionIndex, value: 输入文本
  final Map<String, String> _customInputValues = {};
  // 记录哪些问题有自定义填写选项被选中
  final Set<int> _questionsWithCustomInput = {};

  @override
  void initState() {
    super.initState();
    _initializeAndLoad();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _apiService.dispose();
    super.dispose();
  }

  Future<void> _initializeAndLoad() async {
    try {
      final token = await _storage.read(key: 'auth_token');
      _apiService = ApiService(authToken: token ?? '');
      await _loadSurvey();
    } catch (e) {
      if (!mounted) return;
      showFToast(
        context: context,
        alignment: FToastAlignment.bottomRight,
        title: const Text('初始化失败'),
        description: Text(ErrorFormatter.format(e)),
      );
      Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
    }
  }

  Future<void> _loadSurvey() async {
    try {
      setState(() {
        isLoading = true;
        errorMessage = null;
      });

      final data = await _apiService.getPublicSurvey(widget.surveyUID);
      
      setState(() {
        surveyName = data['surveyName'] ?? '';
        description = data['description'] ?? '';
        _desktopBackground = data['desktopBackground'] as String?;
        _mobileBackground = data['mobileBackground'] as String?;
        autoSubmit = data['autoSubmit'] ?? false;
        allowAnonymous = data['allowAnonymous'] ?? false;
        
        final questionsData = data['questions'] as List? ?? [];
        questions = questionsData.map((q) {
          List<QuestionOption> options = [];
          try {
            final optionsData = q['options'];
            if (optionsData is List) {
              options = optionsData.map((o) => QuestionOption.fromJson(o)).toList();
            } else if (optionsData is String) {
              // JSON字符串格式
              final optionsList = json.decode(optionsData) as List;
              options = optionsList.map((o) => QuestionOption.fromJson(o)).toList();
            }
          } catch (e) {
            if (kDebugMode) {
              print('解析选项失败: $e');
            }
          }

          // 解析媒体URLs
          List<String> mediaUrls = [];
          try {
            final mediaUrlsData = q['mediaUrls'];
            if (mediaUrlsData is List) {
              mediaUrls = mediaUrlsData.cast<String>();
            }
          } catch (e) {
            // 解析媒体URL失败，使用空列表
            if (kDebugMode) {
              print('解析媒体URL失败: $e');
            }
          }

          return Question(
            id: q['id'] ?? 0,
            title: q['title'] ?? '',
            type: _parseQuestionType(q['questionType'] ?? 1),
            options: options,
            required: q['required'] ?? true,
            order: q['order'] ?? 0,
            mediaUrls: mediaUrls,
            imageScale: (q['imageScale'] as num?)?.toDouble() ?? 1.0,
          );
        }).toList();
        
        questions.sort((a, b) => a.order.compareTo(b.order));
        
        _runtime = SurveyRuntimeController(
          questions: questions,
          multiJumpStrategy: MultiJumpStrategy.first,
        );
        _runtime!.recomputeVisible();
        
        isLoading = false;
      });
      
      await Future.delayed(const Duration(milliseconds: 50));
      if (!mounted) return;
      setState(() {
        _backgroundLoaded = true;
      });
    } on TokenExpired catch (_) {
      if (!mounted) return;
      showFToast(
        context: context,
        alignment: FToastAlignment.bottomRight,
        title: const Text('登录过期'),
        description: const Text('登录已过期，请重新登录'),
      );
      Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
    } catch (e) {
      setState(() {
        isLoading = false;
        errorMessage = ErrorFormatter.format(e);
        _backgroundLoaded = true;
      });
    }
  }

  QuestionType _parseQuestionType(int type) {
    switch (type) {
      case 1:
        return QuestionType.singleChoice;
      case 2:
        return QuestionType.multipleChoice;
      case 3:
        return QuestionType.slider;
      case 4:
        return QuestionType.textInput;
      default:
        return QuestionType.singleChoice;
    }
  }

  String _getOptionKey(int questionId, int optionIndex) {
    return 'q${questionId}_opt$optionIndex';
  }

  void _updateSingleChoiceAnswer(int questionId, String option, int optionIndex) {
    setState(() {
      for (int i = 0; i < questions.firstWhere((q) => q.id == questionId).options.length; i++) {
        _optionStates[_getOptionKey(questionId, i)] = false;
      }
      _optionStates[_getOptionKey(questionId, optionIndex)] = true;
      
      _runtime?.setAnswerSingle(questionId, option);
      _runtime?.recomputeVisible();
      
      // 检查是否选中了自定义填写选项
      if (option == '__custom_input__') {
        _questionsWithCustomInput.add(questionId);
      } else {
        _questionsWithCustomInput.remove(questionId);
      }
    });
    
    _scrollToBottom();
    // 如果选中的是自定义填写选项，不触发自动提交
    if (option != '__custom_input__') {
      _checkAutoSubmit();
    }
  }

  void _updateMultipleChoiceAnswer(int questionId, String option, int optionIndex, bool isSelected) {
    setState(() {
      _optionStates[_getOptionKey(questionId, optionIndex)] = !isSelected;
      
      _runtime?.toggleMultiple(questionId, option, !isSelected);
      _runtime?.recomputeVisible();
      
      // 检查是否选中了自定义填写选项
      if (option == '__custom_input__') {
        if (!isSelected) {
          _questionsWithCustomInput.add(questionId);
        } else {
          _questionsWithCustomInput.remove(questionId);
        }
      }
    });
    
    _scrollToBottom();
    // 如果选中的是自定义填写选项，不触发自动提交
    if (option != '__custom_input__') {
      _checkAutoSubmit();
    }
  }

  void _updateTextInputAnswer(int questionId, String value) {
    setState(() {
      _runtime?.setAnswerSingle(questionId, value);
      _runtime?.recomputeVisible();
    });
    _checkAutoSubmit();
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

  bool _areAllRequiredQuestionsAnswered() {
    if (_runtime == null) return false;
    
    // 检查所有必答题是否都已回答（不仅限于当前可见的题目）
    for (final question in questions) {
      if (question.required) {
        final answer = _runtime!.answers[question.id];
        if (answer == null || answer.isEmpty) {
          return false;
        }
      }
    }
    return true;
  }

  void _checkAutoSubmit() {
    if (!autoSubmit || isSubmitting || isSubmitted) return;
    
    // 如果有问题选中了自定义填写选项，不触发自动提交
    if (_questionsWithCustomInput.isNotEmpty) return;
    
    // 延迟检查，避免在状态更新过程中触发
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_areAllRequiredQuestionsAnswered()) {
        _submitAnswers();
      }
    });
  }


  Future<void> _submitAnswers() async {
    for (final question in questions.where((q) => _runtime!.visibleQuestionIds.contains(q.id))) {
      final a = _runtime!.answers[question.id];
      if (question.required && (a == null || a.isEmpty)) {
        showFToast(
          context: context,
          alignment: FToastAlignment.bottomRight,
          title: const Text('提示'),
          description: Text('请回答必答题: ${question.title}'),
          suffixBuilder: (context, entry, _) => IntrinsicHeight(
            child: FButton(
              style: context.theme.buttonStyles.primary.copyWith(
                contentStyle: context.theme.buttonStyles.primary.contentStyle.copyWith(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7.5),
                  textStyle: FWidgetStateMap.all(
                    context.theme.typography.xs.copyWith(color: context.theme.colors.primaryForeground),
                  ),
                ),
              ),
              onPress: entry.dismiss,
              child: const Text('关闭'),
            ),
          ),
        );
        return;
      }
    }

    try {
      setState(() {
        isSubmitting = true;
      });

      // 构造答案，附带 indices（仅对有选项的题型提供）
      final answers = <Map<String, dynamic>>[];
      for (final q in questions) {
        final qid = q.id;
        final texts = List<String>.from(_runtime!.answers[qid] ?? <String>[]);
        List<int>? indices;
        
        // 仅对单选/多选题计算索引
        if (q.type == QuestionType.singleChoice || q.type == QuestionType.multipleChoice) {
          final idxList = <int>[];
          final customInputParts = <String>[]; // 存储自定义填写内容
          
          for (final e in q.options.asMap().entries) {
            final optionIndex = e.key;
            final option = e.value;
            final key = _getOptionKey(qid, optionIndex);
            final selected = _optionStates[key] ?? false;
            
            if (selected) {
              idxList.add(optionIndex);
              
              // 如果是自定义填写选项，添加用户输入
              if (option.text == '__custom_input__') {
                final customKey = '${qid}_$optionIndex';
                final customValue = _customInputValues[customKey] ?? '';
                if (customValue.isNotEmpty) {
                  // 格式: __custom_input__:选项索引:用户输入
                  customInputParts.add('__custom_input__:$optionIndex:$customValue');
                }
              }
            }
          }
          
          if (idxList.isNotEmpty) {
            indices = idxList;
          }
          
          if (customInputParts.isNotEmpty) {
            texts.addAll(customInputParts);
          }
        }
        
        final item = <String, dynamic>{
          'questionId': qid,
          'answer': texts,
        };
        if (indices != null) item['indices'] = indices;
        answers.add(item);
      }

      final submitData = {
        'answers': answers,
      };

      await _apiService.submitPublicAnswer(widget.surveyUID, submitData);
      
      setState(() {
        isSubmitted = true;
        isSubmitting = false;
      });

      if (mounted) {
        showFToast(
          context: context,
          alignment: FToastAlignment.bottomRight,
          title: const Text('成功'),
          description: const Text('问卷提交成功！'),
        );
      }
    } on TokenExpired catch (_) {
      if (!mounted) return;
      setState(() {
        isSubmitting = false;
      });
      // 如果允许匿名提交，不需要跳转到登录页面
      if (!allowAnonymous) {
        showFToast(
          context: context,
          alignment: FToastAlignment.bottomRight,
          title: const Text('登录过期'),
          description: const Text('登录已过期，请重新登录'),
        );
        Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
      } else {
        showFToast(
          context: context,
          alignment: FToastAlignment.bottomRight,
          title: const Text('提交失败'),
          description: const Text('网络错误，请稍后重试'),
        );
      }
    } catch (e) {
      setState(() {
        isSubmitting = false;
      });
      
      final errorStr = e.toString();
      if (errorStr.contains('403') || errorStr.contains('权限') || errorStr.contains('禁止')) {
        // 403错误：跳转到错误提示界面
        setState(() {
          errorMessage = '您可能没有权限提交此问卷或者达到提交次数限制';
        });
      } else if (errorStr.contains('404') || errorStr.contains('不存在')) {
        setState(() {
          errorMessage = '问卷不存在或已被删除';
        });
      } else if (errorStr.contains('网络') || errorStr.contains('连接')) {
        setState(() {
          errorMessage = '网络连接失败，请检查网络设置';
        });
      } else {
        // 其他错误：显示Toast提示
        if (mounted) {
          showFToast(
            context: context,
            alignment: FToastAlignment.bottomRight,
            title: const Text('提交失败'),
            description: Text(ErrorFormatter.format(e)),
            suffixBuilder: (context, entry, _) => IntrinsicHeight(
              child: FButton(
                style: context.theme.buttonStyles.primary.copyWith(
                  contentStyle: context.theme.buttonStyles.primary.contentStyle.copyWith(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7.5),
                    textStyle: FWidgetStateMap.all(
                      context.theme.typography.xs.copyWith(color: context.theme.colors.primaryForeground),
                    ),
                  ),
                ),
                onPress: entry.dismiss,
                child: const Text('关闭'),
              ),
            ),
          );
        }
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
            child: AnimatedOpacity(
              opacity: _backgroundLoaded ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeInOut,
              child: (_desktopBackground != null && _desktopBackground!.isNotEmpty) ||
                     (_mobileBackground != null && _mobileBackground!.isNotEmpty)
                  ? Container(
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
                          ? Container(color: Colors.black.withValues(alpha: 0.4))
                          : null,
                    )
                  : const FrostedGlassBackground(),
            ),
          ),

          Column(
            children: [
              const TopSafeSpacer(),
              FHeader.nested(
                title: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(surveyName.isNotEmpty ? surveyName : '问卷调查'),
                  ],
                ),
                prefixes: [
                  FHeaderAction(
                    icon: const Icon(Icons.close, size: 20),
                    onPress: () => _navigateToPublicAccess(),
                  ),
                ],
              ),
              Expanded(
                child: isLoading
                    ? const LoadingIndicator.page()
                    : errorMessage != null
                        ? _buildErrorView()
                        : isSubmitted
                            ? _buildSuccessView()
                            : _buildSurveyView(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AdaptiveMessageCard(
      cardWrapper: (content) => _buildGlassCard(child: content),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            'assets/images/loading.gif',
            width: 64,
            height: 64,
            color: Colors.red[400],
          ),
          const SizedBox(height: 16),
          Text(
            errorMessage!,
            style: TextStyle(
              fontSize: 16,
              color: isDark ? Colors.white : Colors.black87,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          GlassButton(
            text: '返回主界面',
            color: Colors.blue,
            onPressed: () => Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessView() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AdaptiveMessageCard(
      cardWrapper: (content) => _buildGlassCard(child: content),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, size: 64, color: Colors.green[400]),
          const SizedBox(height: 16),
          Text(
            '问卷提交成功！',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '感谢您的参与！',
            style: TextStyle(
              color: isDark ? Colors.white70 : Colors.black54,
            ),
          ),
          const SizedBox(height: 24),
          GlassButton(
            text: '返回',
            color: Colors.green,
            onPressed: () => _navigateToPublicAccess(),
          ),
        ],
      ),
    );
  }


  Widget _buildSurveyView() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    final visible = questions.where((q) => _runtime?.visibleQuestionIds.contains(q.id) ?? false).toList();

    return CustomScrollView(
      controller: _scrollController,
      cacheExtent: 800.0,
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
        if (description.isNotEmpty)
          _buildGlassCard(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    surveyName,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    description,
                    style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 16),

        ...visible.asMap().entries.map((entry) {
          final index = entry.key;
          final q = entry.value;
          return TweenAnimationBuilder<double>(
            duration: Duration(milliseconds: 500 + (index * 150)),
            tween: Tween(begin: 0.0, end: 1.0),
            curve: Curves.easeOutQuart,
            builder: (context, value, child) {
              return Transform.translate(
                offset: Offset(0, 30 * (1 - value)),
                child: Opacity(
                  opacity: value,
                  child: Transform.scale(
                    scale: 0.8 + (0.2 * value),
                    child: AnimatedSize(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.fastOutSlowIn,
                      alignment: Alignment.topCenter,
                      child: _buildGlassCard(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: QuestionDisplayWidget(
                              question: q,
                              mode: QuestionDisplayMode.interactive,
                              optionStates: _optionStates,
                              selectedAnswers: _runtime?.answers[q.id] ?? [],
                              hoverRatings: _hoverRatings,
                              onSingleChoiceChanged: _updateSingleChoiceAnswer,
                              onMultipleChoiceChanged: _updateMultipleChoiceAnswer,
                              onRatingChanged: (questionId, value) {
                                setState(() {
                                  _runtime?.setAnswerSingle(questionId, value);
                                  _runtime?.recomputeVisible();
                                });
                                _checkAutoSubmit();
                              },
                              onTextInputChanged: _updateTextInputAnswer,
                              onMediaOpen: (url, all, index) => _openFullscreenViewer(url, all, index),
                              customInputValues: _customInputValues,
                              onCustomInputChanged: (questionId, optionIndex, value) {
                                setState(() {
                                  final key = '${questionId}_$optionIndex';
                                  _customInputValues[key] = value;
                                });
                                // 自定义填写输入不触发自动提交
                              },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        }),

        if (_runtime?.ended == true)
          _buildGlassCard(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    '问卷已结束',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: 8),
                  Text('根据您的选择，问卷在此结束。您可以直接提交。'),
                ],
              ),
            ),
          ),
        
        // 提交按钮
        if (_areAllRequiredQuestionsAnswered())
          _buildGlassCard(
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Opacity(
                opacity: 0.77,
                child: ElevatedButton(
                  onPressed: isSubmitting ? null : _submitAnswers,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isDark ? Colors.blue[600] : Colors.blue[700],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: isSubmitting
                      ? const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            LoadingIndicator.button(
                            ),
                            SizedBox(width: 12),
                            Text('提交中...', style: TextStyle(fontSize: 16)),
                          ],
                        )
                      : const Text(
                          '提交问卷',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                ),
              ),
            ),
          ),
            ]),
          ),
        ),
      ],
    );
  }


  void _openFullscreenViewer(String mediaUrl, List<String> allMediaUrls, int currentIndex) {
    Navigator.push(
      context,
      PageRouteBuilder(
        opaque: false, // 允许下层页面透出
        barrierColor: Colors.transparent, // 不再额外叠加遮罩色
        transitionDuration: const Duration(milliseconds: 150),
        reverseTransitionDuration: const Duration(milliseconds: 150),
        pageBuilder: (context, animation, secondaryAnimation) => FullscreenMediaViewer(
          mediaUrl: mediaUrl,
          title: '问卷媒体',
          allMediaUrls: allMediaUrls,
          currentIndex: currentIndex,
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

  /// 玻璃卡片封装
  Widget _buildGlassCard({required Widget child}) {
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      blurSigma: 12,
      backgroundColor: CupertinoColors.white.withValues(alpha: 0.2),
      borderColor: CupertinoColors.white.withValues(alpha: 0.2),
      child: child,
    );
  }

  /// 导航到公开访问页面，避免Web端路由SecurityError
  void _navigateToPublicAccess() {
    Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
  }

}
