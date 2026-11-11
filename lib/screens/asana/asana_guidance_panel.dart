import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../priority.dart';
import '../asana_landing_screen.dart';
import 'asana_filter_widgets.dart';
import 'asana_status_aura.dart';
import 'asana_theme.dart';
import 'asana_value_chips.dart';

/// How-to guide for Project Tracker, drawn with live widgets instead of screenshots.
class AsanaGuidancePanel extends StatefulWidget {
  const AsanaGuidancePanel({super.key, required this.palette});

  final AsanaLandingPalette palette;

  @override
  State<AsanaGuidancePanel> createState() => _AsanaGuidancePanelState();
}

class _AsanaGuidancePanelState extends State<AsanaGuidancePanel> {
  final _scroll = ScrollController();
  final _kIntro = GlobalKey();
  final _kTask = GlobalKey();
  final _kSubtask = GlobalKey();
  final _kProject = GlobalKey();
  final _kSubproject = GlobalKey();
  final _kNest = GlobalKey();
  final _kRecurring = GlobalKey();
  final _kMilestones = GlobalKey();
  final _kViews = GlobalKey();
  final _kMap = GlobalKey();
  final _kCheck = GlobalKey();
  final _kMove = GlobalKey();
  final _kMake = GlobalKey();
  final _kDetach = GlobalKey();
  final _kClone = GlobalKey();
  final _kPriority = GlobalKey();
  final _kStatus = GlobalKey();
  final _kCommence = GlobalKey();
  final _kComplexity = GlobalKey();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _jumpTo(GlobalKey key) async {
    final target = key.currentContext;
    if (target == null) return;
    await Scrollable.ensureVisible(
      target,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      alignment: 0.04,
    );
  }

