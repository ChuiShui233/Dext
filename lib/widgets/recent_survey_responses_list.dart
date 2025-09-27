import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import '../services/api_service.dart';

class RecentSurveyResponsesList extends StatefulWidget {
  /// 当在桌面端需要与图表卡片等高时，传入一个固定高度以启用内部滚动
  final double? fixedHeight;

  const RecentSurveyResponsesList({super.key, this.fixedHeight});

  @override
  State<RecentSurveyResponsesList> createState() => _RecentSurveyResponsesListState();
}

class _RecentSurveyResponsesListState extends State<RecentSurveyResponsesList> {
  List<RecentSubmission> submissions = [];
  bool isLoading = true;
  String errorMessage = '';

  @override
  void initState() {
    super.initState();
    _loadRecentSubmissions();
  }

  Future<void> _loadRecentSubmissions() async {
    try {
      setState(() {
        isLoading = true;
        errorMessage = '';
      });

      final api = ApiService();
      final list = await api.getRecentSubmissions();
      setState(() {
        submissions = list.map((e) => RecentSubmission.fromJson(e)).toList();
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        errorMessage = '加载失败: $e';
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    final card = Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? theme.colorScheme.surface.withValues(alpha: 0.6) : Colors.white.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? theme.colorScheme.outline.withValues(alpha: 0.2) : Colors.grey[200]!,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '最近回复',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              Text(
                '共 ${submissions.length} 个回复',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (widget.fixedHeight == null)
            _buildBodyStatic(theme)
          else
            SizedBox(height: widget.fixedHeight, child: _buildBodyScrollable(theme)),
        ],
      ),
    );

    return card;
  }

  Widget _buildResponseItem(RecentSubmission submission) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Row(
      children: [
        // 用户头像
        CircleAvatar(
          radius: 20,
          backgroundColor: isDark 
              ? theme.colorScheme.surfaceContainerHighest 
              : Colors.grey[200],
          backgroundImage: submission.avatarUrl != null 
              ? NetworkImage(submission.avatarUrl!)
              : null,
          child: submission.avatarUrl == null
              ? Text(
                  submission.username.isNotEmpty 
                      ? submission.username[0].toUpperCase()
                      : '?',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: isDark 
                        ? theme.colorScheme.onSurfaceVariant 
                        : Colors.black,
                  ),
                )
              : null,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                submission.username,
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              Text(
                submission.surveyName,
                style: TextStyle(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        Text(
          submission.timeAgo,
          style: TextStyle(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  // 静态（不滚动）内容：移动端或未指定高度时使用
  Widget _buildBodyStatic(ThemeData theme) {
    if (isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: CircularProgressIndicator(),
        ),
      );
    } else if (errorMessage.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            children: [
              Icon(FIcons.check, color: theme.colorScheme.onSurface.withValues(alpha: 0.4), size: 48),
              const SizedBox(height: 16),
              Text(
                errorMessage,
                style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FButton(
                onPress: _loadRecentSubmissions,
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    } else if (submissions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            children: [
              Icon(FIcons.messageSquare, color: theme.colorScheme.onSurface.withValues(alpha: 0.4), size: 48),
              const SizedBox(height: 16),
              Text(
                '暂无回复记录',
                style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
              ),
            ],
          ),
        ),
      );
    } else {
      return Column(
        children: [
          ...submissions.asMap().entries.map((entry) {
            final index = entry.key;
            final submission = entry.value;
            return Column(
              children: [
                if (index > 0) const SizedBox(height: 16),
                _buildResponseItem(submission),
              ],
            );
          })
        ],
      );
    }
  }

  // 可滚动内容：当提供 fixedHeight 时，使用 ListView 以避免溢出
  Widget _buildBodyScrollable(ThemeData theme) {
    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    } else if (errorMessage.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(FIcons.check, color: theme.colorScheme.onSurface.withValues(alpha: 0.4), size: 48),
              const SizedBox(height: 16),
              Text(
                errorMessage,
                style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FButton(
                onPress: _loadRecentSubmissions,
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    } else if (submissions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(FIcons.messageSquare, color: theme.colorScheme.onSurface.withValues(alpha: 0.4), size: 48),
              const SizedBox(height: 16),
              Text(
                '暂无回复记录',
                style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
              ),
            ],
          ),
        ),
      );
    } else {
      return ListView.separated(
        padding: EdgeInsets.zero,
        itemBuilder: (context, index) => _buildResponseItem(submissions[index]),
        separatorBuilder: (context, index) => const SizedBox(height: 16),
        itemCount: submissions.length,
      );
    }
  }
}

class RecentSubmission {
  final String username;
  final String? avatarUrl;
  final String surveyName;
  final String timeAgo;

  RecentSubmission({
    required this.username,
    this.avatarUrl,
    required this.surveyName,
    required this.timeAgo,
  });

  factory RecentSubmission.fromJson(Map<String, dynamic> json) {
    return RecentSubmission(
      username: json['username'] ?? '',
      avatarUrl: json['avatarUrl'],
      surveyName: json['surveyName'] ?? '',
      timeAgo: json['timeAgo'] ?? '',
    );
  }
}
