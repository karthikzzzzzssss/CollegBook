import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/native_bridge.dart';
import '../home/college_guide_api.dart';
import '../support/contact_us_page.dart';
import 'plan_card.dart';
import 'plan_purchase.dart';

const _state = Color(0xFF1E4B3E);
const _iconColor = Color(0xFF004D40);
const _appColor = Color(0xFF12151B);
const _secondary = Color(0xFF6B7280);
const _gold = Color(0xFFE8BE5E);

/// GET college/plan/: the plans, or null when there are none / it failed.
Future<List<Plan>?> fetchPlans(CollegeGuideApiRepository api) async {
  try {
    final json = await api.send('GET', 'college/plan/');
    final data = json['data'];
    final results = data is Map ? data['results'] as List? : null;
    if (results == null || results.isEmpty) return null;
    return [
      for (final r in results)
        if (r is Map<String, dynamic>) Plan(r),
    ];
  } on CollegeGuideApiException {
    return null;
  }
}

/// common_header_college_layout with back / search / premium hidden.
class _TabHeader extends StatelessWidget {
  const _TabHeader({required this.title, this.onBack});

  final String title;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: _state,
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          if (onBack != null) ...[
            const SizedBox(width: 12),
            Semantics(
              label: 'Back',
              button: true,
              child: GestureDetector(
                onTap: onBack,
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
          ],
          const SizedBox(width: 20),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w700,
              height: 1.47,
            ),
          ),
        ],
      ),
    );
  }
}

/// The Premium tab — PremiumFragment (fragment_premium.xml).
class PremiumPage extends StatefulWidget {
  const PremiumPage({super.key, required this.api});

  final CollegeGuideApiRepository api;

  @override
  State<PremiumPage> createState() => _PremiumPageState();
}

class _PremiumPageState extends State<PremiumPage> {
  final _scroll = ScrollController();
  final _tabsKey = GlobalKey();
  final _contentKey = GlobalKey();
  final _tabsScroll = ScrollController();
  final _pinnedTabsScroll = ScrollController();
  List<GlobalKey> _cardKeys = [];
  late final _purchase = PlanPurchase(
    api: widget.api,
    onPurchased: (message) {
      if (!mounted) return;
      showToast(context, message);
      _load();
    },
  );

