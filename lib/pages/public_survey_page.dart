import 'dart:convert';
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/api_service.dart';
import '../models/question.dart';
import '../controllers/survey_runtime.dart';
import 'public_access_page.dart';

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
  
  String surveyName = '';
  String description = '';
  List<Question> questions = [];
  SurveyRuntimeController? _runtime;
  final Map<String, bool> _optionStates = {}; // 独立的选项状态管理
  String? _desktopBackground;
  String? _mobileBackground;
  // 运行时状态与路径由控制器维护
  
  bool isLoading = true;
  bool isSubmitting = false;
  String? errorMessage;
  bool isSubmitted = false;

  @override
  void initState() {
    super.initState();
    _initializeAndLoad();
  }

  Future<void> _initializeAndLoad() async {
    try {
      final token = await _storage.read(key: 'auth_token');
      if (token == null || token.isEmpty) {
        if (mounted) {
          showFToast(
            context: context,
            alignment: FToastAlignment.bottomRight,
            title: const Text('需要登录'),
            description: const Text('请先登录再访问问卷'),
          );
          Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
        }
        return;
      }
      _apiService = ApiService(authToken: token);
      await _loadSurvey();
    } catch (e) {
      if (!mounted) return;
      showFToast(
        context: context,
        alignment: FToastAlignment.bottomRight,
        title: const Text('初始化失败'),
        description: Text('初始化失败: $e'),
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
        
        // 解析问题数据
        final questionsData = data['questions'] as List? ?? [];
        questions = questionsData.map((q) {
          // 解析选项
          List<QuestionOption> options = [];
          try {
            final optionsData = q['options'];
            if (optionsData is List) {
              // 直接是数组格式
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
            print('解析媒体URLs失败: $e');
          }

          return Question(
            id: q['id'] ?? 0,
            title: q['title'] ?? '',
            type: _parseQuestionType(q['questionType'] ?? 1),
            options: options,
            required: q['required'] ?? true,
            order: q['order'] ?? 0,
            mediaUrls: mediaUrls,
          );
        }).toList();
        
        // 按顺序排序
        questions.sort((a, b) => a.order.compareTo(b.order));
        
        // 初始化共享运行时控制器并计算可见题
        _runtime = SurveyRuntimeController(
          questions: questions,
          multiJumpStrategy: MultiJumpStrategy.first,
        );
        _runtime!.recomputeVisible();
        
        isLoading = false;
      });
    } on TokenExpiredException catch (_) {
      if (!mounted) return;
      showFToast(
        context: context,
        alignment: FToastAlignment.bottomRight,
        title: const Text('登录过期'),
        description: const Text('登录已过期，请重新登录后再试'),
      );
      Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
    } catch (e) {
      setState(() {
        errorMessage = '加载问卷失败: $e';
        isLoading = false;
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
        return QuestionType.matrix;
      default:
        return QuestionType.singleChoice;
    }
  }

  // 生成选项的唯一键
  String _getOptionKey(int questionId, int optionIndex) {
    return 'q${questionId}_opt$optionIndex';
  }

  // 更新单选题答案
  void _updateSingleChoiceAnswer(int questionId, String selectedOption, int optionIndex) {
    setState(() {
      // 清除该问题的所有选项状态
      final questionOptions = questions.firstWhere((q) => q.id == questionId).options;
      for (int i = 0; i < questionOptions.length; i++) {
        _optionStates[_getOptionKey(questionId, i)] = false;
      }
      
      // 设置选中的选项状态
      _optionStates[_getOptionKey(questionId, optionIndex)] = true;
      
      // 更新答案并重算可见问题
      _runtime?.setAnswerSingle(questionId, selectedOption);
      _runtime?.recomputeVisible();
    });
  }

  // 更新多选题答案
  void _updateMultipleChoiceAnswer(int questionId, String option, int optionIndex, bool isSelected) {
    setState(() {
      // 更新选项状态
      _optionStates[_getOptionKey(questionId, optionIndex)] = !isSelected;
      
      // 更新答案并重算可见问题
      _runtime?.toggleMultiple(questionId, option, !isSelected);
      _runtime?.recomputeVisible();
    });
  }

  void _updateAnswer(int questionId, List<String> selectedOptions) {
    setState(() {
      _runtime?.setAnswerMultiple(questionId, selectedOptions);
      _runtime?.recomputeVisible();
    });
  }


  Future<void> _submitAnswers() async {
    // 验证必答题（仅校验可见题）
    for (final question in questions.where((q) => _runtime!.visibleQuestionIds.contains(q.id))) {
      final a = _runtime!.answers[question.id];
      if (question.required && (a == null || a.isEmpty)) {
        showFToast(
          context: context,
          alignment: FToastAlignment.bottomRight,
          title: const Text('提示'),
          description: Text('请回答必答题: ${question.title}'),
        );
        return;
      }
    }

    try {
      setState(() {
        isSubmitting = true;
      });

      final submitData = {
        'answers': _runtime!.answers.entries.map((entry) => {
          'questionId': entry.key,
          'answer': entry.value,
        }).toList(),
      };

      await _apiService.submitPublicAnswer(widget.surveyUID, submitData);
      
      setState(() {
        isSubmitted = true;
        isSubmitting = false;
      });

      showFToast(
        context: context,
        alignment: FToastAlignment.bottomRight,
        title: const Text('成功'),
        description: const Text('问卷提交成功！'),
      );
    } on TokenExpiredException catch (_) {
      if (!mounted) return;
      setState(() {
        isSubmitting = false;
      });
      showFToast(
        context: context,
        alignment: FToastAlignment.bottomRight,
        title: const Text('登录过期'),
        description: const Text('登录已过期，请重新登录'),
      );
      Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
    } catch (e) {
      setState(() {
        isSubmitting = false;
      });
      
      showFToast(
        context: context,
        alignment: FToastAlignment.bottomRight,
        title: const Text('提交失败'),
        description: Text('提交失败: $e'),
      );
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
                image: (_desktopBackground != null && _desktopBackground!.isNotEmpty) ||
                       (_mobileBackground != null && _mobileBackground!.isNotEmpty)
                    ? DecorationImage(
                        image: NetworkImage(isWide
                            ? (_desktopBackground ?? '')
                            : (_mobileBackground ?? '')),
                        fit: BoxFit.cover,
                        onError: (_, __) {},
                      )
                    : null,
                gradient: (_desktopBackground == null || _desktopBackground!.isEmpty) &&
                          (_mobileBackground == null || _mobileBackground!.isEmpty)
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: isDark
                            ? [Colors.grey[900]!, Colors.grey[800]!]
                            : [Colors.blue[50]!, Colors.indigo[100]!],
                      )
                    : null,
              ),
              child: isDark
                  ? Container(
                      color: Colors.black.withOpacity(0.4),
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
                    ? const Center(child: CircularProgressIndicator())
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
    return Center(
      child: _buildGlassCard(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 64, color: Colors.red[400]),
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
              ElevatedButton(
                onPressed: _loadSurvey,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[600],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSuccessView() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: _buildGlassCard(
        child: Padding(
          padding: const EdgeInsets.all(32),
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
              ElevatedButton(
                onPressed: () => _navigateToPublicAccess(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green[600],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('返回'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSurveyView() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    final visible = questions.where((q) => _runtime?.visibleQuestionIds.contains(q.id) ?? false).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 问卷信息卡片
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

        // 问题列表（仅渲染可见题）
        ...visible.map((q) => _buildGlassCard(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _buildQuestionWidget(q),
              ),
            )),

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
        _buildGlassCard(
          child: Padding(
            padding: const EdgeInsets.all(4),
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
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
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
      ],
    );
  }

  Widget _buildQuestionWidget(Question question) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                question.title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ),
            if (question.required)
              const Text(' *', style: TextStyle(color: Colors.red)),
          ],
        ),
        const SizedBox(height: 12),

        // 媒体区域
        if (question.mediaUrls.isNotEmpty)
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
                  _buildMediaWidgets(question.mediaUrls),
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),
        
        _buildAnswerWidget(question),
      ],
    );
  }

  Widget _buildAnswerWidget(Question question) {
    switch (question.type) {
      case QuestionType.singleChoice:
        return _buildSingleChoiceWidget(question);
      case QuestionType.multipleChoice:
        return _buildMultipleChoiceWidget(question);
      case QuestionType.slider:
        return _buildSliderWidget(question);
      case QuestionType.matrix:
        return _buildMatrixWidget(question);
    }
  }

  Widget _buildSingleChoiceWidget(Question question) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: question.options.asMap().entries.map((entry) {
        final int index = entry.key;
        final opt = entry.value;
        final optionKey = _getOptionKey(question.id, index);
        final isSelected = _optionStates[optionKey] ?? false;
        
        return _buildGlassCard(
          child: InkWell(
            onTap: () {
              _updateSingleChoiceAnswer(question.id, opt.text, index);
            },
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Radio<bool>(
                    value: true, 
                    groupValue: isSelected ? true : null, 
                    onChanged: (value) {
                      _updateSingleChoiceAnswer(question.id, opt.text, index);
                    }
                  ),
                  Expanded(
                    child: Text(
                      opt.text, 
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      )
                    )
                  ),
                  if (opt.mediaUrl != null && opt.mediaUrl!.isNotEmpty)
                    Container(
                      width: 40,
                      height: 40,
                      margin: const EdgeInsets.only(left: 8),
                      decoration: BoxDecoration(
                        border: Border.all(color: isDark ? Colors.grey[700]! : Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: CachedNetworkImage(
                          imageUrl: opt.mediaUrl!,
                          fit: BoxFit.cover,
                          placeholder: (context, url) =>
                              const Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))),
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
  }

  Widget _buildMultipleChoiceWidget(Question question) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: question.options.asMap().entries.map((entry) {
        final int index = entry.key;
        final opt = entry.value;
        final optionKey = _getOptionKey(question.id, index);
        final isSelected = _optionStates[optionKey] ?? false;
        
        return _buildGlassCard(
          child: InkWell(
            onTap: () {
              _updateMultipleChoiceAnswer(question.id, opt.text, index, isSelected);
            },
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Checkbox(
                    value: isSelected, 
                    onChanged: (checked) {
                      _updateMultipleChoiceAnswer(question.id, opt.text, index, isSelected);
                    }
                  ),
                  Expanded(
                    child: Text(
                      opt.text, 
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      )
                    )
                  ),
                  if (opt.mediaUrl != null && opt.mediaUrl!.isNotEmpty)
                    Container(
                      width: 40,
                      height: 40,
                      margin: const EdgeInsets.only(left: 8),
                      decoration: BoxDecoration(
                        border: Border.all(color: isDark ? Colors.grey[700]! : Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: CachedNetworkImage(
                          imageUrl: opt.mediaUrl!,
                          fit: BoxFit.cover,
                          placeholder: (context, url) =>
                              const Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))),
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
  }

  Widget _buildSliderWidget(Question question) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final theme = Theme.of(context);
    final value = (_runtime?.answers[question.id]?.isNotEmpty == true)
        ? double.tryParse(_runtime!.answers[question.id]!.first) ?? 50.0
        : 50.0;

    double min = 0, max = 100;
    String minLabel = '最小值', maxLabel = '最大值';
    if (question.options.length >= 5) {
      min = double.tryParse(question.options[0].text) ?? 0;
      max = double.tryParse(question.options[1].text) ?? 100;
      minLabel = question.options[3].text;
      maxLabel = question.options[4].text;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          onChanged: (newValue) {
            _updateAnswer(question.id, [newValue.round().toString()]);
          },
          activeColor: theme.colorScheme.primary,
          inactiveColor: theme.colorScheme.onSurface.withOpacity(0.3),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(minLabel, style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
            Text(maxLabel, style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
          ],
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            '当前值: ${value.round()}',
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMatrixWidget(Question question) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Column(
      children: question.options.map((option) {
        return _buildGlassCard(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    option.text,
                    style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                  ),
                ),
                Switch(
                  value: _runtime?.answers[question.id]?.contains(option.text) ?? false,
                  onChanged: (checked) {
                    final currentAnswers = _runtime?.answers[question.id] ?? [];
                    final newAnswers = List<String>.from(currentAnswers);
                    if (checked) {
                      if (!newAnswers.contains(option.text)) {
                        newAnswers.add(option.text);
                      }
                    } else {
                      newAnswers.remove(option.text);
                    }
                    _updateAnswer(question.id, newAnswers);
                  },
                ),
              ],
            ),
          ),
        );
      }).toList(),
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

  /// 玻璃卡片封装
  Widget _buildGlassCard({required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            decoration: BoxDecoration(
              color: CupertinoColors.white.withOpacity(0.2),
              border: Border.all(
                color: CupertinoColors.white.withOpacity(0.2),
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

  /// 导航到公开访问页面，避免Web端路由SecurityError
  void _navigateToPublicAccess() {
    if (kIsWeb) {
      // Web平台直接使用MaterialPageRoute替换当前页面
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => const PublicAccessPage(),
          settings: const RouteSettings(name: '/public/access'),
        ),
      );
    } else {
      // 移动平台使用路由导航
      Navigator.pushNamedAndRemoveUntil(context, '/public/access', (route) => false);
    }
  }

  @override
  void dispose() {
    _apiService.dispose();
    super.dispose();
  }
}
