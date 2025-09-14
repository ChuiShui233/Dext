import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import '../models/survey.dart';
import '../models/survey_result.dart';
import '../models/question.dart';
import '../services/api_service.dart';
import '../main.dart' show isDesktop;

class SurveyResultsPage extends StatefulWidget {
  final String token;
  final Survey survey;

  const SurveyResultsPage({
    super.key,
    required this.token,
    required this.survey,
  });

  @override
  State<SurveyResultsPage> createState() => _SurveyResultsPageState();
}

class _SurveyResultsPageState extends State<SurveyResultsPage> {
  List<SurveyResult> _results = [];
  List<Question> _questions = [];
  bool _isLoading = true;
  String? _errorMessage;
  Set<int> _selectedResults = {};
  bool _isSelectionMode = false;
  late final ApiService _apiService;
  String? _desktopBackground;
  String? _mobileBackground;
  int? _hoveredResultId; // 桌面端悬停高亮
  final ScrollController _scrollController = ScrollController();
  // 统计块缓存
  Widget? _statisticsCache;
  String _statisticsCacheKey = '';

  String _computeStatsKey() {
    // 基于结果与问题的数量及首尾 ID 简单生成 key（避免每次都重建）
    final lenR = _results.length;
    final lenQ = _questions.length;
    final firstId = lenR > 0 ? _results.first.id : -1;
    final lastId = lenR > 0 ? _results.last.id : -1;
    return '$lenR-$lenQ-$firstId-$lastId';
  }

  @override
  void initState() {
    super.initState();
    _apiService = ApiService(authToken: widget.token);
    _loadBackground();
    _loadData();
  }

  // 获取（或构建）统计块，带缓存以减少重建
  Widget _getStatisticsCard() {
    if (_results.isEmpty) return const SizedBox.shrink();
    final key = _computeStatsKey();
    if (_statisticsCacheKey == key && _statisticsCache != null) {
      return _statisticsCache!;
    }
    final card = _buildStatistics();
    _statisticsCacheKey = key;
    _statisticsCache = card;
    return card;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // 玻璃卡片（与预览页相同风格），支持高亮
  Widget _buildGlassCard({required Widget child, bool highlighted = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Material(
        color: Colors.transparent,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            decoration: BoxDecoration(
              color: highlighted
                  ? Colors.white.withAlpha(68)
                  : Colors.white.withAlpha(51),
              border: Border.all(
                color: highlighted
                    ? Colors.white.withAlpha(102)
                    : Colors.white.withAlpha(51),
                width: 0.8,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: child,
          ),
        ),
      ),
    );
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final apiService = _apiService;
      // 获取问卷结果和问题
      final futures = await Future.wait([
        apiService.getSurveyResults(widget.survey.id),
        apiService.getSurveyQuestions(widget.survey.id),
      ]);

      final results = futures[0] as List<SurveyResult>;
      final questions = futures[1] as List<Question>;

      setState(() {
        _results = results;
        _questions = questions;
        _isLoading = false;
        _selectedResults.clear();
        _isSelectionMode = false;
        // 数据更新后重置统计缓存
        _statisticsCache = null;
        _statisticsCacheKey = '';
      });
    } catch (e) {
      setState(() {
        _errorMessage = '加载数据失败: $e';
        _isLoading = false;
      });
    }
  }

  // 加载问卷壁纸（桌面/移动）
  Future<void> _loadBackground() async {
    try {
      final data = await _apiService.getSurveyBackground(widget.survey.id);
      if (!mounted) return;
      setState(() {
        _desktopBackground = data['desktopBackground'] as String?;
        _mobileBackground = data['mobileBackground'] as String?;
      });
    } catch (e) {
      // 获取失败不影响主流程
      if (!mounted) return;
      setState(() {
        _desktopBackground = null;
        _mobileBackground = null;
      });
    }
  }

