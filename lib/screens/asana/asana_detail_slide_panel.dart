import 'package:flutter/material.dart';

import '../asana_landing_screen.dart';
import 'asana_detail_panel_host.dart';
import 'asana_detail_selection.dart';

/// Right-hand slide stack (push/pop with horizontal animation).
class AsanaDetailSlidePanel extends StatefulWidget {
  const AsanaDetailSlidePanel({
    super.key,
    required this.stack,
    required this.palette,
    required this.width,
    required this.onDismissAll,
    required this.onPop,
    this.onPushCreateSubtask,
    this.onPushSubtask,
    this.detailRefreshToken = 0,
  });

  final List<AsanaDetailSelection> stack;
  final int detailRefreshToken;
  final AsanaLandingPalette palette;
  final double width;
  final VoidCallback onDismissAll;
  final VoidCallback onPop;
  final void Function(String parentTaskId)? onPushCreateSubtask;
  final void Function(String subtaskId)? onPushSubtask;

  @override
  State<AsanaDetailSlidePanel> createState() => _AsanaDetailSlidePanelState();
}

class _AsanaDetailSlidePanelState extends State<AsanaDetailSlidePanel> {
  Future<void> _handleClose() async {
    if (widget.stack.length > 1) {
      widget.onPop();
    } else {
      widget.onDismissAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.stack.isEmpty) return const SizedBox.shrink();

    final current = widget.stack.last;
    final chrome = AsanaSlideChrome(widget.palette);

    return Material(
      elevation: 8,
      shadowColor: Colors.black26,
      color: chrome.body,
      child: SizedBox(
        width: widget.width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Material(
              color: chrome.header,
              elevation: 0,
              child: SafeArea(
                bottom: false,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    icon: Icon(
                      widget.stack.length > 1
                          ? Icons.arrow_back
                          : Icons.close,
                      color: chrome.onHeader,
                    ),
                    tooltip: widget.stack.length > 1 ? 'Back' : 'Close',
                    onPressed: _handleClose,
                  ),
                ),
              ),
            ),
            Divider(height: 1, color: chrome.footerBorder),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) {
                  return SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(1, 0),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  );
                },
                child: AsanaDetailPanelHost(
                  key: ValueKey(_hostKey(current)),
                  selection: current,
                  palette: widget.palette,
                  onClose: _handleClose,
                  onPop: widget.onPop,
                  onPushCreateSubtask: widget.onPushCreateSubtask,
                  onPushSubtask: widget.onPushSubtask,
                  detailRefreshToken: widget.detailRefreshToken,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _hostKey(AsanaDetailSelection s) => switch (s) {
        AsanaTaskDetailSelection(:final taskId) => 'task:$taskId',
        AsanaSubtaskDetailSelection(:final subtaskId) => 'sub:$subtaskId',
        AsanaProjectDetailSelection(:final projectId) => 'proj:$projectId',
        AsanaCreateSubtaskDetailSelection(:final parentTaskId) =>
          'create-sub:$parentTaskId',
        AsanaCreateTaskDetailSelection() => 'create:task',
        AsanaCreateProjectDetailSelection() => 'create:project',
      };
}
