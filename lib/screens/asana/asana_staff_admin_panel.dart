import 'package:flutter/material.dart';

import '../../config/dev_auth_context.dart';
import '../../services/backend_api.dart';
import '../asana_landing_screen.dart';
import 'asana_detail_widgets.dart';
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

String _teamDisplayName(
  _TeamRow team,
  List<_TeamRow> teams,
  List<_OfficeRow> offices,
) {
  final name = team.teamName.trim().isEmpty ? 'Team' : team.teamName.trim();
  final sameName = teams
      .where((other) => other.teamName.trim().toLowerCase() == name.toLowerCase())
      .length;
  if (sameName < 2) return name;
  final office = offices
      .where((item) => item.officeId == team.officeId)
      .map((item) => item.officeName)
      .firstOrNull;
  if (office == null || office.isEmpty) return name;
  return '$name ($office)';
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
    required this.active,
  });

  final String id;
  final String name;
  final String email;
  final String? teamId;
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

class AsanaStaffAdminPanel extends StatefulWidget {
  const AsanaStaffAdminPanel({super.key, required this.palette});

  final AsanaLandingPalette palette;

  @override
  State<AsanaStaffAdminPanel> createState() => _AsanaStaffAdminPanelState();
}

class _AsanaStaffAdminPanelState extends State<AsanaStaffAdminPanel> {
  bool _loading = true;
  String? _error;
  String _role = '';
  List<_OfficeRow> _offices = const [];
  List<_TeamRow> _teams = const [];
  List<_StaffRow> _staff = const [];
  List<_LinkRow> _links = const [];
  List<_LinkRow> _impliedLinks = const [];
  String? _supervisorId;
  final Set<String> _checkedSubordinates = {};
  bool _savingLinks = false;
  _StaffRow? _editingStaff;
  int _staffFormToken = 0;

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
      return (data: null, error: 'Sign in again to use Staff.');
    }
    return BackendApi().staffAdminRequest(
      idToken: token,
      method: method,
      path: path,
      body: body,
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await _request('GET', '/api/staff-admin/context');
    if (!mounted) return;
    if (result.error != null || result.data == null) {
      setState(() {
        _loading = false;
        _error = result.error ?? 'Could not load Staff.';
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
    final previous = _supervisorId;
    final supervisor = staff.any((s) => s.id == previous)
        ? previous
        : (staff.isEmpty ? null : staff.first.id);
    setState(() {
      _loading = false;
      _role = data['role']?.toString() ?? '';
      _offices = offices;
      _teams = teams;
      _staff = staff;
      _links = links;
      _impliedLinks = impliedLinks;
      _supervisorId = supervisor;
      _checkedSubordinates
        ..clear()
        ..addAll(_subordinatesOf(supervisor));
    });
  }

  Set<String> _idsFor(List<_LinkRow> rows, String? supervisorId) {
    if (supervisorId == null) return {};
    return {
      for (final link in rows)
        if (link.supervisorStaffId == supervisorId) link.subordinateStaffId,
    };
  }

  Set<String> _subordinatesOf(String? supervisorId) {
    return {
      ..._idsFor(_links, supervisorId),
      ..._idsFor(_impliedLinks, supervisorId),
    };
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
      title: 'Staff',
      content: message,
      palette: widget.palette,
    );
  }

  Future<void> _saveLinks() async {
    final supervisorId = _supervisorId;
    if (supervisorId == null) return;
    setState(() => _savingLinks = true);
    final result = await _request(
      'PUT',
      '/api/staff-admin/subordinates',
      body: {
        'supervisorStaffId': supervisorId,
        'subordinateStaffIds': _checkedSubordinates
            .where((id) => !_idsFor(_impliedLinks, supervisorId).contains(id))
            .toList(),
      },
    );
    if (!mounted) return;
    setState(() => _savingLinks = false);
    if (result.error != null) {
      await _showError(result.error!);
      return;
    }
    await _load();
  }

  Future<void> _submitStaff(Map<String, dynamic> body) async {
    final existing = _editingStaff;
    final result = await _request(
      existing == null ? 'POST' : 'PATCH',
      existing == null
          ? '/api/staff-admin/staff'
          : '/api/staff-admin/staff/${existing.id}',
      body: body,
    );
    if (result.error != null) {
      throw result.error!;
    }
    if (!mounted) return;
    setState(() {
      _editingStaff = null;
      _staffFormToken++;
    });
    await _load();
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
    final wide = MediaQuery.sizeOf(context).width >= 980;
    final teamsPane = _TeamsPane(
      palette: widget.palette,
      teams: _teams,
      offices: _offices,
      onAdd: () => _editTeam(),
      onEdit: (team) => _editTeam(existing: team),
      onRemove: _removeTeam,
    );
    final staffPane = _StaffPane(
      palette: widget.palette,
      staff: _staff,
      teams: _teams,
      offices: _offices,
      supervisorId: _supervisorId,
      checked: _checkedSubordinates,
      locked: _idsFor(_impliedLinks, _supervisorId),
      saving: _savingLinks,
      onEdit: (person) {
        setState(() {
          _editingStaff = person;
          _staffFormToken++;
        });
      },
      onSupervisor: (id) {
        setState(() {
          _supervisorId = id;
          _checkedSubordinates
            ..clear()
            ..addAll(_subordinatesOf(id));
        });
      },
      onToggle: (id, selected) {
        if (_idsFor(_impliedLinks, _supervisorId).contains(id)) return;
        setState(() {
          if (selected) {
            _checkedSubordinates.add(id);
          } else {
            _checkedSubordinates.remove(id);
          }
        });
      },
      onSave: _saveLinks,
    );
    final scope = _role == 'super_admin'
        ? 'Super admin. All offices.'
        : 'Office admin. ${_offices.map((o) => o.officeName).join(', ')}.';
    return ColoredBox(
      color: widget.palette.panelBackground,
      child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Staff',
            style: asanaTextStyle(
              Theme.of(context).textTheme.titleLarge,
              fontWeight: FontWeight.w700,
              color: kAsanaTextPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            scope,
            style: asanaTextStyle(
              Theme.of(context).textTheme.bodyMedium,
              color: kAsanaTextSecondary,
            ),
          ),
          const SizedBox(height: 16),
          _StaffFormBlock(
            key: ValueKey('${_editingStaff?.id ?? 'new'}-$_staffFormToken'),
            palette: widget.palette,
            teams: _teams,
            offices: _offices,
            existing: _editingStaff,
            onSubmit: _submitStaff,
            onCancelEdit: _editingStaff == null
                ? null
                : () => setState(() {
                    _editingStaff = null;
                    _staffFormToken++;
                  }),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 2, child: teamsPane),
                      const SizedBox(width: 16),
                      Expanded(flex: 3, child: staffPane),
                    ],
                  )
                : Column(
                    children: [
                      Expanded(child: teamsPane),
                      const SizedBox(height: 16),
                      Expanded(child: staffPane),
                    ],
                  ),
          ),
        ],
      ),
      ),
    );
  }
}

