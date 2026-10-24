import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/native_bridge.dart';
import '../../core/notification_sync.dart';
import '../auth/auth_api.dart';
import '../auth/login_screen.dart';
import '../auth/session_store.dart';
import '../../theme/app_theme.dart';
import '../cutoff/cutoff_page.dart';
import 'college_guide_api.dart';
import '../community/community_page.dart';
import '../mentor/incoming_consultation.dart';
import '../mentor/mentor_page.dart';
import '../premium/premium_page.dart';
import '../support/as_mentor_page.dart';
import '../support/contact_us_page.dart';
import '../support/payment_history_page.dart';
import '../support/legal_content.dart';
import '../videos/videos_page.dart';
import 'home_page.dart';

/// The native CollegeHomePageActivity: six bottom-nav tabs and the side menu.
class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    this.apiRepository,
    this.sessionStore,
    this.authRepository,
  });

  final CollegeGuideApiRepository? apiRepository;
  final SessionStore? sessionStore;
  final AuthRepository? authRepository;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  late final _notificationSync = NotificationSync(_apiRepository);
  bool _syncingNotifications = false;
  int _selectedIndex = 0;
  int _selectedCollegeTab = 0;
  DateTime? _backPressedAt;

  /// From college/membership/ (the native fetchMembershipPlans()); every tab
  /// treats the user as free until it says otherwise.
  bool _isSubscribed = false;
  late final SessionStore _sessionStore;
  late final CollegeGuideApiRepository _apiRepository;
  late final bool _ownsApiRepository;

  @override
  void initState() {
    super.initState();
    _sessionStore = widget.sessionStore ?? SecureSessionStore();
    _ownsApiRepository = widget.apiRepository == null;
    _apiRepository =
        widget.apiRepository ??
        CollegeGuideApiRepository(sessionStore: _sessionStore);
    _loadMembership();
    // iOS mentor calls (CallKit); a fresh PushKit token goes to the server.
    CounsellorCalls.start(
      _apiRepository,
      onVoipToken: _notificationSync.syncIfEnabled,
    );
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkNotifications());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkNotifications();
  }

  /// Native onResume(): notifications on → make sure the server has this
  /// device's FCM token; off → ask at most once a day.
  Future<void> _checkNotifications() async {
    if (_syncingNotifications || !mounted) return;
    _syncingNotifications = true;
    try {
      await _notificationSync.checkAndSync(context);
    } on Object {
      // Never in the way of using the app (also: no platform in tests).
    } finally {
      _syncingNotifications = false;
    }
  }

  Future<void> _loadMembership() async {
    try {
      final data = await _apiRepository.membership();
      if (mounted) {
        setState(() => _isSubscribed = data['is_subscribed'] == true);
      }
    } on CollegeGuideApiException {
      // Server down: the native app falls back to a free (unsubscribed) model.
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_ownsApiRepository) _apiRepository.close();
    super.dispose();
  }

  /// CollegePackagesActivity, for "Get a Package" / "Go Premium to Apply".
  void _openPackages() => Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => PackagesPage(api: _apiRepository)),
  );

  void _selectSection(int index, {int? collegeTab}) {
    setState(() {
      _selectedIndex = index;
      if (collegeTab != null) _selectedCollegeTab = collegeTab;
    });
  }

  /// Native onBackPressed(): close the menu, else go Home, else
  /// double-back-to-exit.
  void _onBack() {
    final scaffold = _scaffoldKey.currentState;
    if (scaffold != null && scaffold.isDrawerOpen) {
      scaffold.closeDrawer();
      return;
    }
    if (_selectedIndex != 0) {
      _selectSection(0);
      return;
    }
    final now = DateTime.now();
    final last = _backPressedAt;
    _backPressedAt = now;
    if (last != null && now.difference(last) < const Duration(seconds: 2)) {
      SystemNavigator.pop();
    } else {
      showToast(context, 'Press back again to exit');
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _ProgressDialog(message: 'Logging out...'),
    );
    final auth = widget.authRepository ?? AuthRepository();
    try {
      final access = await _sessionStore.readAccessToken();
      if (access != null) {
        await auth.logout(
          accessToken: access,
          refreshToken: await _sessionStore.readRefreshToken(),
        );
      }
    } catch (_) {
      // The server call is best effort; the user is signed out regardless.
    } finally {
      if (widget.authRepository == null) auth.close();
    }
    await _sessionStore.clear();
    try {
      await _notificationSync.clear(); // next login sends its token fresh
    } on Object {
      // Nothing stored (or no platform in tests).
    }
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (_) => LoginScreen(
          authRepository: widget.authRepository,
          sessionStore: _sessionStore,
        ),
      ),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          statusBarColor: AppColors.deepGreen,
          statusBarIconBrightness: Brightness.light,
          systemNavigationBarColor: AppColors.primary,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
        child: Scaffold(
          key: _scaffoldKey,
          backgroundColor: AppColors.primary,
          drawer: _SideMenu(
            sessionStore: _sessionStore,
            api: _apiRepository,
            onLogout: _logout,
          ),
          body: IndexedStack(
            index: _selectedIndex,
            children: [
              HomePage(
                apiRepository: _apiRepository,
                onOpenCutoffTab: (tab) => _selectSection(1, collegeTab: tab),
                onOpenSideMenu: () => _scaffoldKey.currentState?.openDrawer(),
                isSubscribed: _isSubscribed,
                onOpenPremium: () => _selectSection(5),
                onOpenPackages: _openPackages,
              ),
              CutoffPage(
                apiRepository: _apiRepository,
                isSubscribed: _isSubscribed,
                selectedTab: _selectedCollegeTab,
                onTabSelected: (index) =>
                    setState(() => _selectedCollegeTab = index),
                onOpenMentor: () => _selectSection(2),
                onOpenPremium: () => _selectSection(5),
                onOpenPackages: _openPackages,
              ),
              MentorPage(api: _apiRepository),
              VideosPage(api: _apiRepository),
              CommunityPage(api: _apiRepository),
              PremiumPage(api: _apiRepository),
            ],
          ),
          bottomNavigationBar: _BottomNav(
            selectedIndex: _selectedIndex,
            onSelected: _selectSection,
          ),
        ),
      ),
    );
  }
}

