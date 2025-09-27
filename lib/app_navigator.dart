import 'package:flutter/widgets.dart';

// 全局 Navigator Key，供需要在 Navigator 子树外部弹窗/跳转的组件使用
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();
