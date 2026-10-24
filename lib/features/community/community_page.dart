import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../home/college_guide_api.dart';
import 'group_chat.dart';
import 'qna.dart';

const _state = Color(0xFF1E4B3E);
const _allIndia = Color(0xFFE0FFC2);
const _iconColor = Color(0xFF004D40);

/// DataProvider.counsellingStates — the state picker's list.
const counsellingStates = [
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
  'Delhi',
  'Jammu and Kashmir',
  'Ladakh',
  'Lakshadweep',
  'Puducherry',
];

/// PreferenceManager.getDefaultState(): the counselling state, Telangana
/// until one is picked.
class DefaultStateStore {
  static const _key = 'college_guide_default_state';
  static const _storage = FlutterSecureStorage();

  /// The last value read or written this session.
  static String? cached;

  static Future<String> read() async {
    try {
      final v = await _storage.read(key: _key);
      if (v != null && v.trim().isNotEmpty) return cached = v;
    } on Object {
      // No secure storage (tests).
    }
    await write('Telangana');
    return 'Telangana';
  }

  static Future<void> write(String state) async {
    cached = state;
    try {
      await _storage.write(key: _key, value: state);
    } on Object {
      // No secure storage (tests).
    }
  }
}

/// The Community tab — CollegeQnATabsFragment.
class CommunityPage extends StatefulWidget {
  const CommunityPage({super.key, required this.api});

  final CollegeGuideApiRepository api;

  @override
  State<CommunityPage> createState() => _CommunityPageState();
}

class _CommunityPageState extends State<CommunityPage> {
  static const _chats = 0;
  static const _discussions = 1;

  String? _stateName = DefaultStateStore.cached ?? 'Telangana';
  bool _allIndiaSelected = true;
  int _mode = _chats;

  final _chatKey = GlobalKey<GroupChatViewState>();
  final _allIndiaQna = GlobalKey<QnaListViewState>();
  final _stateQna = GlobalKey<QnaListViewState>();

  @override
  void initState() {
    super.initState();
    DefaultStateStore.read().then((s) {
      if (mounted) setState(() => _stateName = s);
    });
  }

  void _selectMode(int mode) {
    if (mode == _mode) return;
    if (mode == _discussions) _chatKey.currentState?.onLeftChat();
    setState(() => _mode = mode);
  }

  void _tapAllIndia() => setState(() => _allIndiaSelected = true);

  void _tapState() {
    if (!_allIndiaSelected) {
      // Already on the state: tapping again opens the picker.
      _pickState();
    } else {
      setState(() => _allIndiaSelected = false);
    }
  }

