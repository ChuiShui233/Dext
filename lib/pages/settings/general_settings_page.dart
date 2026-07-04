import 'dart:io';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:provider/provider.dart';

import '../../components/loading_indicator.dart';
import '../../services/settings_service.dart';
import '../frame_page.dart';
import '../../widgets/top_safe_spacer.dart';
import '../../services/power_service.dart';
import '../../providers/theme_provider.dart';

class GeneralSettingsPage extends StatefulWidget {
  const GeneralSettingsPage({super.key});

  @override
  State<GeneralSettingsPage> createState() => _GeneralSettingsPageState();
}

class _GeneralSettingsPageState extends State<GeneralSettingsPage> {
  bool _wasDesktopLayout = false;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bool isDesktopLayout = MediaQuery.of(context).size.width >= 1025;
    // 跳过首次构建，避免在桌面端直接打开时错误弹出
    if (_initialized && !_wasDesktopLayout && isDesktopLayout) {
      // 移动端→桌面端布局切换，弹出当前页面，返回设置列表
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context).pop();
        }
      });
    }
    _wasDesktopLayout = isDesktopLayout;
    _initialized = true;
  }

  Future<Map<String, dynamic>> _loadSettings() async {
    final s = SettingsService();
    return {
      'edge_drag_width': s.edgeDragWidth,
      'window_close_dont_ask': s.windowCloseDontAsk,
      'window_close_default_action': s.windowCloseDefaultAction,
      'dpi_scale': s.dpiScale,
      'theme_mode': s.themeMode,
      'questionnaire_layout': s.questionnaireLayout,
    };
  }



  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool isDesktopLayout = MediaQuery.of(context).size.width >= 1025;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // 纯色背景
          Container(color: theme.colorScheme.surface),
          Column(
            children: [
              if (!isDesktopLayout) const TopSafeSpacer(),
              FHeader.nested(
                title: Row(
                  children: const [
                    SizedBox(width: 16),
                    Text('通用'),
                  ],
                ),
                prefixes: [
                  FHeaderAction(
                    icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                    onPress: () {
                      final nav = Navigator.maybeOf(context);
                      if (nav != null && nav.canPop()) {
                        nav.pop();
                        return;
                      }
                      final frameState = context.findAncestorStateOfType<FramePageState>();
                      if (frameState != null) {
                        frameState.handleTabChange(0);
                        return;
                      }
                      Navigator.of(context).maybePop();
                    },
                  ),
                ],
              ),
              Expanded(
                child: FutureBuilder<Map<String, dynamic>>(
                  future: _loadSettings(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: LoadingIndicator.page());
                    }

                    final settings = snapshot.data!;
                    final currentEdgeDragWidth = settings['edge_drag_width'] as double;
                    final currentDpiScale = (settings['dpi_scale'] as double);
                    final isDesktop = !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

                    final List<FItem> items = [];

                    // 主题模式
                    items.add(
                      FItem(
                        title: const Text('主题模式'),
                        details: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                () {
                                  final mode = context.watch<ThemeProvider>().themeMode;
                                  return '当前: ${mode == ThemeMode.light ? '浅色模式' : mode == ThemeMode.dark ? '深色模式' : '跟随系统'}';
                                }(),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.primary.withValues(alpha: 0.7),
                                ),
                              ),
                            ),
                            FSelect<String>(
                              hint: '选择主题模式',
                              items: const {
                                '跟随系统': '跟随系统',
                                '浅色模式': '浅色模式',
                                '深色模式': '深色模式',
                              },
                              onChange: (mode) async {
                                if (mode == null) return;
                                ThemeMode themeMode;
                                switch (mode) {
                                  case '浅色模式':
                                    themeMode = ThemeMode.light;
                                    break;
                                  case '深色模式':
                                    themeMode = ThemeMode.dark;
                                    break;
                                  case '跟随系统':
                                  default:
                                    themeMode = ThemeMode.system;
                                }
                                context.read<ThemeProvider>().setMode(themeMode);
                              },
                            ),
                          ],
                        ),
                      ),
                    );

                    // 侧滑触发范围
                    items.add(
                      FItem(
                        title: const Text('侧滑触发范围'),
                        details: _EdgeDragWidgetCard(
                          key: ValueKey(currentEdgeDragWidth),
                          initialValue: currentEdgeDragWidth,
                          theme: theme,
                          onChanged: (v) => SettingsService().setEdgeDragWidth(v),
                        ),
                      ),
                    );

                    // DPI 缩放
                    items.add(
                      FItem(
                        title: const Text('DPI 缩放'),
                        details: _DpiScaleCard(
                          initialValue: currentDpiScale,
                          theme: theme,
                          onChanged: (v) {
                            context.read<ThemeProvider>().setDpiScale(v);
                          },
                        ),
                      ),
                    );

                    // 问卷布局外观
                    items.add(
                      FItem(
                        title: const Text('问卷布局'),
                        details: _QuestionnaireLayoutCard(
                          initialValue: settings['questionnaire_layout'] as String,
                          theme: theme,
                          onChanged: (v) => SettingsService().setQuestionnaireLayout(v),
                        ),
                      ),
                    );

                    // 保持后台运行（Android）
                    if (!kIsWeb && Platform.isAndroid) {
                      items.add(
                        FItem(
                          title: const Text('保持后台运行'),
                          details: _KeepAliveAndroidCard(theme: theme),
                        ),
                      );
                    }

                    // 界面效果：毛玻璃卡片
                    items.add(
                      FItem(
                        title: const Text('毛玻璃效果'),
                        details: const _FrostedCard(),
                      ),
                    );

                    // 窗口关闭行为（桌面端）
                    if (isDesktop) {
                      final currentAction = settings['window_close_default_action'] as String;
                      String currentDisplayValue;
                      switch (currentAction) {
                        case 'hide':
                          currentDisplayValue = '隐藏到托盘';
                          break;
                        case 'close':
                          currentDisplayValue = '直接关闭';
                          break;
                        case 'ask':
                        default:
                          currentDisplayValue = '每次询问';
                      }
                      items.add(
                        FItem(
                          title: const Text(''),
                          details: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              FSelect<String>(
                                label: const Text('窗口关闭行为'),
                                hint: '选择关闭行为',
                                items: const {
                                  '每次询问': '每次询问',
                                  '隐藏到托盘': '隐藏到托盘',
                                  '直接关闭': '直接关闭',
                                },
                                onChange: (displayValue) async {
                                  if (displayValue == null) return;
                                  String actionValue;
                                  switch (displayValue) {
                                    case '每次询问':
                                      actionValue = 'ask';
                                      break;
                                    case '隐藏到托盘':
                                      actionValue = 'hide';
                                      break;
                                    case '直接关闭':
                                      actionValue = 'close';
                                      break;
                                    default:
                                      actionValue = 'ask';
                                  }
                                  final s = SettingsService();
                                  if (actionValue == 'ask') {
                                    await s.setWindowCloseDontAsk(false);
                                    await s.setWindowCloseDefaultAction('ask');
                                  } else {
                                    await s.setWindowCloseDontAsk(true);
                                    await s.setWindowCloseDefaultAction(actionValue);
                                  }
                                },
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '当前: $currentDisplayValue',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.primary.withValues(alpha: 0.7),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    // 页面主体
                    return SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(isDesktopLayout ? 12 : 16, 12, isDesktopLayout ? 12 : 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: isDesktopLayout ? 4 : 8),
                            child: FItemGroup(
                              divider: FItemDivider.indented,
                              children: items,
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
}

// ---- 控件：Android 保持后台运行（忽略电池优化） ----
class _KeepAliveAndroidCard extends StatefulWidget {
  final ThemeData theme;
  const _KeepAliveAndroidCard({required this.theme});

  @override
  State<_KeepAliveAndroidCard> createState() => _KeepAliveAndroidCardState();
}

class _KeepAliveAndroidCardState extends State<_KeepAliveAndroidCard> {
  bool? _isExempt;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final ok = await PowerService.isIgnoringBatteryOptimizations();
    if (!mounted) return;
    setState(() => _isExempt = ok);
  }

  Future<void> _request() async {
    setState(() => _loading = true);
    final started = await PowerService.requestIgnoreBatteryOptimizations();
    // 无论是否成功，尝试刷新状态
    await Future.delayed(const Duration(milliseconds: 300));
    await _refresh();
    if (!mounted) return;
    setState(() => _loading = false);
    if (!(_isExempt ?? false) && !started) {
      // 失败时尝试打开设置列表作为降级
      await PowerService.openBatteryOptimizationSettings();
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusKnown = _isExempt != null;
    final exempt = _isExempt == true;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '保持后台运行',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
              if (statusKnown)
                Text(
                  exempt ? '已开启' : '未开启',
                  style: TextStyle(
                    fontSize: 12,
                    color: (exempt
                            ? Colors.green
                            : widget.theme.colorScheme.primary)
                        .withValues(alpha: 0.8),
                  ),
                )
              else
                const SizedBox.shrink(),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '为避免系统电池优化在后台杀死应用，请为 Dext 关闭电池优化。',
            style: TextStyle(
              fontSize: 12,
              color: widget.theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              FButton(
                style: context.theme.buttonStyles.primary.call,
                onPress: _loading ? null : _request,
                child: Text(
                  exempt
                      ? '重新申请/检查'
                      : (_loading ? '申请中…' : '申请忽略电池优化'),
                ),
              ),
              const SizedBox(width: 12),
              FButton(
                style: context.theme.buttonStyles.ghost.call,
                onPress: () async {
                  await PowerService.openBatteryOptimizationSettings();
                  await Future.delayed(const Duration(milliseconds: 300));
                  if (mounted) _refresh();
                },
                child: const Text('打开系统设置'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
class _FrostedCard extends StatefulWidget {
  const _FrostedCard();

  @override
  State<_FrostedCard> createState() => _FrostedCardState();
}

class _FrostedCardState extends State<_FrostedCard> {
  late bool _value;

  @override
  void initState() {
    super.initState();
    _value = SettingsService().glassCardEnabled;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '卡片渲染效果',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
              FSwitch(
                value: _value,
                onChange: (v) async {
                  setState(() => _value = v);
                  await SettingsService().setGlassCardEnabled(v);
                },
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '开启后卡片将采用毛玻璃效果，关闭则使用普通半透明',
            softWrap: true,
            overflow: TextOverflow.visible,
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}

// ---- 控件：侧滑触发范围 ----
class _EdgeDragWidgetCard extends StatefulWidget {
  final double initialValue;
  final ThemeData theme;
  final ValueChanged<double> onChanged;

  const _EdgeDragWidgetCard({
    super.key,
    required this.initialValue,
    required this.theme,
    required this.onChanged,
  });

  @override
  State<_EdgeDragWidgetCard> createState() => _EdgeDragWidgetCardState();
}

class _EdgeDragWidgetCardState extends State<_EdgeDragWidgetCard> {
  late FDiscreteSliderController _controller;
  late double _currentValue;
  // 全局覆盖层用于预览触发区域
  OverlayEntry? _previewOverlay;
  final ValueNotifier<double> _overlayWidth = ValueNotifier<double>(0);
  final ValueNotifier<double> _overlayOpacity = ValueNotifier<double>(0);
  Timer? _deferredShowTimer;
  // 拖动结束后自动隐藏
  Timer? _autoHideTimer;

  @override
  void initState() {
    super.initState();
    _currentValue = widget.initialValue;
    _controller = FDiscreteSliderController(
      selection: FSliderSelection(
        max: (_currentValue - 16) / 48,
      ),
    );
    // 监听移动端侧栏状态变化：打开时立即隐藏预览
    mobileSidebarOpen.addListener(_onMobileSidebarChanged);
  }

  @override
  void dispose() {
    _controller.dispose();
    _removeOverlay();
    _overlayWidth.dispose();
    _overlayOpacity.dispose();
    _autoHideTimer?.cancel();
    mobileSidebarOpen.removeListener(_onMobileSidebarChanged);
    super.dispose();
  }

  void _ensureOverlay() {
    if (_previewOverlay != null) return;
    _previewOverlay = OverlayEntry(
      builder: (context) {
        return IgnorePointer(
          ignoring: true,
          child: SafeArea(
            left: false,
            right: false,
            top: false,
            bottom: false,
            child: Stack(
              children: [
                ValueListenableBuilder<double>(
                  valueListenable: _overlayOpacity,
                  builder: (context, opacity, child) {
                    return AnimatedOpacity(
                      duration: const Duration(milliseconds: 180),
                      opacity: opacity.clamp(0.0, 1.0),
                      child: child,
                    );
                  },
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: ValueListenableBuilder<double>(
                      valueListenable: _overlayWidth,
                      builder: (context, width, _) {
                        return Container(
                          width: width,
                          height: double.infinity,
                          decoration: BoxDecoration(
                            color: Colors.lightBlueAccent.withValues(alpha: 0.18),
                            border: Border(
                              right: BorderSide(
                                color: Colors.lightBlueAccent.withValues(alpha: 0.35),
                                width: 1,
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
          ),
        );
      },
    );
    Overlay.of(context, rootOverlay: true).insert(_previewOverlay!);
  }

  void _removeOverlay() {
    _previewOverlay?.remove();
    _previewOverlay = null;
    _deferredShowTimer?.cancel();
  }

  void _showGlobalPreview(double pixels) {
    // 仅在“移动布局”中显示预览；桌面布局返回
    final screenWidth = MediaQuery.of(context).size.width;
    final bool isCompactLayout = screenWidth < 1025;
    final scaffoldState = Scaffold.maybeOf(context);
    final bool isDrawerOpen = scaffoldState?.isDrawerOpen ?? false;
    if (!isCompactLayout) {
      _overlayOpacity.value = 0;
      _deferredShowTimer?.cancel();
      Future.delayed(const Duration(milliseconds: 200), _removeOverlay);
      return;
    }
    // 侧边栏打开时不显示
    if (isDrawerOpen || mobileSidebarOpen.value) {
      _overlayOpacity.value = 0;
      _deferredShowTimer?.cancel();
      Future.delayed(const Duration(milliseconds: 150), () {
        if (mounted) _removeOverlay();
      });
      return;
    }

    // 稍作延迟后显示（避免闪烁）；在本页面我们不自动隐藏，使预览保持可见
    _deferredShowTimer?.cancel();
    _deferredShowTimer = Timer(const Duration(milliseconds: 60), () {
      if (!mounted) return;
      final s = Scaffold.maybeOf(context);
      final bool drawerNow = s?.isDrawerOpen ?? false;
      if (drawerNow || mobileSidebarOpen.value) {
        return;
      }
      _ensureOverlay();
      _overlayWidth.value = pixels.clamp(0, screenWidth);
      _overlayOpacity.value = 1.0;
    });
  }

  void _onMobileSidebarChanged() {
    if (!mounted) return;
    if (mobileSidebarOpen.value) {
      // 侧栏打开：立即隐藏并移除预览
      _overlayOpacity.value = 0;
      _deferredShowTimer?.cancel();
      _autoHideTimer?.cancel();
      Future.delayed(const Duration(milliseconds: 120), () {
        if (mounted) _removeOverlay();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '侧滑触发范围',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
              Text(
                '${_currentValue.toInt()}px',
                style: TextStyle(
                  fontSize: 12,
                  color: widget.theme.colorScheme.primary.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '调整从屏幕左侧边缘触发侧边栏的距离',
            style: TextStyle(
              fontSize: 12,
              color: widget.theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 8),
          FSlider(
            tooltipBuilder: (style, value) {
              final pixels = (16 + value * 48).round();
              return Text('${pixels}px');
            },
            controller: _controller,
            onChange: (selection) {
              final normalizedValue = _controller.selection.offset.max;
              final pixels = 16 + normalizedValue * 48;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                setState(() {
                  _currentValue = pixels;
                });
                _showGlobalPreview(pixels);
                widget.onChanged(pixels);
                // 停止拖动后自动隐藏预览
                _autoHideTimer?.cancel();
                _autoHideTimer = Timer(const Duration(milliseconds: 800), () {
                  if (!mounted) return;
                  _overlayOpacity.value = 0;
                  Future.delayed(const Duration(milliseconds: 150), () {
                    if (mounted) _removeOverlay();
                  });
                });
              });
            },
            marks: const [
              FSliderMark(value: 0, label: Text('16px')),
              FSliderMark(value: 0.25, tick: false),
              FSliderMark(value: 0.5, label: Text('40px')),
              FSliderMark(value: 0.75, tick: false),
              FSliderMark(value: 1, label: Text('64px')),
            ],
          ),
        ],
      ),
    );
  }
}

// ---- 控件：DPI 缩放 ----
class _DpiScaleCard extends StatefulWidget {
  final double initialValue;
  final ThemeData theme;
  final ValueChanged<double> onChanged;

  const _DpiScaleCard({
    required this.initialValue,
    required this.theme,
    required this.onChanged,
  });

  @override
  State<_DpiScaleCard> createState() => _DpiScaleCardState();
}

class _DpiScaleCardState extends State<_DpiScaleCard> {
  late FDiscreteSliderController _controller;
  late double _currentValue;

  @override
  void initState() {
    super.initState();
    _currentValue = widget.initialValue.clamp(0.85, 1.15);
    final normalized = ((_currentValue - 0.85) / 0.3).clamp(0.0, 1.0);
    _controller = FDiscreteSliderController(
      selection: FSliderSelection(max: normalized),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'DPI 缩放',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
              Text(
                '${(_currentValue * 100).toInt()}%',
                style: TextStyle(
                  fontSize: 12,
                  color: widget.theme.colorScheme.primary.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '调整界面元素的显示大小',
            style: TextStyle(
              fontSize: 12,
              color: widget.theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 8),
          FSlider(
            tooltipBuilder: (style, value) {
              final percentage = (85 + value * 30).round();
              return Text('$percentage%');
            },
            controller: _controller,
            onChange: (selection) {
              final normalizedValue = _controller.selection.offset.max;
              final scaleValue = 0.85 + normalizedValue * 0.3;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                setState(() {
                  _currentValue = scaleValue;
                });
                widget.onChanged(scaleValue);
              });
            },
            marks: const [
              FSliderMark(value: 0, label: Text('85%')),
              FSliderMark(value: 0.333, tick: false),
              FSliderMark(value: 0.5, label: Text('100%')),
              FSliderMark(value: 0.667, tick: false),
              FSliderMark(value: 1, label: Text('115%')),
            ],
          ),
        ],
      ),
    );
  }
}

// ---- 控件：问卷布局外观（Wizard / Continuous） ----
class _QuestionnaireLayoutCard extends StatefulWidget {
  final String initialValue;
  final ThemeData theme;
  final ValueChanged<String> onChanged;

  const _QuestionnaireLayoutCard({
    required this.initialValue,
    required this.theme,
    required this.onChanged,
  });

  @override
  State<_QuestionnaireLayoutCard> createState() => _QuestionnaireLayoutCardState();
}

class _QuestionnaireLayoutCardState extends State<_QuestionnaireLayoutCard> {
  late String _current;

  @override
  void initState() {
    super.initState();
    _current = widget.initialValue.isEmpty
        ? SettingsService.layoutWizard
        : widget.initialValue;
  }

  void _select(String value) {
    if (_current == value) return;
    setState(() => _current = value);
    widget.onChanged(value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final isDark = theme.brightness == Brightness.dark;
    final skeletonColor = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : const Color(0xFFE5E7EB);
    final phoneBorder = isDark
        ? Colors.white.withValues(alpha: 0.18)
        : const Color(0xFFDDDDDD);
    final phoneBg = isDark
        ? Colors.white.withValues(alpha: 0.04)
        : const Color(0xFFFAFAFA);
    final cardBg = theme.colorScheme.surface;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '外观',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
              Flexible(
                child: Text(
                  _current == SettingsService.layoutWizard ? 'Wizard 布局' : '连续布局',
                  textAlign: TextAlign.end,
                  softWrap: true,
                  overflow: TextOverflow.visible,
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.primary.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '选择问卷填写界面的外观布局方式',
            softWrap: true,
            overflow: TextOverflow.visible,
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              // 宽度足够时使用原始的 200 定宽 + Wrap 排版；
              // 放不下时再让卡片按可用宽度等分缩小，避免换行。
              const spacing = 16.0;
              const originalCardWidth = 200.0;
              const originalPhoneWidth = 104.0;
              const originalPhoneHeight = 170.0;
              final available = constraints.maxWidth;
              final enoughSpace =
                  available >= 2 * originalCardWidth + spacing;

              if (enoughSpace) {
                return Wrap(
                  spacing: spacing,
                  runSpacing: spacing,
                  alignment: WrapAlignment.center,
                  children: [
                    _buildLayoutOption(
                      value: SettingsService.layoutWizard,
                      title: 'Wizard 布局',
                      desc: '一次只显示一个问题',
                      selected: _current == SettingsService.layoutWizard,
                      theme: theme,
                      cardBg: cardBg,
                      phoneBorder: phoneBorder,
                      phoneBg: phoneBg,
                      skeletonColor: skeletonColor,
                      isDark: isDark,
                      mock: _MockPhoneKind.wizard,
                      cardWidth: originalCardWidth,
                      phoneWidth: originalPhoneWidth,
                      phoneHeight: originalPhoneHeight,
                    ),
                    _buildLayoutOption(
                      value: SettingsService.layoutContinuous,
                      title: '连续布局',
                      desc: '所有问题同页显示',
                      selected: _current == SettingsService.layoutContinuous,
                      theme: theme,
                      cardBg: cardBg,
                      phoneBorder: phoneBorder,
                      phoneBg: phoneBg,
                      skeletonColor: skeletonColor,
                      isDark: isDark,
                      mock: _MockPhoneKind.continuous,
                      cardWidth: originalCardWidth,
                      phoneWidth: originalPhoneWidth,
                      phoneHeight: originalPhoneHeight,
                    ),
                  ],
                );
              }

              // 空间不足：两张卡片等分宽度，手机模型按比例缩小
              final cardWidth = (available - spacing) / 2;
              final phoneWidth = (cardWidth - 28).clamp(64.0, 104.0);
              final phoneHeight =
                  (phoneWidth * 170 / 104).clamp(110.0, 170.0);
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildLayoutOption(
                    value: SettingsService.layoutWizard,
                    title: 'Wizard 布局',
                    desc: '一次只显示一个问题',
                    selected: _current == SettingsService.layoutWizard,
                    theme: theme,
                    cardBg: cardBg,
                    phoneBorder: phoneBorder,
                    phoneBg: phoneBg,
                    skeletonColor: skeletonColor,
                    isDark: isDark,
                    mock: _MockPhoneKind.wizard,
                    cardWidth: cardWidth,
                    phoneWidth: phoneWidth,
                    phoneHeight: phoneHeight,
                  ),
                  const SizedBox(width: spacing),
                  _buildLayoutOption(
                    value: SettingsService.layoutContinuous,
                    title: '连续布局',
                    desc: '所有问题同页显示',
                    selected: _current == SettingsService.layoutContinuous,
                    theme: theme,
                    cardBg: cardBg,
                    phoneBorder: phoneBorder,
                    phoneBg: phoneBg,
                    skeletonColor: skeletonColor,
                    isDark: isDark,
                    mock: _MockPhoneKind.continuous,
                    cardWidth: cardWidth,
                    phoneWidth: phoneWidth,
                    phoneHeight: phoneHeight,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLayoutOption({
    required String value,
    required String title,
    required String desc,
    required bool selected,
    required ThemeData theme,
    required Color cardBg,
    required Color phoneBorder,
    required Color phoneBg,
    required Color skeletonColor,
    required bool isDark,
    required _MockPhoneKind mock,
    required double cardWidth,
    required double phoneWidth,
    required double phoneHeight,
  }) {
    final highlight = theme.colorScheme.primary;
    return Semantics(
      button: true,
      selected: selected,
      label: '$title，$desc',
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _select(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          width: cardWidth,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? highlight : Colors.transparent,
              width: 2,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _MockPhone(
                kind: mock,
                borderColor: phoneBorder,
                phoneBg: phoneBg,
                skeletonColor: skeletonColor,
                width: phoneWidth,
                height: phoneHeight,
              ),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                softWrap: true,
                overflow: TextOverflow.visible,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: selected
                      ? highlight
                      : theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                desc,
                textAlign: TextAlign.center,
                softWrap: true,
                overflow: TextOverflow.visible,
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 8),
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width: selected ? 18 : 0,
                height: 4,
                decoration: BoxDecoration(
                  color: highlight,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _MockPhoneKind { wizard, continuous }

class _MockPhone extends StatelessWidget {
  final _MockPhoneKind kind;
  final Color borderColor;
  final Color phoneBg;
  final Color skeletonColor;
  final double? width;
  final double? height;

  const _MockPhone({
    required this.kind,
    required this.borderColor,
    required this.phoneBg,
    required this.skeletonColor,
    this.width,
    this.height,
  });

  Widget _skeleton() => FractionallySizedBox(
        widthFactor: 1.0,
        child: Container(
          height: 8,
          decoration: BoxDecoration(
            color: skeletonColor,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      );

  Widget _optionBar() => FractionallySizedBox(
        widthFactor: 0.7,
        alignment: Alignment.centerLeft,
        child: Container(
          height: 6,
          decoration: BoxDecoration(
            color: skeletonColor,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 104,
      height: 170,
      decoration: BoxDecoration(
        color: phoneBg,
        border: Border.all(color: borderColor, width: 1.5),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(10),
      child: kind == _MockPhoneKind.wizard
          ? _buildWizard()
          : _buildContinuous(),
    );
  }

  Widget _buildWizard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _skeleton(),
        const SizedBox(height: 10),
        _optionBar(),
        const SizedBox(height: 6),
        _optionBar(),
        const SizedBox(height: 6),
        _optionBar(),
        const Spacer(),
        Container(
          height: 18,
          decoration: BoxDecoration(
            color: skeletonColor,
            borderRadius: BorderRadius.circular(6),
          ),
        ),
      ],
    );
  }

  Widget _buildContinuous() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _skeleton(),
        const SizedBox(height: 6),
        _optionBar(),
        const SizedBox(height: 4),
        _optionBar(),
        const SizedBox(height: 4),
        _optionBar(),
        const SizedBox(height: 8),
        _skeleton(),
        const SizedBox(height: 6),
        _optionBar(),
        const SizedBox(height: 4),
        _optionBar(),
        const SizedBox(height: 4),
        _optionBar(),
        const SizedBox(height: 8),
        _skeleton(),
        const SizedBox(height: 6),
        _optionBar(),
        const SizedBox(height: 4),
        _optionBar(),
        const SizedBox(height: 4),
        _optionBar(),
      ],
    );
  }
}
