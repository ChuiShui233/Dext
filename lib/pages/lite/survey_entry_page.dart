import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:dext/components/glass_card.dart';
import 'package:dext/components/loading_indicator.dart';
import 'package:dext/widgets/frosted_glass_background.dart';
import 'package:dext/widgets/survey_preview_card.dart';
import '../public_survey_page.dart';
import '../../services/lite_token_storage.dart';
import '../../services/settings_service.dart';

class SurveyEntryPage extends StatefulWidget {
  final String? initialSurveyId;
  final VoidCallback onLogout;
  final VoidCallback onToggleTheme;

  final SurveyPreview? surveyPreview;

  const SurveyEntryPage({
    super.key,
    this.initialSurveyId,
    required this.onLogout,
    required this.onToggleTheme,
    this.surveyPreview,
  });

  @override
  State<SurveyEntryPage> createState() => _SurveyEntryPageState();
}

class _SurveyEntryPageState extends State<SurveyEntryPage> {
  late final TextEditingController _idController;
  bool _busy = false;
  late String _questionnaireLayout;

  @override
  void initState() {
    super.initState();
    _idController = TextEditingController();
    if (widget.initialSurveyId != null && widget.initialSurveyId!.isNotEmpty) {
      _idController.text = widget.initialSurveyId!;
    }
    _idController.addListener(_onInputChanged);
    _questionnaireLayout = SettingsService().questionnaireLayout;
  }

  @override
  void dispose() {
    _idController.removeListener(_onInputChanged);
    _idController.dispose();
    super.dispose();
  }

  void _onInputChanged() {
    if (mounted) setState(() {});
  }

  bool get _canEnter {
    final uid = _resolveSurveyUid(_idController.text);
    return uid != null && uid.isNotEmpty;
  }
  String? _resolveSurveyUid(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    if (!text.contains('?') && !text.contains('/')) return text;
    try {
      final uri = Uri.parse(text);
      final id = uri.queryParameters['id'];
      if (id != null && id.isNotEmpty) return id;
    } catch (_) {}
    return text;
  }

  bool _isObviouslyFake(String text) {
    if (text.isEmpty) return false;
    return RegExp(r'^[0-9]+$').hasMatch(text) ||
        RegExp(r'^[A-Za-z]+$').hasMatch(text);
  }

