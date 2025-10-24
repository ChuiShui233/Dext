import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'dart:convert';
import 'package:forui/forui.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;
import '../../widgets/top_safe_spacer.dart';
import '../../models/question.dart';
import '../../services/api_service.dart';
import '../../widgets/frosted_glass_background.dart';
import '../../widgets/markdown_text_widget.dart';
import '../../widgets/question_display_widget.dart';
import 'components/rating_editor.dart';
import 'components/options_editor.dart';
import 'components/media_editor.dart';
import 'components/text_input_editor.dart';
import 'dialogs/add_option_dialog.dart';
import 'dialogs/jump_logic_dialog.dart';

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

class _EditQuestionPageState extends State<EditQuestionPage> with TickerProviderStateMixin {
  bool _enableRatingLabels = false;
  final TextEditingController _ratingLabelsController = TextEditingController();
  final List<TextEditingController> _perStarLabelCtrls = [];
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _minValueController = TextEditingController();
  final _maxValueController = TextEditingController();
  final _initialValueController = TextEditingController();
  final _minLabelController = TextEditingController();
  final _maxLabelController = TextEditingController();
  final _midLabelController = TextEditingController();
  final _starsCountController = TextEditingController();

  late final ApiService _apiService;
  late QuestionType _selectedType;
  final List<QuestionOption> _options = [];
  final List<String> _mediaUrls = [];
  final Map<int, int> _jumpLogic = {};
  bool _required = false;
  bool _isLoading = false;
  
  final Map<String, double> _uploadProgress = {};
  final Map<String, bool> _uploadingFiles = {};
  final Map<String, bool> _cancelledUploads = {};
  final Map<String, String> _uploadStatus = {};

  double _minValue = 0.0;
  double _maxValue = 100.0;
  double _initialValue = 50.0;
  String _minLabel = '最小值';
  String _midLabel = '一般';
  String _maxLabel = '最大值';
  int _starsCount = 5;
  
  String _textInputPlaceholder = '请输入您的答案...';
  int _textInputMaxLength = 500;
  bool _textInputMultiline = false;
  bool _allowHalf = true;
  String _ratingStyle = 'star';
  String _ratingIcon = 'star';
  double _imageScale = 1.0;

  List<Question> _allQuestions = [];

  // 预览用：选项选中状态
  final Map<String, bool> _previewOptionStates = {};

  void _ensurePerStarLabelCtrls(int stars) {
    if (_perStarLabelCtrls.length < stars) {
      for (int i = _perStarLabelCtrls.length; i < stars; i++) {
        _perStarLabelCtrls.add(TextEditingController());
      }
    } else if (_perStarLabelCtrls.length > stars) {
      for (int i = stars; i < _perStarLabelCtrls.length; i++) {
        _perStarLabelCtrls[i].dispose();
      }
      _perStarLabelCtrls.removeRange(stars, _perStarLabelCtrls.length);
    }
  }

  // 将大图压缩到最大边<=1920；
  // 若原文件为PNG则保持PNG编码（避免把PNG压成JPG导致透明丢失/格式变化）；
  // 其他图片统一以JPEG质量85编码。
  Uint8List _compressImageBytesWithFormat(Uint8List input, String fileName) {
    final decoded = img.decodeImage(input);
    if (decoded == null) return input;

    const int maxSide = 1920;
    img.Image processed = decoded;
    final int w = decoded.width;
    final int h = decoded.height;
    if (w > maxSide || h > maxSide) {
      processed = img.copyResize(
        decoded,
        width: w >= h ? maxSide : (w * maxSide / h).round(),
        height: h > w ? maxSide : (h * maxSide / w).round(),
        interpolation: img.Interpolation.average,
      );
    }

    final lower = fileName.toLowerCase();
    final isPng = lower.endsWith('.png');
    if (isPng) {
      // 保持PNG编码（默认压缩级别）
      final pngBytes = img.encodePng(processed);
      return Uint8List.fromList(pngBytes);
    } else {
      // 非PNG统一使用JPEG 85
      final jpg = img.encodeJpg(processed, quality: 85);
      return Uint8List.fromList(jpg);
    }
  }

