// file: edit_question_page.dart

import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../models/question.dart';
import '../services/api_service.dart';
import '../main.dart' show isDesktop;


// ###########################################################################
// ## Edit Question Page
// ###########################################################################

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

    _selectedType = widget.question?.type ?? QuestionType.singleChoice;

    if (widget.question != null) {
      _titleController.text = widget.question!.title;
      _options.addAll(widget.question!.options);
      _mediaUrls.addAll(widget.question!.mediaUrls);
      _jumpLogic.addAll(widget.question!.jumpLogic);
      // 将已有的选项目的地同步到跳题表，或将跳题表同步回选项
      for (int i = 0; i < _options.length; i++) {
        final opt = _options[i];
        final jl = _jumpLogic[opt.id];
        if (opt.destination == null && jl != null) {
          _options[i] = opt.copyWith(destination: jl);
        } else if (opt.destination != null && jl == null) {
          _jumpLogic[opt.id] = opt.destination!;
        }
      }
      _required = widget.question!.required;

      if (_selectedType == QuestionType.slider && _options.length >= 5) {
        _minValue = double.tryParse(_options[0].text) ?? 0.0;
        _maxValue = double.tryParse(_options[1].text) ?? 100.0;
        _initialValue = double.tryParse(_options[2].text) ?? 50.0;
        _minLabel = _options[3].text;
        _maxLabel = _options[4].text;
      }
    }

    _minValueController.text = _minValue.toStringAsFixed(2);
    _maxValueController.text = _maxValue.toStringAsFixed(2);
    _initialValueController.text = _initialValue.toStringAsFixed(2);
    _minLabelController.text = _minLabel;
    _maxLabelController.text = _maxLabel;
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

  Future<void> _loadAllQuestions() async {
    try {
      final questions = await _apiService.getSurveyQuestions(widget.surveyId);
      setState(() {
        _allQuestions = questions;
      });
    } catch (e) {
      if (!mounted) return;
      _showErrorToast('加载问题列表失败', e.toString());
    }
  }

  // 批量为当前题的所有选项设置相同的跳转目标
  Future<void> _batchSetJump() async {
    if (_options.isEmpty) return;
    final result = await showDialog<int>(
      context: context,
      builder: (context) => JumpLogicDialog(
        currentQuestionId: widget.question?.id ?? 0,
        questions: _allQuestions,
        currentOptionId: -1,
        currentJumpTo: null,
      ),
    );
    if (result == null) return;
    setState(() {
      final newDest = (result == -1) ? null : result;
      for (int i = 0; i < _options.length; i++) {
        final opt = _options[i];
        _options[i] = opt.copyWith(destination: newDest);
        if (newDest == null) {
          _jumpLogic.remove(opt.id);
        } else {
          _jumpLogic[opt.id] = newDest;
        }
      }
    });
  }

  Future<void> _addOption() async {
    final result = await showDialog<QuestionOption>(
      context: context,
      builder: (context) => AddOptionDialog(
        apiService: _apiService,
        surveyId: widget.surveyId,
      ),
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
      builder: (context) => AddOptionDialog(
        option: option,
        apiService: _apiService,
        surveyId: widget.surveyId,
      ),
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
      _showErrorToast('上传媒体文件失败', e.toString());
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
        // -1 代表无跳转/结束问卷：这里统一视为清空目的地
        final newDest = (result == -1) ? null : result;
        final idx = _options.indexWhere((o) => o.id == option.id);
        if (idx != -1) {
          _options[idx] = _options[idx].copyWith(destination: newDest);
        }

        if (newDest == null) {
          _jumpLogic.remove(option.id);
        } else {
          _jumpLogic[option.id] = newDest;
        }
      });
    }
  }

  Future<void> _saveQuestion() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      List<QuestionOption> finalOptions;

      if (_selectedType == QuestionType.slider) {
        final minValue = double.parse(_minValueController.text);
        final maxValue = double.parse(_maxValueController.text);
        final initialValue = double.parse(_initialValueController.text);
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
        order: widget.question?.order ?? _allQuestions.length,
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
      _showErrorToast('保存问题失败', e.toString());
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showErrorToast(String title, String message) {
    showFToast(
      context: context,
      alignment: FToastAlignment.bottomRight,
      title: Text(title),
      description: Text(message),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          SizedBox(height: isDesktop ? 40 : 20),
          FHeader.nested(
            title: Text(widget.question == null ? '添加问题' : '编辑问题'),
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
                    validator: (value) => (value == null || value.isEmpty) ? '请输入问题标题' : null,
                  ),
                  const SizedBox(height: 16),
                  FSelect<QuestionType>(
                    label: const Text('问题类型'),
                    format: (value) => _getQuestionTypeText(value),
                    initialValue: _selectedType,
                    onChange: (value) {
                      if (value != null) setState(() => _selectedType = value);
                    },
                    children: QuestionType.values
                        .map((type) => FSelectItem(_getQuestionTypeText(type), type))
                        .toList(),
                  ),
                  const SizedBox(height: 16),
                  if (_selectedType == QuestionType.slider)
                    _buildSliderSettings()
                  else
                    _buildOptionsSettings(),
                  const SizedBox(height: 16),
                  _buildMediaSettings(),
                  const SizedBox(height: 16),
                  FSwitch(
                    label: const Text('必答题'),
                    value: _required,
                    onChange: (value) => setState(() => _required = value),
                  ),
                  const SizedBox(height: 24),
                  FButton(
                    onPress: _isLoading ? null : _saveQuestion,
                    child: _isLoading ? const CircularProgressIndicator() : const Text('保存问题'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSliderSettings() {
    return Column(
      children: [
        FTextFormField(
          controller: _minValueController,
          label: const Text('最小值'),
          hint: '请输入最小值',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autovalidateMode: AutovalidateMode.onUserInteraction,
          validator: (value) => (value == null || double.tryParse(value) == null) ? '请输入有效的数字' : null,
          onEditingComplete: () => setState(() {}),
        ),
        const SizedBox(height: 16),
        FTextFormField(
          controller: _maxValueController,
          label: const Text('最大值'),
          hint: '请输入最大值',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autovalidateMode: AutovalidateMode.onUserInteraction,
          validator: (value) => (value == null || double.tryParse(value) == null) ? '请输入有效的数字' : null,
          onEditingComplete: () => setState(() {}),
        ),
        const SizedBox(height: 16),
        FTextFormField(
          controller: _initialValueController,
          label: const Text('初始值'),
          hint: '请输入初始值',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autovalidateMode: AutovalidateMode.onUserInteraction,
          validator: (value) => (value == null || double.tryParse(value) == null) ? '请输入有效的数字' : null,
          onEditingComplete: () => setState(() {}),
        ),
        const SizedBox(height: 16),
        FTextFormField(
          label: const Text('最小值标签'),
          hint: '请输入最小值标签',
          controller: _minLabelController,
          onEditingComplete: () => setState(() {}),
        ),
        const SizedBox(height: 16),
        FTextFormField(
          label: const Text('最大值标签'),
          hint: '请输入最大值标签',
          controller: _maxLabelController,
          onEditingComplete: () => setState(() {}),
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
                return max > min ? ((init - min) / (max - min)).clamp(0.0, 1.0) : 0.0;
              })(),
            ),
          ),
          marks: [
            FSliderMark(value: 0, label: Text(_minLabelController.text)),
            FSliderMark(value: 1, label: Text(_maxLabelController.text)),
          ],
        ),
      ],
    );
  }

  Widget _buildOptionsSettings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('选项列表'),
            Row(children: [
              if (_selectedType == QuestionType.singleChoice)
                FButton(
                  style: FButtonStyle.outline,
                  onPress: _batchSetJump,
                  child: const Text('批量设置跳转'),
                ),
            ]),
          ],
        ),
        const SizedBox(height: 8),
        ..._options.map((option) => ListTile(
          title: Text(option.text),
          subtitle: ((option.mediaUrl != null && option.mediaUrl!.isNotEmpty) || _jumpLogic.containsKey(option.id))
              ? Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (option.mediaUrl != null && option.mediaUrl!.isNotEmpty)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: CachedNetworkImage(
                            imageUrl: option.mediaUrl!,
                            height: 100,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            alignment: Alignment.centerLeft,
                            errorWidget: (context, url, error) => Container(
                              color: Colors.grey.shade200,
                              height: 100,
                              child: const Icon(Icons.error),
                            ),
                          ),
                        ),
                      if (_jumpLogic.containsKey(option.id))
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            () {
                              final targetId = _jumpLogic[option.id]!;
                              final target = _allQuestions.firstWhere(
                                (q) => q.id == targetId,
                                orElse: () => Question(id: 0, title: '（未知）', type: QuestionType.singleChoice, options: [], required: true, order: 0),
                              );
                              return '跳转至：第${target.order + 1}题 ${target.title}';
                            }(),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                    ],
                  ),
                )
              : null,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_selectedType == QuestionType.singleChoice)
                IconButton(
                  tooltip: "设置跳题逻辑",
                  icon: Icon(Icons.call_split, color: _jumpLogic.containsKey(option.id) ? Theme.of(context).primaryColor : null),
                  onPressed: () => _setJumpLogic(option),
                ),
              if (_selectedType == QuestionType.singleChoice)
                IconButton(
                  tooltip: "清除跳转",
                  icon: const Icon(Icons.clear_all),
                  onPressed: () {
                    setState(() {
                      final idx = _options.indexWhere((o) => o.id == option.id);
                      if (idx != -1) {
                        _options[idx] = _options[idx].copyWith(destination: null);
                      }
                      _jumpLogic.remove(option.id);
                    });
                  },
                ),
              IconButton(icon: const Icon(Icons.edit), onPressed: () => _editOption(option)),
              IconButton(icon: const Icon(Icons.delete), onPressed: () => _deleteOption(option)),
            ],
          ),
        )),
        FButton(
          style: FButtonStyle.outline,
          onPress: _addOption,
          child: const Text('添加选项'),
        ),
      ],
    );
  }

  Widget _buildMediaSettings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('问题媒体文件（视频/图片/音频）'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _mediaUrls.map((url) {
            Widget mediaIcon;
            if (url.toLowerCase().endsWith('.jpg') || url.toLowerCase().endsWith('.jpeg') || url.toLowerCase().endsWith('.png')) {
              mediaIcon = CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                progressIndicatorBuilder: (context, url, progress) => Center(child: CircularProgressIndicator(value: progress.progress)),
                errorWidget: (context, url, error) => const Icon(Icons.error),
              );
            } else if (url.toLowerCase().endsWith('.mp4')) {
              mediaIcon = const Center(child: Icon(Icons.video_file, size: 40));
            } else if (url.toLowerCase().endsWith('.mp3')) {
              mediaIcon = const Center(child: Icon(Icons.audio_file, size: 40));
            } else {
              mediaIcon = const Center(child: Icon(Icons.file_present, size: 40));
            }

            return Stack(
              children: [
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ClipRRect(borderRadius: BorderRadius.circular(7), child: mediaIcon),
                ),
                Positioned(
                  top: -12,
                  right: -12,
                  child: IconButton(
                    icon: const Icon(Icons.cancel, color: Colors.red),
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
      ],
    );
  }

  String _getQuestionTypeText(QuestionType type) {
    switch (type) {
      case QuestionType.singleChoice: return '单选题';
      case QuestionType.multipleChoice: return '多选题';
      case QuestionType.slider: return '滑块题';
      case QuestionType.matrix: return '矩阵题';
    }
  }
}


// ###########################################################################
// ## Helper Dialogs
// ###########################################################################

class AddOptionDialog extends StatefulWidget {
  final QuestionOption? option;
  final ApiService apiService;
  final int surveyId;

  const AddOptionDialog({
    super.key,
    this.option,
    required this.apiService,
    required this.surveyId,
  });

  @override
  State<AddOptionDialog> createState() => _AddOptionDialogState();
}

class _AddOptionDialogState extends State<AddOptionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _textController = TextEditingController();
  String? _mediaUrl;
  bool _isUploading = false;
  String? _uploadError;

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

  Future<void> _pickAndUploadMedia() async {
    setState(() {
      _isUploading = true;
      _uploadError = null;
    });

    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.media);
      if (result != null && result.files.single.path != null) {
        final filePath = result.files.single.path!;
        final url = await widget.apiService.uploadMedia(widget.surveyId, filePath);
        if (mounted) {
          setState(() {
            _mediaUrl = url;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _uploadError = '上传失败: ${e.toString()}';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  void _removeMedia() {
    setState(() {
      _mediaUrl = null;
    });
  }

  Widget _buildMediaPreview(String url) {
    if (url.toLowerCase().endsWith('.jpg') || url.toLowerCase().endsWith('.jpeg') || url.toLowerCase().endsWith('.png')) {
      return CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        progressIndicatorBuilder: (context, url, progress) => Center(child: CircularProgressIndicator(value: progress.progress)),
        errorWidget: (context, url, error) => const Icon(Icons.error),
      );
    // ###################### FIX START ######################
    // Remove Center widget to align icons to the top-left.
    // Add Padding for better visual spacing.
    } else if (url.toLowerCase().endsWith('.mp4')) {
      return const Padding(
        padding: EdgeInsets.all(8.0),
        child: Icon(Icons.video_file, size: 50),
      );
    } else if (url.toLowerCase().endsWith('.mp3')) {
      return const Padding(
        padding: EdgeInsets.all(8.0),
        child: Icon(Icons.audio_file, size: 50),
      );
    } else {
      return const Padding(
        padding: EdgeInsets.all(8.0),
        child: Icon(Icons.file_present, size: 50),
      );
    }
    // ####################### FIX END #######################
  }

  Widget _buildMediaSection() {
    if (_isUploading) {
      return const SizedBox(
        height: 100,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_mediaUrl != null && _mediaUrl!.isNotEmpty) {
      return Column(
        // ###################### FIX START ######################
        // Align the content of this column (text and media) to the left.
        crossAxisAlignment: CrossAxisAlignment.start,
        // ####################### FIX END #######################
        children: [
          const Text('选项媒体文件'),
          const SizedBox(height: 8),
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: _buildMediaPreview(_mediaUrl!),
                ),
              ),
              Positioned(
                top: -12,
                right: -12,
                child: IconButton(
                  icon: const Icon(Icons.cancel, color: Colors.red),
                  onPressed: _removeMedia,
                  tooltip: '移除媒体文件',
                ),
              ),
            ],
          ),
        ],
      );
    } else {
      return FButton(
        style: FButtonStyle.outline,
        onPress: _pickAndUploadMedia,
        child: const Text('上传媒体文件 (可选)'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FDialog(
      direction: Axis.horizontal,
      title: Text(widget.option == null ? '添加选项' : '编辑选项'),
      body: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FTextFormField(
                  controller: _textController,
                  label: const Text('选项文本'),
                  hint: '请输入选项文本',
                  validator: (value) => (value == null || value.isEmpty) ? '请输入选项文本' : null,
                ),
                const SizedBox(height: 16),
                _buildMediaSection(),
                if (_uploadError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _uploadError!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
              ],
            ),
          ),
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
    final availableQuestions = widget.questions.where((q) => q.id != widget.currentQuestionId).toList();

    return FDialog(
      direction: Axis.horizontal,
      title: const Text('设置跳题逻辑'),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('选择此选项后，跳转到的问题：'),
          const SizedBox(height: 16),
          FSelect<int>(
            hint: '默认（下一题）',
            format: (value) {
              if (value == -1) return '结束问卷';
              final question = availableQuestions.firstWhere(
                (q) => q.id == value,
                orElse: () => Question(id: 0, title: '未知问题', type: QuestionType.singleChoice, options: [], required: true, order: 0),
              );
              return '第${question.order + 1}题: ${question.title}';
            },
            initialValue: _selectedQuestionId,
            onChange: (value) => setState(() => _selectedQuestionId = value),
            children: [
              ...availableQuestions.map((q) => FSelectItem('第${q.order + 1}题: ${q.title}', q.id)),
              FSelectItem('结束问卷', -1), // Use -1 to represent ending the survey
            ],
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