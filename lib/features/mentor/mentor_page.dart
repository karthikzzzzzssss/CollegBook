import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/native_bridge.dart';
import '../../theme/app_theme.dart';
import '../home/college_guide_api.dart';
import 'mentor_call.dart';
import 'wallet_page.dart';

const _state = Color(0xFF1E4B3E);
const _allIndia = Color(0xFFE0FFC2);
const _appColor = Color(0xFF12151B);
const _secondary = Color(0xFF6B7280);
const _stroke = Color(0xFFE3E5E8);

/// One mentor from college/counsellor-list/ (CollegePlanCounselorModel.Result).
class Mentor {
  Mentor(Map<String, dynamic> json)
    : id = '${json['id']}',
      name = '${json['name'] ?? ''}',
      image = json['image'] as String?,
      speciality = json['speciality'] as String?,
      designation = (json['designation'] as String? ?? '').trim(),
      instituteName = json['institute_name'] as String? ?? '',
      degree = (json['degree'] as String? ?? '').trim(),
      available = json['is_available'] as bool?,
      liked = json['like_status'] == true,
      expertise = [
        for (final e in (json['expert'] as List? ?? const []))
          if (e is Map && '${e['name'] ?? ''}'.trim().isNotEmpty)
            '${e['name']}'.trim(),
      ],
      fee = '${(json['appointment'] as Map?)?['consultation_fee'] ?? '0'}',
      duration = '${(json['appointment'] as Map?)?['duration'] ?? ''}';

  final String id;
  final String name;
  final String? image;
  final String? speciality;
  final String designation;
  final String instituteName;
  final String degree;
  final bool? available;
  bool liked;
  final List<String> expertise;
  final String fee;
  final String duration;
}

/// The Mentor tab — CollegePGTalkFragment (fragment_college_p_g_talk.xml).
class MentorPage extends StatefulWidget {
  const MentorPage({super.key, required this.api});

  final CollegeGuideApiRepository api;

  @override
  State<MentorPage> createState() => _MentorPageState();
}

class _MentorPageState extends State<MentorPage> {
  static const _pageLimit = 10;

