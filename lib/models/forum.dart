class ForumThread {
  const ForumThread({
    required this.id,
    required this.title,
    required this.category,
    required this.status,
    required this.pinned,
    required this.locked,
    this.createdBy,
    this.createdByName,
    this.createdAt,
    this.updatedBy,
    this.updatedAt,
    this.rootPostId,
    this.likeCount = 0,
    this.likedByCurrentUser = false,
    this.replyCount = 0,
  });

  final String id;
  final String title;
  final String category;
  final String status;
  final bool pinned;
  final bool locked;
  final String? createdBy;
  final String? createdByName;
  final DateTime? createdAt;
  final String? updatedBy;
  final DateTime? updatedAt;
  final String? rootPostId;
  final int likeCount;
  final bool likedByCurrentUser;
  final int replyCount;

  bool get isDeleted => status.trim().toLowerCase() == 'deleted';

  ForumThread copyWith({
    String? id,
    String? title,
    String? category,
    String? status,
    bool? pinned,
    bool? locked,
    String? createdBy,
    String? createdByName,
    DateTime? createdAt,
    String? updatedBy,
    DateTime? updatedAt,
    String? rootPostId,
    int? likeCount,
    bool? likedByCurrentUser,
    int? replyCount,
  }) {
    return ForumThread(
      id: id ?? this.id,
      title: title ?? this.title,
      category: category ?? this.category,
      status: status ?? this.status,
      pinned: pinned ?? this.pinned,
      locked: locked ?? this.locked,
      createdBy: createdBy ?? this.createdBy,
      createdByName: createdByName ?? this.createdByName,
      createdAt: createdAt ?? this.createdAt,
      updatedBy: updatedBy ?? this.updatedBy,
      updatedAt: updatedAt ?? this.updatedAt,
      rootPostId: rootPostId ?? this.rootPostId,
      likeCount: likeCount ?? this.likeCount,
      likedByCurrentUser: likedByCurrentUser ?? this.likedByCurrentUser,
      replyCount: replyCount ?? this.replyCount,
    );
  }
}

class ForumPost {
  const ForumPost({
    required this.id,
    required this.threadId,
    this.parentPostId,
    required this.depth,
    required this.content,
    required this.status,
    this.createdBy,
    this.createdByName,
    this.createdAt,
    this.updatedBy,
    this.updatedAt,
    this.likeCount = 0,
    this.likedByCurrentUser = false,
  });

  final String id;
  final String threadId;
  final String? parentPostId;
  final int depth;
  final String content;
  final String status;
  final String? createdBy;
  final String? createdByName;
  final DateTime? createdAt;
  final String? updatedBy;
  final DateTime? updatedAt;
  final int likeCount;
  final bool likedByCurrentUser;

  bool get isDeleted => status.trim().toLowerCase() == 'deleted';

  ForumPost copyWith({
    String? id,
    String? threadId,
    String? parentPostId,
    int? depth,
    String? content,
    String? status,
    String? createdBy,
    String? createdByName,
    DateTime? createdAt,
    String? updatedBy,
    DateTime? updatedAt,
    int? likeCount,
    bool? likedByCurrentUser,
  }) {
    return ForumPost(
      id: id ?? this.id,
      threadId: threadId ?? this.threadId,
      parentPostId: parentPostId ?? this.parentPostId,
      depth: depth ?? this.depth,
      content: content ?? this.content,
      status: status ?? this.status,
      createdBy: createdBy ?? this.createdBy,
      createdByName: createdByName ?? this.createdByName,
      createdAt: createdAt ?? this.createdAt,
      updatedBy: updatedBy ?? this.updatedBy,
      updatedAt: updatedAt ?? this.updatedAt,
      likeCount: likeCount ?? this.likeCount,
      likedByCurrentUser: likedByCurrentUser ?? this.likedByCurrentUser,
    );
  }
}

class ForumPostLikeUser {
  const ForumPostLikeUser({
    required this.staffId,
    required this.displayName,
    this.likedAt,
  });

  final String staffId;
  final String displayName;
  final DateTime? likedAt;
}
