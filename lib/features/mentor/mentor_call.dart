import 'dart:async';
import 'dart:convert';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../core/native_bridge.dart';
import '../../core/native_dialog.dart';
import '../home/college_guide_api.dart';
import 'mentor_page.dart';

const _iconColor = Color(0xFF004D40);

/// AppConstants.appId of the native app.
const _agoraAppId = '052d071326e84eaa9176e28c6695933b';

/// MentorCallStarter.confirmAndCall: confirm, start the call session, then
/// open the video call.
Future<void> confirmAndCallMentor(
  BuildContext context,
  CollegeGuideApiRepository api,
  Mentor mentor,
) async {
  final confirmed = await showNativeAlert(
    context,
    title: 'Confirm Video Call',
    message: 'Are you sure you want to go for video call?',
    negative: 'No',
    positive: 'Yes',
  );
  if (confirmed != true || !context.mounted) return;

  final navigator = Navigator.of(context);
  // The fragment's progress bar while the session starts.
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const PopScope(
      canPop: false,
      child: Center(child: CircularProgressIndicator()),
    ),
  );
  Map<String, dynamic>? json;
  String? failure;
  try {
    json = await api.send(
      'POST',
      'college/call/initiate/',
      body: {'counsellor_id': int.tryParse(mentor.id) ?? mentor.id},
    );
  } on CollegeGuideApiException catch (e) {
    failure = e.payload == null
        ? "Couldn't start the call. Check your internet and try again."
        : _serverMessage(e.payload!);
  }
  navigator.pop();
  if (!context.mounted) return;

  final data = json?['data'];
  if (failure != null || data is! Map) {
    showToast(context, failure ?? (json == null ? '' : _serverMessage(json)));
    return;
  }
  navigator.push(
    MaterialPageRoute<void>(
      builder: (_) => VideoCallPage(
        api: api,
        sessionId: '${data['session_id'] ?? ''}',
        uid: (data['uid'] as num?)?.toInt() ?? 0,
        channelName: '${data['channel_name'] ?? ''}',
        agoraToken: '${data['agora_token'] ?? ''}',
      ),
    ),
  );
}

