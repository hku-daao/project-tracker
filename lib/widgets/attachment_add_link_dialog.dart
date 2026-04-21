import 'package:flutter/material.dart';

/// Returns `(description, url)` on **Add**, or `null` on **Cancel**.
Future<({String description, String url})?> showAttachmentAddLinkDialog(
  BuildContext context,
) {
  final descCtrl = TextEditingController();
  final linkCtrl = TextEditingController();
  return showDialog<({String description, String url})>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: const Text('Link to a file or website'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: descCtrl,
                decoration: const InputDecoration(
                  labelText: 'Attachment description',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: linkCtrl,
                decoration: const InputDecoration(
                  labelText: 'Attachment link',
                  hintText: 'https://…',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                autocorrect: false,
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop((
                description: descCtrl.text.trim(),
                url: linkCtrl.text.trim(),
              ));
            },
            child: const Text('Add'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
        ],
      );
    },
  ).whenComplete(() {
    descCtrl.dispose();
    linkCtrl.dispose();
  });
}
