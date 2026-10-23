import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/native_bridge.dart';
import '../../theme/app_theme.dart';
import '../home/web_pages.dart';
import 'choice_export.dart';
import 'choice_repository.dart';

const _state = Color(0xFF1E4B3E);
const _appColor = Color(0xFF12151B);
const _secondary = Color(0xFF6B7280);
const _stroke = Color(0xFFE3E5E8);
const _muted = Color(0xFFF4F5F7);
const _danger = Color(0xFFD32F2F);

const _emptyMessage =
    "You don't have any choice lists currently.\nCreate one here to start adding your college choices.";

/// The Choice List screens' chrome: green status/nav bars, the green header.
class _ChoiceScaffold extends StatelessWidget {
  const _ChoiceScaffold({
    required this.title,
    this.subtitle,
    required this.background,
    required this.body,
    this.messengerKey,
  });

  final GlobalKey<ScaffoldMessengerState>? messengerKey;
  final String title;
  final String? subtitle;
  final Color background;
  final Widget body;

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
      // Its own messenger: a "saved" message stays on this screen, like a
      // native Snackbar on its activity.
      child: ScaffoldMessenger(
        key: messengerKey,
        child: Scaffold(
          backgroundColor: AppColors.primary,
          resizeToAvoidBottomInset: true,
          body: SafeArea(
            child: ColoredBox(
              color: background,
              child: Column(
                children: [
                  GreenHeader(title: title, subtitle: subtitle, large: true),
                  Expanded(child: body),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// bg_choice_pill_button.
class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.label,
    required this.onTap,
    this.enabled = true,
    this.color = _state,
    this.disabledColor = const Color(0xFFA3B4AE),
    this.height = 52,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onTap;
  final bool enabled;
  final Color color;
  final Color disabledColor;
  final double height;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: enabled ? color : disabledColor,
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(28),
        splashColor: const Color(0x33FFFFFF),
        child: SizedBox(
          height: height,
          width: expand ? double.infinity : null,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: expand ? 0 : 24),
            child: Center(
              widthFactor: 1,
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Handle extends StatelessWidget {
  const _Handle({this.width = 40, this.height = 4});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: const Color(0xFFD9D9D9),
      borderRadius: BorderRadius.circular(360),
    ),
  );
}

/// A sheet on bg_filter_sheet (white, 20dp top corners).
Future<T?> _showSheet<T>(BuildContext context, WidgetBuilder builder) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(top: false, child: builder(context)),
      ),
    ),
  );
}

/// ConfirmDeleteSheet.showMenu(): an optional action, then the destructive
/// one in red.
Future<void> _showMoreMenu(
  BuildContext context,
  Offset position, {
  String? actionLabel,
  VoidCallback? onAction,
  required String deleteLabel,
  required VoidCallback onDelete,
}) async {
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  final picked = await showMenu<int>(
    context: context,
    color: Colors.white,
    position: RelativeRect.fromRect(
      position & const Size(1, 1),
      Offset.zero & overlay.size,
    ),
    items: [
      if (actionLabel != null)
        PopupMenuItem(
          value: 1,
          child: Text(actionLabel, style: const TextStyle(fontSize: 16)),
        ),
      PopupMenuItem(
        value: 2,
        child: Text(
          deleteLabel,
          style: const TextStyle(color: _danger, fontSize: 16),
        ),
      ),
    ],
  );
  if (picked == 1) onAction?.call();
  if (picked == 2) onDelete();
}

/// The ⋮ button.
class _MoreButton extends StatelessWidget {
  const _MoreButton({required this.onTap, this.padding = 10});

  final void Function(Offset position) onTap;
  final double padding;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'More options',
      button: true,
      container: true,
      child: InkResponse(
        radius: 20,
        onTapDown: (d) => onTap(d.globalPosition),
        onTap: () {},
        child: Padding(
          padding: EdgeInsets.all(padding),
          child: SvgPicture.asset(
            'assets/icons/ic_more_vert.svg',
            width: 40 - 2 * padding,
            height: 40 - 2 * padding,
            colorFilter: const ColorFilter.mode(_secondary, BlendMode.srcIn),
          ),
        ),
      ),
    );
  }
}

