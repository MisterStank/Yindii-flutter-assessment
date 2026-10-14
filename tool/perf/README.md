# Scroll / rebuild probe

`measure.dart` talks to a running app's VM service (the protocol DevTools
uses), records the timeline while `adb` scrolls the home feed, and prints:

- UI-thread frame times (`Animator::BeginFrame`) and `BUILD` phase times
- per-widget build counts (`ext.flutter.profileWidgetBuilds`, the same switch
  as DevTools' "Track widget builds")
- `dumpsys meminfo` before/after

```bash
flutter build apk --profile && adb install -r build/app/outputs/flutter-apk/app-profile.apk
# launch the app, read the VM service URL from `adb logcat | grep "listening on"`
adb forward tcp:<port> tcp:<port>
dart tool/perf/measure.dart http://127.0.0.1:<port>/<token>/ <label> <swipes> frames|builds
```

`frames` mode records frame timings only; `builds` mode adds widget-build
profiling, which floods the timeline buffer, so use it with 1 swipe (or 0
swipes for a 5 s idle window). The adb path at the top is machine specific.
