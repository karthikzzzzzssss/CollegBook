import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/native_bridge.dart';
import '../home/college_guide_api.dart';

const _state = Color(0xFF1E4B3E);
const _allIndia = Color(0xFFE0FFC2);
const _iconColor = Color(0xFF004D40);
const _chatBg = Color(0xFFF2EDE4);
const _textDark = Color(0xFF1C1E21);
const _meta = Color(0xFF6B7280);
const _sheetText = Color(0xFF1B2B26);

const _pageSize = 40;

/// The tag list of the native "Select Tags" screen.
const askTags = [
  'All india',
  'Andhra Pradesh',
  'Arunachal Pradesh',
  'Assam',
  'Bihar',
  'Chhattisgarh',
  'Goa',
  'Gujarat',
  'Haryana',
  'Himachal Pradesh',
  'Jharkhand',
  'Karnataka',
  'Kerala',
  'Madhya Pradesh',
  'Maharashtra',
  'Manipur',
  'Meghalaya',
  'Mizoram',
  'Nagaland',
  'Odisha',
  'Punjab',
  'Rajasthan',
  'Sikkim',
  'Tamil Nadu',
  'Telangana',
  'Tripura',
  'Uttar Pradesh',
  'Uttarakhand',
  'West Bengal',
  'Andaman and Nicobar Islands',
  'Chandigarh',
  'Dadra and Nagar Haveli and Daman and Diu',
  'Lakshadweep',
  'Delhi',
  'Puducherry',
  'Ladakh',
  'Jammu and Kashmir',
];

/// The picked tags ("All india,Telangana") as the API files them: All India
/// is "AIC", so the question lists under All India as well as the state.
String apiTags(String tags) => [
  for (final tag in tags.split(','))
    if (tag.trim().isNotEmpty)
      tag.trim().toLowerCase() == 'all india' ? 'AIC' : tag.trim(),
].join(',');

/// Html.fromHtml(...).toString() for the plain titles/answers the API sends.
String _plain(String? html) {
  var s = (html ?? '')
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'");
  s = s.replaceAll(RegExp(r'[ \t\r\n]+'), ' ');
  return s.trim();
}

