import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:file_picker/file_picker.dart';
import '/pages/survey_preview_page.dart';
import '../models/question.dart';
import '../models/survey.dart';
import '../services/api_service.dart';
import '../main.dart' show isDesktop;
import 'package:cached_network_image/cached_network_image.dart';

class EditSurveyContentPage extends StatefulWidget {
  final String token;
  final Survey survey;

  const EditSurveyContentPage({
    super.key,
    required this.token,
    required this.survey,
  });

  @override
  State<EditSurveyContentPage> createState() => _EditSurveyContentPageState();
}

class _EditSurveyContentPageState extends State<EditSurveyContentPage> {
  late final ApiService _apiService;
  List<Question> _questions = [];
  bool _isLoading = false;
  String? _desktopBackground;
  String? _mobileBackground;

  @override
  void initState() {
    super.initState();
    _apiService = ApiService(authToken: widget.token);
    _loadQuestions();
    _loadBackground();
  }

  Future<void> _loadQuestions() async {
    setState(() => _isLoading = true);
    try {
      final questions = await _apiService.getSurveyQuestions(widget.survey.id);
      setState(() {
        _questions = questions;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      showFToast(
        context: context,
        alignment: FToastAlignment.bottomRight,
        title: const Text('加载失败'),
        description: Text('加载问题失败: \\${e.toString()}'),
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
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadBackground() async {
    try {
      final backgroundData = await _apiService.getSurveyBackground(widget.survey.id);
      setState(() {
        _desktopBackground = backgroundData['desktopBackground'] as String?;
        _mobileBackground = backgroundData['mobileBackground'] as String?;
      });
    } catch (e) {
      // 如果获取背景失败，使用默认值（空）
      
    }
  }

  Future<void> _addQuestion() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditQuestionPage(
          token: widget.token,
          surveyId: widget.survey.id,
        ),
      ),
    );

    if (result == true) {
      _loadQuestions();
    }
  }

  Future<void> _editQuestion(Question question) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditQuestionPage(
          token: widget.token,
          surveyId: widget.survey.id,
          question: question,
        ),
      ),
    );

