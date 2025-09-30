// file: edit_question_page.dart

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:forui/forui.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../widgets/top_safe_spacer.dart';
import '../models/question.dart';
import '../services/api_service.dart';
import '../widgets/frosted_glass_background.dart';
import '../components/video_player_widget.dart';
import '../services/config.dart';


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
  // 自定义评级文本开关与输入
  bool _enableRatingLabels = false;
  final TextEditingController _ratingLabelsController = TextEditingController();
  // 按星星数量生成的标签输入框控制器（1..stars）
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
  
  // 上传进度管理
  final Map<String, double> _uploadProgress = {}; // 文件名 -> 进度(0.0-1.0)
  final Map<String, bool> _uploadingFiles = {}; // 文件名 -> 是否正在上传
  final Map<String, bool> _cancelledUploads = {}; // 文件名 -> 是否已取消

  // 评级题（原滑块）相关属性
  double _minValue = 0.0;
  double _maxValue = 100.0;
  double _initialValue = 50.0;
  String _minLabel = '最小值';
  String _midLabel = '一般';
  String _maxLabel = '最大值';
  int _starsCount = 5;
  bool _allowHalf = true;
  String _ratingStyle = 'star'; // star | crumb
  String _ratingIcon = 'star'; // star | favorite | circle | heart 等（用于 star 风格）

  List<Question> _allQuestions = [];

  // 保证按当前星数生成足够的标签输入框控制器
  void _ensurePerStarLabelCtrls(int stars) {
    if (_perStarLabelCtrls.length < stars) {
      for (int i = _perStarLabelCtrls.length; i < stars; i++) {
        _perStarLabelCtrls.add(TextEditingController());
      }
    } else if (_perStarLabelCtrls.length > stars) {
      // 多余的先dispose再移除
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
        // 样式/图标/半星 从后端 options 读取，驱动前端多选框/开关初始值
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
        // 加载自定义评级标签（第11项，JSON），根据星数生成输入框并回填
        if (_options.length >= 11) {
          final raw = _options[10].text.trim();
          if (raw.isNotEmpty) {
            try {
              final Map<String, dynamic> m = jsonDecode(raw);
              if (m.isNotEmpty) {
                _enableRatingLabels = true;
                _ensurePerStarLabelCtrls(_starsCount);
                for (int i = 0; i < _starsCount; i++) {
                  final key = (i + 1).toString();
                  final val = m[key]?.toString() ?? '';
                  if (val.isNotEmpty) _perStarLabelCtrls[i].text = val;
                }
              }
            } catch (_) {}
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
          final fileName = file.name;
          
          // 标记文件开始上传
          setState(() {
            _uploadingFiles[fileName] = true;
            _uploadProgress[fileName] = 0.0;
          });
          
          try {
            String url;
            
            // Web平台使用字节数据，移动端使用文件路径
            if (kIsWeb) {
              if (file.bytes != null && file.name.isNotEmpty) {
                url = await _apiService.uploadMediaUniversal(
                  widget.surveyId,
                  fileBytes: file.bytes!,
                  fileName: file.name,
                  onProgress: (uploaded, total) {
                    if (mounted && !(_cancelledUploads[fileName] ?? false)) {
                      setState(() {
                        _uploadProgress[fileName] = uploaded / total;
                      });
                    }
                  },
                );
              } else {
                continue; // 跳过无效文件
              }
            } else {
              if (file.path != null) {
                url = await _apiService.uploadMediaUniversal(
                  widget.surveyId,
                  filePath: file.path!,
                  onProgress: (uploaded, total) {
                    if (mounted && !(_cancelledUploads[fileName] ?? false)) {
                      setState(() {
                        _uploadProgress[fileName] = uploaded / total;
                      });
                    }
                  },
                );
              } else {
                continue; // 跳过无效文件
              }
            }
            
            // 检查是否已取消
            if (_cancelledUploads[fileName] ?? false) {
              // 上传已取消，清理状态
              setState(() {
                _uploadingFiles.remove(fileName);
                _uploadProgress.remove(fileName);
                _cancelledUploads.remove(fileName);
              });
              continue;
            }
            
            // 上传完成
            setState(() {
              _mediaUrls.add(url);
              _uploadingFiles.remove(fileName);
              _uploadProgress.remove(fileName);
            });
          } catch (e) {
            // 上传失败或取消，清理状态
            setState(() {
              _uploadingFiles.remove(fileName);
              _uploadProgress.remove(fileName);
              _cancelledUploads.remove(fileName);
            });
            
            // 如果不是取消操作，则重新抛出错误
            if (!(_cancelledUploads[fileName] ?? false)) {
              rethrow;
            }
          }
        }
      }
    } catch (e) {
      if (!mounted) return;
      _showErrorToast('上传媒体文件失败', e.toString());
    }
  }

  void _cancelUpload(String fileName) {
    setState(() {
      _cancelledUploads[fileName] = true;
      _uploadingFiles.remove(fileName);
      _uploadProgress.remove(fileName);
    });
    _showSuccessToast('已取消上传: $fileName');
  }

  Future<void> _deleteMedia(String url) async {
    // 显示删除确认弹窗
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: const Text('确定要删除这个媒体文件吗？此操作无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        // 从URL中提取文件名
        final uri = Uri.parse(url);
        final pathSegments = uri.pathSegments;
        String? fileName;
        
        if (pathSegments.isNotEmpty) {
          fileName = pathSegments.last;
        }
        
        if (fileName != null && fileName.isNotEmpty) {
          // 通过文件名删除媒体文件
          await _apiService.deleteMediaFileByName(
            widget.surveyId,
            fileName,
          );
          
          // 从本地列表中移除
          setState(() {
            _mediaUrls.remove(url);
          });
          
          _showSuccessToast('媒体文件删除成功');
        } else {
          // 如果无法提取文件名，只从本地移除
          setState(() {
            _mediaUrls.remove(url);
          });
          _showSuccessToast('媒体文件已从本地移除');
        }
      } catch (e) {
        // 删除失败时显示错误信息，但仍从本地移除
        setState(() {
          _mediaUrls.remove(url);
        });
        _showErrorToast('删除媒体文件时出错，但已从本地移除', e.toString());
      }
    }
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
        // 固定区间 0..10，初始值固定为 5；中间标签固定为“一般”。仅保存左右标签与样式配置
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

        // 自定义标签（按星数 1..N 生成，留空则跳过），存入第 11 项（索引10）
        if (_enableRatingLabels) {
          _ensurePerStarLabelCtrls(starsCount);
          final Map<String, String> map = {};
          for (int i = 0; i < starsCount; i++) {
            final key = (i + 1).toString();
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

  void _showSuccessToast(String message) {
    showFToast(
      context: context,
      alignment: FToastAlignment.bottomRight,
      title: Text('成功'),
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
                    _buildRatingSettings()
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
        ],
      ),
    );
  }

  Widget _buildRatingSettings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 数值区间固定为 0..10，初始值固定为 5（中间），这里移除数值编辑项
        Row(children: [
          Expanded(
            child: FTextFormField(
              label: const Text('左侧标签'),
              hint: '如 不推荐',
              controller: _minLabelController,
              onEditingComplete: () => setState(() {}),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FTextFormField(
              label: const Text('中间标签'),
              hint: '如 一般',
              controller: _midLabelController,
              onEditingComplete: () => setState(() { _midLabel = _midLabelController.text; }),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FTextFormField(
              label: const Text('右侧标签'),
              hint: '如 强烈推荐',
              controller: _maxLabelController,
              onEditingComplete: () => setState(() {}),
            ),
          ),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: FSelect<String>(
              label: const Text('表现样式'),
              hint: '选择评级的可视样式',
              initialValue: _ratingStyle,
              format: (v) => v == 'star' ? '星星 (建议)' : '面包屑',
              onChange: (v) => setState(() { if (v != null) _ratingStyle = v; }),
              children: [
                FSelectItem('星星 (建议)', 'star'),
                FSelectItem('面包屑', 'crumb'),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FSelect<String>(
              label: const Text('图标（星星样式）'),
              hint: '仅当样式为星星时生效',
              initialValue: _ratingIcon,
              format: (v) => v,
              onChange: (v) => setState(() { if (v != null) _ratingIcon = v; }),
              children: [
                FSelectItem('star', 'star'),
                FSelectItem('favorite', 'favorite'),
                FSelectItem('circle', 'circle'),
                FSelectItem('heart_broken', 'heart_broken'),
              ],
            ),
          ),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: FTextFormField(
              label: const Text('星星数量'),
              hint: '1-10，默认 5',
              controller: _starsCountController,
              keyboardType: TextInputType.number,
              onEditingComplete: () {
                final n = int.tryParse(_starsCountController.text.trim()) ?? _starsCount;
                setState(() {
                  _starsCount = n.clamp(1, 10);
                  _starsCountController.text = _starsCount.toString();
                  _ensurePerStarLabelCtrls(_starsCount);
                });
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FSwitch(
              label: const Text('允许半星'),
              value: _allowHalf,
              onChange: (v) => setState(() { _allowHalf = v; }),
            ),
          ),
        ]),
        const SizedBox(height: 16),
        FSwitch(
          label: const Text('启用自定义评级文本'),
          description: const Text('为 0.5 步进的分值定义显示文本；未设置的分值将使用默认数值'),
          value: _enableRatingLabels,
          onChange: (v) => setState(() {
            _enableRatingLabels = v;
            if (v) _ensurePerStarLabelCtrls(_starsCount);
          }),
        ),
        if (_enableRatingLabels) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: List.generate(_starsCount, (i) {
              final idx = i + 1;
              _ensurePerStarLabelCtrls(_starsCount);
              return SizedBox(
                width: 220,
                child: FTextFormField(
                  label: Text('分值 $idx 文本(可留空)'),
                  controller: _perStarLabelCtrls[i],
                ),
              );
            }),
          ),
          const SizedBox(height: 4),
          const Text('说明：根据星星数量(1..N)提供对应的文本输入，留空则使用默认数值。'),
        ],
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
                            imageUrl: toAbsoluteUrl(option.mediaUrl!),
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
          children: [
            // 显示已上传的媒体文件
            ..._mediaUrls.map((url) {
            Widget mediaWidget;
            final absUrl = toAbsoluteUrl(url);
            final isImage = absUrl.toLowerCase().endsWith('.jpg') || 
                           absUrl.toLowerCase().endsWith('.jpeg') || 
                           absUrl.toLowerCase().endsWith('.png') ||
                           absUrl.toLowerCase().endsWith('.gif');
            final isVideo = absUrl.toLowerCase().endsWith('.mp4') || 
                           absUrl.toLowerCase().endsWith('.avi') || 
                           absUrl.toLowerCase().endsWith('.mov') ||
                           absUrl.toLowerCase().endsWith('.webm');
            final isAudio = absUrl.toLowerCase().endsWith('.mp3') || 
                           absUrl.toLowerCase().endsWith('.wav') || 
                           absUrl.toLowerCase().endsWith('.aac');

            if (isImage) {
              mediaWidget = CachedNetworkImage(
                imageUrl: absUrl,
                fit: BoxFit.cover,
                progressIndicatorBuilder: (context, url, progress) => 
                    Center(child: CircularProgressIndicator(value: progress.progress)),
                errorWidget: (context, url, error) => const Icon(Icons.error),
              );
            } else if (isVideo) {
              mediaWidget = VideoPlayerWidget(
                videoUrl: absUrl,
                width: 200,
                height: 150,
                autoPlay: false,
                showControls: true,
              );
            } else if (isAudio) {
              mediaWidget = const Center(child: Icon(Icons.audio_file, size: 40));
            } else {
              mediaWidget = const Center(child: Icon(Icons.file_present, size: 40));
            }

            return Stack(
              children: [
                Container(
                  width: isVideo ? 200 : 100,
                  height: isVideo ? 150 : 100,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(7), 
                    child: mediaWidget,
                  ),
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: InkWell(
                      onTap: () => _deleteMedia(absUrl),
                      borderRadius: BorderRadius.circular(4),
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
            }),
            // 显示正在上传的文件进度
            ..._uploadingFiles.keys.map((fileName) {
              final progress = _uploadProgress[fileName] ?? 0.0;
              final isImage = fileName.toLowerCase().endsWith('.jpg') || 
                             fileName.toLowerCase().endsWith('.jpeg') || 
                             fileName.toLowerCase().endsWith('.png') ||
                             fileName.toLowerCase().endsWith('.gif');
              final isVideo = fileName.toLowerCase().endsWith('.mp4') || 
                             fileName.toLowerCase().endsWith('.avi') || 
                             fileName.toLowerCase().endsWith('.mov') ||
                             fileName.toLowerCase().endsWith('.webm');
              
              return Container(
                width: isVideo ? 200 : 100,
                height: isVideo ? 150 : 100,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.grey.shade100,
                ),
                child: Stack(
                  children: [
                    // 文件类型图标
                    Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            isImage ? Icons.image : 
                            isVideo ? Icons.video_file : 
                            Icons.audio_file,
                            size: 30,
                            color: Colors.grey.shade600,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            fileName.length > 15 
                                ? '${fileName.substring(0, 12)}...'
                                : fileName,
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                    // 进度条
                    Positioned(
                      bottom: 8,
                      left: 8,
                      right: 8,
                      child: Column(
                        children: [
                          LinearProgressIndicator(
                            value: progress,
                            backgroundColor: Colors.grey.shade300,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Theme.of(context).primaryColor,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${(progress * 100).toInt()}%',
                            style: const TextStyle(fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                    // 取消按钮
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: InkWell(
                          onTap: () => _cancelUpload(fileName),
                          borderRadius: BorderRadius.circular(4),
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
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
      case QuestionType.slider: return '评级题';
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
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.single;
        String url;
        
        // Web平台使用字节数据，移动端使用文件路径
        if (kIsWeb) {
          if (file.bytes != null && file.name.isNotEmpty) {
            url = await widget.apiService.uploadMediaUniversal(
              widget.surveyId,
              fileBytes: file.bytes!,
              fileName: file.name,
            );
          } else {
            throw '无法获取文件数据';
          }
        } else {
          if (file.path != null) {
            url = await widget.apiService.uploadMediaUniversal(
              widget.surveyId,
              filePath: file.path!,
            );
          } else {
            throw '无法获取文件路径';
          }
        }
        
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
    final absUrl = toAbsoluteUrl(url);
    if (absUrl.toLowerCase().endsWith('.jpg') || absUrl.toLowerCase().endsWith('.jpeg') || absUrl.toLowerCase().endsWith('.png')) {
      return CachedNetworkImage(
        imageUrl: absUrl,
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
                top: 4,
                right: 4,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: InkWell(
                    onTap: _removeMedia,
                    borderRadius: BorderRadius.circular(4),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ),
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