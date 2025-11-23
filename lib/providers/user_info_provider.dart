import 'package:flutter/foundation.dart';
import '../models/user.dart';

class UserInfoProvider extends ChangeNotifier {
  User? _user;

  User? get user => _user;
  bool get isLoggedIn => _user != null;

  void setUser(User? user) {
    _user = user;
    notifyListeners();
  }

  void updateUser(User Function(User old) updater) {
    if (_user != null) {
      _user = updater(_user!);
      notifyListeners();
    }
  }

  void clear() {
    _user = null;
    notifyListeners();
  }
}
