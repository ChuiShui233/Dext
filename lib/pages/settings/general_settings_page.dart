import 'dart:io';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../../components/loading_indicator.dart';
import '../../services/settings_service.dart';
import '../frame_page.dart';
import '../../widgets/top_safe_spacer.dart';

class GeneralSettingsPage extends StatelessWidget {
  final Function(ThemeMode) onThemeModeChange;
  final Function(double)? onDpiScaleChange;

  const GeneralSettingsPage({
    super.key,
    required this.onThemeModeChange,
    this.onDpiScaleChange,
  });

  Future<Map<String, dynamic>> _loadSettings() async {
    final s = SettingsService();
    return {
      'edge_drag_width': s.edgeDragWidth,
      'window_close_dont_ask': s.windowCloseDontAsk,
      'window_close_default_action': s.windowCloseDefaultAction,
      'dpi_scale': s.dpiScale,
      'theme_mode': s.themeMode,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool isDesktopLayout = MediaQuery.of(context).size.width >= 1025;
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Stack(
        children: [
          // 纯色背景
          Container(color: theme.colorScheme.surface),
          Column(
            children: [
              const TopSafeSpacer(),
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
                                  final mode = SettingsService().themeMode;
                                  return '当前: ${mode == 'light' ? '浅色模式' : mode == 'dark' ? '深色模式' : '跟随系统'}';
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
                                String pref;
                                ThemeMode themeMode;
                                switch (mode) {
                                  case '浅色模式':
                                    themeMode = ThemeMode.light;
                                    pref = 'light';
                                    break;
                                  case '深色模式':
                                    themeMode = ThemeMode.dark;
                                    pref = 'dark';
                                    break;
                                  case '跟随系统':
                                  default:
                                    themeMode = ThemeMode.system;
                                    pref = 'system';
                                }
                                await SettingsService().setThemeMode(pref);
                                onThemeModeChange(themeMode);
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
                            SettingsService().setDpiScale(v);
                            onDpiScaleChange?.call(v);
                          },
                        ),
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
                          title: const Text('窗口关闭行为'),
                          details: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '当前: $currentDisplayValue',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.primary.withValues(alpha: 0.7),
                                ),
                              ),
                              const SizedBox(height: 8),
                              FSelect<String>(
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
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                            child: Row(
                              children: [
                                Icon(Icons.tune_outlined, size: 20, color: theme.colorScheme.primary),
                                const SizedBox(width: 8),
                                Text(
                                  '通用',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                              ],
                            ),
                          ),
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