// ---- My Choice Lists ----------------------------------------------------------

/// ChoiceListsActivity.
class ChoiceListsPage extends StatefulWidget {
  const ChoiceListsPage({
    super.key,
    required this.repository,
    required this.isSubscribed,
    required this.onGetPackage,
  });

  final ChoiceListRepository repository;
  final bool isSubscribed;
  final VoidCallback onGetPackage;

  @override
  State<ChoiceListsPage> createState() => _ChoiceListsPageState();
}

class _ChoiceListsPageState extends State<ChoiceListsPage> {
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  List<ChoiceList>? _lists;
  String? _empty;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Also runs on return from the add/detail screens (onResume).
  Future<void> _load() async {
    if ((_lists ?? const []).isEmpty) setState(() => _loading = true);
    try {
      final lists = await widget.repository.getLists();
      if (!mounted) return;
      setState(() {
        _lists = lists;
        _empty = lists.isEmpty ? _emptyMessage : null;
      });
    } on String catch (message) {
      if (!mounted) return;
      if ((_lists ?? const []).isEmpty) {
        setState(() => _empty = message);
      } else {
        showToast(context, message);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(Widget page) async {
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => page));
    if (mounted) _load();
  }

  void _openList(ChoiceList list) => _open(
    ChoiceListDetailPage(
      repository: widget.repository,
      listId: list.id,
      listName: list.name,
      isSubscribed: widget.isSubscribed,
      onGetPackage: widget.onGetPackage,
    ),
  );

  Future<void> _create() async {
    final list = await _showSheet<ChoiceList>(
      context,
      (_) => _CreateListSheet(repository: widget.repository),
    );
    if (list == null || !mounted) return;
    _load();
    // Straight to adding the first choice; the list is on this page behind it.
    _open(
      AddChoicePage(
        repository: widget.repository,
        listId: list.id,
        listName: list.name,
        isSubscribed: widget.isSubscribed,
        openListAfter: true,
        onGetPackage: widget.onGetPackage,
      ),
    );
  }

  Future<void> _confirmDelete(ChoiceList list) async {
    final count = list.choiceCount;
    final message =
        '${count == 0 ? 'This list will be permanently deleted.' : 'This list and its $count ${count == 1 ? 'choice' : 'choices'} will be permanently deleted.'}'
        " This can't be undone.";
    final deleted = await _showSheet<bool>(
      context,
      (_) => _ConfirmDeleteSheet(
        title: 'Delete this list?',
        subject: list.name,
        message: message,
        deleteLabel: 'Delete list',
        action: () => widget.repository.deleteList(list.id),
      ),
    );
    if (deleted != true || !mounted) return;
    showToast(context, 'List deleted');
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final lists = _lists ?? const <ChoiceList>[];
    return _ChoiceScaffold(
      messengerKey: _messengerKey,
      title: 'Choice List',
      background: Colors.white,
      body: Column(
        children: [
          const SizedBox(height: 20),
          const _Handle(width: 36, height: 3),
          const SizedBox(height: 12),
          const Text(
            'My Choice Lists',
            style: TextStyle(
              color: _appColor,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  children: [
                    for (final list in lists)
                      _ListCard(
                        list: list,
                        onTap: () => _openList(list),
                        onMore: (position) => _showMoreMenu(
                          context,
                          position,
                          actionLabel: 'Download',
                          onAction: () => _showSheet<void>(
                            context,
                            (_) => _DownloadSheet(
                              repository: widget.repository,
                              list: list,
                              messengerKey: _messengerKey,
                            ),
                          ),
                          deleteLabel: 'Delete list',
                          onDelete: () => _confirmDelete(list),
                        ),
                      ),
                  ],
                ),
                if (_empty != null && lists.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(32, 28, 32, 0),
                    child: Text(
                      _empty!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: _secondary,
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                  ),
                if (_loading)
                  const Align(
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: EdgeInsets.only(top: 40),
                      child: CircularProgressIndicator(color: _state),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: _PillButton(label: '+  Create choice list', onTap: _create),
          ),
        ],
      ),
    );
  }
}

class _ListCard extends StatelessWidget {
  const _ListCard({
    required this.list,
    required this.onTap,
    required this.onMore,
  });

  final ChoiceList list;
  final VoidCallback onTap;
  final void Function(Offset) onMore;

  @override
  Widget build(BuildContext context) {
    final count = list.choiceCount;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: _stroke),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 4, 14),
            child: Row(
              children: [
                const _LockCircle(
                  size: 40,
                  padding: 11,
                  icon: 'ic_heart_filled',
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        list.name ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _appColor,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        count == 0
                            ? 'No choices yet'
                            : '$count ${count == 1 ? 'choice' : 'choices'}',
                        style: const TextStyle(color: _secondary, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                _MoreButton(onTap: onMore),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// bg_choice_lock_circle: a state-colour circle with a 6dp #E6EEEA ring.
class _LockCircle extends StatelessWidget {
  const _LockCircle({
    required this.size,
    required this.padding,
    required this.icon,
  });

  final double size;
  final double padding;
  final String icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: _state,
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFE6EEEA), width: 6),
      ),
      child: SvgPicture.asset(
        'assets/icons/$icon.svg',
        colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
      ),
    );
  }
}

/// bottomsheet_create_choice_list.
class _CreateListSheet extends StatefulWidget {
  const _CreateListSheet({required this.repository});

  final ChoiceListRepository repository;

  @override
  State<_CreateListSheet> createState() => _CreateListSheetState();
}

class _CreateListSheetState extends State<_CreateListSheet> {
  final _name = TextEditingController();
  String? _error;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _name.addListener(() {
      if (_error != null) setState(() => _error = null);
    });
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_creating) return;
    final name = _name.text.trim();
    final error = name.isEmpty
        ? 'Please enter a name for your list'
        : widget.repository.nameExists(name)
        ? 'You already have a list with this name'
        : null;
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() => _creating = true);
    try {
      final list = await widget.repository.createList(name);
      if (mounted) Navigator.of(context).pop(list);
    } on String catch (message) {
      if (mounted) {
        setState(() {
          _creating = false;
          _error = message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Center(child: _Handle()),
          const SizedBox(height: 16),
          const Text(
            'Create choice list',
            style: TextStyle(
              color: _appColor,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Give your list a name, then start adding choices.',
            style: TextStyle(color: _secondary, fontSize: 13),
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 50,
            child: TextField(
              controller: _name,
              autofocus: true,
              maxLength: 60,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _create(),
              cursorColor: _state,
              style: const TextStyle(
                color: _appColor,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
              decoration: _inputDecoration('e.g. Round 1 deemed colleges'),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                _error!,
                style: const TextStyle(color: _danger, fontSize: 12),
              ),
            ),
          const SizedBox(height: 20),
          _PillButton(
            label: _creating ? 'Creating…' : 'Create',
            enabled: !_creating,
            onTap: _create,
          ),
        ],
      ),
    );
  }
}

/// bg_filter_input.
InputDecoration _inputDecoration(String hint, {Widget? prefix}) {
  OutlineInputBorder border(Color c, double w) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide(color: c, width: w),
  );
  return InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: _secondary, fontSize: 15),
    counterText: '',
    filled: true,
    fillColor: _muted,
    prefixIcon: prefix,
    prefixIconConstraints: const BoxConstraints(minWidth: 0),
    contentPadding: EdgeInsets.symmetric(horizontal: prefix == null ? 16 : 0),
    border: border(_stroke, 1),
    enabledBorder: border(_stroke, 1),
    focusedBorder: border(_state, 1.5),
  );
}

