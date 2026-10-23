import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;
import 'package:printing/printing.dart';

import 'chat_models.dart';

const _sentColor = Color(0xFFDCF8C6);
const _timeColor = Color(0xFF606B72);
const _quoteBg = Color(0xFFF5F5F5);
const _quoteBar = Color(0xFF28328C);
const _quoteName = Color(0xFF167D28);

/// TIME_GAP_DP: text end → inline time.
const _timeGap = 9.5;

const _timeStyle = TextStyle(
  color: _timeColor,
  fontSize: 11,
  fontWeight: FontWeight.w400,
  height: 1.21,
);
const _messageStyle = TextStyle(
  color: Colors.black,
  fontSize: 16,
  fontWeight: FontWeight.w500,
  height: 1.21,
);

double _measure(String text, TextStyle style) {
  final p = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textScaler: TextScaler.noScaling,
  )..layout();
  return p.width;
}

/// The message with blank room at its end for the overlaid time, so the time
/// sits on the last line when it fits and drops below when it doesn't.
class _TextWithTime extends StatelessWidget {
  const _TextWithTime({
    required this.text,
    required this.time,
    required this.maxWidth,
    this.startMargin = 5,
    this.endMargin = 6,
  });

  final String text;
  final String time;
  final double maxWidth;
  final double startMargin;
  final double endMargin;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final timeWidth = scaler.scale(_measure(time, _timeStyle));
    final spaceWidth = scaler.scale(_measure(' ', _messageStyle));
    var gap = timeWidth + _timeGap - spaceWidth - endMargin;
    if (gap < timeWidth) gap = timeWidth;
    return Stack(
      children: [
        Padding(
          padding: EdgeInsets.only(left: startMargin, right: endMargin),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: '$text '),
                  WidgetSpan(child: SizedBox(width: gap, height: 1)),
                ],
              ),
              style: _messageStyle,
            ),
          ),
        ),
        Positioned(right: 0, bottom: 0, child: Text(time, style: _timeStyle)),
      ],
    );
  }
}

/// The speech-bubble background of the first bubble in a run: a 4dp rounded
/// body inset from the tail side and a tail at the top corner
/// (incoming/outgoing_speech_bubble.xml).
class _SpeechBubblePainter extends CustomPainter {
  _SpeechBubblePainter({required this.incoming});

  final bool incoming;

  Path _path(Size size) {
    final w = size.width;
    final h = size.height;
    const r = Radius.circular(4);
    final body = incoming
        ? RRect.fromLTRBR(8, 0, w, h, r)
        : RRect.fromLTRBR(0, 0, w - 10, h, r);
    final path = Path()..addRRect(body);
    if (incoming) {
      // A 20dp band rotated -35° about the top-left corner.
      path.addPolygon(const [
        Offset(0, 0),
        Offset(34.9, 0),
        Offset(11.5, 16.4),
      ], true);
    } else {
      // Rotated 40° about the top-right corner.
      path.addPolygon([
        Offset(w, 0),
        Offset(w - 12.9, 15.3),
        Offset(w - 31.1, 0),
      ], true);
    }
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final path = _path(size);
    canvas.drawPath(
      path.shift(const Offset(0, 1)),
      Paint()..color = const Color(0x14000000),
    );
    canvas.drawPath(
      path,
      Paint()..color = incoming ? Colors.white : _sentColor,
    );
  }

  @override
  bool shouldRepaint(_SpeechBubblePainter old) => old.incoming != incoming;
}

/// applyBubbleShape: first in a run → speech bubble with tail (content padded
/// on the tail side); later ones → a plain 8dp card lined up under it.
class BubbleShell extends StatelessWidget {
  const BubbleShell({
    super.key,
    required this.incoming,
    required this.first,
    required this.child,
    this.width,
  });

  final bool incoming;
  final bool first;
  final Widget child;
  final double? width;

