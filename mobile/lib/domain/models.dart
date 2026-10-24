import 'package:flutter/foundation.dart';

String _string(dynamic value, [String fallback = '']) =>
    value?.toString() ?? fallback;
int _integer(dynamic value) =>
    value is num ? value.toInt() : int.tryParse(_string(value)) ?? 0;
DateTime? _date(dynamic value) =>
    value == null ? null : DateTime.tryParse(value.toString());
Map<String, dynamic> _map(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

@immutable
class Category {
  const Category({
    required this.id,
    required this.name,
    this.color = '#3459E6',
  });
  final String id;
  final String name;
  final String color;
  factory Category.fromJson(Map<String, dynamic> json) => Category(
    id: _string(json['id']),
    name: _string(json['name']),
    color: _string(json['color'], '#3459E6'),
  );
}

@immutable
class UserProfile {
  const UserProfile({
    required this.id,
    required this.name,
    this.email = '',
    this.handle = '',
    this.faculty = '',
    this.course = '',
    this.bio = '',
    this.avatarUrl = '',
    this.avatarColor = '#3459E6',
    this.role = 'student',
    this.interests = const [],
    this.followersCount = 0,
    this.followingCount = 0,
    this.publicationsCount = 0,
    this.isFollowing = false,
    this.friendsCount = 0,
    this.friendshipStatus = 'none',
  });
  final String id,
      email,
      name,
      handle,
      faculty,
      course,
      bio,
      avatarUrl,
      avatarColor,
      role;
  final List<String> interests;
  final int followersCount, followingCount, publicationsCount;
  final bool isFollowing;
  final int friendsCount;
  final String friendshipStatus;
  bool get isModerator => role == 'moderator' || role == 'admin';
  String get initials {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    return parts.take(2).map((part) => part[0]).join().toUpperCase();
  }

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    id: _string(json['id']),
    email: _string(json['email']),
    name: _string(json['name'], 'Студент'),
    handle: _string(json['handle']),
    faculty: _string(json['faculty']),
    course: _string(json['course']),
    bio: _string(json['bio']),
    avatarUrl: _string(json['avatar_url']),
    avatarColor: _string(json['avatar_color'], '#3459E6'),
    role: _string(json['role'], 'student'),
    interests: (json['interests'] as List? ?? [])
        .map((e) => e.toString())
        .toList(),
    followersCount: _integer(json['followers_count']),
    followingCount: _integer(json['following_count']),
    publicationsCount: _integer(json['publications_count']),
    isFollowing: json['is_following'] == true,
    friendsCount: _integer(json['friends_count']),
    friendshipStatus: _string(json['friendship_status'], 'none'),
  );
}

@immutable
class CampusPost {
  const CampusPost({
    required this.id,
    required this.title,
    required this.body,
    required this.author,
    this.type = 'news',
    this.excerpt = '',
    this.coverUrl = '',
    this.imageUrls = const [],
    this.aiReview,
    this.category,
    this.status = 'published',
    this.moderationReason = '',
    this.createdAt,
    this.publishedAt,
    this.eventStart,
    this.eventEnd,
    this.location = '',
    this.price = '',
    this.registrationUrl = '',
    this.reactions = const {},
    this.myReaction,
    this.commentsCount = 0,
    this.isBookmarked = false,
    this.isAttending = false,
    this.attendeesCount = 0,
    this.friendAttendees = const [],
    this.friendsAttendingCount = 0,
    this.revision = '',
  });
  final String id,
      type,
      title,
      body,
      excerpt,
      coverUrl,
      status,
      moderationReason,
      location,
      price,
      registrationUrl;
  final UserProfile author;
  final Category? category;
  final DateTime? createdAt, publishedAt, eventStart, eventEnd;
  final Map<String, int> reactions;
  final String? myReaction;
  final int commentsCount, attendeesCount;
  final bool isBookmarked, isAttending;
  final List<UserProfile> friendAttendees;
  final int friendsAttendingCount;
  final String revision;
  final List<String> imageUrls;
  final Map<String, dynamic>? aiReview;
  List<String> get images => imageUrls.isNotEmpty
      ? imageUrls
      : coverUrl.isNotEmpty
      ? [coverUrl]
      : const [];
  bool get isEvent => type == 'event';
  int get reactionsCount =>
      reactions.values.fold(0, (sum, value) => sum + value);
  String get preview => excerpt.isNotEmpty ? excerpt : body;
  factory CampusPost.fromJson(Map<String, dynamic> json) {
    final category = json['category'];
    return CampusPost(
      id: _string(json['id']),
      type: _string(json['type'], 'news'),
      title: _string(json['title']),
      body: _string(json['body']),
      excerpt: _string(json['excerpt']),
      coverUrl: _string(json['cover_url']),
      imageUrls: (json['image_urls'] as List? ?? [])
          .map((value) => value.toString())
          .toList(),
      aiReview: json['ai_review'] is Map ? _map(json['ai_review']) : null,
      category: category is Map
          ? Category.fromJson(_map(category))
          : category == null
          ? null
          : Category(id: category.toString(), name: category.toString()),
      status: _string(json['status'], 'published'),
      moderationReason: _string(json['moderation_reason']),
      author: UserProfile.fromJson(_map(json['author'])),
      createdAt: _date(json['created_at']),
      publishedAt: _date(json['published_at']),
      eventStart: _date(json['event_start']),
      eventEnd: _date(json['event_end']),
      location: _string(json['location']),
      price: _string(json['price']),
      registrationUrl: _string(json['registration_url']),
      reactions: _map(
        json['reactions'],
      ).map((key, value) => MapEntry(key, _integer(value))),
      myReaction: json['my_reaction']?.toString(),
      commentsCount: _integer(json['comments_count']),
      isBookmarked: json['is_bookmarked'] == true,
      isAttending: json['is_attending'] == true,
      attendeesCount: _integer(json['attendees_count']),
      friendAttendees: (json['friend_attendees'] as List? ?? [])
          .map((value) => UserProfile.fromJson(_map(value)))
          .toList(),
      friendsAttendingCount: _integer(json['friends_attending_count']),
      revision: _string(json['updated_at']),
    );
  }
}

@immutable
class CampusComment {
  const CampusComment({
    required this.id,
    required this.body,
    required this.author,
    this.createdAt,
    this.parentId,
  });
  final String id, body;
  final UserProfile author;
  final DateTime? createdAt;
  final String? parentId;
  factory CampusComment.fromJson(Map<String, dynamic> json) => CampusComment(
    id: _string(json['id']),
    body: _string(json['body']),
    author: UserProfile.fromJson(_map(json['author'])),
    createdAt: _date(json['created_at']),
    parentId: json['parent_id']?.toString(),
  );
}

@immutable
class ModerationEntry {
  const ModerationEntry({
    required this.id,
    required this.action,
    this.reason = '',
    this.moderator,
    this.createdAt,
  });
  final String id, action, reason;
  final UserProfile? moderator;
  final DateTime? createdAt;
  factory ModerationEntry.fromJson(Map<String, dynamic> json) =>
      ModerationEntry(
        id: _string(json['id']),
        action: _string(json['action']),
        reason: _string(json['reason']),
        moderator: json['moderator'] is Map
            ? UserProfile.fromJson(_map(json['moderator']))
            : null,
        createdAt: _date(json['created_at']),
      );
}
