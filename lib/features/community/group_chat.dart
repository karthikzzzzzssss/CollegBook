import 'dart:async';
import 'dart:convert';
import 'dart:io' show File, Platform;
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../core/native_bridge.dart';
import '../home/college_guide_api.dart';
import 'chat_bubbles.dart';
import 'chat_models.dart';

const _chatBg = Color(0xFFF2EDE4);
const _state = Color(0xFF1E4B3E);
const _meta = Color(0xFF6B7280);

const _historyLimit = 30;
const _loadMoreThreshold = 5;
const _maxMessageLength = 1000;
const _maxFileBytes = 10 * 1024 * 1024;

/// Group slugs from chat/groups/ — they don't change while the app runs.
class _Groups {
  static String? nationalSlug;
  static final stateSlugByName = <String, String>{};
  static bool loaded = false;

  static String slugFor(bool allIndia, String? state) {
    if (allIndia || state == null) return nationalSlug ?? 'all-india';
    final key = state.trim().toLowerCase();
    return stateSlugByName[key] ??
        key
            .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
            .replaceAll(RegExp(r'^-|-$'), '');
  }
}

/// Community → Chats: the group room of the All India / state selection
/// (GroupChatFragment).
class GroupChatView extends StatefulWidget {
  const GroupChatView({
    super.key,
    required this.api,
    required this.allIndia,
    required this.state,
  });

  final CollegeGuideApiRepository api;
  final bool allIndia;
  final String state;

  @override
  State<GroupChatView> createState() => GroupChatViewState();
}

