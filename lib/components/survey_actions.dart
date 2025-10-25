import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';
import '../models/survey.dart';
import '../services/api_service.dart';
import '../services/config.dart';
import '../pages/edit_survey_page.dart';

class SurveyActions extends StatelessWidget {
  final Survey survey;
  final String token;
  final ApiService apiService;
  final VoidCallback onSuccess;
  final bool compact;
  final bool useRow;

  const SurveyActions({
    super.key,
    required this.survey,
    required this.token,
    required this.apiService,
    required this.onSuccess,
    this.compact = false,
    this.useRow = false,
  });

  Future<void> _editSurvey(BuildContext context) async {
    final projects = await apiService.getProjects();
    if (!context.mounted) return;

    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => EditSurveyPage(
          token: token,
          survey: survey,
          projects: projects,
        ),
      ),
    );

    if (result == true) {
      onSuccess();
    }
  }

  Future<void> _showPublicLink(BuildContext context) async {
    // 构建公开链接 - 使用统一配置的域名和问卷的 surveyUID
    final publicLink = buildPublicSurveyUrl(survey.surveyUid);
    
    await showAdaptiveDialog(
      context: context,
      builder: (context) => FDialog(
        direction: Axis.horizontal,
        title: const Text('问卷公开链接'),
        body: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('分享以下链接，任何人都可以无需登录直接填写问卷：'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
                ),
              ),
              child: SelectableText(
                publicLink,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '注意：只有已发布状态的问卷才能被公开访问',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          FButton(
            style: FButtonStyle.outline,
            onPress: () async {
              await Clipboard.setData(ClipboardData(text: publicLink));
              if (!context.mounted) return;
              
              // 关闭Dialog
              Navigator.of(context).pop();
              
              showFToast(
                context: context,
                alignment: FToastAlignment.bottomRight,
                title: const Text('复制成功'),
                description: const Text('链接已复制到剪贴板'),
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
            },
            child: const Text('复制链接'),
          ),
          FButton(
            onPress: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteSurvey(BuildContext context) async {
    final confirmed = await showAdaptiveDialog<bool>(
      context: context,
      builder: (context) => FDialog(
        direction: Axis.horizontal,
        title: const Text('确认删除'),
        body: Text('确定要删除问卷"${survey.surveyName}"吗？此操作不可恢复。'),
        actions: [
          FButton(
            style: FButtonStyle.outline,
            onPress: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FButton(
            style: FButtonStyle.destructive,
            onPress: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await apiService.deleteSurvey(survey.id);
      if (!context.mounted) return;
      
      showFToast(
        context: context,
        alignment:FToastAlignment.bottomRight,
        title: const Text('删除成功'),
        description: const Text('问卷已删除'),
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
      onSuccess();
    } catch (e) {
      if (!context.mounted) return;
      
      showFToast(
        context: context,
        alignment:FToastAlignment.bottomRight,
        title: const Text('删除失败'),
        description: Text('删除问卷失败: $e'),
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
    if (compact) {
      // 紧凑模式：仅图标按钮，避免在窄宽度下溢出
      return Wrap(
        alignment: WrapAlignment.end,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 4,
        runSpacing: 4,
        children: [
          if (survey.surveyStatus == 1)
            IconButton(
              tooltip: '公开链接',
              icon: const Icon(Icons.link, size: 20),
              onPressed: () => _showPublicLink(context),
            ),
          IconButton(
            tooltip: '编辑',
            icon: const Icon(Icons.edit, size: 20),
            onPressed: () => _editSurvey(context),
          ),
          IconButton(
            tooltip: '删除',
            icon: const Icon(Icons.delete_outline, size: 20),
            onPressed: () => _deleteSurvey(context),
          ),
        ],
      );
    }

    if (useRow) {
      return FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerRight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
          if (survey.surveyStatus == 1) ...[
            FButton(
              style: FButtonStyle.outline,
              onPress: () => _showPublicLink(context),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.link, size: 20),
                  SizedBox(width: 6),
                  Text('公开链接'),
                ],
              ),
            ),
            const SizedBox(width: 12),
          ],
          FButton(
            onPress: () => _editSurvey(context),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.edit, size: 20),
                SizedBox(width: 6),
                Text('编辑'),
              ],
            ),
          ),
          const SizedBox(width: 12),
          FButton(
            style: FButtonStyle.destructive,
            onPress: () => _deleteSurvey(context),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.delete_outline, size: 20),
                SizedBox(width: 6),
                Text('删除'),
              ],
            ),
          ),
          ],
        ),
      );
    }

    return Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 6,
      children: [
        if (survey.surveyStatus == 1)
          FButton(
            style: FButtonStyle.outline,
            onPress: () => _showPublicLink(context),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.link,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 4),
                const Text('公开链接'),
              ],
            ),
          ),
        FButton(
          onPress: () => _editSurvey(context),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.edit,
                size: 20,
                color: Theme.of(context).brightness == Brightness.dark 
                   ? Colors.black.withValues(alpha: 0.6)
                   : Colors.white.withValues(alpha: 0.7),
              ),
              const SizedBox(width: 4),
              const Text('编辑'),
            ],
          ),
        ),
        FButton(
          style: FButtonStyle.destructive,
          onPress: () => _deleteSurvey(context),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.delete,
                size: 20,
                color: Theme.of(context).brightness == Brightness.dark 
                  ? Colors.red.shade300
                  : Colors.red.shade700,
              ),
              const SizedBox(width: 4),
              const Text('删除'),
            ],
          ),
        ),
      ],
    );
  }
}