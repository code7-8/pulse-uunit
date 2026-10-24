import 'package:flutter/material.dart';
import '../domain/controller.dart';
import '../domain/models.dart';
import 'account_screens.dart';
import 'components.dart';
import 'publication_extras.dart';
import 'compose_screen.dart';
import 'post_screen.dart';

class MyPostsScreen extends StatefulWidget {
  const MyPostsScreen({super.key, required this.controller});
  final PulseController controller;
  @override
  State<MyPostsScreen> createState() => _MyPostsScreenState();
}

class _MyPostsScreenState extends State<MyPostsScreen> {
  String _filter = 'all';
  bool _loading = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    await perform(context, widget.controller.loadMyPosts);
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      final theme = Theme.of(context);
      final posts = c.myPosts
          .where(
            (post) =>
                _filter == 'all' ||
                _filter == 'pending' &&
                    [
                      'pending',
                      'pending_review',
                      'submitted',
                    ].contains(post.status) ||
                _filter == 'returned' &&
                    [
                      'returned',
                      'changes_requested',
                      'needs_changes',
                      'rejected',
                    ].contains(post.status) ||
                post.status == _filter,
          )
          .toList();
      return Scaffold(
        appBar: AppBar(title: const Text('Мои публикации')),
        floatingActionButton: FloatingActionButton(
          tooltip: 'Создать публикацию',
          onPressed: () async {
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ComposeScreen(controller: c),
              ),
            );
            await _load();
          },
          backgroundColor: theme.colorScheme.primary,
          foregroundColor: Colors.white,
          child: const Icon(Icons.add_rounded),
        ),
        body: ContentWidth(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 95),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                Text('Мои материалы', style: theme.textTheme.headlineMedium),
                const SizedBox(height: 9),
                Text(
                  'Здесь сохраняются черновики, решения модератора и опубликованные материалы.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 22),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final filter in <(String, String)>[
                        ('all', 'Все'),
                        ('draft', 'Черновики'),
                        ('pending', 'На проверке'),
                        ('returned', 'Доработать'),
                        ('published', 'Опубликовано'),
                      ])
                        Padding(
                          padding: const EdgeInsets.only(right: 7),
                          child: ChoiceChip(
                            label: Text(filter.$2),
                            selected: _filter == filter.$1,
                            onSelected: (_) =>
                                setState(() => _filter = filter.$1),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 23),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else if (posts.isEmpty)
                  const EmptyState(
                    icon: Icons.edit_note_rounded,
                    title: 'Публикаций пока нет',
                    description:
                        'Создайте новость или событие. Черновик будет доступен только вам.',
                  ),
                for (final post in posts)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 17),
                    child: _SubmissionCard(
                      controller: c,
                      post: post,
                      onChanged: _load,
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _SubmissionCard extends StatefulWidget {
  const _SubmissionCard({
    required this.controller,
    required this.post,
    required this.onChanged,
  });
  final PulseController controller;
  final CampusPost post;
  final Future<void> Function() onChanged;
  @override
  State<_SubmissionCard> createState() => _SubmissionCardState();
}

class _SubmissionCardState extends State<_SubmissionCard> {
  bool _sending = false;
  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final c = widget.controller;
    final theme = Theme.of(context);
    final pending = [
      'pending',
      'pending_review',
      'submitted',
    ].contains(post.status);
    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                StatusPill(
                  status:
                      ['queued', 'running'].contains(post.aiReview?['status'])
                      ? 'ai_review'
                      : post.status,
                ),
                const Spacer(),
                Text(
                  dateLabel(post.createdAt),
                  style: theme.textTheme.bodySmall?.copyWith(fontSize: 10),
                ),
              ],
            ),
            const SizedBox(height: 14),
            InkWell(
              onTap: () => openPost(context, c, post),
              child: Text(
                post.title,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontSize: 19,
                  height: 1.3,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              post.preview.replaceAll('\n', ' '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
            AiReviewPanel(
              controller: c,
              post: post,
              onChanged: widget.onChanged,
            ),
            if (post.moderationReason.isNotEmpty &&
                post.status != 'published') ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: const Color(0xFFB7832F).withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post.aiReview?['status'] == 'changes_requested'
                          ? 'Замечание ИИ'
                          : 'Комментарий модератора',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      post.moderationReason,
                      style: const TextStyle(fontSize: 12, height: 1.6),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 17),
            Wrap(
              spacing: 9,
              runSpacing: 9,
              children: [
                OutlinedButton.icon(
                  onPressed: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            ComposeScreen(controller: c, post: post),
                      ),
                    );
                    await widget.onChanged();
                  },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 12,
                    ),
                    minimumSize: const Size(0, 42),
                  ),
                  icon: const Icon(Icons.edit_outlined, size: 15),
                  label: const Text(
                    'Редактировать',
                    style: TextStyle(fontSize: 10),
                  ),
                ),
                if (!pending && post.status != 'published')
                  FilledButton(
                    onPressed: _sending
                        ? null
                        : () async {
                            setState(() => _sending = true);
                            if (await perform(
                              context,
                              () => c.submitPost(post.id),
                              success: 'Отправлено на проверку',
                            )) {
                              await widget.onChanged();
                            }
                            if (mounted) setState(() => _sending = false);
                          },
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 13,
                        vertical: 12,
                      ),
                      minimumSize: const Size(0, 42),
                    ),
                    child: Text(
                      _sending
                          ? 'Отправляем…'
                          : post.status == 'draft'
                          ? 'На проверку'
                          : 'Отправить повторно',
                      style: const TextStyle(fontSize: 10),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            _HistorySection(controller: c, postId: post.id),
          ],
        ),
      ),
    );
  }
}

