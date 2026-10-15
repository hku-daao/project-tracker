import 'package:flutter/material.dart';

import '../../config/dev_auth_context.dart';
import '../../services/backend_api.dart';
import '../asana_landing_screen.dart';
import 'asana_detail_widgets.dart';
import 'asana_filter_widgets.dart';
import 'asana_task_ai_assistant.dart';
import 'asana_theme.dart';

/// Formats a staff name as "Xxxx XXXX" or "Xxx Xxxx XXXX".
/// The last word is the surname in capitals. Earlier words keep one capital.
String? suggestedStaffName(String raw) {
  final parts = raw
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty) return null;
  String given(String word) {
    if (word.isEmpty) return word;
    return word[0].toUpperCase() + word.substring(1).toLowerCase();
  }

  final surname = parts.last.toUpperCase();
  final formatted = [
    for (final part in parts.take(parts.length - 1)) given(part),
    surname,
  ].join(' ');
  if (formatted == raw.trim()) return null;
  return formatted;
}

String? staffEmailError(String raw) {
  final email = raw.trim().toLowerCase();
  final at = email.indexOf('@');
  if (at <= 0 || at != email.lastIndexOf('@')) {
    return 'Email must be a single @hku.hk address.';
  }
  final local = email.substring(0, at);
  if (email.substring(at) != '@hku.hk') {
    return 'Email domain must be @hku.hk.';
  }
  if (local.length > 8) {
    return 'Email name before @ must be 8 characters or fewer.';
  }
  if (!RegExp(r'^[a-z0-9][a-z0-9._-]*$').hasMatch(local)) {
    return 'Email name contains a character that is not allowed.';
  }
  return null;
}

class _OfficeRow {
  const _OfficeRow({required this.officeId, required this.officeName});

  final String officeId;
  final String officeName;
}

class _TeamRow {
  const _TeamRow({
    required this.id,
    required this.teamId,
    required this.teamName,
    required this.officeId,
  });

  final String id;
  final String teamId;
  final String teamName;
  final String? officeId;
}

class _StaffRow {
  const _StaffRow({
    required this.id,
    required this.name,
    required this.email,
    required this.teamId,
    required this.officeId,
    required this.active,
  });

  final String id;
  final String name;
  final String email;
  final String? teamId;
  final String? officeId;
  final bool active;
}

class _LinkRow {
  const _LinkRow({
    required this.supervisorStaffId,
    required this.subordinateStaffId,
  });

  final String supervisorStaffId;
  final String subordinateStaffId;
}

enum _ReportingMode { supervisor, subordinate }

class AsanaStaffAdminPanel extends StatefulWidget {
  const AsanaStaffAdminPanel({super.key, required this.palette});

  final AsanaLandingPalette palette;

  @override
  State<AsanaStaffAdminPanel> createState() => _AsanaStaffAdminPanelState();
}

