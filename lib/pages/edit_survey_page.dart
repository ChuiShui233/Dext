import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import '../models/survey.dart';
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

    await showAdaptiveDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
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

      // 解析可选提交上限（留空或0都视为不限制）
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
          const FrostedGlassBackground(),
          Column(
            children: [
              const TopSafeSpacer(), // Replace SizedBox with TopSafeSpacer
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
                        const SizedBox(height: 16),
                        FTextFormField(
                          controller: _totalTimesController,
                          label: const Text('总提交上限(可选)'),
                          hint: '留空表示不限制，例如 100',
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
                        const SizedBox(height: 12),
                        FTextFormField(
                          controller: _perUserLimitController,
                          label: const Text('单用户提交上限(可选)'),
                          hint: '留空表示不限制，例如 1',
                          keyboardType: TextInputType.number,
                          autovalidateMode: AutovalidateMode.onUserInteraction,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return null; // 空值允许
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
                        const SizedBox(height: 16),
                        FSelect<int>(
                          key: _statusSelectKey,
                          controller: _statusSelectController,
                          label: const Text('问卷状态'),
                          hint: '请选择问卷状态',
                          format: (value) => _getSurveyStatusText(value),
                          onChange: (value) async {
                            if (value == 1 && _selectedStatus != 1) {
                              final confirmed = await _showPublishConfirmDialog();
                              if (!confirmed) {
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