import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class RecentSurveyResponsesList extends StatefulWidget {
  const RecentSurveyResponsesList({super.key});

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

      // Get auth token from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      
      if (token == null) {
        setState(() {
          errorMessage = '未登录，请先登录';
          isLoading = false;
        });
        return;
      }

      final response = await http.get(
        Uri.parse('http://127.0.0.1:11222/api/survey/recent-submissions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['submissions'] != null) {
          setState(() {
            submissions = (data['submissions'] as List)
                .map((item) => RecentSubmission.fromJson(item))
                .toList();
            isLoading = false;
          });
        } else {
          setState(() {
            submissions = [];
            isLoading = false;
          });
        }
      } else {
        setState(() {
          errorMessage = '服务器错误: ${response.statusCode}';
          isLoading = false;
        });
      }
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
    
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? theme.colorScheme.surface : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? theme.colorScheme.outline.withOpacity(0.2) : Colors.grey[200]!,
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
                  color: theme.colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          
          // 内容区域
          if (isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32.0),
                child: CircularProgressIndicator(),
              ),
            )
          else if (errorMessage.isNotEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  children: [
                    Icon(FIcons.check, color: theme.colorScheme.onSurface.withOpacity(0.4), size: 48),
                    const SizedBox(height: 16),
                    Text(
                      errorMessage,
                      style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6)),
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
            )
          else if (submissions.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  children: [
                    Icon(FIcons.messageSquare, color: theme.colorScheme.onSurface.withOpacity(0.4), size: 48),
                    const SizedBox(height: 16),
                    Text(
                      '暂无回复记录',
                      style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6)),
                    ),
                  ],
                ),
              ),
            )
          else
            // 问卷回复记录列表
            ...submissions.asMap().entries.map((entry) {
              final index = entry.key;
              final submission = entry.value;
              return Column(
                children: [
                  if (index > 0) const SizedBox(height: 16),
                  _buildResponseItem(submission),
                ],
              );
            }),
        ],
      ),
    );
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
              ? theme.colorScheme.surfaceVariant 
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
                  color: theme.colorScheme.onSurface.withOpacity(0.6),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        Text(
          submission.timeAgo,
          style: TextStyle(
            color: theme.colorScheme.onSurface.withOpacity(0.5),
            fontSize: 12,
          ),
        ),
      ],
    );
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
