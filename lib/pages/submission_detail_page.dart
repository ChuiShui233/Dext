import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shimmer/shimmer.dart';
import '../components/glass_card.dart';
import '../widgets/question_display_widget.dart';
import '../models/question.dart';
import '../services/api_service.dart';
import '../main.dart' show isDesktop;
import 'fullscreen_media_viewer.dart';
import '../widgets/frosted_glass_background.dart';

class SubmissionDetailPage extends StatefulWidget {
  final ApiService apiService;
  final int answerId;
  final int? surveyId;
  const SubmissionDetailPage({super.key, required this.apiService, required this.answerId, this.surveyId});

  @override
  State<SubmissionDetailPage> createState() => _SubmissionDetailPageState();
}

class _SubmissionDetailPageState extends State<SubmissionDetailPage> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _data;
  final Map<String, bool> _optionStates = {};
  bool _isLoadingAnswers = false;

  @override
  void initState() {
    super.initState();
    _loadCached();
    _load();
  }

  String _templateCacheKey(int surveyId) => 'survey_template_$surveyId';
  String _answerCacheKey() => 'submission_answer_${widget.answerId}';

  Future<void> _loadCached() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      final fullCached = prefs.getString('submission_detail_${widget.answerId}');
      if (fullCached != null) {
        final d = json.decode(fullCached) as Map<String, dynamic>;
        _applyDataToState(d);
        
        final surveyId = (d['surveyId'] as num?)?.toInt();
        if (surveyId != null) {
          final templateData = {
            'surveyId': surveyId,
            'surveyName': d['surveyName'],
            'creator': d['creator'],
            'questions': d['questions'],
          };
          final answerData = {
            'surveyId': surveyId,
            'myAnswers': d['myAnswers'],
            'myAnswerIndices': d['myAnswerIndices'],
          };
          await prefs.setString(_templateCacheKey(surveyId), json.encode(templateData));
          await prefs.setString(_answerCacheKey(), json.encode(answerData));
        }
        return;
      }
      
      int? surveyId = widget.surveyId;
      Map<String, dynamic>? answerData;
      
      final answerCached = prefs.getString(_answerCacheKey());
      if (answerCached != null) {
        answerData = json.decode(answerCached) as Map<String, dynamic>;
        surveyId ??= (answerData['surveyId'] as num?)?.toInt();
      }
      
      if (surveyId != null) {
        final templateCached = prefs.getString(_templateCacheKey(surveyId));
        if (templateCached != null) {
            final templateData = json.decode(templateCached) as Map<String, dynamic>;
            
            if (mounted) {
              setState(() {
                _data = {
                  ...templateData,
                  'myAnswers': <String, dynamic>{},
                  'myAnswerIndices': <String, dynamic>{},
                };
                _loading = false;
                _isLoadingAnswers = true;
                _error = null;
              });
            }
            
            if (answerData != null) {
              Future.delayed(const Duration(milliseconds: 100), () {
                if (!mounted) return;
                
                final myAnswers = (answerData!['myAnswers'] as Map?)?.map((k, v) => 
                MapEntry(int.parse(k.toString()), (v as List).cast<String>())) ?? <int, List<String>>{};
              final myAnswerIndices = (answerData['myAnswerIndices'] as Map?)?.map((k, v) => 
                MapEntry(int.parse(k.toString()), (v as List).map((e) => (e as num).toInt()).toList())) ?? <int, List<int>>{};
              
              final questions = (templateData['questions'] as List?)?.cast<Map<String, dynamic>>() ?? [];
              
              for (final q in questions) {
                final qid = (q['id'] ?? 0) as int;
                final opts = (q['options'] as List?)?.cast<Map<String, dynamic>>() ?? [];
                
                if (myAnswerIndices.containsKey(qid)) {
                  final idxList = myAnswerIndices[qid]!;
                  for (int i = 0; i < opts.length; i++) {
                    _optionStates[_getOptionKey(qid, i)] = idxList.contains(i);
                  }
                  continue;
                }
                
                final mine = List<String>.from(myAnswers[qid] ?? const <String>[]);
                final Map<String, int> counts = {};
                for (final t in mine) {
                  counts[t] = (counts[t] ?? 0) + 1;
                }
                for (int i = 0; i < opts.length; i++) {
                  final text = (opts[i]['text'] ?? '') as String;
                  final key = _getOptionKey(qid, i);
                  final c = counts[text] ?? 0;
                  if (c > 0) {
                    _optionStates[key] = true;
                    counts[text] = c - 1;
                  } else {
                    _optionStates[key] = false;
                  }
                }
              }
              
                setState(() {
                  _data = {
                    ...templateData,
                    'myAnswers': answerData!['myAnswers'],
                    'myAnswerIndices': answerData!['myAnswerIndices'],
                  };
                  _isLoadingAnswers = false;
                });
              });
            }
            return;
        }
      }
    } catch (e) {}
  }
  
  void _applyDataToState(Map<String, dynamic> d) {
    _isLoadingAnswers = false;
    final questions = (d['questions'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final myAnswers = (d['myAnswers'] as Map?)?.map((k, v) => MapEntry(int.parse(k.toString()), (v as List).cast<String>())) ?? <int, List<String>>{};
    final myAnswerIndices = (d['myAnswerIndices'] as Map?)?.map((k, v) => MapEntry(int.parse(k.toString()), (v as List).map((e) => (e as num).toInt()).toList())) ?? <int, List<int>>{};

    _optionStates.clear();
    for (final q in questions) {
      final qid = (q['id'] ?? 0) as int;
      final opts = (q['options'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      if (myAnswerIndices.containsKey(qid)) {
        final idxList = myAnswerIndices[qid]!;
        for (int i = 0; i < opts.length; i++) {
          _optionStates[_getOptionKey(qid, i)] = idxList.contains(i);
        }
        continue;
      }
      final mine = List<String>.from(myAnswers[qid] ?? const <String>[]);
      final Map<String, int> counts = {};
      for (final t in mine) {
        counts[t] = (counts[t] ?? 0) + 1;
      }
      for (int i = 0; i < opts.length; i++) {
        final text = (opts[i]['text'] ?? '') as String;
        final key = _getOptionKey(qid, i);
        final c = counts[text] ?? 0;
        if (c > 0) {
          _optionStates[key] = true;
          counts[text] = c - 1;
        } else {
          _optionStates[key] = false;
        }
      }
    }

    if (mounted) {
      setState(() {
        _data = d;
        _loading = false;
        _error = null;
      });
    }
  }

  Future<void> _load() async {
    Timer? loadingTimer = Timer(const Duration (milliseconds: 150), () {
      if (mounted && _loading) {
        setState(() { _loading = true; _error = null; });
      }
    });
    try {
      final d = await widget.apiService.getSubmissionDetail(widget.answerId);
      final questions = (d['questions'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final myAnswers = (d['myAnswers'] as Map?)?.map((k, v) => MapEntry(int.parse(k.toString()), (v as List).cast<String>())) ?? <int, List<String>>{};
      final myAnswerIndices = (d['myAnswerIndices'] as Map?)?.map((k, v) => MapEntry(int.parse(k.toString()), (v as List).map((e) => (e as num).toInt()).toList())) ?? <int, List<int>>{};

      _optionStates.clear();
      for (final q in questions) {
        final qid = (q['id'] ?? 0) as int;
        final opts = (q['options'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        if (myAnswerIndices.containsKey(qid)) {
          final idxList = myAnswerIndices[qid]!;
          for (int i = 0; i < opts.length; i++) {
            _optionStates[_getOptionKey(qid, i)] = idxList.contains(i);
          }
          continue;
        }
        final mine = List<String>.from(myAnswers[qid] ?? const <String>[]);
        final Map<String, int> counts = {};
        for (final t in mine) {
          counts[t] = (counts[t] ?? 0) + 1;
        }
        for (int i = 0; i < opts.length; i++) {
          final text = (opts[i]['text'] ?? '') as String;
          final key = _getOptionKey(qid, i);
          final c = counts[text] ?? 0;
          if (c > 0) {
            _optionStates[key] = true;
            counts[text] = c - 1;
          } else {
            _optionStates[key] = false;
          }
        }
      }
      loadingTimer.cancel();
      if (!mounted) return;
      setState(() { 
        _data = d; 
        _loading = false;
        _isLoadingAnswers = false;
      });
      try {
        final prefs = await SharedPreferences.getInstance();
        final surveyId = (d['surveyId'] as num?)?.toInt();
        
        if (surveyId != null) {
          final templateData = {
            'surveyId': surveyId,
            'surveyName': d['surveyName'],
            'creator': d['creator'],
            'questions': d['questions'],
          };
          await prefs.setString(_templateCacheKey(surveyId), json.encode(templateData));
          
          final answerData = {
            'surveyId': surveyId,
            'myAnswers': d['myAnswers'],
            'myAnswerIndices': d['myAnswerIndices'],
          };
          await prefs.setString(_answerCacheKey(), json.encode(answerData));
        }
        
        await prefs.setString('submission_detail_${widget.answerId}', json.encode(d));
      } catch (_) {}
    } catch (e) {
      loadingTimer.cancel();
      if (mounted) {
        setState(() { _loading = false; _error = '加载失败: $e'; });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const FrostedGlassBackground(),
          Column(
            children: [
              SizedBox(height: isDesktop ? 38 : 24),
              FHeader.nested(
                title: Text('提交详情'),
                prefixes: [
                  FHeaderAction(
                    icon: const Icon(Icons.chevron_left, size: 32),
                    onPress: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              Expanded(
                child: _data == null
                    ? (_error != null
                        ? _buildError(_error!)
                        : (_loading 
                            ? const Center(child: CircularProgressIndicator())
                            : const SizedBox.shrink()))
                    : _buildContent(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildError(String err) {
    return Center(
      child: _glass(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.redAccent, size: 40),
              const SizedBox(height: 12),
              Text(err, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FButton(onPress: _load, child: const Text('重试')),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_data == null) return const SizedBox.shrink();
    
    final questions = (_data!['questions'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final myAnswers = (_data!['myAnswers'] as Map?)?.map((k, v) => MapEntry(int.parse(k.toString()), (v as List).cast<String>())) ?? <int, List<String>>{};
    final surveyName = (_data!['surveyName'] ?? '') as String;
    final creator = (_data!['creator'] ?? '') as String;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _glass(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(surveyName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 12,
                  children: [
                    _kv('创建人', creator),
                    _kv('答卷ID', widget.answerId.toString()),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        ...questions.map((q) => _buildQuestionCard(q, myAnswers[q['id'] as int] ?? const <String>[])),
      ],
    );
  }

  Widget _buildQuestionCard(Map<String, dynamic> q, List<String> my) {
    final question = _mapToQuestion(q);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    Widget content = Padding(
      padding: const EdgeInsets.all(14),
      child: QuestionDisplayWidget(
        question: question,
        mode: QuestionDisplayMode.readonly,
        optionStates: _optionStates,
        selectedAnswers: my,
        onMediaOpen: (url, all, index) => _openFullscreenViewer(url, all, index),
      ),
    );
    
    Widget card = _glass(child: content);
    
    if (_isLoadingAnswers) {
      card = Shimmer.fromColors(
        baseColor: isDark 
          ? Colors.white.withValues(alpha: 0.1)
          : Colors.grey.withValues(alpha: 0.3),
        highlightColor: isDark
          ? Colors.white.withValues(alpha: 0.2)
          : Colors.grey.withValues(alpha: 0.1),
        period: const Duration(milliseconds: 1200),
        child: card,
      );
    }
    
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (Widget child, Animation<double> animation) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.3, 0.0),
            end: Offset.zero,
          ).animate(CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          )),
          child: FadeTransition(
            opacity: animation,
            child: child,
          ),
        );
      },
      child: Container(
        key: ValueKey<bool>(_isLoadingAnswers),
        child: card,
      ),
    );
  }

  Question _mapToQuestion(Map<String, dynamic> q) {
    final options = (q['options'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final mediaUrls = (q['mediaUrls'] as List?)?.cast<String>() ?? const <String>[];
    final int qType = (q['questionType'] ?? 1) as int;

    List<QuestionOption> questionOptions = [];
    try {
      questionOptions = options.asMap().entries.map((entry) => QuestionOption(
        id: entry.key,
        text: (entry.value['text'] ?? '') as String,
        mediaUrl: (entry.value['mediaUrl'] ?? '') as String,
      )).toList();
    } catch (e) {}


    QuestionType questionType;
    switch (qType) {
      case 1:
        questionType = QuestionType.singleChoice;
        break;
      case 2:
        questionType = QuestionType.multipleChoice;
        break;
      case 3:
        questionType = QuestionType.slider;
        break;
      case 4:
        questionType = QuestionType.matrix;
        break;
      default:
        questionType = QuestionType.singleChoice;
    }

    return Question(
      id: (q['id'] ?? 0) as int,
      title: (q['title'] ?? '') as String,
      type: questionType,
      options: questionOptions,
      required: (q['required'] ?? false) as bool,
      order: (q['order'] ?? 0) as int,
      mediaUrls: mediaUrls,
    );
  }



  Widget _glass({required Widget child}) => GlassCard(child: child);


  void _openFullscreenViewer(String mediaUrl, List<String> allMediaUrls, int currentIndex) {
    Navigator.push(
      context,
      PageRouteBuilder(
        opaque: false, // 允许下层页面透出
        barrierColor: Colors.transparent,
        transitionDuration: const Duration(milliseconds: 150),
        reverseTransitionDuration: const Duration(milliseconds: 150),
        pageBuilder: (context, animation, secondaryAnimation) => FullscreenMediaViewer(
          mediaUrl: mediaUrl,
          title: '问卷媒体',
          allMediaUrls: allMediaUrls,
          currentIndex: currentIndex,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: child,
          );
        },
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$k: ', style: const TextStyle(fontWeight: FontWeight.w600)),
        Text(v),
      ],
    );
  }

  String _getOptionKey(int questionId, int optionIndex) {
    return 'q${questionId}_opt$optionIndex';
  }
}
