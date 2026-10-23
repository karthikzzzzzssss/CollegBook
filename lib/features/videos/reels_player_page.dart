import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:video_player/video_player.dart';

import '../home/college_guide_api.dart';

/// colorPrimary of the native Material 3 theme: ReelsPlayerActivity keeps
/// the theme's status bar.
const _themePrimary = Color(0xFF6750A4);

class _Reel {
  _Reel(Map<String, dynamic> json)
    : id = '${json['id']}',
      thumbnail = json['thumbnail'] as String?,
      caption = '${json['caption'] ?? ''}',
      videoFile = json['video_file'] as String?,
      categoryName = '${(json['category'] as Map?)?['name'] ?? ''}',
      likesCount = (json['likes_count'] as num?)?.toInt() ?? 0,
      liked = json['is_liked'] == true,
      bookmarked = json['is_bookmarked'] == true;

  final String id;
  final String? thumbnail;
  final String caption;
  final String? videoFile;
  final String categoryName;
  int likesCount;
  bool liked;
  bool bookmarked;
}

/// ReelsPlayerActivity: a vertical pager of full-screen looping videos for a
/// category (or the recommended feed), paged by cursor five at a time.
class ReelsPlayerPage extends StatefulWidget {
  const ReelsPlayerPage({
    super.key,
    required this.api,
    this.categoryId = -1,
    this.startVideoId,
    this.recommended = false,
  });

  final CollegeGuideApiRepository api;
  final int categoryId;
  final String? startVideoId;

  /// newIntentRecommended: reels/recommended/ instead of a category feed.
  final bool recommended;

  @override
  State<ReelsPlayerPage> createState() => _ReelsPlayerPageState();
}

