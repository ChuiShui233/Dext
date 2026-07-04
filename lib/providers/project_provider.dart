import 'package:flutter/foundation.dart';

import '../models/project.dart';
import '../services/api_service.dart';

class ProjectProvider extends ChangeNotifier {
  final ApiService Function() _apiServiceBuilder;

  List<Project>? _projects;
  bool _isLoading = false;
  String? _loadError;
  int _requestEpoch = 0;

  ProjectProvider({ApiService Function()? apiServiceBuilder})
      : _apiServiceBuilder = apiServiceBuilder ?? (() => ApiService());

  List<Project>? get projects => _projects;
  bool get isLoading => _isLoading;
  String? get loadError => _loadError;
  int get count => _projects?.length ?? 0;

  Future<List<Project>> ensureLoaded({bool force = false}) async {
    if (!force && _projects != null) return _projects!;
    if (_isLoading) {
      // 等待当前请求结束
      while (_isLoading) {
        await Future<void>.delayed(const Duration(milliseconds: 80));
      }
      return _projects ?? <Project>[];
    }
    return _load();
  }

  Future<List<Project>> refresh() => _load(force: true);

  Future<List<Project>> _load({bool force = false}) async {
    _isLoading = true;
    _loadError = null;
    notifyListeners();
    final epoch = ++_requestEpoch;
    try {
      final api = _apiServiceBuilder();
      final list = await api.getProjects();
      // 仅接受最后一次请求的结果，避免乱序覆盖
      if (epoch != _requestEpoch) return _projects ?? <Project>[];
      _projects = list;
      return list;
    } catch (e) {
      if (epoch == _requestEpoch) {
        _loadError = e.toString();
      }
      rethrow;
    } finally {
      if (epoch == _requestEpoch) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  void clear() {
    _projects = null;
    _loadError = null;
    _isLoading = false;
    _requestEpoch++;
    notifyListeners();
  }
}
