import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/native_bridge.dart';
import 'legal_content.dart';

const _state = Color(0xFF1E4B3E);
const _iconColor = Color(0xFF004D40);
const _appColor = Color(0xFF12151B);
const _secondary = Color(0xFF6B7280);
const _body = Color(0xFF4B5563);
const _pageBg = Color(0xFFF6FAF7);

/// The dialer with the support number filled in (callSupport).
Future<void> callSupport(BuildContext context) async {
  final opened = await dial('+91$supportPhone');
  if (!opened && context.mounted) {
    showToast(context, 'Call us on $supportPhoneDisplay');
  }
}

/// A WhatsApp chat with support: WhatsApp, else WhatsApp Business, else
/// wa.me in the browser (whatsAppSupport).
Future<void> whatsAppSupport(BuildContext context) async {
  final url =
      'https://wa.me/91$supportPhone?text=${Uri.encodeComponent('Hi CollegeBook team, I need help with ')}';
  for (final app in const ['com.whatsapp', 'com.whatsapp.w4b', null]) {
    if (await viewUrl(url, package: app)) return;
  }
  if (context.mounted) {
    showToast(context, 'WhatsApp us on $supportPhoneDisplay');
  }
}

/// layout_cb_header: green bar with back and title.
class CbHeader extends StatelessWidget {
  const CbHeader({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
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
              onTap: () => Navigator.of(context).maybePop(),
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
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
    );
  }
}

