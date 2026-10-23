import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../core/native_bridge.dart';
import '../choice/choice_repository.dart';
import '../choice/choice_screens.dart';
import '../../theme/app_theme.dart';
import '../videos/reels_player_page.dart';
import 'college_guide_api.dart';
import 'web_pages.dart';

/// The Home tab — a port of the native CollegeGuidanceFragment
/// (activity_college_pacakges_plan.xml + activity_plana_details.xml).
/// Sizes are the native dp/sp values; Flutter's logical pixels are dp.
class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.apiRepository,
    required this.onOpenCutoffTab,
    required this.onOpenSideMenu,
    required this.isSubscribed,
    required this.onOpenPremium,
    required this.onOpenPackages,
  });

  final CollegeGuideApiRepository apiRepository;
  final bool isSubscribed;

  /// Where "Get a Package" leads (the native CollegePackagesActivity).
  final VoidCallback onOpenPremium;

  /// CollegePackagesActivity.
  final VoidCallback onOpenPackages;

  /// Native openCollegeTabWithPosition(): 0 Colleges, 1 CutOffs & Matchings,
  /// 2 Allotments.
  final ValueChanged<int> onOpenCutoffTab;
  final VoidCallback onOpenSideMenu;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const contactNumber = '8500001406';

  final _scrollController = ScrollController();
  final _completeNeetKey = GlobalKey();
  late final _choiceRepository = ChoiceListRepository(widget.apiRepository);
  late _HomeData _data;

  /// Until the first load finishes only the banner and the progress spinner
  /// show, so section titles never sit on screen without their content.
  bool _firstLoadDone = false;

  @override
  void initState() {
    super.initState();
    _data = _HomeData.load(widget.apiRepository);
    // .then gives a true Future<void>, so the timeout may complete it empty.
    _data.all
        .then<void>((_) {})
        .timeout(const Duration(seconds: 20), onTimeout: () {})
        .whenComplete(() {
          if (mounted) setState(() => _firstLoadDone = true);
        });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() => _data = _HomeData.load(widget.apiRepository));
    await _data.all;
  }

  Future<void> _selectExamType(_ExamType examType) async {
    try {
      await widget.apiRepository.updateExamType(examType.code);
      if (!mounted) return;
      await _refresh();
    } on CollegeGuideApiException {
      if (mounted) {
        showToast(context, "Couldn't switch exam type, please try again");
      }
    }
  }

  void _onHelpfulTool(String title) {
    switch (title) {
      case 'Cutoff':
        widget.onOpenCutoffTab(2);
      case 'Closing Rank':
      case 'Matching':
        widget.onOpenCutoffTab(1);
      case 'Colleges':
        widget.onOpenCutoffTab(0);
      case '1to1 counselor':
        _scrollToCompleteNeet();
      case 'ChoiceList':
        _push(
          ChoiceListsPage(
            repository: _choiceRepository,
            isSubscribed: widget.isSubscribed,
            onGetPackage: widget.onOpenPackages,
          ),
        );
      case 'Fee Details':
        _push(
          GreenHeaderWebPage(
            api: widget.apiRepository,
            title: 'Fee Details',
            path: 'college/fee/webview/',
          ),
        );
      default:
        break;
    }
  }

  void _push(Widget page) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

  /// CcmsItemWebviewActivity for a State / Course / Counselling card.
  void _openCcmsItem(Map<String, dynamic> item) {
    final id = item['id'];
    if (id is! num) return;
    _push(
      CcmsItemPage(
        api: widget.apiRepository,
        itemId: id.toInt(),
        imageUrl: item['image'] as String?,
      ),
    );
  }

  void _scrollToCompleteNeet() {
    final target = _completeNeetKey.currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(
      target,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // The banner runs up under a transparent status bar (setImageEdgeToEdge).
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: ColoredBox(
        color: Colors.white,
        child: RefreshIndicator(
          onRefresh: _refresh,
          edgeOffset: topInset + 60,
          child: CustomScrollView(
            key: const Key('homeOverviewPage'),
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPersistentHeader(
                pinned: true,
                delegate: _BannerHeader(
                  topInset: topInset,
                  examTypes: _data.examTypes,
                  onExamTypeSelected: _selectExamType,
                  onProfileTap: widget.onOpenSideMenu,
                ),
              ),
              if (!_firstLoadDone)
                // The native fragment's centred progress bar.
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: CircularProgressIndicator(
                      key: Key('homeLoading'),
                      color: Color(0xFF004D40),
                    ),
                  ),
                )
              else
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 64),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _HelpfulTools(
                          future: _data.helpTools,
                          onTap: _onHelpfulTool,
                        ),
                        _NewsUpdates(future: _data.news),
                        _WebinarVideos(
                          future: _data.reels,
                          onOpen: (id) => _push(
                            ReelsPlayerPage(
                              api: widget.apiRepository,
                              startVideoId: id,
                              recommended: true,
                            ),
                          ),
                        ),
                        _CcmsSection(
                          onTap: _openCcmsItem,
                          future: _data.ccms,
                          match: 'state',
                          style: _CcmsCardStyle.state,
                        ),
                        _LiveEvents(future: _data.events),
                        _CompleteNeet(
                          key: _completeNeetKey,
                          recommended: _data.recommended,
                          onCall: () => callNumber(contactNumber),
                        ),
                        _CcmsSection(
                          onTap: _openCcmsItem,
                          future: _data.ccms,
                          match: 'cours',
                          style: _CcmsCardStyle.course,
                        ),
                        _CcmsSection(
                          onTap: _openCcmsItem,
                          future: _data.ccms,
                          match: 'sel',
                          style: _CcmsCardStyle.counselling,
                        ),
                        _CcmsSection(
                          onTap: _openCcmsItem,
                          future: _data.ccms,
                          match: 'countr',
                          style: _CcmsCardStyle.state,
                        ),
                        const _Highlights(),
                        _Reviews(future: _data.guidance),
                        _Faqs(future: _data.guidance),
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

// ---- Data ------------------------------------------------------------------

class _ExamType {
  const _ExamType(this.code, this.name, this.isSelected);

  final String code;
  final String name;
  final bool isSelected;
}

/// Every request the native fragment makes in setupInitialization().
class _HomeData {
  _HomeData({
    required this.examTypes,
    required this.helpTools,
    required this.news,
    required this.reels,
    required this.ccms,
    required this.events,
    required this.recommended,
    required this.guidance,
  });

  factory _HomeData.load(CollegeGuideApiRepository api) {
    return _HomeData(
      examTypes: _quiet(
        api.examTypes().then(
          (c) => [
            for (final item in c.items)
              _ExamType(
                _string(item['code']),
                _string(item['name']),
                item['is_selected'] == true,
              ),
          ],
        ),
      ),
      helpTools: _quiet(api.homeHelpTools().then((c) => c.items)),
      news: _quiet(api.homeNotifications().then((c) => c.items)),
      reels: _quiet(api.homeRecommendedReels().then((c) => c.items)),
      ccms: _quiet(api.homeCategories().then((c) => c.items)),
      events: _quiet(api.homeEvents().then((c) => c.items)),
      recommended: _quiet(api.recommendedColleges().then((c) => c.items)),
      guidance: _quiet(api.collegeGuidance(tab: 'guidance')),
    );
  }

  final Future<List<_ExamType>?> examTypes;
  final Future<List<Map<String, dynamic>>?> helpTools;
  final Future<List<Map<String, dynamic>>?> news;
  final Future<List<Map<String, dynamic>>?> reels;
  final Future<List<Map<String, dynamic>>?> ccms;
  final Future<List<Map<String, dynamic>>?> events;
  final Future<List<Map<String, dynamic>>?> recommended;
  final Future<Map<String, dynamic>?> guidance;

  Future<void> get all => Future.wait<Object?>([
    examTypes,
    helpTools,
    news,
    reels,
    ccms,
    events,
    recommended,
    guidance,
  ]);

  /// Like the native callbacks, a failed request just leaves its section
  /// empty (it is only logged there).
  static Future<T?> _quiet<T>(Future<T> future) async {
    try {
      return await future;
    } on CollegeGuideApiException {
      return null;
    }
  }
}

String _string(Object? value) => value is String ? value : '';

List<Map<String, dynamic>> _maps(Object? value) => [
  if (value is List)
    for (final item in value)
      if (item is Map<String, dynamic>) item,
];

// ---- Shared pieces -----------------------------------------------------------

const _allIndia = Color(0xFFE0FFC2);
const _navy = Color(0xFF131946);
const _cbNavy = Color(0xFF07183A);
const _cbTeal = Color(0xFF045356);

/// The 15sp Inter ExtraBold icon_color section titles.
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {this.color = AppColors.primary});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w800),
    );
  }
}