  final _scroll = ScrollController();
  final List<Mentor> _mentors = [];
  final _filters = _MentorFilters();
  int _page = 1;
  int _totalPages = 1;
  int _request = 0;
  bool _loading = false;
  bool _loaded = false;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      final p = _scroll.position;
      // Native: next page once scrolled to the end.
      if (!_loading && p.pixels >= p.maxScrollExtent && _page < _totalPages) {
        _page++;
        _load(fresh: false);
      }
    });
    _load(fresh: true);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({required bool fresh}) async {
    if (fresh) _page = 1;
    final request = ++_request;
    setState(() => _loading = true);
    try {
      final json = await widget.api.send(
        'POST',
        'college/counsellor-list/',
        body: {
          'states': _filters.applied[0],
          'institute_names': _filters.applied[1],
          'specialities': _filters.applied[2],
          'degrees': _filters.applied[3],
          'page': _page,
          'limit': _pageLimit,
        },
      );
      if (!mounted || request != _request) return;
      final data = json['data'] as Map<String, dynamic>? ?? const {};
      final results = [
        for (final r in (data['results'] as List? ?? const []))
          if (r is Map<String, dynamic>) Mentor(r),
      ];
      setState(() {
        _totalPages = (data['total_page'] as num?)?.toInt() ?? 1;
        if (fresh) _mentors.clear();
        _mentors.addAll(results);
      });
      if (fresh && _scroll.hasClients) _scroll.jumpTo(0);
    } on CollegeGuideApiException {
      if (!mounted || request != _request) return;
      if (fresh) setState(_mentors.clear);
      showToast(context, 'Failed to load counsellors');
    } finally {
      if (mounted && request == _request) {
        setState(() {
          _loading = false;
          _loaded = true;
        });
      }
    }
  }

  Future<void> _openSearch() async {
    final apply = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SearchMentorSheet(api: widget.api, filters: _filters),
    );
    if (apply == true) _load(fresh: true);
  }

  Future<void> _openFavourites() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => FavouriteMentorsPage(api: widget.api)),
    );
    if (changed == true) _load(fresh: true);
  }

  @override
  Widget build(BuildContext context) {
    final empty = _loaded && !_loading && _mentors.isEmpty;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Transparent, so the green drawn behind it dims with dialog scrims.
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: ColoredBox(
        color: _state,
        child: SafeArea(
          bottom: false,
          child: ColoredBox(
            color: const Color(0xFFF6FAF7),
            child: Column(
              key: const Key('mentorScreen'),
              children: [
                _MentorHeader(
                  onSearch: _openSearch,
                  onFavourites: _openFavourites,
                  onWallet: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => WalletPage(api: widget.api),
                    ),
                  ),
                ),
                Expanded(
                  child: Stack(
                    children: [
                      if (_loaded)
                        RefreshIndicator(
                          onRefresh: () => _load(fresh: true),
                          child: ListView(
                            controller: _scroll,
                            physics: const AlwaysScrollableScrollPhysics(),
                            // SwipeRefreshLayout ignores the scroll view's
                            // 6dp top margin natively.
                            padding: const EdgeInsets.only(bottom: 16),
                            children: [
                              _Hero(
                                expanded: _expanded,
                                onToggle: () =>
                                    setState(() => _expanded = !_expanded),
                              ),
                              if (!empty)
                                const Padding(
                                  padding: EdgeInsets.fromLTRB(16, 20, 16, 6),
                                  child: Text(
                                    'Available mentors',
                                    style: TextStyle(
                                      color: _appColor,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              for (final mentor in _mentors)
                                MentorCard(
                                  key: ValueKey(mentor.id),
                                  mentor: mentor,
                                  api: widget.api,
                                ),
                            ],
                          ),
                        ),
                      if (empty)
                        Center(
                          child: Text(
                            _filters.hasApplied
                                ? 'No mentors match your search.'
                                : 'No PG talks available at the moment.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: _secondary,
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      if (_loading && _page == 1)
                        const Center(
                          child: CircularProgressIndicator(color: Colors.black),
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

class _MentorHeader extends StatelessWidget {
  const _MentorHeader({
    required this.onSearch,
    required this.onFavourites,
    required this.onWallet,
  });

  final VoidCallback onSearch;
  final VoidCallback onFavourites;
  final VoidCallback onWallet;

  Widget _box(String label, String icon, Color tint, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Semantics(
        label: label,
        button: true,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _allIndia,
              // The stroke matches the fill, so it only adds the 1dp the
              // native background draws inside the padding.
              borderRadius: BorderRadius.circular(4),
            ),
            child: SvgPicture.asset(
              'assets/icons/$icon.svg',
              width: 20,
              height: 20,
              colorFilter: ColorFilter.mode(tint, BlendMode.srcIn),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _state,
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          const SizedBox(width: 20),
          const Expanded(
            child: Text(
              'Mentor',
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          _box('Search', 'ic_baseline_search_24', _state, onSearch),
          _box(
            'Favourites',
            'ic_heart_filled',
            AppColors.primary,
            onFavourites,
          ),
          _box('Wallet', 'connect_premium_selected', _state, onWallet),
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.expanded, required this.onToggle});

  final bool expanded;
  final VoidCallback onToggle;

  static const _text =
      'Get real, verified hospital insights from current residents and faculty — including daily OPD load, MRI/CT/Ultrasound availability, surgery volume, hospital and ICU beds, monthly deliveries, academic exposure, and branchwise clinical performance — to make better NEET PG choice filling decisions.';

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF4EE),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Talk Directly with PGs & Faculty',
            style: TextStyle(
              color: _state,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _text,
            maxLines: expanded ? null : 3,
            overflow: expanded ? null : TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF4B5563),
              fontSize: 13,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                expanded ? 'Read less' : 'Read more',
                style: const TextStyle(
                  color: _state,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// row_listof_counselor.xml with ListOfCounselorsAdapter's behaviour.
class MentorCard extends StatefulWidget {
  const MentorCard({
    super.key,
    required this.mentor,
    required this.api,
    this.onFavouriteChanged,
  });

  final Mentor mentor;
  final CollegeGuideApiRepository api;

  /// Favourites screen: un-liking removes the card.
  final void Function(Mentor mentor, bool liked)? onFavouriteChanged;

  @override
  State<MentorCard> createState() => _MentorCardState();
}

class _MentorCardState extends State<MentorCard> {
  static const _collapsed = 3;
  bool _expanded = false;

  Mentor get m => widget.mentor;

  /// The heart flips at once; it flips back if the server refuses.
  Future<void> _toggleFavourite() async {
    final liked = !m.liked;
    setState(() => m.liked = liked);
    widget.onFavouriteChanged?.call(m, liked);
    try {
      await widget.api.send(
        'POST',
        'college/fevorite-counsellor/',
        body: {'counsellor_id': m.id, 'like_status': liked},
      );
      if (!mounted) return;
      showToast(
        context,
        liked ? 'Added to favourites' : 'Removed from favourites',
      );
    } on CollegeGuideApiException catch (e) {
      if (!mounted) return;
      setState(() => m.liked = !liked);
      widget.onFavouriteChanged?.call(m, !liked);
      showToast(
        context,
        e.statusCode == null
            ? 'Check your internet and try again.'
            : (liked
                  ? "Couldn't add to favourites"
                  : "Couldn't remove from favourites"),
      );
    }
  }

  Widget _chip(String text, {bool more = false, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 6, top: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: more ? _state : const Color(0xFFEEF5F1),
          borderRadius: BorderRadius.circular(360),
        ),
        child: Text(
          text,
          maxLines: 1,
          style: TextStyle(
            color: more ? Colors.white : _state,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final college = m.speciality != null
        ? '${m.speciality} • ${m.instituteName}'
        : m.instituteName;
    final location = m.degree.isEmpty ? college : '$college • ${m.degree}';
    final shown = _expanded
        ? m.expertise.length
        : m.expertise.length.clamp(0, _collapsed);
    final hidden = m.expertise.length - shown;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 92,
                  height: 112,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _MentorImage(url: m.image),
                      if (m.available != null)
                        Positioned(
                          left: 6,
                          top: 6,
                          child: _AvailabilityBadge(available: m.available!),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Packed chain: the name ellipsizes only when the
                        // name + tick no longer fit before the heart.
                        Expanded(
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  m.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: _appColor,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              SvgPicture.asset(
                                'assets/icons/ic_verified.svg',
                                width: 16,
                                height: 16,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Semantics(
                          button: true,
                          label: m.liked
                              ? 'Remove from favourites'
                              : 'Add to favourites',
                          child: GestureDetector(
                            onTap: _toggleFavourite,
                            child: SvgPicture.asset(
                              m.liked
                                  ? 'assets/icons/ic_heart_filled.svg'
                                  : 'assets/icons/ic_heart_outline.svg',
                              width: 22,
                              height: 22,
                              colorFilter: ColorFilter.mode(
                                m.liked ? AppColors.primary : _secondary,
                                BlendMode.srcIn,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (m.designation.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          m.designation,
                          style: const TextStyle(
                            color: _state,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: SvgPicture.asset(
                            'assets/icons/ic_building.svg',
                            width: 14,
                            height: 14,
                            colorFilter: const ColorFilter.mode(
                              _secondary,
                              BlendMode.srcIn,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            location,
                            style: const TextStyle(
                              color: _secondary,
                              fontSize: 12,
                              height: 1.4,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // The native layout's fixed text (the adapter never sets it).
                    const Text(
                      '⭐ 4.9 (256)   👥 320 Students Guided ',
                      style: TextStyle(
                        color: _appColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (m.expertise.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(
                children: [
                  for (var i = 0; i < shown; i++) _chip(m.expertise[i]),
                  if (hidden > 0 ||
                      (_expanded && m.expertise.length > _collapsed))
                    _chip(
                      hidden > 0 ? '+$hidden more' : 'Show less',
                      more: true,
                      onTap: () => setState(() => _expanded = hidden > 0),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 14),
          Material(
            color: _state,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              splashColor: const Color(0x33FFFFFF),
              onTap: () => confirmAndCallMentor(context, widget.api, m),
              child: SizedBox(
                height: 46,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SvgPicture.asset(
                      'assets/icons/phone_in_talk.svg',
                      width: 18,
                      height: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Call now ₹${m.fee} (${m.duration})',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MentorImage extends StatelessWidget {
  const _MentorImage({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    const placeholder = Image(
      image: AssetImage('assets/images/home/iv_mirror.png'),
      fit: BoxFit.cover,
    );
    final source = url;
    if (source == null || source.isEmpty) return placeholder;
    return CachedNetworkImage(
      imageUrl: source,
      fit: BoxFit.cover,
      placeholder: (_, _) => const ColoredBox(color: Color(0xFFEEEEEE)),
      errorWidget: (_, _, _) => placeholder,
    );
  }
}

class _AvailabilityBadge extends StatelessWidget {
  const _AvailabilityBadge({required this.available});

  final bool available;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: available ? const Color(0xFFDCFCE7) : const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(360),
        border: Border.all(
          color: available ? const Color(0xFF86EFAC) : _stroke,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: available
                  ? const Color(0xFF22C55E)
                  : const Color(0xFF9CA3AF),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            available ? 'Online' : 'Offline',
            style: TextStyle(
              color: available ? const Color(0xFF15803D) : _secondary,
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ---- Favourite Mentors (FavoriteCounsellorsActivity) --------------------------------

class FavouriteMentorsPage extends StatefulWidget {
  const FavouriteMentorsPage({super.key, required this.api});

  final CollegeGuideApiRepository api;

  @override
  State<FavouriteMentorsPage> createState() => _FavouriteMentorsPageState();
}

class _FavouriteMentorsPageState extends State<FavouriteMentorsPage> {
  static const _pageLimit = 10;
  final _scroll = ScrollController();
  final List<Mentor> _mentors = [];
  int _page = 1;
  int _totalPages = 1;
  int _request = 0;
  bool _loading = false;
  bool _changed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (!_loading &&
          _page < _totalPages &&
          _scroll.position.extentAfter < 400) {
        _page++;
        _load(fresh: false);
      }
    });
    _load(fresh: true);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({required bool fresh}) async {
    if (fresh) _page = 1;
    final request = ++_request;
    setState(() => _loading = true);
    try {
      final json = await widget.api.send(
        'GET',
        'college/fevorite-counsellor/',
        query: {'page': '$_page', 'limit': '$_pageLimit'},
      );
      if (!mounted || request != _request) return;
      final data = json['data'] as Map<String, dynamic>? ?? const {};
      setState(() {
        _error = null;
        _totalPages = (data['total_page'] as num?)?.toInt() ?? 1;
        if (fresh) _mentors.clear();
        _mentors.addAll([
          for (final r in (data['results'] as List? ?? const []))
            if (r is Map<String, dynamic>) Mentor(r),
        ]);
      });
    } on CollegeGuideApiException {
      if (!mounted || request != _request) return;
      if (!fresh) _page--;
      const message = "Couldn't load your favourite mentors";
      if (_mentors.isEmpty) {
        setState(() => _error = message);
      } else {
        showToast(context, message);
      }
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final empty = !_loading && _mentors.isEmpty;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          statusBarColor: _state,
          statusBarIconBrightness: Brightness.light,
        ),
        child: Scaffold(
          backgroundColor: _state,
          body: SafeArea(
            child: ColoredBox(
              color: const Color(0xFFF6FAF7),
              child: Column(
                children: [
                  Container(
                    color: _state,
                    constraints: const BoxConstraints(minHeight: 56),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      children: [
                        const SizedBox(width: 4),
                        Semantics(
                          label: 'Back',
                          button: true,
                          child: InkResponse(
                            onTap: () => Navigator.of(context).pop(_changed),
                            child: Padding(
                              padding: const EdgeInsets.all(9),
                              child: SvgPicture.asset(
                                'assets/icons/ic_baseline_arrow_back_24.svg',
                                width: 22,
                                height: 22,
                                colorFilter: const ColorFilter.mode(
                                  Colors.white,
                                  BlendMode.srcIn,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'Favourite Mentors',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Stack(
                      children: [
                        RefreshIndicator(
                          color: _state,
                          onRefresh: () => _load(fresh: true),
                          child: ListView(
                            controller: _scroll,
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.only(top: 12, bottom: 16),
                            children: [
                              for (final mentor in _mentors)
                                MentorCard(
                                  key: ValueKey(mentor.id),
                                  mentor: mentor,
                                  api: widget.api,
                                  onFavouriteChanged: (m, liked) {
                                    _changed = true;
                                    setState(() {
                                      if (!liked) {
                                        _mentors.removeWhere(
                                          (x) => x.id == m.id,
                                        );
                                      } else if (!_mentors.contains(m)) {
                                        _mentors.add(m);
                                      }
                                    });
                                  },
                                ),
                            ],
                          ),
                        ),
                        if (empty)
                          Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 32,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 64,
                                    height: 64,
                                    padding: const EdgeInsets.all(18),
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFE6EEEA),
                                      shape: BoxShape.circle,
                                    ),
                                    child: SvgPicture.asset(
                                      'assets/icons/ic_heart_outline.svg',
                                      colorFilter: const ColorFilter.mode(
                                        AppColors.primary,
                                        BlendMode.srcIn,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    _error != null
                                        ? "Couldn't load favourites"
                                        : 'No favourite mentors yet',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: _appColor,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    _error ?? "Tap the heart on a mentor's card to save them here.",
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: _secondary,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        if (_loading && _mentors.isEmpty)
                          const Center(
                            child: CircularProgressIndicator(
                              color: Colors.black,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---- Find a Mentor sheet ------------------------------------------------------------

class _Option {
  _Option(this.name);

  final String name;
  bool selected = false;
}

/// The selections and option lists, kept across sheet openings like the
/// native fragment's fields.
class _MentorFilters {
  static const hints = [
    'Select States',
    'Select Colleges',
    'Select Specializations',
    'Select Degrees',
  ];

  /// states, colleges, specialities, degrees.
  final options = <List<_Option>>[
    [],
    [],
    [],
    [
      for (final d in ['DNB', 'Diploma', 'M.Ch', 'MD', 'MS', 'Nbems DMRD'])
        _Option(d),
    ],
  ];

  /// What the list is filtered by (sent as states, institute_names, ...).
  final applied = <List<String>>[[], [], [], []];

  bool loadingStates = false;
  bool loadingSpecs = false;
  bool loadingColleges = false;
  int collegesRequest = 0;

  bool get hasApplied => applied.any((a) => a.isNotEmpty);

  List<String> selected(int i) => [
    for (final o in options[i])
      if (o.selected) o.name,
  ];
}

class _SearchMentorSheet extends StatefulWidget {
  const _SearchMentorSheet({required this.api, required this.filters});

  final CollegeGuideApiRepository api;
  final _MentorFilters filters;

  @override
  State<_SearchMentorSheet> createState() => _SearchMentorSheetState();
}

class _SearchMentorSheetState extends State<_SearchMentorSheet> {
  _MentorFilters get f => widget.filters;
  int? _open;

  /// Where each field's floating options (PopupWindow) hang from.
  final _links = List.generate(4, (_) => LayerLink());

  @override
  void initState() {
    super.initState();
    _loadOptions();
  }

  Future<List<_Option>> _fetch(
    String method,
    String endpoint, [
    Map<String, Object?>? body,
  ]) async {
    try {
      final json = await widget.api.send(method, endpoint, body: body);
      final data = json['data'] as Map<String, dynamic>? ?? const {};
      return [
        for (final r in (data['results'] as List? ?? const []))
          if (r is Map && r['name'] != null) _Option('${r['name']}'),
      ];
    } on CollegeGuideApiException {
      return [];
    }
  }

  /// States and specializations load once; a failed load retries later.
  void _loadOptions() {
    if (f.options[0].isEmpty && !f.loadingStates) {
      f.loadingStates = true;
      _fetch('GET', 'college/counsellor/drop-down/state/').then((items) {
        f.loadingStates = false;
        f.options[0]
          ..clear()
          ..addAll(items);
        if (mounted) setState(() {});
      });
    }
    if (f.options[1].isEmpty && !f.loadingColleges) _reloadColleges();
    if (f.options[2].isEmpty && !f.loadingSpecs) {
      f.loadingSpecs = true;
      _fetch('GET', 'college/counsellor/drop-down/speciality/').then((items) {
        f.loadingSpecs = false;
        f.options[2]
          ..clear()
          ..addAll(items);
        if (mounted) setState(() {});
      });
    }
  }

  /// All colleges with no state picked, else the picked states' institutes;
  /// colleges still listed stay ticked.
  void _reloadColleges() {
    final request = ++f.collegesRequest;
    f.loadingColleges = true;
    final keep = f.selected(1).toSet();
    _fetch('POST', 'college/states/institute-list/', {
      'states': f.selected(0),
    }).then((items) {
      if (request != f.collegesRequest) return;
      f.loadingColleges = false;
      final seen = <String>{};
      f.options[1]
        ..clear()
        ..addAll([
          for (final o in items)
            if (seen.add(o.name)) o..selected = keep.contains(o.name),
        ]);
      if (mounted) setState(() {});
    });
  }

  void _tapField(int i) {
    if (_open == i) {
      setState(() => _open = null);
      return;
    }
    if (f.options[i].isEmpty) {
      final message = switch (i) {
        0 => 'Loading states…',
        1 => f.loadingColleges ? 'Loading colleges…' : 'No colleges found',
        _ => 'Loading specializations…',
      };
      showToast(context, message);
      _loadOptions();
      return;
    }
    setState(() => _open = i);
  }

  void _toggle(int field, _Option option) {
    setState(() => option.selected = !option.selected);
    if (field == 0) _reloadColleges();
  }

  String _value(int i) {
    final s = f.selected(i);
    if (s.isEmpty) return '';
    if (s.length <= 2) return s.join(', ');
    return '${s.first} +${s.length - 1} more';
  }

  bool get _canSubmit =>
      List.generate(4, f.selected).any((s) => s.isNotEmpty) || f.hasApplied;

  @override
  Widget build(BuildContext context) {
    // getDisplayMetrics().heightPixels leaves out the status bar.
    final height =
        MediaQuery.sizeOf(context).height -
        MediaQueryData.fromView(View.of(context)).viewPadding.top;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // The sheet draws behind the navigation bar.
      value: const SystemUiOverlayStyle(
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Container(
        constraints: BoxConstraints(minHeight: height * 0.85),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: height * 0.85,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 10),
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD9D9D9),
                      borderRadius: BorderRadius.circular(360),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Find a Mentor',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            for (final list in f.options) {
                              for (final o in list) {
                                o.selected = false;
                              }
                            }
                            _open = null;
                          });
                          _reloadColleges();
                        },
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Text(
                            'Clear all',
                            style: TextStyle(
                              color: _state,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Semantics(
                        label: 'Close',
                        button: true,
                        child: GestureDetector(
                          onTap: () => Navigator.of(context).pop(false),
                          child: SvgPicture.asset(
                            'assets/icons/ic_baseline_close.svg',
                            width: 24,
                            height: 24,
                            colorFilter: const ColorFilter.mode(
                              Colors.black,
                              BlendMode.srcIn,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 4, 20, 0),
                  child: Text(
                    'Get college & branch insights directly from seniors living your dream seat',
                    style: TextStyle(
                      color: Color(0xFF5F6B66),
                      fontSize: 13,
                      // Inter's own line height, as the native TextView.
                      height: 1.21,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const Divider(
                  height: 1,
                  thickness: 1,
                  color: Color(0xFFE6E6E6),
                ),
                Expanded(
                  child: Stack(
                    children: [
                      SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                        child: Column(
                          children: [
                            for (var i = 0; i < 4; i++)
                              _FilterField(
                                hint: _MentorFilters.hints[i],
                                value: _value(i),
                                open: _open == i,
                                onTap: () => _tapField(i),
                                link: _links[i],
                                dropdown: null,
                              ),
                          ],
                        ),
                      ),
                      if (_open != null) ...[
                        // A touch outside the popup dismisses it.
                        Positioned.fill(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => setState(() => _open = null),
                          ),
                        ),
                        Positioned(
                          left: 20,
                          right: 20,
                          top: 0,
                          child: CompositedTransformFollower(
                            link: _links[_open!],
                            showWhenUnlinked: false,
                            targetAnchor: Alignment.bottomLeft,
                            child: _OptionsCard(
                              options: f.options[_open!],
                              onToggle: (o) => _toggle(_open!, o),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: Opacity(
                    opacity: _canSubmit ? 1 : 0.4,
                    child: Material(
                      color: _state,
                      borderRadius: BorderRadius.circular(360),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(360),
                        onTap: _canSubmit
                            ? () {
                                for (var i = 0; i < 4; i++) {
                                  f.applied[i] = f.selected(i);
                                }
                                Navigator.of(context).pop(true);
                              }
                            : null,
                        child: const SizedBox(
                          height: 50,
                          width: double.infinity,
                          child: Center(
                            child: Text(
                              'Submit',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
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

/// layout_mentor_filter_field: an outlined dropdown whose label sits on the
/// top border once it is open or has a value.
class _FilterField extends StatelessWidget {
  const _FilterField({
    required this.hint,
    required this.value,
    required this.open,
    required this.onTap,
    required this.link,
    required this.dropdown,
  });

  final LayerLink link;

  final String hint;
  final String value;
  final bool open;
  final VoidCallback onTap;
  final Widget? dropdown;

  @override
  Widget build(BuildContext context) {
    final showLabel = open || value.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: CompositedTransformTarget(
                  link: link,
                  child: GestureDetector(
                    onTap: onTap,
                    child: Container(
                      height: 52,
                      padding: const EdgeInsets.only(left: 16, right: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF4F9F1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: open ? _state : const Color(0xFFC9D3BF),
                          width: open ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              showLabel ? value : hint,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _state,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          Transform.rotate(
                            angle: open ? 3.14159 : 0,
                            child: SvgPicture.asset(
                              'assets/icons/ic_baseline_arrow_drop_down_24.svg',
                              width: 24,
                              height: 24,
                              colorFilter: const ColorFilter.mode(
                                _state,
                                BlendMode.srcIn,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (showLabel)
                Positioned(
                  left: 12,
                  top: 0,
                  child: Container(
                    height: 16,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: [0.5, 0.5],
                        colors: [Colors.white, Color(0xFFF4F9F1)],
                      ),
                    ),
                    child: Text(
                      hint,
                      style: const TextStyle(
                        color: _state,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          ?dropdown,
        ],
      ),
    );
  }
}

/// popup_mentor_filter_options: a card of checkbox rows under the field.
class _OptionsCard extends StatelessWidget {
  const _OptionsCard({required this.options, required this.onToggle});

  final List<_Option> options;
  final ValueChanged<_Option> onToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      constraints: const BoxConstraints(maxHeight: 300),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFFDCE3D8)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 6,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 4),
        children: [
          for (final o in options)
            InkWell(
              onTap: () => onToggle(o),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                child: Row(
                  children: [
                    IgnorePointer(
                      child: Checkbox(
                        value: o.selected,
                        onChanged: (_) {},
                        activeColor: _state,
                        side: const BorderSide(color: _state, width: 2),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        o.name,
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
