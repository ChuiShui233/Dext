import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import '../models/survey.dart';
import '../models/question.dart';

class SurveyPreviewPage extends StatelessWidget {
  final Survey survey;
  final String token;
  final List<Question> questions;

  const SurveyPreviewPage({
    super.key,
    required this.survey,
    required this.token,
    required this.questions,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const SizedBox(height: 40),
          FHeader.nested(
            title: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('问卷预览 - ${survey.surveyName}'),
              ],
            ),
            prefixes: [
              FHeaderAction(
                icon: const Icon(Icons.close, size: 20),
                onPress: () => Navigator.pop(context),
              ),
            ],
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          survey.surveyName,
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(survey.description),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                ...questions.map((q) => Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              q.title,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                            ),
                            if (q.required)
                              const Text(' *', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _buildPreviewWidget(q),
                      ],
                    ),
                  ),
                )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewWidget(Question q) {
    switch (q.type) {
      case QuestionType.singleChoice:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: q.options.map((opt) => Row(
            children: [
              Radio(value: false, groupValue: true, onChanged: null),
              Text(opt.text),
            ],
          )).toList(),
        );
      case QuestionType.multipleChoice:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: q.options.map((opt) => Row(
            children: [
              Checkbox(value: false, onChanged: null),
              Text(opt.text),
            ],
          )).toList(),
        );
      case QuestionType.slider:
        double min = 0, max = 100, initial = 50;
        String minLabel = '最小值', maxLabel = '最大值';
        if (q.options.length >= 5) {
          min = double.tryParse(q.options[0].text) ?? 0;
          max = double.tryParse(q.options[1].text) ?? 100;
          initial = double.tryParse(q.options[2].text) ?? 50;
          minLabel = q.options[3].text;
          maxLabel = q.options[4].text;
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Slider(
              value: initial,
              min: min,
              max: max,
              onChanged: null,
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(minLabel),
                Text(maxLabel),
              ],
            ),
          ],
        );
      case QuestionType.matrix:
        return const Text('矩阵题暂不支持预览');
      }
  }
} 