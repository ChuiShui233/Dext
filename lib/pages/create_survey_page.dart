import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import '../models/survey.dart';
import '../models/project.dart';
import '../services/api_service.dart';
import '../main.dart' show isDesktop;
import '../widgets/frosted_glass_background.dart';

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
  final _perUserLimitController = TextEditingController();
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
    _perUserLimitController.dispose();
    _projectSelectController.dispose();
    _typeSelectController.dispose();
    super.dispose();
  }

  Future<void> _showTimeLimitDialog() async {
    if (!mounted) return;
    
    int tempDays = _selectedDays;
    int tempHours = _selectedHours;
    int tempMinutes = _selectedMinutes;

    await showFDialog(
      context: context,
      builder: (context, style, animation) => StatefulBuilder(
        builder: (context, setState) => FDialog(
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
      final deadline = _selectedType == 1 
          ? now.add(Duration(
              days: _selectedDays,
              hours: _selectedHours,
              minutes: _selectedMinutes,
            )).toIso8601String()
          : null;

      final String totalTimesRaw = _totalTimesController.text.trim();
      final int totalTimes = totalTimesRaw.isEmpty ? 0 : (int.tryParse(totalTimesRaw) ?? 0);
      final String perUserRaw = _perUserLimitController.text.trim();
      final int? perUserLimit = perUserRaw.isEmpty ? null : int.tryParse(perUserRaw);

      final survey = Survey(
        id: 0, // 后端会生成
        surveyUid: '', // 后端会生成
        surveyName: _titleController.text.trim(), // 确保去除首尾空格
        description: _descriptionController.text.trim(), // 确保去除首尾空格
        surveyType: _selectedType!,
        surveyStatus: 0, // 初始状态为未发布
        totalTimes: totalTimes,
        perUserLimit: perUserLimit,
        projectId: _selectedProjectId!,
        deadline: deadline,
        createTime: now.toIso8601String(),
        updateTime: now.toIso8601String(),
      );

      await apiService.createSurvey(survey);
      if (!mounted) return;
      // 返回新建问卷名称，便于上级页面展示“创建成功：名称”提示
      Navigator.pop(context, _titleController.text.trim());
    } catch (e) {
      if (!mounted) return;
      showFToast(
        context: context,
        alignment:FToastAlignment.bottomRight,
        title: const Text('提示'),
        description: Text('创建问卷失败: ${e.toString()}'),
        suffixBuilder: (context, entry) => IntrinsicHeight(
          child: FButton(
            style: context.theme.buttonStyles.primary.call,
            onPress: entry.dismiss.call,
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

  // 已迁移为 FSelect.items Map，保留时可能未使用

  @override
  Widget build(BuildContext context) {
    if (widget.projects.isEmpty) {
      return Scaffold(
        body: Stack(
          children: [
            const FrostedGlassBackground(),
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
          const FrostedGlassBackground(),
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
                    final isWide = constraints.maxWidth >= 800;
                    final maxWidth = isWide ? 700.0 : double.infinity;
                    final horizontalPadding = isWide ? 48.0 : 16.0;

                    return Center(
                      child: Container(
                        constraints: BoxConstraints(maxWidth: maxWidth),
                        padding: EdgeInsets.all(horizontalPadding),
                        child: Form(
                          key: _formKey,
                          child: ListView(
                            children: [
                              FSelect<int>(
                                controller: _projectSelectController,
                                label: const Text('所属项目'),
                                hint: '请选择项目',
                                onChange: (value) {
                                  setState(() {
                                    _selectedProjectId = value;
                                  });
                                },
                                items: {
                                  for (final project in widget.projects) project.projectName: project.id,
                                },
                              ),
                              SizedBox(height: isWide ? 20 : 16),
                              FSelect<int>(
                                controller: _typeSelectController,
                                label: const Text('问卷类型'),
                                hint: '请选择问卷类型',
                                onChange: (value) {
                                  setState(() {
                                    _selectedType = value;
                                  });
                                },
                                items: const {
                                  '普通问卷': 0,
                                  '限时问卷': 1,
                                  '限次问卷': 2,
                                  '自选风格': 3,
                                },
                              ),
                              if (_selectedType == 1) ...[
                                SizedBox(height: isWide ? 20 : 16),
                                FTile(
                                  prefix: const Icon(Icons.timer),
                                  title: const Text('设置截止时间'),
                                  subtitle: Text(
                                    _selectedDays == 0 && _selectedHours == 0 && _selectedMinutes == 0
                                        ? '请点击设置'
                                        : '$_selectedDays天$_selectedHours小时$_selectedMinutes分钟后截止',
                                  ),
                                  suffix: const Icon(Icons.chevron_right),
                                  onPress: _showTimeLimitDialog,
                                ),
                              ],
                              SizedBox(height: isWide ? 20 : 16),
                              if (isWide)
                                Row(
                                  children: [
                                    Expanded(
                                      child: FTextFormField(
                                        controller: _totalTimesController,
                                        label: const Text('总提交上限(可选)'),
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
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: FTextFormField(
                                        controller: _perUserLimitController,
                                        label: const Text('单用户提交上限(可选)'),
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
                                    ),
                                  ],
                                )
                              else
                                Column(
                                  children: [
                                    FTextFormField(
                                      controller: _totalTimesController,
                                      label: const Text('总提交上限(可选)'),
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
                                    const SizedBox(height: 12),
                                    FTextFormField(
                                      controller: _perUserLimitController,
                                      label: const Text('单用户提交上限(可选)'),
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
                              SizedBox(height: isWide ? 20 : 16),
                              FTextFormField(
                                controller: _titleController,
                                label: const Text('问卷标题'),
                                hint: '请输入问卷标题',
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
                              SizedBox(height: isWide ? 20 : 16),
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
                              SizedBox(height: isWide ? 32 : 24),
                              SizedBox(
                                width: double.infinity,
                                child: FButton(
                                  onPress: _isLoading ? null : _createSurvey,
                                  prefix: _isLoading ? const FCircularProgress() : null,
                                  child: Text(_isLoading ? '创建中...' : '创建问卷'),
                                ),
                              ),
                            ],
                          ),
                        ),
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
}