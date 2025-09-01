@echo off
adb devices 
adb connect 127.0.0.1:7555
flutter run -v PHY110
pause