  Widget _section({
    required GlobalKey key,
    required AsanaLandingPalette palette,
    required String title,
    required String body,
    required Widget figure,
    String? letter,
  }) {
    return KeyedSubtree(
      key: key,
      child: _GuideSectionCard(
        palette: palette,
        letter: letter,
        title: title,
        body: body,
        figure: figure,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = widget.palette;
    return SelectionArea(
      child: AsanaStatusAuraClock(
      child: ColoredBox(
        color: palette.panelBackground,
        child: AsanaPanelListSurface(
          palette: palette,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 720;
              return SingleChildScrollView(
                controller: _scroll,
                padding: EdgeInsets.fromLTRB(wide ? 36 : 20, 28, wide ? 36 : 20, 48),
                child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 880),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'How to use Project Tracker',
                        style: asanaTextStyle(
                          theme.textTheme.headlineSmall,
                          fontSize: wide ? 28 : 24,
                          fontWeight: FontWeight.w700,
                          color: kAsanaTextPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Use the buttons below to jump to a section. The drawings reuse the same labels and colours as the live app.',
                        style: asanaTextStyle(
                          theme.textTheme.bodyLarge,
                          fontSize: 15,
                          height: 1.45,
                          color: kAsanaTextSecondary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _GuideJumpBar(
                        items: [
                          ('Introduction', _kIntro),
                          ('Task', _kTask),
                          ('Sub-task', _kSubtask),
                          ('Project', _kProject),
                          ('Sub-project', _kSubproject),
                          ('How they nest', _kNest),
                          ('Recurring', _kRecurring),
                          ('Milestones', _kMilestones),
                          ('Views', _kViews),
                          ('Map', _kMap),
                          ('Check and uncheck', _kCheck),
                          ('Move', _kMove),
                          ('Make', _kMake),
                          ('Detach', _kDetach),
                          ('Clone', _kClone),
                          ('Priority', _kPriority),
                          ('Status', _kStatus),
                          ('Commence', _kCommence),
                          ('Complexity', _kComplexity),
                        ],
                        onJump: _jumpTo,
                      ),
                      const SizedBox(height: 20),
                      _section(
                        key: _kIntro,
                        palette: palette,
                        title: 'Introduction',
                        body:
                            'Proper use of Project Tracker builds a four-level tree. A project holds sub-projects, each sub-project holds tasks, and each task holds sub-tasks. A task stays Incomplete while any sub-task is still open. Every sub-task is Completed before that task can be Submitted. Completing a task completes its sub-tasks.',
                        figure: _IntroductionFigure(palette: palette),
                      ),
                      const SizedBox(height: 16),
                      _section(
                        key: _kTask,
                        palette: palette,
                        letter: 'T',
                        title: 'Task',
                        body:
                            'A task is a sizeable piece of work that one person can finish in about 1 to 3 working days. Give it a clear name, a PIC, and a due date. Standard priority assumes 3 working days; URGENT assumes 1 working day.',
                        figure: _TaskFigure(palette: palette),
                      ),
                      const SizedBox(height: 16),
                      _section(
                        key: _kSubtask,
                        palette: palette,
                        letter: 'ST',
                        title: 'Sub-task',
                        body:
                            'A sub-task is a smaller step that belongs to a task. Use it when the task is easier to finish if it is broken into named pieces, each with its own PIC or due date. A sub-task always sits under a task, never by itself.',
                        figure: _SubtaskFigure(palette: palette),
                      ),
                      const SizedBox(height: 16),
                      _section(
                        key: _kProject,
                        palette: palette,
                        letter: 'P',
                        title: 'Project',
                        body:
                            'A project is a container for related work. It has a creator, PIC, assignees, dates, and a status. Tasks can sit directly under a project, or under a sub-project inside it. Optional milestones measure how far the project has come.',
                        figure: _ProjectFigure(palette: palette),
                      ),
                      const SizedBox(height: 16),
                      _section(
                        key: _kSubproject,
                        palette: palette,
                        letter: 'SP',
                        title: 'Sub-project',
                        body:
                            'A sub-project groups tasks inside a project when the project has more than one stream of work. A task linked to a sub-project is not treated as a direct child of the project. On the map, if any sub-project is shown in the tree, every task sits two levels below the project.',
                        figure: _SubprojectFigure(palette: palette),
                      ),
                      const SizedBox(height: 16),
                      _section(
                        key: _kNest,
                        palette: palette,
                        title: 'How they nest',
                        body:
                            'Work can nest in a few ways. T-ST is a task with sub-tasks and no project. P-T is a project with tasks sitting directly under it. P-SP-T is a project that groups tasks under a sub-project. The last two add sub-tasks under those tasks.',
                        figure: _HierarchyCompare(palette: palette),
                      ),
                      const SizedBox(height: 16),
                      _section(
                        key: _kRecurring,
                        palette: palette,
                        title: 'Recurring',
                        body:
                            'On a create slide, Make recurring turns one form into several separate items. Choose Daily, Weekly, Monthly, or Yearly, then end by a date or after a count. Daily can be every day, or Monday to Friday only. Each occurrence is its own task or sub-task after you click Create. They are not kept as a linked series. Recurring is hidden when Commence is To be commenced, because those items do not have start and due dates yet.',
                        figure: _RecurringFigure(palette: palette),
                      ),
                      const SizedBox(height: 16),
                      _section(
                        key: _kMilestones,
                        palette: palette,
                        title: 'Milestones',
                        body:
                            'Milestones are optional project steps. Each step has a description and a percent of the whole project. The percents must add up to 100%. When a step is Achieved, its percent is added to the project progress shown under the project name and on the project slide. If milestones are on, the project can be marked Completed only when every step is achieved. A project without milestones shows 100% if it is Completed, otherwise 0%.',
                        figure: _MilestoneFigure(palette: palette),
                      ),
                      const SizedBox(height: 16),
                      _section(
                        key: _kViews,
                        palette: palette,
                        title: 'Views',
                        body:
                            'The left panel opens each view. Work is a heading, not a page. Tasks and All Works sit under it. List and Map both run from the project down to the sub-task. The notes beside the panel say what each view is for.',
                        figure: _ViewsFigure(palette: palette),
                      ),
                      const SizedBox(height: 16),
                      _section(
                        key: _kMap,
                        palette: palette,
                        title: 'Map',
                        body:
                            'Map draws the same hierarchy as pictures: project, then sub-project if there is one, then task, then sub-task. On a phone the tree goes left to right; on a wide screen it goes top to bottom. Each block has a P, SP, T, or ST label at the top left. A task or sub-task also has a word at the top right: Incomplete, Due today, Overdue, Submitted, or Completed. Completed glows in several colours with rising particles. Submitted has a steady amber pulse. Incomplete, including Due today and Overdue, has a low red-grey glow. Filters at the top choose which blocks appear. Click a block to open its slide.',
                        figure: _MapFigure(palette: palette),
                      ),
                      const SizedBox(height: 16),
                      _section(
                        key: _kCheck,
                        palette: palette,
                        title: 'Check and uncheck',
                        body:
                            'This app offers actions that work on items, such as move, make, detach, and clone. The sections below introduce each one. To use these features, select the work item in List or Map. With nothing selected, the buttons stay hidden. The buttons that fit the selected item appear at the top. Uncheck the item if you picked the wrong one.\n\nOn a computer, point at the List row, or at the bottom-left corner of a Map block, until the box appears, then click it to check. Click the box again to uncheck. On a phone, press the row or block and hold still for 0.2 seconds to check it. The check appears while you are still holding. Press the same spot again for 0.2 seconds to uncheck. A press that scrolls does not check or uncheck. A short tap still opens the item. On the phone Map, when a block is checked, tap the visible checkbox to uncheck it.',
                        figure: _CheckFigure(palette: palette),
                      ),
                      const SizedBox(height: 16),
                      _section(
                        key: _kMove,
                        palette: palette,
                        title: 'Move',
                        body:
                            'Move keeps the item and puts it under a different parent. You need to be the PIC or the creator. Check the item first, then press Move Task, Move Subproject, or Move Subtask, and choose the new parent. Cancel leaves this step. Each picture is one button, before and after.',
                        figure: _MoveExamples(palette: palette),
                      ),
                      const SizedBox(height: 16),
                      _section(
                        key: _kMake,
                        palette: palette,
                        title: 'Make',
                        body:
                            'Make turns the selected item into a child of another item. You need to be the PIC or the creator. Check the item first.\n\nMake Subproject turns a project into a sub-project under another project. That project cannot already have milestones or sub-projects. Its tasks move with it. After Make Subproject, check the project that will be the parent.\n\nMake Subtask turns a task into a sub-task under another task. That task cannot already have sub-tasks. After Make Subtask, check the task that will be the parent.\n\nCancel leaves this step. Each picture is one button, before and after.',
                        figure: _MakeExamples(palette: palette),
                      ),
                      const SizedBox(height: 16),
                      _section(
                        key: _kDetach,
                        palette: palette,
                        title: 'Detach',
                        body:
                            'Detach lifts the item out of its parent so it stands on its own. You need to be the PIC or the creator. Check the item first, then press Detach Project or Detach Task. Detach Project turns a sub-project into a project. Detach Task turns a sub-task into a task. Each picture is one button, before and after.',
                        figure: _DetachExamples(palette: palette),
                      ),
                      const SizedBox(height: 16),
                      _section(
                        key: _kClone,
                        palette: palette,
                        title: 'Clone',
                        body:
                            'Clone copies a task or sub-task when you are its PIC or its creator. The original stays. The copy is a new item, and its name ends with " (cloned)". Check a task, a sub-task, or both when you are the PIC or the creator of each one, then press Clone. Each picture is one case of the Clone button, before and after.',
                        figure: _CloneExamples(palette: palette),
                      ),
                      const SizedBox(height: 16),
                      _section(
                        key: _kPriority,
                        palette: palette,
                        title: 'Priority',
                        body:
                            'Priority sets the assumed working-day target. Standard is the default and assumes 3 working days after the start date. URGENT assumes 1 working day. If the due date is later than that span, the slide asks for a Reason. Recurring items use the same idea: Standard defaults to 4 inclusive working days, URGENT to 2. Priority is not the same as complexity — urgent work can still be simple.',
                        figure: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            AsanaPriorityChip(priority: priorityStandard),
                            AsanaPriorityChip(priority: priorityUrgent),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _section(
                        key: _kStatus,
                        palette: palette,
                        title: 'Status',
                        body:
                            'Status is the workflow state. You do not type Completed into this field; it changes when work is accepted through the workflow. Paused appears when the item, or its parent project or sub-project, is paused. Deleted items leave the normal active lists.\n\nTasks and sub-tasks use Incomplete, Completed, Paused, and Deleted. Projects and sub-projects use Not started, In progress, Completed, Paused, and Deleted.\n\nOn the map, a task or sub-task shows a word in the top-right corner. Incomplete, Due today, and Overdue are unfinished. Due today and Overdue come from the due date. Submitted comes from the submission. Completed, Paused, and other states use the status word itself. Projects and sub-projects do not use this corner.',
                        figure: const _StatusFigure(),
                      ),
                      const SizedBox(height: 16),
                      _section(
                        key: _kCommence,
                        palette: palette,
                        title: 'Commence',
                        body:
                            'Commence records whether the task or sub-task has started. Commenced is the default: the work has started or is ready to work on, and start and due dates follow the normal priority policy. To be commenced means it has not started yet. Start and due dates can be left blank, and you can add a note. Make recurring is hidden for To be commenced items because those items do not have dates yet.',
                        figure: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: const [
                            AsanaCommencementChip(status: 'Commenced'),
                            AsanaCommencementChip(
                              status: 'To be commenced',
                              preserveFullLabel: true,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _section(
                        key: _kComplexity,
                        palette: palette,
                        title: 'Complexity',
                        body:
                            'Complexity is how difficult the work is to complete well, not how urgent or important it is. Choose one value when you create a task or sub-task.\n\nLow: a clear goal and familiar steps, few dependencies, and little coordination.\nMedium: several steps, some analysis, or some coordination; moderate follow-up may be needed.\nHigh: significant uncertainty, risk, or many dependencies; substantial coordination, decisions, or extended effort.\n\nPerformance view groups completed work by these three values.',
                        figure: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: const [
                            _GuidePlainChip(
                              label: 'Low',
                              bg: Color(0xFFE8F5E9),
                              fg: Color(0xFF2E7D32),
                            ),
                            _GuidePlainChip(
                              label: 'Medium',
                              bg: Color(0xFFE3F2FD),
                              fg: Color(0xFF1565C0),
                            ),
                            _GuidePlainChip(
                              label: 'High',
                              bg: Color(0xFFFFEBEE),
                              fg: Color(0xFFC62828),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
            },
          ),
        ),
      ),
      ),
    );
  }
}


class _GuideJumpBar extends StatefulWidget {
  const _GuideJumpBar({required this.items, required this.onJump});

  final List<(String label, GlobalKey key)> items;
  final Future<void> Function(GlobalKey key) onJump;

  @override
  State<_GuideJumpBar> createState() => _GuideJumpBarState();
}

class _GuideJumpBarState extends State<_GuideJumpBar> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _shift(int direction) {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    final distance = MediaQuery.sizeOf(context).width / 5;
    final target = (_controller.offset + direction * distance).clamp(
      0.0,
      position.maxScrollExtent,
    );
    _controller.animateTo(
      target,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final chipStyle = OutlinedButton.styleFrom(
      foregroundColor: kAsanaTextPrimary,
      side: const BorderSide(color: Color(0xFFD0D3D4)),
      backgroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      minimumSize: const Size(0, 36),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
    final arrowStyle = OutlinedButton.styleFrom(
      foregroundColor: kAsanaTextPrimary,
      side: const BorderSide(color: Color(0xFFD0D3D4)),
      backgroundColor: Colors.white,
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.standard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
    Widget arrow(IconData icon, int direction) {
      return SizedBox(
        width: 36,
        child: OutlinedButton(
          onPressed: () => _shift(direction),
          style: arrowStyle,
          child: Icon(icon, size: 22),
        ),
      );
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          arrow(Icons.chevron_left, -1),
          const SizedBox(width: 8),
          Expanded(
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(
                context,
              ).copyWith(scrollbars: false),
              child: SingleChildScrollView(
                controller: _controller,
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.hardEdge,
                child: Row(
                  children: [
                    for (var i = 0; i < widget.items.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: () => widget.onJump(widget.items[i].$2),
                        style: chipStyle,
                        child: Text(
                          widget.items[i].$1,
                          style: asanaTextStyle(
                            Theme.of(context).textTheme.labelLarge,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: kAsanaTextPrimary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          arrow(Icons.chevron_right, 1),
        ],
      ),
    );
  }
}


class _GuidePlainChip extends StatelessWidget {
  const _GuidePlainChip({
    required this.label,
    required this.bg,
    required this.fg,
  });

  final String label;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: asanaTextStyle(
          Theme.of(context).textTheme.bodyMedium,
          fontSize: kAsanaTableChipFontSize,
          fontWeight: FontWeight.w600,
          color: fg,
          height: 1.2,
        ),
      ),
    );
  }
}

class _GuideSectionCard extends StatelessWidget {
  const _GuideSectionCard({
    required this.palette,
    required this.title,
    required this.body,
    required this.figure,
    this.letter,
  });

  final AsanaLandingPalette palette;
  final String? letter;
  final String title;
  final String body;
  final Widget figure;

  @override
  Widget build(BuildContext context) {
    final titleStyle = asanaTextStyle(
      Theme.of(context).textTheme.titleMedium,
      fontSize: 18,
      fontWeight: FontWeight.w700,
      color: kAsanaTextPrimary,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.content,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE6E7E8)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (letter != null)
              Row(
                children: [
                  _GuideTypeLetter(palette: palette, letter: letter!),
                  const SizedBox(width: 10),
                  Text(title, style: titleStyle),
                ],
              )
            else
              Text(title, style: titleStyle),
            const SizedBox(height: 10),
            Text(
              body,
              style: asanaTextStyle(
                Theme.of(context).textTheme.bodyMedium,
                fontSize: 14.5,
                height: 1.45,
                color: kAsanaTextPrimary,
              ),
            ),
            const SizedBox(height: 16),
            figure,
          ],
        ),
        ),
      ),
    );
  }
}

/// Accent badge used for the map’s top-left letter.
class _GuideCornerBadge extends StatelessWidget {
  const _GuideCornerBadge({
    required this.palette,
    required this.tooltip,
    required this.child,
    this.width = 24,
    this.fill,
  });

  final AsanaLandingPalette palette;
  final String tooltip;
  final Widget child;
  final double width;
  final Color? fill;

  @override
  Widget build(BuildContext context) {
    final badge = fill ?? palette.accent;
    return Tooltip(
      message: tooltip,
      child: Container(
        width: width,
        height: 24,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: badge,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: fill == null ? palette.banner : badge),
        ),
        child: child,
      ),
    );
  }
}

Color? _guideLevelBadgeColor(AsanaLandingPalette palette, String letter) {
  final badges = palette.levelBadges;
  if (badges == null) return null;
  return badges.forLetter(letter);
}

Color _guideBadgeInk(AsanaLandingPalette palette, {Color? fill}) {
  if (fill == null && palette.id == 'Classic') return Colors.white;
  final accent = fill ?? palette.accent;
  final accentLum = accent.computeLuminance();
  final inkLum = palette.onBanner.computeLuminance();
  if ((accentLum - inkLum).abs() < 0.25) {
    return accentLum > 0.45 ? const Color(0xFF1A1A1A) : Colors.white;
  }
  return palette.onBanner;
}

String _guideLetterName(String letter) {
  switch (letter) {
    case 'P':
      return 'Project';
    case 'SP':
      return 'Sub-project';
    case 'T':
      return 'Task';
    case 'ST':
      return 'Sub-task';
    default:
      return letter;
  }
}

class _GuideTypeLetter extends StatelessWidget {
  const _GuideTypeLetter({required this.palette, required this.letter});

  final AsanaLandingPalette palette;
  final String letter;

  @override
  Widget build(BuildContext context) {
    final twoLetter = letter.trim().length > 1;
    final fill = _guideLevelBadgeColor(palette, letter);
    return _GuideCornerBadge(
      palette: palette,
      tooltip: _guideLetterName(letter),
      width: twoLetter ? 30 : 24,
      fill: fill,
      child: Text(
        letter,
        style: TextStyle(
          fontSize: twoLetter ? 10 : 12,
          fontWeight: FontWeight.w700,
          color: _guideBadgeInk(palette, fill: fill),
          height: 1,
        ),
      ),
    );
  }
}

/// Word label the map draws at the top right of a task or sub-task block.
class _GuideStatusLabel extends StatelessWidget {
  const _GuideStatusLabel({required this.label});

  final String label;

  static const _fills = <String, Color>{
    'Completed': Color(0xFF2E9B57),
    'Submitted': Color(0xFF1565C0),
    'Due today': Color(0xFF7B5EA7),
    'Overdue': Color(0xFFD32F2F),
    'Incomplete': Color(0xFFE09A2B),
  };

  @override
  Widget build(BuildContext context) {
    final fill = _fills[label] ?? const Color(0xFF607D8B);
    final ink = fill.computeLuminance() > 0.45
        ? const Color(0xFF1A1A1A)
        : Colors.white;
    return Tooltip(
      message: label,
      child: Container(
        height: 24,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: fill),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: ink,
            height: 1,
          ),
        ),
      ),
    );
  }
}

class _StatusFigure extends StatelessWidget {
  const _StatusFigure();

  static const _fieldStatuses = [
    'Incomplete',
    'Completed',
    'Not started',
    'In progress',
    'Paused',
    'Deleted',
  ];

  static const _mapCorners = [
    'Incomplete',
    'Due today',
    'Overdue',
    'Submitted',
    'Completed',
  ];

  @override
  Widget build(BuildContext context) {
    final caption = asanaTextStyle(
      Theme.of(context).textTheme.labelLarge,
      fontSize: 13,
      fontWeight: FontWeight.w700,
      color: kAsanaTextPrimary,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Status field', style: caption),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final status in _fieldStatuses)
              AsanaStatusChip(status: status),
          ],
        ),
        const SizedBox(height: 14),
        Text('Map corner', style: caption),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final label in _mapCorners) _GuideStatusLabel(label: label),
          ],
        ),
      ],
    );
  }
}

