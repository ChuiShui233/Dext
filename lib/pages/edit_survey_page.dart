import 'package:dext/pages/survey_preview_page.dart';
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import '../models/survey.dart';
import '../models/question.dart';
import '../models/project.dart';
import '../services/api_service.dart';
import '../widgets/frosted_glass_background.dart';
import '../widgets/top_safe_spacer.dart';
import 'edit_survey_content_page.dart';
import 'survey_results_page.dart';

class EditSurveyPage extends StatefulWidget {
  final String token;
  final Survey survey;
  final List<Project> projects;

  const EditSurveyPage({
    super.key,
    required this.token,
    required this.survey,
    required this.projects,
  });

  @override
  State<EditSurveyPage> createState() => _EditSurveyPageState();
}

class TimeLimitPage extends StatefulWidget {
  final int initialDays;
  final int initialHours;
  final int initialMinutes;

  const TimeLimitPage({
    super.key,
    required this.initialDays,
    required this.initialHours,
    required this.initialMinutes,
  });

  @override
  State<TimeLimitPage> createState() => _TimeLimitPageState();
}

class _TimeLimitPageState extends State<TimeLimitPage> with TickerProviderStateMixin {
  late int _days;
  late int _hours;
  late int _minutes;
  
  final _daysSelectKey = GlobalKey();
  final _hoursSelectKey = GlobalKey();
  final _minutesSelectKey = GlobalKey();
  
  late final FSelectController<int> _daysController;
  late final FSelectController<int> _hoursController;
  late final FSelectController<int> _minutesController;