class GroupChatViewState extends State<GroupChatView>
    with WidgetsBindingObserver {
  final _scroll = ScrollController();
  final _input = TextEditingController();
  final _inputFocus = FocusNode();
  final _parser = ChatParser();

  /// Oldest first, with date headers.
  final List<ChatBubble> _list = [];

  String? _roomId;
  bool _roomUnavailable = false;
  bool _groupsLoading = false;
  String? _status = 'Connecting…';
  bool _hasMoreHistory = false;
  bool _loadingMoreHistory = false;
  bool _catchingUp = false;
  bool _sending = false;
  bool _attachmentsOpen = false;

  ChatBubble? _replyTo;

  WebSocketChannel? _socket;
  StreamSubscription<dynamic>? _socketSub;
  Timer? _reconnectTimer;
  int _reconnectAttempt = 0;
  bool _wentToBackground = false;

  String? _stickyLabel;
  Timer? _stickyTimer;

  /// Built rows, by list index, for the sticky date and jumping to a quote.
  final _rowKeys = <String, GlobalKey>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scroll.addListener(_onScroll);
    _input.addListener(() => setState(() {}));
    _inputFocus.addListener(() {
      if (_inputFocus.hasFocus && _attachmentsOpen) {
        setState(() => _attachmentsOpen = false);
      }
    });
    _setRoom();
  }

  @override
  void didUpdateWidget(GroupChatView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.allIndia != widget.allIndia ||
        oldWidget.state != widget.state) {
      _setRoom();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _closeSocket();
    _reconnectTimer?.cancel();
    _stickyTimer?.cancel();
    _scroll.dispose();
    _input.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  /// Back from the background: fetch what was missed, reconnect if dropped.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _wentToBackground = true;
    } else if (state == AppLifecycleState.resumed && _wentToBackground) {
      _wentToBackground = false;
      if (_roomId == null || _roomUnavailable) return;
      if (_socket == null) {
        _reconnectTimer?.cancel();
        _reconnectAttempt = 0;
        _connect();
      } else {
        _catchUp();
      }
    }
  }

  /// onLeftChat(): Q&A took over, so the keyboard and panel go away.
  void onLeftChat() {
    FocusManager.instance.primaryFocus?.unfocus();
    if (_attachmentsOpen) setState(() => _attachmentsOpen = false);
  }

  void _toast(String text) {
    if (mounted) showToast(context, text);
  }

  void _showStatus(String? text) {
    if (mounted) setState(() => _status = text);
  }

  // ---- rooms ----

  void _setRoom() {
    if (!_Groups.loaded) {
      _loadGroupsThenOpen();
      return;
    }
    _openRoom(_Groups.slugFor(widget.allIndia, widget.state));
  }

  Future<void> _loadGroupsThenOpen() async {
    if (_groupsLoading) return;
    _groupsLoading = true;
    _showStatus('Connecting…');
    try {
      final json = await widget.api.send('GET', 'chat/groups/');
      final data = json['data'];
      final results = data is Map ? data['results'] : null;
      _Groups.stateSlugByName.clear();
      for (final g in (results as List? ?? const [])) {
        if (g is! Map || g['slug'] == null) continue;
        final slug = '${g['slug']}';
        if ('${g['group_type']}'.toUpperCase() == 'NATIONAL') {
          _Groups.nationalSlug ??= slug;
          continue;
        }
        final name = '${g['name'] ?? ''}'
            .replaceFirst(
              RegExp(r'\s*counselling\s*$', caseSensitive: false),
              '',
            )
            .trim()
            .toLowerCase();
        _Groups.stateSlugByName[name] = slug;
      }
      _Groups.loaded = true;
    } on CollegeGuideApiException {
      // Falls back to the state name in slug form.
    }
    _groupsLoading = false;
    if (mounted) _openRoom(_Groups.slugFor(widget.allIndia, widget.state));
  }

  void _openRoom(String slug) {
    if (slug == _roomId &&
        (_socket != null || _list.isNotEmpty || _roomUnavailable)) {
      return;
    }
    _roomId = slug;
    _resetRoom();
    if (_Groups.loaded &&
        _Groups.stateSlugByName.isNotEmpty &&
        !widget.allIndia &&
        !_Groups.stateSlugByName.containsValue(slug)) {
      _markUnavailable();
      return;
    }
    _connect();
  }

  void _markUnavailable() {
    _roomUnavailable = true;
    _reconnectTimer?.cancel();
    _closeSocket();
    _showStatus(
      widget.allIndia
          ? "This chat group isn't available."
          : "There's no chat group for ${widget.state} yet.",
    );
  }

  void _resetRoom() {
    _reconnectTimer?.cancel();
    _reconnectAttempt = 0;
    _closeSocket();
    _list.clear();
    _rowKeys.clear();
    _hasMoreHistory = false;
    _loadingMoreHistory = false;
    _catchingUp = false;
    _roomUnavailable = false;
    _parser.removedIds.clear();
    _replyTo = null;
    _stickyLabel = null;
    _status = 'Connecting…';
    if (mounted) setState(() {});
  }

  // ---- socket ----

  void _closeSocket() {
    _socketSub?.cancel();
    _socketSub = null;
    _socket?.sink.close();
    _socket = null;
  }

  Future<void> _connect() async {
    final room = _roomId;
    if (room == null) return;
    final token = await widget.api.accessToken();
    if (!mounted || room != _roomId) return;
    if (token == null || token.isEmpty) {
      _showStatus('Log in to join the chat.');
      return;
    }
    if (_list.isEmpty) _showStatus('Connecting…');
    // Widget tests have no network: history still comes over REST.
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      _loadLatest();
      return;
    }
    final uri = Uri.parse('wss://${widget.api.apiHost}/ws/chat/$room/')
        .replace(queryParameters: {'token': token});
    final WebSocketChannel socket;
    try {
      socket = WebSocketChannel.connect(uri);
    } on Object {
      _onSocketLost(null);
      return;
    }
    _socket = socket;
    socket.ready.then((_) {
      if (_socket != socket || !mounted) return;
      _reconnectAttempt = 0;
      if (_list.isEmpty) {
        _loadLatest();
      } else {
        _catchUp();
      }
    }, onError: (Object _) => _onSocketLost(socket));
    _socketSub = socket.stream.listen(
      (message) {
        if (_socket != socket || !mounted) return;
        try {
          final event = jsonDecode('$message');
          if (event is Map<String, dynamic>) _handleEvent(event);
        } on FormatException {
          // Ignored, as natively.
        }
      },
      onError: (Object _) => _onSocketLost(socket),
      onDone: () => _onSocketLost(socket),
    );
  }

  /// History still loads over REST; the socket retries 2s, 4s … 30s.
  void _onSocketLost(WebSocketChannel? socket) {
    if (socket != null && socket != _socket) return;
    if (!mounted) return;
    _socketSub?.cancel();
    _socketSub = null;
    _socket = null;
    if (_roomUnavailable) return;
    if (_list.isEmpty) {
      _loadLatest();
    } else {
      _catchUp();
    }
    final delay = math.min(30000, 2000 << math.min(_reconnectAttempt, 4));
    _reconnectAttempt++;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(milliseconds: delay), () {
      if (mounted && _socket == null && _roomId != null && !_roomUnavailable) {
        _connect();
      }
    });
  }

  void _handleEvent(Map<String, dynamic> event) {
    final type = '${event['type'] ?? event['event'] ?? ''}';
    final payload = eventPayload(event);
    switch (type) {
      case 'message_created':
        final message = messageObject(payload);
        if (((message['id'] as num?)?.toInt() ?? 0) <= 0) return;
        final atBottom = _isAtBottom;
        final incoming = _parser.parse(message);
        _merge(incoming);
        if (atBottom || incoming.first.mine) _scrollToBottom();
      case 'message_hidden':
        _removeMessage(messageIdOf(payload));
      case 'message_restored':
        final message = messageObject(payload);
        if (message.containsKey('created_at')) {
          final bubbles = _parser.parse(message);
          _replaceMessage(bubbles.first.id, bubbles);
        } else {
          _refetchMessage(messageIdOf(payload));
        }
      case 'attachment_hidden':
      case 'attachment_restored':
        _refetchMessage(messageIdOf(payload));
    }
  }

  // ---- history ----

  Future<({Map data, List<ChatBubble> batch})?> _fetchPage({
    int? before,
    int? after,
    void Function(CollegeGuideApiException e)? onError,
  }) async {
    final slug = _roomId;
    if (slug == null) return null;
    try {
      final json = await widget.api.send(
        'GET',
        'chat/groups/$slug/messages/',
        query: {
          'limit': '$_historyLimit',
          'before': ?before?.toString(),
          'after': ?after?.toString(),
        },
      );
      if (!mounted || slug != _roomId) return null;
      final data = json['data'] is Map ? json['data'] as Map : const {};
      final batch = <ChatBubble>[];
      for (final m in (data['results'] as List? ?? const [])) {
        if (m is Map<String, dynamic> && ((m['id'] as num?) ?? 0) > 0) {
          batch.addAll(_parser.parse(m));
        }
      }
      _sortById(batch);
      return (data: data, batch: batch);
    } on CollegeGuideApiException catch (e) {
      if (!mounted || slug != _roomId) return null;
      onError?.call(e);
      return null;
    }
  }

  Future<void> _loadLatest() async {
    final page = await _fetchPage(
      onError: (e) {
        if (_list.isNotEmpty) return;
        final code = '${e.payload?['message'] ?? ''}';
        if (code == 'GROUP_NOT_FOUND') {
          _markUnavailable();
        } else if (code == 'PROFILE_INACTIVE') {
          _showStatus('Your profile is deactivated.');
        } else {
          _showStatus("Couldn't connect to the chat right now.");
        }
      },
    );
    if (page == null) return;
    _hasMoreHistory = page.data['has_more'] == true;
    _merge(page.batch);
    _scrollToBottom();
    _showStatus(_list.isEmpty ? 'No messages yet. Say hi 👋' : null);
  }

  void _catchUp() {
    if (_catchingUp) return;
    final newest = _newestId;
    if (newest <= 0) {
      _loadLatest();
      return;
    }
    _catchingUp = true;
    _fetchNewer(newest);
  }

  Future<void> _fetchNewer(int after) async {
    final page = await _fetchPage(after: after, onError: (_) {});
    if (page == null) {
      _catchingUp = false;
      return;
    }
    final atBottom = _isAtBottom;
    _merge(page.batch);
    if (atBottom && page.batch.isNotEmpty) _scrollToBottom();
    _showStatus(_list.isEmpty ? 'No messages yet. Say hi 👋' : null);
    final newest = math.max(
      (page.data['newest_id'] as num?)?.toInt() ?? 0,
      _newestId,
    );
    if (page.data['has_more'] == true &&
        page.batch.isNotEmpty &&
        newest > after) {
      _fetchNewer(newest);
    } else {
      _catchingUp = false;
    }
  }

  Future<bool> _loadMoreHistory() async {
    final oldest = _oldestId;
    if (!_hasMoreHistory || _loadingMoreHistory || oldest <= 0) return false;
    _loadingMoreHistory = true;
    final page = await _fetchPage(before: oldest, onError: (_) {});
    _loadingMoreHistory = false;
    if (page == null) return false;
    _hasMoreHistory = page.data['has_more'] == true;
    final older = [
      for (final m in page.batch)
        if (m.id < oldest) m,
    ];
    if (older.isEmpty) return true;
    // A reversed list keeps what's on screen still while older rows land above.
    _rebuild([...older, ..._messages]);
    return true;
  }

  Future<void> _refetchMessage(int id) async {
    if (id <= 0) return;
    final page = await _fetchPage(before: id + 1);
    if (page == null) return;
    final bubbles = [
      for (final m in page.batch)
        if (m.id == id) m,
    ];
    if (bubbles.isEmpty) {
      _removeMessage(id);
    } else {
      _replaceMessage(id, bubbles);
    }
  }

  // ---- list edits ----

  List<ChatBubble> get _messages => [
    for (final m in _list)
      if (m.type != BubbleType.header) m,
  ];

  int get _newestId {
    for (var i = _list.length - 1; i >= 0; i--) {
      if (_list[i].id > 0) return _list[i].id;
    }
    return 0;
  }

  int get _oldestId {
    for (final m in _list) {
      if (m.id > 0) return m.id;
    }
    return 0;
  }

  static void _sortById(List<ChatBubble> list) {
    // Stable, so a message's attachments keep their order.
    final indexed = list.indexed.toList()
      ..sort((a, b) {
        final c = a.$2.id.compareTo(b.$2.id);
        return c != 0 ? c : a.$1.compareTo(b.$1);
      });
    list
      ..clear()
      ..addAll(indexed.map((e) => e.$2));
  }

  void _merge(List<ChatBubble> incoming) {
    if (incoming.isEmpty) return;
    final shown = {for (final m in _list) m.serverId};
    final fresh = [
      for (final m in incoming)
        if (!shown.contains(m.serverId)) m,
    ];
    if (fresh.isEmpty) return;
    _rebuild([..._messages, ...fresh]);
    _status = null;
    _updateSticky();
  }

  void _rebuild(List<ChatBubble> messages) {
    _sortById(messages);
    _list.clear();
    String? lastKey;
    for (final m in messages) {
      final key = dayKeyOf(m);
      if (key != lastKey) {
        _list.add(ChatBubble.header(dateLabelFor(m.at)));
        lastKey = key;
      }
      _list.add(m);
    }
    if (mounted) setState(() {});
  }

  void _removeMessage(int id) {
    if (id <= 0) return;
    final remaining = [
      for (final m in _messages)
        if (m.id != id) m,
    ];
    if (remaining.length != _messages.length) _rebuild(remaining);
    _updateRepliesQuoting('$id', null);
    if (_list.isEmpty) _showStatus('No messages yet. Say hi 👋');
  }

  void _replaceMessage(int id, List<ChatBubble> bubbles) {
    _rebuild([
      for (final m in _messages)
        if (m.id != id) m,
      ...bubbles,
    ]);
    _updateRepliesQuoting('$id', ChatParser.quoteOf(bubbles));
    _showStatus(null);
  }

  void _updateRepliesQuoting(String target, ReplyQuote? quote) {
    for (final m in _list) {
      final r = m.reply;
      if (r == null || r.targetId != target) continue;
      m.reply =
          quote ??
          ReplyQuote(preview: removedText, name: r.name, targetId: target);
    }
    if (quote == null) {
      _parser.removedIds.add(target);
    } else {
      _parser.removedIds.remove(target);
    }
    if (mounted) setState(() {});
  }

  // ---- scrolling ----

  bool get _isAtBottom => !_scroll.hasClients || _scroll.offset <= 4;

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(0);
    });
    _updateSticky();
  }

  void _onScroll() {
    _updateSticky();
    // Near the oldest loaded message: fetch the page before it.
    final firstVisible = _firstVisibleIndex();
    if (firstVisible != null && firstVisible <= _loadMoreThreshold) {
      _loadMoreHistory();
    }
  }

  /// List index of the topmost row on screen.
  int? _firstVisibleIndex() {
    final listBox = context.findRenderObject() as RenderBox?;
    if (listBox == null) return null;
    int? best;
    for (var i = 0; i < _list.length; i++) {
      final ctx = _rowKeys[_keyFor(i)]?.currentContext;
      final box = ctx?.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) continue;
      final top = box.localToGlobal(Offset.zero, ancestor: listBox).dy;
      if (top + box.size.height > 0) {
        best = i;
        break;
      }
    }
    return best;
  }

  /// The sticky date pill for the day at the top; fades after 1.5s.
  void _updateSticky() {
    if (!mounted) return;
    final first = _firstVisibleIndex();
    if (first == null) return;
    String? label;
    for (var i = first; i >= 0; i--) {
      if (_list[i].type == BubbleType.header) {
        label = _list[i].dateLabel;
        break;
      }
    }
    if (label == null) return;
    _stickyTimer?.cancel();
    if (_stickyLabel != label) setState(() => _stickyLabel = label);
    _stickyTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _stickyLabel = null);
    });
  }

  String _keyFor(int index) {
    final m = _list[index];
    return m.type == BubbleType.header
        ? 'h:${m.dateLabel}:$index'
        : 'm:${m.id}:${m.attachmentId}';
  }

  /// Jumps to a quoted message, paging older history until it turns up.
  Future<void> _navigateTo(String? target) async {
    if (target == null || _parser.removedIds.contains(target)) return;
    var index = _list.indexWhere((m) => m.serverId == target);
    while (index == -1) {
      if (_loadingMoreHistory) return;
      if (!_hasMoreHistory) {
        _toast('Original message not found');
        return;
      }
      if (!await _loadMoreHistory()) return;
      index = _list.indexWhere((m) => m.serverId == target);
    }
    await _scrollToIndex(index);
  }

  Future<void> _scrollToIndex(int index) async {
    for (var i = 0; i < 60 && mounted; i++) {
      final ctx = _rowKeys[_keyFor(index)]?.currentContext;
      if (ctx != null && ctx.mounted) {
        await Scrollable.ensureVisible(ctx, alignment: 1);
        return;
      }
      final pos = _scroll.position;
      if (pos.pixels >= pos.maxScrollExtent) return;
      _scroll.jumpTo(
        math.min(pos.maxScrollExtent, pos.pixels + pos.viewportDimension),
      );
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  // ---- composer ----

  void _showReply(ChatBubble m) {
    if (m.type == BubbleType.header) return;
    setState(() => _replyTo = m);
    _inputFocus.requestFocus();
  }

  void _hideReply() => setState(() => _replyTo = null);

  void _send() {
    final text = _input.text.trim();
    if (text.isEmpty) {
      _toast('Message cannot be empty');
      return;
    }
    if (text.length > _maxMessageLength) {
      _toast(
        'Message is too long (${text.length}/$_maxMessageLength characters)',
      );
      return;
    }
    _post(text, null);
  }

  /// POST chat/groups/{slug}/messages/: text, a file, or both, with reply_to.
  Future<void> _post(String? text, http.MultipartFile? file) async {
    final slug = _roomId;
    if (slug == null) return;
    if (_roomUnavailable) {
      _toast("This chat group isn't available");
      return;
    }
    if (_sending) {
      _toast('Still sending your last message…');
      return;
    }
    setState(() => _sending = true);
    final reply = _replyTo;
    try {
      final result = await widget.api.postMultipart(
        'chat/groups/$slug/messages/',
        fields: {
          if (text != null && text.isNotEmpty) 'message': text,
          if (reply != null) 'reply_to': reply.serverId,
        },
        files: [?file],
      );
      if (!mounted) return;
      setState(() => _sending = false);
      if (result.status < 200 || result.status >= 300 || result.json == null) {
        final code = '${result.json?['message'] ?? ''}';
        if (code == 'INVALID_REPLY') _hideReply();
        _toast(sendErrorText(result.status, result.json));
        return;
      }
      _input.clear();
      setState(() => _replyTo = null);
      if (slug != _roomId) return;
      final created = messageObject(eventPayload(result.json!));
      if (((created['id'] as num?)?.toInt() ?? 0) > 0) {
        _merge(_parser.parse(created));
        _scrollToBottom();
      }
    } on CollegeGuideApiException {
      if (!mounted) return;
      setState(() => _sending = false);
      _toast("Couldn't send. Check your connection and try again.");
    }
  }

  Future<void> _pick(String kind) async {
    setState(() => _attachmentsOpen = false);
    Uint8List? bytes;
    String? name;
    try {
      if (kind == 'PDF') {
        final picked = await FilePicker.pickFiles(
          type: FileType.custom,
          allowedExtensions: const ['pdf'],
        );
        final f = picked.isEmpty ? null : picked.single;
        final path = f?.path;
        bytes = path == null ? null : await File(path).readAsBytes();
        name = f?.name;
      } else {
        final picked = await ImagePicker().pickImage(
          source: kind == 'Camera' ? ImageSource.camera : ImageSource.gallery,
          requestFullMetadata: false,
        );
        if (picked != null) {
          bytes = await picked.readAsBytes();
          name = picked.name;
        }
      }
    } on Exception {
      if (kind == 'Camera') _toast('Camera permission denied');
      return;
    }
    if (bytes == null || name == null || !mounted) return;
    await _upload(bytes, name, kind == 'PDF');
  }

  /// Only real JPG / PNG / PDF up to 10 MB: other photo formats become JPG,
  /// a sideways (EXIF) photo is turned upright, a big one is scaled down.
  Future<void> _upload(Uint8List bytes, String name, bool pdf) async {
    var mime = pdf ? 'application/pdf' : guessMimeType(name);
    final isImage =
        !pdf &&
        (mime.startsWith('image/') || mime == 'application/octet-stream');
    if (!isImage && !pdf) {
      _toast('Only JPG, PNG and PDF files can be sent');
      return;
    }
    if (pdf && bytes.length > _maxFileBytes) {
      _toast('PDF must be 10 MB or smaller');
      return;
    }
    final caption = _input.text.trim();
    if (caption.length > _maxMessageLength) {
      _toast(
        'Message is too long (${caption.length}/$_maxMessageLength characters)',
      );
      return;
    }
    var data = bytes;
    var fileName = name;
    if (isImage) {
      final prepared = await compute(_prepareImage, (bytes, mime));
      if (prepared == null) {
        _toast("This photo can't be sent. Choose a JPG or PNG");
        return;
      }
      data = prepared.$1;
      if (prepared.$2) {
        mime = 'image/jpeg';
        fileName = _withExtension(fileName, '.jpg');
      }
    } else {
      fileName = _withExtension(fileName, '.pdf');
    }
    if (data.length > _maxFileBytes) {
      _toast(
        isImage
            ? 'Photo must be 10 MB or smaller'
            : 'PDF must be 10 MB or smaller',
      );
      return;
    }
    _toast(isImage ? 'Sending photo…' : 'Sending PDF…');
    await _post(
      caption,
      http.MultipartFile.fromBytes(
        'files',
        data,
        filename: fileName,
        contentType: MediaType.parse(mime),
      ),
    );
  }

  static String _withExtension(String name, String ext) {
    final lower = name.toLowerCase();
    if (lower.endsWith(ext)) return name;
    if (ext == '.jpg' && lower.endsWith('.jpeg')) return name;
    final dot = name.lastIndexOf('.');
    return '${dot > 0 ? name.substring(0, dot) : name}$ext';
  }

  void _openImage(String? url) {
    if (url != null) viewUrl(url, mimeType: 'image/*');
  }

  void _openFile(ChatBubble m) {
    if (m.url != null) viewUrl(m.url!, chooserTitle: m.fileName ?? 'Document');
  }

  // ---- build ----

  bool _firstInGroup(int index) {
    if (index == 0) return true;
    final prev = _list[index - 1];
    if (prev.type == BubbleType.header) return true;
    return prev.username != _list[index].username;
  }

  Widget _row(int index, double maxBubble) {
    final m = _list[index];
    final key = _rowKeys.putIfAbsent(_keyFor(index), GlobalKey.new);
    if (m.type == BubbleType.header) {
      return Padding(
        key: key,
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Center(child: DateHeaderChip(m.dateLabel ?? '')),
      );
    }
    final first = _firstInGroup(index);
    final Widget bubble = switch (m.type) {
      BubbleType.image => ImageBubble(
        bubble: m,
        first: first,
        maxWidth: maxBubble,
        onQuoteTap: () => _navigateTo(m.reply?.targetId),
        onImageTap: () => _openImage(m.url),
      ),
      BubbleType.file => FileBubble(
        bubble: m,
        first: first,
        maxWidth: maxBubble,
        onQuoteTap: () => _navigateTo(m.reply?.targetId),
        onOpen: () => _openFile(m),
      ),
      _ => TextBubble(
        bubble: m,
        first: first,
        maxWidth: maxBubble,
        onQuoteTap: () => _navigateTo(m.reply?.targetId),
      ),
    };
    final row = Padding(
      padding: const EdgeInsets.fromLTRB(8, 3, 8, 0),
      child: m.mine
          ? Align(alignment: Alignment.centerRight, child: bubble)
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ChatAvatar(m, visible: first),
                const SizedBox(width: 6),
                Flexible(child: bubble),
              ],
            ),
    );
    return _SwipeToReply(key: key, onReply: () => _showReply(m), child: row);
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final maxBubble = width * 0.74;
    final replying = _replyTo != null;
    return ColoredBox(
      color: _chatBg,
      child: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () {
                    FocusManager.instance.primaryFocus?.unfocus();
                    if (_attachmentsOpen) {
                      setState(() => _attachmentsOpen = false);
                    }
                  },
                  child: ListView.builder(
                    key: const Key('chatList'),
                    controller: _scroll,
                    reverse: true,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 2,
                      vertical: 8,
                    ),
                    itemCount: _list.length,
                    itemBuilder: (context, i) =>
                        _row(_list.length - 1 - i, maxBubble),
                  ),
                ),
                if (_status != null)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Text(
                            _status!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: _meta,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  top: 8,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: _stickyLabel == null ? 0 : 1,
                      duration: const Duration(milliseconds: 250),
                      child: Center(
                        child: _stickyLabel == null
                            ? const SizedBox.shrink()
                            : DateHeaderChip(_stickyLabel!, sticky: true),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Container(
                        // 10dp/6dp margins plus the card's compat padding.
                        margin: const EdgeInsets.fromLTRB(13, 0.5, 9, 0.5),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(
                            replying || _input.text.contains('\n') ? 20 : 360,
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x1F000000),
                              blurRadius: 1,
                              offset: Offset(0, 0.5),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(6),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_replyTo != null) _composerReply(_replyTo!),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Expanded(
                                  child: TextField(
                                    key: const Key('chatInput'),
                                    controller: _input,
                                    focusNode: _inputFocus,
                                    minLines: 1,
                                    maxLines: 5,
                                    keyboardType: TextInputType.multiline,
                                    textCapitalization:
                                        TextCapitalization.sentences,
                                    cursorColor: _state,
                                    style: const TextStyle(
                                      color: Colors.black,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                      height: 1.21,
                                    ),
                                    decoration: const InputDecoration(
                                      hintText: 'Message',
                                      hintStyle: TextStyle(
                                        color: _meta,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      isDense: true,
                                      filled: false,
                                      border: InputBorder.none,
                                      enabledBorder: InputBorder.none,
                                      focusedBorder: InputBorder.none,
                                      constraints: BoxConstraints(
                                        minHeight: 38,
                                      ),
                                      contentPadding: EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 9.3,
                                      ),
                                    ),
                                  ),
                                ),
                                Semantics(
                                  label: 'Attach',
                                  button: true,
                                  child: GestureDetector(
                                    onTap: _sending
                                        ? null
                                        : () {
                                            if (_attachmentsOpen) {
                                              setState(
                                                () => _attachmentsOpen = false,
                                              );
                                            } else {
                                              FocusManager.instance.primaryFocus
                                                  ?.unfocus();
                                              setState(
                                                () => _attachmentsOpen = true,
                                              );
                                            }
                                          },
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        3,
                                        3,
                                        11,
                                        8,
                                      ),
                                      child: SvgPicture.asset(
                                        'assets/icons/ic_baseline_attach_file_24.svg',
                                        width: 26,
                                        height: 26,
                                        colorFilter: const ColorFilter.mode(
                                          Colors.black,
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
                      ),
                    ),
                    Semantics(
                      label: 'Send',
                      button: true,
                      child: GestureDetector(
                        onTap: _sending ? null : _send,
                        child: Opacity(
                          opacity: _sending ? 0.5 : 1,
                          child: Container(
                            width: 38,
                            height: 38,
                            margin: const EdgeInsets.only(right: 10),
                            padding: const EdgeInsets.all(8),
                            decoration: const BoxDecoration(
                              color: _state,
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
                    ),
                  ],
                ),
                AnimatedSize(
                  duration: Duration(
                    milliseconds: _attachmentsOpen ? 280 : 240,
                  ),
                  curve: Curves.decelerate,
                  child: _attachmentsOpen
                      ? _attachmentPanel()
                      : const SizedBox(width: double.infinity),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _composerReply(ChatBubble m) {
    final thumb = m.type == BubbleType.image ? m.url : null;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(0, 6, 10, 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 3,
              margin: const EdgeInsets.only(left: 8),
              decoration: const BoxDecoration(
                color: Color(0xFF28328C),
                borderRadius: BorderRadius.horizontal(
                  left: Radius.circular(16),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    m.mine ? 'You' : m.username,
                    maxLines: 1,
                    style: const TextStyle(
                      color: Color(0xFF167D28),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  ReplyPreviewText(
                    m.previewText(),
                    style: const TextStyle(color: Colors.black, fontSize: 13),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (thumb != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: CachedNetworkImage(
                        imageUrl: thumb,
                        width: 44,
                        height: 44,
                        fit: BoxFit.cover,
                      ),
                    ),
                  Align(
                    alignment: Alignment.topCenter,
                    child: GestureDetector(
                      onTap: _hideReply,
                      child: Container(
                        width: 20,
                        height: 20,
                        margin: const EdgeInsets.only(left: 8),
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: Color(0xB3FFFFFF),
                          shape: BoxShape.circle,
                        ),
                        child: SvgPicture.asset(
                          'assets/icons/cancel.svg',
                          colorFilter: const ColorFilter.mode(
                            Colors.black,
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
    );
  }

  /// Camera / Gallery / PDF (chat_gallery_row.xml in a 3-column grid).
  Widget _attachmentPanel() {
    const items = [
      ('Camera', 'Take a photo', 'ic_camera', Color(0xFF4CAF50)),
      ('Gallery', 'Choose from gallery', 'ic_gallery', Color(0xFF9C27B0)),
      ('PDF', 'Share a PDF', 'ic_document', Color(0xFFFF9800)),
    ];
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(8),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      ),
      child: Row(
        children: [
          for (final item in items)
            Expanded(
              child: InkWell(
                onTap: () => _pick(item.$1),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: item.$4,
                          shape: BoxShape.circle,
                        ),
                        child: SvgPicture.asset(
                          'assets/icons/${item.$3}.svg',
                          width: 28,
                          height: 28,
                          colorFilter: const ColorFilter.mode(
                            Colors.white,
                            BlendMode.srcIn,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.$1,
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF1A1A1A),
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.$2,
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF777777),
                          fontSize: 9,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Upright, JPG/PNG and ≤10 MB (runs on a background isolate).
(Uint8List, bool)? _prepareImage((Uint8List, String) args) {
  final (bytes, mime) = args;
  final jpegOrPng = mime == 'image/jpeg' || mime == 'image/png';
  var data = bytes;
  var reencoded = false;
  img.Image? decoded;
  if (mime == 'image/jpeg') {
    final exif = img.decodeJpgExif(bytes);
    final orientation = exif?.imageIfd.orientation ?? 1;
    if (orientation != 1) {
      decoded = img.decodeJpg(bytes);
      if (decoded == null) return (bytes, false);
      decoded = img.bakeOrientation(decoded);
      data = img.encodeJpg(decoded, quality: 92);
      reencoded = true;
    }
  }
  if (!jpegOrPng) {
    decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    data = img.encodeJpg(decoded, quality: 90);
    reencoded = true;
  }
  for (
    var sample = 2;
    data.length > _maxFileBytes && sample <= 8;
    sample *= 2
  ) {
    decoded ??= img.decodeImage(bytes);
    if (decoded == null) break;
    final smaller = img.copyResize(decoded, width: decoded.width ~/ sample);
    data = img.encodeJpg(smaller, quality: 90);
    reencoded = true;
  }
  return (data, reencoded);
}

/// SwipeToReplyCallback: drag right (with resistance, max 40% width); past
/// 35% the reply fires once and the row springs back.
class _SwipeToReply extends StatefulWidget {
  const _SwipeToReply({super.key, required this.onReply, required this.child});

  final VoidCallback onReply;
  final Widget child;

  @override
  State<_SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<_SwipeToReply>
    with SingleTickerProviderStateMixin {
  late final _spring = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );
  double _dx = 0;
  double _from = 0;
  bool _triggered = false;

  @override
  void initState() {
    super.initState();
    _spring.addListener(() {
      if (mounted) setState(() => _dx = _from * (1 - _spring.value));
    });
  }

  @override
  void dispose() {
    _spring.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final max = box.maxWidth * 0.4;
        return GestureDetector(
          onHorizontalDragStart: (_) {
            _spring.stop();
            _triggered = false;
          },
          onHorizontalDragUpdate: (d) {
            setState(() => _dx = (_dx + d.delta.dx * 0.6).clamp(0.0, max));
            if (!_triggered && _dx / max >= 0.35) {
              _triggered = true;
              widget.onReply();
            }
          },
          onHorizontalDragEnd: (_) {
            _from = _dx;
            _spring.forward(from: 0);
          },
          child: Stack(
            children: [
              if (_dx > 0)
                Positioned(
                  left: 16,
                  top: 0,
                  bottom: 0,
                  child: Opacity(
                    opacity: (_dx / max).clamp(0.0, 1.0),
                    child: Center(
                      child: SvgPicture.asset(
                        'assets/icons/reply_24px.svg',
                        width: 24,
                        height: 24,
                      ),
                    ),
                  ),
                ),
              Transform.translate(offset: Offset(_dx, 0), child: widget.child),
            ],
          ),
        );
      },
    );
  }
}
