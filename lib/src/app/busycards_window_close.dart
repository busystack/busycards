import 'dart:async';

import 'package:flutter/widgets.dart';

typedef BusyCardsWindowCloseHandler = FutureOr<bool> Function();

/// Coordinates destructive top-level window close requests with the active
/// modal surface that owns any transient editor state.
///
/// Handlers are ordered by presentation: the most recently mounted active
/// surface owns the decision. Concurrent close requests share one resolution
/// so they cannot open duplicate confirmation dialogs.
final class BusyCardsWindowCloseCoordinator {
  final List<_BusyCardsWindowCloseRegistration> _registrations = [];
  Future<bool>? _pendingRequest;

  bool get hasActiveHandler => _registrations.isNotEmpty;

  Future<bool> requestClose() {
    final pending = _pendingRequest;
    if (pending != null) return pending;

    final request = _resolveCloseRequest();
    _pendingRequest = request;
    return request.whenComplete(() {
      if (identical(_pendingRequest, request)) {
        _pendingRequest = null;
      }
    });
  }

  _BusyCardsWindowCloseRegistration _register(
    BusyCardsWindowCloseHandler handler,
  ) {
    final registration = _BusyCardsWindowCloseRegistration(this, handler);
    _registrations.add(registration);
    return registration;
  }

  Future<bool> _resolveCloseRequest() async {
    if (_registrations case [..., final active]) {
      try {
        return await active.handler();
      } on Object catch (error, stackTrace) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'BusyCards window close coordinator',
            context: ErrorDescription(
              'while asking the active surface to resolve a window close',
            ),
          ),
        );
        return false;
      }
    }
    return true;
  }

  void _unregister(_BusyCardsWindowCloseRegistration registration) {
    _registrations.remove(registration);
  }
}

final class _BusyCardsWindowCloseRegistration {
  _BusyCardsWindowCloseRegistration(this._owner, this.handler);

  BusyCardsWindowCloseCoordinator? _owner;
  final BusyCardsWindowCloseHandler handler;

  void dispose() {
    _owner?._unregister(this);
    _owner = null;
  }
}

class BusyCardsWindowCloseScope extends InheritedWidget {
  const BusyCardsWindowCloseScope({
    super.key,
    required this.coordinator,
    required super.child,
  });

  final BusyCardsWindowCloseCoordinator coordinator;

  static BusyCardsWindowCloseCoordinator? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<BusyCardsWindowCloseScope>()
        ?.coordinator;
  }

  @override
  bool updateShouldNotify(BusyCardsWindowCloseScope oldWidget) =>
      !identical(coordinator, oldWidget.coordinator);
}

/// Registers a close decision owned by an editor or modal surface while that
/// surface is mounted beneath [BusyCardsWindowCloseScope].
class BusyCardsWindowCloseGuard extends StatefulWidget {
  const BusyCardsWindowCloseGuard({
    super.key,
    required this.onCloseRequested,
    required this.child,
  });

  final BusyCardsWindowCloseHandler onCloseRequested;
  final Widget child;

  @override
  State<BusyCardsWindowCloseGuard> createState() =>
      _BusyCardsWindowCloseGuardState();
}

class _BusyCardsWindowCloseGuardState extends State<BusyCardsWindowCloseGuard> {
  BusyCardsWindowCloseCoordinator? _coordinator;
  _BusyCardsWindowCloseRegistration? _registration;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final coordinator = BusyCardsWindowCloseScope.maybeOf(context);
    if (identical(coordinator, _coordinator)) return;
    _registration?.dispose();
    _coordinator = coordinator;
    _registration = coordinator?._register(() => widget.onCloseRequested());
  }

  @override
  void dispose() {
    _registration?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