String _cleanName(String? name) =>
    (name ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');

class QnaItem {
  QnaItem(Map<String, dynamic> json)
    : id = (json['id'] as num?)?.toInt() ?? 0,
      title = _plain(json['title'] as String?),
      name = _cleanName(json['name'] as String?),
      date = json['create_date'] as String?,
      tags = [for (final t in (json['tags_array'] as List? ?? const [])) '$t'],
      totalComment = (json['total_comment'] as num?)?.toInt() ?? 0,
      answers = [
        for (final c in (json['comments'] as List? ?? const []))
          if (c is Map && _plain(c['comment'] as String?).isNotEmpty)
            (
              text: _plain(c['comment'] as String?),
              name: _cleanName(c['name'] as String?),
            ),
      ];

  final int id;
  final String title;
  final String name;
  final String? date;
  final List<String> tags;
  final int totalComment;
  final List<({String text, String name})> answers;
}

/// One Q&A page (CollegeQandAFragment): "All India" or a state.
class QnaListView extends StatefulWidget {
  const QnaListView({
    super.key,
    required this.api,
    required this.selection,
    required this.onAsk,
    this.onAnswered,
  });

  final CollegeGuideApiRepository api;
  final String selection;
  final VoidCallback onAsk;

  /// An answer was posted. A question tagged All India and a state is in
  /// both lists, so the page reloads both; without it this list reloads.
  final VoidCallback? onAnswered;

  @override
  State<QnaListView> createState() => QnaListViewState();
}

class QnaListViewState extends State<QnaListView>
    with AutomaticKeepAliveClientMixin {
  final _scroll = ScrollController();
  final List<QnaItem> _items = [];
  int _page = 1;
  bool _lastPage = false;
  bool _loading = false;
  bool _loaded = false;
  bool _failed = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 1) _load();
    });
    _load();
  }

  @override
  void didUpdateWidget(QnaListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new state from the picker: its own list from the first page.
    if (oldWidget.selection != widget.selection) refresh();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// A new question was posted: back to the top with fresh data.
  Future<void> refresh() async {
    if (_scroll.hasClients) _scroll.jumpTo(0);
    await _load(refresh: true);
  }

  Future<void> _load({bool refresh = false}) async {
    if (_loading || (_lastPage && !refresh)) return;
    if (refresh) {
      _page = 1;
      _lastPage = false;
      _items.clear();
    }
    final allIndia = widget.selection == 'All India';
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final json = await widget.api.send(
        'GET',
        'college/homepage',
        query: {
          'page': '$_page',
          'limit': '$_pageSize',
          'state': allIndia ? '' : widget.selection,
          'councelling_type': allIndia ? 'AIC' : 'SC',
          'query': 'user-post',
        },
      );
      final data = json['data'] is Map ? json['data'] as Map : const {};
      final total = (data['total_page'] as num?)?.toInt() ?? 1;
      _lastPage = _page >= total;
      final seen = {for (final i in _items) i.id};
      for (final r in (data['results'] as List? ?? const [])) {
        if (r is Map<String, dynamic>) {
          final item = QnaItem(r);
          // The API accepts blank questions; they'd show as empty cards.
          if (item.title.isNotEmpty && seen.add(item.id)) _items.add(item);
        }
      }
      _page++;
      _loaded = true;
    } on CollegeGuideApiException {
      // An empty list says so instead of "No discussions yet"; pull to retry.
      _loaded = true;
      _failed = true;
      if (mounted && _items.isNotEmpty) {
        showToast(context, 'Couldn\'t load more discussions');
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _openQuestion(QnaItem item) async {
    final answered = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AnswersSheet(api: widget.api, item: item),
    );
    if (answered != true) return;
    final onAnswered = widget.onAnswered;
    onAnswered == null ? refresh() : onAnswered();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final empty = _loaded && !_loading && _items.isEmpty;
    final failed = empty && _failed;
    return ColoredBox(
      color: _chatBg,
      child: RefreshIndicator(
        color: _state,
        onRefresh: () => _load(refresh: true),
        child: Stack(
          children: [
            ListView(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(top: 4, bottom: 108),
              children: [
                for (final item in _items)
                  _QuestionCard(item: item, onOpen: () => _openQuestion(item)),
              ],
            ),
            if (failed)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    'Couldn\'t load discussions. Check your internet and '
                    'pull down to try again.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _state, fontSize: 15),
                  ),
                ),
              )
            else if (empty)
              _EmptyState(onStart: widget.onAsk),
            if (_loading && _items.isEmpty)
              const Center(child: CircularProgressIndicator(color: _state)),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: _allIndia,
                shape: BoxShape.circle,
              ),
              child: SvgPicture.asset(
                'assets/icons/ic_forum_outline.svg',
                colorFilter: const ColorFilter.mode(_state, BlendMode.srcIn),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'No discussions yet',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _textDark,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              "Ask about cutoffs, colleges or counselling rounds and get answers from students who've been there.",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _meta,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                height: 1.36,
              ),
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: onStart,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: _state,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SvgPicture.asset(
                      'assets/icons/ic_edit_pencil_small.svg',
                      width: 16,
                      height: 16,
                      colorFilter: const ColorFilter.mode(
                        Colors.white,
                        BlendMode.srcIn,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'Start a discussion',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// row_college_qanda.xml.
class _QuestionCard extends StatelessWidget {
  const _QuestionCard({required this.item, required this.onOpen});

  final QnaItem item;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final poster = item.name.isEmpty ? 'Guest' : item.name;
    final count = item.totalComment > item.answers.length
        ? item.totalComment
        : item.answers.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Material(
        color: Colors.white,
        elevation: 1,
        shadowColor: const Color(0x55000000),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          color: _allIndia,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          poster.substring(0, 1).toUpperCase(),
                          style: const TextStyle(
                            color: _state,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              poster,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _textDark,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if ((item.date ?? '').isNotEmpty)
                              Text(
                                item.date!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: _meta,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                  child: Text(
                    item.title,
                    style: const TextStyle(
                      color: _textDark,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      height: 1.4,
                    ),
                  ),
                ),
                if (item.answers.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: _AnswerCards(
                      question: item.title,
                      answers: item.answers,
                    ),
                  ),
                Container(
                  height: 1,
                  margin: const EdgeInsets.only(top: 12),
                  color: const Color(0xFFEEEAE2),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      SvgPicture.asset(
                        'assets/icons/ic_comment_outline_small.svg',
                        width: 16,
                        height: 16,
                        colorFilter: const ColorFilter.mode(
                          _meta,
                          BlendMode.srcIn,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          count == 0
                              ? 'No answers yet'
                              : count == 1
                              ? '1 answer'
                              : '$count answers',
                          style: const TextStyle(
                            color: _meta,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      Material(
                        color: _allIndia,
                        borderRadius: BorderRadius.circular(16),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          splashColor: const Color(0x331E4B3E),
                          onTap: onOpen,
                          child: Container(
                            height: 32,
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            alignment: Alignment.center,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SvgPicture.asset(
                                  'assets/icons/ic_edit_pencil_small.svg',
                                  width: 16,
                                  height: 16,
                                  colorFilter: const ColorFilter.mode(
                                    _state,
                                    BlendMode.srcIn,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                const Text(
                                  'Answer',
                                  style: TextStyle(
                                    color: _state,
                                    fontSize: 12,
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// QnAAnswerCardAdapter: a lone answer spans the row; several show 1.5
/// cards so the next one peeks in. "... Read More" opens the full answer.
class _AnswerCards extends StatelessWidget {
  const _AnswerCards({required this.question, required this.answers});

  final String question;
  final List<({String text, String name})> answers;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        const gap = 8.0;
        final available = box.maxWidth - 28;
        final alone = answers.length == 1;
        final cardWidth = alone
            ? available
            : (available - gap * (1.5 - 1)) / 1.5;
        final cards = [
          for (final a in answers)
            _AnswerCard(
              width: cardWidth,
              answer: a,
              alone: alone,
              onOpen: () => _showDetail(context, a),
            ),
        ];
        if (alone) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: cards.single,
          );
        }
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < cards.length; i++)
                  Padding(
                    padding: EdgeInsets.only(
                      right: i == cards.length - 1 ? 0 : gap,
                    ),
                    child: cards[i],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// bottom_sheet_news_detail.xml with the question and the full answer.
  void _showDetail(BuildContext context, ({String text, String name}) answer) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.9,
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            20,
            12,
            20,
            24 + MediaQuery.paddingOf(sheetContext).bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      answer.name,
                      style: const TextStyle(
                        color: _meta,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    icon: const Icon(Icons.close, color: _meta),
                  ),
                ],
              ),
              Text(
                question,
                style: const TextStyle(
                  color: _textDark,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                answer.text,
                style: const TextStyle(
                  color: Color(0xFF3C4043),
                  fontSize: 15,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnswerCard extends StatelessWidget {
  const _AnswerCard({
    required this.width,
    required this.answer,
    required this.alone,
    required this.onOpen,
  });

  final double width;
  final ({String text, String name}) answer;
  final bool alone;
  final VoidCallback onOpen;

  static const _textStyle = TextStyle(
    color: Colors.black,
    fontSize: 13,
    fontWeight: FontWeight.w500,
    height: 1.37,
  );

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onOpen,
      child: Container(
        width: width,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF3FBEA),
          border: Border.all(color: const Color(0xFFDDEFC9)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Visibility.maintain(
              visible: answer.name.isNotEmpty,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  answer.name.isEmpty ? ' ' : 'Answer by ${answer.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _meta,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            // Card width less its 12dp padding and 1dp stroke each side.
            _ReadMoreText(
              text: answer.text,
              width: width - 26,
              maxLines: 3,
              minLines: alone ? 1 : 3,
              style: _textStyle,
            ),
          ],
        ),
      ),
    );
  }
}

/// InlineReadMore: three lines, the last ending in "... Read More".
class _ReadMoreText extends StatelessWidget {
  const _ReadMoreText({
    required this.text,
    required this.width,
    required this.maxLines,
    required this.minLines,
    required this.style,
  });

  final String text;
  final double width;
  final int maxLines;
  final int minLines;
  final TextStyle style;

  static const _more = 'Read More';

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    // Measure in the font the Text will actually use (Inter from the theme).
    final style = DefaultTextStyle.of(context).style.merge(this.style);
    TextPainter layout(InlineSpan span) => TextPainter(
      text: span,
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: maxLines,
    )..layout(maxWidth: width);
    final full = layout(TextSpan(text: text, style: style));
    final lineHeight = scaler.scale(style.fontSize! * style.height!);
    Widget result;
    if (!full.didExceedMaxLines) {
      result = Text(text, style: style);
    } else {
      final moreStyle = style.copyWith(
        color: const Color(0xFF003300),
        fontWeight: FontWeight.w700,
      );
      var lo = 0;
      var hi = text.length;
      while (lo < hi) {
        final mid = (lo + hi + 1) ~/ 2;
        final probe = layout(
          TextSpan(
            style: style,
            children: [
              TextSpan(text: '${text.substring(0, mid).trimRight()}... '),
              TextSpan(text: _more, style: moreStyle),
            ],
          ),
        );
        if (probe.didExceedMaxLines) {
          hi = mid - 1;
        } else {
          lo = mid;
        }
      }
      result = Text.rich(
        TextSpan(
          style: style,
          children: [
            TextSpan(text: '${text.substring(0, lo).trimRight()}... '),
            TextSpan(text: _more, style: moreStyle),
          ],
        ),
        maxLines: maxLines,
      );
    }
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: lineHeight * minLines),
      child: result,
    );
  }
}

/// bottomsheet_qna_layout.xml: the question, its answers with up/down votes,
/// and a "Write answer" bar.
class AnswersSheet extends StatefulWidget {
  const AnswersSheet({super.key, required this.api, required this.item});

  final CollegeGuideApiRepository api;
  final QnaItem item;

  @override
  State<AnswersSheet> createState() => _AnswersSheetState();
}

class _Answer {
  _Answer(Map json)
    : id = (json['id'] as num?)?.toInt() ?? 0,
      text = '${json['comment'] ?? ''}',
      liked = (json['status'] as Map?)?['like_status'] == true,
      unliked = (json['status'] as Map?)?['unlike_status'] == true;

  final int id;
  final String text;
  bool liked;
  bool unliked;
}

class _AnswersSheetState extends State<AnswersSheet> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  List<_Answer>? _answers;
  bool _posting = false;
  bool _answered = false;

  @override
  void initState() {
    super.initState();
    _input.addListener(() => setState(() {}));
    _load();
    // The native sheet opens with the keyboard up on "Write answer".
    Future<void>.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final json = await widget.api.send(
        'GET',
        'college/question-comments/${widget.item.id}/',
      );
      final data = json['data'] is Map ? json['data'] as Map : const {};
      if (!mounted) return;
      setState(() {
        _answers = [
          for (final r in (data['results'] as List? ?? const []))
            if (r is Map) _Answer(r),
        ];
      });
    } on CollegeGuideApiException {
      if (mounted) setState(() => _answers ??= []);
    }
  }

  Future<void> _post() async {
    final text = _input.text.trim();
    if (text.isEmpty || _posting) return;
    setState(() => _posting = true);
    try {
      await widget.api.send(
        'POST',
        'college/question-comments/${widget.item.id}/',
        body: {'comment': text},
      );
      _answered = true;
      _input.clear();
      FocusManager.instance.primaryFocus?.unfocus();
      await _load();
    } on CollegeGuideApiException catch (e) {
      // The answer stays in the box to try again.
      if (mounted) {
        showToast(
          context,
          e.payload == null ? 'Network failure, please try again.' : e.message,
        );
      }
    }
    if (mounted) setState(() => _posting = false);
  }

  /// college/question-comments-reaction/ {comment_id, action}.
  Future<void> _react(_Answer a, String action) async {
    try {
      final json = await widget.api.send(
        'POST',
        'college/question-comments-reaction/',
        body: {'comment_id': a.id, 'action': action},
      );
      final data = json['data'];
      if (data is! Map || !mounted) return;
      setState(() {
        final liked = data['like_status'] == true;
        final unliked = data['unlike_status'] == true;
        if (action == 'like') {
          a.liked = liked;
          if (liked) a.unliked = false;
        } else {
          a.unliked = unliked;
          if (unliked) {
            a.liked = false;
          } else if (liked) {
            a.liked = true;
          }
        }
      });
    } on CollegeGuideApiException {
      // Unchanged, as natively.
    }
  }

  String get _tags {
    final out = <String>[];
    for (final tag in widget.item.tags) {
      var t = tag.trim().replaceFirst(RegExp('^@'), '');
      if (t.isEmpty) continue;
      if (t.toUpperCase() == 'AIC') t = 'All India';
      out.add(t);
    }
    return out.join('  ·  ');
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final answers = _answers;
    final count = answers?.length ?? 0;
    final tags = _tags;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: PopScope(
        onPopInvokedWithResult: (didPop, _) {},
        child: Padding(
          // 60dp under the status bar (the modal hides its inset from us).
          padding: EdgeInsets.only(
            top: MediaQueryData.fromView(View.of(context)).viewPadding.top + 60,
          ),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                Container(
                  height: 60,
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: Color(0xFFE3ECE8)),
                    ),
                  ),
                  child: Stack(
                    children: [
                      Align(
                        alignment: Alignment.topCenter,
                        child: Container(
                          width: 40,
                          height: 4,
                          margin: const EdgeInsets.only(top: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFD3DED9),
                            borderRadius: BorderRadius.circular(40),
                          ),
                        ),
                      ),
                      // Title and close are centred in the bar, 6dp down.
                      Positioned.fill(
                        left: 16,
                        top: 6,
                        child: Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Question & Answers',
                                style: TextStyle(
                                  color: _sheetText,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Semantics(
                              label: 'Close',
                              button: true,
                              child: InkResponse(
                                onTap: () =>
                                    Navigator.of(context).pop(_answered),
                                child: Container(
                                  width: 36,
                                  height: 36,
                                  margin: const EdgeInsets.only(right: 10),
                                  padding: const EdgeInsets.all(9),
                                  child: SvgPicture.asset(
                                    'assets/icons/ic_baseline_close.svg',
                                    colorFilter: const ColorFilter.mode(
                                      Color(0xFF5C6B66),
                                      BlendMode.srcIn,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ColoredBox(
                    color: const Color(0xFFF6FAF7),
                    child: ListView(
                      padding: const EdgeInsets.only(bottom: 12),
                      children: [
                        Container(
                          color: Colors.white,
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.item.title,
                                style: const TextStyle(
                                  color: _sheetText,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  height: 1.45,
                                ),
                              ),
                              if (tags.isNotEmpty)
                                Container(
                                  margin: const EdgeInsets.only(top: 10),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE6F2ED),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    tags,
                                    style: const TextStyle(
                                      color: _iconColor,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Container(height: 1, color: const Color(0xFFE3ECE8)),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                          child: Text(
                            answers == null
                                ? 'ANSWERS'
                                : count == 0
                                ? 'NO ANSWERS YET'
                                : count == 1
                                ? '1 ANSWER'
                                : '$count ANSWERS',
                            style: const TextStyle(
                              color: _meta,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 12 * 0.06,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        for (final a in answers ?? const <_Answer>[])
                          _AnswerRow(
                            answer: a,
                            onLike: () => _react(a, 'like'),
                            onUnlike: () => _react(a, 'unlike'),
                          ),
                      ],
                    ),
                  ),
                ),
                Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(top: BorderSide(color: Color(0xFFE3ECE8))),
                  ),
                  padding: EdgeInsets.fromLTRB(
                    12,
                    10,
                    12,
                    10 +
                        (media.viewInsets.bottom > 0
                            ? media.viewInsets.bottom
                            : media.padding.bottom),
                  ),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 48),
                    padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F7F5),
                      border: Border.all(color: const Color(0xFFDCE9E3)),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Row(
                      children: [
                        ClipOval(
                          child: Image.asset(
                            'assets/images/home/iv_user_profile.jpg',
                            width: 30,
                            height: 30,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Container(
                              width: 30,
                              height: 30,
                              color: const Color(0xFFDDDDDD),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: TextField(
                              key: const Key('answerInput'),
                              controller: _input,
                              focusNode: _focus,
                              minLines: 1,
                              maxLines: 5,
                              keyboardType: TextInputType.multiline,
                              textCapitalization: TextCapitalization.sentences,
                              cursorColor: _sheetText,
                              style: const TextStyle(
                                color: _sheetText,
                                fontSize: 14.5,
                              ),
                              decoration: const InputDecoration(
                                hintText: 'Write answer',
                                hintStyle: TextStyle(
                                  color: Color(0xFF8A9A94),
                                  fontSize: 14.5,
                                ),
                                isDense: true,
                                filled: false,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                          ),
                        ),
                        if (_input.text.trim().isNotEmpty)
                          Semantics(
                            label: 'Send answer',
                            button: true,
                            child: GestureDetector(
                              onTap: _posting ? null : _post,
                              child: Container(
                                width: 36,
                                height: 36,
                                padding: const EdgeInsets.all(9),
                                decoration: const BoxDecoration(
                                  color: _iconColor,
                                  shape: BoxShape.circle,
                                ),
                                child: SvgPicture.asset(
                                  'assets/icons/ic_baseline_send_24.svg',
                                  colorFilter: const ColorFilter.mode(
                                    Colors.white,
                                    BlendMode.srcIn,
                                  ),
                                ),
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
      ),
    );
  }
}

/// article_comments_row.xml.
class _AnswerRow extends StatelessWidget {
  const _AnswerRow({
    required this.answer,
    required this.onLike,
    required this.onUnlike,
  });

  final _Answer answer;
  final VoidCallback onLike;
  final VoidCallback onUnlike;

  static const _on = _iconColor;
  static const _off = Color(0xFF455A64);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 5, 16, 5),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE1ECE7)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            answer.text,
            style: const TextStyle(
              color: _sheetText,
              fontSize: 14.5,
              height: 1.42,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              InkWell(
                onTap: onLike,
                child: SizedBox(
                  height: 32,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Row(
                      children: [
                        SvgPicture.asset(
                          'assets/icons/ic_baseline_thumb_up_24.svg',
                          width: 16,
                          height: 16,
                          colorFilter: ColorFilter.mode(
                            answer.liked ? _on : _off,
                            BlendMode.srcIn,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Upvote',
                          style: TextStyle(
                            color: answer.liked ? _on : _off,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Semantics(
                label: 'Downvote',
                button: true,
                child: InkResponse(
                  onTap: onUnlike,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: SvgPicture.asset(
                      'assets/icons/ic_baseline_thumb_down_24.svg',
                      width: 16,
                      height: 16,
                      colorFilter: ColorFilter.mode(
                        answer.unliked ? _on : _off,
                        BlendMode.srcIn,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// CollegeQnAPostActivity: "Ask a Question". Pops the posted tags.
class AskQuestionPage extends StatefulWidget {
  const AskQuestionPage({super.key, required this.api});

  final CollegeGuideApiRepository api;

  @override
  State<AskQuestionPage> createState() => _AskQuestionPageState();
}

class _AskQuestionPageState extends State<AskQuestionPage> {
  final _title = TextEditingController();
  String? _tags;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _pickTags() async {
    final picked = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => SelectTagsPage(selected: _tags)),
    );
    if (picked != null) setState(() => _tags = picked);
  }

  Future<void> _post() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      showToast(context, 'Please write question');
      return;
    }
    final tags = _tags;
    if (tags == null) {
      showToast(context, 'Please select tags');
      return;
    }
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 24),
              Text('Posting...'),
            ],
          ),
        ),
      ),
    );
    final navigator = Navigator.of(context);
    try {
      final json = await widget.api.send(
        'POST',
        'college/homepage',
        body: {'title': title, 'tags': apiTags(tags)},
      );
      navigator.pop();
      if (!mounted) return;
      showToast(context, '${json['message'] ?? 'No message found'}');
      navigator.pop(tags);
    } on CollegeGuideApiException catch (e) {
      navigator.pop();
      if (!mounted) return;
      showToast(
        context,
        e.payload == null ? 'Network failure, please try again.' : e.message,
      );
    }
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
          child: GestureDetector(
            onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
            child: ColoredBox(
              color: const Color(0xFFF6FAF7),
              child: Column(
                children: [
                  _AskHeader(
                    title: 'Ask a Question',
                    trailing: GestureDetector(
                      onTap: _post,
                      child: Container(
                        height: 36,
                        margin: const EdgeInsets.only(right: 16),
                        padding: const EdgeInsets.symmetric(horizontal: 22),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _iconColor,
                          borderRadius: BorderRadius.circular(28),
                        ),
                        child: const Text(
                          'Post',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                    child: SizedBox(
                      height: 180,
                      child: TextField(
                        key: const Key('questionInput'),
                        controller: _title,
                        expands: true,
                        maxLines: null,
                        textAlignVertical: TextAlignVertical.top,
                        keyboardType: TextInputType.multiline,
                        textCapitalization: TextCapitalization.sentences,
                        cursorColor: _sheetText,
                        style: const TextStyle(
                          color: _sheetText,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          height: 1.4,
                        ),
                        decoration: _askBox('Type your question...'),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                    child: GestureDetector(
                      onTap: _pickTags,
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 52),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: const Color(0xFFDCE9E3)),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _tags == null
                                    ? 'Select Tags...'
                                    : _tags!.replaceAll(',', ', '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: _tags == null
                                      ? const Color(0xFF8A9A94)
                                      : _iconColor,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SvgPicture.asset(
                              'assets/icons/ic_baseline_keyboard_arrow_down_24.svg',
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
                  const Expanded(child: SizedBox.expand()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static InputDecoration _askBox(String hint) {
    OutlineInputBorder border(Color c, double w) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: c, width: w),
    );
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(
        color: Color(0xFF8A9A94),
        fontSize: 15,
        fontWeight: FontWeight.w500,
      ),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.all(16),
      border: border(const Color(0xFFDCE9E3), 1),
      enabledBorder: border(const Color(0xFFDCE9E3), 1),
      focusedBorder: border(_iconColor, 1.5),
    );
  }
}

/// The white 56dp header with back + title (bg_ask_header).
class _AskHeader extends StatelessWidget {
  const _AskHeader({required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE3ECE8))),
      ),
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
                    _sheetText,
                    BlendMode.srcIn,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _sheetText,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// BigDoctorPickDataActivity for tags: up to two chips, then "Done".
class SelectTagsPage extends StatefulWidget {
  const SelectTagsPage({super.key, this.selected});

  final String? selected;

  @override
  State<SelectTagsPage> createState() => _SelectTagsPageState();
}

class _SelectTagsPageState extends State<SelectTagsPage> {
  static const _max = 2;
  final _picked = <String>[];

  /// Like the native screen, Done only knows about taps made here.
  String? _result;

  @override
  void initState() {
    super.initState();
    for (final part in (widget.selected ?? '').split(',')) {
      final t = part.trim();
      if (t.isEmpty || _picked.length >= _max) continue;
      _picked.add(t);
    }
  }

  void _toggle(String tag) {
    setState(() {
      if (_picked.contains(tag)) {
        _picked.remove(tag);
      } else {
        if (_picked.length >= _max) {
          showToast(context, 'You can select up to $_max only');
          return;
        }
        _picked.add(tag);
      }
      _result = _picked.join(',');
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.white,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Column(
            children: [
              const _AskHeader(title: 'Select Tags'),
              Expanded(
                child: ColoredBox(
                  color: const Color(0xFFF6FAF7),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
                    child: Wrap(
                      children: [
                        for (final tag in askTags)
                          Padding(
                            padding: const EdgeInsets.all(4),
                            child: _TagChip(
                              label: tag,
                              selected: _picked.contains(tag),
                              onTap: () => _toggle(tag),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              GestureDetector(
                onTap: () {
                  final result = _result;
                  if (result == null || result.trim().isEmpty) {
                    showToast(context, 'Please Select Tags');
                    return;
                  }
                  Navigator.of(context).pop(result);
                },
                child: Container(
                  height: 52,
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _iconColor,
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: const Text(
                    'Done',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
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

class _TagChip extends StatelessWidget {
  const _TagChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 38),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: selected ? _iconColor : Colors.white,
          border: selected ? null : Border.all(color: const Color(0xFFD6E3DE)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 9),
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : const Color(0xFF2B3A35),
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 9),
          ],
        ),
      ),
    );
  }
}
