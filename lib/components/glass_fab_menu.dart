import 'package:flutter/material.dart';
import '../components/glass_card.dart';

class GlassFabMenu extends StatefulWidget {
  final EdgeInsets padding;
  final VoidCallback onFillSurvey;
  final VoidCallback onProjectTap;
  final VoidCallback onSurveyTap;

  const GlassFabMenu({
    super.key,
    this.padding = EdgeInsets.zero,
    required this.onFillSurvey,
    required this.onProjectTap,
    required this.onSurveyTap,
  });

  @override
  State<GlassFabMenu> createState() => _GlassFabMenuState();
}

class _GlassFabMenuState extends State<GlassFabMenu> {
  bool _isOpen = false;

  void _toggle() => setState(() => _isOpen = !_isOpen);

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isLargeScreen = screenWidth > 600;

    final double mainButtonSize = isLargeScreen ? 68 : 60;
    final double iconSize = isLargeScreen ? 28 : 24;
    final double itemIconSize = isLargeScreen ? 24 : 22;
    final EdgeInsets itemPadding = EdgeInsets.symmetric(
      horizontal: isLargeScreen ? 14 : 12,
      vertical: isLargeScreen ? 10 : 8,
    );

    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color fabFg = isDark ? Colors.white : const Color(0xFF222222);

    final Color panelBg = isDark
        ? Colors.black.withValues(alpha: 0.50)
        : Colors.black.withValues(alpha: 0.12);
    final Color panelBorder = isDark
        ? Colors.white.withValues(alpha: 0.20)
        : Colors.white.withValues(alpha: 0.24);
    final Color fabBg = isDark
        ? Colors.black.withValues(alpha: 0.55)
        : Colors.black.withValues(alpha: 0.14);
    final Color fabBorder = panelBorder;

    return Padding(
      padding: widget.padding,
      child: Stack(
        alignment: Alignment.bottomRight,
        children: [
          AnimatedSlide(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            offset: _isOpen ? Offset.zero : const Offset(0, 0.05),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 180),
              opacity: _isOpen ? 1 : 0,
              child: IgnorePointer(
                ignoring: !_isOpen,
                child: GlassCard(
                  borderRadius: 14,
                  blurSigma: 18,
                  margin: EdgeInsets.only(bottom: mainButtonSize + 16, right: 0),
                  backgroundColor: panelBg,
                  borderColor: panelBorder,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minWidth: isLargeScreen ? 180 : 168,
                      maxWidth: 180,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _MenuItem(
                            icon: Icons.edit_note_outlined,
                            iconSize: itemIconSize,
                            label: '填写问卷',
                            padding: itemPadding,
                            onTap: () {
                              _toggle();
                              widget.onFillSurvey();
                            },
                          ),
                          const _MenuDivider(),
                          _MenuItem(
                            icon: Icons.folder_outlined,
                            iconSize: itemIconSize,
                            label: '管理项目',
                            padding: itemPadding,
                            onTap: () {
                              _toggle();
                              widget.onProjectTap();
                            },
                          ),
                          const _MenuDivider(),
                          _MenuItem(
                            icon: Icons.notes_outlined,
                            iconSize: itemIconSize,
                            label: '管理问卷',
                            padding: itemPadding,
                            onTap: () {
                              _toggle();
                              widget.onSurveyTap();
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          GestureDetector(
            onTap: _toggle,
            child: GlassCard(
              borderRadius: mainButtonSize / 2,
              blurSigma: 16,
              margin: EdgeInsets.zero,
              backgroundColor: fabBg,
              borderColor: fabBorder,
              child: Container(
                height: mainButtonSize,
                width: mainButtonSize,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(mainButtonSize / 2),
                ),
                child: Center(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, anim) => RotationTransition(
                      turns: Tween<double>(begin: 0.85, end: 1).animate(anim),
                      child: FadeTransition(opacity: anim, child: child),
                    ),
                    child: Icon(
                      _isOpen ? Icons.close : Icons.add,
                      key: ValueKey(_isOpen),
                      size: iconSize,
                      color: fabFg,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final double iconSize;
  final String label;
  final EdgeInsets padding;
  final VoidCallback onTap;

  const _MenuItem({
    required this.icon,
    required this.iconSize,
    required this.label,
    required this.padding,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color hoverCol = Colors.white.withValues(alpha: 0.08);
    final Color splashCol = Colors.white.withValues(alpha: 0.12);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color fg = isDark ? Colors.white : const Color(0xFF222222);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      hoverColor: hoverCol,
      splashColor: splashCol,
      highlightColor: hoverCol,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: padding.horizontal / 2),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(icon, size: iconSize, color: fg),
              const SizedBox(width: 12),
              Text(
                label,
                textAlign: TextAlign.left,
                style: TextStyle(
                  color: fg,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuDivider extends StatelessWidget {
  const _MenuDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Container(
        height: 1,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(1),
        ),
      ),
    );
  }
}
