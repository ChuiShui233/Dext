import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import '../services/api_service.dart';
import '../models/project.dart';
import '../models/survey.dart';

class DebugToolsPage extends StatefulWidget {
  final ApiService apiService;
  const DebugToolsPage({super.key, required this.apiService});

  @override
  State<DebugToolsPage> createState() => _DebugToolsPageState();
}

class _DebugToolsPageState extends State<DebugToolsPage> {
  bool _running = false;
  double _progress = 0;
  String _status = '就绪';

  Future<void> _createProjects(int count) async {
    if (_running) return;
    setState(() {
      _running = true;
      _progress = 0;
      _status = '正在创建项目...';
    });
    try {
      final rng = Random();
      final now = DateTime.now();
      for (int i = 1; i <= count; i++) {
        final name = '项目_${now.millisecondsSinceEpoch}_${i}_${rng.nextInt(9999)}';
        final desc = '自动生成的测试项目 #$i';
        final p = Project(
          id: 0,
          projectName: name,
          projectDescription: desc,
          userId: '',
          createBy: '',
          createTime: DateTime.now().toIso8601String(),
          updateTime: DateTime.now().toIso8601String(),
          updateBy: '',
        );
        await widget.apiService.createProject(p);
        if (!mounted) return;
        setState(() {
          _progress = i / count;
        });
        // 小幅让出事件循环，避免UI阻塞
        await Future.delayed(const Duration(milliseconds: 1));
      }
      if (!mounted) return;
      showFToast(
        context: context,
        alignment: FToastAlignment.bottomRight,
        title: const Text('完成'),
        description: Text('已创建 $count 个项目'),
      );
    } catch (e) {
      if (!mounted) return;
      showFToast(
        context: context,
        alignment: FToastAlignment.bottomRight,
        title: const Text('出错'),
        description: Text('创建项目失败: $e'),
      );
    } finally {
      if (mounted) {
        setState(() {
          _running = false;
          _status = '就绪';
        });
      }
    }
  }

  Future<void> _createSurveys(int count) async {
    if (_running) return;
    setState(() {
      _running = true;
      _progress = 0;
      _status = '正在创建问卷...';
    });
    try {
      final projects = await widget.apiService.getProjects();
      if (projects.isEmpty) {
        if (!mounted) return;
        showFToast(
          context: context,
          title: const Text('提示'),
          description: const Text('当前没有项目，请先创建项目'),
        );
        return;
      }
      final rng = Random();
      final now = DateTime.now();
      for (int i = 1; i <= count; i++) {
        final project = projects[rng.nextInt(projects.length)];
        final name = '问卷_${now.millisecondsSinceEpoch}_${i}_${rng.nextInt(9999)}';
        final desc = '自动生成的测试问卷 #$i';
        final survey = Survey(
          id: 0,
          surveyUid: '',
          surveyName: name,
          description: desc,
          surveyType: rng.nextInt(4),
          surveyStatus: 0,
          totalTimes: 0,
          perUserLimit: null,
          projectId: project.id,
          deadline: null,
          createTime: DateTime.now().toIso8601String(),
          updateTime: DateTime.now().toIso8601String(),
        );
        await widget.apiService.createSurvey(survey);
        if (!mounted) return;
        setState(() {
          _progress = i / count;
        });
        await Future.delayed(const Duration(milliseconds: 1));
      }
      if (!mounted) return;
      showFToast(
        context: context,
        alignment: FToastAlignment.bottomRight,
        title: const Text('完成'),
        description: Text('已创建 $count 份问卷'),
      );
    } catch (e) {
      if (!mounted) return;
      showFToast(
        context: context,
        alignment: FToastAlignment.bottomRight,
        title: const Text('出错'),
        description: Text('创建问卷失败: $e'),
      );
    } finally {
      if (mounted) {
        setState(() {
          _running = false;
          _status = '就绪';
        });
      }
    }
  }

  Future<void> _createBoth() async {
    await _createProjects(500);
    await _createSurveys(500);
  }

  Future<void> _manualRefreshToken() async {
    if (_running) return;
    setState(() {
      _running = true;
      _status = '正在刷新令牌...';
    });
    try {
      final success = await widget.apiService.manualRefreshToken();
      if (!mounted) return;
      if (success) {
        showFToast(
          context: context,
          alignment: FToastAlignment.bottomRight,
          title: const Text('成功'),
          description: const Text('令牌刷新成功'),
        );
      } else {
        showFToast(
          context: context,
          alignment: FToastAlignment.bottomRight,
          title: const Text('失败'),
          description: const Text('令牌刷新失败，请查看控制台日志'),
        );
      }
    } catch (e) {
      if (!mounted) return;
      showFToast(
        context: context,
        alignment: FToastAlignment.bottomRight,
        title: const Text('出错'),
        description: Text('令牌刷新出错: $e'),
      );
    } finally {
      if (mounted) {
        setState(() {
          _running = false;
          _status = '就绪';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('调试工具'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('批量生成测试数据', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text('状态：$_status'),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: _running ? _progress : null, minHeight: 6),
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FButton(
                  onPress: _running ? null : () => _createProjects(500),
                  child: const Text('创建500个项目'),
                ),
                FButton(
                  onPress: _running ? null : () => _createSurveys(500),
                  child: const Text('创建500份问卷'),
                ),
                FButton(
                  onPress: _running ? null : _createBoth,
                  child: const Text('一键创建(项目+问卷)'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('说明：创建量较大，请耐心等待进度完成。'),
            const Divider(height: 32),
            Text('认证调试工具', style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            FButton(
              onPress: _running ? null : _manualRefreshToken,
              child: const Text('手动刷新令牌'),
            ),
            const SizedBox(height: 8),
            const Text('说明：测试令牌刷新功能，刷新日志会显示在控制台。'),
          ],
        ),
      ),
    );
  }
}
