import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../domain/controller.dart';
import '../domain/models.dart';
import '../domain/comment_threads.dart';
import 'account_screens.dart';
import 'components.dart';
import 'publication_extras.dart';
import 'compose_screen.dart';

Future<void> openPost(
  BuildContext context,
  PulseController controller,
  CampusPost post,
) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => PostScreen(controller: controller, initialPost: post),
  ),
);

class PostScreen extends StatefulWidget {
  const PostScreen({
    super.key,
    required this.controller,
    required this.initialPost,
  });
  final PulseController controller;
  final CampusPost initialPost;
  @override
  State<PostScreen> createState() => _PostScreenState();
}

class _PostScreenState extends State<PostScreen> {
  late CampusPost _post;
  Timer? _aiTimer;
  bool _reacting = false, _bookmarking = false, _attending = false;
  PulseController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    _post = widget.initialPost;
    _reload(silent: true);
    _aiTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted &&
          ModalRoute.of(context)?.isCurrent == true &&
          ['queued', 'running'].contains(_post.aiReview?['status'])) {
        _reload(silent: true);
      }
    });
  }

  @override
  void dispose() {
    _aiTimer?.cancel();
    super.dispose();
  }

  Future<void> _reload({bool silent = false}) async {
    try {
      final post = await c.loadPost(_post.id);
      if (mounted) setState(() => _post = post);
    } catch (error) {
      if (!silent && mounted) notifyError(context, error);
    }
  }

  Future<void> _bookmark() async {
    if (!await requireAuth(context, c) || !mounted) return;
    setState(() => _bookmarking = true);
    if (await perform(context, () => c.bookmark(_post.id))) await _reload();
    if (mounted) setState(() => _bookmarking = false);
  }

  Future<void> _react() async {
    if (!await requireAuth(context, c) || !mounted) return;
    setState(() => _reacting = true);
    if (await perform(context, () => c.react(_post.id, 'like'))) {
      await _reload();
    }
    if (mounted) setState(() => _reacting = false);
  }

  Future<void> _comments() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => CommentsSheet(controller: c, postId: _post.id),
    );
    await _reload(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final post = _post;
    final hasCover = post.coverUrl.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: Text(post.isEvent ? 'Событие' : 'Публикация'),
        actions: [
          if (post.author.id == c.user?.id)
            IconButton(
              tooltip: 'Редактировать',
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ComposeScreen(controller: c, post: post),
                  ),
                );
                await _reload();
              },
              icon: const Icon(Icons.edit_outlined, size: 21),
            ),
          IconButton(
            tooltip: post.isBookmarked ? 'Убрать из избранного' : 'Сохранить',
            onPressed: _bookmarking ? null : _bookmark,
            icon: Icon(
              post.isBookmarked
                  ? Icons.bookmark_rounded
                  : Icons.bookmark_border_rounded,
              size: 23,
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: ContentWidth(
        child: RefreshIndicator(
          onRefresh: _reload,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 5, 20, 35),
            children: [
              if (hasCover) ...[
                PostGallery(
                  controller: c,
                  post: post,
                  height: 250,
                  borderRadius: BorderRadius.circular(22),
                ),
                const SizedBox(height: 23),
              ],
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  CategoryPill(
                    label: post.category?.name ?? 'УУНИТ',
                    color: parseColor(post.category?.color ?? '#3459E6'),
                  ),
                  if (post.isEvent)
                    const CategoryPill(
                      label: 'Событие',
                      icon: Icons.event_outlined,
                    ),
                  if (post.status != 'published')
                    StatusPill(
                      status:
                          [
                            'queued',
                            'running',
                          ].contains(post.aiReview?['status'])
                          ? 'ai_review'
                          : post.status,
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                post.title,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontSize: 30,
                  height: 1.17,
                  letterSpacing: -.8,
                ),
              ),
              const SizedBox(height: 22),
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => openProfile(context, c, post.author.id),
                child: Row(
                  children: [
                    PulseAvatar(controller: c, user: post.author, radius: 21),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            post.author.name,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            [
                              if (post.author.faculty.isNotEmpty)
                                post.author.faculty,
                              relativeDate(post.publishedAt ?? post.createdAt),
                            ].where((text) => text.isNotEmpty).join(' · '),
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 19,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
              AiReviewPanel(controller: c, post: post, onChanged: _reload),
              if (post.moderationReason.isNotEmpty &&
                  post.status != 'published') ...[
                const SizedBox(height: 22),
                Container(
                  padding: const EdgeInsets.all(17),
                  decoration: BoxDecoration(
                    color: const Color(0xFFB7832F).withValues(alpha: .09),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        post.aiReview?['status'] == 'changes_requested'
                            ? 'Замечание ИИ'
                            : 'Комментарий модератора',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        post.moderationReason,
                        style: const TextStyle(fontSize: 13, height: 1.6),
                      ),
                    ],
                  ),
                ),
              ],
              if (post.isEvent) ...[
                const SizedBox(height: 25),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    border: Border.all(
                      color: theme.colorScheme.outline.withValues(alpha: .75),
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    children: [
                      if (post.eventStart != null)
                        _EventInfo(
                          icon: Icons.schedule_rounded,
                          title: dateLabel(post.eventStart, time: true),
                          subtitle: post.eventEnd == null
                              ? 'Дата и время'
                              : 'До ${dateLabel(post.eventEnd, time: true)}',
                        ),
                      if (post.location.isNotEmpty) ...[
                        const SizedBox(height: 17),
                        _EventInfo(
                          icon: Icons.place_outlined,
                          title: post.location,
                          subtitle: 'Место проведения',
                        ),
                      ],
                      const SizedBox(height: 17),
                      _EventInfo(
                        icon: Icons.confirmation_number_outlined,
                        title: post.price.isEmpty || post.price == '0'
                            ? 'Бесплатно'
                            : post.price,
                        subtitle: 'Участие',
                      ),
                      const SizedBox(height: 21),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _attending
                              ? null
                              : () async {
                                  if (!await requireAuth(context, c) ||
                                      !context.mounted) {
                                    return;
                                  }
                                  setState(() => _attending = true);
                                  if (await perform(
                                    context,
                                    () => c.attend(post.id),
                                  )) {
                                    await _reload();
                                  }
                                  if (mounted) {
                                    setState(() => _attending = false);
                                  }
                                },
                          icon: Icon(
                            post.isAttending
                                ? Icons.check_rounded
                                : Icons.add_rounded,
                            size: 18,
                          ),
                          label: Text(
                            _attending
                                ? 'Сохраняем…'
                                : post.isAttending
                                ? 'Вы участвуете'
                                : 'Буду участвовать',
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        countLabel(
                          post.attendeesCount,
                          'участник',
                          'участника',
                          'участников',
                        ),
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 7),
                      Text(
                        'Отметку об участии увидят друзья',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 10,
                        ),
                      ),
                      if (post.friendsAttendingCount > 0) ...[
                        const SizedBox(height: 17),
                        const Divider(),
                        const SizedBox(height: 15),
                        Row(
                          children: [
                            for (final friend in post.friendAttendees.take(3))
                              Padding(
                                padding: const EdgeInsets.only(right: 5),
                                child: PulseAvatar(
                                  controller: c,
                                  user: friend,
                                  radius: 15,
                                  onTap: () =>
                                      openProfile(context, c, friend.id),
                                ),
                              ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                post.friendAttendees.isEmpty
                                    ? countLabel(
                                        post.friendsAttendingCount,
                                        'друг идёт',
                                        'друга идут',
                                        'друзей идут',
                                      )
                                    : '${post.friendAttendees.first.name.split(' ').first}${post.friendsAttendingCount > 1 ? ' и ещё ${post.friendsAttendingCount - 1}' : ''} ${post.friendsAttendingCount > 1 ? 'идут' : 'идёт'}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (post.registrationUrl.isNotEmpty)
                        TextButton.icon(
                          onPressed: () async {
                            final uri = Uri.tryParse(post.registrationUrl);
                            if (uri == null ||
                                !['https', 'http'].contains(uri.scheme)) {
                              notifyError(context, 'Не удалось открыть ссылку');
                              return;
                            }
                            try {
                              if (!await launchUrl(
                                    uri,
                                    mode: LaunchMode.externalApplication,
                                  ) &&
                                  context.mounted) {
                                notifyError(
                                  context,
                                  'Не удалось открыть ссылку',
                                );
                              }
                            } catch (error) {
                              if (context.mounted) notifyError(context, error);
                            }
                          },
                          icon: const Icon(Icons.open_in_new_rounded, size: 15),
                          label: const Text(
                            'Страница регистрации',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 27),
              SelectableText(
                post.body,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.85,
                  letterSpacing: -.1,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 28),
              const Divider(),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Обсуждение',
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  Text(
                    '${post.commentsCount}',
                    style: TextStyle(
                      fontSize: 20,
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                post.commentsCount == 0
                    ? 'Обсудите публикацию или задайте вопрос автору.'
                    : 'Вопросы, идеи и впечатления участников.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              InkWell(
                onTap: _comments,
                borderRadius: BorderRadius.circular(15),
                child: Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    border: Border.all(color: theme.colorScheme.outline),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Row(
                    children: [
                      if (c.user != null)
                        PulseAvatar(controller: c, user: c.user!, radius: 16)
                      else
                        Icon(
                          Icons.mode_comment_outlined,
                          size: 21,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Написать комментарий',
                          style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.arrow_forward_rounded,
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: ContentWidth(
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(
                top: BorderSide(
                  color: theme.colorScheme.outline.withValues(alpha: .6),
                ),
              ),
            ),
            child: Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _reacting ? null : _react,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: post.myReaction != null
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface,
                    side: BorderSide(
                      color: post.myReaction != null
                          ? theme.colorScheme.primary.withValues(alpha: .4)
                          : theme.colorScheme.outline,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  icon: Icon(
                    post.myReaction != null
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    size: 19,
                  ),
                  label: Text('${post.reactionsCount}'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _comments,
                    icon: const Icon(Icons.mode_comment_outlined, size: 18),
                    label: Text(
                      post.commentsCount == 0
                          ? 'Обсудить'
                          : 'Комментарии · ${post.commentsCount}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
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

class _EventInfo extends StatelessWidget {
  const _EventInfo({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  final IconData icon;
  final String title, subtitle;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: .07),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Icon(
          icon,
          size: 20,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 13,
                height: 1.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              subtitle,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontSize: 10),
            ),
          ],
        ),
      ),
    ],
  );
}

class CommentsSheet extends StatefulWidget {
  const CommentsSheet({
    super.key,
    required this.controller,
    required this.postId,
  });
  final PulseController controller;
  final String postId;
  @override
  State<CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<CommentsSheet> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  List<CampusComment> _comments = [];
  CampusComment? _reply;
  bool _loading = true, _sending = false;
  String? _error;
  PulseController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final comments = await c.loadComments(widget.postId);
      if (mounted) {
        setState(() {
          _comments = comments;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    if (_text.text.trim().isEmpty) return;
    if (!await requireAuth(context, c) || !mounted) return;
    setState(() => _sending = true);
    final sent = await perform(
      context,
      () =>
          c.addComment(widget.postId, _text.text.trim(), parentId: _reply?.id),
    );
    if (!mounted) return;
    if (sent) {
      _text.clear();
      setState(() => _reply = null);
      await _load();
    }
    if (mounted) setState(() => _sending = false);
  }

  Future<void> _report(CampusComment comment) async {
    if (!await requireAuth(context, c) || !mounted) return;
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Причина жалобы', style: TextStyle(fontSize: 19)),
        children: [
          for (final label in [
            'Спам и реклама',
            'Оскорбления',
            'Недостоверная информация',
            'Другое',
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(label),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
              child: Text(label),
            ),
        ],
      ),
    );
    if (reason != null && mounted) {
      await perform(
        context,
        () => c.reportComment(comment.id, reason),
        success: 'Жалоба отправлена модератору',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final threaded = threadComments(_comments);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height:
            (MediaQuery.sizeOf(context).height * .83 -
                    MediaQuery.viewInsetsOf(context).bottom)
                .clamp(180.0, double.infinity),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 15, 15),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Обсуждение',
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Text(
                    '${_comments.length}',
                    style: TextStyle(
                      fontSize: 17,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Обновить комментарии',
                    onPressed: _load,
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                  ),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : _error != null
                  ? EmptyState(
                      icon: Icons.wifi_off_rounded,
                      title: 'Не удалось загрузить комментарии',
                      description: _error,
                      label: 'Повторить',
                      action: _load,
                    )
                  : _comments.isEmpty
                  ? const SingleChildScrollView(
                      child: EmptyState(
                        icon: Icons.chat_bubble_outline_rounded,
                        title: 'Начните обсуждение',
                        description: 'Задайте вопрос или поделитесь мнением.',
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 19, 17, 12),
                        itemCount: threaded.length,
                        itemBuilder: (context, index) {
                          final entry = threaded[index];
                          final comment = entry.comment;
                          final own = comment.author.id == c.user?.id;
                          final canDelete = own || c.user?.isModerator == true;
                          return Padding(
                            padding: EdgeInsets.only(
                              bottom: 23,
                              left: entry.depth.clamp(0, 2) * 24.0,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                PulseAvatar(
                                  controller: c,
                                  user: comment.author,
                                  radius: 17,
                                  onTap: () => openProfile(
                                    context,
                                    c,
                                    comment.author.id,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: GestureDetector(
                                              onTap: () => openProfile(
                                                context,
                                                c,
                                                comment.author.id,
                                              ),
                                              child: Text(
                                                comment.author.name,
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                          ),
                                          PopupMenuButton<String>(
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(),
                                            icon: Icon(
                                              Icons.more_horiz_rounded,
                                              size: 18,
                                              color: theme
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                            onSelected: (value) async {
                                              if (value == 'delete') {
                                                if (await perform(
                                                  context,
                                                  () => c.deleteComment(
                                                    comment.id,
                                                  ),
                                                )) {
                                                  await _load();
                                                }
                                              } else {
                                                await _report(comment);
                                              }
                                            },
                                            itemBuilder: (_) => [
                                              if (canDelete)
                                                const PopupMenuItem(
                                                  value: 'delete',
                                                  child: Text(
                                                    'Удалить',
                                                    style: TextStyle(
                                                      fontSize: 13,
                                                    ),
                                                  ),
                                                ),
                                              if (!own)
                                                const PopupMenuItem(
                                                  value: 'report',
                                                  child: Text(
                                                    'Пожаловаться',
                                                    style: TextStyle(
                                                      fontSize: 13,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ],
                                      ),
                                      if (comment.parentId != null)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 5,
                                          ),
                                          child: Text(
                                            entry.parent == null
                                                ? 'Ответ в обсуждении'
                                                : 'Ответ: ${entry.parent!.author.name}',
                                            style: TextStyle(
                                              color: theme.colorScheme.primary,
                                              fontSize: 9,
                                            ),
                                          ),
                                        ),
                                      Text(
                                        comment.body,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          height: 1.65,
                                        ),
                                      ),
                                      const SizedBox(height: 7),
                                      Row(
                                        children: [
                                          Text(
                                            relativeDate(comment.createdAt),
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(fontSize: 9),
                                          ),
                                          const SizedBox(width: 13),
                                          InkWell(
                                            onTap: () {
                                              setState(() => _reply = comment);
                                              _focus.requestFocus();
                                            },
                                            child: Text(
                                              'Ответить',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w700,
                                                color:
                                                    theme.colorScheme.primary,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
            ),
            const Divider(),
            if (_reply != null)
              Container(
                color: theme.colorScheme.primary.withValues(alpha: .05),
                padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.reply_rounded,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        'Ответ: ${_reply!.author.name}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Отменить ответ',
                      onPressed: () => setState(() => _reply = null),
                      icon: const Icon(Icons.close_rounded, size: 17),
                    ),
                  ],
                ),
              ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 13, 16, 14),
                child: c.user == null
                    ? SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () async {
                            if (await requireAuth(context, c) && mounted) {
                              setState(() {});
                            }
                          },
                          child: const Text('Войти, чтобы комментировать'),
                        ),
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _text,
                              focusNode: _focus,
                              minLines: 1,
                              maxLines: 4,
                              maxLength: 2000,
                              textCapitalization: TextCapitalization.sentences,
                              decoration: const InputDecoration(
                                hintText: 'Ваш комментарий',
                                counterText: '',
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 13,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 9),
                          IconButton.filled(
                            tooltip: 'Отправить комментарий',
                            onPressed: _sending ? null : _send,
                            style: IconButton.styleFrom(
                              minimumSize: const Size(47, 47),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            icon: _sending
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(
                                    Icons.arrow_upward_rounded,
                                    size: 22,
                                  ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