class _ReelsPlayerPageState extends State<ReelsPlayerPage>
    with WidgetsBindingObserver {
  static const _pageSize = 5;

  final _pager = PageController();
  final List<_Reel> _reels = [];
  VideoPlayerController? _player;
  int _active = -1;
  bool _loadingMore = false;
  bool _userHasDragged = false;
  String? _nextCursor;
  String? _previousCursor;
  bool _hasNext = false;
  bool _hasPrevious = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadInitial();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _player?.dispose();
    _pager.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // onPause / onResume.
    if (state == AppLifecycleState.resumed) {
      _player?.play();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _player?.pause();
    }
  }

  Future<List<_Reel>?> _fetch(String? direction, String? cursor) async {
    final query = <String, String>{
      'direction': ?direction,
      'cursor': ?cursor,
      'limit': '$_pageSize',
      if (widget.recommended) 'page': '1',
    };
    try {
      final json = await widget.api.send(
        'GET',
        widget.recommended
            ? 'reels/recommended/'
            : 'reels/feed-cursor/${widget.categoryId}/',
        query: query,
      );
      final data = json['data'];
      if (data is! Map) return const [];
      final p = data['pagination'];
      _hasNext = p is Map && p['has_next'] == true;
      _hasPrevious = p is Map && p['has_previous'] == true;
      _nextCursor = p is Map ? p['next_cursor'] as String? : null;
      _previousCursor = p is Map ? p['previous_cursor'] as String? : null;
      return [
        for (final r in (data['results'] as List? ?? const []))
          if (r is Map<String, dynamic>) _Reel(r),
      ];
    } on CollegeGuideApiException {
      // The native player only logs a failed feed load.
      return null;
    }
  }

  Future<void> _loadInitial() async {
    setState(() => _loadingMore = true);
    final start = widget.startVideoId;
    final results = await _fetch(start == null ? null : 'next', start);
    if (!mounted) return;
    setState(() {
      _loadingMore = false;
      _reels
        ..clear()
        ..addAll(results ?? const []);
    });
    if (_reels.isNotEmpty) _playAt(0);
  }

  void _onPageChanged(int position) {
    _playAt(position);
    if (!_userHasDragged) return;
    _loadNextIfNeeded(position);
    _loadPreviousIfNeeded(position);
  }

  /// Only from the last loaded reel, once, while the server has more.
  Future<void> _loadNextIfNeeded(int position) async {
    if (position != _reels.length - 1 || !_hasNext || _loadingMore) return;
    setState(() => _loadingMore = true);
    final results = await _fetch('next', _nextCursor);
    if (!mounted) return;
    setState(() {
      _loadingMore = false;
      _reels.addAll(results ?? const []);
    });
  }

  /// Only from the first loaded reel; keeps the same reel on screen.
  Future<void> _loadPreviousIfNeeded(int position) async {
    if (position != 0 || !_hasPrevious || _loadingMore) return;
    setState(() => _loadingMore = true);
    final results = await _fetch('previous', _previousCursor);
    if (!mounted) return;
    setState(() => _loadingMore = false);
    if (results == null || results.isEmpty) return;
    final count = results.length;
    setState(() {
      _reels.insertAll(0, results);
      _active += count;
    });
    _pager.jumpToPage(_pager.page!.round() + count);
  }

  Future<void> _playAt(int position) async {
    if (position < 0 || position >= _reels.length || position == _active) {
      return;
    }
    _active = position;
    final old = _player;
    _player = null;
    setState(() {});
    await old?.dispose();
    final url = _reels[position].videoFile;
    if (url == null || url.isEmpty) return;
    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    _player = controller;
    try {
      await controller.initialize();
    } on Object {
      // A failed reel stays on its thumbnail, as natively.
      return;
    }
    if (!mounted || _player != controller) return;
    await controller.setLooping(true);
    await controller.play();
    if (mounted) setState(() {});
  }

  Future<void> _toggle(_Reel reel, {required bool like}) async {
    final endpoint = like ? 'reels/like/' : 'reels/bookmark/';
    final now = like ? !reel.liked : !reel.bookmarked;
    setState(() {
      if (like) {
        reel.liked = now;
        reel.likesCount = (reel.likesCount + (now ? 1 : -1)).clamp(0, 1 << 31);
      } else {
        reel.bookmarked = now;
      }
    });
    try {
      await widget.api.send(
        'POST',
        endpoint,
        body: {
          'reel_id': reel.id,
          'action': like
              ? (now ? 'like' : 'unlike')
              : (now ? 'bookmark' : 'unbookmark'),
        },
      );
    } on CollegeGuideApiException {
      if (!mounted) return;
      setState(() {
        if (like) {
          reel.liked = !now;
          reel.likesCount += now ? -1 : 1;
        } else {
          reel.bookmarked = !now;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: _themePrimary,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Column(
          children: [
            Container(height: padding.top, color: _themePrimary),
            Expanded(
              child: Stack(
                children: [
                  NotificationListener<ScrollStartNotification>(
                    onNotification: (n) {
                      if (n.dragDetails != null) _userHasDragged = true;
                      return false;
                    },
                    child: PageView.builder(
                      key: const Key('reelsPager'),
                      controller: _pager,
                      scrollDirection: Axis.vertical,
                      itemCount: _reels.length,
                      onPageChanged: _onPageChanged,
                      itemBuilder: (context, i) => _ReelPage(
                        reel: _reels[i],
                        player: i == _active ? _player : null,
                        onLike: () => _toggle(_reels[i], like: true),
                        onBookmark: () => _toggle(_reels[i], like: false),
                      ),
                    ),
                  ),
                  if (_loadingMore)
                    const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                  Positioned(
                    top: 12,
                    left: 12,
                    child: Semantics(
                      label: 'Back',
                      button: true,
                      child: GestureDetector(
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
                  ),
                ],
              ),
            ),
            Container(height: padding.bottom, color: Colors.white),
          ],
        ),
      ),
    );
  }
}

/// item_reel_video.xml.
class _ReelPage extends StatelessWidget {
  const _ReelPage({
    required this.reel,
    required this.player,
    required this.onLike,
    required this.onBookmark,
  });

  final _Reel reel;
  final VideoPlayerController? player;
  final VoidCallback onLike;
  final VoidCallback onBookmark;

  static const _shadow = [Shadow(color: Color(0x99000000), blurRadius: 4)];

  @override
  Widget build(BuildContext context) {
    final controller = player;
    final playing = controller != null && controller.value.isInitialized;
    final thumb = reel.thumbnail;
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (playing)
            // resize_mode="zoom": fill, cropping the overflow.
            ClipRect(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: controller.value.size.width,
                  height: controller.value.size.height,
                  child: VideoPlayer(controller),
                ),
              ),
            )
          else if (controller == null && thumb != null && thumb.isNotEmpty)
            CachedNetworkImage(
              imageUrl: thumb,
              fit: BoxFit.cover,
              errorWidget: (_, _, _) => const SizedBox.shrink(),
            ),
          Align(
            alignment: Alignment.bottomLeft,
            child: Padding(
              padding: const EdgeInsets.only(right: 72),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      reel.categoryName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        shadows: _shadow,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      reel.caption,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        shadows: _shadow,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 12, bottom: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ActionDisc(
                    label: 'Like',
                    icon: reel.liked
                        ? 'assets/icons/ic_heart_filled.svg'
                        : 'assets/icons/ic_heart_outline.svg',
                    tint: reel.liked ? const Color(0xFFFF3B5C) : Colors.white,
                    padding: 11,
                    onTap: onLike,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${reel.likesCount}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      shadows: _shadow,
                    ),
                  ),
                  const SizedBox(height: 18),
                  _ActionDisc(
                    label: 'Save',
                    icon: 'assets/icons/ic_bookmark_outline.svg',
                    tint: reel.bookmarked
                        ? const Color(0xFFFFC107)
                        : Colors.white,
                    padding: 12,
                    onTap: onBookmark,
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

/// bg_reel_action: a 48dp translucent dark disc behind the icon.
class _ActionDisc extends StatelessWidget {
  const _ActionDisc({
    required this.label,
    required this.icon,
    required this.tint,
    required this.padding,
    required this.onTap,
  });

  final String label;
  final String icon;
  final Color tint;
  final double padding;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 48,
          height: 48,
          padding: EdgeInsets.all(padding),
          decoration: const BoxDecoration(
            color: Color(0x59000000),
            shape: BoxShape.circle,
          ),
          child: SvgPicture.asset(
            icon,
            colorFilter: ColorFilter.mode(tint, BlendMode.srcIn),
          ),
        ),
      ),
    );
  }
}
