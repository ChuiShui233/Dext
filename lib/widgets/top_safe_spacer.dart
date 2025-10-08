import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import '../main.dart' show isDesktop;

class TopSafeSpacer extends StatelessWidget {
  final double desktop;
  final double web;
  final double mobile;

  const TopSafeSpacer({
    super.key,
    this.desktop = 40,
    this.web = 20,
    this.mobile = 0,
  });

  @override
  Widget build(BuildContext context) {
    final double height = isDesktop ? desktop : (kIsWeb ? web : mobile);
    return SizedBox(height: height);
  }
}