  List<Plan>? _plans;
  bool _loading = true;
  bool _pinned = false;
  int _tab = 0;
  DateTime _ignoreScrollUntil = DateTime(0);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScrolled);
    _load();
  }

  @override
  void dispose() {
    _purchase.dispose();
    _scroll.dispose();
    _tabsScroll.dispose();
    _pinnedTabsScroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final plans = await fetchPlans(widget.api);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _plans = plans;
      _cardKeys = [for (final _ in plans ?? const []) GlobalKey()];
      _tab = 0;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _onScrolled());
  }

  void _openContact() =>
      Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => const ContactUsPage()));

  /// Offset of [key]'s top inside the scrolled content.
  double? _topOf(GlobalKey key) {
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    final content =
        _contentKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || content == null || !box.attached) return null;
    return box.localToGlobal(Offset.zero, ancestor: content).dy;
  }

  static const _pinnedHeight = 36.0 + 20;

  /// Pins the tabs once they scroll away and highlights the plan under them.
  void _onScrolled() {
    if (!mounted || !_scroll.hasClients) return;
    final plans = _plans;
    final hasTabs = plans != null && plans.length > 1;
    final y = _scroll.offset;
    final tabsTop = _topOf(_tabsKey);
    final pinned = hasTabs && tabsTop != null && y > tabsTop;
    if (pinned != _pinned) setState(() => _pinned = pinned);
    if (!hasTabs || DateTime.now().isBefore(_ignoreScrollUntil)) return;
    var active = 0;
    if (y > 0 && _scroll.position.extentAfter < 1) {
      active = plans.length - 1;
    } else {
      final anchor = y + _pinnedHeight + 24;
      for (var i = 0; i < _cardKeys.length; i++) {
        final top = _topOf(_cardKeys[i]);
        if (top != null && top <= anchor) active = i;
      }
    }
    _select(active);
  }

  void _select(int index) {
    if (index == _tab) return;
    setState(() => _tab = index);
    _revealTab(index);
  }

  /// smoothScrollToPosition on both tab strips.
  void _revealTab(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final c in [_tabsScroll, _pinnedTabsScroll]) {
        if (!c.hasClients) continue;
        final max = c.position.maxScrollExtent;
        final target = max * index / ((_plans?.length ?? 1) - 1).clamp(1, 99);
        c.animateTo(
          target,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _onTab(int index) {
    final top = _topOf(_cardKeys[index]);
    _select(index);
    if (top == null) return;
    _ignoreScrollUntil = DateTime.now().add(const Duration(milliseconds: 700));
    _scroll.animateTo(
      (top - _pinnedHeight - 12).clamp(0, _scroll.position.maxScrollExtent),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final plans = _plans;
    final hasTabs = plans != null && plans.length > 1;
    return AnnotatedRegion<SystemUiOverlayStyle>(
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
            color: Colors.white,
            child: Column(
              key: const Key('premiumScreen'),
              children: [
                const _TabHeader(title: 'Premium'),
                Expanded(
                  child: Stack(
                    children: [
                      // fillViewport: the light page colour reaches the bottom.
                      const Positioned.fill(
                        child: ColoredBox(color: Color(0xFFF6FAF7)),
                      ),
                      RefreshIndicator(
                        color: _iconColor,
                        onRefresh: _load,
                        child: SingleChildScrollView(
                          controller: _scroll,
                          physics: const AlwaysScrollableScrollPhysics(),
                          child: Container(
                            key: _contentKey,
                            color: const Color(0xFFF6FAF7),
                            padding: const EdgeInsets.only(bottom: 32),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _Hero(onTalk: _openContact),
                                const _ChooseHeading(),
                                if (_loading && plans == null)
                                  const Padding(
                                    padding: EdgeInsets.only(top: 32),
                                    child: Center(
                                      child: CircularProgressIndicator(
                                        color: _iconColor,
                                      ),
                                    ),
                                  ),
                                if (!_loading && plans == null)
                                  const Padding(
                                    padding: EdgeInsets.fromLTRB(32, 32, 32, 0),
                                    child: Text(
                                      'No packages available right now. Pull down to refresh.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Colors.black,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                if (hasTabs)
                                  Padding(
                                    key: _tabsKey,
                                    padding: const EdgeInsets.only(top: 10),
                                    child: _PlanTabs(
                                      controller: _tabsScroll,
                                      names: [for (final p in plans) p.name],
                                      selected: _tab,
                                      onTap: _onTab,
                                    ),
                                  ),
                                if (plans != null) ...[
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                    ),
                                    child: Column(
                                      children: [
                                        for (var i = 0; i < plans.length; i++)
                                          PlanCard(
                                            key: _cardKeys[i],
                                            plan: plans[i],
                                            index: i,
                                            count: plans.length,
                                            onContinue: () =>
                                                _purchase.buy(plans[i]),
                                          ),
                                      ],
                                    ),
                                  ),
                                  _Footer(onHelp: _openContact),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (_pinned && hasTabs)
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: Container(
                            decoration: const BoxDecoration(
                              color: Color(0xFFF6FAF7),
                              border: Border(
                                bottom: BorderSide(color: Color(0xFFE3ECE8)),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Color(0x1F000000),
                                  blurRadius: 4,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: _PlanTabs(
                              controller: _pinnedTabsScroll,
                              names: [for (final p in plans) p.name],
                              selected: _tab,
                              onTap: _onTab,
                              bottomPadding: 0,
                            ),
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
    );
  }
}

/// "Confused between plans?" (bg_premium_hero).
class _Hero extends StatelessWidget {
  const _Hero({required this.onTalk});

  final VoidCallback onTalk;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF0E5A49), Color(0xFF003A30)],
                ),
              ),
            ),
          ),
          Positioned(
            top: -90,
            right: -70,
            child: _circle(220, const Color(0x14FFFFFF)),
          ),
          Positioned(
            bottom: -70,
            left: -40,
            child: _circle(150, const Color(0x0FFFFFFF)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 6, 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Confused between plans?',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          height: 1.27,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Our counsellors explain every plan and help you pick the right one.',
                        style: TextStyle(
                          color: Color(0xD9FFFFFF),
                          fontSize: 12.5,
                          height: 1.37,
                        ),
                      ),
                      const SizedBox(height: 10),
                      InkWell(
                        onTap: onTalk,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 4),
                          child: Text(
                            'Talk to a counsellor  →',
                            style: TextStyle(
                              color: _gold,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                Semantics(
                  label: 'A counsellor explaining plans to students',
                  child: SvgPicture.asset(
                    'assets/icons/img_premium_counsellor.svg',
                    width: 168,
                    height: 126,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Widget _circle(double size, Color color) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

class _ChooseHeading extends StatelessWidget {
  const _ChooseHeading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(20, 22, 20, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Text(
              'Choose your plan',
              style: TextStyle(
                color: _appColor,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(bottom: 1),
            child: Text(
              'Tap a plan to select',
              style: TextStyle(
                color: _secondary,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// item_premium_plan_tab.xml pills in a horizontal strip.
class _PlanTabs extends StatelessWidget {
  const _PlanTabs({
    required this.controller,
    required this.names,
    required this.selected,
    required this.onTap,
    this.bottomPadding = 10,
  });

  final ScrollController controller;
  final List<String> names;
  final int selected;
  final ValueChanged<int> onTap;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: controller,
      scrollDirection: Axis.horizontal,
      physics: const ClampingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(16, 0, 16, bottomPadding),
      child: Row(
        children: [
          for (var i = 0; i < names.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Semantics(
                button: true,
                selected: i == selected,
                child: GestureDetector(
                  onTap: () => onTap(i),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 36),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: i == selected ? _iconColor : Colors.white,
                      border: i == selected
                          ? null
                          : Border.all(color: const Color(0xFFD6E3DE)),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      names[i],
                      maxLines: 1,
                      style: TextStyle(
                        color: i == selected
                            ? Colors.white
                            : const Color(0xFF2B3A35),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Secure-payments note and the "Not sure which plan is right?" card.
class _Footer extends StatelessWidget {
  const _Footer({required this.onHelp});

  final VoidCallback onHelp;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SvgPicture.asset(
                'assets/icons/ic_plan_lock.svg',
                width: 14,
                height: 14,
                colorFilter: const ColorFilter.mode(
                  _secondary,
                  BlendMode.srcIn,
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                '100% secure payments via Razorpay',
                style: TextStyle(
                  color: _secondary,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Material(
            color: Colors.transparent,
            child: Ink(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFEEF7F2), Color(0xFFD2E8DE)],
                ),
                border: Border.all(color: const Color(0xFFD6E8E0)),
                borderRadius: BorderRadius.circular(20),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: onHelp,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFFD6E8E0)),
                        ),
                        child: SvgPicture.asset(
                          'assets/icons/ic_cb_support.svg',
                          colorFilter: const ColorFilter.mode(
                            _iconColor,
                            BlendMode.srcIn,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Not sure which plan is right?',
                              style: TextStyle(
                                color: _appColor,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Talk to our team – call or WhatsApp',
                              style: TextStyle(
                                color: _secondary,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SvgPicture.asset(
                        'assets/icons/ic_cb_chevron_right.svg',
                        width: 24,
                        height: 24,
                        colorFilter: const ColorFilter.mode(
                          _iconColor,
                          BlendMode.srcIn,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// CollegePackagesActivity: "Packages", the same plan cards on white, opened
/// by "Get a Package" and "Go Premium to Apply". A bought plan returns home.
class PackagesPage extends StatefulWidget {
  const PackagesPage({super.key, required this.api});

  final CollegeGuideApiRepository api;

  @override
  State<PackagesPage> createState() => _PackagesPageState();
}

class _PackagesPageState extends State<PackagesPage> {
  List<Plan>? _plans;
  late final _purchase = PlanPurchase(
    api: widget.api,
    onPurchased: (message) {
      if (!mounted) return;
      showToast(context, message);
      Navigator.of(context).popUntil((route) => route.isFirst);
    },
  );

  @override
  void initState() {
    super.initState();
    unawaited(
      fetchPlans(widget.api).then((plans) {
        if (mounted && plans != null) setState(() => _plans = plans);
      }),
    );
  }

  @override
  void dispose() {
    _purchase.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final plans = _plans;
    final padding = MediaQuery.paddingOf(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // setupEdgeToEdge(black, black, white icons).
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.black,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.black,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Padding(
          padding: EdgeInsets.only(top: padding.top, bottom: padding.bottom),
          child: ColoredBox(
            color: Colors.white,
            child: Column(
              children: [
                _TabHeader(
                  title: 'Packages',
                  onBack: () => Navigator.of(context).maybePop(),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
                    child: Column(
                      children: [
                        if (plans != null)
                          for (var i = 0; i < plans.length; i++)
                            PlanCard(
                              plan: plans[i],
                              index: i,
                              count: plans.length,
                              onContinue: () => _purchase.buy(plans[i]),
                            ),
                      ],
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
