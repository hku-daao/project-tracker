import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../models/forum.dart';
import '../../services/database_service.dart';
import '../../services/llm_service.dart';
import '../../utils/hk_time.dart';
import '../asana_landing_screen.dart';
import 'asana_detail_widgets.dart'
    show
        AsanaTaskDetailActionStyles,
        AsanaDetailLabelValue,
        AsanaDetailSlideFooter,
        AsanaDetailSlideScaffold,
        AsanaDetailTwoColumnRow,
        AsanaHoverTextField,
        AsanaHoverTapValue,
        asanaDetailLabelStyle,
        asanaDetailMultilineValueStyle,
        asanaDetailTitleStyle,
        asanaDetailValueStyle;
import 'asana_filter_widgets.dart';
import 'asana_inline_image_widgets.dart';
import 'asana_task_ai_assistant.dart' show AsanaTaskAiColors;
import 'asana_theme.dart';
import 'asana_value_chips.dart';

class AsanaDiscussionPanel extends StatefulWidget {
  const AsanaDiscussionPanel({
    super.key,
    required this.palette,
    required this.searchQuery,
    this.refreshToken = 0,
    this.onCreatePost,
  });

  final AsanaLandingPalette palette;
  final String searchQuery;
  final int refreshToken;
  final VoidCallback? onCreatePost;

  @override
  State<AsanaDiscussionPanel> createState() => _AsanaDiscussionPanelState();
}

class _AsanaDiscussionPanelState extends State<AsanaDiscussionPanel> {
  static const List<String> _categories = [
    'General',
    'Announcement',
    'Suggestion',
    'Feature idea',
    'Bug report',
  ];

