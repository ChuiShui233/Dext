import 'dart:async';
import 'dart:ui' as ui;

import 'package:dext/widgets/frosted_glass_background.dart';
import 'package:dext/widgets/downscaled_blur.dart';
import 'package:dext/widgets/glass_sidebar_card.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';
import 'package:layout/layout.dart';
import 'package:dext/services/settings_service.dart';
import '../services/api_service.dart';
import '../models/project.dart';
import '../models/survey.dart';
import '../models/user.dart';
import 'home_page.dart';
import 'project_page.dart';
import 'survey_page.dart';
import 'public_survey_page.dart';
import '../utils/error_formatter.dart';
import '../services/config.dart';

final showSidebarInDrawer = LayoutValue(xs: true, md: false);
final showSidebarInline = LayoutValue(xs: false, md: true);

class FramePage extends StatefulWidget {
  final int selectedIndex;
  final Function(int) onIndexChanged;
  final VoidCallback onLogout;
  final Function(ThemeMode) onThemeModeChange;
  final ApiService? apiService;
  final PageStorageBucket bucket;
  final ValueNotifier<User?>? userNotifier;

  const FramePage({
    super.key,
    required this.selectedIndex,
    required this.onIndexChanged,
    required this.onLogout,
    required this.onThemeModeChange,
    this.apiService,
    required this.bucket,
    this.userNotifier,
  });

  @override
  FramePageState createState() => FramePageState();
}

/// 私有导航观察者：当嵌套 Navigator 发生路由变化时，触发一次回调
class _BackdropNavObserver extends NavigatorObserver {
  final VoidCallback onRouteChanged;
  _BackdropNavObserver(this.onRouteChanged);

  void _tick() {
    try {
      onRouteChanged();
    } catch (_) {}
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _tick();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _tick();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    _tick();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    _tick();
  }
}

