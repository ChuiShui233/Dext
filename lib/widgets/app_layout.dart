import 'package:flutter/material.dart';
import '../pages/frame_page.dart';
import '../services/api_service.dart';

// 这是一个代理类，将功能转移到了FramePage
class AppLayout extends StatelessWidget {
  final int selectedIndex;
  final Function(int) onIndexChanged;
  final VoidCallback onLogout;
  final Function(ThemeMode) onThemeModeChange;
  final ApiService? apiService;
  final PageStorageBucket bucket;

  const AppLayout({
    super.key,
    required this.selectedIndex,
    required this.onIndexChanged,
    required this.onLogout,
    required this.onThemeModeChange,
    this.apiService,
    required this.bucket,
  });

  @override
  Widget build(BuildContext context) {
    return FramePage(
      selectedIndex: selectedIndex,
      onIndexChanged: onIndexChanged,
      onLogout: onLogout,
      onThemeModeChange: onThemeModeChange,
      apiService: apiService,
      bucket: bucket,
    );
  }
} 