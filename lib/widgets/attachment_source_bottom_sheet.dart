import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// iOS often refuses to show the system document picker if it is presented while
/// another route (menu overlay, modal sheet, etc.) is still being torn down. Pop the
/// sheet first, then run the native pick after the **next** frame so the presenter
/// hierarchy is stable.
Future<void> showAttachmentSourceBottomSheet({
  required BuildContext context,
  required VoidCallback onPickFromDevice,
  required VoidCallback onPickFromLink,
}) {
  void runAfterSheetDismissed(VoidCallback action) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      SchedulerBinding.instance.addPostFrameCallback((_) => action());
    });
  }

  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    showDragHandle: true,
    builder: (sheetCtx) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              leading: const Icon(Icons.upload_file_outlined),
              title: const Text('From your device'),
              onTap: () {
                Navigator.pop(sheetCtx);
                runAfterSheetDismissed(onPickFromDevice);
              },
            ),
            ListTile(
              leading: const Icon(Icons.add_link_outlined),
              title: const Text('Link to a file or website'),
              onTap: () {
                Navigator.pop(sheetCtx);
                runAfterSheetDismissed(onPickFromLink);
              },
            ),
          ],
        ),
      );
    },
  );
}
