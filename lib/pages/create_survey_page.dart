import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import '../models/survey.dart';
import '../models/project.dart';
import '../services/api_service.dart';
import '../main.dart' show isDesktop;

class CreateSurveyPage extends StatefulWidget {
  final String token;
  final List<Project> projects;

  const CreateSurveyPage({
    super.key,
    required this.token,
    required this.projects,
  });

  @override
  State<CreateSurveyPage> createState() => _CreateSurveyPageState();
}

class _CreateSurveyPageState extends State<CreateSurveyPage> with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _totalTimesController = TextEditingController();
  late final FSelectController<int> _projectSelectController;
  late final FSelectController<int> _typeSelectController;
  int? _selectedProjectId;
  int? _selectedType;
  bool _isLoading = false;
  int _selectedDays = 0;
  int _selectedHours = 0;
  int _selectedMinutes = 0;

  @override
  void initState() {
    super.initState();
    _projectSelectController = FSelectController<int>(vsync: this);
    _typeSelectController = FSelectController<int>(vsync: this);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _totalTimesController.dispose();
    _projectSelectController.dispose();
    _typeSelectController.dispose();
    super.dispose();
  }

  Future<void> _showTimeLimitDialog() async {
    if (!mounted) return;
    
    int tempDays = _selectedDays;
    int tempHours = _selectedHours;
    int tempMinutes = _selectedMinutes;

    await showAdaptiveDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => FDialog(
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
        ),
      ),
    );
  }

  Future<void> _createSurvey() async {
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

      final survey = Survey(
        id: 0, // 后端会生成
        surveyUid: '', // 后端会生成
        surveyName: _titleController.text.trim(), // 确保去除首尾空格
        description: _descriptionController.text.trim(), // 确保去除首尾空格
        surveyType: _selectedType!,
        surveyStatus: 0, // 初始状态为未发布
        totalTimes: _selectedType == 2 ? int.parse(_totalTimesController.text) : 0,
        projectId: _selectedProjectId!,
        deadline: deadline,
        createTime: now.toIso8601String(),
        updateTime: now.toIso8601String(),
      );

      await apiService.createSurvey(survey);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      showFToast(
        context: context,
        alignment:FToastAlignment.bottomRight,
        title: const Text('提示'),
        description: Text('创建问卷失败: ${e.toString()}'),
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

  @override
  Widget build(BuildContext context) {
    // 处理无项目的情况
    if (widget.projects.isEmpty) {
      return Scaffold(
        body: Stack(
          children: [
            Column(
              children: [
                if (isDesktop)
                  const SizedBox(height: 40),
                FHeader.nested(
                  title: const Text('创建新问卷'),
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
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(height: 100),
                            const Text('没有可用项目'),
                            const SizedBox(height: 100),
                            Padding(
                              padding: EdgeInsets.all(constraints.maxWidth * 0.2),
                              child: FButton(
                                onPress: () => Navigator.pop(context),
                                child: const Text('返回'),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          Column(
            children: [
              if (isDesktop)
                const SizedBox(height: 40),
              FHeader.nested(
                title: const Text('创建新问卷'),
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
                          controller: _typeSelectController,
                          label: const Text('问卷类型'),
                          hint: '请选择问卷类型',
                          format: (value) => _getSurveyTypeText(value),
                          onChange: (value) {
                            setState(() {
                              _selectedType = value;
                            });
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
                        SizedBox(
                          width: double.infinity,
                          child: FButton(
                            onPress: _isLoading ? null : _createSurvey,
                            child: _isLoading
                                ? const CircularProgressIndicator()
                                : const Text('创建问卷'),
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