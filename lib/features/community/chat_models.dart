import 'dart:io' show Platform;

import 'package:flutter/painting.dart';
import 'package:intl/intl.dart';

/// GroupChatFragment.SENDER_COLORS.
const _senderColors = [
  Color(0xFF1E4B3E),
  Color(0xFF0B6E99),
  Color(0xFF8E44AD),
  Color(0xFFC0392B),
  Color(0xFFD35400),
  Color(0xFF16A085),
  Color(0xFF2C3E50),
  Color(0xFFB7950B),
];

const removedText = 'This message was removed';

enum BubbleType { text, image, file, header }

/// The quote shown above a reply (ChatMessageModel.ReplyTo).
class ReplyQuote {
  const ReplyQuote({
    required this.preview,
    this.name,
    this.targetId,
    this.thumbnail,
  });

  final String preview;
  final String? name;
  final String? targetId;
  final String? thumbnail;
}

/// One row of the chat list: a message bubble (one per attachment) or a
/// date header (ChatMessageModel).
class ChatBubble {
  ChatBubble.header(this.dateLabel)
    : type = BubbleType.header,
      id = 0,
      mine = false,
      username = '',
      time = '',
      at = null,
      senderColor = _senderColors.first;

  ChatBubble._({
    required this.type,
    required this.id,
    required this.mine,
    required this.username,
    required this.time,
    required this.at,
    required this.senderColor,
  }) : dateLabel = null;

  final BubbleType type;
  final int id;
  final bool mine;
  final String username;
  final String time;
  final DateTime? at;
  final Color senderColor;
  final String? dateLabel;

  String? text;
  ReplyQuote? reply;
  int attachmentId = 0;
  String? url;
  String? fileName;
  String? mimeType;
  String? sizeText;
  double? width;
  double? height;

  String get serverId => '$id';
  bool get hasCaption => (text ?? '').trim().isNotEmpty;

  /// previewText(): the reply bar's label for this message.
  String previewText() => switch (type) {
    BubbleType.image => hasCaption ? text! : '📷 Photo',
    BubbleType.file => '📎 ${fileName ?? 'Document'}',
    _ => text ?? '',
  };

  /// "48.5 KB  •  PDF".
  String fileInfoText() {
    final parts = <String>[
      if ((sizeText ?? '').trim().isNotEmpty) sizeText!.trim(),
      ?_typeLabel(),
    ];
    return parts.join('  •  ');
  }

  String? _typeLabel() {
    final mime = (mimeType ?? '').toLowerCase();
    if (mime == 'application/pdf') return 'PDF';
    if (mime.startsWith('image/')) return mime.substring(6).toUpperCase();
    final name = (fileName ?? '').toLowerCase();
    final dot = name.lastIndexOf('.');
    return dot >= 0 && dot < name.length - 1
        ? name.substring(dot + 1).toUpperCase()
        : null;
  }
}

/// String.hashCode() of Java, so a sender keeps the native colour.
int _javaHash(String s) {
  var h = 0;
  for (final c in s.codeUnits) {
    h = (31 * h + c) & 0xFFFFFFFF;
  }
  return h >= 0x80000000 ? h - 0x100000000 : h;
}

double _luminance(Color c) => c.computeLuminance();

/// GroupChatAdapter.readableOn(color, white): darkened until 4.5:1.
Color readableOnWhite(Color color) {
  var c = color;
  for (var i = 0; i < 40 && 1.05 / (_luminance(c) + 0.05) < 4.5; i++) {
    c = Color.fromARGB(
      255,
      (c.r * 255 * 0.94).toInt(),
      (c.g * 255 * 0.94).toInt(),
      (c.b * 255 * 0.94).toInt(),
    );
  }
  return c;
}

Color senderColorFor(String username) =>
    _senderColors[(_javaHash(username) % _senderColors.length).abs()];

final _isoPattern = RegExp(
  r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d+)?(Z|[+-]\d{2}:\d{2})?$',
);

/// parseIsoUtc: any fraction length, "Z" or "+05:30".
DateTime? parseChatTime(String? iso) {
  if (iso == null) return null;
  final m = _isoPattern.firstMatch(iso);
  if (m == null) return null;
  var t = DateTime.utc(
    int.parse(m[1]!),
    int.parse(m[2]!),
    int.parse(m[3]!),
    int.parse(m[4]!),
    int.parse(m[5]!),
    int.parse(m[6]!),
  );
  final offset = m[7];
  if (offset != null && offset != 'Z') {
    final sign = offset.startsWith('-') ? -1 : 1;
    final parts = offset.substring(1).split(':');
    t = t.subtract(
      Duration(
        hours: sign * int.parse(parts[0]),
        minutes: sign * int.parse(parts[1]),
      ),
    );
  }
  return t.toLocal();
}

