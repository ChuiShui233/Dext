import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';
import '../components/loading_indicator.dart';
import '../utils/survey_utils.dart';

class PublicAccessDialog extends StatefulWidget {
  final Function(String) onAccess;
  final Duration animationDuration;

  const PublicAccessDialog({
    super.key,
    required this.onAccess,
    this.animationDuration = const Duration(milliseconds: 220),
  });

  @override
  State<PublicAccessDialog> createState() => _PublicAccessDialogState();
}

class _PublicAccessDialogState extends State<PublicAccessDialog> {
  final TextEditingController _surveyIdController = TextEditingController();
  bool _isLoading = false;
  bool _animateIn = false;
  bool _isClosing = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) {
        setState(() {
          _animateIn = true;
        });
      }
    });
  }

  Future<void> _closeDialogWithAnimation([VoidCallback? onComplete]) async {
    if (_isClosing) return;
    setState(() {
      _animateIn = false;
      _isClosing = true;
    });
    await Future.delayed(widget.animationDuration);
    if (mounted) {
      Navigator.of(context).pop();
      if (onComplete != null) onComplete();
    }
  }

  void _accessSurvey() async {
    final surveyId = _surveyIdController.text.trim();
    
    if (surveyId.isEmpty) {
      showFToast(
        context: context,
        alignment: FToastAlignment.bottomRight,
        title: const Text('提示'),
        description: const Text('请输入问卷ID'),
      );
      return;
    }

    if (!SurveyUtils.isValidSurveyId(surveyId)) {
      showFToast(
        context: context,
        alignment: FToastAlignment.bottomRight,
        title: const Text('提示'),
        description: const Text('问卷ID应为16位字符'),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // 关闭弹窗并执行回调
      await _closeDialogWithAnimation(() {
        widget.onAccess(surveyId);
      });
    } catch (e) {
      if (mounted) {
        showFToast(
          context: context,
          alignment: FToastAlignment.bottomRight,
          title: const Text('错误'),
          description: const Text('无法访问问卷，请稍后重试'),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _pasteFromClipboard() async {
    try {
      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
      final text = clipboardData?.text ?? '';
      
      final surveyId = SurveyUtils.extractSurveyId(text);
      
      setState(() {
        _surveyIdController.text = surveyId;
      });
      
      if (mounted) {
        showFToast(
          context: context,
          alignment: FToastAlignment.bottomRight,
          title: const Text('成功'),
          description: const Text('已粘贴问卷ID'),
        );
      }
    } catch (e) {
      if (mounted) {
        showFToast(
          context: context,
          alignment: FToastAlignment.bottomRight,
          title: const Text('失败'),
          description: const Text('粘贴失败'),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final size = MediaQuery.of(context).size;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _closeDialogWithAnimation();
      },
      child: AnimatedOpacity(
        opacity: _animateIn ? 1.0 : 0.0,
        duration: widget.animationDuration,
        curve: _animateIn ? Curves.easeOutCubic : Curves.easeInCubic,
        child: AnimatedScale(
          scale: _animateIn ? 1.0 : 0.92,
          duration: widget.animationDuration,
          curve: _animateIn ? Curves.easeOutBack : Curves.easeInCubic,
          child: Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: size.width.clamp(0, 500).toDouble(),
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.2),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // 头部
                          Padding(
                            padding: const EdgeInsets.fromLTRB(24, 24, 16, 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '访问公开问卷',
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                IconButton(
                                  onPressed: () => _closeDialogWithAnimation(),
                                  icon: const Icon(Icons.close, size: 20),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                              ],
                            ),
                          ),
                          
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '输入16位问卷ID或粘贴完整链接来访问公开问卷',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                                  ),
                                ),
                                const SizedBox(height: 24),
                                
                                Text(
                                  '问卷ID',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _surveyIdController,
                                  autofocus: true,
                                  decoration: InputDecoration(
                                    hintText: '输入16位问卷ID',
                                    hintStyle: TextStyle(
                                      color: isDark ? Colors.white54 : Colors.grey[500],
                                    ),
                                    filled: true,
                                    fillColor: isDark 
                                        ? Colors.white.withValues(alpha: 0.05)
                                        : Colors.black.withValues(alpha: 0.05),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide.none,
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                        color: isDark ? Colors.white10 : Colors.black12,
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                        color: theme.colorScheme.primary.withValues(alpha: 0.5),
                                        width: 2,
                                      ),
                                    ),
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        FIcons.clipboard,
                                        size: 18,
                                        color: theme.colorScheme.primary,
                                      ),
                                      onPressed: _pasteFromClipboard,
                                    ),
                                  ),
                                  style: theme.textTheme.bodyLarge,
                                  maxLength: 16,
                                  textInputAction: TextInputAction.go,
                                  onSubmitted: (_) => _accessSurvey(),
                                ),
                                
                                const SizedBox(height: 24),
                                
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    onPressed: _isLoading ? null : _accessSurvey,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: theme.colorScheme.primary,
                                      foregroundColor: theme.colorScheme.onPrimary,
                                      padding: const EdgeInsets.symmetric(vertical: 16),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      elevation: 0,
                                    ),
                                    child: _isLoading
                                        ? const Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              LoadingIndicator.button(),
                                              SizedBox(width: 12),
                                              Text('正在访问...', style: TextStyle(fontSize: 16)),
                                            ],
                                          )
                                        : const Text(
                                            '访问问卷',
                                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                                          ),
                                  ),
                                ),
                                
                                const SizedBox(height: 24),
                                
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primary.withValues(alpha: 0.05),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: theme.colorScheme.primary.withValues(alpha: 0.1),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.info_outline, 
                                            color: theme.colorScheme.primary,
                                            size: 18,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            '使用说明',
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: theme.colorScheme.primary,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        '• 问卷ID是16位随机字符串\n'
                                        '• 可以直接粘贴完整的问卷链接\n'
                                        '• 只能访问已发布状态的问卷\n'
                                        '• 需要登录才能访问与提交问卷',
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          height: 1.5,
                                          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],
                      ),
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

  @override
  void dispose() {
    _surveyIdController.dispose();
    super.dispose();
  }
}