  @override
  void initState() {
    super.initState();
    _days = widget.initialDays;
    _hours = widget.initialHours;
    _minutes = widget.initialMinutes;
    
    _daysController = FSelectController<int>(vsync: this);
    _hoursController = FSelectController<int>(vsync: this);
    _minutesController = FSelectController<int>(vsync: this);
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _daysController.value = _days;
      _hoursController.value = _hours;
      _minutesController.value = _minutes;
    });
  }

  @override
  void dispose() {
    _daysController.dispose();
    _hoursController.dispose();
    _minutesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置截止时间'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '请选择问卷截止时间',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 100,
                  child: FSelect<int>(
                    key: _daysSelectKey,
                    controller: _daysController,
                    hint: '天数',
                    onChange: (value) {
                      setState(() {
                        _days = value ?? 0;
                      });
                    },
                    items: { for (var index = 0; index < 31; index++) '$index天': index },
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 100,
                  child: FSelect<int>(
                    key: _hoursSelectKey,
                    controller: _hoursController,
                    hint: '小时',
                    onChange: (value) {
                      setState(() {
                        _hours = value ?? 0;
                      });
                    },
                    items: { for (var index = 0; index < 24; index++) '${index.toString().padLeft(2, '0')}时': index },
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 100,
                  child: FSelect<int>(
                    key: _minutesSelectKey,
                    controller: _minutesController,
                    hint: '分钟',
                    onChange: (value) {
                      setState(() {
                        _minutes = value ?? 0;
                      });
                    },
                    items: { for (var index = 0; index < 60; index++) '${index.toString().padLeft(2, '0')}分': index },
                  ),
                ),
              ],
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: FButton(
                style: context.theme.buttonStyles.primary.call,
                onPress: () {
                  if (_days == 0 && _hours == 0 && _minutes == 0) {
                    showFToast(
                      context: context,
                      alignment:FToastAlignment.bottomRight,
                      title: const Text('提示'),
                      description: const Text('请至少设置一个时间单位'),
                      suffixBuilder: (context, entry) => IntrinsicHeight(
                        child: FButton(
                          style: context.theme.buttonStyles.primary.call,
                          onPress: entry.dismiss.call,
                          child: const Text('关闭'),
                        ),
                      ),
                    );
                    return;
                  }
                  Navigator.pop(context, {
                    'days': _days,
                    'hours': _hours,
                    'minutes': _minutes,
                  });
                },
                child: const Text('确定'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditSurveyPageState extends State<EditSurveyPage> with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _totalTimesController = TextEditingController();
  final _perUserLimitController = TextEditingController();
  
  // 为每个 FSelect 创建唯一的 key
  final _projectSelectKey = GlobalKey();
  final _typeSelectKey = GlobalKey();
  final _statusSelectKey = GlobalKey();
  final _daysSelectKey = GlobalKey();
  final _hoursSelectKey = GlobalKey();
  final _minutesSelectKey = GlobalKey();
  
  late final FSelectController<int> _projectSelectController;
  late final FSelectController<int> _typeSelectController;
  late final FSelectController<int> _statusSelectController;
  int? _selectedProjectId;
  int? _selectedType;
  int? _selectedStatus;
  bool _isLoading = false;
  int _selectedDays = 0;
  int _selectedHours = 0;
  int _selectedMinutes = 0;
  bool _autoSubmit = false;
  bool _allowAnonymous = false;

  @override
  void initState() {
    super.initState();
    _projectSelectController = FSelectController<int>(vsync: this);
    _typeSelectController = FSelectController<int>(vsync: this);
    _statusSelectController = FSelectController<int>(vsync: this);

    _titleController.text = widget.survey.surveyName;
    _descriptionController.text = widget.survey.description;
    _selectedProjectId = widget.survey.projectId;
    _selectedType = widget.survey.surveyType;
    _selectedStatus = widget.survey.surveyStatus;
    _totalTimesController.text = widget.survey.totalTimes > 0 ? widget.survey.totalTimes.toString() : '';
    _perUserLimitController.text = (widget.survey.perUserLimit != null && widget.survey.perUserLimit! > 0)
        ? widget.survey.perUserLimit!.toString()
        : '';
    _autoSubmit = widget.survey.autoSubmit;
    _allowAnonymous = widget.survey.allowAnonymous;
    
    if (widget.survey.surveyType == 1 && widget.survey.deadline != null) {
      try {
        final deadline = DateTime.parse(widget.survey.deadline!);
        final now = DateTime.now();
        if (deadline.isAfter(now)) {
          final difference = deadline.difference(now);
          _selectedDays = difference.inDays;
          _selectedHours = difference.inHours.remainder(24);
          _selectedMinutes = difference.inMinutes.remainder(60);
        } else {
          _selectedDays = 0;
          _selectedHours = 0;
          _selectedMinutes = 0;
        }
      } catch (e) {
        _selectedDays = 0;
        _selectedHours = 0;
        _selectedMinutes = 0;
      }
    }
    
    // 设置FSelect控制器的初始值
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _projectSelectController.value = _selectedProjectId;
      _typeSelectController.value = _selectedType;
      _statusSelectController.value = _selectedStatus;
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _totalTimesController.dispose();
    _perUserLimitController.dispose();
    _projectSelectController.dispose();
    _typeSelectController.dispose();
    _statusSelectController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(EditSurveyPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.survey.surveyType != widget.survey.surveyType) {
      setState(() {
        _selectedDays = 0;
        _selectedHours = 0;
        _selectedMinutes = 0;
      });
    }
    
    // 更新FSelect控制器的值
    if (oldWidget.survey.projectId != widget.survey.projectId) {
      _selectedProjectId = widget.survey.projectId;
      _projectSelectController.value = _selectedProjectId;
    }
    
    if (oldWidget.survey.surveyType != widget.survey.surveyType) {
      _selectedType = widget.survey.surveyType;
      _typeSelectController.value = _selectedType;
    }
    
    if (oldWidget.survey.surveyStatus != widget.survey.surveyStatus) {
      _selectedStatus = widget.survey.surveyStatus;
      _statusSelectController.value = _selectedStatus;
    }
  }

  Future<bool> _showPublishConfirmDialog() async {
    if (!mounted) return false;
    
    final confirmed = await showFDialog<bool>(
      context: context,
      builder: (context, style, animation) => FDialog(
        style: style.call,
        animation: animation,
        direction: Axis.horizontal,
        title: const Text('确认发布问卷'),
        body: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('您确定要将问卷切换到发布状态吗？'),
            SizedBox(height: 8),
            Text(
              '发布后，问卷将对外开放，用户可以通过公开链接访问和填写问卷。',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          FButton(
            style: context.theme.buttonStyles.outline.call,
            onPress: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FButton(
            onPress: () => Navigator.of(context).pop(true),
            child: const Text('确认发布'),
          ),
        ],
      ),
    );
    
    return confirmed ?? false;
  }

  Future<void> _showTimeLimitDialog() async {
    if (!mounted) return;
    if (_selectedStatus == 2) {
      showFToast(
        context: context,
        alignment:FToastAlignment.bottomRight,
        title: const Text('已完结'),
        description: const Text('问卷已完结，截止时间不可修改'),
      );
      return;
    }
    
    int tempDays = _selectedDays;
    int tempHours = _selectedHours;
    int tempMinutes = _selectedMinutes;

    final daysController = FSelectController<int>(vsync: this);
    final hoursController = FSelectController<int>(vsync: this);
    final minutesController = FSelectController<int>(vsync: this);

    await showFDialog(
      context: context,
      builder: (context, style, animation) => StatefulBuilder(
        builder: (context, setState) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            daysController.value = tempDays;
            hoursController.value = tempHours;
            minutesController.value = tempMinutes;
          });

          return FDialog(
            style: style.call,
            animation: animation,
            direction: Axis.horizontal,
            title: const Text('设置截止时间'),
            body: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('请选择问卷截止时间'),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 100,
                      child: FSelect<int>(
                        key: _daysSelectKey,
                        controller: daysController,
                        hint: '天数',
                        onChange: (value) {
                          setState(() {
                            tempDays = value ?? 0;
                          });
                        },
                        items: { for (var index = 0; index < 31; index++) '$index天': index },
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 100,
                      child: FSelect<int>(
                        key: _hoursSelectKey,
                        controller: hoursController,
                        hint: '小时',
                        onChange: (value) {
                          setState(() {
                            tempHours = value ?? 0;
                          });
                        },
                        items: { for (var index = 0; index < 24; index++) '${index.toString().padLeft(2, '0')}时': index },
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 100,
                      child: FSelect<int>(
                        key: _minutesSelectKey,
                        controller: minutesController,
                        hint: '分钟',
                        onChange: (value) {
                          setState(() {
                            tempMinutes = value ?? 0;
                          });
                        },
                        items: { for (var index = 0; index < 60; index++) '${index.toString().padLeft(2, '0')}分': index },
                      ),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              FButton(
                style: context.theme.buttonStyles.outline.call,
                onPress: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
              FButton(
                onPress: () {
                  if (tempDays == 0 && tempHours == 0 && tempMinutes == 0) {
                    if (!mounted) return;
                    showFToast(
                      context: context,
                      alignment: FToastAlignment.bottomRight,
                      title: const Text('提示'),
                      description: const Text('请至少设置一个时间单位'),
                      suffixBuilder: (context, entry) => IntrinsicHeight(
                        child: FButton(
                          style: context.theme.buttonStyles.primary.call,
                          onPress: entry.dismiss.call,
                          child: const Text('关闭'),
                        ),
                      ),
                    );
                    return;
                  }
                  if (!mounted) return;
                  setState(() {
                    _selectedDays = tempDays;
                    _selectedHours = tempHours;
                    _selectedMinutes = tempMinutes;
                  });
                  Navigator.of(context).pop();
                },
                child: const Text('确定'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _updateSurvey() async {
    if (!_formKey.currentState!.validate()) return;
    
    if (_selectedProjectId == null) {
      if (!mounted) return;
      showFToast(
        context: context,
        alignment:FToastAlignment.bottomRight,
        title: const Text('提示'),
        description: const Text('请选择一个项目'),
        suffixBuilder: (context, entry) => IntrinsicHeight(
          child: FButton(
            style: context.theme.buttonStyles.primary.call,
            onPress: entry.dismiss.call,
            child: const Text('关闭'),
          ),
        ),
      );
      return;
    }

    if (_selectedType == null) {
      if (!mounted) return;
      showFToast(
        context: context,
        alignment:FToastAlignment.bottomRight,
        title: const Text('提示'),
        description: const Text('请选择问卷类型'),
        suffixBuilder: (context, entry) => IntrinsicHeight(
          child: FButton(
            style: context.theme.buttonStyles.primary.call,
            onPress: entry.dismiss.call,
            child: const Text('关闭'),
          ),
        ),
      );
      return;
    }

    if (_selectedStatus == null) {
      if (!mounted) return;
      showFToast(
        context: context,
        alignment:FToastAlignment.bottomRight,
        title: const Text('提示'),
        description: const Text('请选择问卷状态'),
        suffixBuilder: (context, entry) => IntrinsicHeight(
          child: FButton(
            style: context.theme.buttonStyles.primary.call,
            onPress: entry.dismiss.call,
            child: const Text('关闭'),
          ),
        ),
      );
      return;
    }


    if (_selectedType == 1 && (_selectedDays == 0 && _selectedHours == 0 && _selectedMinutes == 0)) {
      if (!mounted) return;
      showFToast(
        context: context,
        alignment:FToastAlignment.bottomRight,
        title: const Text('提示'),
        description: const Text('请设置问卷截止时间'),
        suffixBuilder: (context, entry) => IntrinsicHeight(
          child: FButton(
            style: context.theme.buttonStyles.primary.call,
            onPress: entry.dismiss.call,
            child: const Text('关闭'),
          ),
        ),
      );
      return;
    }

    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final apiService = ApiService(authToken: widget.token);
      final now = DateTime.now();
      // 若问卷已完结，则禁止修改 deadline，沿用原值；否则按选择计算
      final String? deadline = (_selectedStatus == 2)
          ? widget.survey.deadline
          : (_selectedType == 1 
              ? now.add(Duration(
                  days: _selectedDays,
                  hours: _selectedHours,
                  minutes: _selectedMinutes,
                )).toIso8601String()
              : null);

      final String totalTimesRaw = _totalTimesController.text.trim();
      final int totalTimes = totalTimesRaw.isEmpty ? 0 : (int.tryParse(totalTimesRaw) ?? 0);
      final String perUserRaw = _perUserLimitController.text.trim();
      final int? perUserLimit = perUserRaw.isEmpty ? null : int.tryParse(perUserRaw);

      final survey = widget.survey.copyWith(
        surveyName: _titleController.text,
        description: _descriptionController.text,
        surveyType: _selectedType!,
        surveyStatus: _selectedStatus!,
        projectId: _selectedProjectId!,
        totalTimes: totalTimes,
        perUserLimit: perUserLimit,
        deadline: deadline,
        updateTime: now.toIso8601String(),
        autoSubmit: _autoSubmit,
        allowAnonymous: _allowAnonymous,
      );

      await apiService.updateSurvey(survey);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      showFToast(
        context: context,
        title: Text('更新问卷失败: ${e.toString()}'),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }



  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 900;
    
    return Scaffold(
      body: Stack(
        children: [
          const FrostedGlassBackground(),
          Column(
            children: [
              const TopSafeSpacer(),
              _buildAppBar(context, theme),
              Expanded(
                child: isDesktop ? _buildDesktopLayout(theme) : _buildMobileLayout(theme),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar(BuildContext context, ThemeData theme) {
    return FHeader.nested(
      title: const Text('编辑问卷'),
      prefixes: [
        FHeaderAction(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPress: () => Navigator.pop(context),
        ),
      ],
      // 预览入口移至右侧操作面板卡片
    );
  }

  Future<void> _openPreview() async {
    try {
      final api = ApiService(authToken: widget.token);
      final List<Question> questions = await api.getSurveyQuestions(widget.survey.id);
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => SurveyPreviewPage(
            survey: widget.survey,
            token: widget.token,
            questions: questions,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      showFToast(
        context: context,
        title: const Text('预览失败'),
        description: Text(e.toString()),
      );
    }
  }

  Widget _buildDesktopLayout(ThemeData theme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 左侧主要内容区域
        Expanded(
          flex: 2,
          child: Form(
            key: _formKey,
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(
                scrollbars: false,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildBasicInfoCard(theme),
                  const SizedBox(height: 24),
                  _buildSettingsCard(theme),
                  const SizedBox(height: 24),
                  _buildLimitsCard(theme),
                ],
                ),
              ),
            ),
          ),
        ),
        // 右侧操作面板
        SizedBox(
          width: 360,
          child: Container(
            decoration: BoxDecoration(
              color: theme.cardColor.withValues(alpha: 0.5),
              border: Border(
                left: BorderSide(
                  color: theme.dividerColor.withValues(alpha: 0.1),
                  width: 1,
                ),
              ),
            ),
            child: Column(
              children: [
                Expanded(
                  child: ScrollConfiguration(
                    behavior: ScrollConfiguration.of(context).copyWith(
                      scrollbars: false,
                    ),
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
    );
  }

  Widget _buildMobileLayout(ThemeData theme) {
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(
        scrollbars: false,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
        key: _formKey,
        child: Column(
          children: [
            _buildBasicInfoCard(theme),
            const SizedBox(height: 16),
            _buildSettingsCard(theme),
            const SizedBox(height: 16),
            _buildLimitsCard(theme),
            const SizedBox(height: 24),
            _buildActionPanel(theme),
          ],
        ),
        ),
      ),
    );
  }

  Widget _buildBasicInfoCard(ThemeData theme) {
    return Card(
      elevation: 0,
      color: theme.cardColor.withValues(alpha: 0.7),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.dividerColor.withValues(alpha: 0.1),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.edit_document,
                    size: 24,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '基本信息',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              FTextFormField(
                controller: _titleController,
                label: const Text('问卷标题'),
                hint: '请输入问卷标题（最多100字符）',
                autovalidateMode: AutovalidateMode.onUserInteraction,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '请输入问卷标题';
                  }
                  if (value.trim().length > 100) {
                    return '问卷标题不能超过100个字符';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              FTextFormField(
                controller: _descriptionController,
                label: const Text('问卷描述'),
                hint: '请输入问卷描述',
                maxLines: 4,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return '请输入问卷描述';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              FSelect<int>(
                key: _projectSelectKey,
                controller: _projectSelectController,
                label: const Text('所属项目'),
                hint: '请选择项目',
                onChange: (value) {
                  setState(() {
                    _selectedProjectId = value;
                  });
                  _projectSelectController.value = value;
                },
                items: {
                  for (final project in widget.projects) project.projectName: project.id,
                },
              ),
            ],
        ),
      ),
    );
  }

  Widget _buildSettingsCard(ThemeData theme) {
    return Card(
      elevation: 0,
      color: theme.cardColor.withValues(alpha: 0.7),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.dividerColor.withValues(alpha: 0.1),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.settings_outlined,
                  size: 24,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Text(
                  '问卷设置',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            FSelect<int>(
              key: _typeSelectKey,
              controller: _typeSelectController,
              label: const Text('问卷类型'),
              hint: '请选择问卷类型',
              onChange: (value) {
                setState(() {
                  _selectedType = value;
                });
                _typeSelectController.value = value;
              },
              items: const {
                '普通问卷': 0,
                '限时问卷': 1,
                '限次问卷': 2,
                '自选风格': 3,
              },
            ),
            if (_selectedType == 1) ...[
              const SizedBox(height: 16),
              Material(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: _showTimeLimitDialog,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(
                          Icons.timer_outlined,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '截止时间',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _selectedDays == 0 && _selectedHours == 0 && _selectedMinutes == 0
                                    ? '点击设置截止时间'
                                    : '$_selectedDays天 $_selectedHours小时 $_selectedMinutes分钟后截止',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            FSelect<int>(
              key: _statusSelectKey,
              controller: _statusSelectController,
              label: const Text('问卷状态'),
              hint: '请选择问卷状态',
              onChange: (value) async {
                if (value == 1 && _selectedStatus != 1) {
                  final confirmed = await _showPublishConfirmDialog();
                  if (!confirmed) return;
                }
                setState(() {
                  _selectedStatus = value;
                });
                _statusSelectController.value = value;
              },
              items: const {
                '未发布': 0,
                '发布中': 1,
                '已完结': 2,
              },
            ),
            const SizedBox(height: 24),
            _buildSwitchTile(
              theme,
              title: '自动提交',
              subtitle: '开启后，用户回答完所有必答题时会自动提交问卷',
              value: _autoSubmit,
              onChanged: (value) {
                setState(() {
                  _autoSubmit = value;
                });
              },
            ),
            const SizedBox(height: 16),
            _buildSwitchTile(
              theme,
              title: '允许匿名提交',
              subtitle: '开启后，未登录用户也可以提交问卷答案',
              value: _allowAnonymous,
              onChanged: (value) {
                setState(() {
                  _allowAnonymous = value;
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSwitchTile(ThemeData theme, {
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            FSwitch(
              value: value,
              onChange: onChanged,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLimitsCard(ThemeData theme) {
    return Card(
      elevation: 0,
      color: theme.cardColor.withValues(alpha: 0.7),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.dividerColor.withValues(alpha: 0.1),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.rule_outlined,
                  size: 24,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Text(
                  '提交限制',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            FTextFormField(
              controller: _totalTimesController,
              label: const Text('总提交上限'),
              hint: '留空表示不限制',
              keyboardType: TextInputType.number,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              validator: (value) {
                if (value == null || value.trim().isEmpty) return null;
                final n = int.tryParse(value.trim());
                if (n == null) return '请输入有效的数字';
                if (n < 0 || n > 2147483647) return '请输入有效的数字';
                return null;
              },
            ),
            const SizedBox(height: 16),
            FTextFormField(
              controller: _perUserLimitController,
              label: const Text('单用户提交上限'),
              hint: '留空表示不限制',
              keyboardType: TextInputType.number,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return null;
                }
                final intValue = int.tryParse(value.trim());
                if (intValue == null) {
                  return '请输入有效的数字';
                }
                if (intValue < 1 || intValue > 2147483647) {
                  return '请输入有效的数字';
                }
                return null;
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionPanel(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '快捷操作',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        _buildActionButton(
          theme,
          icon: Icons.visibility_outlined,
          label: '预览问卷',
          subtitle: '以最终效果预览当前问卷',
          onPressed: _openPreview,
        ),
        const SizedBox(height: 12),
        _buildActionButton(
          theme,
          icon: Icons.edit_note_outlined,
          label: '编辑问卷内容',
          subtitle: '添加和编辑问题',
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => EditSurveyContentPage(
                  token: widget.token,
                  survey: widget.survey,
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        _buildActionButton(
          theme,
          icon: Icons.analytics_outlined,
          label: '查看作答结果',
          subtitle: '统计和分析数据',
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => SurveyResultsPage(
                  token: widget.token,
                  survey: widget.survey,
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 32),
        FilledButton.icon(
          onPressed: _isLoading ? null : _updateSurvey,
          icon: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.save_outlined),
          label: Text(_isLoading ? '保存中...' : '保存修改'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton(
    ThemeData theme, {
    required IconData icon,
    required String label,
    required String subtitle,
    required VoidCallback onPressed,
  }) {
    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  color: theme.colorScheme.onPrimaryContainer,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
} 