/// The device locale decides "pm" (en_IN) or "PM", as SimpleDateFormat does.
bool get _lowerMeridiem {
  try {
    return Platform.localeName.contains('_IN');
  } on Object {
    return false;
  }
}

String formatChatTime(DateTime? t, String fallback) {
  if (t == null) return fallback;
  final s = DateFormat('h:mm a').format(t);
  return _lowerMeridiem ? s.toLowerCase() : s;
}

String _dayKey(DateTime t) => DateFormat('yyyyMMdd').format(t);

/// WhatsApp wording: Today / Yesterday / weekday within the week / full date.
String dateLabelFor(DateTime? t) {
  if (t == null) return '';
  final now = DateTime.now();
  if (_dayKey(t) == _dayKey(now)) return 'Today';
  if (_dayKey(t) == _dayKey(now.subtract(const Duration(days: 1)))) {
    return 'Yesterday';
  }
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(t.year, t.month, t.day);
  final daysAgo = today.difference(day).inDays;
  if (daysAgo >= 2 && daysAgo <= 6) return DateFormat('EEEE').format(t);
  return DateFormat('d MMMM yyyy').format(t);
}

String dayKeyOf(ChatBubble b) => b.at == null ? '' : _dayKey(b.at!);

String? _text(Map? m, String key) {
  final v = m?[key];
  if (v == null) return null;
  final s = '$v';
  return s.trim().isEmpty ? null : s;
}

String? formatFileSize(num? bytes) {
  if (bytes == null || bytes <= 0) return null;
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String guessMimeType(String? name) {
  final lower = (name ?? '').toLowerCase();
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.gif')) return 'image/gif';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.pdf')) return 'application/pdf';
  return 'application/octet-stream';
}

String _fileNameFromUrl(String url) {
  var name = url.substring(url.lastIndexOf('/') + 1);
  final q = name.indexOf('?');
  if (q >= 0) name = name.substring(0, q);
  return name;
}

/// Parses server messages into bubbles (GroupChatFragment.parseChatMessage).
class ChatParser {
  /// The signed-in user's chat name, learned from any is_mine message.
  String? myUsername;

  /// Ids whose quotes read "This message was removed".
  final removedIds = <String>{};

  List<ChatBubble> parse(Map<String, dynamic> obj) {
    final id = (obj['id'] as num?)?.toInt() ?? 0;
    final text = _text(obj, 'message');
    final mine = obj['is_mine'] == true;
    final username = (_text(obj, 'username') ?? 'Member').trim().replaceAll(
      RegExp(r'\s+'),
      ' ',
    );
    if (mine) myUsername = username;
    final iso = '${obj['created_at'] ?? ''}';
    final at = parseChatTime(iso);
    final reply = parseReply(obj['reply_to'] as Map?);

    ChatBubble base(BubbleType type) => ChatBubble._(
      type: type,
      id: id,
      mine: mine,
      username: username,
      time: formatChatTime(at, iso),
      at: at,
      senderColor: senderColorFor(username),
    );

    final bubbles = <ChatBubble>[];
    for (final a in (obj['attachments'] as List? ?? const [])) {
      if (a is! Map) continue;
      final url = _text(a, 'url');
      if (url == null) continue;
      final name = _text(a, 'name') ?? _fileNameFromUrl(url);
      final mime = _text(a, 'mime_type') ?? guessMimeType(name);
      final image =
          '${a['file_type']}'.toUpperCase() == 'IMAGE' ||
          mime.startsWith('image/');
      final first = bubbles.isEmpty;
      final b = base(image ? BubbleType.image : BubbleType.file)
        ..text = first ? text : null
        ..reply = first ? reply : null
        ..attachmentId = (a['id'] as num?)?.toInt() ?? 0
        ..url = url
        ..fileName = name
        ..mimeType = mime
        ..sizeText = formatFileSize(a['size'] as num?)
        ..width = (a['width'] as num?)?.toDouble()
        ..height = (a['height'] as num?)?.toDouble();
      bubbles.add(b);
    }
    if (bubbles.isEmpty) {
      bubbles.add(
        base(BubbleType.text)
          ..text = text ?? ''
          ..reply = reply,
      );
    }
    return bubbles;
  }