class _AsanaStaffAdminPanelState extends State<AsanaStaffAdminPanel> {
  bool _loading = true;
  String? _error;
  List<_OfficeRow> _offices = const [];
  List<_TeamRow> _teams = const [];
  List<_StaffRow> _staff = const [];
  List<_LinkRow> _links = const [];
  List<_LinkRow> _impliedLinks = const [];
  _ReportingMode _reportingMode = _ReportingMode.subordinate;
  String? _reportingStaffId;
  final Set<String> _checkedReporting = {};
  bool _savingLinks = false;
  String? _createdStaffEmail;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<({Map<String, dynamic>? data, String? error})> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final token = await activeUserIdToken();
    if (token == null) {
      return (data: null, error: 'Sign in again to use People.');
    }
    return BackendApi().staffAdminRequest(
      idToken: token,
      method: method,
      path: path,
      body: body,
    );
  }

  Future<void> _load({bool silent = false, String? focusEmail}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    final result = await _request('GET', '/api/staff-admin/context');
    if (!mounted) return;
    if (result.error != null || result.data == null) {
      final message = result.error ?? 'Could not load People.';
      if (silent) {
        await _showError(message);
        return;
      }
      setState(() {
        _loading = false;
        _error = message;
      });
      return;
    }
    final data = result.data!;
    final offices = [
      for (final raw in (data['offices'] as List? ?? const []))
        if (raw is Map)
          _OfficeRow(
            officeId: raw['officeId']?.toString() ?? '',
            officeName: raw['officeName']?.toString() ?? '',
          ),
    ];
    final teams = [
      for (final raw in (data['teams'] as List? ?? const []))
        if (raw is Map)
          _TeamRow(
            id: raw['id']?.toString() ?? '',
            teamId: raw['teamId']?.toString() ?? '',
            teamName: raw['teamName']?.toString() ?? '',
            officeId: raw['officeId']?.toString(),
          ),
    ];
    final staff = [
      for (final raw in (data['staff'] as List? ?? const []))
        if (raw is Map)
          _StaffRow(
            id: raw['id']?.toString() ?? '',
            name: raw['name']?.toString() ?? '',
            email: raw['email']?.toString() ?? '',
            teamId: raw['teamId']?.toString(),
            officeId: raw['officeId']?.toString(),
            active: raw['active'] != false,
          ),
    ];
    List<_LinkRow> readLinks(String key) => [
      for (final raw in (data[key] as List? ?? const []))
        if (raw is Map)
          _LinkRow(
            supervisorStaffId: raw['supervisorStaffId']?.toString() ?? '',
            subordinateStaffId: raw['subordinateStaffId']?.toString() ?? '',
          ),
    ];
    final links = readLinks('links');
    final impliedLinks = readLinks('impliedLinks');
    final previous = _reportingStaffId;
    var focus = staff.any((s) => s.id == previous)
        ? previous
        : (staff.isEmpty ? null : staff.first.id);
    final wantedEmail = focusEmail?.trim().toLowerCase();
    if (wantedEmail != null &&
        wantedEmail.isNotEmpty &&
        _reportingMode == _ReportingMode.subordinate) {
      for (final person in staff) {
        if (person.email.trim().toLowerCase() == wantedEmail) {
          focus = person.id;
          break;
        }
      }
    }
    setState(() {
      _loading = false;
      _offices = offices;
      _teams = teams;
      _staff = staff;
      _links = links;
      _impliedLinks = impliedLinks;
      _reportingStaffId = focus;
      _checkedReporting
        ..clear()
        ..addAll(_reportingPeersOf(focus));
    });
  }

  bool get _subordinateMode => _reportingMode == _ReportingMode.subordinate;

  Set<String> _peerIds(List<_LinkRow> rows, String? staffId) {
    if (staffId == null) return {};
    final ids = <String>{};
    for (final link in rows) {
      if (_subordinateMode) {
        if (link.subordinateStaffId == staffId) ids.add(link.supervisorStaffId);
      } else if (link.supervisorStaffId == staffId) {
        ids.add(link.subordinateStaffId);
      }
    }
    return ids;
  }

  Set<String> _reportingPeersOf(String? staffId) {
    return {
      ..._peerIds(_links, staffId),
      ..._peerIds(_impliedLinks, staffId),
    };
  }

  bool _managementChanged() {
    final saved = _reportingPeersOf(_reportingStaffId);
    if (saved.length != _checkedReporting.length) return true;
    return !saved.containsAll(_checkedReporting);
  }

  List<_StaffRow> _staffOnTeam(_TeamRow team) {
    final key = team.teamId.trim().toLowerCase();
    return [
      for (final person in _staff)
        if ((person.teamId ?? '').trim().toLowerCase() == key) person,
    ];
  }

  Future<void> _showError(String message) {
    return showAsanaInfoDialog(
      context: context,
      title: 'People',
      content: message,
      palette: widget.palette,
    );
  }

  Future<void> _saveLinks() async {
    final staffId = _reportingStaffId;
    if (staffId == null) return;
    final locked = _peerIds(_impliedLinks, staffId);
    setState(() => _savingLinks = true);
    final result = _subordinateMode
        ? await _request(
            'PUT',
            '/api/staff-admin/supervisors',
            body: {
              'subordinateStaffId': staffId,
              'supervisorStaffIds': _checkedReporting
                  .where((id) => !locked.contains(id))
                  .toList(),
            },
          )
        : await _request(
            'PUT',
            '/api/staff-admin/subordinates',
            body: {
              'supervisorStaffId': staffId,
              'subordinateStaffIds': _checkedReporting
                  .where((id) => !locked.contains(id))
                  .toList(),
            },
          );
    if (!mounted) return;
    setState(() => _savingLinks = false);
    if (result.error != null) {
      await _showError(result.error!);
      return;
    }
    await _load(silent: true);
  }

  Future<void> _submitStaff(
    Map<String, dynamic> body, {
    String? staffId,
  }) async {
    final result = await _request(
      staffId == null ? 'POST' : 'PATCH',
      staffId == null ? '/api/staff-admin/staff' : '/api/staff-admin/staff/$staffId',
      body: body,
    );
    if (result.error != null) {
      throw result.error!;
    }
    if (staffId == null) {
      _createdStaffEmail = body['email']?.toString();
    }
  }

  Future<void> _openStaffForm({_StaffRow? existing}) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => _StaffFormDialog(
        palette: widget.palette,
        offices: _offices,
        teams: _teams,
        existing: existing,
        onSubmit: (body) => _submitStaff(body, staffId: existing?.id),
      ),
    );
    if (saved == true) {
      final email = _createdStaffEmail;
      _createdStaffEmail = null;
      await _load(silent: true, focusEmail: email);
    }
  }

  Future<void> _editTeam({_TeamRow? existing}) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => _TeamFormDialog(
        palette: widget.palette,
        offices: _offices,
        teams: _teams,
        existing: existing,
        affectedStaff: existing == null ? const [] : _staffOnTeam(existing),
        onSubmit: (body) => _request(
          existing == null ? 'POST' : 'PATCH',
          existing == null
              ? '/api/staff-admin/teams'
              : '/api/staff-admin/teams/${existing.id}',
          body: body,
        ),
      ),
    );
    if (saved == true) await _load();
  }

  Future<void> _removeTeam(_TeamRow team) async {
    final people = _staffOnTeam(team);
    final names = people.map((p) => p.name).join(', ');
    final content = people.isEmpty
        ? 'Remove team ${team.teamName}? No staff currently use it.'
        : 'Removing ${team.teamName} leaves ${people.length} staff with no team: $names. '
            'Set a team for each of them afterwards. Staff with no team leave this office list until a super admin, or a later team assignment, puts them back.';
    final ok = await showAsanaConfirmDialog(
      context: context,
      title: 'Remove team?',
      content: content,
      confirmText: 'Remove team',
      isDestructive: true,
      palette: widget.palette,
    );
    if (ok != true) return;
    final result = await _request('DELETE', '/api/staff-admin/teams/${team.id}');
    if (!mounted) return;
    if (result.error != null) {
      await _showError(result.error!);
      return;
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return ColoredBox(
        color: widget.palette.panelBackground,
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return ColoredBox(
        color: widget.palette.panelBackground,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_error!, textAlign: TextAlign.center),
          ),
        ),
      );
    }
    return ColoredBox(
      color: widget.palette.panelBackground,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          final homeTitleNarrow = MediaQuery.sizeOf(context).width < 600;
          final staffPane = _StaffListPane(
            palette: widget.palette,
            staff: _staff,
            teams: _teams,
            offices: _offices,
            onAdd: () => _openStaffForm(),
            onEdit: (person) => _openStaffForm(existing: person),
          );
          final teamPane = _TeamsPane(
            palette: widget.palette,
            teams: _teams,
            offices: _offices,
            onAdd: () => _editTeam(),
            onEdit: (team) => _editTeam(existing: team),
            onRemove: _removeTeam,
          );
          final managementPane = _ManagementPane(
            palette: widget.palette,
            staff: _staff,
            teams: _teams,
            offices: _offices,
            subordinateMode: _subordinateMode,
            focusId: _reportingStaffId,
            checked: _checkedReporting,
            locked: _peerIds(_impliedLinks, _reportingStaffId),
            saving: _savingLinks,
            changed: _managementChanged(),
            onMode: (subordinate) {
              setState(() {
                _reportingMode = subordinate
                    ? _ReportingMode.subordinate
                    : _ReportingMode.supervisor;
                _checkedReporting
                  ..clear()
                  ..addAll(_reportingPeersOf(_reportingStaffId));
              });
            },
            onFocus: (id) {
              setState(() {
                _reportingStaffId = id;
                _checkedReporting
                  ..clear()
                  ..addAll(_reportingPeersOf(id));
              });
            },
            onToggle: (id, selected) {
              if (_peerIds(_impliedLinks, _reportingStaffId).contains(id)) {
                return;
              }
              setState(() {
                if (selected) {
                  _checkedReporting.add(id);
                } else {
                  _checkedReporting.remove(id);
                }
              });
            },
            onSave: _saveLinks,
          );
          final desktopPanels = Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Column(
                  children: [
                    Expanded(child: staffPane),
                    const SizedBox(height: 12),
                    Expanded(child: teamPane),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(child: managementPane),
            ],
          );
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Text(
                  'People, Teams and Reportings',
                  style: asanaTextStyle(
                    Theme.of(context).textTheme.headlineMedium,
                    fontSize: homeTitleNarrow ? 22 : 32,
                    fontWeight: FontWeight.w700,
                    color: kAsanaTextPrimary,
                    height: 1.15,
                  ),
                  ),
                ),
                const SizedBox(height: 28),
                Expanded(
                  child: wide
                      ? desktopPanels
                      : LayoutBuilder(
                          builder: (context, paneConstraints) {
                            final share =
                                ((paneConstraints.maxHeight - 24) / 3)
                                    .clamp(0.0, double.infinity);
                            final topPaneHeight = share * 1.7;
                            return SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  SizedBox(
                                    height: topPaneHeight,
                                    child: staffPane,
                                  ),
                                  const SizedBox(height: 12),
                                  SizedBox(
                                    height: topPaneHeight,
                                    child: teamPane,
                                  ),
                                  const SizedBox(height: 12),
                                  SizedBox(
                                    height: topPaneHeight,
                                    child: managementPane,
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

TextStyle? _panelTitleStyle(BuildContext context) {
  return asanaTextStyle(
    Theme.of(context).textTheme.titleLarge,
    fontSize: 22,
    fontWeight: FontWeight.w700,
    color: kAsanaTextPrimary,
    height: 1.2,
  );
}

class _TeamsPane extends StatelessWidget {
  const _TeamsPane({
    required this.palette,
    required this.teams,
    required this.offices,
    required this.onAdd,
    required this.onEdit,
    required this.onRemove,
  });

  final AsanaLandingPalette palette;
  final List<_TeamRow> teams;
  final List<_OfficeRow> offices;
  final VoidCallback onAdd;
  final ValueChanged<_TeamRow> onEdit;
  final ValueChanged<_TeamRow> onRemove;

  @override
  Widget build(BuildContext context) {
    final nameStyle = asanaTableRowNameStyle(context);
    final valueStyle = asanaTableRowValueStyle(context);
    return AsanaPanelListSurface(
      palette: palette,
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Team',
                    style: _panelTitleStyle(context),
                  ),
                ),
                AsanaToolbarCreateButton(
                  label: 'Add team',
                  palette: palette,
                  onPressed: onAdd,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: teams.isEmpty
                ? Center(
                    child: Text(
                      'No teams',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.builder(
                    primary: false,
                    itemCount: teams.length,
                    itemBuilder: (context, index) {
                      final team = teams[index];
                      final office = offices
                          .where((o) => o.officeId == team.officeId)
                          .map((o) => o.officeName)
                          .firstOrNull;
                      return Material(
                        color: palette.tableColors.subtaskRow,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
                          child: Row(
                            children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Text(team.teamName, style: nameStyle),
                                        const SizedBox(height: 5),
                                        Text(office ?? '', style: valueStyle),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Modify team',
                                    onPressed: () => onEdit(team),
                                    icon: const Icon(
                                      Icons.edit_outlined,
                                      size: 18,
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Remove team',
                                    onPressed: () => onRemove(team),
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      size: 18,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                    },
                  ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StaffListPane extends StatelessWidget {
  const _StaffListPane({
    required this.palette,
    required this.staff,
    required this.teams,
    required this.offices,
    required this.onAdd,
    required this.onEdit,
  });

  final AsanaLandingPalette palette;
  final List<_StaffRow> staff;
  final List<_TeamRow> teams;
  final List<_OfficeRow> offices;
  final VoidCallback onAdd;
  final ValueChanged<_StaffRow> onEdit;

  String _officeName(_StaffRow person) {
    final id = (person.officeId ?? '').trim();
    for (final office in offices) {
      if (office.officeId == id && office.officeName.trim().isNotEmpty) {
        return office.officeName.trim();
      }
    }
    return id.isEmpty ? 'No office' : id;
  }

  String _teamName(_StaffRow person) {
    final key = (person.teamId ?? '').trim().toLowerCase();
    for (final team in teams) {
      if (team.teamId.trim().toLowerCase() == key &&
          team.teamName.trim().isNotEmpty) {
        return team.teamName.trim();
      }
    }
    return 'No team';
  }

  @override
  Widget build(BuildContext context) {
    final people = [...staff]..sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    final nameStyle = asanaTableRowNameStyle(context);
    final valueStyle = asanaTableRowValueStyle(context);
    return AsanaPanelListSurface(
      palette: palette,
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text('Staff', style: _panelTitleStyle(context)),
                ),
                AsanaToolbarCreateButton(
                  label: 'Add Staff',
                  palette: palette,
                  onPressed: onAdd,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: people.isEmpty
                ? Center(
                    child: Text(
                      'No staff',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.builder(
                    primary: false,
                    itemCount: people.length,
                    itemBuilder: (context, index) {
                      final person = people[index];
                      final meta = [
                        _officeName(person),
                        _teamName(person),
                        person.email,
                        person.active ? 'Active' : 'Inactive',
                      ].join(' · ');
                      return Material(
                        color: palette.tableColors.subtaskRow,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Text(person.name, style: nameStyle),
                                        const SizedBox(height: 5),
                                        Text(meta, style: valueStyle),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Modify staff',
                                    onPressed: () => onEdit(person),
                                    icon: const Icon(
                                      Icons.edit_outlined,
                                      size: 18,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                    },
                  ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ReportingModeButton extends StatelessWidget {
  const _ReportingModeButton({
    required this.palette,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final AsanaLandingPalette palette;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color background;
    final Color foreground;
    final BorderSide side;
    if (!selected && palette.id == 'Charcoal') {
      final wash = Color.alphaBlend(
        palette.accent.withValues(alpha: palette.darkChrome ? 0.18 : 0.12),
        palette.listSurface,
      );
      background = wash;
      foreground = kAsanaTextPrimary;
      side = BorderSide(color: palette.accent.withValues(alpha: 0.36));
    } else {
      background = selected ? palette.accent : palette.sidebar;
      foreground = selected ? palette.onBanner : palette.onSidebar;
      side = BorderSide(color: palette.accent, width: selected ? 0 : 1.5);
    }
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        minimumSize: const Size(0, 34),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        backgroundColor: background,
        foregroundColor: foreground,
        side: side,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: foreground,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
        ),
      ),
    );
  }
}

class _ManagementPane extends StatelessWidget {
  const _ManagementPane({
    required this.palette,
    required this.staff,
    required this.teams,
    required this.offices,
    required this.subordinateMode,
    required this.focusId,
    required this.checked,
    required this.locked,
    required this.saving,
    required this.changed,
    required this.onMode,
    required this.onFocus,
    required this.onToggle,
    required this.onSave,
  });

  final AsanaLandingPalette palette;
  final List<_StaffRow> staff;
  final List<_TeamRow> teams;
  final List<_OfficeRow> offices;
  final bool subordinateMode;
  final String? focusId;
  final Set<String> checked;
  final Set<String> locked;
  final bool saving;
  final bool changed;
  final ValueChanged<bool> onMode;
  final ValueChanged<String?> onFocus;
  final void Function(String id, bool selected) onToggle;
  final VoidCallback onSave;

  String _officeName(_StaffRow person) {
    final id = (person.officeId ?? '').trim();
    for (final office in offices) {
      if (office.officeId == id && office.officeName.trim().isNotEmpty) {
        return office.officeName.trim();
      }
    }
    return id.isEmpty ? 'No office' : id;
  }

  String _teamName(_StaffRow person) {
    final key = (person.teamId ?? '').trim().toLowerCase();
    for (final team in teams) {
      if (team.teamId.trim().toLowerCase() == key &&
          team.teamName.trim().isNotEmpty) {
        return team.teamName.trim();
      }
    }
    return 'No team';
  }

  @override
  Widget build(BuildContext context) {
    final people = [...staff]..sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    final related = [
      for (final person in people)
        if (person.id != focusId) person,
    ];
    final selected = people.where((person) => person.id == focusId);
    final focusLabel = selected.isEmpty
        ? (subordinateMode ? 'Choose subordinate' : 'Choose supervisor')
        : selected.first.name;
    final relatedCount = related
        .where(
          (person) =>
              checked.contains(person.id) || locked.contains(person.id),
        )
        .length;
    final relatedLabel = subordinateMode
        ? (relatedCount == 1 ? '1 supervisor' : '$relatedCount supervisors')
        : (relatedCount == 1
              ? '1 subordinate'
              : '$relatedCount subordinates');
    final nameStyle = asanaTableRowNameStyle(context);
    final valueStyle = asanaTableRowValueStyle(context);
    return AsanaPanelListSurface(
      palette: palette,
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Reporting',
                    style: _panelTitleStyle(context),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _ReportingModeButton(
                  palette: palette,
                  label: 'Supervisor',
                  selected: !subordinateMode,
                  onTap: () {
                    if (!subordinateMode) return;
                    onMode(false);
                  },
                ),
                const SizedBox(width: 8),
                _ReportingModeButton(
                  palette: palette,
                  label: 'Subordinate',
                  selected: subordinateMode,
                  onTap: () {
                    if (subordinateMode) return;
                    onMode(true);
                  },
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            return AsanaFilterDropdown(
                              title: subordinateMode
                                  ? 'Subordinate'
                                  : 'Supervisor',
                              value: focusLabel,
                              buttonWidth: (constraints.maxWidth - 12).clamp(
                                120.0,
                                double.infinity,
                              ),
                              enabled: people.isNotEmpty,
                              onPressed: (buttonContext) async {
                                final selection =
                                    await showAsanaCheckboxFilterPanel(
                                      anchorContext: buttonContext,
                                      singleSelect: true,
                                      options: [
                                        for (final person in people)
                                          AsanaFilterCheckboxOption(
                                            key: person.id,
                                            label: person.name,
                                          ),
                                      ],
                                      initialSelection: {
                                        if (selected.isNotEmpty) focusId!,
                                      },
                                    );
                                if (selection == null || selection.isEmpty) {
                                  return;
                                }
                                onFocus(selection.first);
                              },
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: saving || focusId == null || !changed
                            ? null
                            : onSave,
                        style: FilledButton.styleFrom(
                          backgroundColor: palette.accent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text(saving ? 'Saving' : 'Save'),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                  child: Text(
                    relatedLabel,
                    style: asanaTextStyle(
                      Theme.of(context).textTheme.bodyMedium,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: kAsanaTextPrimary,
                    ),
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                    child: related.isEmpty
                        ? Center(
                            child: Text(
                              'No staff',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyLarge
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          )
                        : ListView.builder(
                            primary: false,
                            itemCount: related.length,
                            itemBuilder: (context, index) {
                              final person = related[index];
                              final includedByOffice = locked.contains(
                                person.id,
                              );
                              final isChecked =
                                  checked.contains(person.id) ||
                                  includedByOffice;
                              final meta = [
                                _officeName(person),
                                _teamName(person),
                                person.email,
                                person.active ? 'Active' : 'Inactive',
                              ].join(' · ');
                              return Material(
                                color: palette.tableColors.subtaskRow,
                                child: InkWell(
                                  onTap: includedByOffice
                                      ? null
                                      : () => onToggle(person.id, !isChecked),
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      4,
                                      2,
                                      14,
                                      2,
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        Checkbox(
                                          value: isChecked,
                                          visualDensity: VisualDensity.compact,
                                          materialTapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                          onChanged: includedByOffice
                                              ? null
                                              : (value) => onToggle(
                                                  person.id,
                                                  value == true,
                                                ),
                                        ),
                                        Expanded(
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 8,
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.stretch,
                                              children: [
                                                Text(
                                                  person.name,
                                                  style: nameStyle,
                                                ),
                                                const SizedBox(height: 5),
                                                Text(meta, style: valueStyle),
                                              ],
                                            ),
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StaffFormDialog extends StatefulWidget {
  const _StaffFormDialog({
    required this.palette,
    required this.teams,
    required this.offices,
    required this.onSubmit,
    this.existing,
  });

  final AsanaLandingPalette palette;
  final List<_TeamRow> teams;
  final List<_OfficeRow> offices;
  final _StaffRow? existing;
  final Future<void> Function(Map<String, dynamic> body) onSubmit;

  @override
  State<_StaffFormDialog> createState() => _StaffFormDialogState();
}

class _StaffFormDialogState extends State<_StaffFormDialog> {
  late final TextEditingController _email;
  late final TextEditingController _name;
  String? _officeId;
  String? _teamId;
  bool _active = true;
  String? _dismissedName;
  String? _formError;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _email = TextEditingController(text: existing?.email ?? '');
    _name = TextEditingController(text: existing?.name ?? '');
    _active = existing?.active ?? true;
    final currentTeam = existing?.teamId?.trim().toLowerCase();
    _TeamRow? team;
    for (final item in widget.teams) {
      if (item.teamId.trim().toLowerCase() == currentTeam) {
        team = item;
        break;
      }
    }
    _officeId = team?.officeId ?? existing?.officeId;
    if (_officeId == null ||
        !widget.offices.any((office) => office.officeId == _officeId)) {
      _officeId = widget.offices.isEmpty ? null : widget.offices.first.officeId;
    }
    final officeTeams = _teamsForOffice(_officeId);
    _teamId = officeTeams.any((item) => item.teamId == team?.teamId)
        ? team?.teamId
        : (officeTeams.isEmpty ? null : officeTeams.first.teamId);
  }

  @override
  void dispose() {
    _email.dispose();
    _name.dispose();
    super.dispose();
  }

  List<_TeamRow> _teamsForOffice(String? officeId) {
    return [
      for (final team in widget.teams)
        if (team.officeId == officeId) team,
    ];
  }

  String? get _suggestion {
    final suggested = suggestedStaffName(_name.text);
    if (suggested == null || _dismissedName == _name.text) return null;
    return suggested;
  }

  String _officeLabel() {
    for (final office in widget.offices) {
      if (office.officeId == _officeId) return office.officeName;
    }
    return 'Choose office';
  }

  String _teamLabel() {
    for (final team in _teamsForOffice(_officeId)) {
      if (team.teamId == _teamId) return team.teamName;
    }
    return 'Choose team';
  }

  Future<void> _pickOffice(BuildContext buttonContext) async {
    final selection = await showAsanaCheckboxFilterPanel(
      anchorContext: buttonContext,
      options: [
        for (final office in widget.offices)
          AsanaFilterCheckboxOption(
            key: office.officeId,
            label: office.officeName,
          ),
      ],
      initialSelection: {?_officeId},
      singleSelect: true,
    );
    if (!mounted || selection == null || selection.isEmpty) return;
    final next = selection.length == 1
        ? selection.first
        : selection.firstWhere(
            (id) => id != _officeId,
            orElse: () => selection.first,
          );
    setState(() {
      _officeId = next;
      final teams = _teamsForOffice(next);
      if (!teams.any((team) => team.teamId == _teamId)) {
        _teamId = teams.isEmpty ? null : teams.first.teamId;
      }
    });
  }

  Future<void> _pickTeam(BuildContext buttonContext) async {
    final teams = _teamsForOffice(_officeId);
    final selection = await showAsanaCheckboxFilterPanel(
      anchorContext: buttonContext,
      options: [
        for (final team in teams)
          AsanaFilterCheckboxOption(key: team.teamId, label: team.teamName),
      ],
      initialSelection: {?_teamId},
      singleSelect: true,
    );
    if (!mounted || selection == null || selection.isEmpty) return;
    final next = selection.length == 1
        ? selection.first
        : selection.firstWhere((id) => id != _teamId, orElse: () => selection.first);
    setState(() => _teamId = next);
  }

  Future<void> _save() async {
    final emailError = staffEmailError(_email.text);
    if (emailError != null) {
      setState(() => _formError = emailError);
      return;
    }
    if (_name.text.trim().isEmpty) {
      setState(() => _formError = 'Name is required.');
      return;
    }
    if (_teamId == null || _teamId!.isEmpty) {
      setState(() => _formError = 'Choose a team.');
      return;
    }
    setState(() {
      _saving = true;
      _formError = null;
    });
    try {
      await widget.onSubmit({
        'email': _email.text.trim().toLowerCase(),
        'name': _name.text.trim(),
        'teamId': _teamId,
        'active': _active,
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _formError = e.toString().replaceFirst('Exception: ', '');
      });
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Widget _fieldLabel(String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        fontWeight: FontWeight.w600,
        color: kAsanaTextSecondary,
        fontSize: 11,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AsanaTaskAiColors.fromPalette(widget.palette);
    final suggestion = _suggestion;
    final titleStyle = asanaTextStyle(
      theme.textTheme.titleMedium,
      fontSize: 18,
      fontWeight: FontWeight.w600,
      color: kAsanaTextPrimary,
    );
    final screenWidth = MediaQuery.sizeOf(context).width;
    final dialogWidth = screenWidth < 488 ? screenWidth - 48 : 440.0;
    return Dialog(
      backgroundColor: widget.palette.panelBackground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0xFFEDEAE9), width: 1),
      ),
      elevation: 12,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: dialogWidth,
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: SingleChildScrollView(
          child: Container(
            width: dialogWidth,
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.existing == null ? 'Add staff' : 'Modify staff',
                  style: titleStyle,
                ),
                const SizedBox(height: 16),
                _fieldLabel('Staff name'),
                const SizedBox(height: 4),
                TextField(
                  controller: _name,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                if (suggestion != null) ...[
                  const SizedBox(height: 8),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.boxBackground,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: colors.boxBorder),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              suggestion,
                              style: asanaTextStyle(
                                theme.textTheme.bodyMedium,
                                fontWeight: FontWeight.w600,
                                color: colors.suggestedLabel,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Dismiss suggestion',
                            onPressed: () =>
                                setState(() => _dismissedName = _name.text),
                            icon: const Icon(Icons.cancel_outlined, size: 20),
                            color: const Color(0xFFC62828),
                          ),
                          IconButton(
                            tooltip: 'Apply this suggestion',
                            onPressed: () {
                              _name.text = suggestion;
                              _name.selection = TextSelection.collapsed(
                                offset: suggestion.length,
                              );
                              setState(() => _dismissedName = null);
                            },
                            icon: const Icon(
                              Icons.check_circle_outline,
                              size: 20,
                            ),
                            color: colors.adoptIcon,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                AsanaFilterDropdown(
                  title: 'Office',
                  value: _officeLabel(),
                  buttonWidth: dialogWidth - 60,
                  enabled: widget.offices.isNotEmpty,
                  onPressed: _pickOffice,
                ),
                const SizedBox(height: 16),
                AsanaFilterDropdown(
                  title: 'Team',
                  value: _teamLabel(),
                  buttonWidth: dialogWidth - 60,
                  enabled: _teamsForOffice(_officeId).isNotEmpty,
                  onPressed: _pickTeam,
                ),
                const SizedBox(height: 16),
                _fieldLabel('Email'),
                const SizedBox(height: 4),
                TextField(
                  controller: _email,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '@hku.hk, and the name before @ is at most 8 characters',
                    textAlign: TextAlign.left,
                    style: asanaTextStyle(
                      theme.textTheme.bodySmall,
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: kAsanaTextSecondary,
                      height: 1.35,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Transform.translate(
                  offset: const Offset(-15, 0),
                  child: Row(
                    children: [
                      Checkbox(
                        value: _active,
                        materialTapTargetSize: MaterialTapTargetSize.padded,
                        onChanged: _saving
                            ? null
                            : (value) =>
                                  setState(() => _active = value ?? false),
                      ),
                      const Text('Active'),
                    ],
                  ),
                ),
                if (_formError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _formError!,
                    style: asanaTextStyle(
                      theme.textTheme.bodyMedium,
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: const Color(0xFFC62828),
                      height: 1.4,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pop(false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: kAsanaTextPrimary,
                        side: const BorderSide(color: Color(0xFFEDEAE9)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      style: FilledButton.styleFrom(
                        backgroundColor: widget.palette.accent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      child: Text(
                        _saving
                            ? 'Saving'
                            : widget.existing == null
                            ? 'Add'
                            : 'Modify',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TeamFormDialog extends StatefulWidget {
  const _TeamFormDialog({
    required this.palette,
    required this.offices,
    required this.teams,
    required this.affectedStaff,
    required this.onSubmit,
    this.existing,
  });

  final AsanaLandingPalette palette;
  final List<_OfficeRow> offices;
  final List<_TeamRow> teams;
  final List<_StaffRow> affectedStaff;
  final _TeamRow? existing;
  final Future<({Map<String, dynamic>? data, String? error})> Function(
    Map<String, dynamic> body,
  )
  onSubmit;

  @override
  State<_TeamFormDialog> createState() => _TeamFormDialogState();
}

class _TeamFormDialogState extends State<_TeamFormDialog> {
  late final TextEditingController _teamName;
  String? _officeId;
  String? _formError;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _teamName = TextEditingController(text: existing?.teamName ?? '');
    _officeId = existing?.officeId;
    _officeId ??= widget.offices.isEmpty ? null : widget.offices.first.officeId;
  }

  @override
  void dispose() {
    _teamName.dispose();
    super.dispose();
  }

  String _newTeamId(String name) {
    var base = name
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    if (base.isEmpty) base = 'team';
    if (base.length > 40) base = base.substring(0, 40);
    final taken = widget.teams.map((team) => team.teamId.toLowerCase()).toSet();
    var candidate = base;
    var n = 2;
    while (taken.contains(candidate)) {
      candidate = '${base}_$n';
      n++;
    }
    return candidate;
  }

  Future<void> _save() async {
    final teamName = _teamName.text.trim();
    final teamId = widget.existing?.teamId ?? _newTeamId(teamName);
    if (teamName.isEmpty || _officeId == null || teamId.isEmpty) {
      setState(() => _formError = 'Team name and office are required.');
      return;
    }
    if (widget.existing != null) {
      final count = widget.affectedStaff.length;
      final ok = await showAsanaConfirmDialog(
        context: context,
        title: 'Update staff on this team?',
        content: count == 0
            ? 'Saving this team also updates staff records that use it. None use it yet.'
            : 'Saving this team also updates staff records that use it. $count staff are in ${widget.existing!.teamName}. If the office changes, those staff move with the team.',
        confirmText: 'Modify',
        palette: widget.palette,
      );
      if (ok != true || !mounted) return;
    }
    setState(() {
      _saving = true;
      _formError = null;
    });
    final result = await widget.onSubmit({
      'teamId': teamId,
      'teamName': teamName,
      'officeId': _officeId,
    });
    if (!mounted) return;
    if (result.error != null) {
      setState(() {
        _saving = false;
        _formError = result.error;
      });
      return;
    }
    Navigator.of(context).pop(true);
  }

  String _officeLabel() {
    for (final office in widget.offices) {
      if (office.officeId == _officeId) return office.officeName;
    }
    return 'Choose office';
  }

  Future<void> _pickOffice(BuildContext buttonContext) async {
    final selection = await showAsanaCheckboxFilterPanel(
      anchorContext: buttonContext,
      options: [
        for (final office in widget.offices)
          AsanaFilterCheckboxOption(
            key: office.officeId,
            label: office.officeName,
          ),
      ],
      initialSelection: {?_officeId},
      singleSelect: true,
    );
    if (!mounted || selection == null || selection.isEmpty) return;
    final next = selection.length == 1
        ? selection.first
        : selection.firstWhere(
            (id) => id != _officeId,
            orElse: () => selection.first,
          );
    setState(() => _officeId = next);
  }

  Widget _fieldLabel(String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        fontWeight: FontWeight.w600,
        color: kAsanaTextSecondary,
        fontSize: 11,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleStyle = asanaTextStyle(
      theme.textTheme.titleMedium,
      fontSize: 18,
      fontWeight: FontWeight.w600,
      color: kAsanaTextPrimary,
    );
    final screenWidth = MediaQuery.sizeOf(context).width;
    final dialogWidth = screenWidth < 488 ? screenWidth - 48 : 440.0;
    return Dialog(
      backgroundColor: widget.palette.panelBackground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0xFFEDEAE9), width: 1),
      ),
      elevation: 12,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: dialogWidth,
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: SingleChildScrollView(
          child: Container(
            width: dialogWidth,
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.existing == null ? 'Add team' : 'Modify team',
                  style: titleStyle,
                ),
                const SizedBox(height: 16),
                _fieldLabel('Team name'),
                const SizedBox(height: 4),
                TextField(
                  controller: _teamName,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                AsanaFilterDropdown(
                  title: 'Office',
                  value: _officeLabel(),
                  buttonWidth: dialogWidth - 60,
                  enabled: widget.offices.isNotEmpty,
                  onPressed: _pickOffice,
                ),
            if (_formError != null) ...[
              const SizedBox(height: 12),
              Text(
                _formError!,
                style: asanaTextStyle(
                  theme.textTheme.bodyMedium,
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: const Color(0xFFC62828),
                  height: 1.4,
                ),
              ),
            ],
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: _saving
                      ? null
                      : () => Navigator.of(context).pop(false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: kAsanaTextPrimary,
                    side: const BorderSide(color: Color(0xFFEDEAE9)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: widget.palette.accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  child: Text(
                    _saving
                        ? 'Saving'
                        : widget.existing == null
                        ? 'Add'
                        : 'Modify',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
        ),
      ),
    );
  }
}
