import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/native_bridge.dart';
import '../home/college_guide_api.dart';
import 'reels_player_page.dart';

const _state = Color(0xFF1E4B3E);
const _iconColor = Color(0xFF004D40);

/// One row of DiscoverFragment: a reels category and its videos.
class _Section {
  _Section(Map<String, dynamic> json)
    : title = '${(json['category'] as Map?)?['name'] ?? ''}',
      categoryId = ((json['category'] as Map?)?['id'] as num?)?.toInt() ?? -1,
      cards = [
        for (final v in (json['videos'] as List? ?? const []))
          if (v is Map)
            (id: '${v['id']}', thumbnail: v['thumbnail'] as String?),
      ];

  final String title;
  final int categoryId;
  final List<({String id, String? thumbnail})> cards;
}

/// The Videos tab — DiscoverFragment (fragment_discover.xml).
class VideosPage extends StatefulWidget {
  const VideosPage({super.key, required this.api});

  final CollegeGuideApiRepository api;

  @override
  State<VideosPage> createState() => _VideosPageState();
}

class _VideosPageState extends State<VideosPage> {
  List<_Section>? _sections;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final json = await widget.api.send('GET', 'reels/landing/');
      final data = json['data'];
      final results = data is Map ? data['results'] : null;
      if (!mounted) return;
      setState(() {
        _sections = [
          for (final s in (results as List? ?? const []))
            if (s is Map<String, dynamic>) _Section(s),
        ];
      });
    } on CollegeGuideApiException catch (e) {
      if (!mounted) return;
      showToast(context, e.message);
      // A failed first load shows the empty message, as the native list
      // stays hidden until sections arrive.
      setState(() => _sections ??= const []);
    }
  }

  void _open(int categoryId, String? videoId) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReelsPlayerPage(
          api: widget.api,
          categoryId: categoryId,
          startVideoId: videoId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sections = _sections;
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
            color: const Color(0xFFF5F5F5),
            child: Column(
              key: const Key('videosScreen'),
              children: [
                // common_header_college_layout with back, search and the
                // premium box hidden.
                Container(
                  width: double.infinity,
                  color: _state,
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                  child: const Text(
                    'Videos',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      // TextView font padding.
                      height: 1.47,
                    ),
                  ),
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _load,
                    child: sections == null
                        ? const SizedBox.expand()
                        : sections.isEmpty
                        ? LayoutBuilder(
                            builder: (context, box) => ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: [
                                SizedBox(
                                  height: box.maxHeight,
                                  child: const Center(
                                    child: Padding(
                                      padding: EdgeInsets.all(12),
                                      child: Text(
                                        "We're working on adding reels — pull down to refresh.",
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: Colors.black,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView(
                            physics: const AlwaysScrollableScrollPhysics(
                              parent: ClampingScrollPhysics(),
                            ),
                            padding: const EdgeInsets.only(bottom: 12),
                            children: [
                              for (final s in sections)
                                _SectionView(
                                  section: s,
                                  onCard: (id) => _open(s.categoryId, id),
                                  onViewAll: () => _open(s.categoryId, null),
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

/// item_section.xml.
class _SectionView extends StatelessWidget {
  const _SectionView({
    required this.section,
    required this.onCard,
    required this.onViewAll,
  });

  final _Section section;
  final ValueChanged<String> onCard;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 20, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    section.title,
                    style: const TextStyle(
                      color: _iconColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Semantics(
                  button: true,
                  label: 'View All ${section.title}',
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onViewAll,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SvgPicture.asset(
                            'assets/icons/ic_play_arrow.svg',
                            width: 12,
                            height: 12,
                            colorFilter: const ColorFilter.mode(
                              _iconColor,
                              BlendMode.srcIn,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Text(
                            'View All',
                            style: TextStyle(
                              color: _iconColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
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
          SizedBox(
            height: 180 + 8 + 16,
            child: ListView(
              scrollDirection: Axis.horizontal,
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              children: [
                for (final card in section.cards)
                  _DiscoverCard(
                    thumbnail: card.thumbnail,
                    onTap: () => onCard(card.id),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// item_discover_card.xml: a 130x180 8dp card holding the thumbnail.
class _DiscoverCard extends StatelessWidget {
  const _DiscoverCard({required this.thumbnail, required this.onTap});

  final String? thumbnail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final url = thumbnail;
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Material(
        color: const Color(0xFFFDF7FD),
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 130,
            height: 180,
            child: url == null || url.isEmpty
                ? null
                : CachedNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.cover,
                    errorWidget: (_, _, _) => const SizedBox.shrink(),
                  ),
          ),
        ),
      ),
    );
  }
}
