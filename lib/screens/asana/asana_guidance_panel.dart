import 'package:flutter/material.dart';

import '../../priority.dart';
import '../asana_landing_screen.dart';
import 'asana_due_badge.dart';
import 'asana_filter_widgets.dart';
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
  final _kTask = GlobalKey();
  final _kSubtask = GlobalKey();
  final _kProject = GlobalKey();
  final _kSubproject = GlobalKey();
  final _kNest = GlobalKey();
  final _kRecurring = GlobalKey();
  final _kMilestones = GlobalKey();
  final _kMap = GlobalKey();
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
                          ('Task', _kTask),
                          ('Sub-task', _kSubtask),
                          ('Project', _kProject),
                          ('Sub-project', _kSubproject),
                          ('How they nest', _kNest),
                          ('Recurring', _kRecurring),
                          ('Milestones', _kMilestones),
                          ('Map', _kMap),
                          ('Priority', _kPriority),
                          ('Status', _kStatus),
                          ('Commence', _kCommence),
                          ('Complexity', _kComplexity),
                        ],
                        onJump: _jumpTo,
                      ),
                      const SizedBox(height: 20),
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
                            'On a create slide, Make recurring turns one form into several separate items. Choose Daily, Weekly, Monthly, or Yearly, then end by a date or after a count. Each occurrence is its own task or sub-task after you click Create. They are not kept as a linked series. Recurring is hidden when Commence is To be commenced, because those items do not have start and due dates yet.',
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
                        key: _kMap,
                        palette: palette,
                        title: 'Map',
                        body:
                            'Map draws the same hierarchy as pictures: project, then sub-project if there is one, then task, then sub-task. On a phone the tree goes left to right; on a wide screen it goes top to bottom. Each block has a P / SP / T / ST label. Task and sub-task blocks also show Completed, Submitted, Overdue, Due Today, or Incomplete. Filters at the top (status, completed dates, expected due dates, creator team) control which blocks appear. Click a block to open its slide.',
                        figure: _MapFigure(palette: palette),
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
                            'Status is the workflow state. You do not type Completed into this field; it changes when work is accepted through the workflow. Paused appears when the item, or its parent project or sub-project, is paused. Deleted items leave the normal active lists.\n\nTasks and sub-tasks use Incomplete, Completed, Paused, and Deleted. Projects and sub-projects use Not started, In progress, Completed, Paused, and Deleted.\n\nMap blocks can also show Overdue, Due Today, or Submitted. Those are due-date and submission labels, not the Status field.',
                        figure: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: const [
                            AsanaStatusChip(status: 'Incomplete'),
                            AsanaStatusChip(status: 'Completed'),
                            AsanaStatusChip(status: 'Not started'),
                            AsanaStatusChip(status: 'In progress'),
                            AsanaStatusChip(status: 'Paused'),
                            AsanaStatusChip(status: 'Deleted'),
                          ],
                        ),
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
    );
  }
}


class _GuideJumpBar extends StatelessWidget {
  const _GuideJumpBar({required this.items, required this.onJump});