class _GuideBlock extends StatelessWidget {
  const _GuideBlock({
    required this.palette,
    required this.letter,
    required this.name,
    required this.detail,
    this.badge,
    this.checked = false,
    this.width = 158,
  });

  final AsanaLandingPalette palette;
  final String letter;
  final String name;
  final String detail;
  final String? badge;
  final bool checked;
  final double width;

  @override
  Widget build(BuildContext context) {
    final (:bg, :fg, :border) = _blockColors(palette, letter);
    final auraKind = letter == 'T' || letter == 'ST'
        ? asanaStatusAuraKind(badge ?? '')
        : null;
    final auraPad = auraKind == null ? 0.0 : asanaStatusAuraPadFor(auraKind);
    return SizedBox(
      width: width,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (auraKind != null)
            Positioned(
              left: -auraPad,
              top: -auraPad,
              right: -auraPad,
              bottom: -auraPad,
              child: IgnorePointer(
                child: AsanaStatusAura(kind: auraKind, pad: auraPad),
              ),
            ),
          Container(
            width: width,
            padding: const EdgeInsets.fromLTRB(10, 14, 10, 10),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: border),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 4,
                  offset: Offset(1, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                Text(
                  name,
                  textAlign: TextAlign.center,
                  style: asanaTextStyle(
                    Theme.of(context).textTheme.labelLarge,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: fg,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  detail,
                  textAlign: TextAlign.center,
                  style: asanaTextStyle(
                    Theme.of(context).textTheme.labelSmall,
                    fontSize: 11,
                    color: fg.withValues(alpha: 0.78),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: -14,
            left: -6,
            child: _GuideTypeLetter(palette: palette, letter: letter),
          ),
          if (badge != null)
            Positioned(
              top: -14,
              right: -6,
              child: _GuideStatusLabel(label: badge!),
            ),
          if (checked)
            const Positioned(
              left: -6,
              bottom: -10,
              child: _GuideCheckMark(),
            ),
        ],
      ),
    );
  }
}

({Color bg, Color fg, Color border}) _blockColors(
  AsanaLandingPalette palette,
  String letter,
) {
  final fills = palette.levelFills;
  final badges = palette.levelBadges;
  if (fills != null) {
    final fill = fills.forLetter(letter);
    final badge = badges?.forLetter(letter) ?? fill;
    final ink = asanaInkIfDark(fill) ?? kAsanaTextPrimary;
    return (bg: fill, fg: ink, border: badge);
  }
  final surface = palette.listSurface;
  final accent = palette.accent;
  final dark = palette.darkChrome;
  Color wash(double alpha) =>
      Color.alphaBlend(accent.withValues(alpha: alpha), surface);
  switch (letter) {
    case 'P':
      return (bg: accent, fg: Colors.white, border: accent);
    case 'SP':
      return (
        bg: wash(dark ? 0.78 : 0.70),
        fg: Colors.white,
        border: accent.withValues(alpha: 0.88),
      );
    case 'T':
      return (
        bg: wash(dark ? 0.38 : 0.32),
        fg: kAsanaTextPrimary,
        border: accent.withValues(alpha: 0.52),
      );
    default:
      return (
        bg: wash(dark ? 0.18 : 0.12),
        fg: kAsanaTextPrimary,
        border: accent.withValues(alpha: 0.36),
      );
  }
}

class _IntroductionFigure extends StatelessWidget {
  const _IntroductionFigure({required this.palette});

  final AsanaLandingPalette palette;