/// Glide-style network image with a local placeholder/error image.
class _NetImage extends StatelessWidget {
  const _NetImage(this.url, {this.placeholder});

  final String? url;
  final String? placeholder;
  static const fit = BoxFit.cover;

  @override
  Widget build(BuildContext context) {
    final fallback = placeholder == null
        ? const SizedBox.expand()
        : Image.asset(placeholder!, fit: fit);
    final source = url;
    if (source == null || source.isEmpty) return fallback;
    return CachedNetworkImage(
      imageUrl: source,
      fit: fit,
      fadeInDuration: Duration.zero,
      placeholder: (_, _) => fallback,
      errorWidget: (_, _, _) => fallback,
    );
  }
}

/// A horizontal list sized by its tallest child, like a wrap_content
/// horizontal RecyclerView.
class _HorizontalList extends StatelessWidget {
  const _HorizontalList({required this.padding, required this.children});

  final EdgeInsets padding;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const ClampingScrollPhysics(),
      padding: padding,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }
}

/// MaterialCardView with layout_margin 4dp and cardUseCompatPadding for its
/// 1.8dp elevation: [width] is the whole item, card plus that padding.
class _CompatCard extends StatelessWidget {
  const _CompatCard({required this.width, required this.child});

  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      margin: const EdgeInsets.all(4),
      padding: const EdgeInsets.symmetric(horizontal: 1.8, vertical: 2.7),
      child: child,
    );
  }
}

/// A TextView with minLines/maxLines [lines]: always [lines] tall, longer
/// text ellipsized. [center] is gravity="center".
class _MinLinesText extends StatelessWidget {
  const _MinLinesText(
    this.text, {
    required this.lines,
    required this.style,
    this.center = false,
  });

  final String text;
  final int lines;
  final TextStyle style;
  final bool center;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: center ? Alignment.center : AlignmentDirectional.topStart,
      children: [
        // Reserves the height of [lines] lines.
        Opacity(
          opacity: 0,
          child: Text(
            List.filled(lines, ' ').join('\n'),
            style: style,
            maxLines: lines,
          ),
        ),
        Text(
          text,
          maxLines: lines,
          overflow: TextOverflow.ellipsis,
          textAlign: center ? TextAlign.center : TextAlign.start,
          style: style,
        ),
      ],
    );
  }
}

