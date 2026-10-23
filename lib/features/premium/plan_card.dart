import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';

const _iconColor = Color(0xFF004D40);
const _appColor = Color(0xFF12151B);
const _secondary = Color(0xFF6B7280);

class PlanFeature {
  const PlanFeature(this.name, this.available);

  final String name;
  final bool available;
}

class Plan {
  Plan(Map<String, dynamic> json)
    : id = '${json['id']}',
      name = json['name'] as String? ?? 'Plan',
      description = json['description'] as String?,
      price = (json['price'] as num?)?.toInt() ?? 0,
      features = [
        for (final f in (json['features'] as List? ?? const []))
          if (f is Map)
            PlanFeature(
              '${f['feature_name'] ?? ''}',
              f['is_available'] == true,
            ),
      ];

  final String id;
  final String name;
  final String? description;
  final int price;
  final List<PlanFeature> features;

  /// "₹24,999" — Indian digit grouping, as the native NumberFormat(en_IN).
  String get priceText =>
      '₹${NumberFormat.decimalPattern('en_IN').format(price)}';
}

/// row_services_plans.xml (CollegeServicePlansAdapter): green header band
/// with tier icon and price, the feature checklist, and its own buy button.
class PlanCard extends StatefulWidget {
  const PlanCard({
    super.key,
    required this.plan,
    required this.index,
    required this.count,
    required this.onContinue,
  });

  final Plan plan;
  final int index;
  final int count;
  final VoidCallback onContinue;

  @override
  State<PlanCard> createState() => _PlanCardState();
}

class _PlanCardState extends State<PlanCard> {
  static const _collapsed = 6;
  bool _open = false;

  /// Star, then crown, with a diamond for the last of three or more.
  String get _icon {
    if (widget.count >= 3 && widget.index == widget.count - 1) {
      return 'ic_plan_tier_diamond';
    }
    return widget.index == 0 ? 'ic_plan_tier_star' : 'ic_plan_tier_crown';
  }

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    // Included features first.
    final sorted = [
      ...plan.features.where((f) => f.available),
      ...plan.features.where((f) => !f.available),
    ];
    final collapsible = sorted.length > _collapsed;
    final shown = collapsible && !_open ? sorted.take(_collapsed) : sorted;
    final description = plan.description ?? '';
    return Container(
      margin: const EdgeInsets.fromLTRB(2, 10, 2, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x24000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFDCE9E3)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // bg_plan_header_popular: gradient band with two faint circles.
          Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF1A7A63), _iconColor],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: -90,
                right: -60,
                child: _circle(170, const Color(0x14FFFFFF)),
              ),
              Positioned(
                bottom: -50,
                right: 40,
                child: _circle(90, const Color(0x0FFFFFFF)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0x26FFFFFF),
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0x40FFFFFF)),
                          ),
                          child: SvgPicture.asset(
                            'assets/icons/$_icon.svg',
                            colorFilter: const ColorFilter.mode(
                              Colors.white,
                              BlendMode.srcIn,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                plan.name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (description.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    description,
                                    style: const TextStyle(
                                      color: Color(0xD9FFFFFF),
                                      fontSize: 12.5,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          plan.priceText,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.w700,
                            height: 1.0,
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.only(left: 8, bottom: 2),
                          child: Text(
                            'one-time payment',
                            style: TextStyle(
                              color: Color(0xB3FFFFFF),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "WHAT'S INCLUDED",
                  style: TextStyle(
                    color: _secondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 11 * 0.08,
                  ),
                ),
                const SizedBox(height: 6),
                for (final f in shown) _FeatureRow(f),
                if (collapsible)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: InkWell(
                      onTap: () => setState(() => _open = !_open),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Text(
                          _open
                              ? 'Show less'
                              : '+ ${sorted.length - _collapsed} more features',
                          style: const TextStyle(
                            color: _iconColor,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                Material(
                  borderRadius: BorderRadius.circular(28),
                  clipBehavior: Clip.antiAlias,
                  child: Ink(
                    height: 52,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF1A7A63), _iconColor],
                      ),
                    ),
                    child: InkWell(
                      onTap: widget.onContinue,
                      child: Center(
                        child: Text(
                          'Continue  ·  ${plan.priceText}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 15 * 0.01,
                          ),
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
    );
  }

  static Widget _circle(double size, Color color) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

/// item_plan_feature.xml.
class _FeatureRow extends StatelessWidget {
  const _FeatureRow(this.feature);

  final PlanFeature feature;

  @override
  Widget build(BuildContext context) {
    final included = feature.available;
    return Semantics(
      label: '${included ? 'Included' : 'Not included'}: ${feature.name}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: SvgPicture.asset(
                'assets/icons/${included ? 'ic_plan_check' : 'ic_plan_unavailable'}.svg',
                width: 18,
                height: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Opacity(
                opacity: included ? 1 : 0.7,
                child: Text(
                  feature.name,
                  style: TextStyle(
                    color: included ? _appColor : _secondary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    // 14sp line plus lineSpacingExtra="2dp".
                    height: 1.5,
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
