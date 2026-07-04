import 'package:flutter/foundation.dart';
import '../models/user.dart';

class UserInfoProvider extends ChangeNotifier {
  User? _user;
  bool _isLoading = false;
  String? _loadError;

  User? get user => _user;
  bool get isLoggedIn => _user != null;
  bool get isLoading => _isLoading;
  String? get loadError => _loadError;

  void setUser(User? user) {
    _user = user;
    _loadError = null;
    notifyListeners();
  }

  void updateUser(User Function(User old) updater) {
    if (_user != null) {
      _user = updater(_user!);
      notifyListeners();
    }
  }

  void setLoading(bool value) {
    if (_isLoading == value) return;
    _isLoading = value;
    notifyListeners();
  }

  void setLoadError(String? error) {
    _loadError = error;
    notifyListeners();
  }

  void clear() {
    _user = null;
    _loadError = null;
    _isLoading = false;
    notifyListeners();
  }
}