/// Shows its child only once [future] has produced a non-empty value.
class _WhenLoaded<T> extends StatelessWidget {
  const _WhenLoaded({required this.future, required this.builder});

  final Future<T?> future;
  final Widget Function(BuildContext context, T data) builder;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T?>(
      future: future,
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (data == null || (data is List && data.isEmpty)) {
          return const SizedBox.shrink();
        }
        return builder(context, data);
      },
    );
  }
}

// ---- Banner header -------------------------------------------------------------

/// AppBarLayout (250dp) + CollapsingToolbarLayout: the banner scrolls away
/// with 0.7 parallax while the avatar row stays pinned; once fully collapsed
/// the pinned row turns icon_color.
class _BannerHeader extends SliverPersistentHeaderDelegate {
  _BannerHeader({
    required this.topInset,
    required this.examTypes,
    required this.onExamTypeSelected,
    required this.onProfileTap,
  });

  static const _expandedHeight = 250.0;

  final double topInset;
  final Future<List<_ExamType>?> examTypes;
  final ValueChanged<_ExamType> onExamTypeSelected;
  final VoidCallback onProfileTap;

  /// conBannerTop: status bar + 12dp margin + 36dp avatar + 12dp padding.
  double get _pinnedHeight => topInset + 60;

  @override
  double get maxExtent => math.max(_expandedHeight, _pinnedHeight);

