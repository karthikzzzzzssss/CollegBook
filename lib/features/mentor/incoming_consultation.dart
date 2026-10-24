import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/native_bridge.dart';
import '../home/college_guide_api.dart';
import 'mentor_call.dart';

/// The app's root navigator, so a call can open over whatever is on screen.
final appNavigatorKey = GlobalKey<NavigatorState>();

/// iOS mentor calls: CallKit (AppDelegate) rings the phone for each VoIP push;
/// with the app open the Android-style [IncomingConsultationPage] shows too.
/// Answering or declining on either one answers or declines both.
class CounsellorCalls {
  CounsellorCalls._();

  static CollegeGuideApiRepository? _api;

  /// Starts listening for CallKit (once logged in). [onVoipToken] runs when
  /// iOS issues a new PushKit token, to send it to the server.
  static void start(
    CollegeGuideApiRepository api, {
    required VoidCallback onVoipToken,
  }) {
    _api = api;
    listenToCallKit(_onEvent, onVoipToken: onVoipToken);
  }

  static void _onEvent(CallKitEvent event, String sessionId, String? userName) {
    final api = _api;
    final navigator = appNavigatorKey.currentState;
    if (api == null || navigator == null) return;
    final ringing = IncomingConsultationPage.showing[sessionId];
    switch (event) {
      case CallKitEvent.incoming:
        if (ringing != null ||
            CounsellorVideoCallPage.active.containsKey(sessionId)) {
          return;
        }
        navigator.push(_route(api, sessionId, userName, autoAccept: false));
      case CallKitEvent.answered:
        if (CounsellorVideoCallPage.active.containsKey(sessionId)) return;
        if (ringing != null) {
          ringing.acceptFromCallKit();
        } else {
          navigator.push(_route(api, sessionId, userName, autoAccept: true));
        }
      case CallKitEvent.declined:
        ringing?.close();
      case CallKitEvent.ended:
        ringing?.close();
        CounsellorVideoCallPage.active[sessionId]?.forceClose('Session ended.');
      case CallKitEvent.hungUp:
        CounsellorVideoCallPage.active[sessionId]?.hangUp();
    }
  }

  static Route<void> _route(
    CollegeGuideApiRepository api,
    String sessionId,
    String? userName, {
    required bool autoAccept,
  }) => MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => IncomingConsultationPage(
      api: api,
      sessionId: sessionId,
      userName: userName,
      autoAccept: autoAccept,
    ),
  );
}

const _background = Color(0xFF0D1B2A);
const _accent = Color(0xFF4FC3F7);
const _timerColor = Color(0xFFFF7043);
const _ringSeconds = 30;

/// IncomingCounsellorConsultationActivity
/// (activity_incoming_counsellor_consultation.xml): rings for 30s, then
/// declines. Accept → college/call/{id}/accept/ → the video call.
class IncomingConsultationPage extends StatefulWidget {
  const IncomingConsultationPage({
    super.key,
    required this.api,
    required this.sessionId,
    this.userName,
    this.autoAccept = false,
  });

  final CollegeGuideApiRepository api;
  final String sessionId;
  final String? userName;

  /// Already answered on the system call screen: accept straight away.
  final bool autoAccept;

  /// The ringing screens, so CallKit events reach them.
  static final showing = <String, IncomingConsultationPageState>{};

  @override
  State<IncomingConsultationPage> createState() =>
      IncomingConsultationPageState();
}

