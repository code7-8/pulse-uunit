import 'package:flutter/material.dart';
import 'package:pulse/domain/controller.dart';
import 'package:pulse/domain/models.dart';

class FakePulseController extends PulseController {
  FakePulseController({bool signedIn = true, bool moderator = false}) {
    user = signedIn
        ? UserProfile(
            id: '1',
            name: 'Александра Константинопольская',
            handle: 'alexandra',
            faculty: 'Институт информатики, математики и робототехники',
            course: '3',
            bio:
                'Занимаюсь робототехникой и организую университетские события.',
            role: moderator ? 'moderator' : 'student',
            interests: const ['science', 'campus'],
            publicationsCount: 2,
            friendsCount: 3,
            followersCount: 12,
            followingCount: 8,
          )
        : null;
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    allPosts = [
      CampusPost(
        id: 'news-1',
        title:
            'Студенты УУНИТ представили университет на всероссийском инженерном чемпионате и прошли в финал',
        body:
            'Команда университета разработала прототип автономной системы и представила результаты на инженерном чемпионате.\n\nНа встрече участники расскажут о подготовке, работе над проектом и возможностях присоединиться к команде.',
        excerpt:
            'Команда университета прошла в финал инженерного чемпионата. Рассказываем, как готовился проект и кто над ним работал.',
        author:
            user ??
            const UserProfile(id: '1', name: 'Александра Константинопольская'),
        category: categories.first,
        createdAt: DateTime.now().subtract(const Duration(hours: 2)),
        publishedAt: DateTime.now().subtract(const Duration(hours: 2)),
        commentsCount: 2,
        reactions: const {'like': 18},
      ),
      CampusPost(
        id: 'event-1',
        type: 'event',
        title:
            'Открытая встреча лаборатории: от первой идеи до собственного инженерного проекта',
        body:
            'Обсудим проекты лаборатории и покажем оборудование. Можно прийти без предварительной подготовки. Приглашаем студентов всех курсов.',
        author: const UserProfile(id: '2', name: 'Михаил Александров'),
        category: categories[1],
        createdAt: DateTime.now(),
        publishedAt: DateTime.now(),
        eventStart: DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 18),
        location:
            'Главный корпус, аудитория 5-312, вход со стороны улицы Карла Маркса',
        price: 'Бесплатно',
        attendeesCount: 23,
        friendsAttendingCount: 1,
        friendAttendees: const [
          UserProfile(id: '2', name: 'Михаил Александров'),
        ],
      ),
    ];
    posts = [...allPosts];
  }

  late List<CampusPost> allPosts;
  int initializeCalls = 0;
  bool submitted = false;
  Map<String, dynamic>? lastCreatedFields;
  String? lastComment, lastCommentParent, moderationDecision, moderationReason;
  final List<Map<String, dynamic>> messages = [];
  final List<CampusComment> comments = [
    CampusComment(
      id: 'comment-1',
      body: 'Подскажите, можно ли прийти студентам первого курса?',
      author: const UserProfile(id: '3', name: 'Никита Фёдоров'),
      createdAt: DateTime.now(),
    ),
  ];

  @override
  UserProfile? user;
  @override
  List<CampusPost> posts = [];
  @override
  final List<Category> categories = const [
    Category(id: 'campus', name: 'Кампус'),
    Category(id: 'science', name: 'Наука'),
    Category(id: 'career', name: 'Карьера'),
    Category(id: 'sport', name: 'Спорт'),
    Category(id: 'culture', name: 'Культура'),
    Category(id: 'community', name: 'Сообщества'),
  ];
  @override
  List<CampusPost> savedPosts = [];
  @override
  List<CampusPost> myPosts = [];
  @override
  List<CampusPost> moderationPosts = [];
  @override
  bool loading = false;
  @override
  String? error;
  @override
  String? selectedCategory;
  @override
  String searchQuery = '';
  @override
  String feedMode = 'all';
  @override
  ThemeMode themeMode = ThemeMode.light;
  @override
  Color accent = const Color(0xFF3459E6);
  @override
  String baseUrl = 'http://localhost:8000';

  @override
  Future<void> initialize() async {
    initializeCalls++;
  }

  @override
  Future<void> loadFeed({
    String? categoryId,
    String? query,
    String? mode,
    bool eventsOnly = false,
  }) async {
    selectedCategory = categoryId;
    searchQuery = query ?? '';
    feedMode = mode ?? 'all';
    posts = allPosts
        .where(
          (post) =>
              (!eventsOnly || post.isEvent) &&
              (categoryId == null || post.category?.id == categoryId),
        )
        .toList();
    notifyListeners();
  }

  @override
  Future<void> loadSavedPosts() async {
    notifyListeners();
  }

  @override
  Future<UserProfile> getProfile(String userId) async => userId == user?.id
      ? user!
      : const UserProfile(
          id: '2',
          name: 'Михаил Александров',
          friendshipStatus: 'friends',
          faculty: 'Институт электротехнических комплексов и систем',
        );
  @override
  Future<List<CampusPost>> getUserPosts(String userId) async =>
      allPosts.where((post) => post.author.id == userId).toList();
  @override
  Future<CampusPost> loadPost(String id) async =>
      allPosts.firstWhere((post) => post.id == id);
  @override
  Future<List<CampusComment>> loadComments(String postId) async => [
    ...comments,
  ];
  @override
  Future<void> addComment(
    String postId,
    String body, {
    String? parentId,
  }) async {
    lastComment = body;
    lastCommentParent = parentId;
    comments.add(
      CampusComment(
        id: 'comment-${comments.length + 1}',
        body: body,
        author: user!,
        parentId: parentId,
        createdAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<void> bookmark(String postId) async {}
  @override
  Future<void> react(String postId, String reaction) async {}
  @override
  Future<void> attend(String postId) async {}
  @override
  Future<void> loadMyPosts() async {
    myPosts = allPosts;
    notifyListeners();
  }

  @override
  Future<void> loadModeration() async {
    moderationPosts = allPosts;
    notifyListeners();
  }

  @override
  Future<List<ModerationEntry>> loadModerationHistory(String postId) async =>
      [];
  @override
  Future<List<UserProfile>> loadFriends() async => [];
  @override
  Future<Map<String, List<UserProfile>>> loadFriendRequests() async => {
    'incoming': [],
    'outgoing': [],
  };
  @override
  Future<List<UserProfile>> lookupUsers(String query) async => [];
  @override
  Future<List<Map<String, dynamic>>> loadChats() async => [];
  @override
  Future<Map<String, dynamic>> openChat(String userId) async => {
    'id': 1,
    'can_send': true,
    'peer': {
      'id': 2,
      'name': 'Михаил Александров',
      'handle': 'mikhail',
      'faculty': 'Институт электротехнических комплексов и систем',
    },
  };
  @override
  Future<List<Map<String, dynamic>>> loadMessages(
    String chatId, {
    int? afterId,
    int? beforeId,
  }) async => [...messages];
  @override
  Future<Map<String, dynamic>> sendMessage(
    String chatId,
    String body, {
    String? imageUrl,
  }) async {
    final message = <String, dynamic>{
      'id': messages.length + 1,
      'sender_id': 1,
      'body': body,
      'image_url': imageUrl,
      'created_at': DateTime.now().toIso8601String(),
    };
    messages.add(message);
    return message;
  }

  @override
  Future<void> markChatRead(String chatId) async {}
  @override
  Future<List<Map<String, dynamic>>> loadCommentReports() async => [];
  @override
  Future<CampusPost> createPost(Map<String, dynamic> fields) async {
    lastCreatedFields = fields;
    final created = CampusPost(
      id: 'new-post',
      title: fields['title'].toString(),
      body: fields['body'].toString(),
      author: user!,
      status: 'draft',
    );
    allPosts.add(created);
    return created;
  }

  @override
  Future<void> submitPost(String id) async {
    submitted = true;
  }

  @override
  Future<void> moderate(
    String postId,
    String decision, {
    String reason = '',
  }) async {
    moderationDecision = decision;
    moderationReason = reason;
  }

  @override
  void setAppearance({ThemeMode? mode, Color? accent}) {
    themeMode = mode ?? themeMode;
    this.accent = accent ?? this.accent;
    notifyListeners();
  }

  @override
  Future<void> setConnection(String url) async {
    baseUrl = url;
    notifyListeners();
  }

  @override
  Future<void> logout() async {
    user = null;
    notifyListeners();
  }

  @override
  Future<void> login(String email, String password) async {
    user = const UserProfile(id: '1', name: 'Александра Константинопольская');
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