/// The server's text for a refused call: description, else message.
String _serverMessage(Map<String, dynamic> json) {
  for (final key in const ['description', 'message']) {
    final value = json[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
  }
  return 'Unable to start the call. Please try again.';
}

/// AgoraVideoCallActivity (activity_agora_video_call.xml).
class VideoCallPage extends StatefulWidget {
  const VideoCallPage({
    super.key,
    required this.api,
    required this.sessionId,
    required this.uid,
    required this.channelName,
    required this.agoraToken,
  });

  final CollegeGuideApiRepository api;
  final String sessionId;
  final int uid;
  final String channelName;
  final String agoraToken;

  @override
  State<VideoCallPage> createState() => _VideoCallPageState();
}

class _VideoCallPageState extends State<VideoCallPage> {
  RtcEngine? _engine;
  WebSocketChannel? _socket;
  StreamSubscription<dynamic>? _socketSubscription;
  Timer? _waitingTimer;

  bool _muted = false;
  bool _localConnected = false;
  bool _remoteConnected = false;
  bool _connected = false;
  bool _apiCallInProgress = false;
  bool _sessionClosing = false;
  bool _finished = false;
  bool _swapped = false;
  bool _waitingShown = false;
  int? _remoteUid;
  String? _remaining;

  @override
  void initState() {
    super.initState();
    _initializeAndJoinChannel();
    _connectCallSocket();
  }

  @override
  void dispose() {
    _waitingTimer?.cancel();
    _socketSubscription?.cancel();
    _socket?.sink.close();
    _releaseEngine();
    super.dispose();
  }

  void _releaseEngine() {
    final engine = _engine;
    _engine = null;
    if (engine == null) return;
    engine.leaveChannel().whenComplete(engine.release);
  }

  // ---- Call socket: waiting/accepted/balance/terminal events ----

  Future<void> _connectCallSocket() async {
    if (widget.sessionId.isEmpty) return;
    final token = await widget.api.accessToken() ?? '';
    if (!mounted) return;
    final uri = Uri.parse(
      'wss://${widget.api.apiHost}/ws/call/${widget.sessionId}/user/',
    ).replace(queryParameters: {'token': token});
    // Logged like CallSocketManager; never the URL, it carries the token.
    debugPrint('CallSocketManager: Connecting call socket');
    try {
      final socket = WebSocketChannel.connect(uri);
      _socket = socket;
      socket.ready.then(
        (_) => debugPrint('CallSocketManager: Socket opened'),
        onError: (Object e) =>
            debugPrint('CallSocketManager: Socket failure: ${e.runtimeType}'),
      );
      _socketSubscription = socket.stream.listen(
        (message) => _handleMessage('$message'),
        onError: (Object e) {
          // CallSocketManager only logs a failed socket.
          debugPrint('CallSocketManager: Socket failure: ${e.runtimeType}');
        },
        onDone: () => debugPrint(
          'CallSocketManager: Socket closed, code=${socket.closeCode}',
        ),
      );
    } on Object catch (e) {
      debugPrint('CallSocketManager: Socket failure: ${e.runtimeType}');
    }
  }

  void _handleMessage(String text) {
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      return;
    }
    if (decoded is! Map || !mounted) return;
    debugPrint('CallSocketManager: message type=${decoded['type']}');
    switch (decoded['type']) {
      case 'WAITING_FOR_COUNSELLOR':
        _showWaitingDialog();
      case 'CALL_ACCEPTED':
        _waitingTimer?.cancel();
        _dismissWaitingDialog();
      case 'BALANCE_UPDATE':
        final balance = '${decoded['balance'] ?? '0'}';
        setState(() => _remaining = 'Balance: ₹$balance');
        final value = double.tryParse(balance);
        if (value != null && value <= 0) {
          _closeSessionAndFinish('Call ended: balance exhausted');
        }
      case 'CALL_CANCELLED' ||
          'CALL_REJECTED' ||
          'CALL_MISSED' ||
          'CALL_BALANCE_EXHAUSTED' ||
          'CALL_ENDED':
        final body = decoded['body'];
        showToast(context, body is String ? body : 'Call ended');
        _leaveAndFinish();
    }
  }

  Future<void> _endCall() async {
    debugPrint('CallSocketManager: ending call session');
    try {
      await widget.api.send(
        'POST',
        'college/call/${widget.sessionId}/end/',
        body: const {},
      );
    } on CollegeGuideApiException {
      // The native screen closes whatever the answer.
    }
  }

  Future<void> _closeSessionAndFinish(String reason) async {
    if (_sessionClosing) return;
    _sessionClosing = true;
    showToast(context, reason);
    await _endCall();
    _leaveAndFinish();
  }

  // ---- Waiting dialog: shown until the mentor joins ----

  void _showWaitingDialog() {
    if (_waitingShown || _finished) return;
    _waitingShown = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _showExitCallDialog();
        },
        child: _WaitingDialog(onCancel: _cancelFromWaiting),
      ),
    ).whenComplete(() => _waitingShown = false);
  }

  void _dismissWaitingDialog() {
    if (!_waitingShown || !mounted) return;
    _waitingShown = false;
    Navigator.of(context).pop();
  }

  Future<void> _cancelFromWaiting() async {
    if (_apiCallInProgress) return;
    _apiCallInProgress = true;
    await _endCall();
    _apiCallInProgress = false;
    _leaveAndFinish();
  }

  // ---- Exit dialog: cancel (waiting) or end (connected) ----

  Future<void> _showExitCallDialog() async {
    if (_apiCallInProgress) return;
    final connected = _connected;
    final confirmed = await showNativeAlert(
      context,
      title: connected ? 'End Call?' : 'Cancel Call?',
      message: connected
          ? 'Are you sure you want to end this call?'
          : 'Are you sure you want to cancel the call request?',
      negative: 'Stay',
      positive: connected ? 'End' : 'Cancel Call',
    );
    if (confirmed != true || _apiCallInProgress || !mounted) return;
    _apiCallInProgress = true;
    _waitingTimer?.cancel();
    await _endCall();
    _apiCallInProgress = false;
    _leaveAndFinish();
  }

  void _checkBothConnected() {
    if (!_localConnected || !_remoteConnected) return;
    _dismissWaitingDialog();
    showToast(context, 'Both connected successfully');
    _waitingTimer?.cancel();
    setState(() {
      _connected = true;
      _remaining = null;
    });
  }

  /// Auto-cancel when the mentor doesn't join within 15s.
  void _startWaitingTimer() {
    _waitingTimer = Timer(const Duration(seconds: 15), () async {
      if (_remoteConnected || _apiCallInProgress || !mounted) return;
      debugPrint('CallSocketManager: 15s wait timer fired');
      showToast(context, 'No response. Cancelling call...');
      _apiCallInProgress = true;
      await _endCall();
      _leaveAndFinish();
    });
  }

  /// Leaves the channel and goes back to the home screen.
  void _leaveAndFinish() {
    if (_finished || !mounted) return;
    _finished = true;
    _waitingTimer?.cancel();
    _releaseEngine();
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  // ---- Agora ----

  Future<void> _initializeAndJoinChannel() async {
    final statuses = await [Permission.microphone, Permission.camera].request();
    if (!mounted) return;
    if (statuses.values.any((s) => !s.isGranted)) {
      showToast(context, 'Camera & Audio permissions required.');
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    final engine = createAgoraRtcEngine();
    try {
      await engine.initialize(
        const RtcEngineContext(
          appId: _agoraAppId,
          channelProfile: ChannelProfileType.channelProfileCommunication,
        ),
      );
    } on Object {
      return;
    }
    if (!mounted) {
      await engine.release();
      return;
    }
    _engine = engine;
    engine.registerEventHandler(
      RtcEngineEventHandler(
        onUserJoined: (connection, remoteUid, elapsed) {
          if (!mounted) return;
          _waitingTimer?.cancel();
          setState(() {
            _remoteConnected = true;
            _remoteUid = remoteUid;
          });
          _checkBothConnected();
        },
        onUserOffline: (connection, remoteUid, reason) {
          if (!mounted) return;
          setState(() {
            _remoteConnected = false;
            _remoteUid = null;
          });
          showToast(context, 'User disconnected');
          _leaveAndFinish();
        },
      ),
    );
    await engine.enableVideo();
    await engine.enableAudio();
    await engine.setDefaultAudioRouteToSpeakerphone(true);
    await engine.muteLocalAudioStream(false);
    await engine.startPreview();
    await engine.joinChannel(
      token: widget.agoraToken,
      channelId: widget.channelName,
      uid: widget.uid,
      options: const ChannelMediaOptions(
        channelProfile: ChannelProfileType.channelProfileCommunication,
        clientRoleType: ClientRoleType.clientRoleBroadcaster,
      ),
    );
    if (!mounted) return;
    setState(() => _localConnected = true);
    _checkBothConnected();
    _showWaitingDialog();
    _startWaitingTimer();
  }

  void _switchCamera() => _engine?.switchCamera();

  void _toggleMute() {
    setState(() => _muted = !_muted);
    _engine?.muteLocalAudioStream(_muted);
  }

  /// Tapping either box swaps the two videos once the mentor is in.
  void _swap() {
    if (_remoteUid == null) return;
    setState(() => _swapped = !_swapped);
  }

  Widget? _localView() {
    final engine = _engine;
    if (engine == null || !_localConnected) return null;
    return AgoraVideoView(
      controller: VideoViewController(
        rtcEngine: engine,
        canvas: const VideoCanvas(
          uid: 0,
          renderMode: RenderModeType.renderModeHidden,
        ),
      ),
    );
  }

  Widget? _remoteView() {
    final engine = _engine;
    final remoteUid = _remoteUid;
    if (engine == null || remoteUid == null) return null;
    return AgoraVideoView(
      controller: VideoViewController.remote(
        rtcEngine: engine,
        canvas: VideoCanvas(
          uid: remoteUid,
          renderMode: RenderModeType.renderModeHidden,
        ),
        connection: RtcConnection(channelId: widget.channelName),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final top = _swapped ? _localView() : _remoteView();
    final bottom = _swapped ? _remoteView() : _localView();
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _showExitCallDialog();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          statusBarColor: Colors.black,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
          systemNavigationBarColor: Colors.black,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
        child: Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: Column(
              children: [
                _CallHeader(onBack: _showExitCallDialog),
                Expanded(
                  child: Stack(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          children: [
                            Expanded(
                              child: _VideoBox(
                                key: const Key('remoteVideoBox'),
                                onTap: _swap,
                                child: top,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Expanded(
                              child: _VideoBox(
                                key: const Key('localVideoBox'),
                                onTap: _swap,
                                child: bottom,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_remaining != null && !_connected)
                        Positioned(
                          top: 30,
                          left: 30,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(360),
                            ),
                            child: Text(
                              _remaining!,
                              style: const TextStyle(
                                color: Colors.black,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _PressedImageButton(
                        label: 'Switch camera',
                        name: 'btn_switch_camera',
                        onTap: _switchCamera,
                      ),
                      const SizedBox(width: 16),
                      _PressedImageButton(
                        label: _muted ? 'Unmute' : 'Mute',
                        name: _muted ? 'btn_mute' : 'btn_unmute',
                        onTap: _toggleMute,
                      ),
                      const SizedBox(width: 16),
                      _PressedImageButton(
                        label: 'End call',
                        name: 'btn_endcall',
                        onTap: _showExitCallDialog,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CallHeader extends StatelessWidget {
  const _CallHeader({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _iconColor,
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          const SizedBox(width: 12),
          Semantics(
            label: 'Back',
            button: true,
            child: GestureDetector(
              onTap: onBack,
              child: SvgPicture.asset(
                'assets/icons/ic_baseline_arrow_back_24.svg',
                width: 24,
                height: 24,
                colorFilter: const ColorFilter.mode(
                  Colors.white,
                  BlendMode.srcIn,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Text(
            'Video Call',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// A black 16dp card with the 2dp #8BC34A outline.
class _VideoBox extends StatelessWidget {
  const _VideoBox({super.key, required this.onTap, this.child});

  final VoidCallback onTap;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF8BC34A), width: 2),
        ),
        child: ClipRRect(borderRadius: BorderRadius.circular(14), child: child),
      ),
    );
  }
}

/// The btn_* state-list drawables: the _pressed bitmap while held.
class _PressedImageButton extends StatefulWidget {
  const _PressedImageButton({
    required this.label,
    required this.name,
    required this.onTap,
  });

  final String label;
  final String name;
  final VoidCallback onTap;

  @override
  State<_PressedImageButton> createState() => _PressedImageButtonState();
}

class _PressedImageButtonState extends State<_PressedImageButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.label,
      button: true,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: Image.asset(
          'assets/images/call/${widget.name}_${_pressed ? 'pressed' : 'normal'}.png',
          width: 70,
          height: 70,
          fit: BoxFit.cover,
          gaplessPlayback: true,
        ),
      ),
    );
  }
}

/// dialog_waiting_doctor.xml.
class _WaitingDialog extends StatefulWidget {
  const _WaitingDialog({required this.onCancel});

  final VoidCallback onCancel;

  @override
  State<_WaitingDialog> createState() => _WaitingDialogState();
}

class _WaitingDialogState extends State<_WaitingDialog>
    with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width * 0.85;
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: width,
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFC5C5C5)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 90,
                height: 90,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    AnimatedBuilder(
                      animation: _pulse,
                      builder: (_, child) {
                        final t = Curves.decelerate.transform(_pulse.value);
                        return Opacity(
                          opacity: 0.6 * (1 - t),
                          child: Transform.scale(
                            scale: 1 + 0.35 * t,
                            child: child,
                          ),
                        );
                      },
                      child: Container(
                        width: 90,
                        height: 90,
                        decoration: const BoxDecoration(
                          color: Color(0x33007BFF),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    Container(
                      width: 64,
                      height: 64,
                      decoration: const BoxDecoration(
                        color: Color(0x33007BFF),
                        shape: BoxShape.circle,
                      ),
                    ),
                    Image.asset(
                      'assets/images/home/iv_mirror.png',
                      width: 32,
                      height: 32,
                      color: Colors.white,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Connecting you to the Mentor',
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Please hold on, your mentor will join shortly',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF888888), fontSize: 13),
              ),
              const SizedBox(height: 18),
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF12151B),
                ),
              ),
              Container(
                height: 1,
                margin: const EdgeInsets.only(top: 20, bottom: 4),
                color: const Color(0xFFF0F0F0),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: widget.onCancel,
                child: Container(
                  height: 44,
                  width: double.infinity,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF0F0),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Cancel Request',
                    style: TextStyle(
                      color: Color(0xFFF44336),
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
