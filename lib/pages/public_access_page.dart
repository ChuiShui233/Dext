import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../widgets/top_safe_spacer.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';
import 'public_survey_page.dart';
import '../widgets/frosted_glass_background.dart';
import '../components/loading_indicator.dart';

class PublicAccessPage extends StatefulWidget {
  final VoidCallback? onBackToHome;

  const PublicAccessPage({super.key, this.onBackToHome});

  @override
  State<PublicAccessPage> createState() => _PublicAccessPageState();
}

class _PublicAccessPageState extends State<PublicAccessPage> {
  final TextEditingController _surveyIdController = TextEditingController();
  bool _isLoading = false;

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

    if (surveyId.length != 16) {
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
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PublicSurveyPage(surveyUID: surveyId),
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _pasteFromClipboard() async {
    try {
      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
      final text = clipboardData?.text ?? '';
      
      // 尝试从URL中提取问卷ID
      String surveyId = text;
      if (text.contains('?id=')) {
        final uri = Uri.tryParse(text);
        surveyId = uri?.queryParameters['id'] ?? text;
      } else if (text.contains('/')) {
        final parts = text.split('/');
        surveyId = parts.last;
      }
      
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final iconSize = dpr <= 1.5 ? 200.0 : (dpr >= 3.0 ? 80.0 : 90.0);
    
    return Scaffold(
      body: Stack(
        children: [
          const FrostedGlassBackground(),
          Column(
            children: [
              const TopSafeSpacer(),
              FHeader.nested(
                title: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('访问公开问卷'),
                  ],
                ),
                prefixes: [
                  FHeaderAction(
                    icon: const Icon(Icons.arrow_back, size: 20),
                    onPress: () => _navigateToHome(),
                  ),
                ],
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 20),
                      
                      _buildGlassCard(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            children: [
                              Icon(
                                CupertinoIcons.doc_text,
                                size: iconSize,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                '访问公开问卷',
                                style: TextStyle(
                                  fontSize: 23,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '输入16位问卷ID或粘贴完整链接来访问公开问卷',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: isDark ? Colors.white70 : Colors.grey[600],
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                      
                      const SizedBox(height: 24),
                      
                      _buildGlassCard(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '问卷ID',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _surveyIdController,
                                decoration: InputDecoration(
                                  hintText: '输入16位问卷ID',
                                  hintStyle: TextStyle(
                                    color: isDark ? Colors.white54 : Colors.grey[500],
                                  ),
                                  filled: true,
                                  fillColor: isDark 
                                      ? Colors.white.withValues(alpha: 0.1)
                                      : Colors.white.withValues(alpha: 0.8),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide.none,
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: isDark ? Colors.white24 : Colors.grey[300]!,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: isDark ? Colors.blue[300]! : Colors.blue[600]!,
                                      width: 2,
                                    ),
                                  ),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      FIcons.clipboard,
                                      color: isDark ? Colors.white70 : Colors.grey[600],
                                    ),
                                    onPressed: _pasteFromClipboard,
                                  ),
                                ),
                                style: TextStyle(
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                                maxLength: 50,
                                textInputAction: TextInputAction.go,
                                onSubmitted: (_) => _accessSurvey(),
                              ),
                            ],
                          ),
                        ),
                      ),
                      
                      const SizedBox(height: 24),
                      
                      _buildGlassCard(
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _accessSurvey,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isDark ? Colors.blue[600] : Colors.blue[700],
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 18),
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
                      ),
                      
                      const SizedBox(height: 32),
                      
                      _buildGlassCard(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.info_outline, 
                                    color: isDark ? Colors.blue[300] : Colors.blue[700],
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '使用说明',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: isDark ? Colors.blue[300] : Colors.blue[700],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                '• 问卷ID是16位随机字符串\n'
                                '• 可以直接粘贴完整的问卷链接\n'
                                '• 只能访问已发布状态的问卷\n'
                                '• 需要登录才能访问与提交问卷',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: isDark ? Colors.white70 : Colors.grey[700],
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      
                      const SizedBox(height: 24),
                      
                      Text(
                        '如果您是问卷创建者，请在问卷管理界面获取公开链接',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white54 : Colors.grey[500],
                        ),
                        textAlign: TextAlign.center,
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

  /// 玻璃卡片封装
  Widget _buildGlassCard({required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            decoration: BoxDecoration(
              color: CupertinoColors.white.withValues(alpha: 0.2),
              border: Border.all(
                color: CupertinoColors.white.withValues(alpha: 0.2),
                width: 0.8,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: child,
          ),
        ),
      ),
    );
  }

  /// 导航到主页或后退：
  /// 1) 若提供了 onBackToHome，则优先调用它（用于切换 Tab）
  /// 2) 否则尝试 maybePop 返回上一页
  /// 3) 仍不可返回时，作为兜底回到根路由 '/'
  void _navigateToHome() async {
    if (widget.onBackToHome != null) {
      widget.onBackToHome!();
      return;
    }

    final popped = await Navigator.maybePop(context);
    if (!mounted) return;
    if (!popped) {
      Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
    }
  }

  @override
  void dispose() {
    _surveyIdController.dispose();
    super.dispose();
  }
}