  /// reply_to → "📷 Photo" / "📎 name" / its text / removed.
  ReplyQuote? parseReply(Map? r) {
    if (r == null) return null;
    final rid = (r['id'] as num?)?.toInt() ?? 0;
    var name = _text(r, 'username')?.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (name != null && name == myUsername) name = 'You';
    final target = rid > 0 ? '$rid' : null;
    if (r['is_removed'] == true) {
      if (target != null) removedIds.add(target);
      return ReplyQuote(preview: removedText, name: name, targetId: target);
    }
    final text = _text(r, 'message');
    final files = r['attachments'] as List?;
    final file = files != null && files.isNotEmpty && files.first is Map
        ? files.first as Map
        : null;
    final image =
        file != null &&
        ('${file['file_type']}'.toUpperCase() == 'IMAGE' ||
            '${file['mime_type']}'.startsWith('image/'));
    final String preview;
    if (file != null && !image) {
      preview = '📎 ${_text(file, 'name') ?? text ?? 'Document'}';
    } else if (text != null) {
      preview = image ? '📷 $text' : text;
    } else if (file != null) {
      preview = '📷 Photo';
    } else {
      preview = r['has_attachments'] == true ? '📎 Attachment' : 'Message';
    }
    return ReplyQuote(
      preview: preview,
      name: name,
      targetId: target,
      thumbnail: image ? _text(file, 'url') : null,
    );
  }

  /// A quote of an on-screen message, for replies to it once it's restored.
  static ReplyQuote quoteOf(List<ChatBubble> bubbles) {
    final first = bubbles.first;
    return ReplyQuote(
      preview: first.type == BubbleType.image && first.hasCaption
          ? '📷 ${first.text}'
          : first.previewText(),
      name: first.mine ? 'You' : first.username,
      targetId: first.serverId,
      thumbnail: first.type == BubbleType.image ? first.url : null,
    );
  }
}

/// The event body under data / payload / message, or the event itself.
Map<String, dynamic> eventPayload(Map<String, dynamic> event) {
  for (final key in const ['data', 'payload', 'message']) {
    final o = event[key];
    if (o is Map<String, dynamic>) return o;
  }
  return event;
}

Map<String, dynamic> messageObject(Map<String, dynamic> payload) {
  final nested = payload['message'];
  return nested is Map<String, dynamic> ? nested : payload;
}

int messageIdOf(Map<String, dynamic> payload) {
  if (payload.containsKey('message_id')) {
    return (payload['message_id'] as num?)?.toInt() ?? 0;
  }
  return (messageObject(payload)['id'] as num?)?.toInt() ?? 0;
}

/// GroupChatFragment.sendErrorText.
String sendErrorText(int http, Map<String, dynamic>? err) {
  final code = '${err?['message'] ?? ''}';
  final data = err?['data'] is Map ? err!['data'] as Map : null;
  int opt(String key, int fallback) =>
      (data?[key] as num?)?.toInt() ?? fallback;
  switch (code) {
    case 'EMPTY_MESSAGE':
      return 'Type a message or attach a file';
    case 'MESSAGE_TOO_LONG':
      return 'Message is too long (max ${opt('max_length', 1000)} characters)';
    case 'TOO_MANY_FILES':
      return 'You can attach up to ${opt('max_files', 10)} files';
    case 'FILES_TOO_LARGE':
      return 'Files must be 10 MB or smaller in total';
    case 'INVALID_FILE_TYPE':
      final errors = data?['errors'] is Map ? data!['errors'] as Map : null;
      final files = errors?['files'] is List ? errors!['files'] as List : null;
      final first = files != null && files.isNotEmpty && files.first is Map
          ? files.first as Map
          : null;
      final name = _text(first, 'name');
      return name != null
          ? "$name isn't a valid JPG, PNG or PDF"
          : 'Only JPG, PNG and PDF files can be sent';
    case 'INVALID_REPLY':
      return 'The message you replied to is no longer available';
    case 'USER_BLOCKED_FROM_CHAT':
      return "You've been blocked from sending messages in this chat";
    case 'GROUP_NOT_FOUND':
      return "This chat group isn't available";
    case 'RATE_LIMITED':
      final seconds = opt('retry_after_seconds', 0);
      return seconds > 0
          ? "You're sending too fast. Try again in ${seconds}s"
          : "You're sending too fast. Try again shortly";
    case 'FILE_UPLOAD_FAILED':
      return 'Upload failed. Please try again';
    case 'TOKEN_EXPIRED':
    case 'AUTHENTICATION_FAILED':
      return 'Your session has expired. Please log in again';
    case 'PROFILE_INACTIVE':
      return 'Your profile is deactivated';
  }
  if (http == 413) return 'Files must be 10 MB or smaller in total';
  return _text(err, 'description') ?? "Couldn't send your message";
}