class IncomingConsultationPageState extends State<IncomingConsultationPage>
    with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();
  Timer? _countdown;
  int _secondsLeft = _ringSeconds;
  bool _responding = false;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    IncomingConsultationPage.showing[widget.sessionId] = this;
    if (widget.autoAccept) {
      WidgetsBinding.instance.addPostFrameCallback((_) => acceptFromCallKit());
    } else {
      _startCountdown();
    }
  }

  @override
  void dispose() {
    if (IncomingConsultationPage.showing[widget.sessionId] == this) {
      IncomingConsultationPage.showing.remove(widget.sessionId);
    }
    _countdown?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  void _startCountdown() {
    _countdown?.cancel();
    setState(() => _secondsLeft = _ringSeconds);
    _countdown = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      if (_secondsLeft <= 1) {
        timer.cancel();
        _respond(accept: false);
        return;
      }
      setState(() => _secondsLeft--);
    });
  }

  /// Answered on the system call screen: CallKit is already answered.
  void acceptFromCallKit() => _respond(accept: true, fromCallKit: true);

  /// Declined or over elsewhere (system call screen, student cancelled).
  void close() {
    if (_closed || !mounted) return;
    _closed = true;
    Navigator.of(context).pop();
  }

  Future<void> _respond({
    required bool accept,
    bool fromCallKit = false,
  }) async {
    if (_responding || _closed) return;
    setState(() => _responding = true);
    _countdown?.cancel();
    if (!fromCallKit) {
      // Stop the system call screen ringing; AppDelegate sends no API call.
      accept ? callKitAnswered(widget.sessionId) : callKitEnd(widget.sessionId);
    }
    final action = accept ? 'accept' : 'reject';
    Map<String, dynamic>? json;
    try {
      json = await widget.api.send(
        'POST',
        'college/call/${widget.sessionId}/$action/',
        body: const {},
      );
    } on CollegeGuideApiException {
      json = null;
    }
    if (!mounted || _closed) return;
    if (!accept) {
      close();
      return;
    }
    final data = json?['data'];
    if (data is Map) {
      _closed = true;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => CounsellorVideoCallPage.fromAccept(
            widget.api,
            widget.sessionId,
            data,
          ),
        ),
      );
      return;
    }
    // Let them try again while the student is still waiting.
    showToast(context, 'Failed to accept. Please try again.');
    setState(() => _responding = false);
    _startCountdown();
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.userName?.trim() ?? '';
    return PopScope(
      canPop: false,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          statusBarColor: _background,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
        child: Scaffold(
          backgroundColor: _background,
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: Column(
                  children: [
                    if (_responding)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 16),
                        child: CircularProgressIndicator(color: _accent),
                      ),
                    _PulseIcon(animation: _pulse),
                    const SizedBox(height: 24),
                    const Text(
                      'Incoming Consultation',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0x1A4FC3F7),
                        border: Border.all(color: _accent),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        '🎥  Video Consultation',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    Container(height: 1, color: const Color(0x22FFFFFF)),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF121F2E),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              '👤  User',
                              style: TextStyle(
                                color: Color(0xFF78909C),
                                fontSize: 13,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              name.isEmpty ? 'Student' : name,
                              textAlign: TextAlign.end,
                              style: const TextStyle(
                                color: Color(0xFFECEFF1),
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                    _CountdownRing(seconds: _secondsLeft),
                    const SizedBox(height: 36),
                    Row(
                      children: [
                        Expanded(
                          child: _ActionButton(
                            label: 'Decline',
                            color: const Color(0xFFC62828),
                            stroke: const Color(0xFFB71C1C),
                            onTap: _responding
                                ? null
                                : () => _respond(accept: false),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _ActionButton(
                            label: 'Accept',
                            color: const Color(0xFF2E7D32),
                            stroke: const Color(0xFF1B5E20),
                            onTap: _responding
                                ? null
                                : () => _respond(accept: true),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// bg_pulse_ring (15% #4FC3F7) around bg_icon_circle with the 🎓.
class _PulseIcon extends StatelessWidget {
  const _PulseIcon({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 100,
      height: 100,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: animation,
            builder: (_, _) => Transform.scale(
              scale: 0.85 + 0.15 * animation.value,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _accent.withValues(
                    alpha: 0.15 * (1 - animation.value * 0.5),
                  ),
                ),
              ),
            ),
          ),
          Container(
            width: 72,
            height: 72,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0x1A4FC3F7),
              border: Border.all(color: _accent, width: 2),
            ),
            child: const Text('🎓', style: TextStyle(fontSize: 32)),
          ),
        ],
      ),
    );
  }
}

/// circular_timer_progress: an #FF7043 ring draining with the seconds.
class _CountdownRing extends StatelessWidget {
  const _CountdownRing({required this.seconds});

  final int seconds;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 80,
      height: 80,
      child: CustomPaint(
        painter: _RingPainter(seconds / _ringSeconds),
        child: Center(
          child: Text(
            '${seconds}s',
            style: const TextStyle(
              color: _timerColor,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 80 / 14;
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawArc(
      rect,
      0,
      math.pi * 2,
      false,
      paint..color = const Color(0x33FF7043),
    );
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * progress,
      false,
      paint..color = _timerColor,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress;
}

/// bg_decline_button / bg_accept_button: 56dp, 12dp corners, 1dp stroke.
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.color,
    required this.stroke,
    required this.onTap,
  });

  final String label;
  final Color color;
  final Color stroke;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? 0.6 : 1,
      child: Material(
        color: color,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: stroke),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: SizedBox(
            height: 56,
            child: Center(
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