class _HistorySection extends StatefulWidget {
  const _HistorySection({required this.controller, required this.postId});
  final PulseController controller;
  final String postId;
  @override
  State<_HistorySection> createState() => _HistorySectionState();
}

class _HistorySectionState extends State<_HistorySection> {
  Future<List<ModerationEntry>>? _future;
  @override
  Widget build(BuildContext context) => Theme(
    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
    child: ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      dense: true,
      title: Text(
        'История проверки',
        style: TextStyle(
          fontSize: 10,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      onExpansionChanged: (expanded) {
        if (expanded) {
          setState(
            () => _future ??= widget.controller.loadModerationHistory(
              widget.postId,
            ),
          );
        }
      },
      children: [
        FutureBuilder<List<ModerationEntry>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.all(15),
                child: SizedBox(
                  width: 17,
                  height: 17,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              );
            }
            if (snapshot.hasError) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 9),
                child: Text(
                  'Не удалось загрузить историю',
                  style: TextStyle(fontSize: 11),
                ),
              );
            }
            final entries = snapshot.data ?? [];
            if (entries.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 9),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Решений пока нет',
                    style: TextStyle(fontSize: 11),
                  ),
                ),
              );
            }
            return Column(
              children: entries
                  .map(
                    (entry) => Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            switch (entry.action) {
                              'approve' ||
                              'approved' => Icons.check_circle_outline_rounded,
                              'reject' || 'rejected' => Icons.cancel_outlined,
                              _ => Icons.history_rounded,
                            },
                            size: 17,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  switch (entry.action) {
                                    'approve' || 'approved' => 'Одобрено',
                                    'reject' || 'rejected' => 'Отклонено',
                                    'return' ||
                                    'returned' ||
                                    'changes_requested' =>
                                      'Возвращено на доработку',
                                    'submit' ||
                                    'submitted' => 'Отправлено на проверку',
                                    'edited' => 'Изменено автором',
                                    _ => entry.action,
                                  },
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  [
                                    entry.moderator?.name ?? '',
                                    dateLabel(entry.createdAt, time: true),
                                  ].where((e) => e.isNotEmpty).join(' · '),
                                  style: Theme.of(
                                    context,
                                  ).textTheme.bodySmall?.copyWith(fontSize: 9),
                                ),
                                if (entry.reason.isNotEmpty) ...[
                                  const SizedBox(height: 5),
                                  Text(
                                    entry.reason,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      height: 1.6,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            );
          },
        ),
      ],
    ),
  );
}

