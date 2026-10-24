import 'dart:async';
import 'package:flutter/material.dart';
import '../domain/controller.dart';
import '../domain/models.dart';
import 'account_screens.dart';
import 'chat_screens.dart';
import 'components.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key, required this.controller});
  final PulseController controller;
  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final _search = TextEditingController();
  final _busy = <String>{};
  Timer? _debounce;
  int _tab = 0, _searchGeneration = 0;
  bool _loading = true;
  String? _error;
  List<UserProfile> _friends = [], _incoming = [], _outgoing = [], _people = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final result = await Future.wait([
        widget.controller.loadFriends(),
        widget.controller.loadFriendRequests(),
        widget.controller.lookupUsers(_search.text.trim()),
      ]);
      if (!mounted) return;
      final requests = result[1] as Map<String, List<UserProfile>>;
      setState(() {
        _friends = result[0] as List<UserProfile>;
        _incoming = requests['incoming'] ?? [];
        _outgoing = requests['outgoing'] ?? [];
        _people = result[2] as List<UserProfile>;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  void _searchPeople(String value) {
    _debounce?.cancel();
    final generation = ++_searchGeneration;
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final people = await widget.controller.lookupUsers(value.trim());
        if (mounted && generation == _searchGeneration) {
          setState(() => _people = people);
        }
      } catch (e) {
        if (mounted) notifyError(context, e);
      }
    });
  }

  Future<void> _act(UserProfile person, Future<void> Function() action) async {
    setState(() => _busy.add(person.id));
    final ok = await perform(context, action);
    if (ok) await _load(silent: true);
    if (mounted) setState(() => _busy.remove(person.id));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final list = _tab == 0
        ? _friends
        : _tab == 1
        ? _incoming
        : _people;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Друзья'),
        actions: [
          IconButton(
            tooltip: 'Найти человека',
            onPressed: () => setState(() => _tab = 2),
            icon: const Icon(Icons.person_add_alt_1_rounded),
          ),
        ],
      ),
      body: ContentWidth(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              Text(
                'Ваш круг',
                style: theme.textTheme.headlineLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                'Общайтесь и находите события, на которые идут друзья.',
                style: theme.textTheme.bodyMedium?.copyWith(color: muted),
              ),
              const SizedBox(height: 22),
              SegmentedButton<int>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: 0,
                    label: Text('Друзья ${_friends.length}'),
                  ),
                  ButtonSegment(
                    value: 1,
                    label: Text(
                      _incoming.isEmpty
                          ? 'Заявки'
                          : 'Заявки ${_incoming.length}',
                    ),
                  ),
                  const ButtonSegment(value: 2, label: Text('Поиск')),
                ],
                selected: {_tab},
                onSelectionChanged: (value) =>
                    setState(() => _tab = value.first),
              ),
              const SizedBox(height: 20),
              if (_tab == 2) ...[
                TextField(
                  controller: _search,
                  onChanged: _searchPeople,
                  decoration: const InputDecoration(
                    hintText: 'Имя или институт',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                ),
                const SizedBox(height: 18),
              ],
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(48),
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (_error != null) ...[
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                TextButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Повторить'),
                ),
              ],
              if (!_loading && _error == null && list.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 42,
                    horizontal: 12,
                  ),
                  child: Column(
                    children: [
                      Icon(
                        _tab == 1
                            ? Icons.mark_email_read_outlined
                            : Icons.people_outline_rounded,
                        size: 42,
                        color: muted,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _tab == 0
                            ? 'Добавьте знакомых'
                            : _tab == 1
                            ? 'Новых заявок нет'
                            : 'Никого не нашли',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _tab == 0
                            ? 'Найдите друзей по имени во вкладке «Поиск».'
                            : _tab == 1
                            ? 'Входящие заявки появятся здесь.'
                            : 'Попробуйте другое имя или название института.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: muted),
                      ),
                      if (_tab == 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: FilledButton(
                            onPressed: () => setState(() => _tab = 2),
                            child: const Text('Найти друзей'),
                          ),
                        ),
                    ],
                  ),
                ),
              for (final person in list) _personTile(person),
              if (_tab == 1 && _outgoing.isNotEmpty) ...[
                const SizedBox(height: 26),
                Text(
                  'Отправленные',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                for (final person in _outgoing) _personTile(person),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _personTile(UserProfile person) {
    final theme = Theme.of(context);
    final busy = _busy.contains(person.id);
    final status = person.friendshipStatus;
    final friends = status == 'friends' || status == 'accepted';
    final incoming = status == 'incoming' || status == 'pending_received';
    final outgoing = status == 'outgoing' || status == 'pending_sent';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () async {
                openProfile(context, widget.controller, person.id);
              },
              borderRadius: BorderRadius.circular(12),
              child: Row(
                children: [
                  PulseAvatar(
                    user: person,
                    controller: widget.controller,
                    radius: 24,
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          person.name,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          person.faculty.isEmpty
                              ? '@${person.handle}'
                              : person.faculty,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: muted),
                ],
              ),
            ),
            const SizedBox(height: 13),
            if (busy)
              const LinearProgressIndicator(minHeight: 2)
            else
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  if (friends) ...[
                    FilledButton.tonalIcon(
                      onPressed: () =>
                          openChatWithUser(context, widget.controller, person),
                      icon: const Icon(
                        Icons.chat_bubble_outline_rounded,
                        size: 18,
                      ),
                      label: const Text('Написать'),
                    ),
                    TextButton(
                      onPressed: () => _act(
                        person,
                        () => widget.controller.removeFriendship(person.id),
                      ),
                      child: const Text('Удалить из друзей'),
                    ),
                  ] else if (incoming) ...[
                    FilledButton(
                      onPressed: () => _act(
                        person,
                        () => widget.controller.acceptFriendRequest(person.id),
                      ),
                      child: const Text('Принять'),
                    ),
                    TextButton(
                      onPressed: () => _act(
                        person,
                        () => widget.controller.removeFriendship(person.id),
                      ),
                      child: const Text('Отклонить'),
                    ),
                  ] else if (outgoing)
                    OutlinedButton(
                      onPressed: () => _act(
                        person,
                        () => widget.controller.removeFriendship(person.id),
                      ),
                      child: const Text('Отменить заявку'),
                    )
                  else
                    FilledButton.tonalIcon(
                      onPressed: () => _act(
                        person,
                        () => widget.controller.sendFriendRequest(person.id),
                      ),
                      icon: const Icon(
                        Icons.person_add_alt_1_rounded,
                        size: 18,
                      ),
                      label: const Text('Добавить'),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