/// A page with the CB header under a green status bar.
class _CbScaffold extends StatelessWidget {
  const _CbScaffold({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: _state,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: _state,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: _state,
        body: SafeArea(
          child: ColoredBox(
            color: _pageBg,
            child: Column(
              children: [
                CbHeader(title: title),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                    children: children,
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

/// bg_cb_hero: gradient card with a round icon, title and text.
class _CbHero extends StatelessWidget {
  const _CbHero({required this.icon, required this.title, required this.text});

  final String icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_state, _iconColor],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              color: Color(0x26FFFFFF),
              shape: BoxShape.circle,
            ),
            child: SvgPicture.asset(
              'assets/icons/$icon.svg',
              colorFilter: const ColorFilter.mode(
                Colors.white,
                BlendMode.srcIn,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Semantics(
            header: true,
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            text,
            style: const TextStyle(
              color: Color(0xE6FFFFFF),
              fontSize: 13.5,
              height: 1.46,
            ),
          ),
        ],
      ),
    );
  }
}

BoxDecoration _card() => BoxDecoration(
  color: Colors.white,
  borderRadius: BorderRadius.circular(14),
  border: Border.all(color: const Color(0xFFE3E5E8)),
);

Widget _pill({
  required String label,
  required VoidCallback onTap,
  String? icon,
  bool outline = false,
  double height = 50,
}) {
  final fg = outline ? _state : Colors.white;
  return Material(
    color: outline ? Colors.white : _state,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(28),
      side: outline
          ? const BorderSide(color: Color(0xFFD1D5DB))
          : BorderSide.none,
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: SizedBox(
        height: height,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              SvgPicture.asset(
                'assets/icons/$icon.svg',
                width: 18,
                height: 18,
                colorFilter: ColorFilter.mode(fg, BlendMode.srcIn),
              ),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: TextStyle(
                color: fg,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _sectionTitle(String text) => Padding(
  padding: const EdgeInsets.fromLTRB(4, 22, 0, 10),
  child: Text(
    text,
    style: const TextStyle(
      color: _appColor,
      fontSize: 16,
      fontWeight: FontWeight.w600,
    ),
  ),
);

/// ContactUsActivity (activity_contact_us.xml).
class ContactUsPage extends StatelessWidget {
  const ContactUsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return _CbScaffold(
      title: 'Contact Us',
      children: [
        const _CbHero(
          icon: 'ic_cb_support',
          title: "We're here to help",
          text: 'Questions about counselling, mentor calls, payments or your account? Talk to the CollegeBook team.',
        ),
        Container(
          margin: const EdgeInsets.only(top: 16),
          padding: const EdgeInsets.all(20),
          decoration: _card(),
          child: Column(
            children: [
              const Text(
                'Call or WhatsApp us',
                style: TextStyle(
                  color: _secondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              const SelectableText(
                supportPhoneDisplay,
                style: TextStyle(
                  color: _appColor,
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _pill(
                      label: 'Call now',
                      icon: 'ic_cb_phone',
                      onTap: () => callSupport(context),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _pill(
                      label: 'WhatsApp',
                      icon: 'ic_cb_chat',
                      outline: true,
                      onTap: () => whatsAppSupport(context),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        _sectionTitle('We can help you with'),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: _card(),
          child: const Text(
            '•  Using cutoffs, matching and choice lists\n'
            '•  Booking or joining a mentor call\n'
            '•  Wallet top-ups and payments\n'
            '•  Premium packages\n'
            '•  Login or account problems\n'
            '•  Becoming a mentor on CollegeBook',
            // lineSpacingExtra="6dp".
            style: TextStyle(color: _body, fontSize: 13.5, height: 1.65),
          ),
        ),
        _sectionTitle('Policies'),
        const PolicyLinks(),
      ],
    );
  }
}

/// Privacy Policy and Terms & Conditions rows (item_cb_link_row.xml).
class PolicyLinks extends StatelessWidget {
  const PolicyLinks({super.key, this.withContact = false});

  /// About's "Help & legal": a Contact Us row first.
  final bool withContact;

  @override
  Widget build(BuildContext context) {
    Widget row(
      String icon,
      String title,
      String subtitle,
      LegalDoc? doc,
    ) => InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              doc == null ? const ContactUsPage() : LegalDocumentPage(doc: doc),
        ),
      ),
      child: Container(
        constraints: const BoxConstraints(minHeight: 64),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              padding: const EdgeInsets.all(10),
              decoration: const BoxDecoration(
                color: Color(0xFFE6EEEA),
                shape: BoxShape.circle,
              ),
              child: SvgPicture.asset(
                'assets/icons/$icon.svg',
                colorFilter: const ColorFilter.mode(_state, BlendMode.srcIn),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: _appColor,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(color: _secondary, fontSize: 12.5),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            SvgPicture.asset(
              'assets/icons/ic_cb_chevron_right.svg',
              width: 24,
              height: 24,
              colorFilter: const ColorFilter.mode(_secondary, BlendMode.srcIn),
            ),
          ],
        ),
      ),
    );
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: _card(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          if (withContact)
            row(
              'ic_cb_support',
              'Contact Us',
              'Call or WhatsApp $supportPhoneDisplay',
              null,
            ),
          row(
            'ic_cb_privacy',
            'Privacy Policy',
            'How we collect and protect your data',
            LegalDoc.privacy,
          ),
          row(
            'ic_cb_terms',
            'Terms & Conditions',
            'The rules for using CollegeBook',
            LegalDoc.terms,
          ),
        ],
      ),
    );
  }
}

/// LegalDocumentActivity: Privacy Policy or Terms & Conditions.
class LegalDocumentPage extends StatelessWidget {
  const LegalDocumentPage({super.key, required this.doc});

  final LegalDoc doc;

  @override
  Widget build(BuildContext context) {
    final sections = legalSections(doc);
    return _CbScaffold(
      title: legalTitle(doc),
      children: [
        _CbHero(
          icon: doc == LegalDoc.privacy ? 'ic_cb_privacy' : 'ic_cb_terms',
          title: legalTitle(doc),
          text: legalIntro(doc),
        ),
        const SizedBox(height: 4),
        for (var i = 0; i < sections.length; i++)
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(16),
            decoration: _card(),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(
                  child: Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: _state,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 2),
                      Semantics(
                        header: true,
                        child: Text(
                          sections[i].$1,
                          style: const TextStyle(
                            color: _appColor,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SelectableText(
                        sections[i].$2,
                        style: const TextStyle(
                          color: _body,
                          fontSize: 14,
                          height: 1.57,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        Container(
          margin: const EdgeInsets.only(top: 20),
          padding: const EdgeInsets.all(20),
          decoration: _card(),
          child: Column(
            children: [
              const Text(
                'Still have a question?',
                style: TextStyle(
                  color: _appColor,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Our team is a call or a WhatsApp message away.',
                textAlign: TextAlign.center,
                style: TextStyle(color: _secondary, fontSize: 13),
              ),
              const SizedBox(height: 14),
              _pill(
                label: 'Contact Us',
                height: 48,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ContactUsPage(),
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

const _playStoreUrl =
    'https://play.google.com/store/apps/details?id=com.minibrain.collegebook';

/// AboutActivity.shareApp (also the side menu's Share App).
Future<void> shareApp() => shareText(
  text:
      'CollegeBook – by the doctor for the doctor 🩺\n\nNEET PG college cutoffs, rank-wise college matching, fee details, counselling choice lists and 1-to-1 video calls with PGs & faculty – all in one app.\n\nDownload it free: $_playStoreUrl',
  subject: 'CollegeBook – NEET PG college guide',
  title: 'Share CollegeBook via',
);

/// AboutActivity (activity_about.xml).
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  static const _features = [
    (
      'ic_building',
      'Explore colleges',
      'Courses, seats, fellowships, facilities and student Q&A for medical colleges across India.',
    ),
    (
      'ic_cb_file_csv',
      'Cutoffs & rank-wise matching',
      "Previous years' closing ranks by quota and category, and the colleges that match your rank.",
    ),
    (
      'ic_payment',
      'Fee details',
      'Tuition and other fees, college by college, so you can compare before you choose.',
    ),
    (
      'icon_choicelist',
      'Counselling choice lists',
      'Build ordered choice lists for each counselling and download them as PDF or CSV.',
    ),
    (
      'ic_menu_mentor',
      '1-to-1 mentor video calls',
      'Talk directly to PGs and faculty about their hospital, workload and training. Save favourites.',
    ),
    (
      'ic_play_arrow',
      'Webinars & video guides',
      'Step-by-step counselling guides, reels and expert webinars.',
    ),
    (
      'ic_about',
      'Updates & community',
      'Counselling deadlines, official notices and discussions with fellow aspirants.',
    ),
    (
      'school_24px',
      'Become a mentor',
      'Already a PG or faculty member? Register as a mentor and guide aspirants.',
    ),
  ];

  /// The Play Store app if installed, else the store page in the browser.
  Future<void> _rate() async {
    if (await viewUrl('market://details?id=com.minibrain.collegebook')) return;
    await viewUrl(_playStoreUrl);
  }

  @override
  Widget build(BuildContext context) {
    return _CbScaffold(
      title: 'About',
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_state, _iconColor],
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: [
              Container(
                width: 80,
                height: 80,
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(
                  color: Color(0x26FFFFFF),
                  shape: BoxShape.circle,
                ),
                child: Image.asset('assets/images/home/app_icon.png'),
              ),
              const SizedBox(height: 12),
              const Text(
                'CollegeBook',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'by the doctor for the doctor',
                style: TextStyle(
                  color: Color(0xE6FFFFFF),
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        Container(
          margin: const EdgeInsets.only(top: 16),
          padding: const EdgeInsets.all(18),
          decoration: _card(),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Our mission',
                style: TextStyle(
                  color: _state,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 6),
              Text(
                'Turn your NEET PG rank into the right seat.',
                style: TextStyle(
                  color: _appColor,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 10),
              Text(
                'After NEET PG, every aspirant faces the same hard question: which college and course should I lock? The answers are scattered across counselling PDFs, college websites and word of mouth. CollegeBook brings it together – verified cutoffs, seats and fees, a smart way to plan your choices, and direct calls with PGs and faculty who already study and work there – so you can decide with confidence, not guesswork.',
                // lineSpacingExtra="3dp".
                style: TextStyle(color: _body, fontSize: 13.5, height: 1.45),
              ),
            ],
          ),
        ),
        _sectionTitle('What you can do'),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: _card(),
          child: Column(
            children: [
              for (final (icon, title, body) in _features)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        padding: const EdgeInsets.all(10),
                        decoration: const BoxDecoration(
                          color: Color(0xFFE6EEEA),
                          shape: BoxShape.circle,
                        ),
                        child: SvgPicture.asset(
                          'assets/icons/$icon.svg',
                          colorFilter: const ColorFilter.mode(
                            _state,
                            BlendMode.srcIn,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                color: _appColor,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              body,
                              style: const TextStyle(
                                color: _secondary,
                                fontSize: 12.5,
                                height: 1.37,
                              ),
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
        Container(
          margin: const EdgeInsets.only(top: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFE6EEEA),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SvgPicture.asset(
                'assets/icons/ic_cb_privacy.svg',
                width: 22,
                height: 22,
                colorFilter: const ColorFilter.mode(_state, BlendMode.srcIn),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'CollegeBook is an independent platform. We are not affiliated with MCC, NBEMS, NMC or any state counselling authority. Always confirm dates and data on the official portals before locking your choices.',
                  style: TextStyle(color: _state, fontSize: 12.5, height: 1.4),
                ),
              ),
            ],
          ),
        ),
        _sectionTitle('Help & legal'),
        const PolicyLinks(withContact: true),
        const SizedBox(height: 22),
        _pill(
          label: 'Share App',
          icon: 'ic_share',
          height: 52,
          onTap: shareApp,
        ),
        const SizedBox(height: 12),
        _pill(
          label: '★  Rate us on Google Play',
          outline: true,
          height: 52,
          onTap: _rate,
        ),
        Padding(
          padding: const EdgeInsets.only(top: 24),
          child: Text(
            '© ${DateTime.now().year} MiniBrain  ·  Made in India 🇮🇳',
            textAlign: TextAlign.center,
            style: const TextStyle(color: _secondary, fontSize: 12),
          ),
        ),
      ],
    );
  }
}