class ModerationScreen extends StatefulWidget {
  const ModerationScreen({super.key, required this.controller});
  final PulseController controller;
  @override
  State<ModerationScreen> createState() => _ModerationScreenState();
}

class _ModerationScreenState extends State<ModerationScreen> {
  bool _loading = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    await perform(context, widget.controller.loadModeration);
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      final theme = Theme.of(context);
      return Scaffold(
        appBar: AppBar(
          title: const Text('Модерация'),
          actions: [
            IconButton(
              tooltip: 'Жалобы на комментарии',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => CommentReportsScreen(controller: c),
                ),
              ),
              icon: const Icon(Icons.flag_outlined),
            ),
            const SizedBox(width: 6),
          ],
        ),
        body: ContentWidth(
          child: c.user?.isModerator != true
              ? const EmptyState(
                  icon: Icons.lock_outline_rounded,
                  title: 'Доступ для модераторов',
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 35),
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              'Очередь проверки',
                              style: theme.textTheme.headlineMedium,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 13,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary.withValues(
                                alpha: .09,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${c.moderationPosts.length}',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 20,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Проверьте содержание, факты и оформление перед публикацией.',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 25),
                      if (_loading)
                        const Padding(
                          padding: EdgeInsets.all(45),
                          child: Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      else if (c.moderationPosts.isEmpty)
                        const EmptyState(
                          icon: Icons.fact_check_outlined,
                          title: 'Всё проверено',
                          description:
                              'Новые публикации появятся здесь, когда авторы отправят их на проверку.',
                        ),
                      for (final post in c.moderationPosts)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 15),
                          child: Material(
                            color: theme.colorScheme.surface,
                            borderRadius: BorderRadius.circular(20),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: () async {
                                await Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => ModerationReviewScreen(
                                      controller: c,
                                      initialPost: post,
                                    ),
                                  ),
                                );
                                await _load();
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(18),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        CategoryPill(
                                          label: post.isEvent
                                              ? 'Событие'
                                              : 'Новость',
                                        ),
                                        const Spacer(),
                                        Text(
                                          relativeDate(post.createdAt),
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(fontSize: 10),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 14),
                                    Text(
                                      post.title,
                                      style: theme.textTheme.titleLarge
                                          ?.copyWith(fontSize: 19, height: 1.3),
                                    ),
                                    const SizedBox(height: 9),
                                    Text(
                                      post.preview.replaceAll('\n', ' '),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall,
                                    ),
                                    const SizedBox(height: 17),
                                    Row(
                                      children: [
                                        PulseAvatar(
                                          controller: c,
                                          user: post.author,
                                          radius: 14,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            post.author.name,
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        Text(
                                          'Проверить',
                                          style: TextStyle(
                                            color: theme.colorScheme.primary,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(width: 5),
                                        Icon(
                                          Icons.arrow_forward_rounded,
                                          size: 16,
                                          color: theme.colorScheme.primary,
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
        ),
      );
    },
  );
}

class ModerationReviewScreen extends StatefulWidget {
  const ModerationReviewScreen({
    super.key,
    required this.controller,
    required this.initialPost,
  });
  final PulseController controller;
  final CampusPost initialPost;
  @override
  State<ModerationReviewScreen> createState() => _ModerationReviewScreenState();
}

class _ModerationReviewScreenState extends State<ModerationReviewScreen> {
  late CampusPost _post;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _post = widget.initialPost;
    _load();
  }

  Future<void> _load() async {
    try {
      final post = await widget.controller.loadPost(_post.id);
      if (mounted) setState(() => _post = post);
    } catch (error) {
      if (mounted) notifyError(context, error);
    }
  }

  Future<void> _decide(String decision) async {
    var reason = '';
    if (decision != 'approve') {
      final result = await showDialog<String>(
        context: context,
        builder: (_) => _ReasonDialog(reject: decision == 'reject'),
      );
      if (result == null || !mounted) return;
      reason = result;
    }
    setState(() => _busy = true);
    final ok = await perform(
      context,
      () => widget.controller.moderate(_post.id, decision, reason: reason),
      success: decision == 'approve'
          ? 'Публикация одобрена'
          : decision == 'return'
          ? 'Публикация возвращена автору'
          : 'Публикация отклонена',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final post = _post;
    return Scaffold(
      appBar: AppBar(title: const Text('Проверка публикации')),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 7, 20, 30),
          children: [
            if (post.coverUrl.isNotEmpty) ...[
              PostGallery(
                controller: widget.controller,
                post: post,
                height: 220,
                borderRadius: BorderRadius.circular(20),
              ),
              const SizedBox(height: 21),
            ],
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                StatusPill(status: post.status),
                CategoryPill(label: post.category?.name ?? 'Без категории'),
              ],
            ),
            const SizedBox(height: 15),
            AiReviewPanel(
              controller: widget.controller,
              post: post,
              onChanged: _load,
            ),
            Text(post.title, style: theme.textTheme.headlineMedium),
            const SizedBox(height: 20),
            InkWell(
              onTap: () =>
                  openProfile(context, widget.controller, post.author.id),
              child: Row(
                children: [
                  PulseAvatar(
                    controller: widget.controller,
                    user: post.author,
                    radius: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          post.author.name,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          dateLabel(post.createdAt, time: true),
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, size: 18),
                ],
              ),
            ),
            const SizedBox(height: 24),
            if (post.isEvent) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(17),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dateLabel(post.eventStart, time: true),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(post.location, style: const TextStyle(fontSize: 12)),
                    const SizedBox(height: 6),
                    Text(
                      post.price.isEmpty ? 'Бесплатно' : post.price,
                      style: const TextStyle(fontSize: 12),
                    ),
                    if (post.registrationUrl.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      SelectableText(
                        post.registrationUrl,
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 23),
            ],
            SelectableText(
              post.body,
              style: const TextStyle(fontSize: 14, height: 1.85),
            ),
            const SizedBox(height: 28),
            const Divider(),
            const SizedBox(height: 10),
            _HistorySection(controller: widget.controller, postId: post.id),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: ContentWidth(
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 13, 20, 13),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(top: BorderSide(color: theme.colorScheme.outline)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : () => _decide('approve'),
                    icon: const Icon(Icons.check_rounded, size: 19),
                    label: Text(
                      _busy ? 'Сохраняем решение…' : 'Одобрить и опубликовать',
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _busy ? null : () => _decide('return'),
                        child: const Text(
                          'На доработку',
                          style: TextStyle(fontSize: 11),
                        ),
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: TextButton(
                        onPressed: _busy ? null : () => _decide('reject'),
                        style: TextButton.styleFrom(
                          foregroundColor: theme.colorScheme.error,
                        ),
                        child: const Text(
                          'Отклонить',
                          style: TextStyle(fontSize: 11),
                        ),
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

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({required this.reject});
  final bool reject;
  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _text = TextEditingController();
  final _form = GlobalKey<FormState>();
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.reject ? 'Причина отказа' : 'Что нужно исправить?',
      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
    ),
    content: Form(
      key: _form,
      child: TextFormField(
        controller: _text,
        autofocus: true,
        minLines: 4,
        maxLines: 8,
        maxLength: 1000,
        decoration: const InputDecoration(
          hintText: 'Автор получит этот комментарий',
          alignLabelWithHint: true,
        ),
        validator: (value) =>
            (value ?? '').trim().length < 3 ? 'Укажите понятную причину' : null,
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Отмена'),
      ),
      FilledButton(
        onPressed: () {
          if (_form.currentState!.validate()) {
            Navigator.of(context).pop(_text.text.trim());
          }
        },
        child: const Text('Отправить'),
      ),
    ],
  );
}

class CommentReportsScreen extends StatefulWidget {
  const CommentReportsScreen({super.key, required this.controller});
  final PulseController controller;
  @override
  State<CommentReportsScreen> createState() => _CommentReportsScreenState();
}

class _CommentReportsScreenState extends State<CommentReportsScreen> {
  List<Map<String, dynamic>> _reports = [];
  bool _loading = true;
  String? _error, _resolving;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final reports = await widget.controller.loadCommentReports();
      if (mounted) {
        setState(() {
          _reports = reports;
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

  Future<void> _resolve(String id, String action) async {
    setState(() => _resolving = id);
    if (await perform(
      context,
      () => widget.controller.resolveCommentReport(id, action),
      success: action == 'delete_comment'
          ? 'Комментарий удалён'
          : 'Жалоба рассмотрена',
    )) {
      await _load();
    }
    if (mounted) setState(() => _resolving = null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Жалобы на комментарии')),
      body: ContentWidth(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 15, 20, 30),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              Text('Обсуждения', style: theme.textTheme.headlineMedium),
              const SizedBox(height: 9),
              Text(
                'Проверьте комментарий и причину обращения.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 25),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else if (_error != null)
                EmptyState(
                  icon: Icons.wifi_off_rounded,
                  title: 'Не удалось загрузить жалобы',
                  description: _error,
                  label: 'Повторить',
                  action: _load,
                )
              else if (_reports.isEmpty)
                const EmptyState(
                  icon: Icons.shield_outlined,
                  title: 'Новых жалоб нет',
                  description: 'Обращения пользователей появятся здесь.',
                ),
              for (final report in _reports) _reportCard(report),
            ],
          ),
        ),
      ),
    );
  }

  Widget _reportCard(Map<String, dynamic> report) {
    final theme = Theme.of(context);
    final id = '${report['id']}';
    final comment = report['comment'] is Map
        ? Map<String, dynamic>.from(report['comment'] as Map)
        : <String, dynamic>{};
    final author = comment['author'] is Map
        ? UserProfile.fromJson(
            Map<String, dynamic>.from(comment['author'] as Map),
          )
        : null;
    final reporter = report['reporter'] is Map
        ? UserProfile.fromJson(
            Map<String, dynamic>.from(report['reporter'] as Map),
          )
        : null;
    final busy = _resolving == id;
    return Container(
      margin: const EdgeInsets.only(bottom: 17),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CategoryPill(
                label: '${report['reason'] ?? 'Жалоба'}',
                color: const Color(0xFFC25353),
              ),
              const Spacer(),
              Text(
                dateLabel(DateTime.tryParse('${report['created_at'] ?? ''}')),
                style: theme.textTheme.bodySmall?.copyWith(fontSize: 9),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (author != null) ...[
            Row(
              children: [
                PulseAvatar(
                  controller: widget.controller,
                  user: author,
                  radius: 15,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    author.name,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 11),
          ],
          Text(
            '${comment['body'] ?? report['comment_body'] ?? 'Комментарий удалён'}',
            style: const TextStyle(fontSize: 13, height: 1.65),
          ),
          const SizedBox(height: 12),
          if (reporter != null)
            Text(
              'Обращение от ${reporter.name}',
              style: theme.textTheme.bodySmall?.copyWith(fontSize: 10),
            ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 9,
            runSpacing: 9,
            children: [
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.error,
                  minimumSize: const Size(0, 42),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 11,
                  ),
                ),
                onPressed: busy ? null : () => _resolve(id, 'delete_comment'),
                icon: const Icon(Icons.delete_outline_rounded, size: 15),
                label: Text(
                  busy ? 'Сохраняем…' : 'Удалить комментарий',
                  style: const TextStyle(fontSize: 10),
                ),
              ),
              OutlinedButton(
                onPressed: busy ? null : () => _resolve(id, 'dismiss'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 42),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 11,
                  ),
                ),
                child: const Text(
                  'Отклонить жалобу',
                  style: TextStyle(fontSize: 10),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
