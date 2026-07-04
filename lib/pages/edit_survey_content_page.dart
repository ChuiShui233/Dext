
import 'dart:async';
import 'dart:ui';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:forui/forui.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../widgets/top_safe_spacer.dart';
import '../models/survey.dart';
import '../models/question.dart';
import '../services/api_service.dart';
import '../main.dart' show isDesktop;
import '../widgets/frosted_glass_background.dart';
import '../components/glass_card.dart';
import '../widgets/question_display_widget.dart';
import 'edit_question/edit_question_page.dart';
import 'survey_preview_page.dart';
import '../services/config.dart';
import '../providers/theme_provider.dart';


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

class _InteractiveScale extends StatefulWidget {
  final Widget child;

  const _InteractiveScale({
    required this.child,
  });

  @override
  State<_InteractiveScale> createState() => _InteractiveScaleState();
}

class _InteractiveScaleState extends State<_InteractiveScale> {
  bool _hovered = false;
  bool _pressed = false;

  double get _scale {
    if (_pressed) return 0.98;
    if (_hovered) return 1.02;
    return 1.0;
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) {
        if (mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() => _hovered = true);
            }
          });
        }
      },
      onExit: (_) {
        if (mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() => _hovered = false);
            }
          });
        }
      },
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => setState(() => _pressed = true),
        onPointerUp: (_) => setState(() => _pressed = false),
        onPointerCancel: (_) => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _scale,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          child: widget.child,
        ),
      ),
    );
  }
}

class _EditSurveyContentPageState extends State<EditSurveyContentPage> {
  late final ApiService _apiService;
  List<Question> _questions = [];
  bool _isLoading = false;
  bool _isBgLoading = false;
  static const double _bottomButtonHeight = 44.0;
  bool _isDragOver = false;
  bool _showDragHandle = false;
  String? _desktopBackground;
  String? _mobileBackground;
  bool _isDesktopPreview = true;
  List<Question>? _previousQuestionOrder;
  bool _isPreviewLoading = false;
  bool _isDisposed = false;

  String? _lastMeasuredUrl;
  double? _bgNaturalWidth;
  double? _bgNaturalHeight;
  
  // 上传进度相关
  bool _isUploadingBackground = false;
  double _uploadProgress = 0.0;
  String _uploadStatus = '';