  Future<void> _enterSurvey() async {
    if (_busy) return;
    final raw = _idController.text.trim();
    if (raw.isEmpty) {
      _showToast('请输入问卷 ID 或链接');
      return;
    }
    if (_isObviouslyFake(raw)) {
      await _showFakeIdDialog();
      return;
    }
    final uid = _resolveSurveyUid(raw);
    setState(() => _busy = true);
    try {
      final valid = await LiteTokenStorage.instance.isValid();
      if (!valid) {
        widget.onLogout();
        return;
      }
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PublicSurveyPage(surveyUID: uid!),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _handleLogout() async {
    if (_busy) return;
    final ok = await _confirmLogout();
    if (ok != true) return;
    await LiteTokenStorage.instance.clear();
    if (!mounted) return;
    widget.onLogout();
  }

  Future<bool?> _confirmLogout() {
    return showFDialog<bool>(
      context: context,
      builder: (ctx, style, animation) => FDialog(
        style: style.call,
        direction: Axis.horizontal,
        title: const Text('确认登出'),
        body: const Text('登出后需要重新登录才能填写问卷。'),
        actions: [
          FButton(
            style: ctx.theme.buttonStyles.outline.call,
            onPress: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FButton(
            style: ctx.theme.buttonStyles.destructive.call,
            onPress: () => Navigator.of(ctx).pop(true),
            child: const Text('登出'),
          ),
        ],
      ),
    );
  }

  void _showToast(String message) {
    showFToast(
      context: context,
      title: Text(message),
    );
  }

  Future<void> _showFakeIdDialog() {
    return showFDialog<void>(
      context: context,
      builder: (ctx, style, animation) => FDialog(
        style: style.call,
        title: const Text('瞎几把乱编的？兄弟'),
        body: const Text('你输入的看起来不像正经的问卷 ID 或链接，检查一下再来。'),
        actions: [
          FButton(
            onPress: () => Navigator.of(ctx).pop(),
            child: const Text('好'),
          ),
        ],
      ),
    );
  }

  Future<void> _setQuestionnaireLayout(String value) async {
    if (_busy) return;
    if (value == _questionnaireLayout) return;
    setState(() => _questionnaireLayout = value);
    await SettingsService().setQuestionnaireLayout(value);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isDesktop = MediaQuery.of(context).size.width > 600;
    final statusBarHeight = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          const FrostedGlassBackground(
            count: 8,
            blurSigma: 120,
            blobOpacity: 0.28,
            animated: true,
            vignette: true,
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final maxCardWidth =
                    constraints.maxWidth > 600.0 ? 480.0 : constraints.maxWidth - 32.0;
                return Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: maxCardWidth),
                      child: GlassCard(
                        borderRadius: 20,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildHeader(isDark),
                              const SizedBox(height: 20),
                              if (widget.surveyPreview != null) ...[
                                SurveyPreviewCard(preview: widget.surveyPreview!),
                                const SizedBox(height: 16),
                              ],
                              _buildInstruction(isDark),
                              const SizedBox(height: 16),
                              FTextField(
                                controller: _idController,
                                label: const Text('问卷 ID 或链接'),
                                hint: '在此输入问卷id',
                                onSubmit: (_) => _enterSurvey(),
                              ),
                              const SizedBox(height: 20),
                              FButton(
                                onPress: (!_canEnter || _busy) ? null : _enterSurvey,
                                child: _busy
                                    ? Row(
                                        mainAxisSize: MainAxisSize.min,
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          LoadingIndicator.button(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onPrimary,
                                          ),
                                          const SizedBox(width: 8),
                                          const Text('加载中'),
                                        ],
                                      )
                                    : const Text('进入问卷'),
                              ),
                              const SizedBox(height: 24),
                              const Divider(height: 1),
                              const SizedBox(height: 12),
                              _buildQuestionnaireLayoutSwitcher(isDark),
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: _busy ? null : _handleLogout,
                                  child: const Text('登出'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Positioned(
            top: isDesktop ? 24 : statusBarHeight + 12,
            right: 16,
            child: FButton.icon(
              onPress: widget.onToggleTheme,
              child: Icon(
                isDark ? FIcons.sun : FIcons.moon,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionnaireLayoutSwitcher(bool isDark) {
    final isWizard = _questionnaireLayout == SettingsService.layoutWizard;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8, left: 2),
          child: Text(
            '问卷样式',
            style: TextStyle(
              fontSize: 12,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.6)
                  : Colors.black.withValues(alpha: 0.55),
              fontFamily: 'PingFangSuper',
            ),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: FButton(
                style: isWizard
                    ? context.theme.buttonStyles.primary.call
                    : context.theme.buttonStyles.outline.call,
                onPress: _busy
                    ? null
                    : () => _setQuestionnaireLayout(SettingsService.layoutWizard),
                child: const Text('分步'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FButton(
                style: isWizard
                    ? context.theme.buttonStyles.outline.call
                    : context.theme.buttonStyles.primary.call,
                onPress: _busy
                    ? null
                    : () => _setQuestionnaireLayout(SettingsService.layoutContinuous),
                child: const Text('连续'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildHeader(bool isDark) {
    return Column(
      children: [
        Text(
          'DEXT 问卷',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            fontFamily: 'PingFangSuper',
            color: isDark ? Colors.white : const Color(0xFF18181B),
          ),
        ),
      ],
    );
  }

  Widget _buildInstruction(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '请输入问卷发布方提供的 ID 或包含 ?id= 参数的链接，然后点击「进入问卷」开始填写。',
        style: TextStyle(
          fontSize: 13,
          height: 1.5,
          color: isDark
              ? Colors.white.withValues(alpha: 0.75)
              : Colors.black.withValues(alpha: 0.65),
          fontFamily: 'PingFangSuper',
        ),
      ),
    );
  }
}
