import 'package:flutter/material.dart';

/// colorAccent under the native Theme.Material3 app theme.
const _accent = Color(0xFF6750A4);

/// The native `android.app.AlertDialog`: a white 2dp-cornered card with a
/// 20sp title, 16sp message and borderless all-caps accent buttons, in the
/// system font. Resolves true for [positive], false for [negative] and null
/// when dismissed.
Future<bool?> showNativeAlert(
  BuildContext context, {
  required String title,
  required String message,
  required String positive,
  String? negative,
  bool cancelable = true,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: cancelable,
    barrierColor: const Color(0x99000000),
    builder: (dialogContext) => PopScope(
      canPop: cancelable,
      child: NativeAlertDialog(
        title: title,
        message: message,
        positive: positive,
        negative: negative,
      ),
    ),
  );
}

class NativeAlertDialog extends StatelessWidget {
  const NativeAlertDialog({
    super.key,
    required this.title,
    required this.message,
    required this.positive,
    this.negative,
  });

  final String title;
  final String message;
  final String positive;
  final String? negative;

  Widget _button(BuildContext context, String label, bool result) {
    return TextButton(
      onPressed: () => Navigator.of(context).pop(result),
      style: TextButton.styleFrom(
        foregroundColor: _accent,
        minimumSize: const Size(64, 48),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
        textStyle: const TextStyle(
          fontFamily: 'Roboto',
          fontSize: 14,
          fontWeight: FontWeight.w500,
          letterSpacing: 1.25,
        ),
      ),
      child: Text(label.toUpperCase()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 24,
      insetPadding: const EdgeInsets.symmetric(horizontal: 26, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 21, 24, 0),
              child: Text(
                title,
                style: const TextStyle(
                  fontFamily: 'Roboto',
                  color: Color(0xDE000000),
                  fontSize: 20,
                  fontWeight: FontWeight.w500,
                  height: 1.17,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 11, 24, 0),
              child: Text(
                message,
                style: const TextStyle(
                  fontFamily: 'Roboto',
                  color: Color(0xDE000000),
                  fontSize: 16,
                  height: 1.17,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 13, 12, 3),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (negative != null) _button(context, negative!, false),
                  _button(context, positive, true),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
