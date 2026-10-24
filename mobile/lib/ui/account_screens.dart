import 'package:flutter/material.dart';
import '../domain/controller.dart';
import '../domain/models.dart';
import 'components.dart';
import 'friends_screen.dart';
import 'chat_screens.dart';
import 'moderation_screens.dart';
import 'post_screen.dart';

Future<bool> requireAuth(
  BuildContext context,
  PulseController controller,
) async {
  if (controller.user != null) return true;
  await Navigator.of(context).push<bool>(
    MaterialPageRoute(builder: (_) => AuthScreen(controller: controller)),
  );
  return controller.user != null;
}

void openProfile(BuildContext context, PulseController controller, String id) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ProfileScreen(controller: controller, userId: id),
    ),
  );
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.controller});
  final PulseController controller;
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  bool _register = false, _busy = false, _obscure = true;
  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit({String? demo}) async {
    if (demo == null && !_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final ok = await perform(
      context,
      () => demo != null
          ? widget.controller.login(
              '$demo@pulse.local',
              demo == 'student' ? 'Student123!' : 'Moderator123!',
            )
          : _register
          ? widget.controller.register({
              'name': _name.text.trim(),
              'email': _email.text.trim(),
              'password': _password.text,
            })
          : widget.controller.login(_email.text.trim(), _password.text),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(),
      body: ContentWidth(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(25, 5, 25, 30),
          child: Form(
            key: _form,
            child: AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(21),
                    ),
                    child: const Icon(
                      Icons.graphic_eq_rounded,
                      size: 40,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 27),
                  Text(
                    _register ? 'Ваш профиль\nв университете' : 'Вход в Пульс',
                    style: theme.textTheme.displaySmall,
                  ),
                  const SizedBox(height: 13),
                  Text(
                    _register
                        ? 'Обсуждайте события, подписывайтесь на авторов и делитесь новостями УУНИТ.'
                        : 'Войдите, чтобы сохранять новости, участвовать в обсуждениях и публиковать своё.',
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.6,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 32),
                  if (_register) ...[
                    TextFormField(
                      controller: _name,
                      maxLength: 80,
                      textCapitalization: TextCapitalization.words,
                      autofillHints: const [AutofillHints.name],
                      decoration: const InputDecoration(
                        labelText: 'Имя и фамилия',
                        prefixIcon: Icon(Icons.person_outline_rounded),
                      ),
                      validator: (value) => (value ?? '').trim().length < 2
                          ? 'Укажите ваше имя'
                          : null,
                    ),
                    const SizedBox(height: 15),
                  ],
                  TextFormField(
                    controller: _email,
                    maxLength: 254,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Электронная почта',
                      prefixIcon: Icon(Icons.alternate_email_rounded),
                    ),
                    validator: (value) =>
                        !RegExp(
                          r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                        ).hasMatch(value?.trim() ?? '')
                        ? 'Проверьте адрес почты'
                        : null,
                  ),
                  const SizedBox(height: 15),
                  TextFormField(
                    controller: _password,
                    maxLength: 128,
                    obscureText: _obscure,
                    autofillHints: [
                      _register
                          ? AutofillHints.newPassword
                          : AutofillHints.password,
                    ],
                    decoration: InputDecoration(
                      labelText: 'Пароль',
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                        tooltip: _obscure ? 'Показать пароль' : 'Скрыть пароль',
                        onPressed: () => setState(() => _obscure = !_obscure),
                        icon: Icon(
                          _obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 20,
                        ),
                      ),
                    ),
                    validator: (value) =>
                        (value ?? '').length < 8 ? 'Минимум 8 символов' : null,
                    onFieldSubmitted: (_) => _busy ? null : _submit(),
                  ),
                  const SizedBox(height: 23),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(_register ? 'Создать профиль' : 'Войти'),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Center(
                    child: TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() => _register = !_register),
                      child: Text(
                        _register
                            ? 'Уже есть профиль? Войти'
                            : 'Создать профиль',
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (widget.controller.baseUrl.startsWith('demo:') ||
                      const bool.fromEnvironment(
                        'ALLOW_DEMO_LOGIN',
                        defaultValue: true,
                      ))
                    DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(color: theme.colorScheme.outline),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Theme(
                        data: theme.copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          tilePadding: const EdgeInsets.symmetric(
                            horizontal: 17,
                          ),
                          title: const Text(
                            'Демо-доступ',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          leading: Icon(
                            Icons.play_circle_outline_rounded,
                            size: 19,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(15, 0, 15, 14),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: _busy
                                          ? null
                                          : () => _submit(demo: 'student'),
                                      child: const Text(
                                        'Студент',
                                        style: TextStyle(fontSize: 11),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 9),
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: _busy
                                          ? null
                                          : () => _submit(demo: 'moderator'),
                                      child: const Text(
                                        'Модератор',
                                        style: TextStyle(fontSize: 11),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
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

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.controller,
    this.userId,
    this.embedded = false,
  });
  final PulseController controller;
  final String? userId;
  final bool embedded;
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  UserProfile? _profile;
  List<CampusPost> _posts = [];
  bool _loading = false;
  String? _error;
  String? _loadedId;
  PulseController get c => widget.controller;
  bool get _own => widget.userId == null || widget.userId == c.user?.id;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId ||
        (_own && _loadedId != c.user?.id && !_loading)) {
      _load();
    }
  }

  Future<void> _load() async {
    final id = widget.userId ?? c.user?.id;
    if (id == null) {
      setState(() {
        _profile = null;
        _posts = [];
        _loadedId = null;
      });
      return;
    }
    setState(() {
      _loadedId = id;
      _loading = true;
      _error = null;
    });
    try {
      final profile = await c.getProfile(id);
      final posts = await c.getUserPosts(id);
      if (mounted) {
        setState(() {
          _profile = profile;
          _posts = posts;
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profile = _own && _profile?.id != c.user?.id
        ? c.user
        : _profile ?? (_own ? c.user : null);
    final body = AnimatedBuilder(
      animation: c,
      builder: (_, _) {
        if (c.user == null && _own) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 15, 20, 90),
            children: [
              Text('Профиль', style: theme.textTheme.headlineMedium),
              EmptyState(
                icon: Icons.person_outline_rounded,
                title: 'Ваш профиль',
                description:
                    'Войдите, чтобы публиковать новости, комментировать и добавлять друзей.',
                action: () async {
                  if (await requireAuth(context, c)) await _load();
                },
                label: 'Войти или зарегистрироваться',
              ),
            ],
          );
        }
        if (profile == null) {
          return _loading
              ? const Center(child: CircularProgressIndicator())
              : EmptyState(
                  icon: Icons.person_off_outlined,
                  title: 'Не удалось открыть профиль',
                  description: _error,
                  label: 'Повторить',
                  action: _load,
                );
        }
        return RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(21, 23, 21, 23),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        PulseAvatar(controller: c, user: profile, radius: 39),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Align(
                            alignment: Alignment.topRight,
                            child: _own
                                ? OutlinedButton(
                                    onPressed: () async {
                                      await Navigator.of(context).push(
                                        MaterialPageRoute<void>(
                                          builder: (_) => EditProfileScreen(
                                            controller: c,
                                            profile: profile,
                                          ),
                                        ),
                                      );
                                      await _load();
                                    },
                                    style: OutlinedButton.styleFrom(
                                      minimumSize: const Size(0, 37),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 13,
                                        vertical: 9,
                                      ),
                                    ),
                                    child: const Text(
                                      'Редактировать',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(fontSize: 11),
                                    ),
                                  )
                                : FilledButton(
                                    onPressed: () async {
                                      if (await requireAuth(context, c) &&
                                          context.mounted &&
                                          await perform(
                                            context,
                                            () => c.follow(profile.id),
                                          )) {
                                        await _load();
                                      }
                                    },
                                    style: FilledButton.styleFrom(
                                      minimumSize: const Size(0, 38),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 13,
                                        vertical: 10,
                                      ),
                                    ),
                                    child: Text(
                                      profile.isFollowing
                                          ? 'Вы подписаны'
                                          : 'Подписаться',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 19),
                    Text(
                      profile.name,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontSize: 26,
                      ),
                    ),
                    if (profile.handle.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        '@${profile.handle.replaceFirst('@', '')}',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    if (profile.faculty.isNotEmpty ||
                        profile.course.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Icon(
                            Icons.school_outlined,
                            size: 15,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              [
                                profile.faculty,
                                if (profile.course.isNotEmpty)
                                  '${profile.course} курс',
                              ].where((e) => e.isNotEmpty).join(' · '),
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (profile.bio.isNotEmpty) ...[
                      const SizedBox(height: 13),
                      Text(
                        profile.bio,
                        style: const TextStyle(fontSize: 13, height: 1.6),
                      ),
                    ],
                    if (!_own) ...[
                      const SizedBox(height: 18),
                      _FriendControls(
                        controller: c,
                        profile: profile,
                        onChanged: _load,
                      ),
                    ],
                    const SizedBox(height: 23),
                    Row(
                      children: [
                        _ProfileStat(
                          number: profile.publicationsCount,
                          label: 'Публикации',
                        ),
                        _ProfileStat(
                          number: profile.followersCount,
                          label: 'Подписчики',
                        ),
                        _ProfileStat(
                          number: profile.followingCount,
                          label: 'Подписки',
                        ),
                      ],
                    ),
                    if (profile.interests.isNotEmpty) ...[
                      const SizedBox(height: 21),
                      Wrap(
                        spacing: 7,
                        runSpacing: 7,
                        children: profile.interests.map((id) {
                          final matches = c.categories.where(
                            (category) => category.id == id,
                          );
                          return CategoryPill(
                            label: matches.isEmpty ? id : matches.first.name,
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              ),
              if (_own) ...[
                const SizedBox(height: 20),
                Material(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(19),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      _ProfileMenu(
                        icon: Icons.people_outline_rounded,
                        title: 'Друзья',
                        subtitle: countLabel(
                          profile.friendsCount,
                          'друг',
                          'друга',
                          'друзей',
                        ),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => FriendsScreen(controller: c),
                          ),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 18),
                        child: Divider(),
                      ),
                      _ProfileMenu(
                        icon: Icons.article_outlined,
                        title: 'Мои публикации',
                        subtitle: 'Черновики и статус проверки',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => MyPostsScreen(controller: c),
                          ),
                        ),
                      ),
                      if (profile.isModerator) ...[
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 18),
                          child: Divider(),
                        ),
                        _ProfileMenu(
                          icon: Icons.fact_check_outlined,
                          title: 'Модерация',
                          subtitle: 'Очередь публикаций и решения',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => ModerationScreen(controller: c),
                            ),
                          ),
                        ),
                      ],
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 18),
                        child: Divider(),
                      ),
                      _ProfileMenu(
                        icon: Icons.palette_outlined,
                        title: 'Оформление',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => SettingsScreen(controller: c),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 28),
              Row(
                children: [
                  Text('Публикации', style: theme.textTheme.titleLarge),
                  const Spacer(),
                  if (_loading)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: theme.colorScheme.error,
                      fontSize: 12,
                    ),
                  ),
                ),
              if (_posts.isEmpty && !_loading)
                EmptyState(
                  icon: Icons.article_outlined,
                  title: _own ? 'Публикаций пока нет' : 'Публикаций пока нет',
                  description: _own
                      ? 'Добавьте новость или событие с помощью кнопки «+».'
                      : null,
                ),
              for (final post in _posts)
                Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: PostCard(
                    controller: c,
                    post: post,
                    onTap: () => openPost(context, c, post),
                    onBookmark: () async {
                      if (await requireAuth(context, c) &&
                          context.mounted &&
                          await perform(context, () => c.bookmark(post.id))) {
                        await _load();
                      }
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
    return widget.embedded
        ? body
        : Scaffold(
            appBar: AppBar(title: const Text('Профиль')),
            body: ContentWidth(child: body),
          );
  }
}

class _FriendControls extends StatefulWidget {
  const _FriendControls({
    required this.controller,
    required this.profile,
    required this.onChanged,
  });
  final PulseController controller;
  final UserProfile profile;
  final Future<void> Function() onChanged;
  @override
  State<_FriendControls> createState() => _FriendControlsState();
}

class _FriendControlsState extends State<_FriendControls> {
  bool _busy = false;
  Future<void> _change() async {
    if (!await requireAuth(context, widget.controller) || !mounted) return;
    setState(() => _busy = true);
    final status = widget.profile.friendshipStatus;
    final ok = await perform(
      context,
      () => ['accepted', 'friends', 'outgoing', 'pending_sent'].contains(status)
          ? widget.controller.removeFriendship(widget.profile.id)
          : ['incoming', 'pending_received'].contains(status)
          ? widget.controller.acceptFriendRequest(widget.profile.id)
          : widget.controller.sendFriendRequest(widget.profile.id),
    );
    if (ok) await widget.onChanged();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.profile.friendshipStatus;
    final accepted = ['accepted', 'friends'].contains(status);
    final incoming = ['incoming', 'pending_received'].contains(status);
    final outgoing = ['outgoing', 'pending_sent'].contains(status);
    return Wrap(
      spacing: 9,
      runSpacing: 9,
      children: [
        OutlinedButton.icon(
          onPressed: _busy ? null : _change,
          icon: Icon(
            accepted
                ? Icons.how_to_reg_outlined
                : outgoing
                ? Icons.schedule_rounded
                : Icons.person_add_alt_1_outlined,
            size: 17,
          ),
          label: Text(
            _busy
                ? 'Сохраняем…'
                : accepted
                ? 'В друзьях'
                : incoming
                ? 'Принять заявку'
                : outgoing
                ? 'Заявка отправлена'
                : 'Добавить в друзья',
            style: const TextStyle(fontSize: 11),
          ),
        ),
        if (accepted)
          FilledButton.icon(
            onPressed: () =>
                openChatWithUser(context, widget.controller, widget.profile),
            icon: const Icon(Icons.chat_bubble_outline_rounded, size: 16),
            label: const Text('Написать', style: TextStyle(fontSize: 11)),
          ),
      ],
    );
  }
}

class _ProfileStat extends StatelessWidget {
  const _ProfileStat({required this.number, required this.label});
  final int number;
  final String label;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$number',
          style: const TextStyle(
            fontSize: 23,
            fontWeight: FontWeight.w800,
            letterSpacing: -.5,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 10),
        ),
      ],
    ),
  );
}