  @override
  void initState() {
    super.initState();
    _apiService = ApiService(authToken: widget.token);
    _loadQuestions();
    _loadBackground();
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  Future<void> _loadQuestions() async {
    Timer? loadingTimer = Timer(const Duration(milliseconds: 150), () {
      if (mounted && _isLoading) {
        setState(() => _isLoading = true);
      }
    });
    
    try {
      final questions = await _apiService.getSurveyQuestions(widget.survey.id);
      loadingTimer.cancel();
      if (!mounted) return;
      
      setState(() {
        _questions = questions;
        _isLoading = false;
      });
    } catch (e) {
      loadingTimer.cancel();
      if (!mounted) return;
      _showErrorToast('加载问题失败', e.toString());
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadBackground() async {
    try {
      if (mounted) setState(() => _isBgLoading = true);
      final backgroundData = await _apiService.getSurveyBackground(widget.survey.id);
      setState(() {
        _desktopBackground = backgroundData['desktopBackground'] as String?;
        _mobileBackground = backgroundData['mobileBackground'] as String?;
      });
      final current = _isDesktopPreview ? _desktopBackground : _mobileBackground;
      final other = _isDesktopPreview ? _mobileBackground : _desktopBackground;
      final currentAbs = toAbsoluteUrl(current ?? '');
      final otherAbs = toAbsoluteUrl(other ?? '');
      final ctx = context;
      if (current != null && current.isNotEmpty) {
        if (!ctx.mounted) return;
        try { await precacheImage(CachedNetworkImageProvider(currentAbs), ctx); } catch (_) {}
        _ensureBackgroundDimensions(currentAbs);
      }
      if (other != null && other.isNotEmpty) {
        if (!ctx.mounted) return;
        try { await precacheImage(CachedNetworkImageProvider(otherAbs), ctx); } catch (_) {}
      }
    } catch (e) {
      //静默失败了喵
    } finally {
      if (mounted) setState(() => _isBgLoading = false);
    }
  }

  void _ensureBackgroundDimensions(String absUrl) {
    if (_lastMeasuredUrl == absUrl) return;
    _lastMeasuredUrl = absUrl;
    // 使用 CachedNetworkImageProvider 与显示组件共用同一缓存体系，命中内存/磁盘缓存更快
    final ImageProvider provider = CachedNetworkImageProvider(absUrl);
    final ImageStream stream = provider.resolve(const ImageConfiguration());
    ImageStreamListener? listener;
    listener = ImageStreamListener((ImageInfo info, bool syncCall) {
      final image = info.image;
      if (mounted) {
        setState(() {
          _bgNaturalWidth = image.width.toDouble();
          _bgNaturalHeight = image.height.toDouble();
        });
      }
      stream.removeListener(listener!);
    }, onError: (error, stackTrace) {
      stream.removeListener(listener!);
    });
    stream.addListener(listener);
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

  Future<void> _openPreview() async {
    if (_isPreviewLoading) return;

    setState(() => _isPreviewLoading = true);

    try {
      final questions = await _apiService.getSurveyQuestions(widget.survey.id);
      if (!mounted || _isDisposed || ModalRoute.of(context)?.isCurrent != true) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => SurveyPreviewPage(
            survey: widget.survey,
            token: widget.token,
            questions: questions,
          ),
        ),
      );
    } catch (e) {
      if (!mounted || _isDisposed || ModalRoute.of(context)?.isCurrent != true) return;
      _showErrorToast('预览失败', e.toString());
    } finally {
      if (mounted) {
        setState(() => _isPreviewLoading = false);
      }
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
            style: context.theme.buttonStyles.outline.call,
            child: const Text('取消'),
            onPress: () => Navigator.pop(context),
          ),
          FButton(
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
        _showErrorToast('删除问题失败', e.toString());
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
        await _processUploadedFile(file, isDesktop);
      }
    } catch (e) {
      if (!mounted) return;
      _showErrorToast('上传背景图片失败', e.toString());
    }
  }

  Future<void> _processUploadedFile(PlatformFile file, bool isDesktop) async {
    setState(() {
      _isUploadingBackground = true;
      _uploadProgress = 0.0;
      _uploadStatus = '正在准备上传...';
    });
    
    try {
      String url;
      
      // Web平台使用字节数据，桌面端优先使用字节数据
      if (kIsWeb) {
        if (file.bytes != null && file.name.isNotEmpty) {
          url = await _apiService.uploadMediaUniversal(
            widget.survey.id,
            fileBytes: file.bytes!,
            fileName: file.name,
            onProgress: (sent, total) {
              if (mounted) {
                setState(() {
                  _uploadProgress = sent / total;
                });
              }
            },
            onStatus: (status, message) {
              if (mounted && message != null) {
                setState(() {
                  _uploadStatus = message;
                });
              }
            },
          );
        } else {
          throw '无法获取文件数据';
        }
      } else {
        // 桌面端优先尝试字节数据，因为FilePicker在某些情况下path可能为null
        if (file.bytes != null && file.name.isNotEmpty) {
          url = await _apiService.uploadMediaUniversal(
            widget.survey.id,
            fileBytes: file.bytes!,
            fileName: file.name,
            onProgress: (sent, total) {
              if (mounted) {
                setState(() {
                  _uploadProgress = sent / total;
                });
              }
            },
            onStatus: (status, message) {
              if (mounted && message != null) {
                setState(() {
                  _uploadStatus = message;
                });
              }
            },
          );
        } else if (file.path != null && file.path!.isNotEmpty) {
          url = await _apiService.uploadMediaUniversal(
            widget.survey.id,
            filePath: file.path!,
            onProgress: (sent, total) {
              if (mounted) {
                setState(() {
                  _uploadProgress = sent / total;
                });
              }
            },
            onStatus: (status, message) {
              if (mounted && message != null) {
                setState(() {
                  _uploadStatus = message;
                });
              }
            },
          );
        } else {
          throw '无法获取文件数据';
        }
      }
      
      setState(() {
        if (isDesktop) {
          _desktopBackground = url;
        } else {
          _mobileBackground = url;
        }
        _uploadStatus = '正在保存背景设置...';
      });
      
      await _apiService.updateSurveyBackground(
        widget.survey.id,
        desktopBackground: _desktopBackground,
        mobileBackground: _mobileBackground,
      );
      
      if (mounted) {
        setState(() {
          _isUploadingBackground = false;
          _uploadStatus = '';
        });
        _showSuccessToast('上传成功', '背景图片已更新');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isUploadingBackground = false;
          _uploadStatus = '';
        });
        _showErrorToast('上传背景图片失败', e.toString());
      }
    }
  }

  void _onReorderQuestions(int oldIndex, int newIndex) {
    _previousQuestionOrder = List<Question>.from(_questions);
    
    setState(() {
      if (oldIndex < newIndex) {
        newIndex -= 1;
      }
      final Question item = _questions.removeAt(oldIndex);
      _questions.insert(newIndex, item);
    });
    
    _updateQuestionOrder();
  }

  Future<void> _updateQuestionOrder() async {
    try {
      final questionIds = _questions.map((q) => q.id).toList();
      await _apiService.reorderQuestions(
        widget.survey.id, 
        questionIds,
        // 不传递onStatus回调，避免重复提示
      );
      
      // API调用成功后显示提示
      if (mounted) {
        _showSuccessToast('排序成功', '问题顺序已更新', canUndo: true);
      }
    } catch (e) {
      if (mounted) {
        _showErrorToast('更新问题顺序失败', e.toString());
      }
    }
  }

  Future<void> _handleDroppedFiles(List<dynamic> files) async {
    if (files.isEmpty) return;
    
    final file = files.first;
    
    if (!file.name.toLowerCase().endsWith('.jpg') && 
        !file.name.toLowerCase().endsWith('.jpeg') && 
        !file.name.toLowerCase().endsWith('.png') && 
        !file.name.toLowerCase().endsWith('.gif') && 
        !file.name.toLowerCase().endsWith('.webp')) {
      _showErrorToast('文件格式不支持', '请上传图片文件（JPG、PNG、GIF、WebP）');
      return;
    }

    try {
      final bytes = await file.readAsBytes();
      final platformFile = PlatformFile(
        name: file.name,
        size: bytes.length,
        bytes: bytes,
      );
      
      await _processUploadedFile(platformFile, _isDesktopPreview);
    } catch (e) {
      if (!mounted) return;
      _showErrorToast('处理拖拽文件失败', e.toString());
    }
  }
  
  void _showErrorToast(String title, String message) {
    showFToast(
      context: context,
      alignment: FToastAlignment.bottomRight,
      title: Text(title),
      description: Text(message),
      suffixBuilder: (context, entry) => IntrinsicHeight(
        child: FButton(
          style: context.theme.buttonStyles.outline.call,
          onPress: entry.dismiss,
          child: const Text('关闭'),
        ),
      ),
    );
  }

  void _showSuccessToast(String title, String message, {bool canUndo = false}) {
    showFToast(
      context: context,
      alignment: FToastAlignment.bottomRight,
      title: Text(title),
      description: Text(message),
      suffixBuilder: (context, entry) => IntrinsicHeight(
        child: FButton(
          style: context.theme.buttonStyles.secondary.call,
          onPress: canUndo
              ? () {
                  entry.dismiss();
                  _undoQuestionReorder();
                }
              : entry.dismiss,
          child: Text(canUndo ? '撤回' : '关闭'),
        ),
      ),
    );
  }

  void _undoQuestionReorder() {
    if (_previousQuestionOrder != null) {
      setState(() {
        _questions = List<Question>.from(_previousQuestionOrder!);
      });
      
      // 调用API恢复到之前的顺序
      final questionIds = _questions.map((q) => q.id).toList();
      _apiService.reorderQuestions(
        widget.survey.id, 
        questionIds,
        // 不传递onStatus回调，避免重复提示
      ).then((_) {
        if (mounted) {
          _showSuccessToast('撤回成功', '问题顺序已恢复');
        }
      }).catchError((e) {
        if (mounted) {
          _showErrorToast('撤回失败', e.toString());
        }
      });
      
      _previousQuestionOrder = null; // 清除撤回状态
    }
  }

  // 按钮整体缩放：屏宽分档 × DPI（ThemeProvider.dpiScale）
  double _buttonBaseScale(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    double base;
    if (width <= 360) {
      base = 0.78;
    } else if (width <= 480) {
      base = 0.84;
    } else if (width <= 600) {
      base = 0.90;
    } else if (width <= 760) {
      base = 0.96;
    } else {
      base = 1.00;
    }
    final dpi = context.watch<ThemeProvider>().dpiScale;
    final scaled = base * dpi;
    return scaled.clamp(0.70, 1.15);
  }

  double _buttonTextScale(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    double widthFactor = 1.0;
    if (width <= 360) {
      widthFactor = 0.90;
    } else if (width <= 480) {
      widthFactor = 0.94;
    } else if (width <= 600) {
      widthFactor = 0.97;
    }

    final dpi = context.watch<ThemeProvider>().dpiScale;
    final dpiFactor = (1 / dpi).clamp(0.70, 1.0);
    return (widthFactor * dpiFactor).clamp(0.55, 1.0);
  }

  Widget _buildScaledButtonText(BuildContext context, String text, {Color? color}) {
    final theme = Theme.of(context);
    final baseStyle = theme.textTheme.labelLarge ?? theme.textTheme.titleMedium ?? const TextStyle(fontSize: 14);
    final scale = _buttonTextScale(context);
    final targetFontSize = (baseStyle.fontSize ?? 14.0) * scale;

    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.center,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.visible,
        softWrap: false,
        style: baseStyle.copyWith(
          fontSize: targetFontSize,
          color: color ?? baseStyle.color,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth > 1080;
    return Scaffold(
      body: Stack(
        children: [
          const FrostedGlassBackground(),
          Column(
            children: [
              const TopSafeSpacer(),
              FHeader.nested(
                title: const Text('编辑问卷内容'),
                prefixes: [
                  FHeaderAction(
                    icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                    onPress: () => Navigator.pop(context),
                  ),
                ],
                suffixes: isWide
                    ? []
                    : [
                        FHeaderAction(
                          icon: _isPreviewLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.visibility, size: 20),
                          onPress: _isPreviewLoading ? null : _openPreview,
                        ),
                      ],
              ),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : isWide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 2,
                                child: ScrollConfiguration(
                                  behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
                                  child: CustomScrollView(
                                    slivers: [
                                      SliverToBoxAdapter(
                                        child: Padding(
                                          padding: const EdgeInsets.all(24),
                                          child: Column(
                                            children: [
                                              _buildBackgroundCard(),
                                              const SizedBox(height: 16),
                                            ],
                                          ),
                                        ),
                                      ),
                                      SliverReorderableList(
                                        itemCount: _questions.length,
                                        onReorder: _onReorderQuestions,
                                        itemBuilder: (context, index) {
                                          final question = _questions[index];
                                          return _buildQuestionListItem(question, index);
                                        },
                                      ),
                                      const SliverToBoxAdapter(child: SizedBox(height: 48)),
                                    ],
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
                          )
                        : CustomScrollView(
                            slivers: [
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    children: [
                                      _buildBackgroundCard(),
                                      const SizedBox(height: 16),
                                    ],
                                  ),
                                ),
                              ),
                              SliverReorderableList(
                                itemCount: _questions.length,
                                onReorder: _onReorderQuestions,
                                itemBuilder: (context, index) {
                                  final question = _questions[index];
                                  return _buildQuestionListItem(question, index);
                                },
                              ),
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: FButton(
                                    onPress: _addQuestion,
                                    child: const Text('添加问题'),
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

  Widget _buildActionPanel(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 预览入口
        FilledButton.icon(
          onPressed: _isPreviewLoading ? null : _openPreview,
          icon: _isPreviewLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.visibility_outlined),
          label: Text(_isPreviewLoading ? '加载中...' : '预览问卷'),
        ),
        const SizedBox(height: 12),
        // 添加问题快捷按钮
        OutlinedButton.icon(
          onPressed: _addQuestion,
          icon: const Icon(Icons.add),
          label: const Text('添加问题'),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildBackgroundCard() {
    final isCurrentDesktop = _isDesktopPreview;
    final currentImage = isCurrentDesktop ? _desktopBackground : _mobileBackground;
    final absImage = toAbsoluteUrl(currentImage ?? '');
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const double bottomHeight = 70;
    const double minHeight = 150;
    final double maxHeight = isDesktop ? 500 : 300;

    if (currentImage != null && currentImage.isNotEmpty) {
      _ensureBackgroundDimensions(absImage);
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final double maxDisplayWidth = isDesktop ? (screenWidth * 0.45).clamp(420.0, 820.0) : (screenWidth - 32);
    double? displayWidth;
    double? displayHeight;
    if (_bgNaturalWidth != null && _bgNaturalHeight != null) {
      final w = _bgNaturalWidth!;
      final h = _bgNaturalHeight!;
      final ratio = h / w;
      displayWidth = w;
      displayHeight = h;
      if (displayWidth > maxDisplayWidth) {
        displayWidth = maxDisplayWidth;
        displayHeight = displayWidth * ratio;
      }
      if (displayHeight > maxHeight) {
        displayHeight = maxHeight;
        displayWidth = displayHeight / ratio;
      }
      if (displayHeight < minHeight) {
        displayHeight = minHeight;
      }
    }

    // 目标尺寸（用于动画过渡）
    final double targetWidth = (displayWidth ?? maxDisplayWidth);
    final double targetHeight = (displayHeight ?? minHeight).clamp(minHeight, maxHeight);

    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxDisplayWidth,
          maxHeight: maxHeight,
        ),
        child: AnimatedContainer(
          width: targetWidth,
          height: targetHeight,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeInOutCubic,
          child: DropTarget(
            onDragDone: (detail) => _handleDroppedFiles(detail.files),
            onDragEntered: (detail) => setState(() => _isDragOver = true),
            onDragExited: (detail) => setState(() => _isDragOver = false),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _isDragOver ? Colors.blue.withAlpha(128) : Colors.transparent,
                  width: _isDragOver ? 2 : 0,
                ),
              ),
              child: Card(
                elevation: 0,
                color: Colors.transparent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: IntrinsicHeight(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: minHeight, maxHeight: maxHeight),
                    child: Stack(
                      children: [
                        Container(
                          width: double.infinity,
                          constraints: BoxConstraints(minHeight: minHeight, maxHeight: maxHeight),
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12)),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: (currentImage != null && currentImage.isNotEmpty)
                                ? AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 450),
                                    switchInCurve: Curves.easeOutCubic,
                                    switchOutCurve: Curves.easeInCubic,
                                    transitionBuilder: (child, animation) {
                                      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
                                      return FadeTransition(
                                        opacity: animation,
                                        child: Align(
                                          alignment: Alignment.topCenter,
                                          child: ScaleTransition(
                                            alignment: Alignment.topCenter,
                                            scale: Tween<double>(begin: 0.96, end: 1.0).animate(curved),
                                            child: child,
                                          ),
                                        ),
                                      );
                                    },
                                    child: CachedNetworkImage(
                                      key: ValueKey('${_isDesktopPreview}_$currentImage'),
                                      imageUrl: absImage,
                                      fit: BoxFit.cover,
                                      alignment: Alignment.topCenter,
                                      errorWidget: (context, url, error) => const Center(
                                        child: Icon(Icons.broken_image_outlined, size: 40),
                                      ),
                                    ),
                                  )
                                : Center(
                                    child: _isBgLoading
                                        ? Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: const [
                                              SizedBox(
                                                width: 28,
                                                height: 28,
                                                child: CircularProgressIndicator(strokeWidth: 2.5),
                                              ),
                                              SizedBox(height: 10),
                                              Text('加载壁纸中...', style: TextStyle(color: Colors.grey, fontSize: 12)),
                                            ],
                                          )
                                        : Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(
                                                _isDragOver ? Icons.cloud_upload : Icons.add_photo_alternate,
                                                size: 48,
                                                color: _isDragOver ? Colors.blue : Colors.grey,
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                                                _isDragOver ? '松开鼠标上传图片' : '还没有图片哦，快上传吧~',
                                                style: TextStyle(
                                                  color: _isDragOver ? Colors.blue : Colors.grey,
                                                  fontSize: 16,
                                                  fontWeight: _isDragOver ? FontWeight.w500 : FontWeight.normal,
                                                ),
                                              ),
                                              if (!_isDragOver)
                                                const Padding(
                                                  padding: EdgeInsets.only(top: 4),
                                                  child: Text('可以拖拽图片文件到这里', style: TextStyle(color: Colors.grey, fontSize: 12)),
                                                ),
                                            ],
                                          ),
                                  ),
                          ),
                        ),
                        if (currentImage != null && currentImage.isNotEmpty)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: ClipRRect(
                              borderRadius: const BorderRadius.only(
                                bottomLeft: Radius.circular(12),
                                bottomRight: Radius.circular(12),
                              ),
                              child: BackdropFilter(
                                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                                child: Container(
                                  width: double.infinity,
                                  height: bottomHeight,
                                  color: Colors.black.withAlpha((0.1 * 255).round()),
                                ),
                              ),
                            ),
                          ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: Container(
                            width: double.infinity,
                            height: bottomHeight,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            decoration: BoxDecoration(
                              color: (currentImage == null || currentImage.isEmpty)
                                  ? (isDark
                                      ? Colors.white.withAlpha((0.05 * 255).round())
                                      : Colors.black.withAlpha((0.05 * 255).round()))
                                  : Colors.transparent,
                              borderRadius: const BorderRadius.only(
                                bottomLeft: Radius.circular(12),
                                bottomRight: Radius.circular(12),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: const Color.fromARGB(144, 255, 227, 134),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Transform.scale(
                                      scale: _buttonBaseScale(context),
                                      alignment: Alignment.center,
                                      child: _InteractiveScale(
                                        child: SizedBox(
                                          width: double.infinity,
                                          height: _bottomButtonHeight,
                                          child: FButton.raw(
                                            style: (_) => context.theme.buttonStyles.ghost,
                                            onPress: () => _uploadBackground(isCurrentDesktop),
                                            child: Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                              child: Center(
                                                child: _buildScaledButtonText(
                                                  context,
                                                  '上传背景',
                                                  color: Colors.black,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? Colors.white.withValues(alpha: 0.14)
                                          : Colors.black.withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Transform.scale(
                                      scale: _buttonBaseScale(context),
                                      alignment: Alignment.center,
                                      child: _InteractiveScale(
                                        child: SizedBox(
                                          width: double.infinity,
                                          height: _bottomButtonHeight,
                                          child: FButton.raw(
                                            style: (_) => context.theme.buttonStyles.ghost,
                                            onPress: () => setState(() => _isDesktopPreview = !_isDesktopPreview),
                                            child: Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                              child: Center(
                                                child: _buildScaledButtonText(
                                                  context,
                                                  isCurrentDesktop ? '切换移动端' : '切换桌面端',
                                                  color: isDark ? Colors.black : Theme.of(context).colorScheme.onSurface,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        // 上传进度显示（放在Stack最后，确保在最上层）
                        if (_isUploadingBackground)
                          Positioned.fill(
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.7),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const SizedBox(
                                    width: 40,
                                    height: 40,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 3,
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    _uploadStatus,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  if (_uploadProgress > 0 && _uploadProgress < 1)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
                                      child: Column(
                                        children: [
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(4),
                                            child: LinearProgressIndicator(
                                              value: _uploadProgress,
                                              minHeight: 8,
                                              backgroundColor: Colors.white.withValues(alpha: 0.3),
                                              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            '${(_uploadProgress * 100).toInt()}%',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }


  Widget _buildQuestionListItem(Question question, int index) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      key: ValueKey(question.id),
      margin: const EdgeInsets.only(bottom: 8, left: 16, right: 16),
      child: GlassCard(
        margin: EdgeInsets.zero,
        child: GestureDetector(
          onLongPress: () {
            setState(() {
              _showDragHandle = !_showDragHandle;
            });
          },
          child: Column(
            children: [
              // 拖动条（长按卡片显示/隐藏）
              if (_showDragHandle)
                ReorderableDragStartListener(
                  index: index,
                  child: Container(
                    width: double.infinity,
                    height: 24,
                    decoration: BoxDecoration(
                      color: isDark 
                          ? Colors.white.withAlpha(26)
                          : Colors.black.withAlpha(13),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(12),
                        topRight: Radius.circular(12),
                      ),
                    ),
                    child: Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: isDark 
                              ? Colors.grey.shade600
                              : Colors.grey.shade400,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
              ListTile(
                title: QuestionDisplayWidget(
                  question: question,
                  mode: QuestionDisplayMode.preview,
                  optionStates: const {},
                  authToken: widget.token,
                  titleOnly: true,
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_getQuestionTypeText(question.type)),
                    if (question.mediaUrls.isNotEmpty)
                      Text(
                        '${question.mediaUrls.length} 个媒体文件',
                        style: TextStyle(
                          fontSize: 12, 
                          color: isDark 
                              ? Colors.grey.shade400
                              : Colors.grey.shade600,
                        ),
                      ),
                  ],
                ),
                isThreeLine: question.mediaUrls.isNotEmpty,
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
            ],
          ),
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
        return '滑块题';
      case QuestionType.textInput:
        return '填写题';
    }
  }
}