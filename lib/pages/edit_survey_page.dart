import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import '../models/survey.dart';
import '../models/project.dart';
import '../services/api_service.dart';
import '../main.dart' show isDesktop;
import 'dart:async';
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
  
  // 为时间选择器添加唯一的 key
  final _daysSelectKey = GlobalKey();
  final _hoursSelectKey = GlobalKey();
  final _minutesSelectKey = GlobalKey();
  
  // 添加控制器
  late final FSelectController<int> _daysController;
  late final FSelectController<int> _hoursController;
  late final FSelectController<int> _minutesController;

  @override
  void initState() {
    super.initState();
    _days = widget.initialDays;
    _hours = widget.initialHours;
    _minutes = widget.initialMinutes;
    
    // 初始化控制器
    _daysController = FSelectController<int>(vsync: this);
    _hoursController = FSelectController<int>(vsync: this);
    _minutesController = FSelectController<int>(vsync: this);
    
    // 设置控制器的初始值
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
                    format: (value) => '$value天',
                    onChange: (value) {
                      setState(() {
                        _days = value ?? 0;
                      });
                    },
                    children: List.generate(31, (index) => FSelectItem('$index天', index)),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 100,
                  child: FSelect<int>(
                    key: _hoursSelectKey,
                    controller: _hoursController,
                    hint: '小时',
                    format: (value) => '${value.toString().padLeft(2, '0')}时',
                    onChange: (value) {
                      setState(() {
                        _hours = value ?? 0;
                      });
                    },
                    children: List.generate(24, (index) => FSelectItem('${index.toString().padLeft(2, '0')}时', index)),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 100,
                  child: FSelect<int>(
                    key: _minutesSelectKey,
                    controller: _minutesController,
                    hint: '分钟',
                    format: (value) => '${value.toString().padLeft(2, '0')}分',
                    onChange: (value) {
                      setState(() {
                        _minutes = value ?? 0;
                      });
                    },
                    children: List.generate(60, (index) => FSelectItem('${index.toString().padLeft(2, '0')}分', index)),
                  ),
                ),
              ],
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: FButton(
                onPress: () {
                  if (_days == 0 && _hours == 0 && _minutes == 0) {
                    showFToast(
                      context: context,
                      alignment:FToastAlignment.bottomRight,
                      title: const Text('提示'),
                      description: const Text('请至少设置一个时间单位'),
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

  @override
  void initState() {
    super.initState();
    _projectSelectController = FSelectController<int>(vsync: this);
    _typeSelectController = FSelectController<int>(vsync: this);
    _statusSelectController = FSelectController<int>(vsync: this);

    // 初始化表单数据
    _titleController.text = widget.survey.surveyName;
    _descriptionController.text = widget.survey.description;
    _selectedProjectId = widget.survey.projectId;
    _selectedType = widget.survey.surveyType;
    _selectedStatus = widget.survey.surveyStatus;
    if (widget.survey.surveyType == 2) {
      _totalTimesController.text = widget.survey.totalTimes.toString();
    }
    
    // 初始化截止时间
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
          // 如果截止时间已经过期，设置为默认值
          _selectedDays = 0;
          _selectedHours = 0;
          _selectedMinutes = 0;
        }
      } catch (e) {
        // 如果日期解析失败，设置为默认值
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
    _projectSelectController.dispose();
    _typeSelectController.dispose();
    _statusSelectController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(EditSurveyPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.survey.surveyType != widget.survey.surveyType) {
      // 当问卷类型改变时，重置相关状态
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
    
    final confirmed = await showAdaptiveDialog<bool>(
      context: context,
      builder: (context) => FDialog(
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
            style: FButtonStyle.outline,
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
    
    int tempDays = _selectedDays;
    int tempHours = _selectedHours;
    int tempMinutes = _selectedMinutes;

    // 创建时间选择控制器
    final daysController = FSelectController<int>(vsync: this);
    final hoursController = FSelectController<int>(vsync: this);
    final minutesController = FSelectController<int>(vsync: this);

    await showAdaptiveDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          // 设置控制器的初始值
          WidgetsBinding.instance.addPostFrameCallback((_) {
            daysController.value = tempDays;
            hoursController.value = tempHours;
            minutesController.value = tempMinutes;
          });
          
          return FDialog(
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
                        format: (value) => '$value天',
                        onChange: (value) {
                          setState(() {
                            tempDays = value ?? 0;
                          });
                        },
                        children: List.generate(31, (index) => FSelectItem('$index天', index)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 100,
                      child: FSelect<int>(
                        key: _hoursSelectKey,
                        controller: hoursController,
                        hint: '小时',
                        format: (value) => '${value.toString().padLeft(2, '0')}时',
                        onChange: (value) {
                          setState(() {
                            tempHours = value ?? 0;
                          });
                        },
                        children: List.generate(24, (index) => FSelectItem('${index.toString().padLeft(2, '0')}时', index)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 100,
                      child: FSelect<int>(
                        key: _minutesSelectKey,
                        controller: minutesController,
                        hint: '分钟',
                        format: (value) => '${value.toString().padLeft(2, '0')}分',
                        onChange: (value) {
                          setState(() {
                            tempMinutes = value ?? 0;
                          });
                        },
                        children: List.generate(60, (index) => FSelectItem('${index.toString().padLeft(2, '0')}分', index)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              FButton(
                style: FButtonStyle.outline,
                onPress: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
              FButton(
                onPress: () {
                  if (tempDays == 0 && tempHours == 0 && tempMinutes == 0) {
                    if (!mounted) return;
                    showFToast(
                      context: context,
                      alignment:FToastAlignment.bottomRight,
                      title: const Text('提示'),
                      description: const Text('请至少设置一个时间单位'),
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
      return;
    }

    if (_selectedType == null) {
      if (!mounted) return;
      showFToast(
        context: context,
        alignment:FToastAlignment.bottomRight,
        title: const Text('提示'),
        description: const Text('请选择问卷类型'),
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
      return;
    }

    if (_selectedStatus == null) {
      if (!mounted) return;
      showFToast(
        context: context,
        alignment:FToastAlignment.bottomRight,
        title: const Text('提示'),
        description: const Text('请选择问卷状态'),
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
      return;
    }

    if (_selectedType == 2 && (_totalTimesController.text.isEmpty || int.tryParse(_totalTimesController.text) == null)) {
      if (!mounted) return;
      showFToast(
        context: context,
        alignment:FToastAlignment.bottomRight,
        title: const Text('提示'),
        description: const Text('请输入有效的提交次数限制'),
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
      return;
    }

    if (_selectedType == 1 && (_selectedDays == 0 && _selectedHours == 0 && _selectedMinutes == 0)) {
      if (!mounted) return;
      showFToast(
        context: context,
        alignment:FToastAlignment.bottomRight,
        title: const Text('提示'),
        description: const Text('请设置问卷截止时间'),
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
      return;
    }

    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final apiService = ApiService(authToken: widget.token);
      final now = DateTime.now();
      final deadline = _selectedType == 1 
          ? now.add(Duration(
              days: _selectedDays,
              hours: _selectedHours,
              minutes: _selectedMinutes,
            )).toIso8601String()
          : null;

      final survey = widget.survey.copyWith(
        surveyName: _titleController.text,
        description: _descriptionController.text,
        surveyType: _selectedType!,
        surveyStatus: _selectedStatus!,
        projectId: _selectedProjectId!,
        totalTimes: _selectedType == 2 ? int.parse(_totalTimesController.text) : 0,
        deadline: deadline,
        updateTime: now.toIso8601String(),
      );

      await apiService.updateSurvey(survey);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('更新问卷失败: ${e.toString()}')),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Column(
            children: [
              SizedBox(height: isDesktop ? 40 : 20),
              FHeader.nested(
                title: const Text('编辑问卷'),
                prefixes: [
                  FHeaderAction(
                    icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                    onPress: () {
                      Navigator.pop(context);
                    },
                  ),
                ],
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Form(
                    key: _formKey,
                    child: ListView(
                      children: [
                        FSelect<int>(
                          key: _projectSelectKey,
                          controller: _projectSelectController,
                          label: const Text('所属项目'),
                          hint: '请选择项目',
                          format: (value) => widget.projects
                              .firstWhere((p) => p.id == value)
                              .projectName,
                          onChange: (value) {
                            setState(() {
                              _selectedProjectId = value;
                            });
                            _projectSelectController.value = value;
                          },
                          children: widget.projects.map((project) {
                            return FSelectItem(
                              project.projectName,
                              project.id,
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 16),
                        FSelect<int>(
                          key: _typeSelectKey,
                          controller: _typeSelectController,
                          label: const Text('问卷类型'),
                          hint: '请选择问卷类型',
                          format: (value) => _getSurveyTypeText(value),
                          onChange: (value) {
                            setState(() {
                              _selectedType = value;
                            });
                            _typeSelectController.value = value;
                          },
                          children: [
                            FSelectItem('普通问卷', 0),
                            FSelectItem('限时问卷', 1),
                            FSelectItem('限次问卷', 2),
                            FSelectItem('自选风格', 3),
                          ],
                        ),
                        if (_selectedType == 1) ...[
                          const SizedBox(height: 16),
                          FTile(
                            prefixIcon: const Icon(Icons.timer),
                            title: const Text('设置截止时间'),
                            subtitle: Text(
                              _selectedDays == 0 && _selectedHours == 0 && _selectedMinutes == 0
                                  ? '请点击设置'
                                  : '$_selectedDays天$_selectedHours小时$_selectedMinutes分钟后截止'
                            ),
                            suffixIcon: const Icon(Icons.chevron_right),
                            onPress: _showTimeLimitDialog,
                          ),
                        ],
                        if (_selectedType == 2) ...[
                          const SizedBox(height: 16),
                          FTextFormField(
                            controller: _totalTimesController,
                            label: const Text('提交次数限制'),
                            hint: '请输入允许的最大提交次数',
                            keyboardType: TextInputType.number,
                            autovalidateMode: AutovalidateMode.onUserInteraction,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return '请输入提交次数限制';
                              }
                              if (int.tryParse(value) == null) {
                                return '请输入有效的数字';
                              }
                              final number = int.parse(value);
                              if (number <= 0) {
                                return '提交次数必须大于0';
                              }
                              return null;
                            },
                          ),
                        ],
                        const SizedBox(height: 16),
                        FSelect<int>(
                          key: _statusSelectKey,
                          controller: _statusSelectController,
                          label: const Text('问卷状态'),
                          hint: '请选择问卷状态',
                          format: (value) => _getSurveyStatusText(value),
                          onChange: (value) async {
                            // 如果切换到发布中状态，显示确认对话框
                            if (value == 1 && _selectedStatus != 1) {
                              final confirmed = await _showPublishConfirmDialog();
                              if (!confirmed) {
                                // 用户取消，回退到之前的状态
                                _statusSelectController.value = _selectedStatus;
                                return;
                              }
                            }
                            setState(() {
                              _selectedStatus = value;
                            });
                            _statusSelectController.value = value;
                          },
                          children: [
                            FSelectItem('未发布', 0),
                            FSelectItem('发布中', 1),
                            FSelectItem('已完结', 2),
                          ],
                        ),
                        const SizedBox(height: 16),
                        FTextFormField(
                          controller: _titleController,
                          label: const Text('问卷标题'),
                          hint: '请输入问卷标题',
                          autovalidateMode: AutovalidateMode.onUserInteraction,
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return '请输入问卷标题';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        FTextFormField(
                          controller: _descriptionController,
                          label: const Text('问卷描述'),
                          hint: '请输入问卷描述',
                          maxLines: 3,
                          autovalidateMode: AutovalidateMode.onUserInteraction,
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return '请输入问卷描述';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 24),
                        FButton(
                          style: FButtonStyle.outline,
                          onPress: () {
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
                          child: const Text('编辑问卷内容'),
                        ),
                        const SizedBox(height: 16),
                        FButton(
                          style: FButtonStyle.outline,
                          onPress: () {
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
                          child: const Text('查看作答结果'),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: FButton(
                            onPress: _isLoading ? null : _updateSurvey,
                            child: _isLoading
                                ? const CircularProgressIndicator()
                                : const Text('保存修改'),
                          ),
                        ),
                      ],
                    ),
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