  @override
  Widget build(BuildContext context) {
    Widget block(String letter, String name, String detail, {String? badge}) {
      return _GuideBlock(
        palette: palette,
        letter: letter,
        name: name,
        detail: detail,
        badge: badge,
        width: letter == 'P' ? 168 : 148,
      );
    }

    Widget task(String name, String badge, List<Widget> subtasks) {
      return _GuideElbowTree(
        palette: palette,
        parent: block('T', name, 'Task', badge: badge),
        children: subtasks,
      );
    }

    Widget subtask(String name, String badge) {
      return block('ST', name, 'Sub-task', badge: badge);
    }

    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.all(asanaStatusCompletedAuraPad),
        child: _GuideElbowTree(
          palette: palette,
          parent: block('P', 'Orientation week', 'Project'),
          children: [
            _GuideElbowTree(
              palette: palette,
              parent: block('SP', 'Student events', 'Sub-project'),
              children: [
                task('Campus tour', 'Incomplete', [
                  subtask('Print maps', 'Incomplete'),
                  subtask('Book a room', 'Submitted'),
                ]),
              ],
            ),
            _GuideElbowTree(
              palette: palette,
              parent: block('SP', 'Closing', 'Sub-project'),
              children: [
                task('Thank-you notes', 'Submitted', [
                  subtask('Draft note', 'Completed'),
                  subtask('Send note', 'Completed'),
                ]),
                task('Archive photos', 'Completed', [
                  subtask('Collect files', 'Completed'),
                  subtask('Store album', 'Completed'),
                ]),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskFigure extends StatelessWidget {
  const _TaskFigure({required this.palette});

  final AsanaLandingPalette palette;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(asanaStatusAuraPad),
        child: _GuideBlock(
          palette: palette,
          letter: 'T',
          name: 'Draft the briefing',
          detail: 'Due: in 3 working days',
          badge: 'Incomplete',
        ),
      ),
    );
  }
}

class _SubtaskFigure extends StatelessWidget {
  const _SubtaskFigure({required this.palette});

  final AsanaLandingPalette palette;

  @override
  Widget build(BuildContext context) {
    return _GuideParentChildren(
      palette: palette,
      parent: _GuideBlock(
        palette: palette,
        letter: 'T',
        name: 'Draft the briefing',
        detail: 'Parent task',
        badge: 'Incomplete',
      ),
      children: [
        _GuideBlock(
          palette: palette,
          letter: 'ST',
          name: 'Collect figures',
          detail: 'Due: Day 1',
          badge: 'Due today',
          width: 140,
        ),
        _GuideBlock(
          palette: palette,
          letter: 'ST',
          name: 'Write draft',
          detail: 'Due: Day 3',
          badge: 'Incomplete',
          width: 140,
        ),
      ],
    );
  }
}

class _ProjectFigure extends StatelessWidget {
  const _ProjectFigure({required this.palette});

  final AsanaLandingPalette palette;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _GuideBlock(
          palette: palette,
          letter: 'P',
          name: 'Orientation week',
          detail: 'In progress',
          width: 180,
        ),
        const SizedBox(height: 10),
        const _GuideProgressRow(percent: 40),
      ],
    );
  }
}

class _SubprojectFigure extends StatelessWidget {
  const _SubprojectFigure({required this.palette});

  final AsanaLandingPalette palette;

  @override
  Widget build(BuildContext context) {
    return _GuideParentChildren(
      palette: palette,
      parent: _GuideBlock(
        palette: palette,
        letter: 'P',
        name: 'Orientation week',
        detail: 'Parent project',
        width: 180,
      ),
      children: [
        _GuideBlock(
          palette: palette,
          letter: 'SP',
          name: 'Student events',
          detail: 'One stream',
          width: 150,
        ),
        _GuideBlock(
          palette: palette,
          letter: 'SP',
          name: 'Staff briefings',
          detail: 'Another stream',
          width: 150,
        ),
      ],
    );
  }
}

class _HierarchyCompare extends StatelessWidget {
  const _HierarchyCompare({required this.palette});

  final AsanaLandingPalette palette;

  @override
  Widget build(BuildContext context) {
    final examples = [
      _MiniTree(
        palette: palette,
        caption: 'T-ST',
        note: 'A task with sub-tasks. No project.',
        children: const [
          _MiniTreeNode('T', 'Task'),
          _MiniTreeNode('ST', 'Sub-task'),
        ],
      ),
      _MiniTree(
        palette: palette,
        caption: 'P-T',
        note: 'A project with tasks sitting directly under it.',
        children: const [
          _MiniTreeNode('P', 'Project'),
          _MiniTreeNode('T', 'Task'),
        ],
      ),
      _MiniTree(
        palette: palette,
        caption: 'P-SP-T',
        note: 'A project that groups tasks under a sub-project.',
        children: const [
          _MiniTreeNode('P', 'Project'),
          _MiniTreeNode('SP', 'Sub-project'),
          _MiniTreeNode('T', 'Task'),
        ],
      ),
      _MiniTree(
        palette: palette,
        caption: 'P-T-ST',
        note: 'A project with tasks, and those tasks have sub-tasks.',
        children: const [
          _MiniTreeNode('P', 'Project'),
          _MiniTreeNode('T', 'Task'),
          _MiniTreeNode('ST', 'Sub-task'),
        ],
      ),
      _MiniTree(
        palette: palette,
        caption: 'P-SP-T-ST',
        note: 'Full nest when a sub-project is used.',
        children: const [
          _MiniTreeNode('P', 'Project'),
          _MiniTreeNode('SP', 'Sub-project'),
          _MiniTreeNode('T', 'Task'),
          _MiniTreeNode('ST', 'Sub-task'),
        ],
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final columns = w >= 720 ? 3 : (w >= 480 ? 2 : 1);
        const gap = 16.0;
        final cardW = columns == 1
            ? w
            : (w - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: 12,
          children: [
            for (final tree in examples) SizedBox(width: cardW, child: tree),
          ],
        );
      },
    );
  }
}

class _MiniTreeNode {
  const _MiniTreeNode(this.letter, this.label);

  final String letter;
  final String label;
}

class _MiniTree extends StatelessWidget {
  const _MiniTree({
    required this.palette,
    required this.caption,
    required this.children,
    this.note,
  });