/// bottomsheet_confirm_delete: stays open while the request runs and shows
/// the server's error in place. Pops true once deleted.
class _ConfirmDeleteSheet extends StatefulWidget {
  const _ConfirmDeleteSheet({
    required this.title,
    required this.subject,
    required this.message,
    required this.deleteLabel,
    required this.action,
  });

  final String title;
  final String? subject;
  final String message;
  final String deleteLabel;
  final Future<void> Function() action;

  @override
  State<_ConfirmDeleteSheet> createState() => _ConfirmDeleteSheetState();
}

class _ConfirmDeleteSheetState extends State<_ConfirmDeleteSheet> {
  bool _busy = false;
  String? _error;

  Future<void> _delete() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.action();
      if (mounted) Navigator.of(context).pop(true);
    } on String catch (message) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_busy,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _Handle(),
            const SizedBox(height: 22),
            Container(
              width: 64,
              height: 64,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: _danger,
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFFDECEC), width: 8),
              ),
              child: SvgPicture.asset(
                'assets/icons/ic_cb_delete.svg',
                colorFilter: const ColorFilter.mode(
                  Colors.white,
                  BlendMode.srcIn,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              widget.title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _appColor,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (widget.subject != null && widget.subject!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  widget.subject!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _appColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            const SizedBox(height: 6),
            Text(
              widget.message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _secondary,
                fontSize: 13,
                height: 1.3,
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: _danger, fontSize: 12),
                ),
              ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: Opacity(
                    opacity: _busy ? 0.5 : 1,
                    child: Material(
                      color: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28),
                        side: const BorderSide(color: Color(0xFFD1D5DB)),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(28),
                        onTap: _busy ? null : () => Navigator.of(context).pop(),
                        child: const SizedBox(
                          height: 52,
                          child: Center(
                            child: Text(
                              'Cancel',
                              style: TextStyle(
                                color: _appColor,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _PillButton(
                    label: _busy ? 'Deleting…' : widget.deleteLabel,
                    enabled: !_busy,
                    color: _danger,
                    disabledColor: const Color(0xFFE9A3A3),
                    onTap: _delete,
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

/// DownloadChoiceListSheet: PDF or CSV into Downloads/CollegeBook.
class _DownloadSheet extends StatefulWidget {
  const _DownloadSheet({
    required this.repository,
    required this.list,
    required this.messengerKey,
  });

  final ChoiceListRepository repository;
  final ChoiceList list;
  final GlobalKey<ScaffoldMessengerState> messengerKey;

  @override
  State<_DownloadSheet> createState() => _DownloadSheetState();
}

class _DownloadSheetState extends State<_DownloadSheet> {
  ChoiceExportFormat? _saving;
  String? _error;

  Future<void> _download(ChoiceExportFormat format) async {
    if (_saving != null) return;
    setState(() {
      _saving = format;
      _error = null;
    });
    final messenger = widget.messengerKey.currentState;
    final navigator = Navigator.of(context);
    try {
      var loaded = await widget.repository.getChoices(widget.list.id);
      if (loaded.name == null) {
        loaded = ChoiceList(
          loaded.id,
          widget.list.name,
          loaded.choices.length,
          loaded.choices,
        );
      }
      final uri = await exportChoiceList(loaded, format);
      if (!mounted) return;
      navigator.pop();
      messenger?.showSnackBar(
        SnackBar(
          content: Text('${format.label} saved to Downloads/CollegeBook'),
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: 'Open',
            textColor: Colors.white,
            onPressed: () => openFile(uri, format.mimeType, format.label),
          ),
        ),
      );
    } on String catch (message) {
      _fail(message);
    } on Object {
      _fail("Couldn't save the file. Please try again.");
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _saving = null;
      _error = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _saving == null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Center(child: _Handle()),
            const SizedBox(height: 16),
            const Text(
              'Download choice list',
              style: TextStyle(
                color: _appColor,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${widget.list.name}  ·  Saved to Downloads/CollegeBook',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _secondary, fontSize: 13),
            ),
            for (final (format, icon, label, hint) in const [
              (
                ChoiceExportFormat.pdf,
                'ic_cb_file_pdf',
                'Download as PDF',
                'Printable table of your choices',
              ),
              (
                ChoiceExportFormat.csv,
                'ic_cb_file_csv',
                'Download as CSV',
                'Open in Excel or Google Sheets',
              ),
            ])
              Opacity(
                opacity: _saving != null && _saving != format ? 0.5 : 1,
                child: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Material(
                    color: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: const BorderSide(color: Color(0xFFE5E7EB)),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      splashColor: const Color(0x14003300),
                      onTap: _saving == null ? () => _download(format) : null,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 72),
                        child: Padding(
                          padding: const EdgeInsets.only(left: 14, right: 10),
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                padding: const EdgeInsets.all(11),
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
                                      label,
                                      style: const TextStyle(
                                        color: _appColor,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      hint,
                                      style: const TextStyle(
                                        color: _secondary,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 32,
                                height: 32,
                                child: _saving == format
                                    ? const Center(
                                        child: SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(
                                            color: _state,
                                            strokeWidth: 2.5,
                                          ),
                                        ),
                                      )
                                    : Padding(
                                        padding: const EdgeInsets.all(4),
                                        child: SvgPicture.asset(
                                          'assets/icons/ic_cb_chevron_right.svg',
                                          colorFilter: const ColorFilter.mode(
                                            _secondary,
                                            BlendMode.srcIn,
                                          ),
                                        ),
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  _error!,
                  style: const TextStyle(color: _danger, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---- One list ------------------------------------------------------------------

/// ChoiceListDetailActivity.
class ChoiceListDetailPage extends StatefulWidget {
  const ChoiceListDetailPage({
    super.key,
    required this.repository,
    required this.listId,
    required this.listName,
    required this.isSubscribed,
    required this.onGetPackage,
  });

  final ChoiceListRepository repository;
  final String listId;
  final String? listName;
  final bool isSubscribed;
  final VoidCallback onGetPackage;

  @override
  State<ChoiceListDetailPage> createState() => _ChoiceListDetailPageState();
}

class _ChoiceListDetailPageState extends State<ChoiceListDetailPage> {
  late String? _name = widget.listName;
  List<ChoiceItem> _choices = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await widget.repository.getChoices(widget.listId);
      if (!mounted) return;
      setState(() {
        if (list.name != null) _name = list.name;
        _choices = list.choices;
      });
    } on String catch (message) {
      if (mounted) showToast(context, message);
    }
  }

  Future<void> _addChoice() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AddChoicePage(
          repository: widget.repository,
          listId: widget.listId,
          listName: _name,
          isSubscribed: widget.isSubscribed,
          openListAfter: false,
          onGetPackage: widget.onGetPackage,
        ),
      ),
    );
    if (mounted) _load();
  }

  Future<void> _confirmRemove(ChoiceItem item) async {
    final details = '${item.course} · ${item.quota} | ${item.category}';
    final removed = await _showSheet<bool>(
      context,
      (_) => _ConfirmDeleteSheet(
        title: 'Remove this choice?',
        subject: item.institute,
        message: '$details\nIt will be removed from "$_name".',
        deleteLabel: 'Remove',
        action: () => widget.repository.deleteChoice(widget.listId, item.id!),
      ),
    );
    if (removed != true || !mounted) return;
    showToast(context, 'Choice removed');
    _load();
  }

  static String _join(String sep, List<String?> parts) =>
      parts.where((p) => p != null && p.trim().isNotEmpty).join(sep);

  @override
  Widget build(BuildContext context) {
    final count = _choices.length;
    final empty = count == 0;
    return _ChoiceScaffold(
      title: _name ?? '',
      subtitle: '$count ${count == 1 ? 'choice' : 'choices'}',
      background: const Color(0xFFF7F8FA),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            children: [
              if (empty)
                const Padding(
                  padding: EdgeInsets.only(top: 40),
                  child: Text(
                    'No choices in this list yet.\nTap “Add new choice” to add one.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _secondary, fontSize: 14),
                  ),
                )
              else
                const Text(
                  'Your choices in order of preference. Tap ⋮ on a choice to remove it.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _secondary, fontSize: 13),
                ),
              for (var i = 0; i < count; i++)
                _ChoiceCard(
                  rank: i + 1,
                  institute: _join(' • ', [
                    _choices[i].institute,
                    _choices[i].state,
                  ]),
                  course: _join(' • ', [
                    _choices[i].course,
                    _choices[i].beds > 0 ? '${_choices[i].beds} BEDS' : null,
                  ]),
                  quota: _join('  |  ', [
                    _choices[i].quota,
                    _choices[i].category,
                  ]),
                  onMore: (position) => _showMoreMenu(
                    context,
                    position,
                    deleteLabel: 'Remove choice',
                    onDelete: () => _confirmRemove(_choices[i]),
                  ),
                ),
              if (!widget.isSubscribed && !empty)
                _LockedCard(onGetPackage: widget.onGetPackage),
            ],
          ),
          Positioned(
            right: 20,
            bottom: 24,
            child: Material(
              elevation: 6,
              borderRadius: BorderRadius.circular(28),
              color: Colors.transparent,
              child: _PillButton(
                label: '+  Add new choice',
                expand: false,
                onTap: _addChoice,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.rank,
    required this.institute,
    required this.course,
    required this.quota,
    required this.onMore,
  });

  final int rank;
  final String institute;
  final String course;
  final String quota;
  final void Function(Offset) onMore;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 16, top: 12),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: _muted,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Text(
                    '#$rank',
                    style: const TextStyle(
                      color: _state,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(top: 4, right: 4),
                child: _MoreButton(onTap: onMore, padding: 8),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  institute,
                  style: const TextStyle(
                    color: _appColor,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  course,
                  style: const TextStyle(
                    color: _secondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(360),
                    border: Border.all(color: _stroke),
                  ),
                  child: Text(
                    quota,
                    style: const TextStyle(
                      color: _state,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
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
}

/// layout_choice_locked_card.
class _LockedCard extends StatelessWidget {
  const _LockedCard({required this.onGetPackage});

  final VoidCallback onGetPackage;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 20),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _stroke),
      ),
      child: Column(
        children: [
          const _LockCircle(size: 64, padding: 18, icon: 'ic_baseline_lock_24'),
          const SizedBox(height: 14),
          const Text(
            'Content Locked',
            style: TextStyle(
              color: _appColor,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Please purchase a NEET PG package to see closing ranks and your chances for these choices.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _secondary, fontSize: 13),
          ),
          const SizedBox(height: 18),
          _PillButton(
            label: 'Get a Package  →',
            height: 48,
            onTap: onGetPackage,
          ),
        ],
      ),
    );
  }
}

// ---- Add new choice -------------------------------------------------------------

/// AddChoiceActivity: Counselling -> Institute -> Course -> Quota -> Category,
/// each single-select; changing a field clears the ones below it.
class AddChoicePage extends StatefulWidget {
  const AddChoicePage({
    super.key,
    required this.repository,
    required this.listId,
    required this.listName,
    required this.isSubscribed,
    required this.openListAfter,
    required this.onGetPackage,
  });

  final ChoiceListRepository repository;
  final String listId;
  final String? listName;
  final bool isSubscribed;

  /// Right after creating a list: show its choices once one is added.
  final bool openListAfter;
  final VoidCallback onGetPackage;

  @override
  State<AddChoicePage> createState() => _AddChoicePageState();
}

class _AddChoicePageState extends State<AddChoicePage> {
  String? _counselling, _institute, _course, _quota, _category;
  List<QuotaOption> _quotas = const [];
  int? _loadingField;
  bool _adding = false;

  ChoiceListRepository get _repo => widget.repository;

  List<String> _categoriesOf(String? quota) => [
    for (final q in _quotas)
      if (q.name == quota) ...q.categories,
  ];

  Future<void> _pick(int field) async {
    const labels = ['Counselling', 'Institute', 'Course', 'Quota', 'Category'];
    const titles = [
      'Select counselling',
      'Select institute',
      'Select course',
      'Select quota',
      'Select category',
    ];
    const searches = [
      'Search counselling',
      'Search institutes',
      'Search courses',
      'Search quotas',
      'Search categories',
    ];
    const locked = [
      '',
      'Select counselling first',
      'Select institute first',
      'Select course first',
      'Select quota first',
    ];
    final values = [_counselling, _institute, _course, _quota, _category];
    if (field > 0 && values[field - 1] == null) {
      showToast(context, locked[field]);
      return;
    }
    if (_loadingField != null) return;
    setState(() => _loadingField = field);
    List<String> options;
    try {
      options = switch (field) {
        0 => await _repo.counsellingOptions(),
        1 => await _repo.instituteOptions(_counselling!),
        2 => await _repo.courseOptions(_counselling!, _institute!),
        3 => await () async {
          _quotas = await _repo.quotaOptions(
            _counselling!,
            _institute!,
            _course!,
          );
          return [for (final q in _quotas) q.name];
        }(),
        _ => _categoriesOf(_quota),
      };
    } on String catch (message) {
      if (mounted) {
        setState(() => _loadingField = null);
        showToast(context, message);
      }
      return;
    }
    if (!mounted) return;
    setState(() => _loadingField = null);
    if (options.isEmpty) {
      showToast(context, 'No ${labels[field].toLowerCase()} options available');
      return;
    }
    final picked = await _showOptionPicker(
      context,
      title: titles[field],
      searchHint: searches[field],
      options: options,
      selected: values[field],
    );
    if (picked == null || picked == values[field] || !mounted) return;
    setState(() {
      switch (field) {
        case 0:
          _counselling = picked;
          _institute = _course = _quota = _category = null;
        case 1:
          _institute = picked;
          _course = _quota = _category = null;
        case 2:
          _course = picked;
          _quota = _category = null;
        case 3:
          _quota = picked;
          _category = null;
        default:
          _category = picked;
      }
    });
  }

  bool get _complete =>
      _counselling != null &&
      _institute != null &&
      _course != null &&
      _quota != null &&
      _category != null;

  Future<void> _add() async {
    setState(() => _adding = true);
    try {
      await _repo.addChoice(
        listId: widget.listId,
        counselling: _counselling!,
        institute: _institute!,
        course: _course!,
        quota: _quota!,
        category: _category!,
      );
      if (!mounted) return;
      showToast(context, 'Choice added');
      final navigator = Navigator.of(context);
      if (widget.openListAfter) {
        navigator.pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => ChoiceListDetailPage(
              repository: _repo,
              listId: widget.listId,
              listName: widget.listName,
              isSubscribed: widget.isSubscribed,
              onGetPackage: widget.onGetPackage,
            ),
          ),
        );
      } else {
        navigator.pop();
      }
    } on String catch (message) {
      if (!mounted) return;
      setState(() => _adding = false);
      showToast(context, message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final values = [_counselling, _institute, _course, _quota, _category];
    const labels = ['Counselling', 'Institute', 'Course', 'Quota', 'Category'];
    const hints = [
      'Select counselling',
      'Select institute',
      'Select course',
      'Select quota',
      'Select category',
    ];
    return _ChoiceScaffold(
      title: 'Add new choice',
      subtitle: (widget.listName ?? '').isEmpty ? null : widget.listName,
      background: Colors.white,
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              children: [
                for (var i = 0; i < 5; i++)
                  _ChoiceField(
                    label: labels[i],
                    hint: hints[i],
                    value: values[i],
                    enabled: i == 0 || values[i - 1] != null,
                    loading: _loadingField == i,
                    onTap: () => _pick(i),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: _PillButton(
              label: _adding ? 'Adding…' : '+  Add choice',
              enabled: _complete && !_adding,
              onTap: _add,
            ),
          ),
        ],
      ),
    );
  }
}

/// layout_choice_field.
class _ChoiceField extends StatelessWidget {
  const _ChoiceField({
    required this.label,
    required this.hint,
    required this.value,
    required this.enabled,
    required this.loading,
    required this.onTap,
  });

  final String label;
  final String hint;
  final String? value;
  final bool enabled;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: _secondary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Opacity(
            opacity: enabled ? 1 : 0.5,
            child: Material(
              color: _muted,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: _stroke),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onTap,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 52),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            value ?? hint,
                            style: TextStyle(
                              color: value == null ? _secondary : _appColor,
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        if (loading)
                          const Padding(
                            padding: EdgeInsets.only(right: 2),
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: _state,
                                strokeWidth: 2.2,
                              ),
                            ),
                          )
                        else
                          SvgPicture.asset(
                            'assets/icons/ic_baseline_arrow_drop_down_24.svg',
                            width: 24,
                            height: 24,
                            colorFilter: const ColorFilter.mode(
                              _secondary,
                              BlendMode.srcIn,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ChoiceOptionPickerSheet: lists over 8 options get a search box and 85% of
/// the screen; short ones just wrap.
Future<String?> _showOptionPicker(
  BuildContext context, {
  required String title,
  required String searchHint,
  required List<String> options,
  required String? selected,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _OptionPicker(
      title: title,
      searchHint: searchHint,
      options: options,
      selected: selected,
    ),
  );
}

class _OptionPicker extends StatefulWidget {
  const _OptionPicker({
    required this.title,
    required this.searchHint,
    required this.options,
    required this.selected,
  });

  final String title;
  final String searchHint;
  final List<String> options;
  final String? selected;

  @override
  State<_OptionPicker> createState() => _OptionPickerState();
}

class _OptionPickerState extends State<_OptionPicker> {
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final long = widget.options.length > 8;
    final query = _search.text.trim().toLowerCase();
    final shown = [
      for (final o in widget.options)
        if (query.isEmpty || o.toLowerCase().contains(query)) o,
    ];
    final rows = [
      for (final option in shown)
        InkWell(
          onTap: () => Navigator.of(context).pop(option),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      option,
                      style: const TextStyle(
                        color: _appColor,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    option == widget.selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: _state,
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ),
        ),
    ];
    final header = [
      const SizedBox(height: 10),
      const Center(child: _Handle()),
      const SizedBox(height: 14),
      Center(
        child: Text(
          widget.title,
          style: const TextStyle(
            color: _appColor,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      if (long) ...[
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SizedBox(
            height: 48,
            child: TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              cursorColor: _state,
              style: const TextStyle(color: _appColor, fontSize: 15),
              decoration: _inputDecoration(
                widget.searchHint,
                prefix: Padding(
                  padding: const EdgeInsets.only(left: 14, right: 10),
                  child: SvgPicture.asset(
                    'assets/icons/ic_baseline_search_24.svg',
                    width: 24,
                    height: 24,
                    colorFilter: const ColorFilter.mode(
                      _secondary,
                      BlendMode.srcIn,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
      const SizedBox(height: 12),
      const Divider(height: 1, thickness: 1, color: Color(0xFFECEDF0)),
    ];
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        height: long ? MediaQuery.sizeOf(context).height * 0.85 : null,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          top: false,
          child: long
              ? Column(
                  children: [
                    ...header,
                    Expanded(
                      child: Stack(
                        children: [
                          ListView(
                            padding: const EdgeInsets.only(bottom: 16),
                            children: rows,
                          ),
                          if (shown.isEmpty)
                            const Align(
                              alignment: Alignment.topCenter,
                              child: Padding(
                                padding: EdgeInsets.only(top: 32),
                                child: Text(
                                  'No matches found',
                                  style: TextStyle(
                                    color: _secondary,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [...header, ...rows, const SizedBox(height: 16)],
                ),
        ),
      ),
    );
  }
}