  // 添加“自定义填写”选项（单选/多选题适用）
  Future<void> _addCustomOption() async {
    // 若已存在则不给重复添加
    final exists = _options.any((o) => o.text == '__custom_input__');
    if (exists) {
      if (!mounted) return;
      showFToast(
        context: context,
        alignment: FToastAlignment.bottomRight,
        title: const Text('无法添加'),
        description: const Text('已存在自定义填写选项'),
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

    setState(() {
      final newId = (_options.isNotEmpty ? _options.map((o) => o.id).reduce((a, b) => a > b ? a : b) : 0) + 1;
      _options.add(QuestionOption(id: newId, text: '__custom_input__'));
    });
  }

  @override
  void initState() {
    super.initState();
    _apiService = ApiService(authToken: widget.token);
    _loadAllQuestions();
    
    _titleController.addListener(() {
      setState(() {});
    });

    _selectedType = widget.question?.type ?? QuestionType.singleChoice;

    if (widget.question != null) {
      _titleController.text = widget.question!.title;
      _options.addAll(widget.question!.options);
      _mediaUrls.addAll(widget.question!.mediaUrls);
      _jumpLogic.addAll(widget.question!.jumpLogic);
      for (int i = 0; i < _options.length; i++) {
        final opt = _options[i];
        final jl = _jumpLogic[opt.id];
        if (jl != null && jl > 0) {
          // 已有跳题逻辑
        } else if (opt.destination != null && opt.destination! > 0) {
          _jumpLogic[opt.id] = opt.destination!;
        }
      }
      _required = widget.question!.required;
      _imageScale = widget.question!.imageScale;

      if (_selectedType == QuestionType.slider) {
        if (_options.length >= 5) {
          _minValue = double.tryParse(_options[0].text) ?? 0.0;
          _maxValue = double.tryParse(_options[1].text) ?? 100.0;
          _initialValue = double.tryParse(_options[2].text) ?? 50.0;
          _minLabel = _options[3].text;
          _maxLabel = _options[4].text;
          _midLabel = _options.length >= 6 ? (_options[5].text.isNotEmpty ? _options[5].text : '一般') : '一般';
        }
        if (_options.length >= 10) {
          _starsCount = int.tryParse(_options[9].text) ?? 5;
          if (_starsCount < 1) _starsCount = 1;
          if (_starsCount > 10) _starsCount = 10;
        }
        if (_options.length >= 7) {
          final v = _options[6].text;
          if (v == 'star' || v == 'crumb') _ratingStyle = v;
        }
        if (_options.length >= 8) {
          final v = _options[7].text;
          if (v.isNotEmpty) _ratingIcon = v;
        }
        if (_options.length >= 9) {
          _allowHalf = _options[8].text.toLowerCase() == 'true';
        }
        if (_options.length >= 11) {
          final raw = _options[10].text.trim();
          if (raw.isNotEmpty) {
            try {
              final Map<String, dynamic> m = jsonDecode(raw);
              if (m.isNotEmpty) {
                _enableRatingLabels = true;
                final totalSteps = _allowHalf ? _starsCount * 2 : _starsCount;
                _ensurePerStarLabelCtrls(totalSteps);
                for (int i = 0; i < totalSteps; i++) {
                  final value = _allowHalf ? (i + 1) * 0.5 : (i + 1).toDouble();
                  final key = value % 1 == 0 ? value.toInt().toString() : value.toString();
                  final val = m[key]?.toString() ?? '';
                  if (val.isNotEmpty) _perStarLabelCtrls[i].text = val;
                }
              }
            } catch (_) {}
          }
        }
      } else if (_selectedType == QuestionType.textInput) {
        if (_options.isNotEmpty) {
          final configText = _options.first.text;
          if (configText.contains('placeholder:')) {
            final parts = configText.split('|');
            for (final part in parts) {
              if (part.startsWith('placeholder:')) {
                _textInputPlaceholder = part.substring('placeholder:'.length).trim();
              } else if (part.startsWith('maxLength:')) {
                _textInputMaxLength = int.tryParse(part.substring('maxLength:'.length).trim()) ?? 500;
              } else if (part.startsWith('multiline:')) {
                _textInputMultiline = part.substring('multiline:'.length).trim().toLowerCase() == 'true';
              }
            }
          }
        }
      }
    }

    _minValueController.text = _minValue.toStringAsFixed(2);
    _maxValueController.text = _maxValue.toStringAsFixed(2);
    _initialValueController.text = _initialValue.toStringAsFixed(2);
    _minLabelController.text = _minLabel;
    _maxLabelController.text = _maxLabel;
    _midLabelController.text = _midLabel;
    _starsCountController.text = _starsCount.toString();
  }

  @override
  void dispose() {
    _ratingLabelsController.dispose();
    for (final c in _perStarLabelCtrls) { c.dispose(); }
    _titleController.dispose();
    _minValueController.dispose();
    _maxValueController.dispose();
    _initialValueController.dispose();
    _minLabelController.dispose();
    _maxLabelController.dispose();
    _midLabelController.dispose();
    _starsCountController.dispose();
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
        option: null,
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

  void _deleteOption(QuestionOption option) {
    setState(() {
      _options.removeWhere((o) => o.id == option.id);
      _jumpLogic.remove(option.id);
    });
  }

  Future<void> _addMedia() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.media,
      allowMultiple: true,
      withData: true, // 确保在桌面端也能直接拿到 bytes
    );

    if (result != null && result.files.isNotEmpty) {
      await _uploadFiles(result.files);
    }
  }

  Future<void> _uploadFiles(List<PlatformFile> files) async {
    for (final file in files) {
      // 尝试优先使用内存中的 bytes，其次使用 readStream 聚合为 bytes
      Uint8List? bytes = file.bytes;
      if (bytes == null && file.readStream != null) {
        try {
          final builder = BytesBuilder();
          await for (final chunk in file.readStream!) {
            builder.add(chunk);
          }
          bytes = builder.takeBytes();
        } catch (_) {
          bytes = null;
        }
      }

      if (bytes == null) {
        // 无可用数据，跳过该文件
        continue;
      }

      // 若为图片，先尝试压缩与限制尺寸
      final lowerName = file.name.toLowerCase();
      final isImage = lowerName.endsWith('.jpg') || lowerName.endsWith('.jpeg') || lowerName.endsWith('.png') || lowerName.endsWith('.webp');
      if (isImage) {
        try {
          bytes = _compressImageBytesWithFormat(bytes, file.name);
        } catch (_) {
          // 压缩失败则使用原始数据
        }
      }

      final fileName = file.name;
      setState(() {
        _uploadingFiles[fileName] = true;
        _uploadProgress[fileName] = 0.0;
        _uploadStatus[fileName] = '正在准备上传...';
      });

      try {
        final url = await _apiService.uploadMediaBytes(
          widget.surveyId,
          bytes!,
          fileName,
          onProgress: (sent, total) {
            if (mounted && !(_cancelledUploads[fileName] ?? false)) {
              setState(() {
                _uploadProgress[fileName] = sent / total;
                final pct = (_uploadProgress[fileName]! * 100).toInt();
                _uploadStatus[fileName] = '上传中 $pct%';
              });
            }
          },
          onStatus: (status, message) {
            if (!mounted) return;
            if (_cancelledUploads[fileName] ?? false) return;
            setState(() {
              if (message != null && message.isNotEmpty) {
                _uploadStatus[fileName] = message;
              }
            });
          },
        );

        if (mounted && !(_cancelledUploads[fileName] ?? false)) {
          setState(() {
            _mediaUrls.add(url);
            _uploadingFiles.remove(fileName);
            _uploadProgress.remove(fileName);
            _uploadStatus.remove(fileName);
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _uploadingFiles.remove(fileName);
            _uploadProgress.remove(fileName);
            _uploadStatus.remove(fileName);
          });
          _showErrorToast('上传失败', e.toString());
        }
      }
    }
  }

  Future<void> _deleteMedia(String url) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => FDialog(
        title: const Text('确认删除'),
        body: const Text('确定要删除这个媒体文件吗？'),
        actions: [
          FButton(
            style: FButtonStyle.outline,
            onPress: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FButton(
            onPress: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (shouldDelete == true) {
      try {
        await _apiService.deleteMediaFileByName(widget.surveyId, url.split('/').last);
        setState(() {
          _mediaUrls.remove(url);
        });
      } catch (e) {
        _showErrorToast('删除媒体文件时出错，但已从本地移除', e.toString());
        setState(() {
          _mediaUrls.remove(url);
        });
      }
    }
  }

  Future<void> _saveQuestion() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      List<QuestionOption> finalOptions;

      if (_selectedType == QuestionType.slider) {
        final minLabel = _minLabelController.text;
        final midLabel = _midLabelController.text.isNotEmpty ? _midLabelController.text : '一般';
        final maxLabel = _maxLabelController.text;
        final parsedStars = int.tryParse(_starsCountController.text.trim());
        final starsCount = (parsedStars ?? _starsCount).clamp(1, 10);

        finalOptions = [
          QuestionOption(id: 1, text: '0'),
          QuestionOption(id: 2, text: '10'),
          QuestionOption(id: 3, text: '5'),
          QuestionOption(id: 4, text: (minLabel).isNotEmpty ? minLabel : '最小值'),
          QuestionOption(id: 5, text: (maxLabel).isNotEmpty ? maxLabel : '最大值'),
          QuestionOption(id: 6, text: midLabel),
          QuestionOption(id: 7, text: _ratingStyle),
          QuestionOption(id: 8, text: _ratingIcon),
          QuestionOption(id: 9, text: _allowHalf.toString()),
          QuestionOption(id: 10, text: starsCount.toString()),
        ];

        if (_enableRatingLabels) {
          final totalSteps = _allowHalf ? starsCount * 2 : starsCount;
          _ensurePerStarLabelCtrls(totalSteps);
          final Map<String, String> map = {};
          for (int i = 0; i < totalSteps; i++) {
            final value = _allowHalf ? (i + 1) * 0.5 : (i + 1).toDouble();
            final key = value % 1 == 0 ? value.toInt().toString() : value.toString();
            final val = _perStarLabelCtrls[i].text.trim();
            if (val.isNotEmpty) {
              map[key] = val;
            }
          }
          if (map.isNotEmpty) {
            final jsonStr = jsonEncode(map);
            finalOptions.add(QuestionOption(id: 11, text: jsonStr));
          }
        }
      } else if (_selectedType == QuestionType.textInput) {
        final configText = 'placeholder:$_textInputPlaceholder|maxLength:$_textInputMaxLength|multiline:$_textInputMultiline';
        finalOptions = [
          QuestionOption(id: 1, text: configText),
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
        imageScale: _imageScale,
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
      
      String errorMessage = e.toString();
      if (e.toString().contains('HandshakeException')) {
        errorMessage = '网络连接失败，请检查网络连接或稍后重试';
      } else if (e.toString().contains('SocketException')) {
        errorMessage = '无法连接到服务器，请检查网络连接';
      } else if (e.toString().contains('TimeoutException')) {
        errorMessage = '请求超时，请稍后重试';
      }
      
      _showErrorToast('保存问题失败', errorMessage);
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

  String _getQuestionTypeText(QuestionType type) {
    switch (type) {
      case QuestionType.singleChoice:
        return '单选题';
      case QuestionType.multipleChoice:
        return '多选题';
      case QuestionType.slider:
        return '评级题';
      case QuestionType.textInput:
        return '填写题';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 1080;

    return Scaffold(
      body: Stack(
        children: [
          const FrostedGlassBackground(),
          Column(
            children: [
              const TopSafeSpacer(),
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
                child: isDesktop
                    ? _buildDesktopLayout(theme)
                    : _buildMobileLayout(theme),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMobileLayout(ThemeData theme) {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildTitleField(),
          const SizedBox(height: 8),
          MarkdownToolbar(
            controller: _titleController,
            onChanged: () => setState(() {}),
          ),
          const SizedBox(height: 8),
          _buildTitlePreview(theme),
          const SizedBox(height: 16),
          _buildTypeSelector(),
          const SizedBox(height: 16),
          _buildTypeSpecificEditor(),
          const SizedBox(height: 16),
          _buildMediaEditor(),
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
    );
  }

  Widget _buildDesktopLayout(ThemeData theme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTitleField(),
                    const SizedBox(height: 8),
                    MarkdownToolbar(
                      controller: _titleController,
                      onChanged: () => setState(() {}),
                    ),
                    const SizedBox(height: 16),
                    _buildTypeSelector(),
                    const SizedBox(height: 16),
                    _buildTypeSpecificEditor(),
                    const SizedBox(height: 16),
                    _buildMediaEditor(),
                    const SizedBox(height: 16),
                    FSwitch(
                      label: const Text('必答题'),
                      value: _required,
                      onChange: (value) => setState(() => _required = value),
                    ),
                    const SizedBox(height: 48),
                  ],
                ),
              ),
            ),
          ),
        ),
        SizedBox(
          width: 360,
          child: Container(
            decoration: BoxDecoration(
              color: theme.cardColor.withValues(alpha: 0.5),
              border: Border(
                left: BorderSide(
                  color: theme.dividerColor.withValues(alpha: 0.08),
                  width: 1,
                ),
              ),
            ),
            child: Column(
              children: [
                Expanded(
                  child: ScrollConfiguration(
                    behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: _buildActionPanel(theme),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTitleField() {
    return FTextFormField(
      controller: _titleController,
      label: const Text('问题标题'),
      hint: '请输入问题标题',
      validator: (value) => (value == null || value.isEmpty) ? '请输入问题标题' : null,
      maxLines: null,
      keyboardType: TextInputType.multiline,
    );
  }

  Widget _buildTypeSelector() {
    return FSelect<QuestionType>(
      label: const Text('问题类型'),
      format: (value) => _getQuestionTypeText(value),
      initialValue: _selectedType,
      onChange: (value) {
        if (value != null) setState(() => _selectedType = value);
      },
      children: QuestionType.values
          .map((type) => FSelectItem(_getQuestionTypeText(type), type))
          .toList(),
    );
  }

  Widget _buildTypeSpecificEditor() {
    if (_selectedType == QuestionType.slider) {
      return RatingEditor(
        minLabelController: _minLabelController,
        maxLabelController: _maxLabelController,
        midLabelController: _midLabelController,
        starsCountController: _starsCountController,
        enableRatingLabels: _enableRatingLabels,
        perStarLabelCtrls: _perStarLabelCtrls,
        ratingStyle: _ratingStyle,
        ratingIcon: _ratingIcon,
        allowHalf: _allowHalf,
        starsCount: _starsCount,
        onEnsurePerStarLabelCtrls: _ensurePerStarLabelCtrls,
        onEnableRatingLabelsChanged: (value) {
          setState(() {
            _enableRatingLabels = value;
            if (value) {
              final totalSteps = _allowHalf ? _starsCount * 2 : _starsCount;
              _ensurePerStarLabelCtrls(totalSteps);
            }
          });
        },
        onRatingStyleChanged: (value) {
          setState(() {
            _ratingStyle = value;
          });
        },
        onRatingIconChanged: (value) {
          setState(() {
            _ratingIcon = value;
          });
        },
        onAllowHalfChanged: (value) {
          setState(() {
            _allowHalf = value;
            if (_enableRatingLabels) {
              final totalSteps = _allowHalf ? _starsCount * 2 : _starsCount;
              _ensurePerStarLabelCtrls(totalSteps);
            }
          });
        },
        onStarsCountChanged: (value) {
          setState(() {
            _starsCount = value;
            _starsCountController.text = value.toString();
            if (_enableRatingLabels) {
              final totalSteps = _allowHalf ? _starsCount * 2 : _starsCount;
              _ensurePerStarLabelCtrls(totalSteps);
            }
          });
        },
      );
    } else if (_selectedType == QuestionType.textInput) {
      return TextInputEditor(
        placeholder: _textInputPlaceholder,
        maxLength: _textInputMaxLength,
        multiline: _textInputMultiline,
        onPlaceholderChanged: (value) {
          setState(() {
            _textInputPlaceholder = value;
          });
        },
        onMaxLengthChanged: (value) {
          setState(() {
            _textInputMaxLength = value;
          });
        },
        onMultilineChanged: (value) {
          setState(() {
            _textInputMultiline = value;
          });
        },
      );
    } else {
      return OptionsEditor(
        options: _options,
        selectedType: _selectedType,
        allQuestions: _allQuestions,
        currentQuestionId: widget.question?.id ?? 0,
        jumpLogic: _jumpLogic,
        onAddOption: _addOption,
        onAddCustomOption: _addCustomOption,
        onEditOption: _editOption,
        onDeleteOption: _deleteOption,
        onBatchSetJump: _batchSetJump,
        onSetJumpLogic: (option) async {
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
        },
      );
    }
  }

  Widget _buildMediaEditor() {
    return MediaEditor(
      mediaUrls: _mediaUrls,
      uploadProgress: _uploadProgress,
      uploadingFiles: _uploadingFiles,
      uploadStatus: _uploadStatus,
      onUploadMedia: _addMedia,
      onDeleteMedia: _deleteMedia,
      onCancelUpload: (fileName) {
        setState(() {
          _cancelledUploads[fileName] = true;
          _uploadingFiles.remove(fileName);
          _uploadProgress.remove(fileName);
          _uploadStatus.remove(fileName);
        });
      },
      onDropFiles: _uploadFiles,
      imageScale: _imageScale,
      onImageScaleChanged: (value) {
        setState(() {
          _imageScale = value;
        });
      },
    );
  }

  Question _buildLivePreviewQuestion() {
    // 根据当前编辑器状态构造完整的 Question，用于预览整道题目
    List<QuestionOption> previewOptions;
    if (_selectedType == QuestionType.slider) {
      final minLabel = _minLabelController.text;
      final midLabel = _midLabelController.text.isNotEmpty ? _midLabelController.text : '一般';
      final maxLabel = _maxLabelController.text;
      final parsedStars = int.tryParse(_starsCountController.text.trim());
      final starsCount = (parsedStars ?? _starsCount).clamp(1, 10);

      previewOptions = [
        QuestionOption(id: 1, text: '0'),
        QuestionOption(id: 2, text: '10'),
        QuestionOption(id: 3, text: '5'),
        QuestionOption(id: 4, text: (minLabel).isNotEmpty ? minLabel : '最小值'),
        QuestionOption(id: 5, text: (maxLabel).isNotEmpty ? maxLabel : '最大值'),
        QuestionOption(id: 6, text: midLabel),
        QuestionOption(id: 7, text: _ratingStyle),
        QuestionOption(id: 8, text: _ratingIcon),
        QuestionOption(id: 9, text: _allowHalf.toString()),
        QuestionOption(id: 10, text: starsCount.toString()),
      ];

      if (_enableRatingLabels) {
        final totalSteps = _allowHalf ? starsCount * 2 : starsCount;
        _ensurePerStarLabelCtrls(totalSteps);
        final Map<String, String> map = {};
        for (int i = 0; i < totalSteps; i++) {
          final value = _allowHalf ? (i + 1) * 0.5 : (i + 1).toDouble();
          final key = value % 1 == 0 ? value.toInt().toString() : value.toString();
          final val = _perStarLabelCtrls[i].text.trim();
          if (val.isNotEmpty) {
            map[key] = val;
          }
        }
        if (map.isNotEmpty) {
          final jsonStr = jsonEncode(map);
          previewOptions.add(QuestionOption(id: 11, text: jsonStr));
        }
      }
    } else if (_selectedType == QuestionType.textInput) {
      final configText = 'placeholder:$_textInputPlaceholder|maxLength:$_textInputMaxLength|multiline:$_textInputMultiline';
      previewOptions = [
        QuestionOption(id: 1, text: configText),
      ];
    } else {
      previewOptions = _options;
    }

    return Question(
      id: widget.question?.id ?? 0,
      title: _titleController.text.isEmpty ? '问题标题预览' : _titleController.text,
      type: _selectedType,
      options: previewOptions,
      mediaUrls: _mediaUrls,
      jumpLogic: _jumpLogic,
      required: _required,
      order: widget.question?.order ?? 0,
      imageScale: _imageScale,
    );
  }

  Widget _buildTitlePreview(ThemeData theme) {
    // 使用完整渲染组件预览整道题目
    final previewQuestion = _buildLivePreviewQuestion();

    return Card(
      elevation: 0,
      color: theme.cardColor.withValues(alpha: 0.7),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '预览效果',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            QuestionDisplayWidget(
              question: previewQuestion,
              mode: QuestionDisplayMode.preview,
              optionStates: _previewOptionStates,
              authToken: widget.token,
              titleOnly: false,
              onSingleChoiceChanged: (questionId, selectedOption, optionIndex) {
                // 单选：清空同题选中，再选中当前
                setState(() {
                  // 清除该题所有选项状态
                  for (int i = 0; i < previewQuestion.options.length; i++) {
                    _previewOptionStates[_optKey(questionId, i)] = false;
                  }
                  _previewOptionStates[_optKey(questionId, optionIndex)] = true;
                });
              },
              onMultipleChoiceChanged: (questionId, option, optionIndex, isSelected) {
                setState(() {
                  _previewOptionStates[_optKey(questionId, optionIndex)] = !isSelected;
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  String _optKey(int questionId, int optionIndex) => 'q${questionId}_opt$optionIndex';

  Widget _buildActionPanel(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTitlePreview(theme),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _isLoading ? null : _saveQuestion,
          icon: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.save_outlined),
          label: Text(_isLoading ? '保存中...' : '保存问题'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ],
    );
  }
}