  final AsanaLandingPalette palette;
  final String caption;
  final String? note;
  final List<_MiniTreeNode> children;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.content,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE6E7E8)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              caption,
              style: asanaTextStyle(
                Theme.of(context).textTheme.labelLarge,
                fontWeight: FontWeight.w700,
                color: kAsanaTextPrimary,
              ),
            ),
            if (note != null) ...[
              const SizedBox(height: 4),
              Text(
                note!,
                style: asanaTextStyle(
                  Theme.of(context).textTheme.bodySmall,
                  fontSize: 12,
                  height: 1.35,
                  color: kAsanaTextSecondary,
                ),
              ),
            ],
            const SizedBox(height: 10),
            for (var i = 0; i < children.length; i++) ...[
              Padding(
                padding: EdgeInsets.only(left: i * 22.0),
                child: Row(
                  children: [
                    _GuideTypeLetter(
                      palette: palette,
                      letter: children[i].letter,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      children[i].label,
                      style: asanaTextStyle(
                        Theme.of(context).textTheme.bodyMedium,
                        fontWeight: FontWeight.w600,
                        color: kAsanaTextPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              if (i < children.length - 1)
                Padding(
                  padding: EdgeInsets.only(left: i * 22.0 + 11),
                  child: Container(
                    width: 2,
                    height: 10,
                    color: palette.accent.withValues(alpha: 0.45),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RecurringFigure extends StatelessWidget {
  const _RecurringFigure({required this.palette});

  final AsanaLandingPalette palette;

  @override
  Widget build(BuildContext context) {
    const weekly = [
      'Mon 5 Oct',
      'Mon 12 Oct',
      'Mon 19 Oct',
      'Mon 26 Oct',
      'Mon 2 Nov',
      'Mon 9 Nov',
      'Mon 16 Nov',
      'Mon 23 Nov',
    ];
    const weekdays = [
      'Mon 5 Oct',
      'Tue 6 Oct',
      'Wed 7 Oct',
      'Thu 8 Oct',
      'Fri 9 Oct',
      'Mon 12 Oct',
      'Tue 13 Oct',
      'Wed 14 Oct',
      'Thu 15 Oct',
      'Fri 16 Oct',
    ];
    final weeklyDates = weekly;
    final weekdayDates = weekdays;
    final caption = asanaTextStyle(
      Theme.of(context).textTheme.labelLarge,
      fontSize: 13,
      fontWeight: FontWeight.w700,
      color: kAsanaTextPrimary,
    );
    Widget row(Iterable<String> dates, String letter, String name) {
      return _GuideHScroll(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final date in dates) ...[
              _GuideBlock(
                palette: palette,
                letter: letter,
                name: name,
                detail: date,
                badge: 'Incomplete',
                width: 124,
              ),
              const SizedBox(width: 12),
            ],
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Weekly task', style: caption),
        const SizedBox(height: 8),
        row(weeklyDates, 'T', 'Weekly report'),
        const SizedBox(height: 16),
        Text('Weekday sub-task, Monday to Friday', style: caption),
        const SizedBox(height: 8),
        row(weekdayDates, 'ST', 'Stand-up note'),
      ],
    );
  }
}

class _MilestoneFigure extends StatelessWidget {
  const _MilestoneFigure({required this.palette});

  final AsanaLandingPalette palette;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.content,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFEDEAE9)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Orientation week',
              style: asanaTextStyle(
                Theme.of(context).textTheme.titleSmall,
                fontWeight: FontWeight.w700,
                color: kAsanaTextPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const _GuideProgressRow(percent: 40),
            const SizedBox(height: 14),
            Text(
              'Milestones',
              style: asanaTextStyle(
                Theme.of(context).textTheme.labelLarge,
                fontWeight: FontWeight.w700,
                color: kAsanaTextPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const _GuideMilestoneLine(
              title: 'Confirm venue',
              percent: 40,
              achieved: true,
            ),
            const _GuideMilestoneLine(
              title: 'Send invitations',
              percent: 35,
              achieved: false,
            ),
            const _GuideMilestoneLine(
              title: 'Run the week',
              percent: 25,
              achieved: false,
            ),
          ],
        ),
      ),
    );
  }
}

class _GuideMilestoneLine extends StatelessWidget {
  const _GuideMilestoneLine({
    required this.title,
    required this.percent,
    required this.achieved,
  });

  final String title;
  final int percent;
  final bool achieved;

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width < 600;
    final label = achieved
        ? (mobile ? 'A' : 'Achieved')
        : (mobile ? 'NA' : 'Not Achieved');
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Container(
            height: 22,
            alignment: Alignment.center,
            padding: EdgeInsets.symmetric(horizontal: mobile ? 6 : 8),
            constraints: BoxConstraints(minWidth: mobile ? 28 : 0),
            decoration: BoxDecoration(
              color: achieved
                  ? const Color(0xFFE8F5E9)
                  : const Color(0xFFECEFF1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: mobile ? 10 : 12,
                fontWeight: FontWeight.w700,
                color: achieved
                    ? const Color(0xFF2E7D32)
                    : kAsanaTextSecondary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: asanaTextStyle(
                Theme.of(context).textTheme.bodyMedium,
                fontWeight: FontWeight.w600,
                color: kAsanaTextPrimary,
              ),
            ),
          ),
          Text(
            '$percent%',
            style: asanaTextStyle(
              Theme.of(context).textTheme.labelLarge,
              fontWeight: FontWeight.w700,
              color: kAsanaTextPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _MapFigure extends StatelessWidget {
  const _MapFigure({required this.palette});

  final AsanaLandingPalette palette;

  @override
  Widget build(BuildContext context) {
    final project = _GuideBlock(
      palette: palette,
      letter: 'P',
      name: 'Orientation week',
      detail: 'In progress',
      width: 160,
    );
    final subproject = _GuideBlock(
      palette: palette,
      letter: 'SP',
      name: 'Student events',
      detail: 'In progress',
      width: 148,
    );
    final campus = _GuideBlock(
      palette: palette,
      letter: 'T',
      name: 'Campus tour',
      detail: 'Due: 10 Oct',
      badge: 'Incomplete',
      width: 140,
    );
    final welcome = _GuideBlock(
      palette: palette,
      letter: 'T',
      name: 'Welcome talk',
      detail: 'Completed',
      badge: 'Completed',
      width: 140,
    );
    final subtask = _GuideBlock(
      palette: palette,
      letter: 'ST',
      name: 'Print maps',
      detail: 'Due: 9 Oct',
      badge: 'Incomplete',
      width: 140,
    );
    return _GuideHScroll(
      child: _GuideElbowTree(
      palette: palette,
      parent: project,
      children: [
        _GuideElbowTree(
          palette: palette,
          parent: subproject,
          children: [
            _GuideElbowTree(
              palette: palette,
              parent: campus,
              children: [subtask],
            ),
            welcome,
          ],
        ),
      ],
      ),
    );
  }
}

class _GuideProgressRow extends StatelessWidget {
  const _GuideProgressRow({required this.percent});

  final int percent;

  @override
  Widget build(BuildContext context) {
    final color = percent >= 100
        ? const Color(0xFF1B7A4E)
        : percent <= 0
        ? kAsanaTextSecondary
        : Theme.of(context).colorScheme.primary;
    return Row(
      children: [
        Text(
          '$percent%',
          style: asanaTextStyle(
            Theme.of(context).textTheme.labelLarge,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 8,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const ColoredBox(color: Color(0xFFE6E7E8)),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: percent / 100,
                      heightFactor: 1,
                      child: ColoredBox(color: color),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

bool _guideMobileLtr(BuildContext context) =>
    MediaQuery.sizeOf(context).width < 600;

/// Horizontal scroll inside a guidance card. The drawing stays inside the
/// card, and the scrollbar stays hidden. On a wide screen a drawing that
/// fits is centered. A mouse wheel or a click-drag moves a drawing that
/// is wider than the card.
class _GuideHScroll extends StatefulWidget {
  const _GuideHScroll({required this.child});

  final Widget child;

  @override
  State<_GuideHScroll> createState() => _GuideHScrollState();
}

class _GuideHScrollState extends State<_GuideHScroll> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_controller.hasClients) return;
    final position = _controller.position;
    if (position.maxScrollExtent <= 0) return;
    final delta = event.scrollDelta.dx != 0
        ? event.scrollDelta.dx
        : event.scrollDelta.dy;
    if (delta == 0) return;
    final target = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (target == position.pixels) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (resolved) {
      if (!_controller.hasClients || resolved is! PointerScrollEvent) return;
      final current = _controller.position;
      final nextDelta = resolved.scrollDelta.dx != 0
          ? resolved.scrollDelta.dx
          : resolved.scrollDelta.dy;
      final next = (current.pixels + nextDelta).clamp(
        current.minScrollExtent,
        current.maxScrollExtent,
      );
      if (next != current.pixels) current.jumpTo(next);
      resolved.respond(allowPlatformDefault: false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final center = MediaQuery.sizeOf(context).width >= 600;
    return LayoutBuilder(
      builder: (context, constraints) {
        final minWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 0.0;
        return ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(
            scrollbars: false,
            dragDevices: const {
              PointerDeviceKind.touch,
              PointerDeviceKind.mouse,
              PointerDeviceKind.trackpad,
              PointerDeviceKind.stylus,
            },
          ),
          child: Listener(
            onPointerSignal: _onPointerSignal,
            child: SingleChildScrollView(
              controller: _controller,
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.hardEdge,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: minWidth),
                child: Row(
                  mainAxisAlignment: center
                      ? MainAxisAlignment.center
                      : MainAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(44, 44, 44, 44),
                      child: widget.child,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

Color _guideConnectorColor(AsanaLandingPalette palette) {
  return (palette.levelBadges?.subproject ?? palette.accent).withValues(
    alpha: 0.78,
  );
}

/// Same elbow as the map: down from the parent centre, across, then down
/// into each child. On a narrow screen the elbow runs to the right, matching
/// the phone map.
class _GuideElbowTree extends StatelessWidget {
  const _GuideElbowTree({
    required this.palette,
    required this.parent,
    required this.children,
  });

  final AsanaLandingPalette palette;
  final Widget parent;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return parent;
    return _GuideElbowBox(
      horizontal: _guideMobileLtr(context),
      color: _guideConnectorColor(palette),
      parent: parent,
      children: children,
    );
  }
}

class _GuideParentChildren extends StatelessWidget {
  const _GuideParentChildren({
    required this.palette,
    required this.parent,
    required this.children,
  });

  final AsanaLandingPalette palette;
  final Widget parent;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return _GuideHScroll(
      child: _GuideElbowTree(
        palette: palette,
        parent: parent,
        children: children,
      ),
    );
  }
}

class _GuideElbowBox extends MultiChildRenderObjectWidget {
  _GuideElbowBox({
    required this.horizontal,
    required this.color,
    required Widget parent,
    required List<Widget> children,
  }) : super(children: [parent, ...children]);

  final bool horizontal;
  final Color color;

  static const double stem = 42;
  static const double gap = 28;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderGuideElbow(horizontal: horizontal, color: color);
  }

  @override
  void updateRenderObject(BuildContext context, _RenderGuideElbow renderObject) {
    renderObject
      ..horizontal = horizontal
      ..color = color;
  }
}

class _GuideElbowParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderGuideElbow extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _GuideElbowParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _GuideElbowParentData> {
  _RenderGuideElbow({required bool horizontal, required Color color})
    : _horizontal = horizontal,
      _color = color;

  bool _horizontal;
  Color _color;

  bool get horizontal => _horizontal;
  set horizontal(bool value) {
    if (_horizontal == value) return;
    _horizontal = value;
    markNeedsLayout();
  }

  Color get color => _color;
  set color(Color value) {
    if (_color == value) return;
    _color = value;
    markNeedsPaint();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _GuideElbowParentData) {
      child.parentData = _GuideElbowParentData();
    }
  }

  List<RenderBox> get _boxes {
    final boxes = <RenderBox>[];
    var child = firstChild;
    while (child != null) {
      boxes.add(child);
      child = childAfter(child);
    }
    return boxes;
  }

  @override
  void performLayout() {
    final boxes = _boxes;
    final parent = boxes.first;
    final kids = boxes.sublist(1);
    final loose = BoxConstraints(maxWidth: constraints.maxWidth);
    parent.layout(loose, parentUsesSize: true);
    for (final kid in kids) {
      kid.layout(loose, parentUsesSize: true);
    }
    if (kids.isEmpty) {
      size = constraints.constrain(parent.size);
      (parent.parentData! as _GuideElbowParentData).offset = Offset.zero;
      return;
    }
    if (_horizontal) {
      var kidsHeight = 0.0;
      var kidsWidth = 0.0;
      for (final kid in kids) {
        kidsHeight += kid.size.height;
        if (kid.size.width > kidsWidth) kidsWidth = kid.size.width;
      }
      kidsHeight += _GuideElbowBox.gap * (kids.length - 1);
      final width = parent.size.width + _GuideElbowBox.stem + kidsWidth;
      final height = parent.size.height > kidsHeight
          ? parent.size.height
          : kidsHeight;
      size = constraints.constrain(Size(width, height));
      (parent.parentData! as _GuideElbowParentData).offset = Offset(
        0,
        (height - parent.size.height) / 2,
      );
      var y = (height - kidsHeight) / 2;
      final x = parent.size.width + _GuideElbowBox.stem;
      for (final kid in kids) {
        (kid.parentData! as _GuideElbowParentData).offset = Offset(x, y);
        y += kid.size.height + _GuideElbowBox.gap;
      }
      return;
    }
    var kidsWidth = 0.0;
    var kidsHeight = 0.0;
    for (final kid in kids) {
      kidsWidth += kid.size.width;
      if (kid.size.height > kidsHeight) kidsHeight = kid.size.height;
    }
    kidsWidth += _GuideElbowBox.gap * (kids.length - 1);
    final width = parent.size.width > kidsWidth ? parent.size.width : kidsWidth;
    final height = parent.size.height + _GuideElbowBox.stem + kidsHeight;
    size = constraints.constrain(Size(width, height));
    (parent.parentData! as _GuideElbowParentData).offset = Offset(
      (width - parent.size.width) / 2,
      0,
    );
    var x = (width - kidsWidth) / 2;
    final y = parent.size.height + _GuideElbowBox.stem;
    for (final kid in kids) {
      (kid.parentData! as _GuideElbowParentData).offset = Offset(x, y);
      x += kid.size.width + _GuideElbowBox.gap;
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final boxes = _boxes;
    final parent = boxes.first;
    final kids = boxes.sublist(1);
    if (kids.isNotEmpty) {
      final paint = Paint()
        ..color = _color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      final canvas = context.canvas;
      final parentData = parent.parentData! as _GuideElbowParentData;
      if (_horizontal) {
        final parentMid = offset +
            parentData.offset +
            Offset(parent.size.width, parent.size.height / 2);
        final junctionX = parentMid.dx + _GuideElbowBox.stem / 2;
        canvas.drawLine(parentMid, Offset(junctionX, parentMid.dy), paint);
        final mids = <double>[];
        for (final kid in kids) {
          final data = kid.parentData! as _GuideElbowParentData;
          mids.add(offset.dy + data.offset.dy + kid.size.height / 2);
        }
        if (mids.length > 1) {
          canvas.drawLine(
            Offset(junctionX, mids.first),
            Offset(junctionX, mids.last),
            paint,
          );
        } else {
          canvas.drawLine(
            Offset(junctionX, parentMid.dy),
            Offset(junctionX, mids.first),
            paint,
          );
        }
        for (var i = 0; i < kids.length; i++) {
          final kid = kids[i];
          final data = kid.parentData! as _GuideElbowParentData;
          final childLeft = offset + data.offset + Offset(0, kid.size.height / 2);
          canvas.drawLine(Offset(junctionX, mids[i]), childLeft, paint);
        }
      } else {
        final parentBottom = offset +
            parentData.offset +
            Offset(parent.size.width / 2, parent.size.height);
        final junctionY = parentBottom.dy + _GuideElbowBox.stem / 2;
        canvas.drawLine(parentBottom, Offset(parentBottom.dx, junctionY), paint);
        for (final kid in kids) {
          final data = kid.parentData! as _GuideElbowParentData;
          final childTop = offset +
              data.offset +
              Offset(kid.size.width / 2, 0);
          canvas.drawLine(
            Offset(parentBottom.dx, junctionY),
            Offset(childTop.dx, junctionY),
            paint,
          );
          canvas.drawLine(Offset(childTop.dx, junctionY), childTop, paint);
        }
      }
    }
    defaultPaint(context, offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    return defaultHitTestChildren(result, position: position);
  }
}

class _GuideCheckMark extends StatelessWidget {
  const _GuideCheckMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.black, width: 1.6),
      ),
      child: const Icon(Icons.check, size: 14, color: Colors.black),
    );
  }
}

class _GuideActionChip extends StatelessWidget {
  const _GuideActionChip({required this.palette, required this.label});

  final AsanaLandingPalette palette;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: palette.accent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          height: 1.1,
        ),
      ),
    );
  }
}

class _ViewsFigure extends StatelessWidget {
  const _ViewsFigure({required this.palette});

  final AsanaLandingPalette palette;

  @override
  Widget build(BuildContext context) {
    final sidebar = _GuideSidebar(palette: palette);
    final titles = const _GuideViewTitles();
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 560) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              sidebar,
              const SizedBox(height: 14),
              titles,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            sidebar,
            const SizedBox(width: 20),
            const Expanded(child: _GuideViewTitles()),
          ],
        );
      },
    );
  }
}

class _GuideSidebar extends StatelessWidget {
  const _GuideSidebar({required this.palette});

  final AsanaLandingPalette palette;

  @override
  Widget build(BuildContext context) {
    const rows = <(String, bool, bool, bool)>[
      ('Home', false, false, false),
      ('Work', true, false, false),
      ('Tasks', false, true, false),
      ('All Works', false, true, false),
      ('List', false, false, true),
      ('Map', false, false, false),
      ('Discussion', false, false, false),
      ('Guidance', false, false, false),
    ];
    final selectedBg = palette.selectedNav;
    final selectedFg = selectedBg.computeLuminance() > 0.45
        ? const Color(0xFF1A1A1A)
        : Colors.white;
    return Container(
      width: 196,
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
      decoration: BoxDecoration(
        color: palette.sidebar,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final row in rows)
            Padding(
              padding: EdgeInsets.only(left: row.$3 ? 14 : 0, bottom: 4),
              child: Container(
                height: row.$2 ? 28 : 32,
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: row.$4 ? selectedBg : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  row.$1,
                  style: TextStyle(
                    fontSize: row.$2 ? 13 : 14,
                    fontWeight: FontWeight.w600,
                    color: row.$4 ? selectedFg : palette.onSidebar,
                  ),
                ),
              ),
            ),
          Text(
            'People and performance appear when your role includes them.',
            style: TextStyle(
              fontSize: 11,
              height: 1.3,
              color: palette.onSidebarMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _GuideViewTitles extends StatelessWidget {
  const _GuideViewTitles();

  @override
  Widget build(BuildContext context) {
    const views = [
      (
        'Tasks',
        'The items you execute. A task is the row, and its sub-tasks are the breakdown under it.',
      ),
      (
        'All Works',
        'Tasks and sub-tasks together in one list, so every item that still needs to be done is on the same page.',
      ),
      (
        'List',
        'The whole structure, from the project down to the sub-task, as rows. Each child is indented under its parent.',
      ),
      (
        'Map',
        'The same whole structure, from the project down to the sub-task, drawn as a tree.',
      ),
    ];
    final name = asanaTextStyle(
      Theme.of(context).textTheme.titleSmall,
      fontSize: 15,
      fontWeight: FontWeight.w700,
      color: kAsanaTextPrimary,
    );
    final body = asanaTextStyle(
      Theme.of(context).textTheme.bodyMedium,
      fontSize: 13.5,
      height: 1.4,
      color: kAsanaTextPrimary,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final view in views)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(view.$1, style: name),
                const SizedBox(height: 2),
                Text(view.$2, style: body),
              ],
            ),
          ),
      ],
    );
  }
}

class _BeforeAfterExample extends StatelessWidget {
  const _BeforeAfterExample({
    required this.palette,
    required this.button,
    required this.before,
    required this.after,
    this.ask,
  });

  final AsanaLandingPalette palette;
  final String button;
  final Widget before;
  final Widget after;
  final String? ask;

  @override
  Widget build(BuildContext context) {
    final caption = asanaTextStyle(
      Theme.of(context).textTheme.labelLarge,
      fontSize: 12,
      fontWeight: FontWeight.w700,
      color: kAsanaTextSecondary,
    );
    Widget side(String label, Widget picture) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: caption),
          const SizedBox(height: 22),
          picture,
        ],
      );
    }

    final arrow = Icon(Icons.arrow_forward, color: palette.accent, size: 22);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
      decoration: BoxDecoration(
        color: palette.listSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE6E7E8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (ask != null) ...[
            Text(
              ask!,
              style: asanaTextStyle(
                Theme.of(context).textTheme.bodyMedium,
                fontSize: 14,
                height: 1.4,
                fontWeight: FontWeight.w600,
                color: kAsanaTextPrimary,
              ),
            ),
            const SizedBox(height: 10),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _GuideActionChip(palette: palette, label: button),
            ],
          ),
          const SizedBox(height: 12),
          _GuideHScroll(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final before = side('Before', this.before);
                final after = side('After', this.after);
                final narrow = MediaQuery.sizeOf(context).width < 600;
                if (narrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      before,
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Icon(
                          Icons.arrow_downward,
                          color: palette.accent,
                          size: 22,
                        ),
                      ),
                      after,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    before,
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 42, 12, 0),
                      child: arrow,
                    ),
                    after,
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

