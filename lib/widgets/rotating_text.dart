import 'package:flutter/material.dart';

class RotatingText extends StatefulWidget {
  final List<String> texts;
  final Duration rotationInterval;
  final Duration staggerDuration;
  final String staggerFrom;
  final Map<String, dynamic> initial;
  final Map<String, dynamic> animate;
  final Map<String, dynamic> exit;
  final bool auto;
  final bool loop;
  final String splitBy;
  final MainAxisAlignment alignment;
  final TextStyle? textStyle;
  final EdgeInsets? padding;

  const RotatingText({
    super.key,
    required this.texts,
    this.rotationInterval = const Duration(milliseconds: 2000),
    this.staggerDuration = const Duration(milliseconds: 25),
    this.staggerFrom = 'first',
    this.initial = const {'y': 1.0, 'opacity': 0.0},
    this.animate = const {'y': 0.0, 'opacity': 1.0},
    this.exit = const {'y': -1.2, 'opacity': 0.0},
    this.auto = true,
    this.loop = true,
    this.splitBy = 'characters',
    this.alignment = MainAxisAlignment.center,
    this.textStyle,
    this.padding,
  });

  @override
  State<RotatingText> createState() => _RotatingTextState();
}

class _RotatingTextState extends State<RotatingText>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  int _currentIndex = 0;
  late List<String> _currentElements;
  late List<String> _previousElements;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _currentElements = _splitText(widget.texts[_currentIndex]);
    _previousElements = [];

    if (widget.auto) _startRotation();
  }

  void _startRotation() {
    Future.delayed(widget.rotationInterval, () {
      if (!mounted) return;

      setState(() {
        _previousElements = _currentElements;
        _currentIndex = (_currentIndex + 1) % widget.texts.length;
        _currentElements = _splitText(widget.texts[_currentIndex]);
      });

      _controller.forward(from: 0.0);

      if (widget.loop || _currentIndex != widget.texts.length - 1) {
        _startRotation();
      }
    });
  }

  List<String> _splitText(String text) {
    if (widget.splitBy == 'characters') return text.split('');
    if (widget.splitBy == 'words') return text.split(' ');
    if (widget.splitBy == 'lines') return text.split('\n');
    return [text];
  }

  Duration _calculateDelay(int index, int total) {
    if (widget.staggerFrom == 'first') {
      return Duration(milliseconds: index * widget.staggerDuration.inMilliseconds);
    } else if (widget.staggerFrom == 'last') {
      return Duration(milliseconds: (total - 1 - index) * widget.staggerDuration.inMilliseconds);
    } else if (widget.staggerFrom == 'center') {
      final center = total ~/ 2;
      return Duration(milliseconds: (center - index).abs() * widget.staggerDuration.inMilliseconds);
    } else if (widget.staggerFrom == 'random') {
      final randomIndex = DateTime.now().microsecond % total;
      return Duration(milliseconds: (randomIndex - index).abs() * widget.staggerDuration.inMilliseconds);
    }
    return Duration.zero;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textStyle = widget.textStyle ?? Theme.of(context).textTheme.bodyLarge;
    final currentText = _currentElements.join('');

    final boxWidth = _AnimatedBox.calculateWidth(currentText, textStyle);
    final boxHeight = _AnimatedBox.calculateHeight(currentText, textStyle);

    return Container(
      padding: widget.padding,
      child: Stack(
        alignment: Alignment.center,
        children: [
          _AnimatedBox(
            text: currentText,
            textStyle: textStyle,
          ),

          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              width: boxWidth,
              height: boxHeight,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Row(
                    mainAxisAlignment: widget.alignment,
                    children: List.generate(_previousElements.length, (i) {
                      final delay = _calculateDelay(i, _previousElements.length);
                      return AnimatedTextElement(
                        text: _previousElements[i],
                        initial: widget.animate,
                        animate: widget.exit,
                        delay: delay,
                        controller: _controller,
                        textStyle: textStyle,
                      );
                    }),
                  ),

                  Row(
                    mainAxisAlignment: widget.alignment,
                    children: List.generate(_currentElements.length, (i) {
                      final delay = _calculateDelay(i, _currentElements.length);
                      return AnimatedTextElement(
                        text: _currentElements[i],
                        initial: widget.initial,
                        animate: widget.animate,
                        delay: delay,
                        controller: _controller,
                        textStyle: textStyle,
                      );
                    }),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AnimatedTextElement extends StatefulWidget {
  final String text;
  final Map<String, dynamic> initial;
  final Map<String, dynamic> animate;
  final Duration delay;
  final AnimationController controller;
  final TextStyle? textStyle;

  const AnimatedTextElement({
    super.key,
    required this.text,
    required this.initial,
    required this.animate,
    required this.delay,
    required this.controller,
    this.textStyle,
  });

  @override
  State<AnimatedTextElement> createState() => _AnimatedTextElementState();
}

class _AnimatedTextElementState extends State<AnimatedTextElement> {
  late Animation<double> _yAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    final start = widget.delay.inMilliseconds /
        (widget.controller.duration?.inMilliseconds ?? 1);

    _yAnimation = Tween<double>(
      begin: widget.initial['y'] ?? 0.0,
      end: widget.animate['y'] ?? 0.0,
    ).animate(
      CurvedAnimation(
        parent: widget.controller,
        curve: Interval(start, 1.0, curve: Curves.easeOutCubic),
      ),
    );

    _opacityAnimation = Tween<double>(
      begin: widget.initial['opacity'] ?? 0.0,
      end: widget.animate['opacity'] ?? 1.0,
    ).animate(
      CurvedAnimation(
        parent: widget.controller,
        curve: Interval(start, 1.0, curve: Curves.easeOutCubic),
      ),
    );

    widget.controller.forward();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _yAnimation.value * 20),
          child: Opacity(
            opacity: _opacityAnimation.value.clamp(0.0, 1.0),
            child: Text(
              widget.text,
              style: widget.textStyle ?? Theme.of(context).textTheme.bodyLarge,
            ),
          ),
        );
      },
    );
  }
}

class _AnimatedBox extends StatefulWidget {
  final String text;
  final TextStyle? textStyle;

  const _AnimatedBox({required this.text, this.textStyle});

  @override
  State<_AnimatedBox> createState() => _AnimatedBoxState();

  static double calculateWidth(String text, TextStyle? style) {
    final span = TextSpan(text: text, style: style);
    final tp = TextPainter(text: span, textDirection: TextDirection.ltr)..layout();
    return tp.width + 24;
  }

  static double calculateHeight(String text, TextStyle? style) {
    final span = TextSpan(text: text, style: style);
    final tp = TextPainter(text: span, textDirection: TextDirection.ltr)..layout();
    return tp.height + 12;
  }
}

class _AnimatedBoxState extends State<_AnimatedBox> {
  double _width = 0;

  @override
  void didUpdateWidget(covariant _AnimatedBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateWidth();
  }

  @override
  void initState() {
    super.initState();
    _updateWidth();
  }

  void _updateWidth() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final span = TextSpan(text: widget.text, style: widget.textStyle);
      final tp = TextPainter(text: span, textDirection: TextDirection.ltr)..layout();
      final targetWidth = tp.width + 24;

      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) {
          setState(() {
            _width = targetWidth;
          });
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final span = TextSpan(text: widget.text, style: widget.textStyle);
    final tp = TextPainter(text: span, textDirection: TextDirection.ltr)..layout();
    final height = tp.height + 12;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      width: _width,
      height: height,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Colors.deepPurple, Colors.purpleAccent],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
    );
  }
}
