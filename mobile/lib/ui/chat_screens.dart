import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../domain/controller.dart';
import '../domain/models.dart';
import 'account_screens.dart';
import 'components.dart';
import 'friends_screen.dart';

Map<String, dynamic> _chatMap(dynamic value) =>
    Map<String, dynamic>.from(value as Map);

Future<void> openChatWithUser(
  BuildContext context,
  PulseController controller,
  UserProfile person,
) async {
  if (!await requireAuth(context, controller) || !context.mounted) return;
  try {
    final chat = await controller.openChat(person.id);
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatScreen(controller: controller, chat: chat),
      ),
    );
  } catch (e) {
    if (context.mounted) notifyError(context, e);
  }
}

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key, required this.controller});
  final PulseController controller;
  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen>
    with WidgetsBindingObserver {
  List<Map<String, dynamic>> _chats = [];
  bool _loading = false, _fetching = false;
  String? _error, _identity;
  Timer? _timer;
  bool _active = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _identity = widget.controller.user?.id;
    widget.controller.addListener(_identityChanged);
    _load();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_active && (ModalRoute.of(context)?.isCurrent ?? true)) {
        _load(silent: true);
      }
    });
  }

  void _identityChanged() {
    if (_identity != widget.controller.user?.id) {
      _identity = widget.controller.user?.id;
      _chats = [];
      _error = null;
      _load();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_identityChanged);
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (_fetching || !_active || widget.controller.user == null) return;
    _fetching = true;
    if (!silent && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    final userId = widget.controller.user!.id;
    try {
      final result = await widget.controller.loadChats();
      if (mounted && userId == widget.controller.user?.id) {
        setState(() {
          _chats = result;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && !silent) setState(() => _error = e.toString());
    } finally {
      _fetching = false;
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    if (_active) _load(silent: true);
  }

  Future<void> _newChat() async {
    if (!await requireAuth(context, widget.controller) || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FriendsScreen(controller: widget.controller),
      ),
    );
    await _load(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final signedIn = widget.controller.user != null;
    return ContentWidth(
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(22, 10, 22, 32),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Сообщения',
                    style: theme.textTheme.headlineMedium,
                  ),
                ),
                IconButton.filledTonal(
                  tooltip: 'Написать другу',
                  onPressed: _newChat,
                  icon: const Icon(Icons.edit_square),
                ),
              ],
            ),
            const SizedBox(height: 7),
            Text(
              'Личные переписки с друзьями',
              style: theme.textTheme.bodyMedium?.copyWith(color: muted),
            ),
            const SizedBox(height: 23),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(40),
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
            if (!_loading && _error == null && _chats.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 64,
                  horizontal: 12,
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.forum_outlined,
                      size: 48,
                      color: theme.colorScheme.primary.withValues(alpha: .65),
                    ),
                    const SizedBox(height: 21),
                    Text(
                      signedIn
                          ? 'Пока нет переписок'
                          : 'Войдите, чтобы общаться',
                      style: theme.textTheme.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 9),
                    Text(
                      signedIn
                          ? 'Начните разговор из профиля друга.\nМожно отправлять текст и фотографии.'
                          : 'Добавляйте знакомых и обсуждайте планы в личных сообщениях.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: muted, height: 1.6),
                    ),
                    const SizedBox(height: 23),
                    FilledButton.icon(
                      onPressed: _newChat,
                      icon: Icon(
                        signedIn
                            ? Icons.people_outline_rounded
                            : Icons.login_rounded,
                      ),
                      label: Text(signedIn ? 'Открыть друзей' : 'Войти'),
                    ),
                  ],
                ),
              ),
            for (final chat in _chats) _chatTile(chat),
          ],
        ),
      ),
    );
  }

  Widget _chatTile(Map<String, dynamic> chat) {
    final peer = UserProfile.fromJson(_chatMap(chat['peer']));
    final last = chat['last_message'] is Map
        ? _chatMap(chat['last_message'])
        : null;
    final unread = (chat['unread_count'] as num?)?.toInt() ?? 0;
    final mine = last?['sender_id'].toString() == widget.controller.user?.id;
    final preview = last == null
        ? 'Начните разговор'
        : (last['body']?.toString().isNotEmpty ?? false)
        ? last['body'].toString()
        : 'Фотография';
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    ChatScreen(controller: widget.controller, chat: chat),
              ),
            );
            await _load(silent: true);
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                PulseAvatar(
                  user: peer,
                  controller: widget.controller,
                  radius: 25,
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        peer.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '${mine ? 'Вы: ' : ''}$preview',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: unread > 0
                              ? theme.colorScheme.onSurface
                              : muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (last != null)
                      Text(
                        _messageTime(last['created_at']),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: muted,
                        ),
                      ),
                    const SizedBox(height: 9),
                    if (unread > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          unread > 99 ? '99+' : '$unread',
                          style: TextStyle(
                            color: theme.colorScheme.onPrimary,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
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

String _messageTime(dynamic value) {
  final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
  if (date == null) return '';
  final now = DateTime.now();
  if (date.year != now.year || date.month != now.month || date.day != now.day) {
    return '${date.day} ${shortMonthNames[date.month - 1]}';
  }
  return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.controller, required this.chat});
  final PulseController controller;
  final Map<String, dynamic> chat;
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  final Map<int, Map<String, dynamic>> _messages = {};
  Timer? _timer;
  bool _loading = true,
      _fetching = false,
      _sending = false,
      _uploading = false,
      _earlier = false,
      _more = false,
      _active = true;
  String? _error, _imageUrl;
  String get _id => widget.chat['id'].toString();
  UserProfile get _peer => UserProfile.fromJson(_chatMap(widget.chat['peer']));
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _text.addListener(_textChanged);
    _refresh(initial: true);
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (_active) _refresh();
    });
  }

  void _textChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    if (_active) _refresh();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _merge(List<Map<String, dynamic>> items) {
    for (final item in items) {
      _messages[(item['id'] as num).toInt()] = item;
    }
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _refresh({bool initial = false}) async {
    if (_fetching) return;
    _fetching = true;
    final atBottom = !_scroll.hasClients || _scroll.position.extentAfter < 130;
    try {
      final items = await widget.controller.loadMessages(_id);
      if (!mounted) return;
      final oldLength = _messages.length;
      setState(() {
        _merge(items);
        if (initial) _more = items.length == 100;
        _loading = false;
        _error = null;
      });
      if (initial || (atBottom && _messages.length != oldLength)) _toBottom();
      await widget.controller.markChatRead(_id);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    } finally {
      _fetching = false;
    }
  }

  Future<void> _loadEarlier() async {
    if (_earlier || _messages.isEmpty) return;
    setState(() => _earlier = true);
    try {
      final first = _messages.keys.reduce((a, b) => a < b ? a : b);
      final items = await widget.controller.loadMessages(_id, beforeId: first);
      if (mounted) {
        setState(() {
          _merge(items);
          _more = items.length == 100;
        });
      }
    } catch (e) {
      if (mounted) notifyError(context, e);
    } finally {
      if (mounted) setState(() => _earlier = false);
    }
  }

  Future<void> _pickPhoto() async {
    setState(() => _uploading = true);
    try {
      final url = await widget.controller.pickAndUploadChatImage(_id);
      if (mounted && url != null) setState(() => _imageUrl = url);
    } catch (e) {
      if (mounted) notifyError(context, e);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _send() async {
    if (_sending || (_text.text.trim().isEmpty && _imageUrl == null)) return;
    setState(() => _sending = true);
    try {
      final message = await widget.controller.sendMessage(
        _id,
        _text.text.trim(),
        imageUrl: _imageUrl,
      );
      if (!mounted) return;
      setState(() {
        _merge([message]);
        _imageUrl = null;
      });
      _text.clear();
      _toBottom();
    } catch (e) {
      if (mounted) notifyError(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final peer = _peer;
    final messages = _messages.values.toList()
      ..sort((a, b) => (a['id'] as num).compareTo(b['id'] as num));
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: InkWell(
          onTap: () => openProfile(context, widget.controller, peer.id),
          child: Row(
            children: [
              PulseAvatar(
                user: peer,
                controller: widget.controller,
                radius: 19,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      peer.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text('Личная переписка', style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              const SizedBox(width: 18),
            ],
          ),
        ),
      ),
      body: ContentWidth(
        child: Column(
          children: [
            if (_error != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                color: theme.colorScheme.errorContainer,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _error!,
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Повторить',
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : messages.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            PulseAvatar(
                              user: peer,
                              controller: widget.controller,
                              radius: 35,
                            ),
                            const SizedBox(height: 18),
                            Text(
                              peer.name,
                              style: theme.textTheme.titleLarge,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Отправьте сообщение или фотографию',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: muted),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(15, 15, 15, 18),
                      itemCount: messages.length + (_more ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (_more && index == 0) {
                          return Center(
                            child: TextButton(
                              onPressed: _earlier ? null : _loadEarlier,
                              child: Text(
                                _earlier ? 'Загрузка…' : 'Ранние сообщения',
                              ),
                            ),
                          );
                        }
                        return _bubble(messages[index - (_more ? 1 : 0)]);
                      },
                    ),
            ),
            if (widget.chat['can_send'] == false)
              const Padding(
                padding: EdgeInsets.all(18),
                child: Text(
                  'Чтобы продолжить переписку, добавьте собеседника в друзья.',
                  textAlign: TextAlign.center,
                ),
              )
            else
              Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  border: Border(
                    top: BorderSide(color: theme.colorScheme.outline),
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_imageUrl != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 72,
                                  height: 72,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: PrivateChatImage(
                                      controller: widget.controller,
                                      url: _imageUrl!,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Expanded(
                                  child: Text(
                                    'Фотография готова к отправке',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Убрать фотографию',
                                  onPressed: _sending
                                      ? null
                                      : () => setState(() => _imageUrl = null),
                                  icon: const Icon(Icons.close_rounded),
                                ),
                              ],
                            ),
                          ),
                        if (_uploading)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 8),
                            child: LinearProgressIndicator(minHeight: 2),
                          ),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            IconButton(
                              tooltip: 'Прикрепить фотографию',
                              onPressed: _uploading || _sending
                                  ? null
                                  : _pickPhoto,
                              icon: const Icon(
                                Icons.add_photo_alternate_outlined,
                              ),
                            ),
                            Expanded(
                              child: TextField(
                                controller: _text,
                                minLines: 1,
                                maxLines: 5,
                                maxLength: 4000,
                                textCapitalization:
                                    TextCapitalization.sentences,
                                decoration: const InputDecoration(
                                  hintText: 'Сообщение',
                                  counterText: '',
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 13,
                                    vertical: 12,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 7),
                            IconButton.filled(
                              tooltip: 'Отправить',
                              onPressed:
                                  _sending ||
                                      _uploading ||
                                      (_text.text.trim().isEmpty &&
                                          _imageUrl == null)
                                  ? null
                                  : _send,
                              icon: _sending
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.arrow_upward_rounded),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _bubble(Map<String, dynamic> message) {
    final mine = message['sender_id'].toString() == widget.controller.user?.id;
    final theme = Theme.of(context);
    final image = message['image_url']?.toString();
    final body = message['body']?.toString() ?? '';
    final foreground = mine
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSurface;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width.clamp(0, 760) * .79,
        ),
        child: Container(
          margin: const EdgeInsets.only(bottom: 9),
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: mine ? theme.colorScheme.primary : theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(18).copyWith(
              bottomRight: mine ? const Radius.circular(5) : null,
              bottomLeft: !mine ? const Radius.circular(5) : null,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (image != null && image.isNotEmpty)
                Padding(
                  padding: EdgeInsets.only(bottom: body.isEmpty ? 0 : 9),
                  child: SizedBox(
                    width: 260,
                    height: 240,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: PrivateChatImage(
                        controller: widget.controller,
                        url: image,
                        fit: BoxFit.cover,
                        openable: true,
                      ),
                    ),
                  ),
                ),
              if (body.isNotEmpty)
                SelectableText(
                  body,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: foreground,
                  ),
                ),
              const SizedBox(height: 5),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _messageTime(message['created_at']),
                    style: TextStyle(
                      fontSize: 10,
                      color: foreground.withValues(alpha: .65),
                    ),
                  ),
                  if (mine) ...[
                    const SizedBox(width: 5),
                    Icon(
                      message['read_at'] != null
                          ? Icons.done_all_rounded
                          : Icons.done_rounded,
                      size: 14,
                      color: foreground.withValues(alpha: .8),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PrivateChatImage extends StatefulWidget {
  const PrivateChatImage({
    super.key,
    required this.controller,
    required this.url,
    this.fit = BoxFit.contain,
    this.openable = false,
  });
  final PulseController controller;
  final String url;
  final BoxFit fit;
  final bool openable;
  @override
  State<PrivateChatImage> createState() => _PrivateChatImageState();
}

class _PrivateChatImageState extends State<PrivateChatImage> {
  late Future<Uint8List> _image;
  @override
  void initState() {
    super.initState();
    _image = widget.controller.loadChatImage(widget.url);
  }

  @override
  void didUpdateWidget(covariant PrivateChatImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _image = widget.controller.loadChatImage(widget.url);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
    future: _image,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return InkWell(
          onTap: () => setState(
            () => _image = widget.controller.loadChatImage(widget.url),
          ),
          child: const Center(child: Icon(Icons.refresh_rounded)),
        );
      }
      if (!snapshot.hasData) {
        return const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      }
      final photo = Image.memory(
        snapshot.data!,
        fit: widget.fit,
        width: double.infinity,
        height: double.infinity,
        gaplessPlayback: true,
      );
      if (!widget.openable) return photo;
      return GestureDetector(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => Scaffold(
              backgroundColor: Colors.black,
              appBar: AppBar(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                title: const Text('Фотография'),
              ),
              body: Center(
                child: InteractiveViewer(
                  minScale: .8,
                  maxScale: 5,
                  child: Image.memory(snapshot.data!),
                ),
              ),
            ),
          ),
        ),
        child: photo,
      );
    },
  );
}
