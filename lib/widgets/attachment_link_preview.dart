import 'package:flutter/material.dart';

import '../utils/attachment_url_launch.dart';

/// Read-only line that opens `http`/`https` URLs on tap.
class AttachmentLinkPreview extends StatelessWidget {
  const AttachmentLinkPreview({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = text.trim();
    if (t.isEmpty) {
      return Text(
        '—',
        style: Theme.of(context).textTheme.bodyMedium,
      );
    }
    final uri = Uri.tryParse(t);
    final clickable =
        uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
    final base = Theme.of(context).textTheme.bodyMedium ?? const TextStyle();
    final style = clickable
        ? base.copyWith(
            color: Theme.of(context).colorScheme.primary,
            decoration: TextDecoration.underline,
            decorationColor: Theme.of(context).colorScheme.primary,
          )
        : base;

    return InkWell(
      onTap: clickable ? () => openAttachmentUrl(context, t) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(t, style: style),
      ),
    );
  }
}