Widget _guideActionBlock(
  AsanaLandingPalette palette, {
  required String letter,
  required String name,
  String? badge,
  double width = 116,
  bool checked = false,
}) {
  return _GuideBlock(
    palette: palette,
    letter: letter,
    name: name,
    detail: letter == 'P' || letter == 'SP' ? 'Project' : 'Work',
    badge: badge,
    checked: checked,
    width: width,
  );
}

class _GuideCheckBox extends StatelessWidget {
  const _GuideCheckBox({required this.checked});

  final bool checked;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.black, width: 1.6),
      ),
      child: checked
          ? const Icon(Icons.check, size: 14, color: Colors.black)
          : null,
    );
  }
}

/// Arrow tip sits at the top-left of the 22×28 picture.
class _GuideMouseCursor extends StatelessWidget {
  const _GuideMouseCursor();

  @override
  Widget build(BuildContext context) {
    return const CustomPaint(
      size: Size(22, 28),
      painter: _MouseCursorPainter(),
    );
  }
}

class _MouseCursorPainter extends CustomPainter {
  const _MouseCursorPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(1, 1)
      ..lineTo(1, 18)
      ..lineTo(5.5, 14)
      ..lineTo(9, 22)
      ..lineTo(12.5, 20.5)
      ..lineTo(9, 12.5)
      ..lineTo(16, 12.5)
      ..close();
    canvas.drawShadow(path, const Color(0x66000000), 1.5, false);
    canvas.drawPath(path, Paint()..color = Colors.white);
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Fingertip, and the press rings around it, sit near the top of the picture.
class _GuideFinger extends StatelessWidget {
  const _GuideFinger();

