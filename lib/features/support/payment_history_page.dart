import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';

import '../home/college_guide_api.dart';

const _iconColor = Color(0xFF004D40);

class _CallItem {
  _CallItem(Map<String, dynamic> json)
    : status = '${json['status'] ?? ''}',
      startTime = json['start_time'] as String?,
      duration = '${json['duration_formatted'] ?? ''}',
      charged = (json['total_charged'] as num?)?.toInt() ?? 0,
      name = (json['counsellor'] as Map?)?['name'] as String?,
      image = (json['counsellor'] as Map?)?['image'] as String?;

  final String status;
  final String? startTime;
  final String duration;
  final int charged;
  final String? name;
  final String? image;

  /// "18 Jul 2026, 06:19 AM" in local time (the API time is UTC).
  String get date {
    final raw = startTime;
    if (raw == null || raw.isEmpty) return '';
    final trimmed = raw.length >= 19 ? raw.substring(0, 19) : raw;
    final parsed = DateTime.tryParse('${trimmed}Z');
    if (parsed == null) return raw;
    return DateFormat('dd MMM yyyy, hh:mm a').format(parsed.toLocal());
  }

  Color get statusColor => switch (status) {
    'ONGOING' => const Color(0xFF4CAF50),
    'COMPLETED' => const Color(0xFF9E9E9E),
    _ => const Color(0xFFE53935),
  };
}

/// PaymentHistoryActivity: the user's mentor calls, 10 per page.
class PaymentHistoryPage extends StatefulWidget {
  const PaymentHistoryPage({super.key, required this.api});

  final CollegeGuideApiRepository api;

  @override
  State<PaymentHistoryPage> createState() => _PaymentHistoryPageState();
}

class _PaymentHistoryPageState extends State<PaymentHistoryPage> {
  static const _limit = 10;

  final _scroll = ScrollController();
  final List<_CallItem> _items = [];
  int _page = 1;
  bool _loading = false;
  bool _hasNext = true;
  bool _firstLoad = true;
  bool _empty = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_loading || !_hasNext) return;
      if (_scroll.position.extentAfter <= 100) {
        _page++;
        _load();
      }
    });
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final json = await widget.api.send(
        'GET',
        'college/call/history/',
        query: {'page': '$_page', 'limit': '$_limit'},
      );
      final data = json['data'] is Map ? json['data'] as Map : const {};
      final results = [
        for (final r in (data['results'] as List? ?? const []))
          if (r is Map<String, dynamic>) _CallItem(r),
      ];
      if (!mounted) return;
      setState(() {
        _hasNext = data['next'] == true;
        if (_firstLoad) _empty = results.isEmpty;
        _items.addAll(results);
      });
    } on CollegeGuideApiException {
      // Logged only, as natively.
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      _firstLoad = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // SystemNavigationUtils.systemCollege: black bars.
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
          child: ColoredBox(
            color: Colors.white,
            child: Column(
              children: [
                // MaterialToolbar: 55dp, back icon, 16sp Inter bold title.
                Container(
                  height: 55,
                  color: _iconColor,
                  child: Row(
                    children: [
                      Semantics(
                        label: 'Back',
                        button: true,
                        child: InkResponse(
                          onTap: () => Navigator.of(context).maybePop(),
                          radius: 24,
                          child: SizedBox(
                            width: 56,
                            height: 55,
                            child: Center(
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
                      const SizedBox(width: 4),
                      const Text(
                        'My Sessions',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Stack(
                    children: [
                      ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(4, 0, 4, 16),
                        itemCount: _items.length,
                        itemBuilder: (_, i) => _CallRow(item: _items[i]),
                      ),
                      if (_firstLoad && _loading)
                        const Center(child: CircularProgressIndicator()),
                      if (_empty)
                        const Center(
                          child: Text(
                            'No call history found',
                            style: TextStyle(
                              color: Color(0xFF9E9E9E),
                              fontSize: 14,
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

/// item_call_history.xml.
class _CallRow extends StatelessWidget {
  const _CallRow({required this.item});

  final _CallItem item;

  @override
  Widget build(BuildContext context) {
    final fallback = SvgPicture.asset(
      'assets/icons/ic_profile.svg',
      width: 48,
      height: 48,
    );
    final image = item.image;
    return Card(
      margin: const EdgeInsets.all(4),
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipOval(
              child: SizedBox(
                width: 48,
                height: 48,
                child: image == null || image.isEmpty
                    ? fallback
                    : CachedNetworkImage(
                        imageUrl: image,
                        fit: BoxFit.cover,
                        placeholder: (_, _) => fallback,
                        errorWidget: (_, _, _) => fallback,
                      ),
              ),
            ),
            const SizedBox(width: 12),
            // Name, duration and date on the left; status and the amount
            // under it on the right.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name ?? '-',
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.duration,
                    style: const TextStyle(
                      color: Color(0xFF757575),
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.date,
                    style: const TextStyle(
                      color: Color(0xFF9E9E9E),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: item.statusColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    item.status,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '₹${item.charged}',
                  style: const TextStyle(
                    color: Color(0xFF283593),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
