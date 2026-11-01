import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import 'data.dart';
import 'main.dart';
import 'ui.dart';

/// Optional LOCAL screen lock (ported from the desktop app). The database
/// file is NOT encrypted - this gates the screen only. Failed attempts are
/// throttled with escalating delays (in-memory, per app run).
class AppLock {
  static int failures = 0;
  static DateTime? lockedUntil;

  static const _delays = [
    Duration(seconds: 5),
    Duration(seconds: 15),
    Duration(minutes: 1),
    Duration(minutes: 5),
  ];

  static Duration? lockoutRemaining() {
    final until = lockedUntil;
    if (until == null) return null;
    final left = until.difference(DateTime.now());
    return left.isNegative ? null : left;
  }

  static void recordFailure() {
    failures++;
    if (failures >= 3) {
      lockedUntil =
          DateTime.now().add(_delays[min(failures - 3, _delays.length - 1)]);
    }
  }

  static void recordSuccess() {
    failures = 0;
    lockedUntil = null;
  }
}

/// Gates the whole app behind the password when one is set. Locks again when
/// the app goes to background, and immediately when a restore swaps in a
/// password hash (dataRevision fires and sessionUnlocked was cleared).
class LockGate extends StatefulWidget {
  final Widget child;
  const LockGate({super.key, required this.child});

  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> with WidgetsBindingObserver {
  bool _hasPassword = false;
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppDb.dataRevision.addListener(_reevaluate);
    _reevaluate();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AppDb.dataRevision.removeListener(_reevaluate);
    super.dispose();
  }

  Future<void> _reevaluate() async {
    final has = await AppDb.hasPassword();
    if (!mounted) return;
    setState(() {
      _hasPassword = has;
      _checked = true;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && _hasPassword) {
      AppDb.sessionUnlocked = false; // require the password again on resume
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_checked) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_hasPassword && !AppDb.sessionUnlocked) {
      return LockScreen(onUnlocked: () => setState(() {}));
    }
    return widget.child;
  }
}

class LockScreen extends StatefulWidget {
  final VoidCallback onUnlocked;
  const LockScreen({super.key, required this.onUnlocked});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _pw = TextEditingController();
  String? _error;
  bool _busy = false;
  Timer? _ticker;

  @override
  void dispose() {
    _ticker?.cancel();
    _pw.dispose();
    super.dispose();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (AppLock.lockoutRemaining() == null) {
        _ticker?.cancel();
      }
      if (mounted) setState(() {});
    });
  }

  Future<void> _unlock() async {
    final lockout = AppLock.lockoutRemaining();
    if (lockout != null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await AppDb.verifyPassword(_pw.text);
    if (!mounted) return;
    if (ok) {
      AppLock.recordSuccess();
      AppDb.sessionUnlocked = true;
      widget.onUnlocked();
    } else {
      AppLock.recordFailure();
      _pw.clear();
      setState(() {
        _busy = false;
        _error = 'Wrong password.';
      });
      if (AppLock.lockoutRemaining() != null) _startTicker();
    }
  }

  @override
  Widget build(BuildContext context) {
    final lockout = AppLock.lockoutRemaining();
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(Brand.value.shopName,
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold, color: kNavy)),
            const SizedBox(height: 6),
            const Text('Locked', style: TextStyle(color: kSoft)),
            const SizedBox(height: 18),
            TextField(
                controller: _pw,
                obscureText: true,
                autofocus: true,
                onSubmitted: (_) => _unlock(),
                decoration: const InputDecoration(
                    labelText: 'Password', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: kRed)),
            if (lockout != null)
              Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                      'Too many tries - wait ${lockout.inSeconds + 1}s',
                      style: const TextStyle(color: kRed))),
            const SizedBox(height: 12),
            SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                    onPressed: lockout != null || _busy ? null : _unlock,
                    child: Text(_busy ? 'Checking...' : 'Unlock'))),
          ]),
        ),
      ),
    );
  }
}