  @override
  Widget build(BuildContext context) {
    return const CustomPaint(
      size: Size(52, 62),
      painter: _FingerPainter(),
    );
  }
}

class _FingerPainter extends CustomPainter {
  const _FingerPainter();

  static const Offset _tip = Offset(26, 18);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(_tip, 20, Paint()..color = const Color(0x33FF7043));
    canvas.drawCircle(
      _tip,
      13,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.7
        ..color = const Color(0xE6FF7043),
    );
    canvas.drawCircle(
      _tip,
      18,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = const Color(0x99FF7043),
    );
    final tick = Paint()
      ..color = const Color(0xDDFF7043)
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round;
    for (final angle in <double>[3.4, 4.1, 4.71, 5.3, 6.0]) {
      final dir = Offset(math.cos(angle), math.sin(angle));
      canvas.drawLine(_tip + dir * 15, _tip + dir * 22, tick);
    }

    final skin = Paint()..color = const Color(0xFFF3C2A0);
    final line = Paint()
      ..color = const Color(0xFF8A5A42)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeJoin = StrokeJoin.round;
    final finger = RRect.fromRectAndRadius(
      const Rect.fromLTWH(18, 18, 16, 42),
      const Radius.circular(8),
    );
    canvas.drawRRect(finger, skin);
    canvas.drawRRect(finger, line);
    final nail = RRect.fromRectAndRadius(
      const Rect.fromLTWH(21, 21, 10, 11),
      const Radius.circular(4),
    );
    canvas.drawRRect(nail, Paint()..color = const Color(0xFFFFE4D2));
    canvas.drawRRect(nail, line);
    canvas.drawLine(const Offset(21, 44), const Offset(31, 44), line);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CheckFigure extends StatelessWidget {
  const _CheckFigure({required this.palette});

  final AsanaLandingPalette palette;

  @override
  Widget build(BuildContext context) {
    final heading = asanaTextStyle(
      Theme.of(context).textTheme.titleSmall,
      fontSize: 15,
      fontWeight: FontWeight.w700,
      color: kAsanaTextPrimary,
    );
    final rowTitle = asanaTextStyle(
      Theme.of(context).textTheme.labelLarge,
      fontSize: 13,
      fontWeight: FontWeight.w700,
      color: kAsanaTextPrimary,
    );
    final caption = asanaTextStyle(
      Theme.of(context).textTheme.labelLarge,
      fontSize: 12,
      fontWeight: FontWeight.w700,
      color: kAsanaTextSecondary,
    );
    final note = asanaTextStyle(
      Theme.of(context).textTheme.bodySmall,
      fontSize: 12.5,
      height: 1.35,
      color: kAsanaTextPrimary,
    );
    final nameStyle = asanaTextStyle(
      Theme.of(context).textTheme.labelLarge,
      fontSize: 12,
      fontWeight: FontWeight.w700,
      color: kAsanaTextPrimary,
    );

    Widget listRow({required bool showBox, required bool checked}) {
      return Container(
        width: 176,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: palette.content,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE6E7E8)),
        ),
        child: Row(
          children: [
            showBox
                ? _GuideCheckBox(checked: checked)
                : const SizedBox(width: 20, height: 20),
            const SizedBox(width: 8),
            Text('Campus tour', style: nameStyle),
          ],
        ),
      );
    }

    Widget mapBlock({required bool checked, required bool showEmptyBox}) {
      return Stack(
        clipBehavior: Clip.none,
        children: [
          _guideActionBlock(
            palette,
            letter: 'T',
            name: 'Campus tour',
            badge: 'Incomplete',
            checked: checked,
            width: 132,
          ),
          if (showEmptyBox)
            const Positioned(
              left: -6,
              bottom: -10,
              child: _GuideCheckBox(checked: false),
            ),
        ],
      );
    }

    Widget picture({
      required double height,
      required List<Widget> children,
    }) {
      return SizedBox(
        width: 210,
        height: height,
        child: Stack(clipBehavior: Clip.none, children: children),
      );
    }

