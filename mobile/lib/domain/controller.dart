import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'models.dart';

/// The application state and API boundary. UI never owns persistent business data.
abstract class PulseController extends ChangeNotifier {
  UserProfile? get user;
  List<CampusPost> get posts;
  List<Category> get categories;
  List<CampusPost> get savedPosts;
  List<CampusPost> get myPosts;
  List<CampusPost> get moderationPosts;
  bool get loading;
  String? get error;
  String? get selectedCategory;
  String get searchQuery;
  String get feedMode;
  ThemeMode get themeMode;
  Color get accent;
  String get baseUrl;
  bool get automaticConnection => false;

  Future<void> initialize();
  Future<void> loadFeed({
    String? categoryId,
    String? query,
    String? mode,
    bool eventsOnly = false,
  });
  Future<void> loadSavedPosts();
  Future<void> login(String email, String password);
  Future<void> register(Map<String, dynamic> fields);
  Future<void> logout();
  Future<CampusPost> loadPost(String id);
  Future<List<CampusComment>> loadComments(String postId);
  Future<void> addComment(String postId, String body, {String? parentId});
  Future<void> deleteComment(String commentId);
  Future<void> reportComment(String commentId, String reason);
  Future<void> react(String postId, String reaction);
  Future<void> bookmark(String postId);
  Future<void> attend(String postId);
  Future<void> follow(String userId);
  Future<List<UserProfile>> lookupUsers(String query);
  Future<List<UserProfile>> loadFriends();
  Future<Map<String, List<UserProfile>>> loadFriendRequests();
  Future<void> sendFriendRequest(String userId);
  Future<void> acceptFriendRequest(String userId);
  Future<void> removeFriendship(String userId);
  Future<List<Map<String, dynamic>>> loadChats();
  Future<Map<String, dynamic>> openChat(String userId);
  Future<List<Map<String, dynamic>>> loadMessages(
    String chatId, {
    int? afterId,
    int? beforeId,
  });
  Future<Map<String, dynamic>> sendMessage(
    String chatId,
    String body, {
    String? imageUrl,
  });
  Future<void> markChatRead(String chatId);
  Future<String?> pickAndUploadChatImage(String chatId);
  Future<Uint8List> loadChatImage(String url);
  Future<List<Map<String, dynamic>>> loadCommentReports();
  Future<void> resolveCommentReport(String reportId, String action);
  Future<UserProfile> getProfile(String userId);
  Future<List<CampusPost>> getUserPosts(String userId);
  Future<void> updateProfile(Map<String, dynamic> fields);
  Future<CampusPost> createPost(Map<String, dynamic> fields);
  Future<CampusPost> updatePost(String id, Map<String, dynamic> fields);
  Future<void> submitPost(String id);
  Future<void> loadMyPosts();
  Future<void> loadModeration();

  /// Decision is 'approve', 'return', or 'reject'. A reason is required for return/reject.
  Future<void> moderate(String postId, String decision, {String reason = ''});
  Future<List<ModerationEntry>> loadModerationHistory(String postId);
  Future<String?> pickAndUploadImage();
  Future<List<String>> pickAndUploadImages({int remaining = 6}) async {
    final image = await pickAndUploadImage();
    return image == null ? [] : [image];
  }

  Future<void> appealPost(String postId) async =>
      throw UnsupportedError('Ручная перепроверка недоступна');
  Future<void> toggleTopic(String categoryId) async {
    final topics = user?.interests.toSet() ?? <String>{};
    if (!topics.remove(categoryId)) topics.add(categoryId);
    await updateProfile({'interests': topics.toList()});
  }

  void setAppearance({ThemeMode? mode, Color? accent});
  Future<void> setConnection(String url);
}
