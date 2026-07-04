import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import '../widgets/top_safe_spacer.dart';

class DebugTestPage extends StatelessWidget {
  const DebugTestPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const TopSafeSpacer(),
          FHeader.nested(
            title: const Text('Debug Test Page'),
            prefixes: [
              FHeaderAction(
                icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                onPress: () => Navigator.pop(context),
              ),
            ],
          ),
          Expanded(
            child: Center(
              child: const Text('Debug Test Page'),
            ),
          ),
        ],
      ),
    );
  }
}