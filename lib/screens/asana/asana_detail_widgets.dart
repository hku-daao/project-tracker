import 'package:flutter/material.dart';
import 'asana_theme.dart';
import 'asana_value_chips.dart';

/// Section label (Inter, secondary).
TextStyle asanaDetailLabelStyle(BuildContext context) {
  return asanaTextStyle(
    Theme.of(context).textTheme.bodySmall,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: kAsanaTextSecondary,
    height: 1.3,
  )!;
}

/// Body value in slide detail (14px Inter).
TextStyle asanaDetailValueStyle(BuildContext context, {FontWeight? weight}) {
  return asanaTextStyle(
    Theme.of(context).textTheme.bodyMedium,
    fontSize: 14,
    fontWeight: weight ?? FontWeight.w400,
    color: kAsanaTextPrimary,
    height: 1.4,
  )!;
}

/// Large bold title at top of slide (task / sub-task / project name only).
TextStyle asanaDetailTitleStyle(BuildContext context) {
  return asanaTextStyle(
    Theme.of(context).textTheme.titleLarge,
    fontSize: 22,
    fontWeight: FontWeight.w700,
    color: kAsanaTextPrimary,
    height: 1.25,
  )!;
}

/// Multiline fields (description, comments).
TextStyle asanaDetailMultilineValueStyle(BuildContext context) {
  return asanaDetailValueStyle(context);
}

/// First column width for 2-column rows (25% wider than original 120px).
const double kAsanaDetailLabelColumnWidth = 150;

/// Label and value on one row (invisible 2-column table).
class AsanaDetailTwoColumnRow extends StatelessWidget {
  const AsanaDetailTwoColumnRow({
    super.key,
    required this.label,
    required this.child,
    this.labelWidth = kAsanaDetailLabelColumnWidth,
    this.bottomPadding = 10,
  });

  final String label;
  final Widget child;
  final double labelWidth;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: labelWidth,
            child: Text(label, style: asanaDetailLabelStyle(context)),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class AsanaDetailLabelValue extends StatelessWidget {
  const AsanaDetailLabelValue({
    super.key,
    required this.label,
    required this.child,
    this.gap = 4,
  });

  final String label;
  final Widget child;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: asanaDetailLabelStyle(context)),
          SizedBox(height: gap),
          child,
        ],
      ),
    );
  }
}

class AsanaDetailPlainValue extends StatelessWidget {
  const AsanaDetailPlainValue({
    super.key,
    required this.text,
    this.maxLines,
    this.completed = false,
  });

  final String text;
  final int? maxLines;
  final bool completed;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: asanaDetailValueStyle(context).copyWith(
        color: completed ? Colors.black38 : kAsanaTextPrimary,
      ),
      maxLines: maxLines,
      overflow: maxLines != null ? TextOverflow.ellipsis : null,
    );
  }
}

/// Text field border only when [canEdit] and pointer is hovering.
class AsanaHoverTextField extends StatefulWidget {
  const AsanaHoverTextField({
    super.key,
    required this.controller,
    required this.canEdit,
    this.maxLines = 1,
    this.minLines = 1,
    this.style,
    this.readOnly = false,
  });

  final TextEditingController controller;
  final bool canEdit;
  final int maxLines;
  final int minLines;
  final TextStyle? style;
  final bool readOnly;

  @override
  State<AsanaHoverTextField> createState() => _AsanaHoverTextFieldState();
}

class _AsanaHoverTextFieldState extends State<AsanaHoverTextField> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final showBorder = widget.canEdit && _hovering && !widget.readOnly;
    final baseStyle = widget.style ??
        (widget.maxLines > 1
            ? asanaDetailMultilineValueStyle(context)
            : asanaDetailValueStyle(context));

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          border: showBorder
              ? Border.all(color: const Color(0xFFB0BEC5))
              : Border.all(color: Colors.transparent),
          borderRadius: BorderRadius.circular(4),
        ),
        padding: EdgeInsets.symmetric(
          horizontal: showBorder ? 8 : 0,
          vertical: showBorder ? 6 : 2,
        ),
        child: TextField(
          controller: widget.controller,
          readOnly: widget.readOnly || !widget.canEdit,
          maxLines: widget.maxLines,
          minLines: widget.minLines,
          style: baseStyle,
          scrollPadding: EdgeInsets.zero,
          decoration: const InputDecoration(
            isDense: true,
            border: InputBorder.none,
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ),
    );
  }
}

/// Tappable value row; border on hover when [canEdit].
class AsanaHoverTapValue extends StatefulWidget {
  const AsanaHoverTapValue({
    super.key,
    required this.value,
    required this.canEdit,
    this.onTap,
    this.emptyPlaceholder = '',
  });