  Future<void> _deleteAnswer(int answerId) async {
    try {
      final apiService = ApiService(authToken: widget.token);
      await apiService.deleteAnswer(answerId);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('删除成功')),
        );
      }
      
      _loadData(); // 重新加载数据
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败: $e')),
        );
      }
    }
  }

  Future<void> _batchDeleteAnswers() async {
    if (_selectedResults.isEmpty) return;
    
    try {
      final apiService = ApiService(authToken: widget.token);
      await apiService.batchDeleteAnswers(_selectedResults.toList());
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('成功删除 ${_selectedResults.length} 条记录')),
        );
      }
      
      _loadData(); // 重新加载数据
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('批量删除失败: $e')),
        );
      }
    }
  }

  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      if (!_isSelectionMode) {
        _selectedResults.clear();
      }
    });
  }

  void _toggleSelection(int answerId) {
    setState(() {
      if (_selectedResults.contains(answerId)) {
        _selectedResults.remove(answerId);
      } else {
        _selectedResults.add(answerId);
      }
    });
  }

  void _selectAll() {
    setState(() {
      if (_selectedResults.length == _results.length) {
        _selectedResults.clear();
      } else {
        _selectedResults = _results.map((r) => r.id).toSet();
      }
    });
  }

  Future<void> _showDeleteConfirmDialog(int answerId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => FDialog(
        direction: Axis.horizontal,
        title: const Text('确认删除'),
        body: const Text('确定要删除这条作答记录吗？此操作不可撤销。'),
        actions: [
          FButton(
            style: FButtonStyle.outline,
            onPress: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FButton(
            style: FButtonStyle.destructive,
            onPress: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      await _deleteAnswer(answerId);
    }
  }

  Future<void> _showBatchDeleteConfirmDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => FDialog(
        direction: Axis.horizontal,
        title: const Text('确认批量删除'),
        body: Text('确定要删除选中的 ${_selectedResults.length} 条作答记录吗？此操作不可撤销。'),
        actions: [
          FButton(
            style: FButtonStyle.outline,
            onPress: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FButton(
            style: FButtonStyle.destructive,
            onPress: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      await _batchDeleteAnswers();
    }
  }

  String _getQuestionTitle(int questionId) {
    final question = _questions.firstWhere(
      (q) => q.id == questionId,
      orElse: () => Question(
        id: questionId,
        title: '未知问题',
        type: QuestionType.singleChoice,
        options: [],
        required: false,
        order: 0,
      ),
    );
    return question.title;
  }

  String _getOptionText(int questionId, int optionIndex) {
    final question = _questions.firstWhere(
      (q) => q.id == questionId,
      orElse: () => Question(
        id: questionId,
        title: '未知问题',
        type: QuestionType.singleChoice,
        options: [],
        required: false,
        order: 0,
      ),
    );
    
    if (optionIndex >= 0 && optionIndex < question.options.length) {
      return question.options[optionIndex].text;
    }
    return '选项 ${optionIndex + 1}';
  }

  Widget _buildResultCard(SurveyResult result) {
    final isSelected = _selectedResults.contains(result.id);

    final isHovered = _hoveredResultId == result.id && isDesktop;

    return MouseRegion(
      onEnter: (_) => setState(() => _hoveredResultId = result.id),
      onExit: (_) => setState(() => _hoveredResultId = null),
      cursor: _isSelectionMode ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: RepaintBoundary(
        child: _buildGlassCard(
          highlighted: isHovered || isSelected,
          child: InkWell(
            onTap: _isSelectionMode ? () => _toggleSelection(result.id) : null,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (_isSelectionMode)
                        Checkbox(
                          value: isSelected,
                          onChanged: (_) => _toggleSelection(result.id),
                        ),
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '作答者: ${result.userAccount}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Row(
                              children: [
                                Text(
                                  result.createTime,
                                  style: TextStyle(
                                    fontSize: 14,
                                  ),
                                ),
                                if (!_isSelectionMode)
                                  IconButton(
                                    icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                                    onPressed: () => _showDeleteConfirmDialog(result.id),
                                    tooltip: '删除此条记录',
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                ...result.questions.map((answer) {
                  final questionTitle = _getQuestionTitle(answer.questionId);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          questionTitle,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        if (answer.selectedOptions.isNotEmpty)
                          ...answer.selectedOptions.map((optionIndex) {
                            final optionText = _getOptionText(answer.questionId, optionIndex);
                            return Padding(
                              padding: const EdgeInsets.only(left: 16, top: 2),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.check_circle,
                                    size: 16,
                                    color: Colors.green[600],
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      optionText,
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          })
                        else
                          Padding(
                            padding: const EdgeInsets.only(left: 16),
                            child: Text(
                              '未作答',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[600],
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }

  Widget _buildStatistics() {
    if (_results.isEmpty) return const SizedBox.shrink();

    final totalResponses = _results.length;
    final responsesByQuestion = <int, Map<int, int>>{};

    for (final result in _results) {
      for (final answer in result.questions) {
        responsesByQuestion[answer.questionId] ??= {};
        for (final option in answer.selectedOptions) {
          responsesByQuestion[answer.questionId]![option] =
              (responsesByQuestion[answer.questionId]![option] ?? 0) + 1;
        }
      }
    }

    return _buildGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '统计概览',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '总回答数: $totalResponses',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            ..._questions.map((question) {
              final questionStats = responsesByQuestion[question.id] ?? {};
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      question.title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...question.options.asMap().entries.map((entry) {
                      final optionIndex = entry.key;
                      final optionText = entry.value.text;
                      final count = questionStats[optionIndex] ?? 0;
                      final percentage = totalResponses > 0
                          ? (count / totalResponses * 100).toStringAsFixed(1)
                          : '0.0';

                      return Padding(
                        padding: const EdgeInsets.only(left: 16, bottom: 4),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Text(
                                optionText,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                '$count 次 ($percentage%)',
                                style: const TextStyle(fontSize: 13),
                                textAlign: TextAlign.right,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth > 800;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Stack(
        children: [
          // 背景层
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                image: (_desktopBackground != null && _desktopBackground!.isNotEmpty) ||
                       (_mobileBackground != null && _mobileBackground!.isNotEmpty)
                    ? DecorationImage(
                        image: CachedNetworkImageProvider(
                          isWide ? (_desktopBackground ?? '') : (_mobileBackground ?? ''),
                        ),
                        fit: BoxFit.cover,
                        onError: (_, __) {},
                      )
                    : null,
                gradient: (_desktopBackground == null || _desktopBackground!.isEmpty) &&
                          (_mobileBackground == null || _mobileBackground!.isEmpty)
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: isDark
                            ? [
                                const Color(0xFF0F2027),
                                const Color(0xFF203A43),
                                const Color(0xFF2C5364),
                              ]
                            : [
                                Colors.blue[50]!,
                                Colors.indigo[100]!,
                              ],
                      )
                    : null,
              ),
              child: isDark
                  ? Container(color: Colors.black.withValues(alpha: 0.4))
                  : null,
            ),
          ),

          // 内容层
          Column(
            children: [
              SizedBox(height: isDesktop ? 40 : 20),
              FHeader.nested(
                title: Text('${widget.survey.surveyName} - 作答结果'),
                prefixes: [
                  FHeaderAction(
                    icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                    onPress: () => Navigator.pop(context),
                  ),
                ],
                suffixes: [
                  if (_results.isNotEmpty && !_isSelectionMode)
                    FHeaderAction(
                      icon: const Icon(Icons.select_all, size: 20),
                      onPress: _toggleSelectionMode,
                    ),
                  if (_isSelectionMode) ...[
                    FHeaderAction(
                      icon: Icon(
                        _selectedResults.length == _results.length
                            ? Icons.deselect
                            : Icons.select_all,
                        size: 20,
                      ),
                      onPress: _selectAll,
                    ),
                    if (_selectedResults.isNotEmpty)
                      FHeaderAction(
                        icon: const Icon(Icons.delete, size: 20, color: Colors.red),
                        onPress: _showBatchDeleteConfirmDialog,
                      ),
                    FHeaderAction(
                      icon: const Icon(Icons.close, size: 20),
                      onPress: _toggleSelectionMode,
                    ),
                  ],
                  FHeaderAction(
                    icon: const Icon(Icons.refresh, size: 20),
                    onPress: _loadData,
                  ),
                ],
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _errorMessage != null
                          ? Center(
                              child: _buildGlassCard(
                                child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.error_outline,
                                        size: 64,
                                        color: Colors.red[400],
                                      ),
                                      const SizedBox(height: 16),
                                      const Text(
                                        '加载失败',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        _errorMessage!,
                                        style: const TextStyle(fontSize: 14),
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: 16),
                                      FButton(
                                        onPress: _loadData,
                                        child: const Text('重试'),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            )
                          : _results.isEmpty
                              ? Center(
                                  child: _buildGlassCard(
                                    child: Padding(
                                      padding: const EdgeInsets.all(32),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.inbox_outlined,
                                            size: 64,
                                            color: isDark ? Colors.white54 : Colors.grey,
                                          ),
                                          const SizedBox(height: 16),
                                          Text(
                                            '暂无作答结果',
                                            style: TextStyle(
                                              fontSize: 18,
                                              color: isDark ? Colors.white : Colors.black87,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            '还没有人填写这份问卷',
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: isDark ? Colors.white70 : Colors.grey[600],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                )
                              : Builder(
                                  builder: (context) {
                                    final width = MediaQuery.of(context).size.width;
                                    final double target = isDesktop ? 1100 : width;
                                    final double side = width > target ? (width - target) / 2 : 0;
                                    return ScrollConfiguration(
                                      behavior: ScrollConfiguration.of(context).copyWith(
                                        scrollbars: false,
                                        dragDevices: {
                                          PointerDeviceKind.touch,
                                          PointerDeviceKind.mouse,
                                          PointerDeviceKind.trackpad,
                                          PointerDeviceKind.stylus,
                                        },
                                      ),
                                      child: CustomScrollView(
                                        controller: _scrollController,
                                        cacheExtent: 800.0,
                                        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                                        slivers: [
                                          SliverPadding(
                                            padding: EdgeInsets.fromLTRB(side + 16, 0, side + 16, 0),
                                            sliver: SliverToBoxAdapter(child: _getStatisticsCard()),
                                          ),
                                          SliverPadding(
                                            padding: EdgeInsets.fromLTRB(side + 16, 16, side + 16, 0),
                                            sliver: SliverToBoxAdapter(
                                              child: _buildGlassCard(
                                                child: const Padding(
                                                  padding: EdgeInsets.all(16),
                                                  child: Text(
                                                    '详细回答',
                                                    style: TextStyle(
                                                      fontSize: 18,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          if (_isSelectionMode && _results.isNotEmpty)
                                            SliverPadding(
                                              padding: EdgeInsets.fromLTRB(side + 16, 0, side + 16, 0),
                                              sliver: SliverToBoxAdapter(
                                                child: _buildGlassCard(
                                                  child: Padding(
                                                    padding: const EdgeInsets.all(12),
                                                    child: Row(
                                                      children: [
                                                        Icon(
                                                          Icons.info_outline,
                                                          size: 20,
                                                          color: isDark ? Colors.white70 : Colors.grey[600],
                                                        ),
                                                        const SizedBox(width: 8),
                                                        Expanded(
                                                          child: Text(
                                                            '已选择 ${_selectedResults.length} 条记录',
                                                            style: TextStyle(
                                                              fontSize: 14,
                                                              color: isDark ? Colors.white : Colors.black87,
                                                            ),
                                                          ),
                                                        ),
                                                        if (_selectedResults.isNotEmpty)
                                                          FButton(
                                                            style: FButtonStyle.destructive,
                                                            onPress: _showBatchDeleteConfirmDialog,
                                                            child: const Text('删除选中'),
                                                          ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          if (_isSelectionMode && _results.isNotEmpty)
                                            SliverToBoxAdapter(child: SizedBox(height: 16 + 0.0)),

                                          // Masonry 瀑布流（桌面端两列），移动端单列
                                          SliverPadding(
                                            padding: EdgeInsets.fromLTRB(side + 16, 0, side + 16, 0),
                                            sliver: SliverLayoutBuilder(
                                              builder: (context, constraints) {
                                                // 根据右侧可用宽度自适应列数：>=1200 三列，>=720 两列，否则一列
                                                final width = constraints.crossAxisExtent;
                                                final crossAxisCount = width >= 1200
                                                    ? 3
                                                    : (width >= 720 ? 2 : 1);

                                                if (crossAxisCount > 1) {
                                                  return SliverMasonryGrid.count(
                                                    crossAxisCount: crossAxisCount,
                                                    mainAxisSpacing: 16,
                                                    crossAxisSpacing: 16,
                                                    childCount: _results.length,
                                                    itemBuilder: (context, index) => _buildResultCard(_results[index]),
                                                  );
                                                }
                                                return SliverList.separated(
                                                  itemCount: _results.length,
                                                  separatorBuilder: (_, __) => const SizedBox(height: 0),
                                                  itemBuilder: (context, index) => _buildResultCard(_results[index]),
                                                );
                                              },
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