    Widget pair({
      required String label,
      required String detail,
      required Widget before,
      required Widget after,
      required double pictureHeight,
    }) {
      Widget frame(String name, Widget child) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: caption),
            const SizedBox(height: 8),
            child,
          ],
        );
      }

      final beforeSide = frame('Before', before);
      final afterSide = frame('After', after);
      return Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: rowTitle),
            const SizedBox(height: 4),
            Text(detail, style: note),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 520;
                if (narrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      beforeSide,
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Icon(
                          Icons.arrow_downward,
                          color: palette.accent,
                          size: 22,
                        ),
                      ),
                      afterSide,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    beforeSide,
                    Padding(
                      padding: EdgeInsets.fromLTRB(12, pictureHeight * 0.35, 12, 0),
                      child: Icon(
                        Icons.arrow_forward,
                        color: palette.accent,
                        size: 22,
                      ),
                    ),
                    afterSide,
                  ],
                );
              },
            ),
          ],
        ),
      );
    }

    Widget subpanel({
      required String title,
      required String intro,
      required List<Widget> rows,
    }) {
      return Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
        decoration: BoxDecoration(
          color: palette.listSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE6E7E8)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: heading),
            const SizedBox(height: 6),
            Text(intro, style: note),
            ...rows,
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        subpanel(
          title: 'Computer',
          intro:
              'Click the box to check. Click it again to uncheck.',
          rows: [
            pair(
              label: 'List',
              detail:
                  'Cursor away from the box: the box stays hidden. Cursor on the box area: the box appears.',
              pictureHeight: 72,
              before: picture(
                height: 72,
                children: [
                  Positioned(left: 8, top: 16, child: listRow(showBox: false, checked: false)),
                  const Positioned(left: 78, top: 22, child: _GuideMouseCursor()),
                ],
              ),
              after: picture(
                height: 72,
                children: [
                  Positioned(left: 8, top: 16, child: listRow(showBox: true, checked: false)),
                  const Positioned(left: 20, top: 28, child: _GuideMouseCursor()),
                ],
              ),
            ),
            pair(
              label: 'Map',
              detail:
                  'Cursor on the block: the box stays hidden. Cursor at the bottom-left corner: the box appears.',
              pictureHeight: 128,
              before: picture(
                height: 128,
                children: [
                  Positioned(
                    left: 28,
                    top: 18,
                    child: mapBlock(checked: false, showEmptyBox: false),
                  ),
                  const Positioned(left: 72, top: 34, child: _GuideMouseCursor()),
                ],
              ),
              after: picture(
                height: 128,
                children: [
                  Positioned(
                    left: 28,
                    top: 18,
                    child: mapBlock(checked: false, showEmptyBox: true),
                  ),
                  const Positioned(left: 26, top: 70, child: _GuideMouseCursor()),
                ],
              ),
            ),
          ],
        ),
        subpanel(
          title: 'Phone',
          intro:
              'Hold still for 0.2 seconds to check. The check appears while your finger is still down. Hold the same spot again for 0.2 seconds to uncheck. A press that scrolls does not check. On the Map, tap the checkbox to uncheck.',
          rows: [
            pair(
              label: 'List',
              detail:
                  'Finger just down: the box stays hidden. Held for 0.2 seconds: the box appears and the row is checked.',
              pictureHeight: 96,
              before: picture(
                height: 96,
                children: [
                  Positioned(left: 8, top: 8, child: listRow(showBox: false, checked: false)),
                  const Positioned(left: 74, top: 0, child: _GuideFinger()),
                ],
              ),
              after: picture(
                height: 96,
                children: [
                  Positioned(left: 8, top: 8, child: listRow(showBox: true, checked: true)),
                  const Positioned(left: 74, top: 0, child: _GuideFinger()),
                ],
              ),
            ),
            pair(
              label: 'Map',
              detail:
                  'Finger just down: the box stays hidden. Held for 0.2 seconds: the box appears and the block is checked.',
              pictureHeight: 140,
              before: picture(
                height: 140,
                children: [
                  Positioned(
                    left: 24,
                    top: 16,
                    child: mapBlock(checked: false, showEmptyBox: false),
                  ),
                  const Positioned(left: 66, top: 12, child: _GuideFinger()),
                ],
              ),
              after: picture(
                height: 140,
                children: [
                  Positioned(
                    left: 24,
                    top: 16,
                    child: mapBlock(checked: true, showEmptyBox: false),
                  ),
                  const Positioned(left: 66, top: 12, child: _GuideFinger()),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MoveExamples extends StatelessWidget {
  const _MoveExamples({required this.palette});

  final AsanaLandingPalette palette;

  @override
  Widget build(BuildContext context) {
    Widget under(
      String parentLetter,
      String parentName,
      String childLetter,
      String childName, {
      String? badge,
      bool checked = false,
    }) {
      return _GuideElbowTree(
        palette: palette,
        parent: _guideActionBlock(
          palette,
          letter: parentLetter,
          name: parentName,
        ),
        children: [
          _guideActionBlock(
            palette,
            letter: childLetter,
            name: childName,
            badge: badge,
            checked: checked,
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _BeforeAfterExample(
          palette: palette,
          button: 'Move Task',
          ask:
              'I want to move the "Campus tour" task from under project "Alpha" to under project "Beta".',
          before: under(
            'P',
            'Alpha',
            'T',
            'Campus tour',
            badge: 'Incomplete',
            checked: true,
          ),
          after: under('P', 'Beta', 'T', 'Campus tour', badge: 'Incomplete'),
        ),
        _BeforeAfterExample(
          palette: palette,
          button: 'Move Subproject',
          ask:
              'I want to move the "Events" sub-project from under project "Alpha" to under project "Beta".',
          before: under('P', 'Alpha', 'SP', 'Events', checked: true),
          after: under('P', 'Beta', 'SP', 'Events'),
        ),
        _BeforeAfterExample(
          palette: palette,
          button: 'Move Subtask',
          ask:
              'I want to move the "Figures" sub-task from under task "Briefing" to under task "Welcome".',
          before: under(
            'T',
            'Briefing',
            'ST',
            'Figures',
            badge: 'Incomplete',
            checked: true,
          ),
          after: under('T', 'Welcome', 'ST', 'Figures', badge: 'Incomplete'),
        ),
      ],
    );
  }
}

class _MakeExamples extends StatelessWidget {
  const _MakeExamples({required this.palette});

  final AsanaLandingPalette palette;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _BeforeAfterExample(
          palette: palette,
          button: 'Make Subproject',
          ask:
              'I want to make the project "Events" a sub-project under the project "Orientation".',
          before: _guideActionBlock(
            palette,
            letter: 'P',
            name: 'Events',
            checked: true,
          ),
          after: _GuideElbowTree(
            palette: palette,
            parent: _guideActionBlock(
              palette,
              letter: 'P',
              name: 'Orientation',
            ),
            children: [
              _guideActionBlock(palette, letter: 'SP', name: 'Events'),
            ],
          ),
        ),
        _BeforeAfterExample(
          palette: palette,
          button: 'Make Subtask',
          ask:
              'I want to make the task "Print maps" a sub-task under the task "Briefing".',
          before: _guideActionBlock(
            palette,
            letter: 'T',
            name: 'Print maps',
            badge: 'Incomplete',
            checked: true,
          ),
          after: _GuideElbowTree(
            palette: palette,
            parent: _guideActionBlock(
              palette,
              letter: 'T',
              name: 'Briefing',
              badge: 'Incomplete',
            ),
            children: [
              _guideActionBlock(
                palette,
                letter: 'ST',
                name: 'Print maps',
                badge: 'Incomplete',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DetachExamples extends StatelessWidget {
  const _DetachExamples({required this.palette});

  final AsanaLandingPalette palette;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _BeforeAfterExample(
          palette: palette,
          button: 'Detach Project',
          before: _GuideElbowTree(
            palette: palette,
            parent: _guideActionBlock(palette, letter: 'P', name: 'Orientation'),
            children: [
              _guideActionBlock(
                palette,
                letter: 'SP',
                name: 'Events',
                checked: true,
              ),
            ],
          ),
          after: _guideActionBlock(palette, letter: 'P', name: 'Events'),
        ),
        _BeforeAfterExample(
          palette: palette,
          button: 'Detach Task',
          before: _GuideElbowTree(
            palette: palette,
            parent: _guideActionBlock(
              palette,
              letter: 'T',
              name: 'Briefing',
              badge: 'Incomplete',
            ),
            children: [
              _guideActionBlock(
                palette,
                letter: 'ST',
                name: 'Print maps',
                badge: 'Incomplete',
                checked: true,
              ),
            ],
          ),
          after: _guideActionBlock(
            palette,
            letter: 'T',
            name: 'Print maps',
            badge: 'Incomplete',
          ),
        ),
      ],
    );
  }
}

class _CloneExamples extends StatelessWidget {
  const _CloneExamples({required this.palette});

  final AsanaLandingPalette palette;

  @override
  Widget build(BuildContext context) {
    Widget task(String name) {
      return _guideActionBlock(
        palette,
        letter: 'T',
        name: name,
        badge: 'Incomplete',
        width: 156,
      );
    }

    Widget subtask(String name) {
      return _guideActionBlock(
        palette,
        letter: 'ST',
        name: name,
        badge: 'Incomplete',
        width: 168,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _BeforeAfterExample(
          palette: palette,
          button: 'Clone',
          before: _guideActionBlock(
            palette,
            letter: 'T',
            name: 'Weekly report',
            badge: 'Incomplete',
            checked: true,
            width: 156,
          ),
          after: Wrap(
            spacing: 36,
            runSpacing: 20,
            crossAxisAlignment: WrapCrossAlignment.start,
            children: [
              task('Weekly report'),
              task('Weekly report (cloned)'),
            ],
          ),
        ),
        _BeforeAfterExample(
          palette: palette,
          button: 'Clone',
          before: _GuideElbowTree(
            palette: palette,
            parent: task('Briefing'),
            children: [
              _guideActionBlock(
                palette,
                letter: 'ST',
                name: 'Collect figures',
                badge: 'Incomplete',
                checked: true,
                width: 168,
              ),
            ],
          ),
          after: _GuideElbowTree(
            palette: palette,
            parent: task('Briefing'),
            children: [
              subtask('Collect figures'),
              subtask('Collect figures (cloned)'),
            ],
          ),
        ),
      ],
    );
  }
}
