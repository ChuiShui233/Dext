// file: edit_survey_content_page.dart

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '/pages/survey_preview_page.dart';
import '../models/question.dart';
import '../models/survey.dart';
import '../services/api_service.dart';
import '../main.dart' show isDesktop;
import 'edit_question_page.dart';



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
  bool _isDesktopPreview = isDesktop;
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
      _showErrorToast('加载问题失败', e.toString());
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
      // 如果获取背景失败，使用默认值（空），不显示错误提示
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
      _showErrorToast('上传背景图片失败', e.toString());
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
            title: const Text('编辑问卷内容'),
            prefixes: [
              FHeaderAction(
                icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                onPress: () => Navigator.pop(context),
              ),
            ],
            suffixes: [
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
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _buildBackgroundCard(),
                      const SizedBox(height: 16),
                      ..._questions.map((question) => _buildQuestionListItem(question)),
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
    );
  }

Widget _buildBackgroundCard() {
  final isCurrentDesktop = _isDesktopPreview;
  final currentImage = isCurrentDesktop ? _desktopBackground : _mobileBackground;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  const double bottomHeight = 70; // 底部模糊/半透明容器高度

  return Card(
    elevation: 2,
    color: isDark ? Colors.transparent : Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(
        color: isDark ? Colors.white.withAlpha(25) : Colors.black.withAlpha(25),
        width: 1,
      ),
    ),
    child: Stack(
      children: [
        // 背景图片
        Container(
          width: double.infinity,
          height: 220,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: currentImage != null && currentImage.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: currentImage,
                    fit: BoxFit.cover,
                    progressIndicatorBuilder: (context, url, progress) =>
                        Center(child: CircularProgressIndicator(value: progress.progress)),
                    errorWidget: (context, url, error) =>
                        Container(color: Colors.grey.shade200, child: const Icon(Icons.error)),
                  )
                : const Center(
                    child: Text(
                      '还没有图片哦，快上传吧~',
                      style: TextStyle(color: Colors.grey, fontSize: 16),
                    ),
                  ),
          ),
        ),
        // 模糊背景容器（仅有图片时显示）
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
                  color: Colors.black.withOpacity(0.1),
                ),
              ),
            ),
          ),
        // 按钮固定显示在底部
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            width: double.infinity,
            height: bottomHeight, // 与模糊容器高度一致
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: currentImage == null || currentImage.isEmpty
                  ? (isDark
                      ? Colors.white.withOpacity(0.05)
                      : Colors.black.withOpacity(0.05))
                  : Colors.transparent,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(12),
                bottomRight: Radius.circular(12),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // 左下角 上传按钮
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
                      iconStyle: FWidgetStateMap.all(
                        const IconThemeData(
                          color: Colors.transparent,
                          size: 20,
                        ),
                      ),
                    ),
                    iconContentStyle: FButtonIconContentStyle(
                      iconStyle: FWidgetStateMap.all(
                        const IconThemeData(
                          color: Colors.transparent,
                          size: 20,
                        ),
                      ),
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
                // 右下角 切换按钮
                FButton(
                  onPress: () {
                    setState(() {
                      _isDesktopPreview = !_isDesktopPreview;
                    });
                  },
                  child: Text(isCurrentDesktop ? '切换移动端' : '切换桌面端'),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}


  Widget _buildQuestionListItem(Question question) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
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
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_getQuestionTypeText(question.type)),
            if (question.mediaUrls.isNotEmpty)
              Text(
                '${question.mediaUrls.length} 个媒体文件',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
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