  @override
  Widget build(BuildContext context) {
    if (first) {
      return CustomPaint(
        painter: _SpeechBubblePainter(incoming: incoming),
        child: Padding(
          padding: EdgeInsets.only(
            left: incoming ? 8 : 0,
            right: incoming ? 0 : 10,
          ),
          child: SizedBox(width: width, child: child),
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.only(
        left: incoming ? 8 : 0,
        right: incoming ? 0 : 10,
      ),
      child: Container(
        width: width,
        decoration: BoxDecoration(
          color: incoming ? Colors.white : _sentColor,
          borderRadius: BorderRadius.circular(8),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1F000000),
              blurRadius: 1,
              offset: Offset(0, 0.5),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    );
  }
}

/// The reply preview text with "📷 " drawn as an outlined photo icon.
class ReplyPreviewText extends StatelessWidget {
  const ReplyPreviewText(
    this.text, {
    super.key,
    required this.style,
    this.maxLines = 1,
  });

  final String text;
  final TextStyle style;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    const prefix = '📷 ';
    if (!text.startsWith(prefix)) {
      return Text(
        text,
        style: style,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
      );
    }
    final size = (style.fontSize ?? 13) * 1.05;
    return Text.rich(
      TextSpan(
        children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: SvgPicture.asset(
              'assets/icons/ic_reply_photo.svg',
              width: size,
              height: size,
              colorFilter: ColorFilter.mode(
                style.color ?? Colors.black,
                BlendMode.srcIn,
              ),
            ),
          ),
          TextSpan(text: ' ${text.substring(prefix.length)}'),
        ],
      ),
      style: style,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// The quote box inside a bubble.
class _QuoteBox extends StatelessWidget {
  const _QuoteBox({
    required this.quote,
    required this.onTap,
    required this.compact,
  });

  final ReplyQuote quote;
  final VoidCallback onTap;

  /// Media / file bubbles use the one-line quote with a small thumbnail.
  final bool compact;

  static const _nameStyle = TextStyle(
    color: _quoteName,
    fontSize: 13,
    fontWeight: FontWeight.w500,
    height: 1.21,
  );
  static const _previewStyle = TextStyle(
    color: Colors.black,
    fontSize: 13,
    fontWeight: FontWeight.w500,
    height: 1.21,
  );

  @override
  Widget build(BuildContext context) {
    final thumb = quote.thumbnail;
    final texts = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          quote.name ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _nameStyle,
        ),
        const SizedBox(height: 3),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 80),
          child: ReplyPreviewText(
            quote.preview,
            style: _previewStyle,
            maxLines: compact ? 1 : 3,
          ),
        ),
      ],
    );
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          color: _quoteBg,
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
        child: compact
            ? Padding(
                padding: const EdgeInsets.all(6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 5,
                      height: 36,
                      decoration: const BoxDecoration(
                        color: _quoteBar,
                        borderRadius: BorderRadius.horizontal(
                          left: Radius.circular(16),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(child: texts),
                    if (thumb != null) ...[
                      const SizedBox(width: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: CachedNetworkImage(
                          imageUrl: thumb,
                          width: 36,
                          height: 36,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ],
                  ],
                ),
              )
            : IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(
                      width: 5,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: _quoteBar,
                          borderRadius: BorderRadius.horizontal(
                            left: Radius.circular(16),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(11, 8, 10, 8),
                        child: texts,
                      ),
                    ),
                    if (thumb != null)
                      // 56dp wide, as tall as the quote (at least 56dp).
                      Container(
                        width: 56,
                        constraints: const BoxConstraints(minHeight: 56),
                        decoration: BoxDecoration(
                          image: DecorationImage(
                            image: CachedNetworkImageProvider(thumb),
                            fit: BoxFit.cover,
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

class _SenderName extends StatelessWidget {
  const _SenderName(this.bubble, {required this.padding});

  final ChatBubble bubble;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Text(
        bubble.username,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: readableOnWhite(bubble.senderColor),
          fontSize: 13,
          fontWeight: FontWeight.w500,
          height: 1.21,
        ),
      ),
    );
  }
}

/// The sender's initial on a circle in their colour.
class ChatAvatar extends StatelessWidget {
  const ChatAvatar(this.bubble, {super.key, required this.visible});

  final ChatBubble bubble;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    final name = bubble.username.trim();
    return Visibility.maintain(
      visible: visible,
      child: Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: readableOnWhite(bubble.senderColor),
          shape: BoxShape.circle,
        ),
        child: Text(
          name.isEmpty ? '?' : name.substring(0, 1).toUpperCase(),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// group_item_chat_{send,receive}_text.xml.
class TextBubble extends StatelessWidget {
  const TextBubble({
    super.key,
    required this.bubble,
    required this.first,
    required this.maxWidth,
    required this.onQuoteTap,
  });

  final ChatBubble bubble;
  final bool first;
  final double maxWidth;
  final VoidCallback onQuoteTap;

  @override
  Widget build(BuildContext context) {
    final incoming = !bubble.mine;
    final quote = bubble.reply;
    // The card's -3dp (received) / -2dp (sent) top margin trims its padding.
    return BubbleShell(
      incoming: incoming,
      first: first,
      child: Padding(
        padding: EdgeInsets.fromLTRB(6, incoming ? 3 : 4, 6, 6),
        child: IntrinsicWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (incoming && first)
                _SenderName(
                  bubble,
                  padding: const EdgeInsets.fromLTRB(7, 2, 8, 2),
                ),
              if (quote != null && quote.preview.isNotEmpty)
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth + 15),
                  child: _QuoteBox(
                    quote: quote,
                    onTap: onQuoteTap,
                    compact: false,
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(2),
                child: _TextWithTime(
                  text: bubble.text ?? '',
                  time: bubble.time,
                  maxWidth: maxWidth,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// group_item_chat_{send,receive}_media.xml.
class ImageBubble extends StatelessWidget {
  const ImageBubble({
    super.key,
    required this.bubble,
    required this.first,
    required this.maxWidth,
    required this.onQuoteTap,
    required this.onImageTap,
  });

  final ChatBubble bubble;
  final bool first;
  final double maxWidth;
  final VoidCallback onQuoteTap;
  final VoidCallback onImageTap;

  @override
  Widget build(BuildContext context) {
    final incoming = !bubble.mine;
    final width = maxWidth - 4;
    // Height follows the photo's ratio, clamped to 160–340dp; unknown → 4:3.
    final w = bubble.width ?? 4;
    final h = bubble.height ?? 3;
    final height = (width * h / w).clamp(160.0, 340.0);
    final quote = bubble.reply;
    return BubbleShell(
      incoming: incoming,
      first: first,
      child: SizedBox(
        width: maxWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (quote != null && quote.preview.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
                child: _QuoteBox(
                  quote: quote,
                  onTap: onQuoteTap,
                  compact: true,
                ),
              ),
            if (incoming && first)
              _SenderName(
                bubble,
                padding: const EdgeInsets.fromLTRB(6, 6, 6, 2),
              ),
            Stack(
              children: [
                GestureDetector(
                  onTap: onImageTap,
                  child: Container(
                    margin: const EdgeInsets.all(2),
                    width: width,
                    height: height,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: bubble.url == null
                        ? null
                        : CachedNetworkImage(
                            imageUrl: bubble.url!,
                            fit: BoxFit.cover,
                            memCacheWidth: 900,
                          ),
                  ),
                ),
                if (!bubble.hasCaption)
                  Positioned(
                    right: 10,
                    bottom: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0x40000000),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        bubble.time,
                        style: _timeStyle.copyWith(color: Colors.white),
                      ),
                    ),
                  ),
              ],
            ),
            if (bubble.hasCaption)
              Padding(
                padding: const EdgeInsets.fromLTRB(11, 4, 6, 6),
                child: SizedBox(
                  width: double.infinity,
                  child: _TextWithTime(
                    text: bubble.text!,
                    time: bubble.time,
                    maxWidth: maxWidth - 16,
                    startMargin: 0,
                    endMargin: 0,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Page-1 top-strip previews of chat PDFs (PdfThumbnailLoader).
class _PdfThumbs {
  static final _cache = <String, Future<Uint8List?>>{};

  static Future<Uint8List?> load(String url) =>
      _cache.putIfAbsent(url, () => _render(url));

  static Future<Uint8List?> _render(String url) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200 ||
          response.bodyBytes.length > 15 * 1024 * 1024) {
        return null;
      }
      await for (final page in Printing.raster(
        response.bodyBytes,
        pages: const [0],
        dpi: 150,
      )) {
        return await page.toPng();
      }
    } on Object {
      return null;
    }
    return null;
  }
}

/// group_item_chat_{send,receive}_file.xml.
class FileBubble extends StatelessWidget {
  const FileBubble({
    super.key,
    required this.bubble,
    required this.first,
    required this.maxWidth,
    required this.onQuoteTap,
    required this.onOpen,
  });

  final ChatBubble bubble;
  final bool first;
  final double maxWidth;
  final VoidCallback onQuoteTap;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final incoming = !bubble.mine;
    final quote = bubble.reply;
    final pdf = (bubble.mimeType ?? '').toLowerCase() == 'application/pdf';
    final icon = SvgPicture.asset(
      'assets/icons/ic_document.svg',
      width: 24,
      height: 24,
      colorFilter: const ColorFilter.mode(Color(0xFF4CAF50), BlendMode.srcIn),
    );
    final timeHeight = MediaQuery.textScalerOf(context).scale(11 * 1.21);
    return BubbleShell(
      incoming: incoming,
      first: first,
      width: maxWidth - (first ? (incoming ? 8 : 10) : 0),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (quote != null && quote.preview.isNotEmpty)
              _QuoteBox(quote: quote, onTap: onQuoteTap, compact: true),
            if (incoming && first)
              _SenderName(
                bubble,
                padding: const EdgeInsets.only(left: 5, bottom: 2),
              ),
            GestureDetector(
              onTap: onOpen,
              behavior: HitTestBehavior.opaque,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 85,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    clipBehavior: Clip.antiAlias,
                    alignment: Alignment.center,
                    child: pdf && bubble.url != null
                        ? FutureBuilder<Uint8List?>(
                            future: _PdfThumbs.load(bubble.url!),
                            builder: (_, snap) => snap.data == null
                                ? _bordered(icon)
                                : _PdfStrip(snap.data!),
                          )
                        : _bordered(icon),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                    child: Text(
                      _middleEllipsis(bubble.fileName ?? 'Document'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _messageStyle,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 8, top: 2),
                    child: Text(
                      bubble.fileInfoText(),
                      style: const TextStyle(
                        color: _timeColor,
                        fontSize: 12,
                        height: 1.21,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // With no caption the time sits on the size line itself.
            Transform.translate(
              offset: Offset(0, bubble.hasCaption ? 0 : -timeHeight),
              child: Padding(
                padding: EdgeInsets.only(
                  top: bubble.hasCaption ? 6 : 0,
                  right: 6,
                  bottom: 3,
                ),
                child: bubble.hasCaption
                    ? Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: _TextWithTime(
                          text: bubble.text!,
                          time: bubble.time,
                          maxWidth: maxWidth - 21,
                          startMargin: 0,
                          endMargin: 0,
                        ),
                      )
                    : Align(
                        alignment: Alignment.centerRight,
                        child: Text(bubble.time, style: _timeStyle),
                      ),
              ),
            ),
            if (!bubble.hasCaption) SizedBox(height: 0 - 0 * timeHeight),
          ],
        ),
      ),
    );
  }

  /// shape_4dp_curve_bordered behind the generic icon; a page render covers it.
  static Widget _bordered(Widget icon) => Container(
    width: double.infinity,
    height: double.infinity,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: const Color(0xFFB4B4BE), width: 0.8),
    ),
    child: icon,
  );

  /// ellipsize="middle" for a long file name.
  static String _middleEllipsis(String name) => name.length <= 34
      ? name
      : '${name.substring(0, 16)}…${name.substring(name.length - 16)}';
}

/// Page 1's top strip (240:85 of the page width), centre-cropped into the
/// preview box like the native CENTER_CROP of that strip.
class _PdfStrip extends StatelessWidget {
  const _PdfStrip(this.png);

  final Uint8List png;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final stripHeight = box.maxWidth * 85 / 240;
        final cut = ((stripHeight - box.maxHeight) / 2).clamp(0.0, 999.0);
        return ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned(
                top: -cut,
                left: 0,
                right: 0,
                child: Image.memory(
                  png,
                  fit: BoxFit.fitWidth,
                  alignment: Alignment.topCenter,
                  filterQuality: FilterQuality.medium,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// group_item_date_header.xml.
class DateHeaderChip extends StatelessWidget {
  const DateHeaderChip(this.label, {super.key, this.sticky = false});

  final String label;
  final bool sticky;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: sticky ? 6 : 4),
      decoration: BoxDecoration(
        color: sticky ? const Color(0xFF3B3B3B) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: sticky
            ? null
            : const [
                BoxShadow(
                  color: Color(0x1F000000),
                  blurRadius: 1,
                  offset: Offset(0, 0.5),
                ),
              ],
      ),
      child: Text(
        label,
        style: TextStyle(
          color: sticky ? Colors.white : _timeColor,
          fontSize: 12.5,
          fontWeight: FontWeight.w500,
          height: 1.21,
        ),
      ),
    );
  }
}

/// Decodes [bytes] to measure an image (used for a just-sent photo).
Future<Size?> imageSizeOf(Uint8List bytes) async {
  try {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    return Size(descriptor.width.toDouble(), descriptor.height.toDouble());
  } on Object {
    return null;
  }
}
