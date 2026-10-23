import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';

import '../../core/native_bridge.dart';
import '../home/college_guide_api.dart';
import 'mentor_registration.dart';

const _iconColor = Color(0xFF004D40);
const _allIndia = Color(0xFFE0FFC2);
const _dark = Color(0xFF1C1E21);
const _grey = Color(0xFF6B7280);

enum _MentorState { loading, notRegistered, pending, approved, error }

/// MentorActivity + PGCounselorFragment: the user's mentor status.
class AsMentorPage extends StatefulWidget {
  const AsMentorPage({super.key, required this.api});

  final CollegeGuideApiRepository api;

  @override
  State<AsMentorPage> createState() => _AsMentorPageState();
}

class _AsMentorPageState extends State<AsMentorPage> {
  static const _historyPageSize = 20;

  final _scroll = ScrollController();
  _MentorState _state = _MentorState.loading;
  Map<String, dynamic>? _profile;
  bool _available = false;
  bool _savingAvailability = false;

  final List<Map<String, dynamic>> _sessions = [];
  int _page = 1;
  bool _hasNext = true;
  bool _loadingHistory = false;
  bool _historyLoaded = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_state != _MentorState.approved || _loadingHistory || !_hasNext) {
        return;
      }
      if (_scroll.position.extentAfter < 200) {
        _page++;
        _fetchHistory(fresh: false);
      }
    });
    _fetchStatus();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _fetchStatus() async {
    Map<String, dynamic>? json;
    try {
      json = await widget.api.send('GET', 'college/counsellor/');
    } on CollegeGuideApiException catch (e) {
      json = e.payload;
    }
    if (!mounted) return;
    switch ('${json?['message'] ?? ''}') {
      case 'COUNSELLOR_PROFILE':
        final data = json!['data'];
        setState(() {
          _state = _MentorState.approved;
          _profile = data is Map<String, dynamic> ? data : null;
          _available = _profile?['is_available'] == true;
        });
        _page = 1;
        _hasNext = true;
        _sessions.clear();
        _fetchHistory(fresh: true);
      case 'REGISTRATION_NOT_APPROVED':
        setState(() => _state = _MentorState.pending);
      case 'REGISTRATION_NOT_FOUND':
        setState(() => _state = _MentorState.notRegistered);
      default:
        setState(() => _state = _MentorState.error);
    }
  }

  Future<void> _register() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => MentorRegistrationPage(api: widget.api),
      ),
    );
    // onResume: re-check (now "under review" after a submit).
    if (mounted) _fetchStatus();
  }

  Future<void> _setAvailable(bool available) async {
    setState(() {
      _available = available;
      _savingAvailability = true;
    });
    var saved = !available;
    var ok = false;
    try {
      final json = await widget.api.send(
        'PUT',
        'college/counsellor/profile/',
        body: {'is_available': available},
      );
      final data = json['data'];
      if (data is Map) {
        saved = data['is_available'] == true;
        ok = true;
      }
    } on CollegeGuideApiException {
      ok = false;
    }
    if (!mounted) return;
    setState(() {
      _savingAvailability = false;
      _available = ok ? saved : !available;
    });
    if (!ok) {
      showToast(context, "Couldn't update availability. Please try again.");
    }
  }

  Future<void> _fetchHistory({required bool fresh}) async {
    setState(() => _loadingHistory = true);
    try {
      final json = await widget.api.send(
        'GET',
        'college/counsellor/call/history/',
        query: {'page': '$_page', 'limit': '$_historyPageSize'},
      );
      final data = json['data'] is Map ? json['data'] as Map : const {};
      _hasNext = data['next'] == true;
      for (final r in (data['results'] as List? ?? const [])) {
        if (r is Map<String, dynamic>) _sessions.add(r);
      }
    } on CollegeGuideApiException {
      // Logged only, as natively.
    }
    if (!mounted) return;
    setState(() {
      _loadingHistory = false;
      _historyLoaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: _iconColor,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: _iconColor,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: _iconColor,
        body: SafeArea(
          child: ColoredBox(
            color: const Color(0xFFF4F7F6),
            child: Column(
              children: [
                Container(
                  height: 56,
                  color: _iconColor,
                  child: Row(
                    children: [
                      const SizedBox(width: 8),
                      Semantics(
                        label: 'Back',
                        button: true,
                        child: InkResponse(
                          onTap: () => Navigator.of(context).maybePop(),
                          child: Padding(
                            padding: const EdgeInsets.all(8),
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
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'As a Mentor',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(child: _body()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _body() {
    if (_state == _MentorState.loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(color: _iconColor),
            ),
            SizedBox(height: 12),
            Text(
              'Checking your mentor status…',
              style: TextStyle(
                color: _grey,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }
    return SingleChildScrollView(
      controller: _scroll,
      child: switch (_state) {
        _MentorState.notRegistered => _notRegistered(),
        _MentorState.pending => _pending(),
        _MentorState.approved => _approved(),
        _ => _error(),
      },
    );
  }

  static Widget _circle(double size, Color color, Widget child) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    child: child,
  );

  static Widget _icon(String name, double size, Color tint) => SvgPicture.asset(
    'assets/icons/$name.svg',
    width: size,
    height: size,
    colorFilter: ColorFilter.mode(tint, BlendMode.srcIn),
  );

  static BoxDecoration _card() => BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: const Color(0xFFE6ECEA)),
  );

  static const _title = TextStyle(
    color: _dark,
    fontSize: 22,
    fontWeight: FontWeight.w700,
  );
  static const _subtitle = TextStyle(color: _grey, fontSize: 14, height: 1.36);
  static const _rowText = TextStyle(
    color: _dark,
    fontSize: 14,
    fontWeight: FontWeight.w500,
  );

  Widget _button(String label, VoidCallback onTap, {bool outline = false}) =>
      Material(
        color: outline ? Colors.white : _iconColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: outline
              ? const BorderSide(color: _iconColor, width: 1.5)
              : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 52,
            width: double.infinity,
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  color: outline ? _iconColor : Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      );

  Widget _benefit(String icon, String text) => Row(
    children: [
      _circle(40, _allIndia, _icon(icon, 20, _iconColor)),
      const SizedBox(width: 14),
      Expanded(child: Text(text, style: _rowText)),
    ],
  );

  Widget _notRegistered() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      child: Column(
        children: [
          _circle(120, _allIndia, _icon('ic_menu_mentor', 72, _iconColor)),
          const SizedBox(height: 24),
          const Text(
            'Become a CollegeBook Mentor',
            textAlign: TextAlign.center,
            style: _title,
          ),
          const SizedBox(height: 8),
          const Text(
            'Share your experience with students choosing their college and branch.',
            textAlign: TextAlign.center,
            style: _subtitle,
          ),
          Container(
            margin: const EdgeInsets.only(top: 28),
            padding: const EdgeInsets.all(18),
            decoration: _card(),
            child: Column(
              children: [
                _benefit(
                  'ic_mentor_video',
                  'Guide students on 1:1 video consultations',
                ),
                const SizedBox(height: 14),
                _benefit(
                  'ic_mentor_rupee',
                  'Earn per minute — you set your own fee',
                ),
                const SizedBox(height: 14),
                _benefit(
                  'ic_mentor_badge',
                  'Get a verified mentor badge on your profile',
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          _button('Register as Mentor', _register),
          const SizedBox(height: 12),
          const Text(
            'Takes about 2 minutes · reviewed in 24–48 hours',
            style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _pending() {
    Widget step(String icon, Color tint, Widget text) => Row(
      children: [
        _icon(icon, 24, tint),
        const SizedBox(width: 14),
        Expanded(child: text),
      ],
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      child: Column(
        children: [
          _circle(
            120,
            const Color(0xFFFFF4DB),
            _icon('ic_mentor_hourglass', 60, const Color(0xFFE0A100)),
          ),
          const SizedBox(height: 24),
          const Text(
            'Application under review',
            textAlign: TextAlign.center,
            style: _title,
          ),
          const SizedBox(height: 8),
          const Text(
            "We're reviewing your mentor application. This usually takes 24–48 hours.",
            textAlign: TextAlign.center,
            style: _subtitle,
          ),
          Container(
            margin: const EdgeInsets.only(top: 28),
            padding: const EdgeInsets.all(18),
            decoration: _card(),
            child: Column(
              children: [
                step(
                  'ic_mentor_check',
                  const Color(0xFF1E8E3E),
                  const Text('Application submitted', style: _rowText),
                ),
                const SizedBox(height: 16),
                step(
                  'ic_mentor_hourglass',
                  const Color(0xFFE0A100),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Under review',
                        style: TextStyle(
                          color: _dark,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Our team is verifying your details',
                        style: TextStyle(color: _grey, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                step(
                  'ic_mentor_check',
                  const Color(0xFFC7CBD1),
                  Text(
                    'Approved — start taking calls',
                    style: _rowText.copyWith(color: const Color(0xFF9CA3AF)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          _button('Refresh status', _fetchStatus, outline: true),
        ],
      ),
    );
  }

  Widget _error() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 80, 32, 24),
      child: Column(
        children: [
          _icon('ic_mentor_error', 56, const Color(0xFF9CA3AF)),
          const SizedBox(height: 14),
          const Text(
            'Unable to fetch your mentor status. Please try again later.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF4B5563),
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 24),
          _button('Try again', () {
            setState(() => _state = _MentorState.loading);
            _fetchStatus();
          }, outline: true),
        ],
      ),
    );
  }

  static String _join(String sep, List<Object?> parts) => parts
      .map((p) => '${p ?? ''}'.trim())
      .where((p) => p.isNotEmpty)
      .join(sep);

  Widget _approved() {
    final p = _profile ?? const {};
    final qualification = _join(' - ', [p['speciality'], p['designation']]);
    final place = _join(', ', [p['institute_name'], p['state']]);
    final image = p['image'] as String?;
    final placeholder = Image.asset(
      'assets/images/home/iv_user_profile.jpg',
      fit: BoxFit.cover,
    );
    final available = _available;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: _card(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipOval(
                      child: Container(
                        width: 72,
                        height: 72,
                        color: const Color(0xFFEEF2F4),
                        child: image == null || image.isEmpty
                            ? placeholder
                            : CachedNetworkImage(
                                imageUrl: image,
                                fit: BoxFit.cover,
                                errorWidget: (_, _, _) => placeholder,
                              ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${p['name'] ?? ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _dark,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (qualification.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                qualification,
                                style: const TextStyle(
                                  color: _iconColor,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          if (place.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(top: 1),
                                    child: _icon(
                                      'ic_mentor_location',
                                      14,
                                      _iconColor,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      place,
                                      style: const TextStyle(
                                        color: _grey,
                                        fontSize: 12,
                                        height: 1.33,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                Container(
                  margin: const EdgeInsets.only(top: 14),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0F7F3),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SvgPicture.asset(
                        'assets/icons/ic_review_verified.svg',
                        width: 16,
                        height: 16,
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'Verified mentor',
                        style: TextStyle(
                          color: Color(0xFF13706B),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            decoration: _card(),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: available
                        ? const Color(0xFF1E8E3E)
                        : const Color(0xFF9CA3AF),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        available ? 'Available for calls' : 'Not available',
                        style: const TextStyle(
                          color: _dark,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        available
                            ? 'Students can request video consultations with you'
                            : "You won't receive consultation requests",
                        style: const TextStyle(color: _grey, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: available,
                  onChanged: _savingAvailability ? null : _setAvailable,
                  activeThumbColor: _iconColor,
                  activeTrackColor: const Color(0xFF8FC1B6),
                  inactiveThumbColor: Colors.white,
                  inactiveTrackColor: const Color(0xFFC7CBD1),
                  trackOutlineColor: WidgetStateProperty.all(
                    Colors.transparent,
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 24, 0, 0),
            child: Text(
              'Session History',
              style: TextStyle(
                color: _dark,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 10),
          for (final s in _sessions) _SessionRow(session: s),
          if (_loadingHistory && _sessions.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(color: _iconColor),
                ),
              ),
            ),
          if (_historyLoaded && _sessions.isEmpty && !_loadingHistory)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 28),
              decoration: _card(),
              child: Column(
                children: [
                  _circle(
                    56,
                    const Color(0xFFEEF2F4),
                    _icon('ic_mentor_video', 26, const Color(0xFF9CA3AF)),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'No sessions yet',
                    style: TextStyle(
                      color: _dark,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      'Your consultation calls will show up here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: _grey, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// item_counsellor_call_history.xml.
class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.session});

  final Map<String, dynamic> session;

  static String _date(String? raw) {
    if (raw == null) return '';
    final trimmed = raw.length > 19 ? raw.substring(0, 19) : raw;
    final parsed = DateTime.tryParse(trimmed);
    return parsed == null
        ? raw
        : DateFormat('hh:mm a, dd MMM yyyy').format(parsed);
  }

  static String? _reason(String? reason) => switch (reason) {
    null => null,
    'user_hangup' => 'Ended by caller',
    'counsellor_hangup' => 'Ended by you',
    'rejected_by_counsellor' => 'You declined this call',
    'disconnected' => 'Call disconnected',
    _ => reason.replaceAll('_', ' '),
  };

  @override
  Widget build(BuildContext context) {
    final caller = session['caller'] as Map?;
    final image = caller?['image'] as String?;
    final charged = (session['total_charged'] as num?)?.toDouble() ?? 0;
    final amount = charged > 0
        ? '₹${charged == charged.floorToDouble() ? charged.toInt() : charged.toStringAsFixed(2)}'
        : 'Free';
    final status = '${session['status'] ?? ''}';
    final (bg, fg, label) = switch (status) {
      'ENDED' => (
        const Color(0xFFE5F6E9),
        const Color(0xFF1E8E3E),
        'Completed',
      ),
      'REJECTED' => (
        const Color(0xFFFDEAEA),
        const Color(0xFFD32F2F),
        'Rejected',
      ),
      'MISSED' => (const Color(0xFFFFF3E0), const Color(0xFFB26A00), 'Missed'),
      _ => (const Color(0xFFEEEEEE), const Color(0xFF666666), status),
    };
    final reason = _reason(session['end_reason'] as String?);
    final placeholder = Image.asset(
      'assets/images/home/iv_mirror.png',
      fit: BoxFit.cover,
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE6ECEA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipOval(
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: image == null || image.isEmpty
                      ? placeholder
                      : CachedNetworkImage(
                          imageUrl: image,
                          fit: BoxFit.cover,
                          placeholder: (_, _) => placeholder,
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${caller?['name'] ?? 'Unknown'}',
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _date(
                        session['end_time'] as String? ??
                            session['start_time'] as String?,
                      ),
                      style: const TextStyle(
                        color: Color(0xFF8A8A8A),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(360),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    color: fg,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          Container(
            height: 1,
            margin: const EdgeInsets.only(top: 12),
            color: const Color(0xFFEDEDED),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text(
                '⏱  ',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              ),
              Expanded(
                child: Text(
                  '${session['duration_formatted'] ?? ''}',
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                amount,
                style: const TextStyle(
                  color: Color(0xFF1E8E3E),
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          if (reason != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                reason,
                style: const TextStyle(color: Color(0xFFB0B0B0), fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }
}
