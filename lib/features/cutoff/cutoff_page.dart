import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/native_bridge.dart';
import '../../theme/app_theme.dart';
import '../home/college_guide_api.dart';

/// The Cutoff tab — a port of the native CollegehomeTabsFragment
/// (fragment_collegehome_tabs.xml) with its three pages: Colleges
/// (CollegesFragment), CutOffs & Matchings (CollegeMyRankMatchFragement) and
/// Allotments (CollegeAllotmentsFragment), plus the Filters sheet.
class CutoffPage extends StatefulWidget {
  const CutoffPage({
    super.key,
    required this.apiRepository,
    required this.isSubscribed,
    required this.selectedTab,
    required this.onTabSelected,
    required this.onOpenMentor,
    required this.onOpenPremium,
    required this.onOpenPackages,
  });

  final CollegeGuideApiRepository apiRepository;
  final bool isSubscribed;
  final int selectedTab;
  final ValueChanged<int> onTabSelected;
  final VoidCallback onOpenMentor;
  final VoidCallback onOpenPremium;

  /// CollegePackagesActivity ("Go Premium to Apply").
  final VoidCallback onOpenPackages;

  @override
  State<CutoffPage> createState() => _CutoffPageState();
}

const _state = Color(0xFF1E4B3E);
const _allIndia = Color(0xFFE0FFC2);
const _appColor = Color(0xFF12151B);
const _b47 = Color(0xFF474747);
const _grey666 = Color(0xFF666666);
const _filterMuted = Color(0xFFF4F5F7);
const _filterDivider = Color(0xFFECEDF0);
const _filterSecondary = Color(0xFF6B7280);
const _filterStroke = Color(0xFFE3E5E8);

class _CutoffPageState extends State<CutoffPage> {
  late final _filters = _FilterState(widget.apiRepository);

  /// mapParams: only the counselling type, used by the header toggle — so
  /// switching AIC/SC there drops the applied filters, as natively.
  final Map<String, String> _mapParams = {'councelling_type': 'AIC'};

  /// filtermapParams: kept across Applies; each Apply builds on the last.
  final Map<String, String> _filterParams = {};

  /// The params the pages are showing.
  Map<String, String> _params = {'councelling_type': 'AIC'};

  /// Bumped whenever the pages must be recreated with new params, like the
  /// native setupViewPagerAndTabs() making a new adapter.
  int _generation = 0;
  final Set<int> _visited = {};

  static const _tabs = ['Colleges', 'CutOffs & Matchings', 'Allotments'];

  @override
  void initState() {
    super.initState();
    _filters.loadHomeFilters();
  }

  void _setCounselling(String type) {
    setState(() {
      _filters.counselling = type;
      _mapParams['councelling_type'] = type;
      _params = Map.of(_mapParams);
      _generation++;
      _visited.clear();
    });
    // The recreated CollegesFragment calls setAPICallForHomeFilters().
    _filters.loadHomeFilters();
  }

