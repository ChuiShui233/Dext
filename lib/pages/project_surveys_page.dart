import 'dart:async';
import 'package:dext/utils/error_formatter.dart';
import 'package:flutter/material.dart';
import '../widgets/top_safe_spacer.dart';
import 'package:forui/forui.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart';
import '../models/project.dart';
import '../models/survey.dart';
import '../services/api_service.dart';
import '../components/survey_actions.dart';
import '../widgets/frosted_glass_background.dart';
import '../components/glass_card.dart';
import '../components/pull_to_refresh_wrapper.dart';
import '../components/loading_indicator.dart';

class ProjectSurveysPage extends StatefulWidget {
  final String token;
  final Project project;
  
  const ProjectSurveysPage({
    super.key,
    required this.token,
    required this.project,
  });

  @override
  State<ProjectSurveysPage> createState() => _ProjectSurveysPageState();
}

class _ProjectSurveysPageState extends State<ProjectSurveysPage> with WidgetsBindingObserver {
  late final ApiService _apiService;
  List<Survey> _surveys = [];
  bool _isLoading = true;
  
  final RefreshController _refreshController = RefreshController(initialRefresh: false);
  
  Timer? _autoRefreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _apiService = ApiService(authToken: widget.token);
    _loadSurveys();
    
    _startAutoRefresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshController.dispose();
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadSurveys();
      _startAutoRefresh();
    } else if (state == AppLifecycleState.paused) {
      _stopAutoRefresh();
    }
  }

  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) {
        _loadSurveys(silent: true);
      }
    });
  }

  void _stopAutoRefresh() {
    _autoRefreshTimer?.cancel();
  }

  void _onRefresh() async {
    await _loadSurveys(silent: false, skipCache: true);
    _refreshController.refreshCompleted();
  }

  Future<void> _loadSurveys({bool silent = false, bool skipCache = false}) async {
    if (!mounted) return;
    
    if (!silent) {
      setState(() => _isLoading = true);
    }
    
    try {
      final surveys = await _apiService.getSurveys(skipCache: skipCache);
      if (!mounted) return;
      
      setState(() {
        _surveys = surveys.where((survey) => survey.projectId == widget.project.id).toList();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      
      setState(() => _isLoading = false);
      
      if (!silent) {
        showFToast(
          context: context,
          alignment:FToastAlignment.bottomRight,
          title: const Text('加载失败'),
          description: Text(ErrorFormatter.format(e)),
          suffixBuilder: (context, entry) => IntrinsicHeight(
            child: FButton(
              style: context.theme.buttonStyles.primary.call,
              onPress: entry.dismiss.call,
              child: const Text('关闭'),
            ),
          ),
        );
      }
    }
  }

  String _getSurveyTypeText(int type) {
    switch (type) {
      case 0:
        return '普通问卷';
      case 1:
        return '限时问卷';
      case 2:
        return '限次问卷';
      case 3:
        return '自选风格';
      default:
        return '未知类型';
    }
  }

  String _getSurveyStatusText(int status) {
    switch (status) {
      case 0:
        return '未发布';
      case 1:
        return '发布中';
      case 2:
        return '已完结';
      default:
        return '未知状态';
    }
  }

  Color _getStatusColor(int status) {
    switch (status) {
      case 0:
        return Colors.grey;
      case 1:
        return Colors.green;
      case 2:
        return Colors.orange;
      default:
        return Colors.grey;
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
                title: Row(
                  children: [
                    const SizedBox(width: 16),
                    Text(widget.project.projectName),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '共 ${_surveys.length} 份问卷',
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                prefixes: [
                  FHeaderAction(
                    icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                    onPress: () => Navigator.pop(context),
                  ),
                ],
                suffixes: [
                  FHeaderAction(
                    icon: const Icon(Icons.refresh, size: 20),
                    onPress: () {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        _refreshController.requestRefresh();
                      });
                    },
                  ),
                ],
              ),
              Expanded(
                child: _isLoading
                    ? const LoadingIndicator.page()
                    : _surveys.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.assignment_outlined,
                                  size: 64,
                                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  '暂无问卷',
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '该项目下还没有问卷',
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : PullToRefreshWrapper(
                            controller: _refreshController,
                            onRefresh: _onRefresh,
                            child: ListView.builder(
                              itemCount: _surveys.length,
                              itemBuilder: (context, index) {
                                final survey = _surveys[index];
                                return GlassCard(
                                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  child: Stack(
                                    clipBehavior: Clip.hardEdge,
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 60), // 底部预留按钮空间
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              survey.surveyName,
                                              style: TextStyle(
                                                color: Theme.of(context).brightness == Brightness.dark 
                                                  ? Colors.white 
                                                  : Colors.black87,
                                                fontWeight: FontWeight.w500,
                                                fontSize: 16,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              survey.description,
                                              style: TextStyle(
                                                color: Theme.of(context).brightness == Brightness.dark 
                                                  ? Colors.white70 
                                                  : Colors.black54,
                                              ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 8),
                                            Row(
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: _getStatusColor(survey.surveyStatus).withValues(alpha: 0.1),
                                                    borderRadius: BorderRadius.circular(20),
                                                    border: Border.all(
                                                      color: _getStatusColor(survey.surveyStatus).withValues(alpha: 0.3),
                                                    ),
                                                  ),
                                                  child: Text(
                                                    _getSurveyStatusText(survey.surveyStatus),
                                                    style: TextStyle(
                                                      color: _getStatusColor(survey.surveyStatus),
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: (Theme.of(context).brightness == Brightness.dark
                                                      ? Colors.white.withValues(alpha: 0.05)
                                                      : Colors.black.withValues(alpha: 0.05)),
                                                    borderRadius: BorderRadius.circular(12),
                                                    border: Border.all(
                                                      color: (Theme.of(context).brightness == Brightness.dark
                                                        ? Colors.white.withValues(alpha: 0.1)
                                                        : Colors.black.withValues(alpha: 0.1)),
                                                    ),
                                                  ),
                                                  child: Text(
                                                    _getSurveyTypeText(survey.surveyType),
                                                    style: TextStyle(
                                                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8),
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      Positioned(
                                        left: 0,
                                        right: 0,
                                        bottom: 0,
                                        child: Container(
                                          alignment: Alignment.centerRight,
                                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                                          child: FittedBox(
                                            fit: BoxFit.scaleDown,
                                            alignment: Alignment.centerRight,
                                            child: Align(
                                              alignment: Alignment.centerRight,
                                              child: SurveyActions(
                                                survey: survey,
                                                token: widget.token,
                                                apiService: _apiService,
                                                useRow: true,
                                                onSuccess: () {
                                                  WidgetsBinding.instance.addPostFrameCallback((_) {
                                                    _refreshController.requestRefresh();
                                                  });
                                                },
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
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