  final String value;
  final bool canEdit;
  final VoidCallback? onTap;
  final String emptyPlaceholder;

  @override
  State<AsanaHoverTapValue> createState() => _AsanaHoverTapValueState();
}

class _AsanaHoverTapValueState extends State<AsanaHoverTapValue> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final showBorder = widget.canEdit && _hovering;
    final display = widget.value.trim().isEmpty
        ? widget.emptyPlaceholder
        : widget.value.trim();

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.canEdit ? widget.onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            border: showBorder
                ? Border.all(color: const Color(0xFFB0BEC5))
                : Border.all(color: Colors.transparent),
            borderRadius: BorderRadius.circular(4),
          ),
          padding: EdgeInsets.symmetric(
            horizontal: showBorder ? 8 : 0,
            vertical: showBorder ? 6 : 2,
          ),
          child: Text(
            display,
            style: asanaDetailValueStyle(context),
          ),
        ),
      ),
    );
  }
}

/// Status pill for slide detail rows (matches table chip size).
class AsanaDetailStatusPill extends StatelessWidget {
  const AsanaDetailStatusPill({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: AsanaTableCellChip(child: AsanaStatusChip(status: status)),
    );
  }
}

/// Section title with circular [+] beside the label.
class AsanaDetailSectionHeader extends StatelessWidget {
  const AsanaDetailSectionHeader({
    super.key,
    required this.title,
    this.showAddButton = false,
    this.onAdd,
    this.addEnabled = true,
    this.addTooltip = 'Add',
    this.bottomPadding = 8,
  });

  final String title;
  final bool showAddButton;
  final VoidCallback? onAdd;
  final bool addEnabled;
  final String addTooltip;
  final double bottomPadding;

  static const double _addButtonSize = 24;

  @override
  Widget build(BuildContext context) {
    final canPress = addEnabled && onAdd != null;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: Row(
        children: [
          Text(title, style: asanaDetailLabelStyle(context)),
          if (showAddButton) ...[
            const SizedBox(width: 8),
            Tooltip(
              message: addTooltip,
              child: Material(
                color: canPress
                    ? const Color(0xFFECEFF1)
                    : const Color(0xFFF5F6F7),
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: canPress ? onAdd : null,
                  customBorder: const CircleBorder(),
                  child: SizedBox(
                    width: _addButtonSize,
                    height: _addButtonSize,
                    child: Center(
                      child: Text(
                        '+',
                        style: asanaTextStyle(
                          Theme.of(context).textTheme.bodyLarge,
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                          color: canPress
                              ? kAsanaTextPrimary
                              : kAsanaTextSecondary,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Slide task detail bottom action bar button styles.
class AsanaTaskDetailActionStyles {
  AsanaTaskDetailActionStyles._();

  static const Color successGreen = Color(0xFF298A00);
  static const Color returnBlue = Color(0xFF0B0094);

  static const EdgeInsets _padding =
      EdgeInsets.symmetric(horizontal: 20, vertical: 12);

  static ButtonStyle updateFilled(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FilledButton.styleFrom(
      backgroundColor: cs.primary,
      foregroundColor: cs.onPrimary,
      padding: _padding,
    );
  }

  static ButtonStyle successFilled() {
    return FilledButton.styleFrom(
      backgroundColor: successGreen,
      foregroundColor: Colors.white,
      padding: _padding,
    );
  }

  static ButtonStyle returnFilled() {
    return FilledButton.styleFrom(
      backgroundColor: returnBlue,
      foregroundColor: Colors.white,
      padding: _padding,
    );
  }

  static ButtonStyle submitFilled(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FilledButton.styleFrom(
      backgroundColor: cs.secondaryContainer,
      foregroundColor: cs.onSecondaryContainer,
      padding: _padding,
    );
  }

  static ButtonStyle undoOutlined(BuildContext context) {
    return OutlinedButton.styleFrom(
      foregroundColor: kAsanaTextPrimary,
      side: BorderSide(color: Colors.grey.shade400),
      padding: _padding,
    );
  }

  static ButtonStyle deleteOutlined() {
    return OutlinedButton.styleFrom(
      foregroundColor: Colors.red.shade800,
      side: BorderSide(color: Colors.red.shade300),
      padding: _padding,
    );
  }
}

/// Submission pill for slide detail rows (matches table chip size).
class AsanaDetailSubmissionPill extends StatelessWidget {
  const AsanaDetailSubmissionPill({super.key, required this.submission});

  final String? submission;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: AsanaTableCellChip(
        child: AsanaSubmissionChip(submission: submission),
      ),
    );
  }
}