  Future<void> _openFilters() async {
    // Natively 85% of DisplayMetrics.heightPixels (the display less the
    // navigation bar); elsewhere 85% of the screen.
    final px = await displayHeight();
    if (!mounted) return;
    final screen = MediaQuery.sizeOf(context).height;
    final ratio = MediaQuery.devicePixelRatioOf(context);
    final sheetHeight = (px != null ? px / ratio : screen) * 0.85;
    final params = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (_) => _FilterSheet(
        filters: _filters,
        height: sheetHeight,
        isSubscribed: widget.isSubscribed,
        currentParams: _filterParams,
        onGoPremium: () {
          Navigator.of(context).pop();
          widget.onOpenPackages();
        },
      ),
    );
    if (params == null || !mounted) return;
    setState(() {
      _filterParams
        ..clear()
        ..addAll(params);
      _params = Map.of(params);
      _generation++;
      _visited.clear();
    });
    _filters.loadHomeFilters();
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.selectedTab.clamp(0, 2);
    _visited.add(selected);
    final type = _params['councelling_type'] ?? 'AIC';
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: _state,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: ColoredBox(
        // Behind the status bar (Android 15+ draws edge to edge) and the
        // header: the colour the native tab sets for its status bar.
        color: _state,
        child: SafeArea(
          bottom: false,
          child: ColoredBox(
            color: const Color(0xFFF5F5F5),
            child: Column(
              key: const Key('collegeScreen'),
              children: [
                _Header(
                  counselling: type,
                  tabs: _tabs,
                  selectedTab: selected,
                  onCounselling: _setCounselling,
                  onFilter: _openFilters,
                  onTabSelected: widget.onTabSelected,
                ),
                Expanded(
                  child: IndexedStack(
                    index: selected,
                    children: [
                      for (var i = 0; i < 3; i++)
                        if (!_visited.contains(i))
                          const SizedBox.shrink()
                        else if (i == 0)
                          _CollegesPage(
                            key: ValueKey('colleges-$_generation'),
                            api: widget.apiRepository,
                            params: {..._params, 'query': 'institute'},
                            isSubscribed: widget.isSubscribed,
                            onOpenMentor: widget.onOpenMentor,
                            onOpenPremium: widget.onOpenPremium,
                            onDefaultState: _filters.setDefaultState,
                          )
                        else
                          _WebListPage(
                            key: ValueKey('web-$i-$_generation'),
                            api: widget.apiRepository,
                            path: i == 1
                                ? 'college/rank-matching/webview/'
                                : 'college/allotment/webview/',
                            noData: i == 1
                                ? 'No cutoffs and matchings found. Pull down to refresh.'
                                : 'No allotments found. Pull down to refresh.',
                            params: _params,
                            isSubscribed: widget.isSubscribed,
                            onOpenPremium: widget.onOpenPremium,
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

// ---- Header -----------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({
    required this.counselling,
    required this.tabs,
    required this.selectedTab,
    required this.onCounselling,
    required this.onFilter,
    required this.onTabSelected,
  });

  final String counselling;
  final List<String> tabs;
  final int selectedTab;
  final ValueChanged<String> onCounselling;
  final VoidCallback onFilter;
  final ValueChanged<int> onTabSelected;

  static final _track = BoxDecoration(
    color: const Color(0x1AFFFFFF),
    border: Border.all(color: const Color(0x40FFFFFF)),
    borderRadius: BorderRadius.circular(12),
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _state,
      width: double.infinity,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Container(
                      decoration: _track,
                      padding: const EdgeInsets.all(3),
                      child: Row(
                        children: [
                          _Toggle(
                            label: 'All India Counselling',
                            selected: counselling == 'AIC',
                            onTap: () => onCounselling('AIC'),
                          ),
                          _Toggle(
                            label: 'State Counselling',
                            selected: counselling == 'SC',
                            onTap: () => onCounselling('SC'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: onFilter,
                      borderRadius: BorderRadius.circular(12),
                      child: Ink(
                        decoration: _track,
                        padding: const EdgeInsets.only(left: 10, right: 12),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SvgPicture.asset(
                              'assets/icons/ic_baseline_filter.svg',
                              width: 18,
                              height: 18,
                              colorFilter: const ColorFilter.mode(
                                _allIndia,
                                BlendMode.srcIn,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              'Filter',
                              style: TextStyle(
                                color: _allIndia,
                                fontSize: 13,
                                height: 1.21,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 44,
            width: double.infinity,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              // tabContentStart 19dp less the first tab's 12dp padding.
              padding: const EdgeInsets.only(left: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < tabs.length; i++)
                    _Tab(
                      label: tabs[i],
                      selected: i == selectedTab,
                      onTap: () => onTabSelected(i),
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

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 36,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: selected ? _allIndia : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          // autoSize 12sp down to 10sp.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              style: TextStyle(
                color: selected ? _state : Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A TabLayout tab: 12dp side padding, Inter Bold 13sp, a 3dp all_india
/// indicator as wide as the text.
class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      splashColor: const Color(0x1FFFFFFF),
      highlightColor: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : const Color(0xA6FFFFFF),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (selected)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  height: 3,
                  decoration: const BoxDecoration(
                    color: _allIndia,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(3),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---- Colleges page (CollegesFragment) ---------------------------------------------

class _CollegesPage extends StatefulWidget {
  const _CollegesPage({
    super.key,
    required this.api,
    required this.params,
    required this.isSubscribed,
    required this.onOpenMentor,
    required this.onOpenPremium,
    required this.onDefaultState,
  });

  final CollegeGuideApiRepository api;
  final Map<String, String> params;
  final bool isSubscribed;
  final VoidCallback onOpenMentor;
  final VoidCallback onOpenPremium;
  final void Function(String? state, String? counselling) onDefaultState;

  @override
  State<_CollegesPage> createState() => _CollegesPageState();
}

class _CollegesPageState extends State<_CollegesPage> {
  final _scroll = ScrollController();
  final List<Map<String, dynamic>> _colleges = [];
  late Map<String, String> _currentParams = widget.params;
  int _page = 1;
  int _totalPages = 1;
  int _request = 0;
  int _examRank = 0;
  String _counselling = 'AIC';
  String _filterBy = '';
  bool _loading = false;
  bool _firstLoad = true;
  bool _loaded = false;

  /// Subscribers page through every college (30 a page); free users see 3
  /// and the Go Premium footer.
  int get _limit => widget.isSubscribed ? 30 : 3;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoadMore);
    _load(widget.params, 1);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    if (!widget.isSubscribed || _loading || _page >= _totalPages) return;
    // Next page a couple of cards before the end.
    if (_scroll.position.extentAfter < 600) _load(_currentParams, _page + 1);
  }

  Future<void> _load(Map<String, String> params, int page) async {
    final fresh = page == 1;
    if (fresh) {
      _request++;
      _currentParams = params;
    }
    final request = _request;
    setState(() {
      _loading = true;
      if (fresh && _firstLoad) _colleges.clear();
    });
    try {
      final data = await widget.api.collegeHomePage(
        page: page,
        limit: _limit,
        params: params,
      );
      if (!mounted || request != _request) return;
      final results = [
        for (final r in (data['results'] as List? ?? const []))
          if (r is Map<String, dynamic>) r,
      ];
      setState(() {
        _page = page;
        _totalPages = (data['total_page'] as num?)?.toInt() ?? 1;
        if (fresh) {
          _applyDefaultParameter(data['default_parameter']);
          _colleges
            ..clear()
            ..addAll(results);
        } else {
          _colleges.addAll(results);
        }
      });
    } on CollegeGuideApiException {
      if (!mounted || request != _request) return;
      showToast(
        context,
        fresh
            ? 'Couldn\'t load colleges. Check your internet and try again.'
            : 'Couldn\'t load more colleges',
      );
    } finally {
      if (mounted && request == _request) {
        setState(() {
          _loading = false;
          _firstLoad = false;
          _loaded = true;
        });
      }
    }
  }

  void _applyDefaultParameter(Object? value) {
    if (value is! Map<String, dynamic>) return;
    _examRank = (value['rank'] as num?)?.toInt() ?? 0;
    _counselling = value['councelling_type'] as String? ?? _counselling;
    final state = value['state'] as String?;
    final category = value['category'] ?? '';
    widget.onDefaultState(state, value['councelling_type'] as String?);
    if (_counselling == 'AIC') {
      _filterBy = 'Filter By: AIC/$category';
    } else if (state != null && state.isNotEmpty) {
      _filterBy = 'Filter By: $state/$category';
    } else {
      _filterBy = 'Filter By: $category';
    }
  }

  Future<void> _askRank() async {
    final rank = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _EnterRankDialog(),
    );
    if (rank == null || !mounted) return;
    _load({
      'councelling_type': _counselling,
      'query': 'institute',
      'rank': rank,
    }, 1);
  }

  void _openDetails(Map<String, dynamic> college) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CollegeDetailsWebPage(
          api: widget.api,
          collegeId: college['id'] as String? ?? '',
          counselling: _counselling,
        ),
      ),
    );
  }

  void _openCutoffSheet(Map<String, dynamic> college) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (context) => _CutoffSheet(
        api: widget.api,
        college: college,
        counselling: _counselling,
        isSubscribed: widget.isSubscribed,
        onGoPremium: () {
          Navigator.of(context).pop();
          widget.onOpenPremium();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final showFooterPremium = !widget.isSubscribed && _colleges.isNotEmpty;
    final loadingMore = _loading && _page >= 1 && _colleges.isNotEmpty;
    return ColoredBox(
      color: _state,
      child: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () => _load(_currentParams, 1),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(19, 10, 16, 0),
                  child: Text(
                    _filterBy,
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ),
                const SizedBox(height: 2),
                Expanded(
                  child: ListView.builder(
                    controller: _scroll,
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 80),
                    itemCount:
                        _colleges.length +
                        (loadingMore || showFooterPremium ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _colleges.length) {
                        return _ListFooter(
                          loading: loadingMore,
                          showPremium: showFooterPremium && !loadingMore,
                          onPremium: widget.onOpenPremium,
                        );
                      }
                      final college = _colleges[index];
                      return _CollegeCard(
                        college: college,
                        examRank: _examRank,
                        isSubscribed: widget.isSubscribed,
                        onOpen: () => _openDetails(college),
                        onCutoffRow: () =>
                            _examRank == 0 ? _askRank() : _openDetails(college),
                        onMore: () {
                          if (!widget.isSubscribed) {
                            showToast(
                              context,
                              'Subscribe to unlock more cutoffs',
                            );
                            return;
                          }
                          _openCutoffSheet(college);
                        },
                        onCall: widget.onOpenMentor,
                      );
                    },
                  ),
                ),
              ],
            ),
            if (_loaded && !_loading && _colleges.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'We couldn’t find any colleges matching your search.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            if (_loading && _colleges.isEmpty)
              const Center(child: CircularProgressIndicator(color: _allIndia)),
          ],
        ),
      ),
    );
  }
}

class _ListFooter extends StatelessWidget {
  const _ListFooter({
    required this.loading,
    required this.showPremium,
    required this.onPremium,
  });

  final bool loading;
  final bool showPremium;
  final VoidCallback onPremium;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          if (loading)
            const SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(color: _allIndia),
            ),
          if (showPremium)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: _PremiumPrompt(
                textColor: Colors.white,
                buttonColor: const Color(0xFFFFC812),
                buttonTextColor: Colors.black,
                onTap: onPremium,
              ),
            ),
        ],
      ),
    );
  }
}

/// "To Unlock Cutoff & Matching" + "Go Premium".
class _PremiumPrompt extends StatelessWidget {
  const _PremiumPrompt({
    required this.textColor,
    required this.buttonColor,
    required this.buttonTextColor,
    required this.onTap,
  });

  final Color textColor;
  final Color buttonColor;
  final Color buttonTextColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'To Unlock Cutoff & Matching',
            style: TextStyle(color: textColor, fontSize: 15),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(
              color: buttonColor,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.white, width: 0.5),
            ),
            child: Text(
              'Go Premium',
              style: TextStyle(
                color: buttonTextColor,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// row_rankwise_colleges.xml.
class _CollegeCard extends StatelessWidget {
  const _CollegeCard({
    required this.college,
    required this.examRank,
    required this.isSubscribed,
    required this.onOpen,
    required this.onCutoffRow,
    required this.onMore,
    required this.onCall,
  });

  final Map<String, dynamic> college;
  final int examRank;
  final bool isSubscribed;
  final VoidCallback onOpen;
  final VoidCallback onCutoffRow;
  final VoidCallback onMore;
  final VoidCallback onCall;

  static String _s(Object? v) => v == null ? '' : '$v';

  @override
  Widget build(BuildContext context) {
    final cutoffs = [
      for (final c in (college['cutoff'] as List? ?? const []))
        if (c is Map<String, dynamic>) c,
    ];
    return Padding(
      // cardUseCompatPadding for the 3dp elevation.
      padding: const EdgeInsets.symmetric(horizontal: 6.5, vertical: 8),
      child: Material(
        color: Colors.white,
        elevation: 3,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 12, top: 6),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.asset(
                          'assets/images/home/iv_rank_image.jpg',
                          width: 55,
                          height: 55,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _s(college['name']),
                              style: const TextStyle(
                                color: _state,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                SvgPicture.asset(
                                  'assets/icons/location_on.svg',
                                  width: 14,
                                  height: 14,
                                  colorFilter: const ColorFilter.mode(
                                    _state,
                                    BlendMode.srcIn,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                // The native adapter never sets this view, so
                                // every card shows the layout's placeholder.
                                const Text(
                                  'Patancheruvu Hyderabad ',
                                  style: TextStyle(
                                    color: _state,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                Container(
                  margin: const EdgeInsets.fromLTRB(10, 10, 10, 0),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F7FB),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0xFFF5F5F5),
                      width: 0.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      _Stat(
                        icon: 'currency_rupee_circle_24px',
                        value: _s(college['course_fee']),
                        label: 'Tuition Fees',
                      ),
                      const _StatDivider(),
                      _Stat(
                        icon: 'ic_bond_year',
                        value: _s(college['bond_year']),
                        label: 'Bond Year',
                      ),
                      const _StatDivider(),
                      _Stat(
                        icon: 'ic_bond_penalty',
                        value: _s(college['bond_penalty']),
                        label: 'Bond Penalty',
                      ),
                      const _StatDivider(),
                      _Stat(
                        icon: 'currency_rupee_circle_24px',
                        value: _s(college['stipend']),
                        label: 'Stipend',
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: _CutoffTable(
                    cutoffs: cutoffs,
                    examRank: examRank,
                    isSubscribed: isSubscribed,
                    onRow: onCutoffRow,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Row(
                    children: [
                      if (cutoffs.isNotEmpty) ...[
                        const SizedBox(width: 10),
                        Expanded(
                          child: _CardButton(
                            icon: isSubscribed
                                ? 'ic_baseline_lock_open_24'
                                : 'ic_baseline_lock_24',
                            label: 'See more CutOFF',
                            weight: FontWeight.w500,
                            onTap: onMore,
                          ),
                        ),
                        const SizedBox(width: 12),
                      ] else
                        const SizedBox(width: 10),
                      Expanded(
                        child: _CardButton(
                          icon: 'phone_in_talk',
                          label: 'Call Counsellor',
                          weight: FontWeight.w700,
                          onTap: onCall,
                        ),
                      ),
                      const SizedBox(width: 10),
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

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.value, required this.label});

  final String icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2, right: 4),
            child: SvgPicture.asset(
              'assets/icons/$icon.svg',
              width: 14,
              height: 16,
              colorFilter: const ColorFilter.mode(_grey666, BlendMode.srcIn),
            ),
          ),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // One line, as natively ("50,00,000" never breaks there).
                Text(
                  value,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.visible,
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.visible,
                  style: const TextStyle(color: _grey666, fontSize: 9),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatDivider extends StatelessWidget {
  const _StatDivider();

  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 30, color: const Color(0xFFDDDDDD));
}

class _CardButton extends StatelessWidget {
  const _CardButton({
    required this.icon,
    required this.label,
    required this.weight,
    required this.onTap,
  });

  final String icon;
  final String label;
  final FontWeight weight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _state,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        splashColor: const Color(0x33FFFFFF),
        child: SizedBox(
          height: 36,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SvgPicture.asset(
                'assets/icons/$icon.svg',
                width: 16,
                height: 16,
                colorFilter: const ColorFilter.mode(
                  Colors.white,
                  BlendMode.srcIn,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: weight,
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

/// The card's horizontally scrolling cutoff table (headerRow + the
/// CutoffMarksAdapter rows, at most two on the list).
class _CutoffTable extends StatelessWidget {
  const _CutoffTable({
    required this.cutoffs,
    required this.examRank,
    required this.isSubscribed,
    required this.onRow,
  });

  final List<Map<String, dynamic>> cutoffs;
  final int examRank;
  final bool isSubscribed;
  final VoidCallback onRow;

  static const _header = TextStyle(color: Colors.black, fontSize: 12);
  static const _headerMuted = TextStyle(color: _b47, fontSize: 12);
  static const _cell = TextStyle(
    color: Colors.black,
    fontSize: 12,
    fontWeight: FontWeight.w700,
  );

  static String _round(Object? v) => v == null ? 'N/A' : '$v';

  @override
  Widget build(BuildContext context) {
    final rows = cutoffs.take(cutoffs.length == 1 ? 1 : 2).toList();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 8, right: 8),
            child: Row(
              children: [
                const SizedBox(width: 14),
                const SizedBox(
                  width: 100,
                  child: Text(
                    'CutOff(2024)',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                for (final (label, muted) in const [
                  ('R1', false),
                  ('R2', false),
                  ('R3', true),
                  ('R4', true),
                  ('R5', true),
                  ('Fee', true),
                  ('Matching', true),
                ])
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: SizedBox(
                      width: 60,
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        style: muted ? _headerMuted : _header,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final row in rows)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onRow,
                    child: IntrinsicWidth(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SizedBox(width: 4),
                                SizedBox(
                                  width: 100,
                                  child: Text(
                                    '${row['course_name'] ?? ''}',
                                    style: const TextStyle(
                                      color: Colors.black,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                for (final key in const [
                                  'round_1',
                                  'round_2',
                                  'round_3',
                                  'round_4',
                                  'round_5',
                                ])
                                  Padding(
                                    padding: const EdgeInsets.only(left: 4),
                                    child: SizedBox(
                                      width: 60,
                                      child: Text(
                                        _round(row[key]),
                                        textAlign: TextAlign.center,
                                        style: _cell,
                                      ),
                                    ),
                                  ),
                                Padding(
                                  padding: const EdgeInsets.only(left: 4),
                                  child: SizedBox(
                                    width: 65,
                                    child: Text(
                                      '${row['fee'] ?? ''}',
                                      textAlign: TextAlign.center,
                                      style: _cell,
                                    ),
                                  ),
                                ),
                                if (examRank != 0)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 20),
                                    child: SvgPicture.asset(
                                      row['is_match'] == true
                                          ? 'assets/icons/ic_baseline_rank_match.svg'
                                          : 'assets/icons/ic_baseline_rank_unamtch.svg',
                                      width: 18,
                                      height: 18,
                                      colorFilter: const ColorFilter.mode(
                                        Color(0xFF404040),
                                        BlendMode.srcIn,
                                      ),
                                    ),
                                  )
                                else
                                  const Padding(
                                    padding: EdgeInsets.only(left: 8),
                                    child: SizedBox(
                                      width: 60,
                                      child: Text(
                                        'Enter Rank',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: Color(0xFF0178D4),
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Container(
                            height: 1,
                            margin: const EdgeInsets.only(top: 2),
                            color: const Color(0xFFEFEEEE),
                          ),
                        ],
                      ),
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

/// college_enter_rank_dailog.xml: 85% of the screen wide.
class _EnterRankDialog extends StatefulWidget {
  const _EnterRankDialog();

  @override
  State<_EnterRankDialog> createState() => _EnterRankDialogState();
}

class _EnterRankDialogState extends State<_EnterRankDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width * 0.85;
    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFC5C5C5), width: 0.75),
      ),
      child: SizedBox(
        width: width,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 4, left: 12),
                child: Text(
                  'Rank',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: TextField(
                  controller: _controller,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(9),
                    _NoLeadingZero(),
                  ],
                  decoration: InputDecoration(
                    hintText: 'Enter your rank',
                    hintStyle: const TextStyle(fontSize: 15),
                    isDense: true,
                    filled: true,
                    fillColor: const Color(0xFFF9F9F9),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.zero,
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.zero,
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.zero,
                      borderSide: BorderSide(color: Colors.grey.shade400),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 10, right: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _DialogText(
                      'Cancel',
                      color: _appColor,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 16),
                    _DialogText(
                      'Ok',
                      color: const Color(0xFF0178D4),
                      onTap: () {
                        final rank = _controller.text.trim();
                        if (rank.isEmpty || rank == '0') {
                          showToast(context, 'Please enter your Rank');
                          return;
                        }
                        Navigator.of(context).pop(rank);
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DialogText extends StatelessWidget {
  const _DialogText(this.text, {required this.color, required this.onTap});

  final String text;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Text(
          text,
          style: TextStyle(
            color: color,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

/// EditTextUtils.preventZeroStartAndGetValue().
class _NoLeadingZero extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => newValue.text.startsWith('0') ? oldValue : newValue;
}

/// college_hompage_bottomsheet_rankcard.xml: 70% of the screen, the
/// server-rendered college/cutoff/{id}/webview/ page inside.
class _CutoffSheet extends StatelessWidget {
  const _CutoffSheet({
    required this.api,
    required this.college,
    required this.counselling,
    required this.isSubscribed,
    required this.onGoPremium,
  });

  final CollegeGuideApiRepository api;
  final Map<String, dynamic> college;
  final String counselling;
  final bool isSubscribed;
  final VoidCallback onGoPremium;

  @override
  Widget build(BuildContext context) {
    final id = college['id'] as String? ?? '';
    return Container(
      height: MediaQuery.sizeOf(context).height * 0.70,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(21, 17, 16, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    '${college['name'] ?? ''}',
                    style: const TextStyle(
                      color: _b47,
                      fontSize: 23,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Image.asset(
                    'assets/images/cutoff/mentor_closed.png',
                    width: 24,
                    height: 24,
                    color: Colors.black,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(21, 4, 16, 0),
            child: Text(
              'NEET PG - ${college['cutoff_and_course_count'] ?? ''}',
              style: const TextStyle(color: _b47, fontSize: 15),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: AuthWebView(
              api: api,
              url: api.webPage('college/cutoff/$id/webview/', {
                'councelling_type': counselling,
              }),
            ),
          ),
          if (!isSubscribed)
            Container(
              width: double.infinity,
              color: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: _PremiumPrompt(
                textColor: _b47,
                buttonColor: const Color(0xFF0178D4),
                buttonTextColor: Colors.white,
                onTap: onGoPremium,
              ),
            ),
        ],
      ),
    );
  }
}

// ---- WebView pages ----------------------------------------------------------------

/// A WebView that loads [url] with the Bearer token and keeps it attached when
/// the page navigates on the API's own host (the native WebViewClients).
class AuthWebView extends StatefulWidget {
  const AuthWebView({
    super.key,
    required this.api,
    required this.url,
    this.onError,
  });

  final CollegeGuideApiRepository api;
  final Uri url;
  final VoidCallback? onError;

  @override
  State<AuthWebView> createState() => _AuthWebViewState();
}

class _AuthWebViewState extends State<AuthWebView> {
  late final WebViewController _controller;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _loading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame ?? false) {
              if (mounted) setState(() => _loading = false);
              widget.onError?.call();
            }
          },
          onNavigationRequest: (request) async {
            final uri = Uri.tryParse(request.url);
            if (uri != null &&
                uri.host == widget.api.apiHost &&
                request.isMainFrame) {
              await _controller.loadRequest(
                uri,
                headers: await widget.api.authHeaders(),
              );
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      );
    _load();
  }

  Future<void> _load() async {
    await _controller.loadRequest(
      widget.url,
      headers: await widget.api.authHeaders(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        WebViewWidget(controller: _controller),
        if (_loading)
          const Center(child: CircularProgressIndicator(color: Colors.black)),
      ],
    );
  }
}

/// CutOffs & Matchings / Allotments: a filter line, "Sort by" and the
/// server-rendered list (it draws its own table and paging).
class _WebListPage extends StatefulWidget {
  const _WebListPage({
    super.key,
    required this.api,
    required this.path,
    required this.noData,
    required this.params,
    required this.isSubscribed,
    required this.onOpenPremium,
  });

  final CollegeGuideApiRepository api;
  final String path;
  final String noData;
  final Map<String, String> params;
  final bool isSubscribed;
  final VoidCallback onOpenPremium;

  @override
  State<_WebListPage> createState() => _WebListPageState();
}

class _WebListPageState extends State<_WebListPage> {
  String _from = '';
  String _to = '';
  int _reload = 0;
  bool _failed = false;

  /// MY_COLLEGE_SIZE for subscribers, COLLEGE otherwise.
  int get _limit => widget.isSubscribed ? 50 : 12;

  Uri get _url {
    final query = <String, String>{
      ...widget.params,
      'page': '1',
      'limit': '$_limit',
    };
    if (_from.isNotEmpty && _to.isNotEmpty && _from != '0' && _to != '0') {
      query['range_from'] = _from;
      query['range_to'] = _to;
    }
    return widget.api.webPage(widget.path, query);
  }

  String get _filterBy {
    final p = widget.params;
    final category = p['category'];
    if ((p['councelling_type'] ?? 'AIC') == 'AIC') {
      return 'Filter By: AIC${category != null ? '/$category' : ''}';
    }
    final state = p['state'];
    return 'Filter By: ${state != null ? '$state/' : ''}${category ?? 'SC'}';
  }

  /// tvsortby: bg_filter_input, "Sort by" and the sort icon (28dp tall).
  Widget _sortChip() {
    return GestureDetector(
      onTap: _sort,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 1, 10, 1),
        decoration: BoxDecoration(
          color: _filterMuted,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _filterStroke),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Sort by',
              style: TextStyle(
                color: AppColors.primary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 4),
            SvgPicture.asset(
              'assets/icons/ic_baseline_sort_24.svg',
              width: 24,
              height: 24,
              colorFilter: const ColorFilter.mode(
                AppColors.primary,
                BlendMode.srcIn,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sort() async {
    final range = await showDialog<(String, String)>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _SortDialog(from: _from, to: _to),
    );
    if (range == null || !mounted) return;
    setState(() {
      _from = range.$1;
      _to = range.$2;
      _reload++;
      _failed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      clipBehavior: Clip.antiAlias,
      child: RefreshIndicator(
        onRefresh: () async => setState(() {
          _reload++;
          _failed = false;
        }),
        notificationPredicate: (_) => false,
        child: Column(
          children: [
            // "Sort by" is centred on the text line and overhangs it (translationZ
            // 1dp in native), so only the text takes up height.
            Stack(
              clipBehavior: Clip.none,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(19, 10, 120, 0),
                  child: SizedBox(
                    width: double.infinity,
                    child: Text(
                      _filterBy,
                      style: const TextStyle(color: Colors.black, fontSize: 11),
                    ),
                  ),
                ),
                Positioned(right: 16, top: 10 + 6.65 - 14, child: _sortChip()),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _failed
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(32, 64, 32, 0),
                      child: Text(
                        widget.noData,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    )
                  : AuthWebView(
                      key: ValueKey(_reload),
                      api: widget.api,
                      url: _url,
                      onError: () => setState(() => _failed = true),
                    ),
            ),
            if (!widget.isSubscribed)
              Container(
                width: double.infinity,
                color: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: _PremiumPrompt(
                  textColor: _b47,
                  buttonColor: AppColors.primary,
                  buttonTextColor: Colors.white,
                  onTap: widget.onOpenPremium,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// college_from_to_rank_dailog.xml: 95% of the screen wide.
class _SortDialog extends StatefulWidget {
  const _SortDialog({required this.from, required this.to});

  final String from;
  final String to;

  @override
  State<_SortDialog> createState() => _SortDialogState();
}

class _SortDialogState extends State<_SortDialog> {
  late final _from = TextEditingController(
    text: widget.from == '0' ? '' : widget.from,
  );
  late final _to = TextEditingController(
    text: widget.to == '0' ? '' : widget.to,
  );

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  void _apply() {
    final from = _from.text.trim();
    final to = _to.text.trim();
    if (from.isEmpty || from == '0') {
      showToast(context, 'Please enter from Rank');
      return;
    }
    if (to.isEmpty || to == '0') {
      showToast(context, 'Please enter to Rank');
      return;
    }
    Navigator.of(context).pop((from, to));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: MediaQuery.sizeOf(context).width * 0.95,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Sort by',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Semantics(
                    label: 'Close',
                    button: true,
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
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
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: _FilterInput(
                      controller: _from,
                      hint: 'From rank',
                      action: TextInputAction.next,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _FilterInput(
                      controller: _to,
                      hint: 'To rank',
                      onSubmitted: _apply,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _FilterButton(label: 'Apply', height: 48, onTap: _apply),
            ],
          ),
        ),
      ),
    );
  }
}

/// bg_filter_input: muted box, 12dp corners; state-colour outline focused.
class _FilterInput extends StatelessWidget {
  const _FilterInput({
    required this.controller,
    required this.hint,
    this.action = TextInputAction.done,
    this.onSubmitted,
    this.height = 48,
    this.textSize = 15,
    this.number = true,
    this.prefix,
  });

  final TextEditingController controller;
  final String hint;
  final TextInputAction action;
  final VoidCallback? onSubmitted;
  final double height;
  final double textSize;
  final bool number;
  final Widget? prefix;

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: color, width: width),
    );
    return SizedBox(
      height: height,
      child: TextField(
        controller: controller,
        textInputAction: action,
        keyboardType: number ? TextInputType.number : TextInputType.text,
        inputFormatters: number
            ? [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(10),
                _NoLeadingZero(),
              ]
            : null,
        cursorColor: _state,
        onSubmitted: (_) => onSubmitted?.call(),
        style: TextStyle(
          color: _appColor,
          fontSize: textSize,
          fontWeight: number ? FontWeight.w500 : FontWeight.w400,
        ),
        textAlignVertical: TextAlignVertical.center,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: _filterSecondary, fontSize: textSize),
          filled: true,
          fillColor: _filterMuted,
          prefixIcon: prefix,
          prefixIconConstraints: const BoxConstraints(minWidth: 0),
          contentPadding: EdgeInsets.symmetric(
            horizontal: prefix == null ? 16 : 0,
          ),
          isCollapsed: false,
          border: border(_filterStroke, 1),
          enabledBorder: border(_filterStroke, 1),
          focusedBorder: border(_state, 1.5),
        ),
      ),
    );
  }
}

/// bg_filter_button: state colour, 12dp corners.
class _FilterButton extends StatelessWidget {
  const _FilterButton({
    required this.label,
    required this.height,
    required this.onTap,
  });

  final String label;
  final double height;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primary,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        splashColor: const Color(0x33FFFFFF),
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: Center(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// CollegeDetailsWebviewActivity: college/full-details/{id}/webview/.
class CollegeDetailsWebPage extends StatelessWidget {
  const CollegeDetailsWebPage({
    super.key,
    required this.api,
    required this.collegeId,
    required this.counselling,
  });

  final CollegeGuideApiRepository api;
  final String collegeId;
  final String counselling;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.black,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: ColoredBox(
            color: Colors.white,
            child: Column(
              children: [
                Container(
                  color: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Row(
                    children: [
                      const SizedBox(width: 16),
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
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
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Text(
                          'College Details',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                    ],
                  ),
                ),
                Expanded(
                  child: AuthWebView(
                    api: api,
                    url: api.webPage(
                      'college/full-details/$collegeId/webview/',
                      {'councelling_type': counselling},
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

// ---- Filters sheet -------------------------------------------------------------

/// One option in a filter list (LevelsNTagsModel): its status IS the
/// selection.
class _Option {
  _Option(this.name, this.selected);

  final String name;
  bool selected;
}

/// The filter state the native fragment keeps in fields, so it survives
/// closing and reopening the sheet.
class _FilterState {
  _FilterState(this.api);

  final CollegeGuideApiRepository api;

  String counselling = 'AIC';
  String rank = '0';
  String defaultState = '';
  String? finalState;
  String? defaultCaste;
  String? finalCaste;
  String? defaultQuota;
  String? finalQuota;
  bool userPickedState = false;
  bool stateHandled = false;
  bool allIndiaHandled = false;

  final aicStates = <_Option>[];
  final aicSpecialities = <_Option>[];
  final aicCastes = <_Option>[];
  final aicQuotas = <_Option>[];
  final scStates = <_Option>[];
  final scSpecialities = <_Option>[];
  final scCastes = <_Option>[];
  final scQuotas = <_Option>[];

  static void _merge(List<_Option> target, Object? name, bool selected) {
    if (name is! String) return;
    if (target.any((o) => o.name == name)) return;
    target.add(_Option(name, selected));
  }

  static List<Map<String, dynamic>> _list(Map<String, dynamic> d, String k) => [
    for (final e in (d[k] as List? ?? const []))
      if (e is Map<String, dynamic>) e,
  ];

  static String? _join(List<_Option> list) {
    final names = [
      for (final o in list)
        if (o.selected) o.name,
    ];
    return names.isEmpty ? null : names.join(',');
  }

  String? indiaStates;
  String? indiaSpecialities;
  String? stateSpecialities;

  /// Native setAPICallForHomeFilters().
  Future<void> loadHomeFilters() async {
    try {
      final data = await api.cutoffFilters(counselling);
      final defaults = data['default_parameter'];
      if (defaults is! Map<String, dynamic>) return;
      finalCaste ?? (defaultCaste = defaults['category'] as String?);
      finalQuota ?? (defaultQuota = defaults['quota'] as String?);
      if (rank == '0') rank = '${defaults['rank'] ?? 0}';
      for (final s in _list(data, 'states')) {
        _merge(aicStates, s['name'], s['is_default'] == true);
        _merge(scStates, s['name'], s['is_default'] == true);
      }
      for (final c in _list(data, 'category')) {
        _merge(aicCastes, c['category'], c['is_default'] == true);
      }
      for (final q in _list(data, 'quota')) {
        _merge(aicQuotas, q['name'], q['is_default'] == true);
      }
      for (final s in _list(data, 'speciality')) {
        _merge(aicSpecialities, s['name'], s['is_default'] == true);
      }
      indiaStates ??= _join(aicStates);
      indiaSpecialities ??= _join(aicSpecialities);
    } on CollegeGuideApiException {
      // Like the native callback: the sheet keeps what it has.
    }
  }

  /// Native setupAllIndiaFilters() for the Category list.
  Future<void> loadAllIndiaFilters() async {
    try {
      final data = await api.cutoffFilters('AIC');
      final defaults = data['default_parameter'];
      if (defaults is! Map<String, dynamic>) return;
      for (final c in _list(data, 'category')) {
        _merge(aicCastes, c['category'], c['is_default'] == true);
      }
      for (final q in _list(data, 'quota')) {
        _merge(aicQuotas, q['name'], q['is_default'] == true);
      }
      if (finalCaste == null) defaultCaste = defaults['category'] as String?;
      if (finalQuota == null) defaultQuota = defaults['quota'] as String?;
    } on CollegeGuideApiException {
      // Keep what is there.
    }
  }

  /// Native setUPForStatewithQuota(): one state's Category/Quota/Speciality.
  Future<void> loadStateFilters(String? state, {bool picked = false}) async {
    if (state == null || state.isEmpty) {
      await _loadDefaultStateThenFilters();
      return;
    }
    scQuotas.clear();
    scCastes.clear();
    if (!picked) scStates.clear();
    try {
      final data = await api.cutoffFilters('SC', stateName: state);
      final defaults = data['default_parameter'];
      if (defaults is! Map<String, dynamic>) return;
      defaultQuota = defaults['quota'] as String?;
      defaultCaste = defaults['category'] as String?;
      finalQuota = defaultQuota;
      finalCaste = defaultCaste;
      for (final s in _list(data, 'states')) {
        _merge(scStates, s['name'], s['is_default'] == true);
      }
      for (final c in _list(data, 'category')) {
        scCastes.add(
          _Option(c['category'] as String? ?? '', c['is_default'] == true),
        );
      }
      for (final s in _list(data, 'speciality')) {
        _merge(scSpecialities, s['name'], s['is_default'] == true);
      }
      for (final q in _list(data, 'quota')) {
        scQuotas.add(
          _Option(q['name'] as String? ?? '', q['is_default'] == true),
        );
      }
      stateSpecialities ??= _join(scSpecialities);
      defaultState = state;
    } on CollegeGuideApiException {
      // Keep what is there.
    }
  }

  Future<void> _loadDefaultStateThenFilters() async {
    try {
      final data = await api.collegeHomePage(
        page: 1,
        limit: 1,
        params: const {'councelling_type': 'SC', 'query': 'institute'},
      );
      final defaults = data['default_parameter'];
      final state = defaults is Map<String, dynamic>
          ? defaults['state'] as String?
          : null;
      if (state == null || state.isEmpty) {
        stateHandled = false;
        return;
      }
      setDefaultState(state, 'SC');
      stateHandled = true;
      await loadStateFilters(defaultState);
    } on CollegeGuideApiException {
      stateHandled = false;
    }
  }

  /// CollegesFragment reports the SC list's default state.
  void setDefaultState(String? state, String? counsellingType) {
    if (counsellingType != 'SC' ||
        state == null ||
        state.isEmpty ||
        userPickedState) {
      return;
    }
    if (state == defaultState) return;
    defaultState = state;
    finalState = state;
    stateHandled = false;
  }

  static String? _summary(List<_Option> list) {
    final picked = [
      for (final o in list)
        if (o.selected) o.name,
    ];
    if (picked.isEmpty) return null;
    return picked.length == 1 ? picked.first : '${picked.length} selected';
  }

  /// refreshFilterSummaries().
  String? summary(String key) {
    final aic = counselling == 'AIC';
    return switch (key) {
      'State' => aic ? _summary(aicStates) : (finalState ?? defaultState),
      'Speciality' => _summary(aic ? aicSpecialities : scSpecialities),
      'Category' => defaultCaste,
      _ => defaultQuota,
    };
  }
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({
    required this.filters,
    required this.height,
    required this.isSubscribed,
    required this.currentParams,
    required this.onGoPremium,
  });

  final _FilterState filters;
  final double height;
  final bool isSubscribed;
  final Map<String, String> currentParams;
  final VoidCallback onGoPremium;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  static const _keys = ['State', 'Speciality', 'Category', 'Quota'];

  final _rank = TextEditingController();
  final _search = TextEditingController();
  late final _FilterState f = widget.filters;
  String _key = 'State';

  // Restored if the sheet closes without Apply.
  late final _saved = (
    f.counselling,
    f.defaultQuota,
    f.finalQuota,
    f.defaultCaste,
    f.finalCaste,
  );
  bool _applied = false;

  @override
  void initState() {
    super.initState();
    if (f.rank != '0') _rank.text = f.rank;
    _search.addListener(() => setState(() {}));
    _select('State');
  }

  @override
  void dispose() {
    if (!_applied) {
      f.counselling = _saved.$1;
      f.defaultQuota = _saved.$2;
      f.finalQuota = _saved.$3;
      f.defaultCaste = _saved.$4;
      f.finalCaste = _saved.$5;
    }
    _rank.dispose();
    _search.dispose();
    super.dispose();
  }

  bool get _aic => f.counselling == 'AIC';

  /// handleFilterSelection().
  Future<void> _select(String key) async {
    _search.clear();
    FocusScope.of(context).unfocus();
    setState(() => _key = key);
    if (key == 'State' && !_aic && !f.stateHandled) {
      f.stateHandled = true;
      await f.loadStateFilters(f.defaultState);
    } else if (key == 'Category' && _aic && !f.allIndiaHandled) {
      f.allIndiaHandled = true;
      await f.loadAllIndiaFilters();
    }
    if (mounted) setState(_adoptTicked);
  }

  /// Binding a ticked radio row calls onFilterValueSelected(name, key,
  /// false) natively, so the shown list's ticked option becomes the value.
  void _adoptTicked() {
    if (_multi) return;
    for (final o in _options) {
      if (!o.selected) continue;
      switch (_key) {
        case 'State':
          f.finalState = o.name;
        case 'Category':
          f.defaultCaste = f.finalCaste = o.name;
        default:
          f.defaultQuota = f.finalQuota = o.name;
      }
      return;
    }
  }

  void _setCounselling(String type) {
    setState(() {
      if (type == 'AIC') {
        if (!_aic) {
          f.defaultQuota = 'AIQ';
          f.finalQuota = 'AIQ';
          _restore(f.aicCastes, f.aicQuotas);
        }
      } else if (_aic) {
        _restore(f.scCastes, f.scQuotas);
      }
      f.counselling = type;
    });
    // setupHomepageFilterNames() makes a new keys adapter, which starts
    // on State.
    _select('State');
  }

  void _restore(List<_Option> castes, List<_Option> quotas) {
    for (final o in castes) {
      if (o.selected) f.defaultCaste = f.finalCaste = o.name;
    }
    for (final o in quotas) {
      if (o.selected) f.defaultQuota = f.finalQuota = o.name;
    }
  }

  bool get _multi =>
      (_aic && (_key == 'State' || _key == 'Speciality')) ||
      (!_aic && _key == 'Speciality');

  List<_Option> get _options => switch (_key) {
    'State' => _aic ? f.aicStates : f.scStates,
    'Speciality' => _aic ? f.aicSpecialities : f.scSpecialities,
    'Category' => _aic ? f.aicCastes : f.scCastes,
    _ => _aic ? f.aicQuotas : f.scQuotas,
  };

  void _toggle(_Option option) {
    setState(() {
      option.selected = !option.selected;
      final joined = _FilterState._join(_options);
      if (_aic && _key == 'State') f.indiaStates = joined;
      if (_aic && _key == 'Speciality') f.indiaSpecialities = joined;
      if (!_aic && _key == 'Speciality') f.stateSpecialities = joined;
    });
  }

  /// onFilterValueSelected().
  Future<void> _pick(_Option option) async {
    setState(() {
      for (final o in _options) {
        o.selected = false;
      }
      option.selected = true;
      switch (_key) {
        case 'State':
          f.finalState = option.name;
          f.userPickedState = true;
        case 'Category':
          f.defaultCaste = f.finalCaste = option.name;
        default:
          f.defaultQuota = f.finalQuota = option.name;
      }
    });
    if (_key == 'State') {
      await f.loadStateFilters(option.name, picked: true);
      if (mounted) setState(_adoptTicked);
    }
  }

  void _apply() {
    final rank = _rank.text.trim();
    if (rank.isEmpty || RegExp(r'^0+$').hasMatch(rank)) {
      showToast(context, 'Please enter a valid Rank');
      return;
    }
    f.rank = rank;
    final params = Map<String, String>.of(widget.currentParams)
      ..['rank'] = rank;
    void putOrRemove(String key, String? value) =>
        value != null ? params[key] = value : params.remove(key);
    if (_aic) {
      params['councelling_type'] = 'AIC';
      putOrRemove('state', f.indiaStates);
      putOrRemove('speciality', f.indiaSpecialities);
    } else {
      params['councelling_type'] = 'SC';
      putOrRemove('state', f.finalState);
      putOrRemove('speciality', f.stateSpecialities);
    }
    if (f.finalCaste != null) params['category'] = f.finalCaste!;
    if (f.finalQuota != null) params['quota'] = f.finalQuota!;
    f.stateHandled = false;
    f.allIndiaHandled = false;
    _applied = true;
    Navigator.of(context).pop(params);
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final options = [
      for (final o in _options)
        if (query.isEmpty || o.name.toLowerCase().contains(query)) o,
    ];
    return Padding(
      padding: EdgeInsets.only(
        bottom:
            MediaQuery.viewInsetsOf(context).bottom +
            MediaQuery.paddingOf(context).bottom,
      ),
      child: Container(
        height: widget.height,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The 36dp close button is centred on the title (marginTop 20,
            // 26dp tall with font padding), so the 36dp row starts 15dp down.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 15, 12, 0),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Filters',
                      style: TextStyle(
                        color: _appColor,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Semantics(
                    label: 'Close',
                    button: true,
                    child: InkResponse(
                      onTap: () => Navigator.of(context).pop(),
                      radius: 18,
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: SvgPicture.asset(
                          'assets/icons/ic_baseline_close.svg',
                          width: 24,
                          height: 24,
                          colorFilter: const ColorFilter.mode(
                            _appColor,
                            BlendMode.srcIn,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              // 16dp below the title, which ends 5dp above the row's end.
              margin: const EdgeInsets.fromLTRB(20, 11, 20, 0),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: _filterMuted,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                children: [
                  for (final (type, label) in const [
                    ('AIC', 'All India Counselling'),
                    ('SC', 'State Counselling'),
                  ])
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _setCounselling(type),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: f.counselling == type
                                ? AppColors.primary
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Text(
                            label,
                            maxLines: 1,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: f.counselling == type
                                  ? Colors.white
                                  : _filterSecondary,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Text(
                'Your Rank',
                style: TextStyle(
                  color: _filterSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _FilterInput(controller: _rank, hint: 'Enter your rank'),
            ),
            const SizedBox(height: 14),
            const Divider(height: 1, thickness: 1, color: _filterDivider),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) => Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      width: constraints.maxWidth * 0.36,
                      color: _filterMuted,
                      child: ListView(
                        padding: EdgeInsets.zero,
                        children: [
                          for (final key in _keys)
                            _FilterKey(
                              label: key,
                              summary: f.summary(key),
                              selected: key == _key,
                              onTap: () => _select(key),
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                            child: _FilterInput(
                              controller: _search,
                              hint: 'Search',
                              height: 40,
                              textSize: 14,
                              number: false,
                              prefix: Padding(
                                padding: const EdgeInsets.only(
                                  left: 12,
                                  right: 8,
                                ),
                                child: SvgPicture.asset(
                                  'assets/icons/ic_baseline_search_24.svg',
                                  width: 24,
                                  height: 24,
                                  colorFilter: const ColorFilter.mode(
                                    _filterSecondary,
                                    BlendMode.srcIn,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: ListView(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              children: [
                                for (final option in options)
                                  _FilterValue(
                                    label: option.name,
                                    multi: _multi,
                                    checked: option.selected,
                                    onTap: () => _multi
                                        ? _toggle(option)
                                        : _pick(option),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1, thickness: 1, color: _filterDivider),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: _FilterButton(
                label: widget.isSubscribed
                    ? 'Apply Filters'
                    : 'Go Premium to Apply',
                height: 50,
                onTap: widget.isSubscribed ? _apply : widget.onGoPremium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// row_home_filter_key.xml.
class _FilterKey extends StatelessWidget {
  const _FilterKey({
    required this.label,
    required this.summary,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String? summary;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        color: selected ? Colors.white : Colors.transparent,
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.centerLeft,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(width: 12),
              Container(
                width: 3,
                decoration: BoxDecoration(
                  color: selected ? AppColors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 7, right: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 14,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                      ),
                      if (summary != null && summary!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            summary!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontSize: 11,
                            ),
                          ),
                        ),
                    ],
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

/// row_home_filter_value.xml: a RadioButton or a CheckBox.
class _FilterValue extends StatelessWidget {
  const _FilterValue({
    required this.label,
    required this.multi,
    required this.checked,
    required this.onTap,
  });

  final String label;
  final bool multi;
  final bool checked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          children: [
            SizedBox(
              width: 32,
              child: multi
                  ? Checkbox(
                      value: checked,
                      onChanged: (_) => onTap(),
                      activeColor: _state,
                      side: const BorderSide(color: _state, width: 2),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    )
                  : Icon(
                      checked
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: _state,
                      size: 22,
                    ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  label,
                  style: const TextStyle(
                    color: _appColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