/// Material 3 BottomNavigationView as the native app styles it: icon_color
/// bar, 26dp untinted icons, a bg_color (#E0FFC2) pill behind the selected
/// icon and 10sp Inter Medium labels in text_color (#B2DFBB).
class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.selectedIndex, required this.onSelected});

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  static const _items = [
    ('Home', 'ic_baseline_college_home'),
    ('Cutoff', 'ic_baseline_college_package'),
    ('Mentor', 'ic_baseline_college_skill'),
    ('Videos', 'ic_baseline_college_call'),
    ('Community', 'ic_baseline_college_community'),
    ('Premium', 'ic_premium'),
  ];

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      key: const Key('mainNavigation'),
      color: AppColors.primary,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 80,
          child: Row(
            children: [
              for (var i = 0; i < _items.length; i++)
                Expanded(
                  child: _BottomNavItem(
                    label: _items[i].$1,
                    icon: _items[i].$2,
                    selected: i == selectedIndex,
                    index: i,
                    count: _items.length,
                    onTap: () => onSelected(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomNavItem extends StatelessWidget {
  const _BottomNavItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.index,
    required this.count,
    required this.onTap,
  });

  final String label;
  final String icon;
  final bool selected;
  final int index;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      label: '$label\nTab ${index + 1} of $count',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        // M3 BottomNavigationView: the indicator pill 12dp from the top,
        // the label just under it.
        child: LayoutBuilder(
          builder: (context, box) => Column(
            children: [
              const SizedBox(height: 12),
              Container(
                // 64dp, less the indicator's 4dp side margins on narrow items.
                width: (box.maxWidth - 8).clamp(0, 64).toDouble(),
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? const Color(0xFFE0FFC2)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: SvgPicture.asset(
                  'assets/icons/nav/${icon}_${selected ? 'select' : 'unselect'}.svg',
                  width: 26,
                  height: 26,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  color: const Color(0xFFB2DFBB),
                  fontSize: 10,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// UICommonUtils.showProgress(): a small blocking progress dialog.
class _ProgressDialog extends StatelessWidget {
  const _ProgressDialog({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Dialog(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              const CircularProgressIndicator(color: AppColors.primary),
              const SizedBox(width: 20),
              Text(message),
            ],
          ),
        ),
      ),
    );
  }
}

/// NavigationView + nav_header_college + side_menu.xml.
class _SideMenu extends StatefulWidget {
  const _SideMenu({
    required this.sessionStore,
    required this.api,
    required this.onLogout,
  });

  final SessionStore sessionStore;
  final CollegeGuideApiRepository api;
  final VoidCallback onLogout;

  @override
  State<_SideMenu> createState() => _SideMenuState();
}

class _SideMenuState extends State<_SideMenu> {
  late final Future<({String? name, String? phone})> _profile = widget
      .sessionStore
      .readProfile();

  void _select(String id) {
    Navigator.of(context).pop();
    if (id == 'share') {
      shareApp();
      return;
    }
    final api = widget.api;
    final Widget? page = switch (id) {
      'mentor' => AsMentorPage(api: api),
      'payments' => PaymentHistoryPage(api: api),
      'about' => const AboutPage(),
      'contact' => const ContactUsPage(),
      'privacy' => const LegalDocumentPage(doc: LegalDoc.privacy),
      'terms' => const LegalDocumentPage(doc: LegalDoc.terms),
      _ => null,
    };
    if (page != null) {
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
      return;
    }
    switch (id) {
      case 'logout':
        widget.onLogout();
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // While the menu is open the status bar matches its header.
      value: const SystemUiOverlayStyle(
        statusBarColor: AppColors.primary,
        statusBarIconBrightness: Brightness.light,
      ),
      child: Drawer(
        width: 300,
        backgroundColor: Colors.white,
        // NavigationView here draws square edges.
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        clipBehavior: Clip.antiAlias,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            FutureBuilder<({String? name, String? phone})>(
              future: _profile,
              builder: (context, snapshot) => _SideMenuHeader(
                name: snapshot.data?.name,
                phone: snapshot.data?.phone,
              ),
            ),
            const SizedBox(height: 8),
            for (final (id, icon, label) in const [
              ('mentor', 'ic_menu_mentor', 'As a Mentor'),
              ('payments', 'ic_payment', 'Payment History'),
              ('share', 'ic_share', 'Share App'),
            ])
              _SideMenuItem(icon: icon, label: label, onTap: () => _select(id)),
            const Divider(
              height: 17,
              thickness: 1,
              indent: 28,
              endIndent: 28,
              color: Color(0xFF79747E),
            ),
            for (final (id, icon, label) in const [
              ('contact', 'ic_cb_support', 'Contact Us'),
              ('privacy', 'ic_cb_privacy', 'Privacy Policy'),
              ('terms', 'ic_cb_terms', 'Terms & Conditions'),
              ('about', 'ic_about', 'About'),
            ])
              _SideMenuItem(icon: icon, label: label, onTap: () => _select(id)),
            const Divider(
              height: 17,
              thickness: 1,
              indent: 28,
              endIndent: 28,
              color: Color(0xFF79747E),
            ),
            _SideMenuItem(
              icon: 'ic_logout',
              label: 'Logout',
              onTap: () => _select('logout'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SideMenuHeader extends StatelessWidget {
  const _SideMenuHeader({this.name, this.phone});

  final String? name;
  final String? phone;

  @override
  Widget build(BuildContext context) {
    final trimmed = name?.trim() ?? '';
    final initial = trimmed.isEmpty ? '' : trimmed[0].toUpperCase();
    final number = phone == null || phone!.isEmpty
        ? null
        : (phone!.startsWith('+') ? phone! : '+91 $phone');
    return Container(
      color: AppColors.primary,
      padding: EdgeInsets.fromLTRB(
        20,
        // The header runs under the status bar without adding its inset.
        28,
        20,
        22,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Container(
              width: 50,
              height: 50,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: initial.isEmpty
                    ? const Color(0xFFEEF2F4)
                    : const Color(0xFFE0FFC2),
                border: initial.isEmpty
                    ? null
                    : Border.all(color: Colors.white, width: 2),
              ),
              clipBehavior: Clip.antiAlias,
              child: initial.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(2),
                      child: ClipOval(
                        child: Image.asset(
                          'assets/images/home/iv_user_profile.jpg',
                          fit: BoxFit.cover,
                        ),
                      ),
                    )
                  : Text(
                      initial,
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    trimmed.isEmpty ? 'CollegeBook' : trimmed,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    number ?? 'by the doctor for the doctor',
                    style: const TextStyle(
                      color: Color(0xCCFFFFFF),
                      fontSize: 13,
                    ),
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

class _SideMenuItem extends StatelessWidget {
  const _SideMenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final String icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // itemShapeInsetStart / End 12dp.
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Material(
        color: Colors.transparent,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          highlightColor: const Color(0xFFE0FFC2),
          splashColor: const Color(0xFFE0FFC2),
          child: Padding(
            // itemHorizontalPadding 20dp (less the 12dp inset), 14dp vertical.
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
            child: Row(
              children: [
                SvgPicture.asset(
                  'assets/icons/$icon.svg',
                  width: 22,
                  height: 22,
                  colorFilter: const ColorFilter.mode(
                    AppColors.primary,
                    BlendMode.srcIn,
                  ),
                ),
                const SizedBox(width: 20),
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF1C1E21),
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
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

class ApiCollectionSection extends StatefulWidget {
  const ApiCollectionSection({
    super.key,
    required this.requestKey,
    required this.repository,
    required this.load,
    required this.titleFields,
    required this.subtitleFields,
    required this.icon,
    required this.emptyMessage,
  });

  final String requestKey;
  final CollegeGuideApiRepository repository;
  final Future<CollegeGuideCollection> Function() load;
  final List<String> titleFields;
  final List<String> subtitleFields;
  final IconData icon;
  final String emptyMessage;

  @override
  State<ApiCollectionSection> createState() => _ApiCollectionSectionState();
}

class _ApiCollectionSectionState extends State<ApiCollectionSection> {
  late Future<CollegeGuideCollection> _collection;

  @override
  void initState() {
    super.initState();
    _collection = widget.load();
  }

  @override
  void didUpdateWidget(covariant ApiCollectionSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.requestKey != widget.requestKey) {
      _collection = widget.load();
    }
  }

  void _retry() {
    setState(() => _collection = widget.load());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<CollegeGuideCollection>(
      future: _collection,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              children: [
                Text(
                  'Could not load this content: ${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF6B7280),
                    fontSize: 13,
                  ),
                ),
                TextButton(onPressed: _retry, child: const Text('Retry')),
              ],
            ),
          );
        }

        final items = snapshot.data!.items;
        if (items.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text(
              widget.emptyMessage,
              style: const TextStyle(color: Color(0xFF6B7280), fontSize: 13),
            ),
          );
        }

        final titles = items
            .map((item) => _firstText(item, widget.titleFields))
            .toList(growable: false);
        if (titles.any((title) => title == null)) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'The service returned content without a displayable title.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF6B7280), fontSize: 13),
            ),
          );
        }

        return Column(
          children: [
            for (var index = 0; index < items.length; index++)
              Card(
                margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                color: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  side: const BorderSide(color: AppColors.border),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  leading: _leading(items[index]),
                  title: Text(
                    titles[index]!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: _subtitle(items[index]),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _leading(Map<String, dynamic> item) {
    final imagePath = _firstText(item, const ['image', 'thumbnail']);
    if (imagePath == null) {
      return Icon(widget.icon, color: AppColors.primary);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        widget.repository.resolveMediaUrl(imagePath),
        width: 48,
        height: 48,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            Icon(widget.icon, color: AppColors.primary),
      ),
    );
  }

  Widget? _subtitle(Map<String, dynamic> item) {
    final subtitle = _firstText(item, widget.subtitleFields);
    if (subtitle == null) return null;
    return Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis);
  }
}

String? _firstText(Map<String, dynamic> item, List<String> fields) {
  for (final field in fields) {
    final value = item[field];
    if (value is String && value.trim().isNotEmpty) return value.trim();
    if (value is num) return value.toString();
  }
  return null;
}