class _PaneCard extends StatelessWidget {
  const _PaneCard({required this.palette, required this.child});

  final AsanaLandingPalette palette;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: palette.listSurface,
      elevation: 0,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
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
    return _PaneCard(
      palette: palette,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Teams',
                    style: asanaTextStyle(
                      Theme.of(context).textTheme.titleMedium,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add team'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              itemCount: teams.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final team = teams[index];
                final office = offices
                    .where((o) => o.officeId == team.officeId)
                    .map((o) => o.officeName)
                    .firstOrNull;
                return ListTile(
                  title: Text(team.teamName),
                  subtitle: Text(office ?? ''),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Modify team',
                        onPressed: () => onEdit(team),
                        icon: const Icon(Icons.edit_outlined, size: 18),
                      ),
                      IconButton(
                        tooltip: 'Remove team',
                        onPressed: () => onRemove(team),
                        icon: const Icon(Icons.delete_outline, size: 18),
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
  }
}

class _StaffPane extends StatelessWidget {
  const _StaffPane({
    required this.palette,
    required this.staff,
    required this.teams,
    required this.offices,
    required this.supervisorId,
    required this.checked,
    required this.locked,
    required this.saving,
    required this.onEdit,
    required this.onSupervisor,
    required this.onToggle,
    required this.onSave,
  });

  final AsanaLandingPalette palette;
  final List<_StaffRow> staff;
  final List<_TeamRow> teams;
  final List<_OfficeRow> offices;
  final String? supervisorId;
  final Set<String> checked;
  final Set<String> locked;
  final bool saving;
  final ValueChanged<_StaffRow> onEdit;
  final ValueChanged<String?> onSupervisor;
  final void Function(String id, bool selected) onToggle;
  final VoidCallback onSave;

  String _teamLabel(String? teamId) {
    final key = (teamId ?? '').trim().toLowerCase();
    for (final team in teams) {
      if (team.teamId.trim().toLowerCase() == key) {
        return _teamDisplayName(team, teams, offices);
      }
    }
    return 'No team';
  }

  @override
  Widget build(BuildContext context) {
    return _PaneCard(
      palette: palette,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Text(
              'Staff',
              style: asanaTextStyle(
                Theme.of(context).textTheme.titleMedium,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    key: ValueKey(supervisorId),
                    initialValue: staff.any((s) => s.id == supervisorId)
                        ? supervisorId
                        : null,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Supervisor',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final person in staff)
                        DropdownMenuItem(
                          value: person.id,
                          child: Text(person.name, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: onSupervisor,
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: saving || supervisorId == null ? null : onSave,
                  child: Text(saving ? 'Saving' : 'Save links'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: Text(
              'Checked staff report to the supervisor above. An office admin only sees staff in that office. Staff stay checked when their office names this supervisor\'s office as its boss.',
              style: asanaTextStyle(
                Theme.of(context).textTheme.bodySmall,
                color: kAsanaTextSecondary,
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              itemCount: staff.length,
              itemBuilder: (context, index) {
                final person = staff[index];
                final isSupervisor = person.id == supervisorId;
                final includedByOffice = locked.contains(person.id);
                return CheckboxListTile(
                  value: checked.contains(person.id) || includedByOffice,
                  onChanged: isSupervisor || includedByOffice
                      ? null
                      : (value) => onToggle(person.id, value == true),
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(person.name),
                  subtitle: Text(
                    '${person.email} · ${_teamLabel(person.teamId)} · ${person.active ? 'Active' : 'Inactive'}'
                    '${includedByOffice ? ' · Included by office' : ''}',
                  ),
                  secondary: IconButton(
                    tooltip: 'Modify staff',
                    onPressed: () => onEdit(person),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _StaffFormBlock extends StatefulWidget {
  const _StaffFormBlock({
    super.key,
    required this.palette,
    required this.teams,
    required this.offices,
    required this.onSubmit,
    this.existing,
    this.onCancelEdit,
  });

  final AsanaLandingPalette palette;
  final List<_TeamRow> teams;
  final List<_OfficeRow> offices;
  final _StaffRow? existing;
  final Future<void> Function(Map<String, dynamic> body) onSubmit;
  final VoidCallback? onCancelEdit;

  @override
  State<_StaffFormBlock> createState() => _StaffFormBlockState();
}

class _StaffFormBlockState extends State<_StaffFormBlock> {
  late final TextEditingController _email;
  late final TextEditingController _name;
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
    _teamId = widget.teams
        .where((t) => t.teamId.trim().toLowerCase() == currentTeam)
        .map((t) => t.teamId)
        .firstOrNull;
    _teamId ??= widget.teams.isEmpty ? null : widget.teams.first.teamId;
  }

  @override
  void dispose() {
    _email.dispose();
    _name.dispose();
    super.dispose();
  }

  String? get _suggestion {
    final suggested = suggestedStaffName(_name.text);
    if (suggested == null || _dismissedName == _name.text) return null;
    return suggested;
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
    setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AsanaTaskAiColors.fromPalette(widget.palette);
    final suggestion = _suggestion;
    final wide = MediaQuery.sizeOf(context).width >= 980;
    final fields = [
      TextField(
        controller: _email,
        decoration: const InputDecoration(
          labelText: 'Email',
          helperText: '@hku.hk, and the name before @ is at most 8 characters',
          isDense: true,
          border: OutlineInputBorder(),
        ),
      ),
      TextField(
        controller: _name,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(
          labelText: 'Name',
          isDense: true,
          border: OutlineInputBorder(),
        ),
      ),
      DropdownButtonFormField<String>(
        initialValue: _teamId,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Team',
          isDense: true,
          border: OutlineInputBorder(),
        ),
        items: [
          for (final team in widget.teams)
            DropdownMenuItem(
              value: team.teamId,
              child: Text(
                _teamDisplayName(team, widget.teams, widget.offices),
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: (value) => setState(() => _teamId = value),
      ),
      DropdownButtonFormField<bool>(
        initialValue: _active,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Sign-in',
          isDense: true,
          border: OutlineInputBorder(),
        ),
        items: const [
          DropdownMenuItem(value: true, child: Text('Active')),
          DropdownMenuItem(value: false, child: Text('Inactive')),
        ],
        onChanged: (value) => setState(() => _active = value ?? true),
      ),
    ];
    return _PaneCard(
      palette: widget.palette,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.existing == null ? 'Add staff' : 'Modify staff',
              style: asanaTextStyle(
                Theme.of(context).textTheme.titleMedium,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < fields.length; i++) ...[
                    if (i > 0) const SizedBox(width: 12),
                    Expanded(child: fields[i]),
                  ],
                ],
              )
            else
              for (var i = 0; i < fields.length; i++) ...[
                if (i > 0) const SizedBox(height: 12),
                fields[i],
              ],
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
                            Theme.of(context).textTheme.bodyMedium,
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
                        icon: const Icon(Icons.check_circle_outline, size: 20),
                        color: colors.adoptIcon,
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (_formError != null) ...[
              const SizedBox(height: 12),
              Text(
                _formError!,
                style: const TextStyle(color: Color(0xFFC62828)),
              ),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.onCancelEdit != null) ...[
                    TextButton(
                      onPressed: _saving ? null : widget.onCancelEdit,
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                  ],
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: Text(_saving ? 'Saving' : 'Save'),
                  ),
                ],
              ),
            ),
          ],
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
        confirmText: 'Save team',
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleStyle = asanaTextStyle(
      theme.textTheme.titleMedium,
      fontSize: 18,
      fontWeight: FontWeight.w600,
      color: kAsanaTextPrimary,
    );
    return Dialog(
      backgroundColor: widget.palette.panelBackground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0xFFEDEAE9), width: 1),
      ),
      elevation: 12,
      child: Container(
        width: 440,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.existing == null ? 'Add team' : 'Modify team',
              style: titleStyle,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _teamName,
              decoration: const InputDecoration(labelText: 'Team name'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: widget.offices.any((o) => o.officeId == _officeId)
                  ? _officeId
                  : null,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Office'),
              items: [
                for (final office in widget.offices)
                  DropdownMenuItem(
                    value: office.officeId,
                    child: Text(office.officeName),
                  ),
              ],
              onChanged: widget.offices.length < 2
                  ? null
                  : (value) => setState(() => _officeId = value),
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
                  child: Text(_saving ? 'Saving' : 'Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