class _ProfileMenu extends StatelessWidget {
  const _ProfileMenu({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 5),
    leading: Container(
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
    ),
    title: Text(
      title,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
    ),
    subtitle: subtitle == null
        ? null
        : Text(subtitle!, style: const TextStyle(fontSize: 10)),
    trailing: Icon(
      Icons.chevron_right_rounded,
      size: 20,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
    onTap: onTap,
  );
}

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({
    super.key,
    required this.controller,
    required this.profile,
  });
  final PulseController controller;
  final UserProfile profile;
  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name, _handle, _faculty, _bio;
  late Set<String> _interests;
  late String _course, _avatarUrl, _avatarColor;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    _name = TextEditingController(text: p.name);
    _handle = TextEditingController(text: p.handle);
    _faculty = TextEditingController(text: p.faculty);
    _bio = TextEditingController(text: p.bio);
    _interests = p.interests.toSet();
    _course = p.course;
    _avatarUrl = p.avatarUrl;
    _avatarColor = p.avatarColor;
  }

  @override
  void dispose() {
    for (final field in [_name, _handle, _faculty, _bio]) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final ok = await perform(
      context,
      () => widget.controller.updateProfile({
        'name': _name.text.trim(),
        'handle': _handle.text.trim().replaceFirst('@', ''),
        'faculty': _faculty.text.trim(),
        'course': _course.isEmpty ? null : int.tryParse(_course),
        'bio': _bio.text.trim(),
        'interests': _interests.toList(),
        'avatar_url': _avatarUrl,
        'avatar_color': _avatarColor,
      }),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Редактировать профиль')),
      body: ContentWidth(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Column(
                    children: [
                      PulseAvatar(
                        controller: widget.controller,
                        user: UserProfile(
                          id: widget.profile.id,
                          name: _name.text,
                          avatarUrl: _avatarUrl,
                          avatarColor: _avatarColor,
                        ),
                        radius: 43,
                      ),
                      TextButton.icon(
                        onPressed: _busy
                            ? null
                            : () async {
                                try {
                                  final url = await widget.controller
                                      .pickAndUploadImage();
                                  if (url != null && mounted) {
                                    setState(() => _avatarUrl = url);
                                  }
                                } catch (error) {
                                  if (context.mounted) {
                                    notifyError(context, error);
                                  }
                                }
                              },
                        icon: const Icon(Icons.add_a_photo_outlined, size: 17),
                        label: const Text(
                          'Изменить фото',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Имя и фамилия'),
                  validator: (value) =>
                      (value ?? '').trim().length < 2 ? 'Укажите имя' : null,
                ),
                const SizedBox(height: 15),
                TextFormField(
                  controller: _handle,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Имя пользователя',
                    prefixText: '@',
                  ),
                  validator: (value) =>
                      value != null &&
                          value.isNotEmpty &&
                          !RegExp(
                            r'^[a-zA-Z0-9_\.]{3,30}$',
                          ).hasMatch(value.replaceFirst('@', ''))
                      ? 'От 3 до 30 латинских букв, цифр, _ или .'
                      : null,
                ),
                const SizedBox(height: 15),
                TextFormField(
                  controller: _faculty,
                  decoration: const InputDecoration(
                    labelText: 'Институт или факультет',
                  ),
                ),
                const SizedBox(height: 15),
                DropdownButtonFormField<String>(
                  initialValue: ['1', '2', '3', '4', '5', '6'].contains(_course)
                      ? _course
                      : '',
                  decoration: const InputDecoration(labelText: 'Курс'),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('Не указан')),
                    for (var i = 1; i <= 6; i++)
                      DropdownMenuItem(value: '$i', child: Text('$i курс')),
                  ],
                  onChanged: (value) => _course = value ?? '',
                ),
                const SizedBox(height: 15),
                TextFormField(
                  controller: _bio,
                  minLines: 3,
                  maxLines: 6,
                  maxLength: 500,
                  decoration: const InputDecoration(
                    labelText: 'О себе',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 19),
                Text('Интересы', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(
                  'Они помогают подобрать публикации для вашей ленты.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 13),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: widget.controller.categories
                      .map(
                        (category) => FilterChip(
                          label: Text(category.name),
                          selected: _interests.contains(category.id),
                          onSelected: (value) => setState(() {
                            if (value) {
                              _interests.add(category.id);
                            } else {
                              _interests.remove(category.id);
                            }
                          }),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 22),
                Text('Цвет профиля', style: theme.textTheme.titleMedium),
                const SizedBox(height: 13),
                Wrap(
                  spacing: 14,
                  runSpacing: 10,
                  children:
                      [
                            '#3459E6',
                            '#278363',
                            '#8155A6',
                            '#C97851',
                            '#466A8B',
                            '#BE5876',
                          ]
                          .map(
                            (color) => InkWell(
                              onTap: () => setState(() => _avatarColor = color),
                              borderRadius: BorderRadius.circular(25),
                              child: Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: parseColor(color),
                                  shape: BoxShape.circle,
                                ),
                                child:
                                    _avatarColor.toUpperCase() ==
                                        color.toUpperCase()
                                    ? const Icon(
                                        Icons.check_rounded,
                                        color: Colors.white,
                                        size: 22,
                                      )
                                    : null,
                              ),
                            ),
                          )
                          .toList(),
                ),
                const SizedBox(height: 30),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _busy ? null : _save,
                    child: Text(_busy ? 'Сохраняем…' : 'Сохранить изменения'),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.controller});
  final PulseController controller;
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _connection;
  bool _connecting = false;
  @override
  void initState() {
    super.initState();
    _connection = TextEditingController(text: widget.controller.baseUrl);
  }

  @override
  void dispose() {
    _connection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      final theme = Theme.of(context);
      return Scaffold(
        appBar: AppBar(title: const Text('Настройки')),
        body: ContentWidth(
          child: ListView(
            padding: const EdgeInsets.all(22),
            children: [
              if (c.baseUrl.startsWith('demo:'))
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.offline_bolt_outlined),
                  title: Text('Демо без сервера'),
                  subtitle: Text(
                    'Примеры и ваши изменения хранятся только на этом телефоне. Между устройствами данные не передаются.',
                  ),
                )
              else
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text(
                    'Подключение к серверу',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  leading: const Icon(Icons.dns_outlined, size: 21),
                  children: [
                    const SizedBox(height: 10),
                    TextField(
                      controller: _connection,
                      readOnly: c.automaticConnection,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Адрес сервера',
                        hintText: bool.fromEnvironment('PUBLIC_BUILD')
                            ? 'https://server.example'
                            : 'http://192.168.1.10:8000',
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: _connecting
                            ? null
                            : () async {
                                setState(() => _connecting = true);
                                await perform(
                                  context,
                                  () =>
                                      c.setConnection(_connection.text.trim()),
                                  success: 'Подключение обновлено',
                                );
                                if (mounted) {
                                  setState(() {
                                    _connecting = false;
                                    _connection.text = c.baseUrl;
                                  });
                                }
                              },
                        child: Text(
                          _connecting
                              ? 'Подключаемся…'
                              : c.automaticConnection
                              ? 'Проверить соединение'
                              : 'Подключиться',
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                ),
              const SizedBox(height: 24),
              Text('Оформление', style: theme.textTheme.headlineMedium),
              const SizedBox(height: 9),
              Text(
                'Выберите удобную тему и цвет приложения.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 26),
              Text('Тема', style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final mode in ThemeMode.values)
                    ChoiceChip(
                      selected: c.themeMode == mode,
                      label: Text(switch (mode) {
                        ThemeMode.system => 'Как на устройстве',
                        ThemeMode.light => 'Светлая',
                        ThemeMode.dark => 'Тёмная',
                      }),
                      avatar: Icon(switch (mode) {
                        ThemeMode.system => Icons.brightness_auto_outlined,
                        ThemeMode.light => Icons.light_mode_outlined,
                        ThemeMode.dark => Icons.dark_mode_outlined,
                      }, size: 16),
                      onSelected: (_) => c.setAppearance(mode: mode),
                    ),
                ],
              ),
              const SizedBox(height: 27),
              Text('Палитра', style: theme.textTheme.titleMedium),
              const SizedBox(height: 15),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final pair in <(String, Color)>[
                    ('УУНИТ', uunitViolet),
                    ('Синий', cobalt),
                    ('Хвойный', const Color(0xFF278363)),
                    ('Сливовый', const Color(0xFF8155A6)),
                    ('Терракота', const Color(0xFFA84F2D)),
                  ])
                    InkWell(
                      onTap: () => c.setAppearance(accent: pair.$2),
                      borderRadius: BorderRadius.circular(15),
                      child: Container(
                        width: 140,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          border: Border.all(
                            color: c.accent == pair.$2
                                ? pair.$2
                                : theme.colorScheme.outline,
                            width: c.accent == pair.$2 ? 1.5 : 1,
                          ),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 25,
                              height: 25,
                              decoration: BoxDecoration(
                                color: pair.$2,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: c.accent == pair.$2
                                  ? const Icon(
                                      Icons.check_rounded,
                                      size: 17,
                                      color: Colors.white,
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 10),
                            Flexible(
                              child: Text(
                                pair.$1,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 30),
              Container(
                padding: const EdgeInsets.all(19),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                            color: c.accent,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text('Предпросмотр', style: theme.textTheme.bodySmall),
                      ],
                    ),
                    const SizedBox(height: 15),
                    Text(
                      'Пример публикации',
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Новости и события в вашем оформлении.',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () =>
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Оформление уже сохранено'),
                            ),
                          ),
                      child: const Text('Выбрано'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              const Divider(),
              const SizedBox(height: 15),
              if (c.user != null) ...[
                const SizedBox(height: 22),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                  ),
                  onPressed: () async {
                    if (await perform(context, c.logout) && context.mounted) {
                      Navigator.of(context).pop();
                    }
                  },
                  icon: const Icon(Icons.logout_rounded, size: 19),
                  label: const Text('Выйти из профиля'),
                ),
              ],
              const SizedBox(height: 30),
              Center(
                child: Text(
                  'Пульс · УУНИТ',
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant,
                    letterSpacing: .3,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
