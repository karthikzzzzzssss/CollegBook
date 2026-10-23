import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/native_bridge.dart';
import '../../theme/app_theme.dart';
import '../cutoff/cutoff_page.dart';
import 'college_guide_api.dart';

/// CcmsItemWebviewActivity: a State / Course / Counselling card's page. The
/// item image stays fixed at the top while a white rounded sheet holding the
/// server's HTML (ccms/items/{id}/webview/) scrolls up over it.
class CcmsItemPage extends StatefulWidget {
  const CcmsItemPage({
    super.key,
    required this.api,
    required this.itemId,
    required this.imageUrl,
  });

  final CollegeGuideApiRepository api;
  final int itemId;
  final String? imageUrl;

  @override
  State<CcmsItemPage> createState() => _CcmsItemPageState();
}

class _CcmsItemPageState extends State<CcmsItemPage> {
  late final WebViewController _controller;
  bool _loading = true;
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _shown = true);
          },
        ),
      );
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final raw = await widget.api.fetchText(
        'ccms/items/${widget.itemId}/webview/',
      );
      if (!mounted) return;
      setState(() => _loading = false);
      await _controller.loadHtmlString(
        _asSheet(_extractHtml(raw)),
        baseUrl: widget.api.webPage('').toString(),
      );
    } on CollegeGuideApiException {
      if (!mounted) return;
      setState(() => _loading = false);
      showToast(context, 'Failed to load content');
    }
  }

  /// The endpoint answers raw HTML; a JSON envelope is the fallback.
  static String _extractHtml(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return '<html><body><p>No content available.</p></body></html>';
    }
    return raw;
  }

  /// Puts the page inside the native layout: a 236dp transparent gap (250dp
  /// image less the sheet's -14dp overlap), then a white sheet with 24dp top
  /// corners, a drag handle and 6dp side padding around the page itself.
  static String _asSheet(String html) {
    const style = '''
<style>
  html, body.cb-host { background: transparent !important; margin: 0 !important; padding: 0 !important; }
  #cb-sheet { margin-top: 236px; background: #fff; border-radius: 24px 24px 0 0;
              padding: 8px 6px 24px; min-height: 100vh; box-sizing: border-box; }
  #cb-handle { width: 40px; height: 4px; border-radius: 2px; background: #D0D0D0; margin: 0 auto; }
  #cb-page { margin-top: 10px; }
</style>''';
    final bodyOpen = RegExp(r'<body([^>]*)>', caseSensitive: false);
    final match = bodyOpen.firstMatch(html);
    if (match == null) {
      return '$style<body class="cb-host"><div id="cb-sheet"><div id="cb-handle"></div>'
          '<div id="cb-page">$html</div></div></body>';
    }
    // The page's own body styles (background, font) move to the wrapper.
    final attrs = match.group(1) ?? '';
    final open =
        '<body class="cb-host"><div id="cb-sheet"><div id="cb-handle"></div>'
        '<div id="cb-page" class="cb-body"$attrs>';
    var out = html.replaceRange(match.start, match.end, open);
    out = out.replaceFirst(
      RegExp(r'</body>', caseSensitive: false),
      '</div></div></body>',
    );
    // Rules written for "body" now style the page wrapper.
    out = out.replaceAllMapped(
      RegExp(r'(^|[\s,}])body(\s*[{,])', multiLine: true),
      (m) => '${m[1]}.cb-body${m[2]}',
    );
    final headClose = RegExp(r'</head>', caseSensitive: false);
    return headClose.hasMatch(out)
        ? out.replaceFirst(headClose, '$style</head>')
        : '$style$out';
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // EdgeToEdge.enable() with the root padded by the system bars: white
      // bars with dark icons.
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.white,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Padding(
          padding: EdgeInsets.only(top: padding.top, bottom: padding.bottom),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 250,
                child: _HeaderImage(url: widget.imageUrl),
              ),
              if (_shown || !_loading)
                Positioned.fill(child: WebViewWidget(controller: _controller)),
              if (_loading || !_shown)
                const Positioned(
                  top: 250,
                  left: 0,
                  right: 0,
                  child: Padding(
                    padding: EdgeInsets.only(top: 24),
                    child: Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF6750A4),
                      ),
                    ),
                  ),
                ),
              Positioned(
                top: 16,
                left: 16,
                child: Semantics(
                  label: 'Back',
                  button: true,
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 40,
                      height: 40,
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: SvgPicture.asset(
                        'assets/icons/ic_baseline_arrow_back_24.svg',
                        colorFilter: const ColorFilter.mode(
                          Colors.black,
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
      ),
    );
  }
}

class _HeaderImage extends StatelessWidget {
  const _HeaderImage({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    const placeholder = Image(
      image: AssetImage('assets/images/home/iv_mirror.png'),
      fit: BoxFit.cover,
    );
    final source = url;
    if (source == null || source.isEmpty) return placeholder;
    return CachedNetworkImage(
      imageUrl: source,
      fit: BoxFit.cover,
      placeholder: (_, _) => placeholder,
      errorWidget: (_, _, _) => placeholder,
    );
  }
}

/// The green-header WebView screens (FeeDetailsWebviewActivity): a
/// bg_selection_pill_green bar with back + title over a server page.
class GreenHeaderWebPage extends StatelessWidget {
  const GreenHeaderWebPage({
    super.key,
    required this.api,
    required this.title,
    required this.path,
  });

  final CollegeGuideApiRepository api;
  final String title;
  final String path;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: AppColors.primary,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: AppColors.primary,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: AppColors.primary,
        body: SafeArea(
          child: ColoredBox(
            color: Colors.white,
            child: Column(
              children: [
                GreenHeader(title: title),
                Expanded(
                  child: AuthWebView(api: api, url: api.webPage(path)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The header of the Fee Details and Choice List screens.
class GreenHeader extends StatelessWidget {
  const GreenHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.large = false,
  });

  final String title;
  final String? subtitle;

  /// layout_choice_header (18sp title, 64dp min height) rather than the
  /// 16sp Fee Details bar.
  final bool large;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(minHeight: large ? 64 : 0),
      padding: EdgeInsets.symmetric(vertical: large ? 12 : 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF004D00), Color(0xFF003300), Color(0xFF003300)],
        ),
      ),
      child: Row(
        children: [
          SizedBox(width: large ? 6 : 16),
          Semantics(
            label: 'Back',
            button: true,
            child: InkResponse(
              onTap: () => Navigator.of(context).maybePop(),
              radius: 20,
              child: Padding(
                padding: EdgeInsets.all(large ? 9 : 0),
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
          SizedBox(width: large ? 8 : 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: large ? 18 : 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xCCFFFFFF),
                        fontSize: 13,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
    );
  }
}
