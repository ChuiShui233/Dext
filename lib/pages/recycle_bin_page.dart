import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import '../models/survey_result.dart';
import '../services/api_service.dart';
import '../utils/date_format.dart';
import '../widgets/top_safe_spacer.dart';
import '../widgets/downscaled_blur.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/config.dart';

class RecycleBinPage extends StatefulWidget {
  final String token;
  final int surveyId;
  final String surveyName;
  final String? desktopBackground;
  final String? mobileBackground;

  const RecycleBinPage({
    super.key,
    required this.token,
    required this.surveyId,
    required this.surveyName,
    this.desktopBackground,
    this.mobileBackground,
  });

  @override
  State<RecycleBinPage> createState() => _RecycleBinPageState();
}

class _RecycleBinPageState extends State<RecycleBinPage> {
  late final ApiService _apiService;
  List<SurveyResult> _deletedResults = [];
  bool _isLoading = true;
  String? _errorMessage;
  Set<int> _selectedIds = {};
  bool _isSelectionMode = false;

  @override
  void initState() {
    super.initState();
    _apiService = ApiService(authToken: widget.token);
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final data = await _apiService.getRecycleBinAnswers(widget.surveyId);
      if (mounted) {
        setState(() {
          _deletedResults = data.map((json) => SurveyResult.fromJson(json)).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _restoreAnswer(int id) async {
    showFDialog(
      context: context,
      builder: (context, style, animation) => FDialog(
        direction: Axis.horizontal,
        style: style.call,
        animation: animation,
        title: const Text('确认恢复'),
        body: const Text('确定要恢复这条作答记录吗？'),
        actions: [
          FButton(
            style: context.theme.buttonStyles.primary.call,
            onPress: () {
              Navigator.pop(context);
              // 第二次确认
              showFDialog(
                context: context,
                builder: (context, style, animation) => FDialog(
                  direction: Axis.horizontal,
                  style: style.call,
                  animation: animation,
                  title: const Text('警告'),
                  body: const Text('除非你知道你在做什么，否则不要随意恢复！'),
                  actions: [
                    FButton(
                      style: context.theme.buttonStyles.outline.call,
                      onPress: () => Navigator.pop(context),
                      child: const Text('取消'),
                    ),
                    FButton(
                      style: context.theme.buttonStyles.primary.call,
                      onPress: () async {
                        final currentContext = context;
                        Navigator.pop(currentContext);
                        try {
                          await _apiService.restoreAnswer(id);
                          if (currentContext.mounted) {
                            showFToast(
                              context: currentContext,
                              alignment: FToastAlignment.bottomRight,
                              title: const Text('已恢复作答记录'),
                              suffixBuilder: (context, entry) => IntrinsicHeight(
                                child: FButton(
                                  style: context.theme.buttonStyles.primary.call,
                                  onPress: entry.dismiss,
                                  child: const Text('关闭'),
                                ),
                              ),
                            );
                            _loadData();
                          }
                        } catch (e) {
                          if (currentContext.mounted) {
                            showFToast(
                              context: currentContext,
                              alignment: FToastAlignment.bottomRight,
                              title: const Text('恢复失败'),
                              description: Text('恢复作答记录失败: $e'),
                              suffixBuilder: (context, entry) => IntrinsicHeight(
                                child: FButton(
                                  style: context.theme.buttonStyles.primary.call,
                                  onPress: entry.dismiss,
                                  child: const Text('关闭'),
                                ),
                              ),
                            );
                          }
                        }
                      },
                      child: const Text('我确定'),
                    ),
                  ],
                ),
              );
            },
            child: const Text('确定'),
          ),
          FButton(
            style: context.theme.buttonStyles.outline.call,
            onPress: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  Future<void> _batchRestore() async {
    if (_selectedIds.isEmpty) return;

    showFDialog(
      context: context,
      builder: (context, style, animation) => FDialog(
        direction: Axis.horizontal,
        style: style.call,
        animation: animation,
        title: const Text('确认批量恢复'),
        body: Text('确定要恢复选中的 ${_selectedIds.length} 条记录吗？'),
        actions: [
          FButton(
            style: context.theme.buttonStyles.primary.call,
            onPress: () {
              Navigator.pop(context);
              // 第二次确认
              showFDialog(
                context: context,
                builder: (context, style, animation) => FDialog(
                  direction: Axis.horizontal,
                  style: style.call,
                  animation: animation,
                  title: const Text('警告'),
                  body: const Text('除非你知道你在做什么，否则不要随意恢复！'),
                  actions: [
                    FButton(
                      style: context.theme.buttonStyles.outline.call,
                      onPress: () => Navigator.pop(context),
                      child: const Text('取消'),
                    ),
                    FButton(
                      style: context.theme.buttonStyles.primary.call,
                      onPress: () async {
                        final currentContext = context;
                        Navigator.pop(currentContext);
                        try {
                          await _apiService.batchRestoreAnswers(_selectedIds.toList());
                          if (currentContext.mounted) {
                            showFToast(
                              context: currentContext,
                              alignment: FToastAlignment.bottomRight,
                              title: Text('已恢复 ${_selectedIds.length} 条记录'),
                              suffixBuilder: (context, entry) => IntrinsicHeight(
                                child: FButton(
                                  style: context.theme.buttonStyles.primary.call,
                                  onPress: entry.dismiss,
                                  child: const Text('关闭'),
                                ),
                              ),
                            );
                            setState(() {
                              _selectedIds.clear();
                              _isSelectionMode = false;
                            });
                            _loadData();
                          }
                        } catch (e) {
                          if (currentContext.mounted) {
                            showFToast(
                              context: currentContext,
                              alignment: FToastAlignment.bottomRight,
                              title: const Text('批量恢复失败'),
                              description: Text('批量恢复作答记录失败: $e'),
                              suffixBuilder: (context, entry) => IntrinsicHeight(
                                child: FButton(
                                  style: context.theme.buttonStyles.primary.call,
                                  onPress: entry.dismiss,
                                  child: const Text('关闭'),
                                ),
                              ),
                            );
                          }
                        }
                      },
                      child: const Text('我确定'),
                    ),
                  ],
                ),
              );
            },
            child: const Text('确定'),
          ),
          FButton(
            style: context.theme.buttonStyles.outline.call,
            onPress: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      if (!_isSelectionMode) {
        _selectedIds.clear();
      }
    });
  }

  void _toggleSelection(int id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _selectAll() {
    setState(() {
      if (_selectedIds.length == _deletedResults.length) {
        _selectedIds.clear();
      } else {
        _selectedIds = _deletedResults.map((r) => r.id).toSet();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth > 800;

    return Scaffold(
      body: Stack(
        children: [
          // Background
          Positioned.fill(
            child: DownscaledBlur(
              sigma: 30,
              downscale: 0.4,
              child: (widget.desktopBackground != null && widget.desktopBackground!.isNotEmpty) ||
                     (widget.mobileBackground != null && widget.mobileBackground!.isNotEmpty)
                  ? Container(
                      decoration: BoxDecoration(
                        image: DecorationImage(
                          image: CachedNetworkImageProvider(
                            isWide
                                ? toAbsoluteUrl(widget.desktopBackground)
                                : toAbsoluteUrl(widget.mobileBackground),
                          ),
                          fit: BoxFit.cover,
                        ),
                      ),
                      child: Container(
                        color: (isDark ? Colors.black : Colors.white).withValues(alpha: 0.3),
                      ),
                    )
                  : Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: isDark
                              ? [Colors.grey[900]!, Colors.black]
                              : [Colors.blue[50]!, Colors.purple[50]!],
                        ),
                      ),
                    ),
            ),
          ),
          Column(
            children: [
              const TopSafeSpacer(),
              FHeader.nested(
                title: Text('${widget.surveyName} - 回收站'),
                prefixes: [
                  FHeaderAction(
                    icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                    onPress: () => Navigator.pop(context),
                  ),
                ],
                suffixes: [
                  if (_deletedResults.isNotEmpty && !_isSelectionMode)
                    FHeaderAction(
                      icon: const Icon(Icons.select_all, size: 20),
                      onPress: _toggleSelectionMode,
                    ),
                  if (_isSelectionMode) ...[
                    FHeaderAction(
                      icon: Icon(
                        _selectedIds.length == _deletedResults.length
                            ? Icons.deselect
                            : Icons.select_all,
                        size: 20,
                      ),
                      onPress: _selectAll,
                    ),
                    FHeaderAction(
                      icon: const Icon(Icons.restore, size: 20),
                      onPress: _batchRestore,
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
                  padding: const EdgeInsets.all(16.0),
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _errorMessage != null
                          ? Center(child: Text(_errorMessage!))
                          : _deletedResults.isEmpty
                              ? const Center(child: Text('回收站为空'))
                              : ListView.builder(
                                  itemCount: _deletedResults.length,
                                  itemBuilder: (context, index) {
                                    final result = _deletedResults[index];
                                    final isSelected = _selectedIds.contains(result.id);
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 12),
                                      child: _buildGlassCard(
                                        highlighted: isSelected,
                                        child: InkWell(
                                          onTap: _isSelectionMode ? () => _toggleSelection(result.id) : null,
                                          child: Padding(
                                            padding: const EdgeInsets.all(16),
                                            child: Row(
                                              children: [
                                                if (_isSelectionMode)
                                                  Padding(
                                                    padding: const EdgeInsets.only(right: 12),
                                                    child: Checkbox(
                                                      value: isSelected,
                                                      onChanged: (_) => _toggleSelection(result.id),
                                                    ),
                                                  ),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        '作答者: ${result.userAccount}',
                                                        style: const TextStyle(
                                                          fontSize: 16,
                                                          fontWeight: FontWeight.bold,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 4),
                                                      Text(
                                                        '提交时间: ${DateFormatUtils.formatIsoString(result.createTime)}',
                                                        style: const TextStyle(fontSize: 14),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                if (!_isSelectionMode)
                                                  FButton(
                                                    style: context.theme.buttonStyles.ghost.call,
                                                    onPress: () => _restoreAnswer(result.id),
                                                    child: const Icon(Icons.restore, color: Colors.lightGreen),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ),
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

  Widget _buildGlassCard({required Widget child, bool highlighted = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: (highlighted
                ? (isDark ? Colors.blue.withValues(alpha: 0.2) : Colors.blue.withValues(alpha: 0.1))
                : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.6))) ,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: highlighted
              ? Colors.blue.withValues(alpha: 0.5)
              : (isDark ? Colors.white.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.2)),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: child,
      ),
    );
  }
}
