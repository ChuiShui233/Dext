import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:forui/forui.dart';
import 'package:file_picker/file_picker.dart';
import '../../widgets/top_safe_spacer.dart';
import '../../models/question.dart';
import '../../services/api_service.dart';
import '../../widgets/frosted_glass_background.dart';
import '../../widgets/markdown_text_widget.dart';
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

class _EditQuestionPageState extends State<EditQuestionPage> {
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
  bool _required = true;
  bool _isLoading = false;
  
  final Map<String, double> _uploadProgress = {};
  final Map<String, bool> _uploadingFiles = {};
  final Map<String, bool> _cancelledUploads = {};

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
    );

    if (result != null && result.files.isNotEmpty) {
      await _uploadFiles(result.files);
    }
  }

  Future<void> _uploadFiles(List<PlatformFile> files) async {
    for (final file in files) {
      if (file.bytes != null) {
        final fileName = file.name;
        setState(() {
          _uploadingFiles[fileName] = true;
          _uploadProgress[fileName] = 0.0;
        });

        try {
          final url = await _apiService.uploadMediaBytes(
            widget.surveyId,
            file.bytes!,
            fileName,
            onProgress: (sent, total) {
              if (mounted && !(_cancelledUploads[fileName] ?? false)) {
                setState(() {
                  _uploadProgress[fileName] = sent / total;
                });
              }
            },
          );

          if (mounted && !(_cancelledUploads[fileName] ?? false)) {
            setState(() {
              _mediaUrls.add(url);
              _uploadingFiles.remove(fileName);
              _uploadProgress.remove(fileName);
            });
          }
        } catch (e) {
          if (mounted) {
            setState(() {
              _uploadingFiles.remove(fileName);
              _uploadProgress.remove(fileName);
            });
            _showErrorToast('上传失败', e.toString());
          }
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
                        maxLines: null,
                        keyboardType: TextInputType.multiline,
                      ),
                      const SizedBox(height: 8),
                      MarkdownToolbar(
                        controller: _titleController,
                        onChanged: () => setState(() {}),
                      ),
                      const SizedBox(height: 8),
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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '预览效果:',
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 8),
                            MarkdownTextWidget(
                              text: _titleController.text.isEmpty ? '问题标题预览' : _titleController.text,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
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
                        RatingEditor(
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
                        )
                      else if (_selectedType == QuestionType.textInput)
                        TextInputEditor(
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
                        )
                      else
                        OptionsEditor(
                          options: _options,
                          selectedType: _selectedType,
                          allQuestions: _allQuestions,
                          currentQuestionId: widget.question?.id ?? 0,
                          jumpLogic: _jumpLogic,
                          onAddOption: _addOption,
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
                        ),
                      const SizedBox(height: 16),
                      MediaEditor(
                        mediaUrls: _mediaUrls,
                        uploadProgress: _uploadProgress,
                        uploadingFiles: _uploadingFiles,
                        onUploadMedia: _addMedia,
                        onDeleteMedia: _deleteMedia,
                        onCancelUpload: (fileName) {
                          setState(() {
                            _cancelledUploads[fileName] = true;
                            _uploadingFiles.remove(fileName);
                            _uploadProgress.remove(fileName);
                          });
                        },
                        onDropFiles: _uploadFiles,
                        imageScale: _imageScale,
                        onImageScaleChanged: (value) {
                          setState(() {
                            _imageScale = value;
                          });
                        },
                      ),
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
        ],
      ),
    );
  }
}
