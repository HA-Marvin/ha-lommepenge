import 'package:flutter/widgets.dart';

import '../providers/app_state.dart';

/// Sits above the app's [Navigator] (in `MaterialApp.builder`), so every tap
/// - also in dialogs and screens opened from parent mode - counts as
/// activity. When [AppState] closes parent mode because of inactivity (family
/// screen only, see [AppState.parentModeTimeout]), all parent screens and
/// dialogs are closed and the start screen is shown again.
///
/// Typing on Android's on-screen keyboard is not seen as a tap, so a parent
/// who only types for the whole period is logged out too.
class ParentModeTimeout extends StatefulWidget {
  final AppState appState;
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  const ParentModeTimeout({
    super.key,
    required this.appState,
    required this.navigatorKey,
    required this.child,
  });

  @override
  State<ParentModeTimeout> createState() => _ParentModeTimeoutState();
}

class _ParentModeTimeoutState extends State<ParentModeTimeout> {
  @override
  void initState() {
    super.initState();
    widget.appState.onParentModeTimedOut = _backToStart;
  }

  @override
  void didUpdateWidget(ParentModeTimeout oldWidget) {
    super.didUpdateWidget(oldWidget);
    widget.appState.onParentModeTimedOut = _backToStart;
  }

  @override
  void dispose() {
    if (widget.appState.onParentModeTimedOut == _backToStart) {
      widget.appState.onParentModeTimedOut = null;
    }
    super.dispose();
  }

  void _backToStart() {
    widget.navigatorKey.currentState?.popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => widget.appState.registerActivity(),
      child: widget.child,
    );
  }
}