  final List<(String label, GlobalKey key)> items;
  final Future<void> Function(GlobalKey key) onJump;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final item in items)
          OutlinedButton(
            onPressed: () => onJump(item.$2),
            style: OutlinedButton.styleFrom(
              foregroundColor: kAsanaTextPrimary,
              side: const BorderSide(color: Color(0xFFD0D3D4)),
              backgroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              minimumSize: const Size(0, 36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              item.$1,
              style: asanaTextStyle(
                Theme.of(context).textTheme.labelLarge,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: kAsanaTextPrimary,
              ),
            ),
          ),
      ],
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
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (letter != null)
              Row(
                children: [
                  AsanaRowTypeLetter(letter: letter!, status: 'Incomplete'),
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
    this.width = 158,
  });

  final AsanaLandingPalette palette;
  final String letter;
  final String name;
  final String detail;
  final String? badge;
  final double width;

  @override
  Widget build(BuildContext context) {
    final (:bg, :fg, :border) = _blockColors(palette, letter);
    return SizedBox(
      width: width,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
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
                    color: fg.withValues(alpha: 0.86),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: -10,
            left: -4,
            child: AsanaRowTypeLetter(letter: letter, status: 'Incomplete'),
          ),
          if (badge != null)
            Positioned(
              top: -10,
              right: -4,
              child: AsanaDueBadge(label: badge!, height: 24, fontSize: 10),
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
  final surface = palette.listSurface;
  final accent = palette.accent;
  Color wash(double alpha) =>
      Color.alphaBlend(accent.withValues(alpha: alpha), surface);
  switch (letter) {
    case 'P':
      return (bg: accent, fg: Colors.white, border: accent);
    case 'SP':
      return (
        bg: wash(0.70),
        fg: Colors.white,
        border: accent.withValues(alpha: 0.88),
      );
    case 'T':
      return (
        bg: wash(0.32),
        fg: kAsanaTextPrimary,
        border: accent.withValues(alpha: 0.52),
      );
    default:
      return (
        bg: wash(0.12),
        fg: kAsanaTextPrimary,
        border: accent.withValues(alpha: 0.36),
      );
  }
}

class _TaskFigure extends StatelessWidget {
  const _TaskFigure({required this.palette});

  final AsanaLandingPalette palette;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: _GuideBlock(
        palette: palette,
        letter: 'T',
        name: 'Draft the briefing',
        detail: 'Due: in 3 working days',
        badge: 'Incomplete',
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
          badge: 'Due Today',
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
                    AsanaRowTypeLetter(
                      letter: children[i].letter,
                      status: 'Incomplete',
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
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _GuideCallout('Create slide\nMake recurring  +'),
        Icon(Icons.arrow_forward, color: palette.accent),
        _GuideBlock(
          palette: palette,
          letter: 'T',
          name: 'Weekly report',
          detail: 'Mon 6 Oct',
          badge: 'Incomplete',
          width: 132,
        ),
        _GuideBlock(
          palette: palette,
          letter: 'T',
          name: 'Weekly report',
          detail: 'Mon 13 Oct',
          badge: 'Incomplete',
          width: 132,
        ),
        _GuideBlock(
          palette: palette,
          letter: 'T',
          name: 'Weekly report',
          detail: 'Mon 20 Oct',
          badge: 'Incomplete',
          width: 132,
        ),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: achieved
                  ? const Color(0xFFE8F5E9)
                  : const Color(0xFFECEFF1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              achieved ? 'A' : 'NA',
              style: TextStyle(
                fontSize: 10,
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
    if (_guideMobileLtr(context)) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            project,
            const _GuideAcrossLine(),
            subproject,
            const _GuideAcrossLine(),
            Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    campus,
                    const _GuideAcrossLine(),
                    subtask,
                  ],
                ),
                const SizedBox(height: 12),
                welcome,
              ],
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        project,
        const _GuideDownLine(),
        subproject,
        const _GuideDownLine(),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                campus,
                const _GuideDownLine(),
                subtask,
              ],
            ),
            const SizedBox(width: 16),
            welcome,
          ],
        ),
      ],
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

class _GuideCallout extends StatelessWidget {
  const _GuideCallout(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFFE082)),
      ),
      child: Text(
        text,
        style: asanaTextStyle(
          Theme.of(context).textTheme.labelLarge,
          fontWeight: FontWeight.w600,
          color: kAsanaTextPrimary,
          height: 1.35,
        ),
      ),
    );
  }
}

class _GuideDownLine extends StatelessWidget {
  const _GuideDownLine();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Center(
        child: Container(
          width: 2,
          height: 18,
          color: const Color(0xFFB0B3B5),
        ),
      ),
    );
  }
}

bool _guideMobileLtr(BuildContext context) =>
    MediaQuery.sizeOf(context).width < 600;

class _GuideAcrossLine extends StatelessWidget {
  const _GuideAcrossLine();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 4, vertical: 28),
      child: SizedBox(
        width: 18,
        height: 2,
        child: ColoredBox(color: Color(0xFFB0B3B5)),
      ),
    );
  }
}

class _GuideParentChildren extends StatelessWidget {
  const _GuideParentChildren({
    required this.parent,
    required this.children,
  });

  final Widget parent;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (_guideMobileLtr(context)) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            parent,
            const _GuideAcrossLine(),
            Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) const SizedBox(height: 12),
                  children[i],
                ],
              ],
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        parent,
        const _GuideDownLine(),
        if (children.length == 1)
          children.first
        else
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(width: 16),
                children[i],
              ],
            ],
          ),
      ],
    );
  }
}
