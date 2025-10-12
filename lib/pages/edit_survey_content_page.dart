
import 'dart:async';
import 'dart:ui';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:forui/forui.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
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
  bool _isDragOver = false;
  String? _desktopBackground;
  String? _mobileBackground;
  bool _isDesktopPreview = true;
  List<Question>? _previousQuestionOrder; // 用于撤回功能

  String? _lastMeasuredUrl;
  double? _bgNaturalWidth;
  double? _bgNaturalHeight;
  bool _isBgLoading = true;

  @override
  void initState() {
    super.initState();
    _apiService = ApiService(authToken: widget.token);
    _loadQuestions();
    _loadBackground();
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
    try {
      String url;
      
      // Web平台使用字节数据，桌面端优先使用字节数据
      if (kIsWeb) {
        if (file.bytes != null && file.name.isNotEmpty) {
          url = await _apiService.uploadMediaUniversal(
            widget.survey.id,
            fileBytes: file.bytes!,
            fileName: file.name,
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
          );
        } else if (file.path != null && file.path!.isNotEmpty) {
          url = await _apiService.uploadMediaUniversal(
            widget.survey.id,
            filePath: file.path!,
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
      });
      await _apiService.updateSurveyBackground(
        widget.survey.id,
        desktopBackground: _desktopBackground,
        mobileBackground: _mobileBackground,
      );
    } catch (e) {
      if (!mounted) return;
      _showErrorToast('上传背景图片失败', e.toString());
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

  void _showSuccessToast(String title, String message, {bool canUndo = false}) {
    showFToast(
      context: context,
      alignment: FToastAlignment.bottomRight,
      title: Text(title),
      description: Text(message),
      suffixBuilder: (context, entry, _) => IntrinsicHeight(
        child: FButton(
          style: context.theme.buttonStyles.secondary.copyWith(
            contentStyle: context.theme.buttonStyles.secondary.contentStyle.copyWith(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7.5),
              textStyle: FWidgetStateMap.all(
                context.theme.typography.xs.copyWith(color: context.theme.colors.secondaryForeground),
              ),
            ),
          ),
          onPress: canUndo ? () {
            entry.dismiss();
            _undoQuestionReorder();
          } : entry.dismiss,
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
                          icon: const Icon(Icons.visibility, size: 20),
                          onPress: () {
                            Navigator.push(
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
          onPressed: () {
            Navigator.push(
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
          icon: const Icon(Icons.visibility_outlined),
          label: const Text('预览问卷'),
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
                                ? InteractiveViewer(
                                    panEnabled: true,
                                    scaleEnabled: true,
                                    minScale: 0.8,
                                    maxScale: 4.0,
                                    boundaryMargin: const EdgeInsets.all(50),
                                    child: CachedNetworkImage(
                                      imageUrl: absImage,
                                      fit: BoxFit.contain,
                                      fadeInDuration: Duration.zero,
                                      fadeOutDuration: Duration.zero,
                                      progressIndicatorBuilder: (context, url, progress) =>
                                          Center(child: CircularProgressIndicator(value: progress.progress)),
                                      errorWidget: (context, url, error) =>
                                          Container(color: Colors.grey.shade200, child: const Icon(Icons.error)),
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
                                FButton(
                                  style: FButtonStyle(
                                    decoration: FWidgetStateMap.all(
                                      BoxDecoration(
                                        color: const Color.fromARGB(144, 255, 227, 134),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    contentStyle: FButtonContentStyle(
                                      textStyle: FWidgetStateMap.all(
                                        const TextStyle(
                                          color: Color.fromARGB(255, 0, 0, 0),
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                      iconStyle: FWidgetStateMap.all(const IconThemeData(color: Colors.transparent, size: 20)),
                                    ),
                                    iconContentStyle: FButtonIconContentStyle(
                                      iconStyle: FWidgetStateMap.all(const IconThemeData(color: Colors.transparent, size: 20)),
                                    ),
                                    tappableStyle: FTappableStyle(),
                                    focusedOutlineStyle: FFocusedOutlineStyle(
                                      color: Colors.transparent,
                                      width: 0.01,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  onPress: () => _uploadBackground(isCurrentDesktop),
                                  child: const Text('上传背景'),
                                ),
                                FButton(
                                  onPress: () => setState(() => _isDesktopPreview = !_isDesktopPreview),
                                  child: Text(isCurrentDesktop ? '切换移动端' : '切换桌面端'),
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
        child: Column(
          children: [
            // 拖动条 - 只有这个区域可以拖动
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