  Future<void> _pickState() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _StatePickerSheet(selected: _stateName),
    );
    if (picked == null || !mounted) return;
    await DefaultStateStore.write(picked);
    setState(() {
      _stateName = picked;
      _allIndiaSelected = false;
    });
  }

  Future<void> _ask() async {
    final tags = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => AskQuestionPage(api: widget.api)),
    );
    if (tags == null || !mounted) return;
    // Open the tab the question was tagged under, then reload both lists.
    var allIndia = false;
    var state = false;
    for (final tag in tags.split(',')) {
      final t = tag.trim().toLowerCase();
      if (t == 'all india') allIndia = true;
      if (_stateName != null && t == _stateName!.toLowerCase()) state = true;
    }
    final onAllIndia = _allIndiaSelected;
    if (!((onAllIndia && allIndia) || (!onAllIndia && state))) {
      if (allIndia) {
        setState(() => _allIndiaSelected = true);
      } else if (state) {
        setState(() => _allIndiaSelected = false);
      }
    }
    _refreshQna();
  }

  void _refreshQna() {
    _allIndiaQna.currentState?.refresh();
    _stateQna.currentState?.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final stateName = _stateName;
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
            color: const Color(0xFFF2EDE4),
            child: Column(
              key: const Key('communityScreen'),
              children: [
                _Header(
                  stateName: stateName ?? '',
                  allIndiaSelected: _allIndiaSelected,
                  mode: _mode,
                  onAllIndia: _tapAllIndia,
                  onState: _tapState,
                  onMode: _selectMode,
                ),
                Expanded(
                  child: stateName == null
                      ? const SizedBox.expand()
                      : Stack(
                          children: [
                            Offstage(
                              offstage: _mode != _chats,
                              child: GroupChatView(
                                key: _chatKey,
                                api: widget.api,
                                allIndia: _allIndiaSelected,
                                state: stateName,
                              ),
                            ),
                            if (_mode == _discussions) ...[
                              Offstage(
                                offstage: !_allIndiaSelected,
                                child: QnaListView(
                                  key: _allIndiaQna,
                                  api: widget.api,
                                  selection: 'All India',
                                  onAsk: _ask,
                                  onAnswered: _refreshQna,
                                ),
                              ),
                              Offstage(
                                offstage: _allIndiaSelected,
                                child: QnaListView(
                                  key: _stateQna,
                                  api: widget.api,
                                  selection: stateName,
                                  onAsk: _ask,
                                  onAnswered: _refreshQna,
                                ),
                              ),
                              Positioned(
                                right: 16,
                                bottom: 16,
                                child: _AskButton(onTap: _ask),
                              ),
                            ],
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

/// The green header: the All India / state toggle over Chats / Q&A tabs.
class _Header extends StatelessWidget {
  const _Header({
    required this.stateName,
    required this.allIndiaSelected,
    required this.mode,
    required this.onAllIndia,
    required this.onState,
    required this.onMode,
  });

  final String stateName;
  final bool allIndiaSelected;
  final int mode;
  final VoidCallback onAllIndia;
  final VoidCallback onState;
  final ValueChanged<int> onMode;

  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    bool dropdown = false,
  }) {
    final color = selected ? _state : Colors.white;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        excludeSemantics: true,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            height: 36,
            padding: dropdown
                ? const EdgeInsets.only(left: 12, right: 6)
                : const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: selected ? _allIndia : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: color,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (dropdown)
                  SvgPicture.asset(
                    'assets/icons/ic_baseline_arrow_drop_down_24.svg',
                    width: 24,
                    height: 24,
                    colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tab(String label, int index) {
    final selected = mode == index;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        excludeSemantics: true,
        child: InkWell(
          splashColor: const Color(0x1FFFFFFF),
          onTap: () => onMode(index),
          child: SizedBox(
            height: 44,
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
                    bottom: 0,
                    child: Builder(
                      builder: (context) {
                        final width = (TextPainter(
                          text: TextSpan(
                            text: label,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          textDirection: TextDirection.ltr,
                          textScaler: MediaQuery.textScalerOf(context),
                        )..layout()).width;
                        return Container(
                          width: width,
                          height: 3,
                          decoration: const BoxDecoration(
                            color: _allIndia,
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(3),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
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
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: const Color(0x1AFFFFFF),
              borderRadius: BorderRadius.circular(12),
            ),
            // The stroke is drawn inside the track, as a shape drawable does.
            foregroundDecoration: BoxDecoration(
              border: Border.all(color: const Color(0x40FFFFFF)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                _chip(
                  label: 'All India Counselling',
                  selected: allIndiaSelected,
                  onTap: onAllIndia,
                ),
                _chip(
                  label: stateName,
                  selected: !allIndiaSelected,
                  onTap: onState,
                  dropdown: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [_tab('Chats', 0), _tab('Q&A', 1)]),
        ],
      ),
    );
  }
}

/// fab_ask: the compact "Ask" pill.
class _AskButton extends StatelessWidget {
  const _AskButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _iconColor,
      elevation: 6,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Container(
          height: 40,
          padding: const EdgeInsets.only(left: 14, right: 16),
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
                'Ask',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// specialty_bottomsheet_layout.xml: the states at 80% of the screen.
class _StatePickerSheet extends StatelessWidget {
  const _StatePickerSheet({required this.selected});

  final String? selected;

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.8;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Container(
        height: height,
        margin: const EdgeInsets.only(top: 8),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            24,
            0,
            24,
            MediaQuery.paddingOf(context).bottom,
          ),
          children: [
            for (final s in counsellingStates)
              GestureDetector(
                onTap: () => Navigator.of(context).pop(s),
                child: Container(
                  margin: const EdgeInsets.all(2),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: s == selected
                        ? const Color(0xFF283593)
                        : Colors.white,
                    border: s == selected
                        ? null
                        : Border.all(color: const Color(0xFFD3DADE)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    s,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: s == selected ? Colors.white : Colors.black,
                      fontSize: 16,
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