class FramePageState extends State<FramePage> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  int _currentTabIndex = 0;
  int _projectCount = 0;
    int _surveyCount = 0;
    User? _currentUser;
    final GlobalKey<NavigatorState> _contentNavigatorKey = GlobalKey<NavigatorState>();
    // 自定义侧滑菜单：动画与手势状态
    late final AnimationController _menuController;
    late final Animation<double> _menuScale;
    late final Animation<double> _pageScale;
    late final Animation<Offset> _menuSlide;
    bool _isDraggingFromEdge = false;
    double _dragStartX = 0;
    // 页面聚焦背景：截取当前内容作为背景进行放大模糊
    final GlobalKey _backdropRepaintKey = GlobalKey();
    ui.Image? _backdropImage;
    bool _isCapturingBackdrop = false;
    bool _pendingCapture = false;
    bool _backdropLoopActive = false;
    Brightness? _lastBrightness;
    NavigatorObserver? _backdropNavObserver;
    
    void navigateToPublicSurvey(String surveyId) {
      final nav = _contentNavigatorKey.currentState;
      if (nav != null) {
        nav.push(
          MaterialPageRoute(
            builder: (context) => _buildPublicSurveyPage(surveyId),
          ),
        );
        // 导航后强制更新聚焦背景
        _forceBackdropUpdate();
      }
    }
    
    Widget _buildPublicSurveyPage(String surveyId) {
      return PublicSurveyPage(surveyUID: surveyId);
    }
    
    bool _hasLoadedData = false;
    bool _hasLoadedUser = false;
    
    @override
  void dispose() {
    widget.userNotifier?.removeListener(_handleUserUpdate);
    _menuController.dispose();
    // _backdropImage?.dispose(); // 可选：某些平台需要显式释放
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

    @override
  void initState() {
      super.initState();
      _currentTabIndex = widget.selectedIndex;
      _loadData();
      _fetchUserData();
      
      widget.userNotifier?.addListener(_handleUserUpdate);

      // 初始化移动端侧滑菜单动画
      _menuController = AnimationController(vsync: this, duration: const Duration(milliseconds: 280));
      // 侧边栏不使用缩放动画，始终保持原始大小
      _menuScale = Tween<double>(begin: 1.0, end: 1.0)
          .animate(CurvedAnimation(parent: _menuController, curve: Curves.easeOutCubic));
      _pageScale = Tween<double>(begin: 1.0, end: 0.86)
          .animate(CurvedAnimation(parent: _menuController, curve: Curves.easeOutCubic));
      // 侧边栏滑入动画延迟启动，让页面先开始缩放，营造分层视觉效果
      _menuSlide = Tween<Offset>(begin: const Offset(-1, 0), end: Offset.zero)
          .animate(CurvedAnimation(
            parent: _menuController, 
            curve: const Interval(0.16, 1.0, curve: Curves.easeOutCubic),
          ));

      // 侧滑进度变化时，仅在侧边栏打开时实时更新背景截图
      _menuController.addListener(() {
        if (_menuController.value > 0.01) {
          _scheduleBackdropUpdate();
          _ensureBackdropLoop();
        } else {
          // 侧边栏关闭：停止帧循环
          _backdropLoopActive = false;
        }
      });
      // 首次渲染后截一次图
      WidgetsBinding.instance.addPostFrameCallback((_) => _scheduleBackdropUpdate());
      // 监听系统主题变化
      WidgetsBinding.instance.addObserver(this);

      // 监听右侧嵌套 Navigator 的路由变化，切换页面后刷新聚焦背景
      _backdropNavObserver = _BackdropNavObserver(() {
        _forceBackdropUpdate();
      });
    }

    @override
    void didChangePlatformBrightness() {
      super.didChangePlatformBrightness();
      // 系统深浅色切换时刷新截图
      WidgetsBinding.instance.addPostFrameCallback((_) => _scheduleBackdropUpdate());
    }
    
    // 根据屏幕宽度与DPR，为移动布局内容计算一个基础缩放系数
    double _baseScaleForWidth(BuildContext context) {
      final mq = MediaQuery.of(context);
      final w = mq.size.width;
      final dpr = mq.devicePixelRatio;
      // 小屏/高DPI设备稍微缩小，避免局促；中大屏保持1.0
      if (w < 360) return 0.96;
      if (w < 400) return 0.98;
      if (dpr >= 3.0 && w < 420) return 0.98;
      return 1.0;
    }

    // 扩大从屏幕左缘开始的拖拽触发范围，适配不同宽度与DPR
    double _edgeDragWidth(BuildContext context) {
      final mq = MediaQuery.of(context);
      final w = mq.size.width;
      final dpr = mq.devicePixelRatio;
      // 基础 24px，窄屏或高DPR增加到 32~44px
      double base = 24.0;
      if (w < 360) {
        base = 44.0;
      } else if (w < 400) {
        base = 36.0;
      }
      if (dpr >= 3.0 && base < 40.0) {
        base = 40.0;
      }
      return base;
    }

    // 根据屏幕宽度/方向/DPI 计算侧边栏宽度，保持在合理范围
    double _computeSidebarWidth(BuildContext context) {
      final mq = MediaQuery.of(context);
      final w = mq.size.width;
      final isPortrait = mq.orientation == Orientation.portrait;
      final dpr = mq.devicePixelRatio;

      double fraction;
      if (w <= 340) {
        fraction = 0.66;
      } else if (w <= 380) {
        fraction = 0.60;
      } else if (w <= 420) {
        fraction = 0.56;
      } else if (w <= 480) {
        fraction = 0.50;
      } else if (w <= 640) {
        fraction = 0.46;
      } else {
        // 更宽的移动端/平板，收窄一点
        fraction = isPortrait ? 0.42 : 0.38;
      }

      // 高DPI设备适当放大一点侧栏
      if (dpr >= 3.0) {
        fraction += 0.02;
      }

      double width = w * fraction;
      // 限制在 200~340 间，且不超过屏宽 - 56（保留界面余量）
      final double maxAllowed = (w - 56).clamp(240.0, 420.0);
      width = width.clamp(200.0, maxAllowed);
      // 同时与传统桌面侧栏宽度范围保持相近
      width = width.clamp(220.0, 320.0);
      return width;
    }
    
    void _handleUserUpdate() {
      if (mounted) {
        setState(() {
          _currentUser = widget.userNotifier?.value;
        });
      }
    }

    Future<void> _fetchUserData() async {
      if (_hasLoadedUser) return;
      
      try {
        if (widget.apiService != null) {
          final user = await widget.apiService!.getCurrentUserHandler();
          if (mounted) {
            setState(() {
              _currentUser = user;
              _hasLoadedUser = true;
            });
          }
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _hasLoadedUser = true;
          });
        }
        if (kDebugMode) {
          print('获取用户数据失败: $e');
        }
      }
    }

  @override
  void didUpdateWidget(FramePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedIndex != oldWidget.selectedIndex) {
      setState(() {
        _currentTabIndex = widget.selectedIndex;
      });
      _forceBackdropUpdate();
    }
  }

  Future<void> _loadData() async {
    if (widget.apiService == null || _hasLoadedData) return;

    try {
      final projects = await widget.apiService!.getProjects();
      final surveys = await widget.apiService!.getSurveys();

      if (!mounted) return;

      setState(() {
        _projectCount = projects.length;
        _surveyCount = surveys.length;
        _hasLoadedData = true;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasLoadedData = true;
        });
      }
    }
  }

  void handleTabChange(int index) {
    if (_currentTabIndex == index) {
      return;
    }
    
    // 切换 Tab 时，替换右侧嵌套 Navigator 的根路由，使之进入对应的一级页面
    if (_contentNavigatorKey.currentState != null) {
      _contentNavigatorKey.currentState!.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => _buildRootForTab(index)),
        (route) => false,
      );
    }
    setState(() => _currentTabIndex = index);
    widget.onIndexChanged(index);
    // Tab 切换后更新聚焦背景
    WidgetsBinding.instance.addPostFrameCallback((_) => _scheduleBackdropUpdate());
  }

  void _handleProjectTap() {
    handleTabChange(3);
  }

  void _handleSurveyTap() {
    handleTabChange(4);
  }


  @override
  Widget build(BuildContext context) {
    // 依据断点决定是否显示“桌面布局”（侧边栏内联），不再受平台限制（Web 也支持）
    final bool showDesktopLayout = showSidebarInline.resolve(context);
    // 主题变化时，刷新一次截图
    final currentBrightness = Theme.of(context).brightness;
    if (currentBrightness != _lastBrightness) {
      _lastBrightness = currentBrightness;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scheduleBackdropUpdate());
    }
    // 若为移动布局且侧边栏当前处于打开状态，但循环未激活，则立即激活帧循环
    if (!showDesktopLayout && _menuController.value > 0.01 && !_backdropLoopActive) {
      _ensureBackdropLoop();
    }
    // 进入桌面布局时，强制收起移动侧栏动画，避免残留聚焦背景/圆角
    if (showDesktopLayout && _menuController.value != 0.0) {
      _menuController.value = 0.0;
    }

    // 统一采用嵌套 Navigator 承载右侧内容区域，避免切换桌面/移动布局时丢失栈
    final contentArea = Navigator(
      key: _contentNavigatorKey,
      onGenerateRoute: (settings) {
        // 用作兜底；首次构建或未显式设置时，加载当前 Tab 的根页面
        return MaterialPageRoute(builder: (_) => _buildRootForTab(_currentTabIndex));
      },
      onGenerateInitialRoutes: (_, __) => [
        MaterialPageRoute(builder: (_) => _buildRootForTab(_currentTabIndex)),
      ],
      observers: [
        _backdropNavObserver ??= _BackdropNavObserver(() {
          _forceBackdropUpdate();
        })
      ],
    );

    if (showDesktopLayout) {

      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) async {
          if (!didPop) {
            final shouldPop = await _handleWillPop();
            if (shouldPop && context.mounted) {
              Navigator.of(context).pop();
            }
          }
        },
        child: PageStorage(
          bucket: widget.bucket,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSidebar(context),
              Expanded(
                child: RepaintBoundary(
                  key: _backdropRepaintKey,
                  child: contentArea,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 移动端布局：启用全局自定义左侧侧滑菜单，边缘侧滑+跟手动画
    final double gapBetweenSidebarAndContent = 12.0; // 固定间距
    final double sidebarWidth = _computeSidebarWidth(context);
    final double leftOpen = sidebarWidth + gapBetweenSidebarAndContent; // 内容整体右移量 = 侧边栏宽度 + 间距

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop) {
          final shouldPop = await _handleWillPop();
          if (shouldPop && context.mounted) {
            Navigator.of(context).pop();
          }
        }
      },
      child: GestureDetector(
        onHorizontalDragStart: (details) {
          _dragStartX = details.globalPosition.dx;
          final double edge = _edgeDragWidth(context);
          _isDraggingFromEdge = _dragStartX <= edge || _menuController.isCompleted;
        },
        onHorizontalDragUpdate: (details) {
          if (!_isDraggingFromEdge) return;
          final delta = details.primaryDelta ?? 0;
          final newValue = (_menuController.value + delta / leftOpen).clamp(0.0, 1.0);
          _menuController.value = newValue;
        },
        onHorizontalDragEnd: (details) {
          if (!_isDraggingFromEdge) return;
          final threshold = 0.5;
          if (_menuController.value > threshold) {
            _menuController.fling(velocity: 2.0);
          } else {
            _menuController.fling(velocity: -2.0);
          }
        },
        child: Stack(
          children: [
            AnimatedBuilder(
              animation: _menuController,
              builder: (context, _) {
                final value = _menuController.value;
                if (value <= 0.0) return const SizedBox.shrink();
                final radius = ui.lerpDouble(0, 24, value) ?? 0;
                return Positioned.fill(
                  child: _buildFocusedBackdrop(context, radius: radius),
                );
              },
            ),
            SlideTransition(
              position: _menuSlide,
              child: ScaleTransition(
                scale: _menuScale,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    width: sidebarWidth,
                    height: double.infinity,
                    // 在侧边栏与内容区域之间留出固定间距，避免视觉重叠
                    margin: EdgeInsets.only(right: gapBetweenSidebarAndContent),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.zero,
                      border: Border.all(color: Colors.white.withValues(alpha: 0.12), width: 1),
                    ),
                    child: _buildSidebar(context),
                  ),
                ),
              ),
            ),
            AnimatedBuilder(
              animation: _menuController,
              builder: (context, _) {
                final value = _menuController.value;
                // 仅在侧边栏展开时逐步应用基础缩放，关闭时保持1.0，避免圆角屏出现未填满的视觉问题
                final baseScale = _baseScaleForWidth(context);
                final blendedScale = ui.lerpDouble(1.0, baseScale, value) ?? 1.0;
                return Transform.translate(
                  offset: Offset(value * leftOpen, 0),
                  child: Transform.scale(
                    scale: _pageScale.value * blendedScale,
                    alignment: Alignment.center,
                    child: AbsorbPointer(
                      absorbing: false,
                      child: PageStorage(
                        bucket: widget.bucket,
                        child: Builder(builder: (context) {
                          final radius = ui.lerpDouble(0, 24, _menuController.value) ?? 0;
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(radius),
                            clipBehavior: Clip.hardEdge,
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                              ...(radius <= 0.1
                                  ? [
                                      RepaintBoundary(
                                        key: _backdropRepaintKey,
                                        child: contentArea,
                                      ),
                                    ]
                                  : [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(radius),
                                        clipBehavior: Clip.hardEdge,
                                        child: Stack(
                                          fit: StackFit.expand,
                                          children: [
                                            const SizedBox.expand(),
                                            RepaintBoundary(
                                              key: _backdropRepaintKey,
                                              child: contentArea,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ]),
                              if (radius > 0.2)
                                Positioned.fill(
                                  child: IgnorePointer(
                                    child: Container(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(radius),
                                        border: Border.all(
                                          color: Theme.of(context).colorScheme.outlineVariant
                                              .withValues(alpha: 0.14),
                                          width: 1,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              Positioned.fill(
                                child: IgnorePointer(
                                  ignoring: value <= 0.01,
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.translucent,
                                    onTap: () {
                                      if (_menuController.status != AnimationStatus.reverse && _menuController.value > 0.01) {
                                        _menuController.reverse();
                                      }
                                    },
                                    child: const SizedBox.expand(),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          );
                        }),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFocusedBackdrop(BuildContext context, {double radius = 0}) {
    if (_backdropImage == null) {
      return const FrostedGlassBackground(
        count: 8,
        blurSigma: 80,
        blobOpacity: 0.5,
        animated: true,
        vignette: true,
      );
    }
    final double p = _menuController.value.clamp(0.0, 1.0);
    final double blurBottom = ui.lerpDouble(14, 20, p) ?? 18;
    final double scaleBottom = ui.lerpDouble(1.06, 1.18, p) ?? 1.12;
    final double blurTop = ui.lerpDouble(6, 12, p) ?? 10;
    final double scaleTop = ui.lerpDouble(1.02, 1.26, p) ?? 1.2;
    final double opacityTop = Curves.easeOut.transform(p) * 0.65;

    return Stack(
      fit: StackFit.expand,
      children: [
        Transform.scale(
          scale: scaleBottom,
          child: DownscaledBlur(
            sigma: blurBottom,
            downscale: 0.5,
            child: RawImage(
              image: _backdropImage,
              fit: BoxFit.cover,
              alignment: Alignment.center,
              filterQuality: (_menuController.isAnimating && p > 0.01) ? FilterQuality.none : FilterQuality.low,
            ),
          ),
        ),
        Opacity(
          opacity: opacityTop,
          child: Transform.scale(
            scale: scaleTop,
            child: DownscaledBlur(
              sigma: blurTop,
              downscale: 0.4,
              child: RawImage(
                image: _backdropImage,
                fit: BoxFit.cover,
                alignment: Alignment.center,
                filterQuality: (_menuController.isAnimating && p > 0.01) ? FilterQuality.none : FilterQuality.low,
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _scheduleBackdropUpdate() {
    if (!mounted) return;
    if (_isCapturingBackdrop) {
      _pendingCapture = true;
      return;
    }
    _isCapturingBackdrop = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final boundary = _backdropRepaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
        if (boundary != null) {
          final dpr = MediaQuery.of(context).devicePixelRatio.clamp(1.0, 2.5);
          final ui.Image img = await boundary.toImage(pixelRatio: dpr);
          if (!mounted) return;
          setState(() {
            _backdropImage = img;
          });
        }
      } catch (_) {
        // 忽略截图失败，保持原背景
      } finally {
        _isCapturingBackdrop = false;
        if (_pendingCapture) {
          // 立即消费排队的请求
          _pendingCapture = false;
          _scheduleBackdropUpdate();
        }
      }
    });
  }

  void _forceBackdropUpdate() {
    // 实时刷新背景截图
    WidgetsBinding.instance.addPostFrameCallback((_) => _scheduleBackdropUpdate());
  }

  // 每一帧都刷新一次聚焦背景
  void _ensureBackdropLoop() {
    if (_backdropLoopActive) return;
    _backdropLoopActive = true;
    void pump() {
      if (!mounted) { _backdropLoopActive = false; return; }
      if (_menuController.value <= 0.01) { _backdropLoopActive = false; return; }
      _scheduleBackdropUpdate();
      WidgetsBinding.instance.addPostFrameCallback((_) => pump());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => pump());
  }

  Future<bool> _handleWillPop() async {
    final nav = _contentNavigatorKey.currentState;
    if (nav != null && nav.canPop()) {
      nav.pop();

      _forceBackdropUpdate();
      return false;
    }
    if (_currentTabIndex != 0) {
      handleTabChange(0);
      return false;
    }
    final shouldExit = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (context) => FDialog(
        direction: Axis.horizontal,
        title: const Text('确认退出'),
        body: const Text('确定要退出应用吗？'),
        actions: [
          FButton(
            style: FButtonStyle.outline,
            onPress: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FButton(
            onPress: () => Navigator.pop(context, true),
            child: const Text('退出'),
          ),
        ],
      ),
    );

    if (shouldExit == true) {
      await SystemNavigator.pop();
      return false;
    }
    return false; // 取消退出
  }

  // 根据 Tab 索引构建右侧区域的“根页面”
  Widget _buildRootForTab(int index) {
    switch (index) {
      case 0:
      case 1:
      case 2:
        return HomePage(
          apiService: widget.apiService!,
          currentIndex: index,
          projectCount: _projectCount,
          surveyCount: _surveyCount,
          onProjectTap: _handleProjectTap,
          onSurveyTap: _handleSurveyTap,
          onLogout: widget.onLogout,  // 直接传递 main.dart 的 onLogout，不要传递 _handleLogout
          onThemeModeChange: widget.onThemeModeChange,
          onTabChanged: handleTabChange,
          userNotifier: widget.userNotifier,
        );
      case 3:
        return ProjectPage(token: widget.apiService?.authToken ?? '');
      case 4:
        return SurveyPage(token: widget.apiService?.authToken ?? '');
      default:
        return const Center(child: Text('未知页面'));
    }
  }

  Widget _buildSidebar(BuildContext context) {

    return DefaultTextStyle.merge(
      style: const TextStyle(
        decoration: TextDecoration.none,
        decorationColor: Colors.transparent,
        decorationStyle: TextDecorationStyle.solid,
      ),
      child: FSidebar(
        key: const PageStorageKey('sidebar'),
        header: _buildSidebarHeader(context),
        footer: _buildSidebarFooter(context),
        children: [
          _buildMainNavigation(context),
          const SizedBox(height: 16),
          _buildQuickActions(context),
          const SizedBox(height: 16),
          _buildSettingsSection(context),
        ],
      ),
    );
  }

Widget _buildSidebarHeader(BuildContext context) {
  return Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [
          Theme.of(context).colorScheme.primary.withValues(alpha: 0),
            Theme.of(context).colorScheme.primary.withValues(alpha: 0),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 40, // 图片容器宽度
                height: 40, // 图片容器高度
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8), // 圆角
                  child: Image.asset(
                    'assets/images/Dext.png',
                    fit: BoxFit.cover, // 占满整个容器
                    errorBuilder: (context, error, stackTrace) => Icon(
                      FIcons.house,
                      size: 40,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '问卷调查',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    Text(
                      '管理平台',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FDivider(
            style: FDividerStyle(
              padding: EdgeInsets.zero,
              color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    ),
  );
}

  Widget _buildSidebarFooter(BuildContext context) {
    return GlassSidebarCard(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      borderRadius: 12,
      blurSigma: 20,
      showShadow: true,
      child: Column(
          children: [
            Row(
              children: [
                Container(
                    padding: _currentUser?.avatarUrl != null ? const EdgeInsets.all(2) : const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _currentUser?.avatarUrl != null 
                          ? Colors.transparent 
                          : Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: (_currentUser?.avatarUrl?.isNotEmpty ?? false)
    ? ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          toAbsoluteUrl(_currentUser!.avatarUrl!),
          width: 32,
          height: 32,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => Icon(
            FIcons.userRound,
            size: 16,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      )
    : Icon(
        FIcons.userRound,
        size: 16,
        color: Theme.of(context).colorScheme.primary,
      ),

                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          _currentUser?.username ?? 'Ghost',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          _currentUser?.email ?? '啥也没有捏',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              ],
              
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FButton(
                    style: FButtonStyle.ghost,
                    onPress: () {
                      _showThemeMenu(context);
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Theme.of(context).brightness == Brightness.dark
                              ? FIcons.moon
                              : FIcons.sun,
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '主题',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FButton(
                    style: FButtonStyle.ghost,
                    onPress: () {
                      _showLogoutConfirmDialog(context);
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(FIcons.logOut, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          '退出',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
    );
  }

  Widget _buildMainNavigation(BuildContext context) {
    return FSidebarGroup(
      label: Row(
        children: [
          Icon(
            FIcons.navigation,
            size: 16,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Text(
            '主要功能',
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      children: [
        FSidebarItem(
          icon: const Icon(FIcons.house),
          label: const Text('主页'),
          selected: _currentTabIndex == 0,
          onPress: () {
            handleTabChange(0);
          },
        ),
        FSidebarItem(
          icon: const Icon(FIcons.folderArchive),
          label: const Text('项目管理'),
          selected: _currentTabIndex == 3,
          onPress: () {
            handleTabChange(3);
          },
        ),
        FSidebarItem(
          icon: const Icon(FIcons.notebookPen),
          label: const Text('问卷管理'),
          selected: _currentTabIndex == 4,
          onPress: () {
            handleTabChange(4);
          },
        ),
      ],
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    return FSidebarGroup(
      label: Row(
        children: [
          Icon(
            FIcons.zap,
            size: 16,
            color: Theme.of(context).colorScheme.secondary,
          ),
          const SizedBox(width: 8),
          Text(
            '快速操作',
            style: TextStyle(
              color: Theme.of(context).colorScheme.secondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      children: [
        FSidebarItem(
          icon: const Icon(FIcons.plus),
          label: const Text('新建项目'),
          onPress: () {
            _showCreateProjectDialog(context);
          },
        ),
        FSidebarItem(
          icon: const Icon(FIcons.fileText),
          label: const Text('新建问卷'),
          onPress: () {
            _showCreateSurveyDialog(context);
          },
        ),
        FSidebarItem(
          icon: const Icon(Icons.bar_chart),
          label: const Text('数据统计'),
          onPress: () {
            _showStatisticsDialog(context);
          },
        ),
      ],
    );
  }

  Widget _buildSettingsSection(BuildContext context) {
    return FSidebarGroup(
      label: Row(
        children: [
          Icon(
            FIcons.settings,
            size: 16,
            color: Theme.of(context).colorScheme.secondary,
          ),
          const SizedBox(width: 8),
          Text(
            '设置与工具',
            style: TextStyle(
              color: Theme.of(context).colorScheme.secondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      children: [
        FSidebarItem(
          icon: const Icon(FIcons.clock),
          label: const Text('历史记录'),
          selected: _currentTabIndex == 1,
          onPress: () {
            handleTabChange(1);
          },
        ),
        FSidebarItem(
          icon: const Icon(FIcons.settings),
          label: const Text('系统设置'),
          selected: _currentTabIndex == 2,
          onPress: () {
            handleTabChange(2);
          },
        ),
      ],
    );
  }

  void _showThemeMenu(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => FDialog(
        title: const Text('主题设置'),
        body: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FButton(
              style: FButtonStyle.ghost,
              onPress: () async {
                final navigator = Navigator.of(context);
                await SettingsService().setThemeMode('system');
                widget.onThemeModeChange(ThemeMode.system);
                if (mounted) {
                  navigator.pop();
                }
              },
              child: const Text('跟随系统'),
            ),
            FButton(
              style: FButtonStyle.ghost,
              onPress: () async {
                final navigator = Navigator.of(context);
                await SettingsService().setThemeMode('light');
                widget.onThemeModeChange(ThemeMode.light);
                if (mounted) {
                  navigator.pop();
                }
              },
              child: const Text('浅色模式'),
            ),
            FButton(
              style: FButtonStyle.ghost,
              onPress: () async {
                final navigator = Navigator.of(context);
                await SettingsService().setThemeMode('dark');
                widget.onThemeModeChange(ThemeMode.dark);
                if (mounted) {
                  navigator.pop();
                }
              },
              child: const Text('深色模式'),
            ),
          ],
        ),
        actions: [
          FButton(
            child: const Text('关闭'),
            onPress: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  void _showCreateProjectDialog(BuildContext context) {
    if (widget.apiService == null) {
      showDialog(
        context: context,
        builder: (context) => FDialog(
          title: const Text('提示'),
          body: const Text('无法创建项目，请先登录'),
          actions: [
            FButton(
              child: const Text('关闭'),
              onPress: () => Navigator.pop(context),
            ),
          ],
        ),
      );
      return;
    }

    final TextEditingController nameController = TextEditingController();
    final TextEditingController descController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => FDialog(
        direction: Axis.horizontal,
        title: const Text('快速创建项目'),
        body: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FTextField(
              controller: nameController,
              label: const Text('项目名称'),
              hint: '请输入项目名称',
            ),
            const SizedBox(height: 16),
            FTextField(
              controller: descController,
              label: const Text('项目描述'),
              hint: '请输入项目描述',
            ),
          ],
        ),
        actions: [
          FButton(
            style: FButtonStyle.outline,
            onPress: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FButton(
            onPress: () async {
              if (nameController.text.isEmpty || descController.text.isEmpty) {
                showFToast(
                  context: context,
                  alignment: FToastAlignment.bottomRight,
                  title: const Text('提示'),
                  description: const Text('请填写完整信息'),
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

              try {
                final newProject = Project(
                  id: 0,
                  projectName: nameController.text.trim(),
                  projectDescription: descController.text.trim(),
                  userId: '',
                  createBy: '',
                  createTime: DateTime.now().toIso8601String(),
                  updateTime: DateTime.now().toIso8601String(),
                  updateBy: '',
                );

                await widget.apiService!.createProject(newProject);
                if (!context.mounted) return;
                
                Navigator.pop(context); // 关闭对话框
                // 切换到“项目管理”页（在桌面端由右侧嵌套 Navigator 承载）
                handleTabChange(3);
                
                showFToast(
                  context: context,
                  alignment: FToastAlignment.bottomRight,
                  title: const Text('创建成功'),
                  description: const Text('项目已创建，正在跳转到项目管理页面'),
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
              } catch (e) {
                if (!context.mounted) return;
                
                showFToast(
                  context: context,
                  alignment: FToastAlignment.bottomRight,
                  title: const Text('创建失败'),
                  description: Text('创建项目失败: $e'),
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
              }
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }

  void _showCreateSurveyDialog(BuildContext context) {
    if (widget.apiService == null) {
      showDialog(
        context: context,
        builder: (context) => FDialog(
          title: const Text('提示'),
          body: const Text('无法创建问卷，请先登录'),
          actions: [
            FButton(
              child: const Text('关闭'),
              onPress: () => Navigator.pop(context),
            ),
          ],
        ),
      );
      return;
    }

    final TextEditingController nameController = TextEditingController();
    final TextEditingController descController = TextEditingController();
    List<Project> projects = [];
    int? selectedProjectId;
    bool isLoadingProjects = false; // 添加加载状态标志
    bool hasLoadedProjects = false; // 添加已加载标志

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          if (projects.isEmpty && !isLoadingProjects && !hasLoadedProjects) {
            Timer? loadingTimer = Timer(const Duration(milliseconds: 150), () {
              if (context.mounted && isLoadingProjects) {
                setState(() {
                  isLoadingProjects = true;
                });
              }
            });
            
            widget.apiService!.getProjects().then((loadedProjects) {
              loadingTimer.cancel();
              if (context.mounted) {
                setState(() {
                  projects = loadedProjects;
                  isLoadingProjects = false;
                  hasLoadedProjects = true; // 标记已加载完成
                  if (projects.isNotEmpty) {
                    selectedProjectId = projects.first.id;
                  }
                });
              }
            }).catchError((error) {
              loadingTimer.cancel();
              if (context.mounted) {
                setState(() {
                  isLoadingProjects = false;
                  hasLoadedProjects = true; // 即使出错也标记为已加载，避免无限重试
                });
                showFToast(
                  context: context,
                  alignment: FToastAlignment.bottomRight,
                  title: const Text('加载失败'),
                  description: Text(ErrorFormatter.format(error)),
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
              }
            });
          }

          return FDialog(
            direction: Axis.horizontal,
            title: const Text('快速创建问卷'),
            body: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isLoadingProjects)
                  const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: CircularProgressIndicator(),
                  )
                else if (projects.isNotEmpty)
                  FSelect<int>(
                    label: const Text('所属项目'),
                    hint: '请选择项目',
                    format: (value) => projects
                        .firstWhere((p) => p.id == value)
                        .projectName,
                    onChange: (value) {
                      setState(() {
                        selectedProjectId = value;
                      });
                    },
                    children: projects.map((project) {
                      return FSelectItem(
                        project.projectName,
                        project.id,
                      );
                    }).toList(),
                  )
                else if (hasLoadedProjects) // 已加载但没有项目
                  const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text('暂无项目，请先创建项目'),
                  )
                else
                  const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: CircularProgressIndicator(),
                  ),
                const SizedBox(height: 16),
                FTextField(
                  controller: nameController,
                  label: const Text('问卷标题'),
                  hint: '请输入问卷标题',
                ),
                const SizedBox(height: 16),
                FTextField(
                  controller: descController,
                  label: const Text('问卷描述'),
                  hint: '请输入问卷描述',
                ),
              ],
            ),
            actions: [
              FButton(
                style: FButtonStyle.outline,
                onPress: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              FButton(
                onPress: () async {
                  if (nameController.text.isEmpty || 
                      descController.text.isEmpty || 
                      selectedProjectId == null) {
                    showFToast(
                      context: context,
                      alignment: FToastAlignment.bottomRight,
                      title: const Text('提示'),
                      description: const Text('请填写完整信息并选择项目'),
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

                  try {
                    final newSurvey = Survey(
                      id: 0,
                      surveyUid: DateTime.now().millisecondsSinceEpoch.toString(),
                      surveyName: nameController.text.trim(),
                      description: descController.text.trim(),
                      surveyType: 0, // 默认普通问卷
                      surveyStatus: 0, // 默认未发布
                      totalTimes: 0,
                      projectId: selectedProjectId!,
                      deadline: null,
                      createTime: DateTime.now().toIso8601String(),
                      updateTime: DateTime.now().toIso8601String(),
                    );

                    await widget.apiService!.createSurvey(newSurvey);
                    if (!context.mounted) return;
                    
                    Navigator.pop(context); // 关闭对话框
                    // 切换到“问卷管理”页（在桌面端由右侧嵌套 Navigator 承载）
                    handleTabChange(4);
                    
                    showFToast(
                      context: context,
                      alignment: FToastAlignment.bottomRight,
                      title: const Text('创建成功'),
                      description: const Text('问卷已创建，正在跳转到问卷管理页面'),
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
                  } catch (e) {
                    if (!context.mounted) return;
                    
                    showFToast(
                      context: context,
                      alignment: FToastAlignment.bottomRight,
                      title: const Text('创建失败'),
                      description: Text('创建问卷失败: $e'),
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
                  }
                },
                child: const Text('创建'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showStatisticsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => FDialog(
        title: const Text('数据统计'),
        body: const Text('数据统计功能开发中...'),
        actions: [
          FButton(
            child: const Text('关闭'),
            onPress: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  void _showLogoutConfirmDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false, // 禁止点击遮罩关闭
      builder: (context) {
        bool isLoading = false;
        return StatefulBuilder(
          builder: (context, setState) => PopScope(
            canPop: !isLoading, // 加载中阻止返回
            child: FDialog(
              direction: Axis.horizontal,
              title: const Text('确认退出'),
              body: isLoading
                  ? const Row(
                      children: [
                        SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                        SizedBox(width: 8),
                        Text('正在退出登录...'),
                      ],
                    )
                  : const Text('确定要退出当前账号吗？'),
              actions: [
                FButton(
                  style: FButtonStyle.outline,
                  intrinsicWidth: true,
                  onPress: isLoading ? null : () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                FButton(
                  intrinsicWidth: true,
                  onPress: isLoading
                      ? null
                      : () async {
                          setState(() => isLoading = true);
                          try {
                            await widget.apiService?.logoutStrict();
                            if (context.mounted) {
                              Navigator.pop(context);
                            }
                            widget.onLogout();
                          } catch (e) {
                            if (context.mounted) {
                              showFToast(
                                context: context,
                                title: const Text('退出失败'),
                                description: Text(e.toString()),
                              );
                            }
                          } finally {
                            if (context.mounted) setState(() => isLoading = false);
                          }
                        },
                  child: const Text('确认'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