    if (result == true) {
      _loadQuestions();
    }
  }

  Future<void> _deleteQuestion(Question question) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => FDialog(
        direction: Axis.horizontal,
        title: const Text('确认删除'),
        body: const Text('确定要删除这个问题吗？此操作不可恢复。'),
        actions: [
          FButton(
            style: FButtonStyle.outline,
            intrinsicWidth: true,
            child: const Text('取消'),
            onPress: () => Navigator.pop(context),
          ),
          FButton(
            intrinsicWidth: true,
            child: const Text('删除'),
            onPress: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _apiService.deleteQuestion(widget.survey.id, question.id);
        _loadQuestions();
      } catch (e) {
        if (!mounted) return;
        showFToast(
          context: context,
          alignment: FToastAlignment.bottomRight,
          title: const Text('删除失败'),
          description: Text('删除问题失败: \\${e.toString()}'),
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

  Future<void> _uploadBackground(bool isDesktop) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        if (file.path != null) {
          final url = await _apiService.uploadMedia(widget.survey.id, file.path!);
          setState(() {
            if (isDesktop) {
              _desktopBackground = url;
            } else {
              _mobileBackground = url;
            }
          });
          await _apiService.updateSurveyBackground(
            widget.survey.id,
            desktopBackground: _desktopBackground,
            mobileBackground: _mobileBackground,
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      showFToast(
        context: context,
        alignment: FToastAlignment.bottomRight,
        title: const Text('上传失败'),
        description: Text('上传背景图片失败: \\${e.toString()}'),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Column(
            children: [
              if (isDesktop)
                const SizedBox(height: 40),
              FHeader.nested(
                title: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('编辑问卷内容'),
                  ],
                ),
                prefixes: [
                  FHeaderAction(
                    icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                    onPress: () => Navigator.pop(context),
                  ),
                ],
                suffixes: [
                  FHeaderAction(
                    icon: const Icon(Icons.visibility, size: 20),
                    onPress: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => SurveyPreviewPage(
                            survey: widget.survey,
                            token: widget.token,
                            questions: _questions,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          Card(
                            elevation: 2,
                            color: Theme.of(context).brightness == Brightness.dark
                                ? Colors.transparent
                                : Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: Theme.of(context).brightness == Brightness.dark
                                    ? Colors.white.withAlpha(25)
                                    : Colors.black.withAlpha(25),
                                width: 1,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    '问卷背景设置',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Text('桌面端背景'),
                                            const SizedBox(height: 8),
                                            if (_desktopBackground != null && _desktopBackground!.isNotEmpty)
                                              Container(
                                                width: double.infinity,
                                                height: 500,
                                                margin: const EdgeInsets.only(bottom: 8),
                                                decoration: BoxDecoration(
                                                  borderRadius: BorderRadius.circular(8),
                                                  border: Border.all(color: Colors.grey.shade300),
                                                ),
                                                child: ClipRRect(
                                                  borderRadius: BorderRadius.circular(8),
                                                  child: CachedNetworkImage(
                                                    imageUrl: _desktopBackground!,
                                                    fit: BoxFit.cover,
                                                    imageBuilder: (context, imageProvider) => Image(image: imageProvider, fit: BoxFit.cover),
                                                    progressIndicatorBuilder: (context, url, progress) => Center(child: CircularProgressIndicator(value: progress.progress)),
                                                    errorWidget: (context, url, error) => Container(
                                                      color: Colors.grey.shade200,
                                                      child: const Icon(Icons.error),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                        
                                            FButton(
                                              style: FButtonStyle.outline,
                                              onPress: () => _uploadBackground(true),
                                              child: const Text('上传背景图片'),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Text('移动端背景'),
                                            const SizedBox(height: 8),
                                            if (_mobileBackground != null && _mobileBackground!.isNotEmpty)
                                              Container(
                                                width: double.infinity,
                                                height: 500,
                                                margin: const EdgeInsets.only(bottom: 8),
                                                decoration: BoxDecoration(
                                                  borderRadius: BorderRadius.circular(8),
                                                  border: Border.all(color: Colors.grey.shade300),
                                                ),
                                                child: ClipRRect(
                                                  borderRadius: BorderRadius.circular(8),
                                                  child: CachedNetworkImage(
                                                    imageUrl: _mobileBackground!,
                                                    fit: BoxFit.cover,
                                                    imageBuilder: (context, imageProvider) => Image(image: imageProvider, fit: BoxFit.cover),
                                                    progressIndicatorBuilder: (context, url, progress) => Center(child: CircularProgressIndicator(value: progress.progress)),
                                                    errorWidget: (context, url, error) => Container(
                                                      color: Colors.grey.shade200,
                                                      child: const Icon(Icons.error),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            FButton(
                                              style: FButtonStyle.outline,
                                              onPress: () => _uploadBackground(false),
                                              child: const Text('上传背景图片'),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          ..._questions.map((question) => Card(
                            elevation: 2,
                            color: Theme.of(context).brightness == Brightness.dark
                                ? Colors.transparent
                                : Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: Theme.of(context).brightness == Brightness.dark
                                    ? Colors.white.withAlpha(25)
                                    : Colors.black.withAlpha(25),
                                width: 1,
                              ),
                            ),
                            child: ListTile(
                              title: Text(question.title),
                              subtitle: Text(_getQuestionTypeText(question.type)),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit),
                                    onPressed: () => _editQuestion(question),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete),
                                    onPressed: () => _deleteQuestion(question),
                                  ),
                                ],
                              ),
                            ),
                          )),
                          const SizedBox(height: 16),
                          FButton(
                            onPress: _addQuestion,
                            child: const Text('添加问题'),
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

  String _getQuestionTypeText(QuestionType type) {
    switch (type) {
      case QuestionType.singleChoice:
        return '单选题';
      case QuestionType.multipleChoice:
        return '多选题';
      case QuestionType.slider:
        return '滑块题';
      case QuestionType.matrix:
        return '矩阵题';
    }
  }
}

class EditQuestionPage extends StatefulWidget {
  final String token;
  final int surveyId;
  final Question? question;

  const EditQuestionPage({
    super.key,
    required this.token,
    required this.surveyId,
    this.question,
  });

  @override
  State<EditQuestionPage> createState() => _EditQuestionPageState();
}

class _EditQuestionPageState extends State<EditQuestionPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _minValueController = TextEditingController();
  final _maxValueController = TextEditingController();
  final _initialValueController = TextEditingController();
  final _minLabelController = TextEditingController();
  final _maxLabelController = TextEditingController();
  late final ApiService _apiService;
  late QuestionType _selectedType;
  final List<QuestionOption> _options = [];
  final List<String> _mediaUrls = [];
  final Map<int, int> _jumpLogic = {};
  bool _required = true;
  bool _isLoading = false;
  
  // 滑块相关属性
  double _minValue = 0.0;
  double _maxValue = 100.0;
  double _initialValue = 50.0;
  String _minLabel = '最小值';
  String _maxLabel = '最大值';

  List<Question> _allQuestions = [];

  @override
  void initState() {
    super.initState();
    _apiService = ApiService(authToken: widget.token);
    _loadAllQuestions();
    if (widget.question != null) {
      _titleController.text = widget.question!.title;
      _selectedType = widget.question!.type;
      _options.addAll(widget.question!.options);
      _mediaUrls.addAll(widget.question!.mediaUrls);
      _jumpLogic.addAll(widget.question!.jumpLogic);
      _required = widget.question!.required;
      
      // 如果是滑块题，初始化滑块值
      if (_selectedType == QuestionType.slider && _options.isNotEmpty) {
        _minValue = double.tryParse(_options[0].text) ?? 0.0;
        _maxValue = double.tryParse(_options[1].text) ?? 100.0;
        _initialValue = double.tryParse(_options[2].text) ?? 50.0;
        if (_options.length > 3) {
          _minLabel = _options[3].text;
          _maxLabel = _options[4].text;
        }
        _minValueController.text = _minValue.toStringAsFixed(2);
        _maxValueController.text = _maxValue.toStringAsFixed(2);
        _initialValueController.text = _initialValue.toStringAsFixed(2);
        _minLabelController.text = _minLabel;
        _maxLabelController.text = _maxLabel;
      }
    } else {
      _selectedType = QuestionType.singleChoice;
      _minValueController.text = _minValue.toStringAsFixed(2);
      _maxValueController.text = _maxValue.toStringAsFixed(2);
      _initialValueController.text = _initialValue.toStringAsFixed(2);
      _minLabelController.text = _minLabel;
      _maxLabelController.text = _maxLabel;
    }
  }

  Future<void> _loadAllQuestions() async {
    try {
      final questions = await _apiService.getSurveyQuestions(widget.surveyId);
      setState(() {
        _allQuestions = questions;
      });
    } catch (e) {
      if (!mounted) return;
      showFToast(
        context: context,
        alignment: FToastAlignment.bottomRight,
        title: const Text('加载失败'),
        description: Text('加载问题列表失败: \\${e.toString()}'),
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

  @override
  void dispose() {
    _titleController.dispose();
    _minValueController.dispose();
    _maxValueController.dispose();
    _initialValueController.dispose();
    _minLabelController.dispose();
    _maxLabelController.dispose();
    super.dispose();
  }

  Future<void> _addOption() async {
    final result = await showDialog<QuestionOption>(
      context: context,
      builder: (context) => AddOptionDialog(),
    );

    if (result != null) {
      setState(() {
        _options.add(result);
      });
    }
  }

  Future<void> _editOption(QuestionOption option) async {
    final result = await showDialog<QuestionOption>(
      context: context,
      builder: (context) => AddOptionDialog(option: option),
    );

    if (result != null) {
      setState(() {
        final index = _options.indexWhere((o) => o.id == option.id);
        if (index != -1) {
          _options[index] = result;
        }
      });
    }
  }

  Future<void> _deleteOption(QuestionOption option) async {
    setState(() {
      _options.removeWhere((o) => o.id == option.id);
      _jumpLogic.remove(option.id);
    });
  }

  Future<void> _uploadMedia() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.media,
        allowMultiple: true,
      );

      if (result != null && result.files.isNotEmpty) {
        for (final file in result.files) {
          if (file.path != null) {
            final url = await _apiService.uploadMedia(widget.surveyId, file.path!);
            setState(() {
              _mediaUrls.add(url);
            });
          }
        }
      }
    } catch (e) {
      if (!mounted) return;
      showFToast(
        context: context,
        alignment: FToastAlignment.bottomRight,
        title: const Text('上传失败'),
        description: Text('上传媒体文件失败: \\${e.toString()}'),
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

  Future<void> _deleteMedia(String url) async {
    setState(() {
      _mediaUrls.remove(url);
    });
  }

  Future<void> _setJumpLogic(QuestionOption option) async {
    final result = await showDialog<int>(
      context: context,
      builder: (context) => JumpLogicDialog(
        currentQuestionId: widget.question?.id ?? 0,
        questions: _allQuestions,
        currentOptionId: option.id,
        currentJumpTo: _jumpLogic[option.id],
      ),
    );

    if (result != null) {
      setState(() {
        _jumpLogic[option.id] = result;
      });
    }
  }

  Future<void> _saveQuestion() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      List<QuestionOption> finalOptions = [];
      
      // 如果是滑块题，保存滑块配置
      if (_selectedType == QuestionType.slider) {
        final minValue = double.tryParse(_minValueController.text) ?? 0.0;
        final maxValue = double.tryParse(_maxValueController.text) ?? 100.0;
        final initialValue = double.tryParse(_initialValueController.text) ?? 50.0;
        final minLabel = _minLabelController.text;
        final maxLabel = _maxLabelController.text;
        if (minValue >= maxValue) {
          throw Exception('最小值必须小于最大值');
        }
        if (initialValue < minValue || initialValue > maxValue) {
          throw Exception('初始值必须在最小值和最大值之间');
        }
        finalOptions = [
          QuestionOption(id: 1, text: minValue.toString()),
          QuestionOption(id: 2, text: maxValue.toString()),
          QuestionOption(id: 3, text: initialValue.toString()),
          QuestionOption(id: 4, text: (minLabel).isNotEmpty ? minLabel : '最小值'),
          QuestionOption(id: 5, text: (maxLabel).isNotEmpty ? maxLabel : '最大值'),
        ];
      } else {
        finalOptions = _options;
      }

      final question = Question(
        id: widget.question?.id ?? 0,
        title: _titleController.text,
        type: _selectedType,
        options: finalOptions,
        mediaUrls: _mediaUrls,
        jumpLogic: _jumpLogic,
        required: _required,
        order: widget.question?.order ?? _options.length,
      );

      if (widget.question == null) {
        await _apiService.addQuestion(widget.surveyId, question);
      } else {
        await _apiService.updateQuestion(widget.surveyId, question);
      }

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      showFToast(
        context: context,
        alignment: FToastAlignment.bottomRight,
        title: const Text('保存失败'),
        description: Text('保存问题失败: \\${e.toString()}'),
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
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          if (isDesktop)
            const SizedBox(height: 40),
          FHeader.nested(
            title: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(widget.question == null ? '添加问题' : '编辑问题'),
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
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  FTextFormField(
                    controller: _titleController,
                    label: const Text('问题标题'),
                    hint: '请输入问题标题',
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return '请输入问题标题';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  FSelect<QuestionType>(
                    label: const Text('问题类型'),
                    format: (value) => _getQuestionTypeText(value),
                    initialValue: _selectedType,
                    onChange: (value) {
                      if (value != null) {
                        setState(() {
                          _selectedType = value;
                        });
                      }
                    },
                    children: [
                      FSelectItem('单选题', QuestionType.singleChoice),
                      FSelectItem('多选题', QuestionType.multipleChoice),
                      FSelectItem('滑块题', QuestionType.slider),
                      FSelectItem('矩阵题', QuestionType.matrix),
                    ],
                  ),
                  if (_selectedType == QuestionType.slider) ...[
                    const SizedBox(height: 16),
                    FTextFormField(
                      controller: _minValueController,
                      label: const Text('最小值'),
                      hint: '请输入最小值',
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return '请输入最小值';
                        }
                        final number = double.tryParse(value);
                        if (number == null) {
                          return '请输入有效的数字';
                        }
                        return null;
                      },
                      onEditingComplete: () { setState(() {}); },
                    ),
                    const SizedBox(height: 16),
                    FTextFormField(
                      controller: _maxValueController,
                      label: const Text('最大值'),
                      hint: '请输入最大值',
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return '请输入最大值';
                        }
                        final number = double.tryParse(value);
                        if (number == null) {
                          return '请输入有效的数字';
                        }
                        return null;
                      },
                      onEditingComplete: () { setState(() {}); },
                    ),
                    const SizedBox(height: 16),
                    FTextFormField(
                      controller: _initialValueController,
                      label: const Text('初始值'),
                      hint: '请输入初始值',
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return '请输入初始值';
                        }
                        final number = double.tryParse(value);
                        if (number == null) {
                          return '请输入有效的数字';
                        }
                        return null;
                      },
                      onEditingComplete: () { setState(() {}); },
                    ),
                    const SizedBox(height: 16),
                    FTextFormField(
                      label: const Text('最小值标签'),
                      hint: '请输入最小值标签',
                      controller: _minLabelController,
                      onEditingComplete: () { setState(() {}); },
                    ),
                    const SizedBox(height: 16),
                    FTextFormField(
                      label: const Text('最大值标签'),
                      hint: '请输入最大值标签',
                      controller: _maxLabelController,
                      onEditingComplete: () { setState(() {}); },
                    ),
                    const SizedBox(height: 16),
                    FSlider(
                      label: Text('当前值: ${_initialValueController.text}'),
                      description: Text('范围: ${_minLabelController.text} - ${_maxLabelController.text}'),
                      controller: FContinuousSliderController(
                        selection: FSliderSelection(
                          max: (() {
                            final min = double.tryParse(_minValueController.text) ?? 0.0;
                            final max = double.tryParse(_maxValueController.text) ?? 100.0;
                            final init = double.tryParse(_initialValueController.text) ?? 50.0;
                            return ((init - min) / (max - min)).clamp(0.0, 1.0);
                          })(),
                        ),
                      ),
                      marks: [
                        FSliderMark(value: 0, label: Text(_minLabelController.text)),
                        FSliderMark(
                          value: 0.5,
                          label: Text(
                            (((double.tryParse(_maxValueController.text) ?? 100.0) + (double.tryParse(_minValueController.text) ?? 0.0)) / 2).toStringAsFixed(2)
                          ),
                        ),
                        FSliderMark(value: 1, label: Text(_maxLabelController.text)),
                      ],
                      onChange: (value) {
                        // 不实时setState
                      },
                    ),
                  ] else if (_selectedType != QuestionType.slider) ...[
                    const SizedBox(height: 16),
                    const Text('选项列表'),
                    const SizedBox(height: 8),
                    ..._options.map((option) => ListTile(
                      title: Text(option.text),
                      subtitle: option.mediaUrl != null
                          ? CachedNetworkImage(
                              imageUrl: option.mediaUrl!,
                              height: 100,
                              errorWidget: (context, url, error) => Container(
                                color: Colors.grey.shade200,
                                height: 100,
                                child: const Icon(Icons.error),
                              )
                            )
                          : null,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_selectedType == QuestionType.singleChoice ||
                              _selectedType == QuestionType.multipleChoice)
                            IconButton(
                              icon: const Icon(Icons.call_split),
                              onPressed: () => _setJumpLogic(option),
                            ),
                          IconButton(
                            icon: const Icon(Icons.edit),
                            onPressed: () => _editOption(option),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete),
                            onPressed: () => _deleteOption(option),
                          ),
                        ],
                      ),
                    )),
                    FButton(
                      style: FButtonStyle.outline,
                      onPress: _addOption,
                      child: const Text('添加选项'),
                    ),
                  ],
                  const SizedBox(height: 16),
                  const Text('媒体文件'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _mediaUrls.map((url) {
                      final isImage = url.toLowerCase().endsWith('.jpg') ||
                          url.toLowerCase().endsWith('.jpeg') ||
                          url.toLowerCase().endsWith('.png');
                      final isVideo = url.toLowerCase().endsWith('.mp4');
                      final isAudio = url.toLowerCase().endsWith('.mp3');

                      return Stack(
                        children: [
                          Container(
                            width: 100,
                            height: 100,
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: isImage
                                ? CachedNetworkImage(
                                    imageUrl: url,
                                    fit: BoxFit.cover,
                                    imageBuilder: (context, imageProvider) => Image(image: imageProvider, fit: BoxFit.cover),
                                    progressIndicatorBuilder: (context, url, progress) => Center(child: CircularProgressIndicator(value: progress.progress)),
                                    errorWidget: (context, url, error) => Container(
                                      color: Colors.grey.shade200,
                                      child: const Icon(Icons.error),
                                    ),
                                  )
                                : isVideo
                                    ? const Icon(Icons.video_file, size: 40)
                                    : isAudio
                                        ? const Icon(Icons.audio_file, size: 40)
                                        : const Icon(Icons.file_present, size: 40),
                          ),
                          Positioned(
                            top: 0,
                            right: 0,
                            child: IconButton(
                              icon: const Icon(Icons.close, color: Colors.red),
                              onPressed: () => _deleteMedia(url),
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 8),
                  FButton(
                    style: FButtonStyle.outline,
                    onPress: _uploadMedia,
                    child: const Text('上传媒体文件'),
                  ),
                  const SizedBox(height: 16),
                  FSwitch(
                    label: const Text('必答题'),
                    value: _required,
                    onChange: (value) {
                      setState(() {
                        _required = value;
                      });
                    },
                  ),
                  const SizedBox(height: 24),
                  FButton(
                    onPress: _isLoading ? null : _saveQuestion,
                    child: _isLoading
                        ? const CircularProgressIndicator()
                        : const Text('保存问题'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getQuestionTypeText(QuestionType type) {
    switch (type) {
      case QuestionType.singleChoice:
        return '单选题';
      case QuestionType.multipleChoice:
        return '多选题';
      case QuestionType.slider:
        return '滑块题';
      case QuestionType.matrix:
        return '矩阵题';
    }
  }
}

class AddOptionDialog extends StatefulWidget {
  final QuestionOption? option;

  const AddOptionDialog({super.key, this.option});

  @override
  State<AddOptionDialog> createState() => _AddOptionDialogState();
}

class _AddOptionDialogState extends State<AddOptionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _textController = TextEditingController();
  String? _mediaUrl;

  @override
  void initState() {
    super.initState();
    if (widget.option != null) {
      _textController.text = widget.option!.text;
      _mediaUrl = widget.option!.mediaUrl;
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FDialog(
      direction: Axis.horizontal,
      title: Text(widget.option == null ? '添加选项' : '编辑选项'),
      body: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FTextFormField(
              controller: _textController,
              label: const Text('选项文本'),
              hint: '请输入选项文本',
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return '请输入选项文本';
                }
                return null;
              },
            ),
            if (_mediaUrl != null) ...[
              const SizedBox(height: 16),
              CachedNetworkImage(
                imageUrl: _mediaUrl!,
                height: 100,
                errorWidget: (context, url, error) => Container(
                  color: Colors.grey.shade200,
                  height: 100,
                  child: const Icon(Icons.error),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        FButton(
          style: FButtonStyle.outline,
          intrinsicWidth: true,
          child: const Text('取消'),
          onPress: () => Navigator.pop(context),
        ),
        FButton(
          intrinsicWidth: true,
          child: const Text('确定'),
          onPress: () {
            if (_formKey.currentState!.validate()) {
              Navigator.pop(
                context,
                QuestionOption(
                  id: widget.option?.id ?? DateTime.now().millisecondsSinceEpoch,
                  text: _textController.text,
                  mediaUrl: _mediaUrl,
                ),
              );
            }
          },
        ),
      ],
    );
  }
}

class JumpLogicDialog extends StatefulWidget {
  final int currentQuestionId;
  final List<Question> questions;
  final int currentOptionId;
  final int? currentJumpTo;

  const JumpLogicDialog({
    super.key,
    required this.currentQuestionId,
    required this.questions,
    required this.currentOptionId,
    this.currentJumpTo,
  });

  @override
  State<JumpLogicDialog> createState() => _JumpLogicDialogState();
}

class _JumpLogicDialogState extends State<JumpLogicDialog> {
  int? _selectedQuestionId;

  @override
  void initState() {
    super.initState();
    _selectedQuestionId = widget.currentJumpTo;
  }

  @override
  Widget build(BuildContext context) {
    return FDialog(
      direction: Axis.horizontal,
      title: const Text('设置跳题逻辑'),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('选择跳转到的问题：'),
          const SizedBox(height: 16),
          FSelect<int>(
            format: (value) {
              final question = widget.questions.firstWhere(
                (q) => q.id == value,
                orElse: () => Question(
                  id: 0,
                  title: '未知问题',
                  type: QuestionType.singleChoice,
                  options: [],
                  required: true,
                  order: 0,
                ),
              );
              return question.title;
            },
            initialValue: _selectedQuestionId,
            onChange: (value) {
              setState(() {
                _selectedQuestionId = value;
              });
            },
            children: widget.questions
                .where((q) => q.id != widget.currentQuestionId)
                .map((q) => FSelectItem(q.title, q.id))
                .toList(),
          ),
        ],
      ),
      actions: [
        FButton(
          style: FButtonStyle.outline,
          intrinsicWidth: true,
          child: const Text('取消'),
          onPress: () => Navigator.pop(context),
        ),
        FButton(
          intrinsicWidth: true,
          child: const Text('确定'),
          onPress: () => Navigator.pop(context, _selectedQuestionId),
        ),
      ],
    );
  }
}