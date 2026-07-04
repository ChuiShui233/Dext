import 'dart:math' as math;
import 'package:flutter/material.dart';

class AdaptiveMessageCard extends StatelessWidget {

  final Widget child;
  
  final Widget Function(Widget child)? cardWrapper;

  const AdaptiveMessageCard({
    super.key,
    required this.child,
    this.cardWrapper,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final vw = size.width;
    final vh = size.height;
    
    final EdgeInsets adaptivePadding = EdgeInsets.symmetric(
      horizontal: (vw * 0.08).clamp(16.0, 48.0),
      vertical: (vh * 0.04).clamp(12.0, 40.0),
    );
    
    final double maxWidth = math.min(520.0, vw * 0.84);
    
    final contentWidget = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Padding(
        padding: adaptivePadding,
        child: child,
      ),
    );

    final wrappedContent = cardWrapper != null
        ? cardWrapper!(contentWidget)
        : Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: contentWidget,
          );

    return Center(
      child: wrappedContent,
    );
  }
}