  @override
  double get minExtent => _pinnedHeight;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final parallax = -shrinkOffset * 0.7;
    final collapsed = shrinkOffset >= maxExtent - minExtent;
    return ClipRect(
      child: ColoredBox(
        color: Colors.black,
        child: Stack(
          children: [
            Positioned(
              top: parallax,
              left: 0,
              right: 0,
              height: maxExtent,
              child: Image.asset(
                'assets/images/collegebook_home_banner.png',
                fit: BoxFit.cover,
              ),
            ),
            Positioned(
              top: parallax + maxExtent - 16 - 32,
              left: 0,
              right: 0,
              child: Center(
                child: _ExamTypePill(
                  examTypes: examTypes,
                  onSelected: onExamTypeSelected,
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                color: collapsed ? AppColors.primary : Colors.transparent,
                padding: EdgeInsets.fromLTRB(16, topInset + 12, 16, 12),
                alignment: Alignment.centerLeft,
                child: GestureDetector(
                  key: const Key('homeProfileButton'),
                  onTap: onProfileTap,
                  child: Container(
                    width: 36,
                    height: 36,
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: SvgPicture.asset(
                      'assets/icons/ic_profile.svg',
                      colorFilter: const ColorFilter.mode(
                        Color(0xFF49454F),
                        BlendMode.srcIn,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(_BannerHeader oldDelegate) =>
      oldDelegate.topInset != topInset || oldDelegate.examTypes != examTypes;
}

/// The yellow course Spinner: the server's is_selected exam type, with a
/// dropdown of the others.
class _ExamTypePill extends StatefulWidget {
  const _ExamTypePill({required this.examTypes, required this.onSelected});

  final Future<List<_ExamType>?> examTypes;
  final ValueChanged<_ExamType> onSelected;

  @override
  State<_ExamTypePill> createState() => _ExamTypePillState();
}

class _ExamTypePillState extends State<_ExamTypePill> {
  _ExamType? _selected;

  Future<void> _openMenu(List<_ExamType> types) async {
    final box = context.findRenderObject()! as RenderBox;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        box.localToGlobal(Offset(0, box.size.height), ancestor: overlay),
        box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );
    final choice = await showMenu<_ExamType>(
      context: context,
      position: position,
      color: Colors.white,
      constraints: BoxConstraints(minWidth: box.size.width),
      items: [
        for (final type in types)
          PopupMenuItem(
            value: type,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Center(
              child: Text(
                type.name,
                style: const TextStyle(color: Colors.black, fontSize: 14),
              ),
            ),
          ),
      ],
    );
    if (choice == null || choice.code == _selected?.code) return;
    setState(() => _selected = choice);
    widget.onSelected(choice);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<_ExamType>?>(
      future: widget.examTypes,
      builder: (context, snapshot) {
        final types = snapshot.data ?? const [];
        if (types.isEmpty) return const SizedBox(height: 32);
        final selected = types.firstWhere(
          (t) => t.code == _selected?.code,
          orElse: () =>
              types.firstWhere((t) => t.isSelected, orElse: () => types.first),
        );
        return GestureDetector(
          key: const Key('examTypePill'),
          onTap: () => _openMenu(types),
          child: Container(
            height: 32,
            padding: const EdgeInsets.only(left: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(32),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFFFFDF7D),
                  Color(0xFFFDC24C),
                  Color(0xFFF0981B),
                ],
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  // simple_spinner_item's own horizontal padding.
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    selected.name,
                    style: const TextStyle(
                      color: _navy,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                const Icon(Icons.keyboard_arrow_down, size: 18, color: _navy),
                const SizedBox(width: 16),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ---- Helpful tools ----------------------------------------------------------

class _HelpfulTools extends StatelessWidget {
  const _HelpfulTools({required this.future, required this.onTap});

  final Future<List<Map<String, dynamic>>?> future;
  final ValueChanged<String> onTap;

  /// Native HelpfulToolsAdapter.iconFor(): bundled icons matched by title.
  static String _icon(String title) => switch (title) {
    'Matching' => 'icon_matching',
    'Fee Details' => 'icon_feedetails',
    'Colleges' => 'icon_college',
    '1to1 counselor' => 'icon_counselor',
    _ => 'icon_choicelist',
  };

  @override
  Widget build(BuildContext context) {
    return _WhenLoaded<List<Map<String, dynamic>>>(
      future: future,
      builder: (context, tools) => Padding(
        // marginTop 16dp, paddingHorizontal 6dp, 5-column grid.
        padding: const EdgeInsets.fromLTRB(6, 16, 6, 0),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final cell = constraints.maxWidth / 5;
            return Wrap(
              children: [
                for (final tool in tools)
                  SizedBox(
                    width: cell,
                    child: _HelpfulTool(
                      title: _string(tool['title']),
                      icon: _icon(_string(tool['title'])),
                      onTap: () => onTap(_string(tool['title'])),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _HelpfulTool extends StatelessWidget {
  const _HelpfulTool({
    required this.title,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Semantics(
        button: true,
        label: title,
        excludeSemantics: true,
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              child: SvgPicture.asset(
                'assets/icons/$icon.svg',
                width: 24,
                height: 24,
                colorFilter: const ColorFilter.mode(
                  Colors.white,
                  BlendMode.srcIn,
                ),
              ),
            ),
            // minLines 2; gravity=center centres a one-line label.
            _MinLinesText(
              title,
              lines: 2,
              center: true,
              style: const TextStyle(
                color: AppColors.primary,
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---- News updates -------------------------------------------------------------

class _NewsUpdates extends StatelessWidget {
  const _NewsUpdates({required this.future});

  final Future<List<Map<String, dynamic>>?> future;

  @override
  Widget build(BuildContext context) {
    return Container(
      // marginHorizontal 14dp, marginTop 20dp, paddingVertical 10dp.
      margin: const EdgeInsets.fromLTRB(14, 20, 14, 0),
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [Color(0xFFD8D3F5), Color(0xFFF3D5E3), Color(0xFFFBE0D2)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14),
            child: _SectionTitle('Catch up on the latest updates!'),
          ),
          const SizedBox(height: 6),
          _WhenLoaded<List<Map<String, dynamic>>>(
            future: future,
            builder: (context, news) => _HorizontalList(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              children: [
                for (final item in news)
                  _NewsCard(
                    item: item,
                    onTap: () => _showDetailSheet(
                      context,
                      chip: _string(item['updated_date']),
                      title: _string(item['title']),
                      description: _string(item['description']),
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

class _NewsCard extends StatelessWidget {
  const _NewsCard({required this.item, required this.onTap});

  final Map<String, dynamic> item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 155,
      margin: const EdgeInsets.all(4),
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: Colors.white),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _string(item['updated_date']),
                  style: const TextStyle(
                    color: Color(0xFF8A8A9A),
                    fontSize: 10,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _string(item['title']),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF22226B),
                    fontSize: 12,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
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

/// bottom_sheet_news_detail: used for news items and full reviews.
Future<void> _showDetailSheet(
  BuildContext context, {
  required String chip,
  required String title,
  required String description,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.9,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          24 + MediaQuery.paddingOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                color: const Color(0xFFE0E0E0),
              ),
            ),
            if (chip.isNotEmpty) ...[
              const SizedBox(height: 20),
              Container(
                color: const Color(0xFFEEF0FB),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                child: Text(
                  chip,
                  style: const TextStyle(
                    color: Color(0xFF2E2E7A),
                    fontSize: 12,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            Text(
              title,
              style: const TextStyle(
                color: Color(0xFF1A1A2E),
                fontSize: 19,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            const Divider(height: 1, thickness: 1, color: Color(0xFFF0F0F0)),
            const SizedBox(height: 16),
            Text(
              description,
              style: const TextStyle(
                color: Color(0xFF4A4A5A),
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: Material(
                color: const Color(0xFF4F75EE),
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => Navigator.of(context).pop(),
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text(
                      'Close',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
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
  );
}

// ---- Webinars & video guides ---------------------------------------------------

class _WebinarVideos extends StatelessWidget {
  const _WebinarVideos({required this.future, required this.onOpen});

  final Future<List<Map<String, dynamic>>?> future;

  /// ReelsPlayerActivity.newIntentRecommended for the tapped reel.
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 24, 16, 0),
          child: _SectionTitle('Webinars & Video Guides'),
        ),
        const SizedBox(height: 8),
        _WhenLoaded<List<Map<String, dynamic>>>(
          future: future,
          builder: (context, reels) => _HorizontalList(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            children: [
              for (final reel in reels)
                Semantics(
                  label: _string(reel['caption']),
                  button: true,
                  child: GestureDetector(
                    onTap: () => onOpen('${reel['id']}'),
                    child: Container(
                      width: 130,
                      height: 180,
                      margin: const EdgeInsets.all(4),
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF7F2FA),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: _NetImage(_string(reel['thumbnail'])),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---- CCMS sections (States, Courses, Counselling, Countries) --------------------

enum _CcmsCardStyle {
  // CcmsCategoryItemAdapter.CardStyle: width, height, corner radius.
  course(100, 100, 6, 10),
  counselling(90, 90, 60, 30),
  state(120, 120, 6, 10);

  const _CcmsCardStyle(this.width, this.height, this.radius, this.gap);

  final double width;
  final double height;
  final double radius;
  final double gap;
}

class _CcmsSection extends StatelessWidget {
  const _CcmsSection({
    required this.onTap,
    required this.future,
    required this.match,
    required this.style,
  });

  final ValueChanged<Map<String, dynamic>> onTap;
  final Future<List<Map<String, dynamic>>?> future;

  /// The native fetchCcmsCategories() matches category names by substring.
  final String match;
  final _CcmsCardStyle style;

  @override
  Widget build(BuildContext context) {
    return _WhenLoaded<List<Map<String, dynamic>>>(
      future: future,
      builder: (context, categories) {
        final category = categories.cast<Map<String, dynamic>?>().firstWhere(
          (c) => _string(c!['name']).toLowerCase().contains(match),
          orElse: () => null,
        );
        if (category == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _SectionTitle(_string(category['name'])),
              ),
              const SizedBox(height: 8),
              _HorizontalList(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                children: [
                  for (final item in _maps(category['items']))
                    Padding(
                      padding: EdgeInsets.only(right: style.gap),
                      child: _CcmsCard(
                        item: item,
                        style: style,
                        onTap: () => onTap(item),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CcmsCard extends StatelessWidget {
  const _CcmsCard({
    required this.item,
    required this.style,
    required this.onTap,
  });

  final Map<String, dynamic> item;
  final _CcmsCardStyle style;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: style.width,
        child: Column(
          children: [
            Container(
              width: style.width,
              height: style.height,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(style.radius),
              ),
              child: _NetImage(
                item['image'] as String?,
                placeholder: 'assets/images/home/iv_mirror.png',
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: 80,
              child: Text(
                _string(item['title']),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---- Live events --------------------------------------------------------------

class _LiveEvents extends StatelessWidget {
  const _LiveEvents({required this.future});

  final Future<List<Map<String, dynamic>>?> future;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 24, 16, 0),
          child: _SectionTitle('Live Events'),
        ),
        const SizedBox(height: 6),
        _WhenLoaded<List<Map<String, dynamic>>>(
          future: future,
          builder: (context, events) => _HorizontalList(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            children: [for (final event in events) _EventCard(event: event)],
          ),
        ),
      ],
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.event});

  final Map<String, dynamic> event;

  /// "hh:mm a dd MMM" of the start, then the end date's year.
  static String? _dateLine(Map<String, dynamic> event) {
    final start = DateTime.tryParse(_string(event['startdate']))?.toLocal();
    final end = DateTime.tryParse(_string(event['enddate']))?.toLocal();
    if (start == null || end == null) return null;
    return '${DateFormat('hh:mm a dd MMM').format(start)} ${end.year}';
  }

  @override
  Widget build(BuildContext context) {
    final end = DateTime.tryParse(_string(event['enddate']));
    final expired = end != null && end.isBefore(DateTime.now());
    final date = _dateLine(event);
    return _CompatCard(
      width: 160,
      child: Material(
        color: Colors.white,
        elevation: 1.8,
        shadowColor: Colors.black,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: _NetImage(_string(event['image'])),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 8, 6, 0),
                child: _MinLinesText(
                  _string(event['title']),
                  lines: 2,
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (date != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 4, 6, 0),
                  child: Text(
                    date,
                    style: const TextStyle(
                      color: _navy,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              if (!expired && event['event_fee'] != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 10, 6, 0),
                  child: Text(
                    'Rs. ${event['event_fee']}',
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
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

// ---- Explore Admission Guidance (green block) --------------------------------

class _CompleteNeet extends StatelessWidget {
  const _CompleteNeet({
    super.key,
    required this.recommended,
    required this.onCall,
  });

  final Future<List<Map<String, dynamic>>?> recommended;
  final VoidCallback onCall;

  static const _guidance = [
    ('Low Budget MD/MS Admissions', 'Private Colleges I Deemed Universities'),
    (
      'Management NRI/IP Quota Admissions',
      'Private Colleges I Deemed Universities',
    ),
    (
      'NEET PG Counselling Assistance',
      'All India I State I Private College I Deemed Universities',
    ),
  ];

  static const _specialities = [
    'Radiodiagnosis',
    'Dermatology',
    'General Medicine',
    'Obstetrics and Gynaecology (OBG)',
    'General Surgery',
    'Paediatrics',
    'Orthopaedics',
    'Ophthalmology',
    'ENT',
    'Anaesthesiology',
    'Psychiatry',
    'Respiratory Medicine',
    'Pathology',
    'Community Medicine (PSM)',
    'Microbiology',
    'Anatomy',
    'Biochemistry',
    'Forensic Medicine (FMT)',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 20),
      padding: const EdgeInsets.only(bottom: 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF004D00), Color(0xFF003300), Color(0xFF003300)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Row(
              children: [
                const Expanded(
                  child: _SectionTitle(
                    'Explore Admission Guidance',
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 10),
                Semantics(
                  button: true,
                  label: 'Contact Us 8500001406',
                  excludeSemantics: true,
                  child: GestureDetector(
                    onTap: onCall,
                    child: Container(
                      height: 28,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFC812),
                        borderRadius: BorderRadius.circular(360),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.call, size: 14, color: Color(0xFF49454F)),
                          SizedBox(width: 4),
                          Text(
                            _HomePageState.contactNumber,
                            style: TextStyle(
                              color: _navy,
                              fontSize: 11.5,
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
          ),
          const SizedBox(height: 14),
          _HorizontalList(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            children: [
              for (final (title, description) in _guidance)
                Container(
                  width: 140,
                  height: 150,
                  margin: const EdgeInsets.all(4),
                  padding: const EdgeInsets.fromLTRB(14, 16, 14, 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF136105),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: _allIndia, width: 0.5),
                  ),
                  // A fixed 140x150dp view: text that does not fit is clipped.
                  clipBehavior: Clip.hardEdge,
                  child: OverflowBox(
                    alignment: Alignment.topCenter,
                    maxHeight: double.infinity,
                    child: Column(
                      children: [
                        Text(
                          title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Container(
                          height: 2,
                          margin: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                          color: const Color(0xFFB2DFBB),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          description,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Wrap(
              spacing: 4,
              runSpacing: 8,
              children: [
                for (final speciality in _specialities)
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _allIndia,
                      borderRadius: BorderRadius.circular(360),
                    ),
                    child: Text(
                      speciality,
                      maxLines: 1,
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          _WhenLoaded<List<Map<String, dynamic>>>(
            future: recommended,
            builder: (context, colleges) => Padding(
              padding: const EdgeInsets.fromLTRB(4, 20, 4, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(left: 16),
                    child: _SectionTitle(
                      'Recommended Colleges',
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _RecommendedGrid(colleges: colleges),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// GridLayoutManager(3 rows, HORIZONTAL): colleges fill each column top to
/// bottom, then the next column.
class _RecommendedGrid extends StatelessWidget {
  const _RecommendedGrid({required this.colleges});

  final List<Map<String, dynamic>> colleges;

  @override
  Widget build(BuildContext context) {
    final columns = <List<Map<String, dynamic>>>[];
    for (var i = 0; i < colleges.length; i += 3) {
      columns.add(colleges.sublist(i, math.min(i + 3, colleges.length)));
    }
    return _HorizontalList(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      children: [
        for (final column in columns)
          Column(
            children: [
              for (final college in column) _RecommendedCard(college: college),
            ],
          ),
      ],
    );
  }
}

class _RecommendedCard extends StatelessWidget {
  const _RecommendedCard({required this.college});

  final Map<String, dynamic> college;

  @override
  Widget build(BuildContext context) {
    final city = _string(college['city']);
    final state = _string(college['state']);
    final location = city.isNotEmpty ? '$city, $state' : state;
    return _CompatCard(
      width: 300,
      child: Material(
        color: _allIndia,
        elevation: 1.8,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: _NetImage(
                    college['image'] as String?,
                    placeholder: 'assets/images/home/iv_rank_image.jpg',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _string(college['name']),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      location,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
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

// ---- Why CollegeBook (layout_collegebook_highlights) ----------------------------

class _Highlights extends StatelessWidget {
  const _Highlights();

  static const _features = [
    (
      'img_cb_feat_department',
      'Real Department\nInformation',
      'Know HOD, faculty, clinical exposure, hands-on & work culture',
    ),
    (
      'img_cb_feat_mentors',
      'Current PGs &\nFaculty Mentors',
      'Talk to current PGs and faculty from inside the college',
    ),
    (
      'img_cb_feat_fees',
      'Complete Fee\nDetails',
      'All fees including tuition, hostel, exam and hidden charges',
    ),
    (
      'img_cb_feat_cutoffs',
      'Real-Time Cutoffs\n& Allotments',
      'Latest updates, trends and analysis',
    ),
    (
      'img_cb_feat_events',
      'Pre-PG Events\nby Department',
      'What to study, must-know topics, tips from current PGs',
    ),
    (
      'img_cb_feat_support',
      'End-to-End\nAdmission Support',
      'From registration to allotment and even after joining',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.only(bottom: 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFE6FDFC), Color(0xFFF7FEFC), Color(0xFFEEF9F8)],
        ),
      ),
      child: Column(
        children: [
          const _OverlapBottom(overlap: 24, child: _HighlightsHero()),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x1F000000),
                  blurRadius: 2,
                  offset: Offset(0, 1),
                ),
              ],
            ),
            child: const Row(
              children: [
                Expanded(
                  flex: 100,
                  child: _Stat(
                    image: 'img_cb_stat_colleges',
                    number: '2000+',
                    label: 'Colleges &\nInstitutes',
                  ),
                ),
                SizedBox(
                  width: 17,
                  child: Center(
                    child: SizedBox(
                      width: 1,
                      height: 44,
                      child: ColoredBox(color: Color(0xFFC3DBDB)),
                    ),
                  ),
                ),
                Expanded(
                  flex: 115,
                  child: _Stat(
                    image: 'img_cb_stat_doctors',
                    number: '500K+',
                    label: 'Doctors’ Community\n(PGs, Faculty, Alumni)',
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Column(
              children: [
                _FeatureRow(features: _features.sublist(0, 3)),
                const SizedBox(height: 7),
                _FeatureRow(features: _features.sublist(3)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HighlightsHero extends StatelessWidget {
  const _HighlightsHero();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        // img_cb_doctor is 419x586; it sits 2dp from the top.
        final doctorBottom = 2 + width * 0.445 * 586 / 419;
        return Stack(
          children: [
            Positioned(
              top: 2,
              right: 0,
              width: width * 0.445,
              child: Image.asset('assets/images/home/img_cb_doctor.png'),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(minHeight: doctorBottom),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 18, top: 10),
                    child: SizedBox(
                      width: width * 0.62,
                      child: Image.asset(
                        'assets/images/home/img_cb_logo_why.png',
                        semanticLabel:
                            'Why CollegeBook, by the doctor for the doctor',
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(left: 22, top: 16),
                    child: Text(
                      'Talk to Current',
                      style: TextStyle(
                        color: _cbNavy,
                        fontSize: 21,
                        height: 1.21,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 22),
                    child: Row(
                      children: [
                        const Text(
                          ' PGs & Faculty',
                          style: TextStyle(
                            color: _cbTeal,
                            fontSize: 21,
                            height: 1.21,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Image.asset(
                          'assets/images/home/img_cb_spark.png',
                          width: 14,
                        ),
                      ],
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(left: 22, top: 6),
                    child: Text(
                      'Get Real Insights from\nInside the College.',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 13.5,
                        height: 1.3,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 18, top: 10),
                    child: Material(
                      color: _cbTeal,
                      borderRadius: BorderRadius.circular(100),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(100),
                        onTap: () {},
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 9,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.call,
                                size: 18,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 10),
                              const Text(
                                'Explore Mentors',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(width: 8),
                              SvgPicture.asset(
                                'assets/icons/ic_cb_chevron_right.svg',
                                width: 16,
                                height: 16,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Breathing room under the button.
                  SizedBox(height: 12, width: width),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// A negative bottom margin: lays [child] out normally but reports itself
/// [overlap] shorter, so whatever follows is drawn over its bottom edge.
class _OverlapBottom extends SingleChildRenderObjectWidget {
  const _OverlapBottom({required this.overlap, required super.child});

  final double overlap;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderOverlapBottom(overlap);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderOverlapBottom renderObject,
  ) => renderObject.overlap = overlap;
}

class _RenderOverlapBottom extends RenderProxyBox {
  _RenderOverlapBottom(this._overlap);

  double _overlap;
  set overlap(double value) {
    if (value == _overlap) return;
    _overlap = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    child!.layout(constraints.loosen(), parentUsesSize: true);
    size = constraints.constrain(
      Size(child!.size.width, math.max(0, child!.size.height - _overlap)),
    );
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      child!.hitTest(result, position: position);
}

class _Stat extends StatelessWidget {
  const _Stat({required this.image, required this.number, required this.label});

  final String image;
  final String number;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Image.asset('assets/images/home/$image.png', width: 48, height: 48),
        const SizedBox(width: 8),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                number,
                style: const TextStyle(
                  color: Color(0xFF023E42),
                  fontSize: 18,
                  height: 1.21,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFF626376),
                  fontSize: 10.5,
                  height: 1.3,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.features});

  final List<(String, String, String)> features;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < features.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(child: _FeatureCard(feature: features[i])),
          ],
        ],
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({required this.feature});

  final (String, String, String) feature;

  @override
  Widget build(BuildContext context) {
    final (image, title, description) = feature;
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFEDF4F3)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {},
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Image.asset(
                'assets/images/home/$image.png',
                width: 44,
                height: 44,
              ),
              const SizedBox(height: 6),
              Text(
                title,
                style: const TextStyle(
                  color: _cbNavy,
                  fontSize: 12,
                  height: 1.3,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                description,
                style: const TextStyle(
                  color: Color(0xFF6A6C7F),
                  fontSize: 10,
                  height: 1.36,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---- Real Experiences (reviews) -----------------------------------------------

class _Review {
  _Review(Map<String, dynamic> json)
    : description = _string(json['description']).trim(),
      image = json['image'] as String? {
    var title = _string(json['title']);
    String? air;
    // " – Dr. Aisha(AIR 7, 842)" → "Dr. Aisha", "AIR 7,842".
    final match = RegExp(r'^(.*?)\s*\(([^)]*)\)\s*$').firstMatch(title);
    if (match != null) {
      title = match.group(1)!;
      air = match
          .group(2)!
          .replaceFirst(RegExp(r'^AIR\s*', caseSensitive: false), '')
          .replaceAll(RegExp(r'\s*,\s*'), ',');
    }
    name = title.replaceFirst(RegExp(r'^[\s–—-]+'), '').trim();
    final degree = _string(json['degree']).trim();
    final apiAir = _string(json['air']).trim();
    meta = [
      if (degree.isNotEmpty) degree,
      if ((apiAir.isNotEmpty ? apiAir : air) case final a? when a.isNotEmpty)
        'AIR $a',
    ].join(' • ');
    final rating = json['rating'];
    stars = rating is num && rating.round() > 0
        ? rating.round().clamp(0, 5)
        : 5;
  }

  late final String name;
  late final String meta;
  late final int stars;
  final String description;
  final String? image;
}

class _Reviews extends StatefulWidget {
  const _Reviews({required this.future});

  final Future<Map<String, dynamic>?> future;

  @override
  State<_Reviews> createState() => _ReviewsState();
}

class _ReviewsState extends State<_Reviews> {
  final _controller = ScrollController();
  int _page = 0;

  /// CollegeReviewsAdapter.CARD_WIDTH_FRACTION of the row width.
  static double cardWidth(BuildContext context) =>
      (MediaQuery.sizeOf(context).width * 0.8).roundToDouble();
  static const _cardGap = 10.0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final page = (_controller.offset / (cardWidth(context) + _cardGap))
          .round();
      if (page != _page) setState(() => _page = page);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _WhenLoaded<Map<String, dynamic>>(
      future: widget.future,
      builder: (context, guidance) {
        final reviews = _maps(guidance['reviews']).map(_Review.new).toList();
        if (reviews.isEmpty) return const SizedBox.shrink();
        return Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 20, 18, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: Text(
                      'Real Experiences',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 15,
                        height: 1.21,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'See how CollegeBook helped students make better decisions.',
                    style: TextStyle(
                      color: Color(0xFF7C8094),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SingleChildScrollView(
              controller: _controller,
              scrollDirection: Axis.horizontal,
              physics: _CardSnapPhysics(cardWidth(context) + _cardGap),
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final review in reviews)
                      Padding(
                        padding: const EdgeInsets.only(right: _cardGap),
                        child: _ReviewCard(review: review),
                      ),
                  ],
                ),
              ),
            ),
            if (reviews.length > 1)
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < reviews.length; i++)
                      Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.symmetric(horizontal: 5),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i == _page.clamp(0, reviews.length - 1)
                              ? const Color(0xFF045B52)
                              : const Color(0xFFE3E5E8),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

/// PagerSnapHelper: a fling settles on one card at a time.
class _CardSnapPhysics extends ScrollPhysics {
  const _CardSnapPhysics(this.itemExtent, {super.parent});

  final double itemExtent;

  @override
  _CardSnapPhysics applyTo(ScrollPhysics? ancestor) =>
      _CardSnapPhysics(itemExtent, parent: buildParent(ancestor));

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    if ((velocity <= 0 && position.pixels <= position.minScrollExtent) ||
        (velocity >= 0 && position.pixels >= position.maxScrollExtent)) {
      return super.createBallisticSimulation(position, velocity);
    }
    var page = position.pixels / itemExtent;
    if (velocity < -toleranceFor(position).velocity) {
      page = page.floorToDouble();
    } else if (velocity > toleranceFor(position).velocity) {
      page = page.ceilToDouble();
    } else {
      page = page.roundToDouble();
    }
    final target = (page * itemExtent).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((target - position.pixels).abs() < toleranceFor(position).distance) {
      return null;
    }
    return ScrollSpringSimulation(
      spring,
      position.pixels,
      target,
      velocity,
      tolerance: toleranceFor(position),
    );
  }

  @override
  bool get allowImplicitScrolling => false;
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.review});

  final _Review review;

  static const _quoteStyle = TextStyle(
    color: Color(0xFF3B4256),
    fontSize: 14,
    height: 1.43,
  );

  @override
  Widget build(BuildContext context) {
    final quote = review.description.isEmpty ? '' : '“${review.description}”';
    return Semantics(
      button: true,
      child: GestureDetector(
        onTap: () => _showDetailSheet(
          context,
          chip: review.meta,
          title: review.name,
          description: review.description,
        ),
        child: Container(
          width: _ReviewsState.cardWidth(context),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFEDF1F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 65,
                    height: 65,
                    clipBehavior: Clip.antiAlias,
                    decoration: const BoxDecoration(
                      color: Color(0xFFEEF2F4),
                      shape: BoxShape.circle,
                    ),
                    child: _NetImage(
                      review.image,
                      placeholder: 'assets/images/home/iv_user_profile.jpg',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(right: 32),
                            child: Text(
                              review.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _cbNavy,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (review.meta.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 1),
                              child: Text(
                                review.meta,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF6F748A),
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.only(top: 1),
                            child: Row(
                              children: [
                                SvgPicture.asset(
                                  'assets/icons/ic_review_verified.svg',
                                  width: 16,
                                  height: 16,
                                ),
                                const SizedBox(width: 5),
                                const Text(
                                  'Verified User',
                                  style: TextStyle(
                                    color: Color(0xFF13706B),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Image.asset(
                    'assets/images/home/img_review_quote.png',
                    width: 26,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                // minLines 3 / maxLines 3.
                height: 3 * 14 * 1.43,
                child: LayoutBuilder(
                  builder: (context, constraints) => Text.rich(
                    _readMore(quote, constraints.maxWidth, context),
                    maxLines: 3,
                    style: _quoteStyle,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  for (var i = 0; i < review.stars; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 3),
                      child: SvgPicture.asset(
                        'assets/icons/ic_review_star.svg',
                        width: 16,
                        height: 16,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// InlineReadMore.build(): text over three lines is cut as
  /// "... Read More" (bold, #0B6965).
  static InlineSpan _readMore(String text, double width, BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    int lines(InlineSpan span) {
      final painter = TextPainter(
        text: span,
        textDirection: TextDirection.ltr,
        textScaler: scaler,
      )..layout(maxWidth: width);
      return painter.computeLineMetrics().length;
    }

    final full = TextSpan(text: text, style: _quoteStyle);
    if (lines(full) <= 3) return full;
    const readMore = TextSpan(
      text: 'Read More',
      style: TextStyle(color: Color(0xFF0B6965), fontWeight: FontWeight.w700),
    );
    var end = text.length;
    while (end > 0) {
      final candidate = TextSpan(
        style: _quoteStyle,
        children: [
          TextSpan(text: '${text.substring(0, end).trim()}... '),
          readMore,
        ],
      );
      if (lines(candidate) <= 3) return candidate;
      end--;
    }
    return const TextSpan(style: _quoteStyle, children: [readMore]);
  }
}

// ---- FAQs -------------------------------------------------------------------

class _Faqs extends StatelessWidget {
  const _Faqs({required this.future});

  final Future<Map<String, dynamic>?> future;

  @override
  Widget build(BuildContext context) {
    return _WhenLoaded<Map<String, dynamic>>(
      future: future,
      builder: (context, guidance) {
        final faqs = _maps(guidance['faqs']);
        if (faqs.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Text(
                'Frequently asked questions',
                style: TextStyle(
                  color: AppColors.primary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Column(
                children: [for (final faq in faqs) _FaqRow(faq: faq)],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _FaqRow extends StatefulWidget {
  const _FaqRow({required this.faq});

  final Map<String, dynamic> faq;

  @override
  State<_FaqRow> createState() => _FaqRowState();
}

class _FaqRowState extends State<_FaqRow> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(3),
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFFE6E6E6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.only(left: 12, right: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _string(widget.faq['title']),
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Icon(Icons.add, size: 24, color: Color(0xFF1A1A1A)),
                ],
              ),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.only(left: 12, right: 6, top: 2),
              child: Text(
                _string(widget.faq['description']),
                style: const TextStyle(color: Colors.black, fontSize: 14),
              ),
            ),
        ],
      ),
    );
  }
}