  bool _loading = true;
  bool _postsLoading = false;
  String? _error;
  List<ForumThread> _threads = [];
  List<ForumPost> _posts = [];
  Map<String, List<InlineAttachmentRow>> _postInlineImages = {};
  Map<String, String> _staffTeamNameByKey = {};
  Map<String, String> _staffOfficeNameByKey = {};
  final _replyController = TextEditingController();
  final _replyAiPromptController = TextEditingController();
  String? _selectedThreadId;
  String? _replyingToPostId;
  Set<String> _categoryFilters = {};
  Set<String> _statusFilters = {};
  Set<String> _creatorTeamFilters = {};
  Set<String> _creatorNameFilters = {};
  String _sortKey = 'created';
  bool _sortAscending = false;
  bool _mobileThreadDetailOpen = false;
  bool _replySaving = false;
  bool _replyAiBusy = false;
  String? _replyAiMessage;
  String? _replyAiSuggestedDraft;
  ForumPost? _editingPost;
  bool _editSaving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadThreads();
      _loadStaffMetadata();
    });
  }

  Future<void> _loadStaffMetadata() async {
    try {
      final data = await DatabaseService.fetchStaffAssigneePickerData();
      if (!mounted) return;
      final teamNameById = {
        for (final team in data.teams)
          team.teamId.trim().toLowerCase(): team.teamName.trim(),
      };
      final officeNameById = {
        for (final office in data.offices)
          office.officeId.trim().toLowerCase(): office.officeName.trim(),
      };
      final teamByKey = <String, String>{};
      final officeByKey = <String, String>{};
      for (final staff in data.staff) {
        final keys = [
          staff.assigneeId.trim().toLowerCase(),
          if (staff.staffUuid?.trim().isNotEmpty == true)
            staff.staffUuid!.trim().toLowerCase(),
        ].where((k) => k.isNotEmpty);
        final teamId = staff.teamId?.trim().toLowerCase();
        final teamName = teamId == null ? null : teamNameById[teamId];
        final officeId = staff.officeId?.trim().toLowerCase();
        final officeName = officeId == null ? null : officeNameById[officeId];
        for (final key in keys) {
          if (teamName != null && teamName.isNotEmpty) {
            teamByKey[key] = teamName;
          }
          if (officeName != null && officeName.isNotEmpty) {
            officeByKey[key] = officeName;
          }
        }
      }
      setState(() {
        _staffTeamNameByKey = teamByKey;
        _staffOfficeNameByKey = officeByKey;
      });
    } catch (_) {
      // Author metadata is optional; discussion content can render without it.
    }
  }

  String _authorTeamOfficeLabel(String? staffKey) {
    final key = staffKey?.trim().toLowerCase();
    if (key == null || key.isEmpty) return '';
    final team = _staffTeamNameByKey[key];
    final office = _staffOfficeNameByKey[key];
    if (team != null &&
        team.isNotEmpty &&
        office != null &&
        office.isNotEmpty) {
      return '$team - $office';
    }
    if (team != null && team.isNotEmpty) return team;
    if (office != null && office.isNotEmpty) return office;
    return '';
  }

  @override
  void dispose() {
    _replyController.dispose();
    _replyAiPromptController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant AsanaDiscussionPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) {
      _loadThreads(preferFirst: true);
    } else if (oldWidget.searchQuery != widget.searchQuery) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _selectFirstFilteredThread();
      });
    }
  }

  Future<void> _loadThreads({
    String? selectThreadId,
    bool preferFirst = false,
  }) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final state = context.read<AppState>();
      final threads = await DatabaseService.fetchForumThreads(
        viewerStaffLookupKey: state.effectiveStaffAppId,
      );
      if (!mounted) return;
      final visibleThreads = _filteredThreadsFrom(threads, state);
      final selected = preferFirst
          ? null
          : (selectThreadId ?? _selectedThreadId);
      final selectedThreadId = visibleThreads.any((t) => t.id == selected)
          ? selected
          : (visibleThreads.isNotEmpty ? visibleThreads.first.id : null);
      setState(() {
        _threads = threads;
        _selectedThreadId = selectedThreadId;
        _loading = false;
      });
      if (_selectedThreadId != null) {
        await _loadPosts(_selectedThreadId!);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _loadPosts(String threadId) async {
    setState(() => _postsLoading = true);
    final state = context.read<AppState>();
    final posts = await DatabaseService.fetchForumPosts(
      threadId,
      viewerStaffLookupKey: state.effectiveStaffAppId,
    );
    final inlineImages = <String, List<InlineAttachmentRow>>{};
    for (final post in posts) {
      final list = await DatabaseService.fetchInlineAttachments(
        entityType: 'forum_post_content',
        entityId: post.id,
      );
      if (list.isNotEmpty) inlineImages[post.id] = list;
    }
    if (!mounted) return;
    setState(() {
      _posts = posts;
      _postInlineImages = inlineImages;
      _postsLoading = false;
      if (!posts.any((p) => p.id == _replyingToPostId)) {
        _replyingToPostId = null;
        _replyController.clear();
        _replyAiPromptController.clear();
        _replyAiMessage = null;
        _replyAiSuggestedDraft = null;
      }
    });
  }

  List<ForumThread> _filteredThreadsFrom(
    List<ForumThread> source,
    AppState state,
  ) {
    final q = widget.searchQuery.trim().toLowerCase();
    final out = source
        .where(
          (t) =>
              (_categoryFilters.isEmpty ||
                  _categoryFilters.contains(t.category)) &&
              (_statusFilters.isEmpty || _statusFilters.contains(t.status)) &&
              (_creatorNameFilters.isEmpty ||
                  _keyMatches(t.createdBy, _creatorNameFilters)) &&
              (_creatorTeamFilters.isEmpty ||
                  _creatorTeamMatches(state, t.createdBy)) &&
              (q.isEmpty ||
                  t.title.toLowerCase().contains(q) ||
                  t.category.toLowerCase().contains(q) ||
                  t.status.toLowerCase().contains(q) ||
                  (t.createdByName ?? '').toLowerCase().contains(q)),
        )
        .toList();
    out.sort((a, b) {
      final ap = a.pinned ? 1 : 0;
      final bp = b.pinned ? 1 : 0;
      if (ap != bp) return bp.compareTo(ap);
      final cmp = switch (_sortKey) {
        'updated' => _compareNullableDates(
          a.updatedAt ?? a.createdAt,
          b.updatedAt ?? b.createdAt,
          ascending: _sortAscending,
        ),
        'name' => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        _ => _compareNullableDates(
          a.createdAt,
          b.createdAt,
          ascending: _sortAscending,
        ),
      };
      if (_sortKey == 'name' && !_sortAscending) return -cmp;
      return cmp;
    });
    return out;
  }

  int _compareNullableDates(
    DateTime? a,
    DateTime? b, {
    required bool ascending,
  }) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    final cmp = a.compareTo(b);
    return ascending ? cmp : -cmp;
  }

  bool _creatorTeamMatches(AppState state, String? staffKey) {
    final teamId = state.teamIdForStaffKey(staffKey);
    return teamId != null && _creatorTeamFilters.contains(teamId);
  }

  bool _keyMatches(String? value, Iterable<String> selected) {
    final v = value?.trim();
    if (v == null || v.isEmpty) return false;
    return selected.any((s) => v.toLowerCase() == s.trim().toLowerCase());
  }

  void _startReply(ForumPost parent) {
    if (parent.depth >= 2) return;
    setState(() {
      _replyingToPostId = parent.id;
      _replyController.clear();
      _replyAiPromptController.clear();
      _replyAiMessage = null;
      _replyAiSuggestedDraft = null;
    });
  }

  void _setPostLikeState(String postId, int likeCount, bool liked) {
    setState(() {
      _posts = [
        for (final p in _posts)
          if (p.id == postId)
            p.copyWith(likeCount: likeCount, likedByCurrentUser: liked)
          else
            p,
      ];
      _threads = [
        for (final t in _threads)
          if (t.rootPostId == postId)
            t.copyWith(likeCount: likeCount, likedByCurrentUser: liked)
          else
            t,
      ];
    });
  }

  void _setThreadRootLikeState(
    String threadId,
    String rootPostId,
    int likeCount,
    bool liked,
  ) {
    setState(() {
      _threads = [
        for (final t in _threads)
          if (t.id == threadId)
            t.copyWith(likeCount: likeCount, likedByCurrentUser: liked)
          else
            t,
      ];
      _posts = [
        for (final p in _posts)
          if (p.id == rootPostId)
            p.copyWith(likeCount: likeCount, likedByCurrentUser: liked)
          else
            p,
      ];
    });
  }

  int _nextLikeCount(int current, bool liked) {
    final next = current + (liked ? 1 : -1);
    return next < 0 ? 0 : next;
  }

  void _applyThreadRootLikeUpdate(ForumThread thread, bool liked) {
    final rootPostId = thread.rootPostId;
    if (rootPostId == null || rootPostId.isEmpty) return;
    _setThreadRootLikeState(
      thread.id,
      rootPostId,
      _nextLikeCount(thread.likeCount, liked),
      liked,
    );
  }

  Future<void> _toggleLike(AppState state, ForumPost post) async {
    final nextLiked = !post.likedByCurrentUser;
    _setPostLikeState(
      post.id,
      _nextLikeCount(post.likeCount, nextLiked),
      nextLiked,
    );
    final err = await DatabaseService.setForumPostLike(
      postId: post.id,
      liked: nextLiked,
      staffLookupKey: state.effectiveStaffAppId,
    );
    if (!mounted) return;
    if (err != null) {
      _setPostLikeState(post.id, post.likeCount, post.likedByCurrentUser);
      await _showError(err);
      return;
    }
  }

  Future<void> _toggleThreadRootLike(AppState state, ForumThread thread) async {
    final rootPostId = thread.rootPostId;
    if (rootPostId == null || rootPostId.isEmpty) return;
    final nextLiked = !thread.likedByCurrentUser;
    _applyThreadRootLikeUpdate(thread, nextLiked);
    final err = await DatabaseService.setForumPostLike(
      postId: rootPostId,
      liked: nextLiked,
      staffLookupKey: state.effectiveStaffAppId,
    );
    if (!mounted) return;
    if (err != null) {
      _setThreadRootLikeState(
        thread.id,
        rootPostId,
        thread.likeCount,
        thread.likedByCurrentUser,
      );
      await _showError(err);
    }
  }

  Future<void> _selectThread(ForumThread thread) async {
    setState(() {
      _selectedThreadId = thread.id;
      _mobileThreadDetailOpen = true;
    });
    _cancelReply();
    await _loadPosts(thread.id);
  }

  void _closeMobileThreadDetail() {
    setState(() => _mobileThreadDetailOpen = false);
    _cancelReply();
  }

  bool _canEditPost(AppState state, ForumPost post) {
    final creator = post.createdBy?.trim().toLowerCase();
    final creatorName = post.createdByName?.trim().toLowerCase();
    final appId = state.effectiveStaffAppId?.trim().toLowerCase();
    final uuid = state.effectiveStaffUuid?.trim().toLowerCase();
    final displayName = state.currentStaffDisplayName?.trim().toLowerCase();
    if (creator != null && creator.isNotEmpty) {
      if (creator == appId || creator == uuid) return true;
    }
    return creatorName != null &&
        creatorName.isNotEmpty &&
        displayName != null &&
        displayName.isNotEmpty &&
        creatorName == displayName;
  }

  void _startEditPost(ForumPost post) {
    setState(() => _editingPost = post);
    _cancelReply();
  }

  void _closeEditPost() {
    if (_editSaving) return;
    setState(() => _editingPost = null);
  }

  Future<void> _saveEditedPost(
    AppState state, {
    required ForumPost post,
    required String content,
    required String status,
    String? title,
    String? category,
    String? threadStatus,
  }) async {
    if (_editSaving) return;
    setState(() => _editSaving = true);
    final error = await DatabaseService.updateForumPost(
      postId: post.id,
      threadId: post.threadId,
      content: content,
      status: status,
      threadTitle: post.depth == 0 ? title : null,
      threadCategory: post.depth == 0 ? category : null,
      threadStatus: post.depth == 0 ? threadStatus : null,
      updaterStaffLookupKey: state.effectiveStaffAppId,
    );
    if (!mounted) return;
    setState(() => _editSaving = false);
    if (error != null) {
      await _showError(error);
      return;
    }
    setState(() => _editingPost = null);
    await _loadThreads();
    await _loadPosts(post.threadId);
  }

  Widget _buildThreadDetail(
    AppState state,
    List<ForumThread> threads, {
    required bool rounded,
  }) {
    return _ThreadDetail(
      palette: widget.palette,
      thread: threads.any((t) => t.id == _selectedThreadId)
          ? threads.firstWhere((t) => t.id == _selectedThreadId)
          : null,
      posts: _posts,
      postInlineImages: _postInlineImages,
      loading: _postsLoading,
      replyingToPostId: _replyingToPostId,
      replyController: _replyController,
      replyAiPromptController: _replyAiPromptController,
      replyAiBusy: _replyAiBusy,
      replyAiMessage: _replyAiMessage,
      replyAiSuggestedDraft: _replyAiSuggestedDraft,
      replySaving: _replySaving,
      authorMetaForKey: _authorTeamOfficeLabel,
      rounded: rounded,
      canEditPost: (post) => _canEditPost(state, post),
      onEditPost: _startEditPost,
      onStartReply: _startReply,
      onToggleLike: (post) => _toggleLike(state, post),
      onCancelReply: _cancelReply,
      onAcceptReplyAiSuggestion: _acceptReplyAiSuggestion,
      onDismissReplyAiSuggestion: _dismissReplyAiSuggestion,
      onAskReplyAi: _askReplyAi,
      onSubmitReply: (post) => _submitReply(state, post),
    );
  }

  void _cancelReply() {
    setState(() {
      _replyingToPostId = null;
      _replyController.clear();
      _replyAiPromptController.clear();
      _replyAiMessage = null;
      _replyAiSuggestedDraft = null;
    });
  }

  void _acceptReplyAiSuggestion() {
    final draft = _replyAiSuggestedDraft?.trim();
    if (draft == null || draft.isEmpty) return;
    setState(() {
      _replyController.text = draft;
      _replyAiSuggestedDraft = null;
      _replyAiMessage = 'AI draft applied.';
    });
  }

  void _dismissReplyAiSuggestion() {
    setState(() {
      _replyAiSuggestedDraft = null;
      _replyAiMessage = null;
    });
  }

  String _replyParentContext(ForumPost parent) {
    final byId = {for (final p in _posts) p.id: p};
    final chain = <ForumPost>[];
    var cursor = parent;
    while (true) {
      chain.insert(0, cursor);
      final parentId = cursor.parentPostId;
      if (parentId == null || parentId.isEmpty) break;
      final next = byId[parentId];
      if (next == null) break;
      cursor = next;
    }
    return [
      for (var i = 0; i < chain.length; i++)
        'Parent ${i + 1} by ${chain[i].createdByName ?? 'Unknown'}: ${chain[i].content}',
    ].join('\n\n');
  }

  Future<void> _askReplyAi(ForumPost parent) async {
    if (_replyAiBusy) return;
    final prompt = _replyAiPromptController.text.trim();
    if (prompt.isEmpty) return;
    setState(() {
      _replyAiBusy = true;
      _replyAiMessage = null;
      _replyAiSuggestedDraft = null;
    });
    try {
      final draft = await LlmService.suggestDiscussionReplyDraft(
        userPrompt: prompt,
        parentContext: _replyParentContext(parent),
      );
      if (!mounted) return;
      setState(() {
        _replyAiSuggestedDraft = draft;
        _replyAiMessage =
            'AI drafted a reply using the parent discussion context. Review it before applying.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _replyAiMessage = e.toString());
    } finally {
      if (mounted) setState(() => _replyAiBusy = false);
    }
  }

  Future<void> _submitReply(AppState state, ForumPost parent) async {
    if (_replySaving) return;
    final content = _replyController.text.trim();
    if (content.isEmpty) return;
    setState(() => _replySaving = true);
    final result = await DatabaseService.createForumReply(
      threadId: parent.threadId,
      parentPostId: parent.id,
      parentDepth: parent.depth,
      content: content,
      creatorStaffLookupKey: state.effectiveStaffAppId,
    );
    if (!mounted) return;
    setState(() => _replySaving = false);
    if (result.error != null) {
      await _showError(result.error!);
      return;
    }
    final now = DateTime.now();
    final newPost = result.post?.copyWith(
      createdBy: state.effectiveStaffAppId ?? result.post?.createdBy,
      createdByName:
          state.currentStaffDisplayName ?? result.post?.createdByName,
      createdAt: result.post?.createdAt ?? now,
    );
    _cancelReply();
    if (newPost != null) {
      setState(() {
        _posts = [..._posts, newPost];
        _threads = [
          for (final t in _threads)
            if (t.id == parent.threadId)
              t.copyWith(replyCount: t.replyCount + 1, updatedAt: now)
            else
              t,
        ];
      });
    }
  }

  void _clearFilters() {
    setState(() {
      _categoryFilters = {};
      _statusFilters = {};
      _creatorTeamFilters = {};
      _creatorNameFilters = {};
      _mobileThreadDetailOpen = false;
    });
    _selectFirstFilteredThread();
  }

  String _filterLabel(Set<String> selected) {
    if (selected.isEmpty) return 'All';
    if (selected.length == 1) return selected.first;
    return '${selected.length} selected';
  }

  Future<void> _showCategoryMenu(BuildContext buttonContext) async {
    const allKey = '__all__';
    final selection = await showAsanaCheckboxFilterPanel(
      anchorContext: buttonContext,
      options: [
        const AsanaFilterCheckboxOption(key: allKey, label: 'All', isAll: true),
        for (final category in _categories)
          AsanaFilterCheckboxOption(key: category, label: category),
      ],
      initialSelection: _categoryFilters,
    );
    if (selection != null) {
      setState(() => _categoryFilters = selection);
      _selectFirstFilteredThread();
    }
  }

  Future<void> _showStatusMenu(BuildContext buttonContext) async {
    const allKey = '__all__';
    final selection = await showAsanaCheckboxFilterPanel(
      anchorContext: buttonContext,
      options: const [
        AsanaFilterCheckboxOption(key: allKey, label: 'All', isAll: true),
        AsanaFilterCheckboxOption(key: 'Open', label: 'Open'),
        AsanaFilterCheckboxOption(key: 'Resolved', label: 'Resolved'),
        AsanaFilterCheckboxOption(key: 'Closed', label: 'Closed'),
      ],
      initialSelection: _statusFilters,
    );
    if (selection != null) {
      setState(() => _statusFilters = selection);
      _selectFirstFilteredThread();
    }
  }

  Future<void> _showCreatorTeamMenu(BuildContext buttonContext) async {
    final state = context.read<AppState>();
    final selection = await showAsanaCheckboxFilterPanel(
      anchorContext: buttonContext,
      options: _teamOptions(state, _visibleCreatorTeamIds(state)),
      initialSelection: _creatorTeamFilters,
    );
    if (selection != null) {
      setState(() => _creatorTeamFilters = selection);
      _selectFirstFilteredThread();
    }
  }

  Future<void> _showCreatorNameMenu(BuildContext buttonContext) async {
    final state = context.read<AppState>();
    final selection = await showAsanaCheckboxFilterPanel(
      anchorContext: buttonContext,
      options: _staffOptions(state, _visibleCreatorIds()),
      initialSelection: _creatorNameFilters,
    );
    if (selection != null) {
      setState(() => _creatorNameFilters = selection);
      _selectFirstFilteredThread();
    }
  }

  List<String> _visibleCreatorIds() {
    final ids = _threads
        .map((t) => t.createdBy?.trim() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    ids.sort();
    return ids;
  }

  Set<String> _visibleCreatorTeamIds(AppState state) {
    return _visibleCreatorIds()
        .map(state.teamIdForStaffKey)
        .whereType<String>()
        .where((id) => id.trim().isNotEmpty)
        .toSet();
  }

  List<AsanaFilterCheckboxOption> _staffOptions(
    AppState state,
    List<String> ids,
  ) {
    final options = [
      const AsanaFilterCheckboxOption(
        key: '__all__',
        label: 'All',
        isAll: true,
      ),
      for (final id in ids)
        AsanaFilterCheckboxOption(
          key: id,
          label: state.assigneeById(id)?.name.trim().isNotEmpty == true
              ? state.assigneeById(id)!.name.trim()
              : id,
        ),
    ];
    options.sort((a, b) {
      if (a.isAll) return -1;
      if (b.isAll) return 1;
      return a.label.compareTo(b.label);
    });
    return options;
  }

  List<AsanaFilterCheckboxOption> _teamOptions(
    AppState state,
    Set<String> visibleTeamIds,
  ) {
    final teams =
        state.teams
            .where((t) => visibleTeamIds.contains(t.id))
            .map((t) => AsanaFilterCheckboxOption(key: t.id, label: t.name))
            .toList()
          ..sort((a, b) => a.label.compareTo(b.label));
    return [
      const AsanaFilterCheckboxOption(
        key: '__all__',
        label: 'All',
        isAll: true,
      ),
      ...teams,
    ];
  }

  String _creatorLabel(AppState state) {
    if (_creatorNameFilters.isEmpty) return 'All';
    if (_creatorNameFilters.length == 1) {
      final id = _creatorNameFilters.first;
      final name = state.assigneeById(id)?.name.trim();
      return name != null && name.isNotEmpty ? name : id;
    }
    return '${_creatorNameFilters.length} selected';
  }

  String _teamFilterLabel(AppState state, Set<String> teamIds) {
    if (teamIds.isEmpty) return 'All';
    if (teamIds.length == 1) return state.teamNameById(teamIds.first);
    return '${teamIds.length} selected';
  }

  String _sortLabel() {
    final name = switch (_sortKey) {
      'updated' => 'Last updated',
      'name' => 'Name',
      _ => 'Created',
    };
    final arrow = _sortAscending ? '↑' : '↓';
    return '$name $arrow';
  }

  Future<void> _showSortMenu(BuildContext buttonContext) async {
    await showMenu<String>(
      context: buttonContext,
      position: _menuPosition(buttonContext),
      color: Theme.of(buttonContext).colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      items: const [
        PopupMenuItem(value: 'created_desc', child: Text('Created ↓')),
        PopupMenuItem(value: 'created_asc', child: Text('Created ↑')),
        PopupMenuItem(value: 'updated_desc', child: Text('Last updated ↓')),
        PopupMenuItem(value: 'updated_asc', child: Text('Last updated ↑')),
        PopupMenuItem(value: 'name_asc', child: Text('Name A-Z')),
        PopupMenuItem(value: 'name_desc', child: Text('Name Z-A')),
      ],
    ).then((value) {
      if (value == null) return;
      setState(() {
        switch (value) {
          case 'created_asc':
            _sortKey = 'created';
            _sortAscending = true;
          case 'updated_desc':
            _sortKey = 'updated';
            _sortAscending = false;
          case 'updated_asc':
            _sortKey = 'updated';
            _sortAscending = true;
          case 'name_asc':
            _sortKey = 'name';
            _sortAscending = true;
          case 'name_desc':
            _sortKey = 'name';
            _sortAscending = false;
          default:
            _sortKey = 'created';
            _sortAscending = false;
        }
      });
      _selectFirstFilteredThread();
    });
  }

  RelativeRect _menuPosition(BuildContext buttonContext) {
    final box = buttonContext.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(buttonContext).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null || !box.hasSize || !overlay.hasSize) {
      return const RelativeRect.fromLTRB(0, 0, 0, 0);
    }
    final offset = box.localToGlobal(Offset.zero, ancestor: overlay);
    return RelativeRect.fromRect(
      Rect.fromLTWH(offset.dx, offset.dy + box.size.height, box.size.width, 0),
      Offset.zero & overlay.size,
    );
  }

  Future<void> _selectFirstFilteredThread() async {
    final state = context.read<AppState>();
    final threads = _filteredThreadsFrom(_threads, state);
    final nextId = threads.isNotEmpty ? threads.first.id : null;
    if (_selectedThreadId == nextId) {
      if (nextId != null && _posts.isEmpty) await _loadPosts(nextId);
      return;
    }
    setState(() => _selectedThreadId = nextId);
    _cancelReply();
    if (nextId != null) {
      await _loadPosts(nextId);
    } else {
      setState(() {
        _posts = [];
        _postInlineImages = {};
      });
    }
  }

  Future<void> _showError(String message) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Could not save discussion'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = Theme.of(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Text(
          'Could not load discussion forum.\n$_error',
          textAlign: TextAlign.center,
          style: asanaTextStyle(
            theme.textTheme.bodyMedium,
            color: Colors.red.shade700,
          ),
        ),
      );
    }

    final threads = _filteredThreadsFrom(_threads, state);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final compactTitle = screenWidth < 600;
    final mobilePanel = screenWidth < 760;
    final editSlideWidth = screenWidth < 840
        ? screenWidth
        : (screenWidth * 0.504).clamp(480.0, 672.0);
    final editingPost = _editingPost;
    ForumThread? editingThread;
    if (editingPost != null) {
      for (final t in _threads) {
        if (t.id == editingPost.threadId) {
          editingThread = t;
          break;
        }
      }
    }
    return ColoredBox(
      color: widget.palette.panelBackground,
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Welcome to share suggestions, report issues, and brainstorm Project Tracker improvements',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontSize: compactTitle ? 14 : 18,
                      fontWeight: FontWeight.w600,
                      color: kAsanaTextPrimary,
                      height: 1.25,
                    ),
                    maxLines: compactTitle ? 1 : null,
                    overflow: compactTitle
                        ? TextOverflow.ellipsis
                        : TextOverflow.visible,
                  ),
                ),
              ),
              AsanaPanelFilterToolbar(
                palette: widget.palette,
                createLabel: 'New Post',
                onCreate: widget.onCreatePost,
                onClearAll: _clearFilters,
                filterChildren: [
                  AsanaFilterDropdown(
                    title: 'Category',
                    value: _filterLabel(_categoryFilters),
                    highlighted: _categoryFilters.isNotEmpty,
                    buttonWidth: 136,
                    onPressed: _showCategoryMenu,
                  ),
                  AsanaFilterDropdown(
                    title: 'Creator Team',
                    value: _teamFilterLabel(state, _creatorTeamFilters),
                    highlighted: _creatorTeamFilters.isNotEmpty,
                    onPressed: _showCreatorTeamMenu,
                  ),
                  AsanaFilterDropdown(
                    title: 'Creator Name',
                    value: _creatorLabel(state),
                    highlighted: _creatorNameFilters.isNotEmpty,
                    onPressed: _showCreatorNameMenu,
                  ),
                  AsanaFilterDropdown(
                    title: 'Status',
                    value: _filterLabel(_statusFilters),
                    highlighted: _statusFilters.isNotEmpty,
                    onPressed: _showStatusMenu,
                  ),
                  AsanaFilterDropdown(
                    title: 'Sort',
                    value: _sortLabel(),
                    buttonWidth: 136,
                    onPressed: _showSortMenu,
                  ),
                ],
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 760;
                      final list = _ThreadList(
                        palette: widget.palette,
                        threads: threads,
                        selectedThreadId: _selectedThreadId,
                        onSelect: _selectThread,
                        onToggleLike: (thread) =>
                            _toggleThreadRootLike(state, thread),
                      );
                      if (compact) {
                        return list;
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(width: 340, child: list),
                          const SizedBox(width: 14),
                          Expanded(
                            child: _buildThreadDetail(
                              state,
                              threads,
                              rounded: true,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
          if (mobilePanel && _mobileThreadDetailOpen)
            Positioned.fill(
              child: TweenAnimationBuilder<Offset>(
                tween: Tween(begin: const Offset(1, 0), end: Offset.zero),
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                builder: (context, offset, child) {
                  return FractionalTranslation(
                    translation: offset,
                    child: child,
                  );
                },
                child: _MobileDiscussionDetailSlide(
                  palette: widget.palette,
                  onClose: _closeMobileThreadDetail,
                  child: _buildThreadDetail(state, threads, rounded: false),
                ),
              ),
            ),
          if (editingPost != null)
            Positioned.fill(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _editSaving ? null : _closeEditPost,
                      child: const ColoredBox(color: Color(0x33000000)),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    width: editSlideWidth,
                    child: TweenAnimationBuilder<Offset>(
                      tween: Tween(begin: const Offset(1, 0), end: Offset.zero),
                      duration: const Duration(milliseconds: 240),
                      curve: Curves.easeOutCubic,
                      builder: (context, offset, child) {
                        return FractionalTranslation(
                          translation: offset,
                          child: child,
                        );
                      },
                      child: _ForumEditSlide(
                        palette: widget.palette,
                        post: editingPost,
                        thread: editingThread,
                        saving: _editSaving,
                        onClose: _closeEditPost,
                        onSave:
                            ({
                              required content,
                              required status,
                              title,
                              category,
                              threadStatus,
                            }) => _saveEditedPost(
                              state,
                              post: editingPost,
                              content: content,
                              status: status,
                              title: title,
                              category: category,
                              threadStatus: threadStatus,
                            ),
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

class _MobileDiscussionDetailSlide extends StatelessWidget {
  const _MobileDiscussionDetailSlide({
    required this.palette,
    required this.onClose,
    required this.child,
  });

  final AsanaLandingPalette palette;
  final VoidCallback onClose;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final chrome = AsanaSlideChrome(palette);
    return Material(
      elevation: 8,
      shadowColor: Colors.black26,
      color: chrome.body,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: chrome.header,
            elevation: 0,
            child: SafeArea(
              bottom: false,
              child: Row(
                children: [
                  const SizedBox(width: 20),
                  Expanded(
                    child: Text(
                      'Discussion Details',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: chrome.onHeader.withValues(alpha: 0.6),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: chrome.onHeader),
                    tooltip: 'Close',
                    onPressed: onClose,
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: chrome.footerBorder),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _ForumEditSlide extends StatefulWidget {
  const _ForumEditSlide({
    required this.palette,
    required this.post,
    required this.thread,
    required this.saving,
    required this.onClose,
    required this.onSave,
  });

  final AsanaLandingPalette palette;
  final ForumPost post;
  final ForumThread? thread;
  final bool saving;
  final VoidCallback onClose;
  final Future<void> Function({
    required String content,
    required String status,
    String? title,
    String? category,
    String? threadStatus,
  })
  onSave;

  @override
  State<_ForumEditSlide> createState() => _ForumEditSlideState();
}

class _ForumEditSlideState extends State<_ForumEditSlide> {
  static const List<String> _categories = [
    'General',
    'Announcement',
    'Suggestion',
    'Feature idea',
    'Bug report',
  ];

  late final TextEditingController _titleController;
  late final TextEditingController _contentController;
  final _aiPromptController = TextEditingController();
  final LayerLink _categoryAnchorLink = LayerLink();
  final LayerLink _statusAnchorLink = LayerLink();
  String _category = 'General';
  String _threadStatus = 'Open';
  bool _aiBusy = false;
  String? _aiMessage;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.thread?.title ?? '');
    _contentController = TextEditingController(text: widget.post.content);
    _category = widget.thread?.category.trim().isNotEmpty == true
        ? widget.thread!.category.trim()
        : 'General';
    _threadStatus = widget.thread?.status.trim().isNotEmpty == true
        ? widget.thread!.status.trim()
        : 'Open';
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _aiPromptController.dispose();
    super.dispose();
  }

  Future<void> _pickCategory(BuildContext anchorContext) async {
    final choice = await showAsanaAnchoredOptionMenu<String>(
      anchorLink: _categoryAnchorLink,
      anchorContext: anchorContext,
      options: _categories
          .map((v) => AsanaAnchoredOption(value: v, label: v))
          .toList(),
    );
    if (choice != null && mounted) setState(() => _category = choice);
  }

  Future<void> _pickStatus(BuildContext anchorContext) async {
    const options = [
      AsanaAnchoredOption(value: 'Open', label: 'Open'),
      AsanaAnchoredOption(value: 'Resolved', label: 'Resolved'),
      AsanaAnchoredOption(value: 'Closed', label: 'Closed'),
    ];
    final choice = await showAsanaAnchoredOptionMenu<String>(
      anchorLink: _statusAnchorLink,
      anchorContext: anchorContext,
      options: options,
    );
    if (choice != null && mounted) setState(() => _threadStatus = choice);
  }

  Future<void> _askAi() async {
    final prompt = _aiPromptController.text.trim();
    if (prompt.isEmpty || _aiBusy || !LlmService.isConfigured) return;
    setState(() {
      _aiBusy = true;
      _aiMessage = null;
    });
    try {
      if (widget.post.depth == 0) {
        final raw = await LlmService.suggestDiscussionThreadDraft(
          userPrompt: prompt,
          formContext:
              '''
Current forum draft:
- title: ${_titleController.text.trim().isEmpty ? "(empty)" : _titleController.text.trim()}
- category: $_category
- status: $_threadStatus
- content: ${_contentController.text.trim().isEmpty ? "(empty)" : _contentController.text.trim()}
''',
        );
        if (!mounted) return;
        setState(() {
          final title = raw['title']?.toString().trim();
          final content = raw['content']?.toString().trim();
          final category = raw['category']?.toString().trim();
          final status = raw['status']?.toString().trim();
          if (title != null && title.isNotEmpty) _titleController.text = title;
          if (content != null && content.isNotEmpty) {
            _contentController.text = content;
          }
          if (category != null && _categories.contains(category)) {
            _category = category;
          }
          if (status != null &&
              const {'Open', 'Resolved', 'Closed'}.contains(status)) {
            _threadStatus = status;
          }
          _aiMessage = raw['overallComment']?.toString().trim();
        });
      } else {
        final draft = await LlmService.suggestDiscussionReplyDraft(
          userPrompt: prompt,
          parentContext: 'Current reply content: ${_contentController.text}',
        );
        if (!mounted) return;
        setState(() {
          _contentController.text = draft;
          _aiMessage = 'AI revised the reply content. Review before updating.';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _aiMessage = e.toString());
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chrome = AsanaSlideChrome(widget.palette);
    final isRoot = widget.post.depth == 0;
    final cancelStyle =
        AsanaTaskDetailActionStyles.updateFilled(
          widget.palette,
          context: context,
        ).copyWith(
          backgroundColor: const WidgetStatePropertyAll(Color(0xFF4B5563)),
          foregroundColor: const WidgetStatePropertyAll(Colors.white),
        );

    return Material(
      elevation: 8,
      shadowColor: Colors.black26,
      color: chrome.body,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: chrome.header,
            elevation: 0,
            child: SafeArea(
              bottom: false,
              child: Row(
                children: [
                  const SizedBox(width: 20),
                  Expanded(
                    child: Text(
                      isRoot ? 'Discussion Details' : 'Reply Details',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: chrome.onHeader.withValues(alpha: 0.6),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: chrome.onHeader),
                    tooltip: 'Close',
                    onPressed: widget.saving ? null : widget.onClose,
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: chrome.footerBorder),
          Expanded(
            child: AsanaDetailSlideScaffold(
              backgroundColor: chrome.body,
              footer: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ForumEditAiDock(
                    promptController: _aiPromptController,
                    busy: _aiBusy,
                    message: _aiMessage,
                    enabled: !widget.saving && LlmService.isConfigured,
                    palette: widget.palette,
                    footerBorder: chrome.footerBorder,
                    onAsk: _askAi,
                  ),
                  AsanaDetailSlideFooter(
                    backgroundColor: chrome.footer,
                    borderColor: chrome.footerBorder,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        FilledButton(
                          onPressed: widget.saving ? null : widget.onClose,
                          style: cancelStyle,
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 10),
                        FilledButton(
                          onPressed: widget.saving
                              ? null
                              : () => widget.onSave(
                                  title: _titleController.text,
                                  category: _category,
                                  threadStatus: _threadStatus,
                                  status: widget.post.status,
                                  content: _contentController.text,
                                ),
                          style: AsanaTaskDetailActionStyles.updateFilled(
                            widget.palette,
                            context: context,
                          ),
                          child: Text(widget.saving ? 'Saving' : 'Update'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              body: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (isRoot) ...[
                    AsanaHoverTextField(
                      controller: _titleController,
                      canEdit: true,
                      readOnly: widget.saving,
                      maxLines: 3,
                      minLines: 1,
                      hintText: 'Please fill in discussion topic',
                      style: asanaDetailTitleStyle(context),
                    ),
                    const SizedBox(height: 10),
                  ],
                  AsanaDetailLabelValue(
                    label: 'Content',
                    child: AsanaHoverTextField(
                      controller: _contentController,
                      canEdit: true,
                      readOnly: widget.saving,
                      showOutline: true,
                      maxLines: 12,
                      minLines: 6,
                      hintText:
                          'Share your suggestion, issue report, feature idea, or announcement details.',
                      style: asanaDetailMultilineValueStyle(context),
                    ),
                  ),
                  if (isRoot) ...[
                    AsanaDetailTwoColumnRow(
                      label: 'Category',
                      child: Builder(
                        builder: (anchorContext) => CompositedTransformTarget(
                          link: _categoryAnchorLink,
                          child: AsanaHoverTapValue(
                            value: _category,
                            canEdit: !widget.saving,
                            onTap: widget.saving
                                ? null
                                : (_) => _pickCategory(anchorContext),
                          ),
                        ),
                      ),
                    ),
                    AsanaDetailTwoColumnRow(
                      label: 'Status',
                      child: Builder(
                        builder: (anchorContext) => CompositedTransformTarget(
                          link: _statusAnchorLink,
                          child: AsanaHoverTapValue(
                            value: _threadStatus,
                            canEdit: !widget.saving,
                            onTap: widget.saving
                                ? null
                                : (_) => _pickStatus(anchorContext),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ForumEditAiDock extends StatefulWidget {
  const _ForumEditAiDock({
    required this.promptController,
    required this.busy,
    required this.message,
    required this.enabled,
    required this.palette,
    required this.footerBorder,
    required this.onAsk,
  });

  final TextEditingController promptController;
  final bool busy;
  final String? message;
  final bool enabled;
  final AsanaLandingPalette palette;
  final Color footerBorder;
  final Future<void> Function() onAsk;

  @override
  State<_ForumEditAiDock> createState() => _ForumEditAiDockState();
}

class _ForumEditAiDockState extends State<_ForumEditAiDock> {
  bool _expanded = false;

  KeyEventResult _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.enter) {
      return KeyEventResult.ignored;
    }
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    final shiftPressed =
        keys.contains(LogicalKeyboardKey.shiftLeft) ||
        keys.contains(LogicalKeyboardKey.shiftRight);
    if (shiftPressed) return KeyEventResult.ignored;
    if (widget.enabled && !widget.busy) widget.onAsk();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final colors = AsanaTaskAiColors.fromPalette(widget.palette);
    final message = widget.message?.trim();
    return Material(
      color: colors.boxBackground,
      elevation: 4,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: widget.footerBorder)),
        ),
        child: SafeArea(
          top: false,
          child: AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            alignment: Alignment.bottomCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                InkWell(
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.auto_awesome,
                          size: 18,
                          color: colors.accent,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'AI assistant',
                            style: asanaDetailValueStyle(
                              context,
                              weight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Icon(
                          _expanded
                              ? Icons.keyboard_arrow_down
                              : Icons.keyboard_arrow_up,
                          color: kAsanaTextSecondary,
                        ),
                      ],
                    ),
                  ),
                ),
                if (!_expanded && message != null && message.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: Text(
                      message,
                      style: asanaDetailLabelStyle(
                        context,
                      ).copyWith(color: kAsanaTextSecondary, height: 1.35),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                if (_expanded)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Describe how to revise this discussion text.',
                          style: asanaDetailLabelStyle(context),
                        ),
                        const SizedBox(height: 10),
                        Focus(
                          onKeyEvent: (_, event) => _handleKey(event),
                          child: TextField(
                            controller: widget.promptController,
                            readOnly: !widget.enabled,
                            minLines: 2,
                            maxLines: 6,
                            keyboardType: TextInputType.multiline,
                            textInputAction: TextInputAction.newline,
                            decoration: InputDecoration(
                              labelText: 'Your prompt',
                              floatingLabelBehavior:
                                  FloatingLabelBehavior.always,
                              alignLabelWithHint: true,
                              filled: true,
                              fillColor: widget.palette.listSurface,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: BorderSide(color: colors.boxBorder),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: BorderSide(
                                  color: colors.accent,
                                  width: 2,
                                ),
                              ),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton(
                            onPressed: widget.enabled && !widget.busy
                                ? widget.onAsk
                                : null,
                            style: FilledButton.styleFrom(
                              backgroundColor: colors.accent,
                              foregroundColor: widget.palette.darkChrome
                                  ? Colors.white
                                  : widget.palette.onBanner,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: widget.busy
                                ? SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: widget.palette.darkChrome
                                          ? Colors.white
                                          : widget.palette.onBanner,
                                    ),
                                  )
                                : const Text('Analyse prompt'),
                          ),
                        ),
                        if (message != null && message.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(
                            message,
                            style: asanaDetailLabelStyle(context).copyWith(
                              color: kAsanaTextSecondary,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ThreadList extends StatelessWidget {
  const _ThreadList({
    required this.palette,
    required this.threads,
    required this.selectedThreadId,
    required this.onSelect,
    required this.onToggleLike,
  });

  final AsanaLandingPalette palette;
  final List<ForumThread> threads;
  final String? selectedThreadId;
  final ValueChanged<ForumThread> onSelect;
  final ValueChanged<ForumThread> onToggleLike;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: palette.listSurface,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Text(
              'Topics',
              style: asanaTextStyle(
                Theme.of(context).textTheme.titleMedium,
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: threads.isEmpty
                ? Center(
                    child: Text(
                      'No discussions yet.',
                      style: asanaTextStyle(
                        Theme.of(context).textTheme.bodyMedium,
                        color: kAsanaTextSecondary,
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: threads.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final t = threads[i];
                      final selected = t.id == selectedThreadId;
                      final selectedColor = palette.darkChrome
                          ? const Color(0xFFD9DDE3)
                          : Color.alphaBlend(
                              palette.accent.withValues(alpha: 0.1),
                              palette.listSurface,
                            );
                      return ListTile(
                        selected: selected,
                        selectedTileColor: selectedColor,
                        title: Text(
                          t.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: asanaTextStyle(
                            Theme.of(context).textTheme.bodyMedium,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        subtitle: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${t.createdByName ?? 'Unknown'} • ${_date(t.createdAt)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            _ThreadMetricRow(
                              liked: t.likedByCurrentUser,
                              likeCount: t.likeCount,
                              replyCount: t.replyCount,
                              onLike: t.rootPostId == null
                                  ? null
                                  : () => onToggleLike(t),
                            ),
                          ],
                        ),
                        trailing: t.pinned
                            ? Icon(
                                Icons.push_pin,
                                size: 16,
                                color: palette.accent,
                              )
                            : null,
                        onTap: () => onSelect(t),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ThreadDetail extends StatelessWidget {
  const _ThreadDetail({
    required this.palette,
    required this.thread,
    required this.posts,
    required this.postInlineImages,
    required this.loading,
    required this.replyingToPostId,
    required this.replyController,
    required this.replyAiPromptController,
    required this.replyAiBusy,
    required this.replyAiMessage,
    required this.replyAiSuggestedDraft,
    required this.replySaving,
    required this.authorMetaForKey,
    this.rounded = true,
    required this.canEditPost,
    required this.onEditPost,
    required this.onStartReply,
    required this.onToggleLike,
    required this.onCancelReply,
    required this.onAcceptReplyAiSuggestion,
    required this.onDismissReplyAiSuggestion,
    required this.onAskReplyAi,
    required this.onSubmitReply,
  });

  final AsanaLandingPalette palette;
  final ForumThread? thread;
  final List<ForumPost> posts;
  final Map<String, List<InlineAttachmentRow>> postInlineImages;
  final bool loading;
  final String? replyingToPostId;
  final TextEditingController replyController;
  final TextEditingController replyAiPromptController;
  final bool replyAiBusy;
  final String? replyAiMessage;
  final String? replyAiSuggestedDraft;
  final bool replySaving;
  final String Function(String? staffKey) authorMetaForKey;
  final bool rounded;
  final bool Function(ForumPost post) canEditPost;
  final ValueChanged<ForumPost> onEditPost;
  final ValueChanged<ForumPost> onStartReply;
  final ValueChanged<ForumPost> onToggleLike;
  final VoidCallback onCancelReply;
  final VoidCallback onAcceptReplyAiSuggestion;
  final VoidCallback onDismissReplyAiSuggestion;
  final Future<void> Function(ForumPost post) onAskReplyAi;
  final Future<void> Function(ForumPost post) onSubmitReply;

  @override
  Widget build(BuildContext context) {
    final t = thread;
    ForumPost? replyingToPost;
    final targetReplyId = replyingToPostId;
    if (targetReplyId != null) {
      for (final p in posts) {
        if (p.id == targetReplyId) {
          replyingToPost = p;
          break;
        }
      }
    }
    return Material(
      color: palette.listSurface,
      borderRadius: rounded ? BorderRadius.circular(16) : BorderRadius.zero,
      clipBehavior: Clip.antiAlias,
      child: t == null
          ? Center(
              child: Text(
                'Select a discussion to view details.',
                style: asanaTextStyle(
                  Theme.of(context).textTheme.bodyMedium,
                  color: kAsanaTextSecondary,
                ),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.title,
                        style: asanaTextStyle(
                          Theme.of(context).textTheme.headlineSmall,
                          fontWeight: FontWeight.w700,
                          fontSize: 22,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _AuthorDateLine(
                            prefix: 'Started by ',
                            name: t.createdByName ?? 'Unknown',
                            meta: authorMetaForKey(t.createdBy),
                            date: _date(t.createdAt),
                          ),
                          AsanaSubmissionChip(
                            submission: t.category,
                            displayLabel: t.category,
                            fontSize: 11,
                          ),
                          AsanaSubmissionChip(
                            submission: t.status,
                            displayLabel: t.status,
                            fontSize: 11,
                          ),
                          if (t.locked)
                            const AsanaSubmissionChip(
                              submission: 'Locked',
                              displayLabel: 'Locked',
                              fontSize: 11,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: loading
                      ? const Center(child: CircularProgressIndicator())
                      : Stack(
                          children: [
                            Positioned.fill(
                              child: _PostTree(
                                palette: palette,
                                posts: posts,
                                postInlineImages: postInlineImages,
                                locked: t.locked,
                                bottomPadding: replyingToPost == null
                                    ? 24
                                    : 430,
                                authorMetaForKey: authorMetaForKey,
                                canEditPost: canEditPost,
                                onEditPost: onEditPost,
                                onStartReply: onStartReply,
                                onToggleLike: onToggleLike,
                              ),
                            ),
                            if (replyingToPost != null)
                              Builder(
                                builder: (context) {
                                  final parent = replyingToPost!;
                                  return Align(
                                    alignment: Alignment.bottomCenter,
                                    child: _ReplySlideComposer(
                                      palette: palette,
                                      parent: parent,
                                      controller: replyController,
                                      aiPromptController:
                                          replyAiPromptController,
                                      aiBusy: replyAiBusy,
                                      aiMessage: replyAiMessage,
                                      aiSuggestedDraft: replyAiSuggestedDraft,
                                      saving: replySaving,
                                      onAskAi: () => onAskReplyAi(parent),
                                      onAcceptAiSuggestion:
                                          onAcceptReplyAiSuggestion,
                                      onDismissAiSuggestion:
                                          onDismissReplyAiSuggestion,
                                      onCancel: onCancelReply,
                                      onSubmit: () => onSubmitReply(parent),
                                    ),
                                  );
                                },
                              ),
                          ],
                        ),
                ),
              ],
            ),
    );
  }
}

class _ThreadMetricRow extends StatelessWidget {
  const _ThreadMetricRow({
    required this.liked,
    required this.likeCount,
    required this.replyCount,
    required this.onLike,
  });

  final bool liked;
  final int likeCount;
  final int replyCount;
  final VoidCallback? onLike;

  @override
  Widget build(BuildContext context) {
    final muted = kAsanaTextSecondary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _PostIconAction(
          tooltip: liked ? 'Unlike' : 'Like',
          icon: liked ? Icons.favorite : Icons.favorite_border,
          count: likeCount,
          color: liked ? const Color(0xFFE11D48) : muted,
          onPressed: onLike,
        ),
        const SizedBox(width: 4),
        _PostIconAction(
          tooltip: 'Replies',
          icon: Icons.chat_bubble_outline,
          count: replyCount,
          color: muted,
          onPressed: null,
        ),
      ],
    );
  }
}

class _PostTree extends StatelessWidget {
  const _PostTree({
    required this.palette,
    required this.posts,
    required this.postInlineImages,
    required this.locked,
    required this.bottomPadding,
    required this.authorMetaForKey,
    required this.canEditPost,
    required this.onEditPost,
    required this.onStartReply,
    required this.onToggleLike,
  });

  final AsanaLandingPalette palette;
  final List<ForumPost> posts;
  final Map<String, List<InlineAttachmentRow>> postInlineImages;
  final bool locked;
  final double bottomPadding;
  final String Function(String? staffKey) authorMetaForKey;
  final bool Function(ForumPost post) canEditPost;
  final ValueChanged<ForumPost> onEditPost;
  final ValueChanged<ForumPost> onStartReply;
  final ValueChanged<ForumPost> onToggleLike;

  @override
  Widget build(BuildContext context) {
    final orderedPosts = posts.toList();
    final byId = {for (final p in posts) p.id: p};
    final children = <String, List<ForumPost>>{};
    for (final p in posts.where((p) => p.parentPostId != null)) {
      children.putIfAbsent(p.parentPostId!, () => []).add(p);
    }
    int compareCreated(ForumPost a, ForumPost b) {
      final ad = a.createdAt;
      final bd = b.createdAt;
      if (ad == null && bd == null) return 0;
      if (ad == null) return 1;
      if (bd == null) return -1;
      return ad.compareTo(bd);
    }

    orderedPosts.sort(compareCreated);
    return ListView(
      padding: EdgeInsets.fromLTRB(20, 18, 20, bottomPadding),
      children: [
        for (final post in orderedPosts)
          _PostCard(
            post: post,
            inlineImages: postInlineImages[post.id] ?? const [],
            indent: post.depth >= 2 ? 28 : 0,
            replyCount: children[post.id]?.length ?? 0,
            locked: locked,
            authorMetaForKey: authorMetaForKey,
            canEdit: canEditPost(post),
            onEdit: onEditPost,
            onReply: (target) {
              final parentId = target.parentPostId;
              final parent = parentId == null ? null : byId[parentId];
              onStartReply(
                target.depth >= 2 && parent != null ? parent : target,
              );
            },
            onToggleLike: onToggleLike,
          ),
      ],
    );
  }
}

class _ReplySlideComposer extends StatefulWidget {
  const _ReplySlideComposer({
    required this.palette,
    required this.parent,
    required this.controller,
    required this.aiPromptController,
    required this.aiBusy,
    required this.aiMessage,
    required this.aiSuggestedDraft,
    required this.saving,
    required this.onAskAi,
    required this.onAcceptAiSuggestion,
    required this.onDismissAiSuggestion,
    required this.onCancel,
    required this.onSubmit,
  });

  final AsanaLandingPalette palette;
  final ForumPost parent;
  final TextEditingController controller;
  final TextEditingController aiPromptController;
  final bool aiBusy;
  final String? aiMessage;
  final String? aiSuggestedDraft;
  final bool saving;
  final VoidCallback onAskAi;
  final VoidCallback onAcceptAiSuggestion;
  final VoidCallback onDismissAiSuggestion;
  final VoidCallback onCancel;
  final VoidCallback onSubmit;

  @override
  State<_ReplySlideComposer> createState() => _ReplySlideComposerState();
}

class _ReplySlideComposerState extends State<_ReplySlideComposer> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _visible = true);
    });
  }

  bool _enterSubmitsPrompt(BuildContext context) {
    if (!kIsWeb) return false;
    return MediaQuery.sizeOf(context).width >= 600;
  }

  KeyEventResult _handleAiPromptKey(KeyEvent event, bool enterSubmits) {
    if (!enterSubmits) return KeyEventResult.ignored;
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey != LogicalKeyboardKey.enter) {
      return KeyEventResult.ignored;
    }
    if (HardwareKeyboard.instance.isShiftPressed ||
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isAltPressed) {
      return KeyEventResult.ignored;
    }
    if (widget.aiBusy || widget.saving || !LlmService.isConfigured) {
      return KeyEventResult.handled;
    }
    widget.onAskAi();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final enterSubmits = _enterSubmitsPrompt(context);
    final aiColors = AsanaTaskAiColors.fromPalette(widget.palette);
    return AnimatedSlide(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      offset: _visible ? Offset.zero : const Offset(0, 1.08),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 180),
        opacity: _visible ? 1 : 0,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: widget.palette.listSurface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE5E7EB)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x22000000),
                  blurRadius: 18,
                  offset: Offset(0, -4),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Replying to ${widget.parent.createdByName ?? 'Unknown'}',
                    style: asanaTextStyle(
                      Theme.of(context).textTheme.bodySmall,
                      color: kAsanaTextSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: widget.controller,
                    autofocus: true,
                    readOnly: widget.saving,
                    minLines: 3,
                    maxLines: 8,
                    decoration: InputDecoration(
                      hintText: 'Write a reply...',
                      isDense: true,
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFF6B7280)),
                      ),
                    ),
                  ),
                  if (widget.aiSuggestedDraft != null &&
                      widget.aiSuggestedDraft!.trim().isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _ReplyAiSuggestionCard(
                      text: widget.aiSuggestedDraft!.trim(),
                      colors: aiColors,
                      onAccept: widget.onAcceptAiSuggestion,
                      onDismiss: widget.onDismissAiSuggestion,
                    ),
                  ],
                  const SizedBox(height: 10),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: aiColors.boxBackground,
                      border: Border.all(color: aiColors.boxBorder),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.auto_awesome,
                                size: 18,
                                color: aiColors.accent,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'AI assistant',
                                  style: asanaDetailValueStyle(
                                    context,
                                    weight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Describe how you want to reply. The assistant will consider the parent post and reply context.',
                            style: asanaDetailLabelStyle(context),
                          ),
                          const SizedBox(height: 10),
                          Focus(
                            onKeyEvent: (_, event) =>
                                _handleAiPromptKey(event, enterSubmits),
                            child: TextField(
                              controller: widget.aiPromptController,
                              readOnly:
                                  widget.aiBusy ||
                                  widget.saving ||
                                  !LlmService.isConfigured,
                              minLines: 2,
                              maxLines: 5,
                              decoration: InputDecoration(
                                labelText: 'Your prompt',
                                floatingLabelBehavior:
                                    FloatingLabelBehavior.always,
                                alignLabelWithHint: true,
                                filled: true,
                                fillColor: widget.palette.listSurface,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  borderSide: BorderSide(
                                    color: aiColors.boxBorder,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  borderSide: BorderSide(
                                    color: aiColors.accent,
                                    width: 2,
                                  ),
                                ),
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerRight,
                            child: FilledButton(
                              onPressed:
                                  widget.aiBusy ||
                                      widget.saving ||
                                      !LlmService.isConfigured
                                  ? null
                                  : widget.onAskAi,
                              style: FilledButton.styleFrom(
                                backgroundColor: aiColors.accent,
                                foregroundColor: widget.palette.darkChrome
                                    ? Colors.white
                                    : widget.palette.onBanner,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: widget.aiBusy
                                  ? SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: widget.palette.darkChrome
                                            ? Colors.white
                                            : widget.palette.onBanner,
                                      ),
                                    )
                                  : const Text('Analyse prompt'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (widget.aiMessage != null &&
                      widget.aiMessage!.trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      widget.aiMessage!,
                      style: asanaTextStyle(
                        Theme.of(context).textTheme.bodySmall,
                        color: kAsanaTextSecondary,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      const Spacer(),
                      FilledButton(
                        onPressed: widget.saving ? null : widget.onCancel,
                        style: AsanaTaskDetailActionStyles.updateFilled(
                          widget.palette,
                          context: context,
                        ),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: widget.saving ? null : widget.onSubmit,
                        style: AsanaTaskDetailActionStyles.successFilled(
                          context: context,
                        ),
                        child: Text(widget.saving ? 'Replying' : 'Reply'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReplyAiSuggestionCard extends StatelessWidget {
  const _ReplyAiSuggestionCard({
    required this.text,
    required this.colors,
    required this.onAccept,
    required this.onDismiss,
  });

  final String text;
  final AsanaTaskAiColors colors;
  final VoidCallback onAccept;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.boxBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Suggested reply',
                    style: asanaDetailLabelStyle(context).copyWith(
                      color: colors.suggestedLabel,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    text,
                    style: asanaDetailValueStyle(
                      context,
                    ).copyWith(fontWeight: FontWeight.w500, height: 1.35),
                  ),
                ],
              ),
            ),
            Tooltip(
              message: 'Dismiss suggestion',
              child: IconButton(
                onPressed: onDismiss,
                icon: const Icon(
                  Icons.cancel_outlined,
                  size: 20,
                  color: Color(0xFFC62828),
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
              ),
            ),
            Tooltip(
              message: 'Apply this suggestion',
              child: IconButton(
                onPressed: onAccept,
                icon: Icon(
                  Icons.check_circle_outline,
                  size: 20,
                  color: colors.adoptIcon,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AuthorDateLine extends StatelessWidget {
  const _AuthorDateLine({
    this.prefix = '',
    required this.name,
    required this.meta,
    required this.date,
  });

  final String prefix;
  final String name;
  final String meta;
  final String date;

  @override
  Widget build(BuildContext context) {
    final base = asanaTextStyle(
      Theme.of(context).textTheme.bodySmall,
      color: kAsanaTextSecondary,
      fontWeight: FontWeight.w600,
    )!;
    return Text.rich(
      TextSpan(
        style: base,
        children: [
          TextSpan(text: prefix),
          TextSpan(text: name),
          if (meta.isNotEmpty)
            TextSpan(
              text: ' ($meta)',
              style: base.copyWith(fontSize: 11, fontWeight: FontWeight.w500),
            ),
          TextSpan(text: ' • $date'),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _PostCard extends StatelessWidget {
  const _PostCard({
    required this.post,
    required this.inlineImages,
    required this.indent,
    required this.replyCount,
    required this.locked,
    required this.authorMetaForKey,
    required this.canEdit,
    required this.onEdit,
    required this.onReply,
    required this.onToggleLike,
  });

  final ForumPost post;
  final List<InlineAttachmentRow> inlineImages;
  final double indent;
  final int? replyCount;
  final bool locked;
  final String Function(String? staffKey) authorMetaForKey;
  final bool canEdit;
  final ValueChanged<ForumPost> onEdit;
  final ValueChanged<ForumPost> onReply;
  final ValueChanged<ForumPost> onToggleLike;

  @override
  Widget build(BuildContext context) {
    final authorMeta = authorMetaForKey(post.createdBy);
    return Padding(
      padding: EdgeInsets.only(left: indent, bottom: 12),
      child: InkWell(
        onTap: canEdit ? () => onEdit(post) : null,
        borderRadius: BorderRadius.circular(12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: post.depth == 0 ? Colors.white : const Color(0xFFF8F9FA),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: _AuthorDateLine(
                        name: post.createdByName ?? 'Unknown',
                        meta: authorMeta,
                        date: _date(post.createdAt),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  post.content,
                  style: asanaTextStyle(
                    Theme.of(context).textTheme.bodyMedium,
                    height: 1.45,
                  ),
                ),
                InlineImagePreviewList(
                  images: [
                    for (final row in inlineImages)
                      InlineImagePreviewItem.saved(row),
                  ],
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: _PostActionRow(
                    liked: post.likedByCurrentUser,
                    likeCount: post.likeCount,
                    replyCount: replyCount,
                    canReply: !locked,
                    onLike: () => onToggleLike(post),
                    onReply: () => onReply(post),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PostActionRow extends StatelessWidget {
  const _PostActionRow({
    required this.liked,
    required this.likeCount,
    required this.replyCount,
    required this.canReply,
    required this.onLike,
    required this.onReply,
  });

  final bool liked;
  final int likeCount;
  final int? replyCount;
  final bool canReply;
  final VoidCallback onLike;
  final VoidCallback onReply;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = kAsanaTextSecondary;
    return Row(
      children: [
        _PostIconAction(
          tooltip: liked ? 'Unlike' : 'Like',
          icon: liked ? Icons.favorite : Icons.favorite_border,
          count: likeCount,
          color: liked ? const Color(0xFFE11D48) : muted,
          onPressed: onLike,
        ),
        const SizedBox(width: 10),
        _PostIconAction(
          tooltip: 'Reply',
          icon: Icons.chat_bubble_outline,
          count: replyCount,
          color: muted,
          onPressed: canReply ? onReply : null,
        ),
        if (!canReply) ...[
          const SizedBox(width: 8),
          Text(
            'Locked',
            style: asanaTextStyle(
              theme.textTheme.bodySmall,
              color: kAsanaTextSecondary,
            ),
          ),
        ],
      ],
    );
  }
}

class _PostIconAction extends StatelessWidget {
  const _PostIconAction({
    required this.tooltip,
    required this.icon,
    required this.count,
    required this.color,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final int? count;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17, color: color),
              if (count != null) ...[
                const SizedBox(width: 4),
                Text(
                  count.toString(),
                  style: asanaTextStyle(
                    Theme.of(context).textTheme.bodySmall,
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

String _date(DateTime? value) {
  if (value != null) {
    final diff = DateTime.now().difference(value.toLocal());
    if (!diff.isNegative && diff.inHours < 24) {
      final hours = diff.inHours <= 0 ? 1 : diff.inHours;
      return hours == 1 ? '1 hour' : '$hours hours';
    }
  }
  return HkTime.formatInstantAsHk(value, 'yyyy-MM-dd');
}
