import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import '../domain/controller.dart';
import 'account_screens.dart';
import 'chat_screens.dart';
import 'components.dart';
import 'publication_extras.dart';
import 'compose_screen.dart';
import 'post_screen.dart';

class PulseApp extends StatefulWidget {
  const PulseApp({super.key, required this.controller});
  final PulseController controller;
  @override
  State<PulseApp> createState() => _PulseAppState();
}

class _PulseAppState extends State<PulseApp> {
  @override
  void initState() {
    super.initState();
    widget.controller.initialize();
  }

  ThemeData _theme(Brightness brightness, Color accent) {
    final dark = brightness == Brightness.dark;
    final university = accent == uunitViolet;
    final font = university ? 'Golos' : 'Manrope';
    final background = university
        ? (dark ? const Color(0xFF140F23) : const Color(0xFFF7F5FC))
        : (dark ? const Color(0xFF101725) : warmPaper);
    final scheme =
        ColorScheme.fromSeed(
          seedColor: accent,
          brightness: brightness,
        ).copyWith(
          primary: dark
              ? (university
                    ? uunitLilac
                    : Color.lerp(accent, Colors.white, .38)!)
              : accent,
          onPrimary: dark ? ink : Colors.white,
          surface: dark
              ? (university ? const Color(0xFF211831) : const Color(0xFF192235))
              : Colors.white,
          onSurface: dark
              ? const Color(0xFFF1F3F8)
              : (university ? uunitDeep : ink),
          onSurfaceVariant: dark
              ? const Color(0xFF9FA9BC)
              : (university
                    ? const Color(0xFF736583)
                    : const Color(0xFF788194)),
          outline: dark
              ? (university ? const Color(0xFF443458) : const Color(0xFF344056))
              : (university
                    ? const Color(0xFFE7DFF4)
                    : const Color(0xFFE5E8EE)),
          surfaceContainerHighest: dark
              ? (university ? const Color(0xFF302242) : const Color(0xFF232F45))
              : (university
                    ? const Color(0xFFF0EAFB)
                    : const Color(0xFFF0F2F6)),
        );
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      fontFamily: font,
    );
    return base.copyWith(
      textTheme: base.textTheme
          .copyWith(
            displaySmall: TextStyle(
              fontSize: 34,
              height: 1.12,
              fontWeight: FontWeight.w800,
              letterSpacing: -1.2,
              color: scheme.onSurface,
            ),
            headlineMedium: TextStyle(
              fontSize: 29,
              height: 1.15,
              fontWeight: FontWeight.w800,
              letterSpacing: -.9,
              color: scheme.onSurface,
            ),
            titleLarge: TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w700,
              letterSpacing: -.45,
              color: scheme.onSurface,
            ),
            titleMedium: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              letterSpacing: -.2,
              color: scheme.onSurface,
            ),
            bodyMedium: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: scheme.onSurface,
            ),
            bodySmall: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: scheme.onSurfaceVariant,
            ),
          )
          .apply(fontFamily: font),
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: font,
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
        systemOverlayStyle: dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        color: scheme.surface,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
          minimumSize: const Size(0, 50),
          textStyle: TextStyle(
            fontFamily: font,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          minimumSize: const Size(0, 48),
          foregroundColor: scheme.onSurface,
          side: BorderSide(color: scheme.outline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 17,
        ),
        hintStyle: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14),
        labelStyle: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: accent, width: 1.5),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outline,
        thickness: 1,
        space: 1,
      ),
      chipTheme: base.chipTheme.copyWith(
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
        labelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
        showCheckmark: false,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: dark ? const Color(0xFF344056) : ink,
        contentTextStyle: TextStyle(color: Colors.white, fontFamily: font),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) => MaterialApp(
      title: 'Пульс · УУНИТ',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ru'),
      supportedLocales: const [Locale('ru'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: _theme(Brightness.light, widget.controller.accent),
      darkTheme: _theme(Brightness.dark, widget.controller.accent),
      themeMode: widget.controller.themeMode,
      home: PulseShell(controller: widget.controller),
    ),
  );
}

class PulseShell extends StatefulWidget {
  const PulseShell({super.key, required this.controller});
  final PulseController controller;
  @override
  State<PulseShell> createState() => _PulseShellState();
}

class _PulseShellState extends State<PulseShell> {
  int _tab = 0;
  bool _searching = false;
  final _search = TextEditingController();
  PulseController get c => widget.controller;
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _select(int tab) async {
    setState(() {
      _tab = tab;
      _searching = false;
      _search.clear();
    });
    if (tab == 0 || tab == 1) {
      await perform(
        context,
        () => c.loadFeed(eventsOnly: tab == 1, mode: 'all', query: ''),
      );
    }
    if (tab == 3 && c.user != null && mounted) {
      await perform(context, c.loadSavedPosts);
    }
  }

  Future<void> _compose() async {
    if (!await requireAuth(context, c)) return;
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ComposeScreen(controller: c)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 76,
        titleSpacing: 22,
        title: ContentWidth(
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.graphic_eq_rounded,
                  color: theme.colorScheme.onPrimary,
                  size: 25,
                ),
              ),
              const SizedBox(width: 11),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'пульс',
                    style: TextStyle(
                      color: theme.colorScheme.onSurface,
                      fontSize: 23,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.9,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    c.baseUrl.startsWith('demo:') ? 'УУНИТ · ДЕМО' : 'УУНИТ',
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              if (_tab < 2)
                IconButton(
                  tooltip: 'Поиск',
                  onPressed: () => setState(() => _searching = !_searching),
                  icon: Icon(
                    _searching ? Icons.close_rounded : Icons.search_rounded,
                    size: 24,
                  ),
                ),
              if (c.user != null && _tab != 4) ...[
                const SizedBox(width: 4),
                PulseAvatar(
                  controller: c,
                  user: c.user!,
                  radius: 18,
                  onTap: () => _select(4),
                ),
              ] else if (_tab == 4)
                IconButton(
                  tooltip: 'Настройки',
                  icon: const Icon(Icons.tune_rounded, size: 23),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => SettingsScreen(controller: c),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      body: AnimatedBuilder(
        animation: c,
        builder: (_, _) => ContentWidth(
          child: Column(
            children: [
              if (c.loading)
                LinearProgressIndicator(
                  minHeight: 2,
                  backgroundColor: theme.colorScheme.primary.withValues(
                    alpha: .08,
                  ),
                ),
              if (_searching)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: TextField(
                    controller: _search,
                    autofocus: true,
                    textInputAction: TextInputAction.search,
                    decoration: const InputDecoration(
                      hintText: 'Найти новость или событие',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                    onSubmitted: (query) => perform(
                      context,
                      () => c.loadFeed(
                        query: query,
                        categoryId: c.selectedCategory,
                        eventsOnly: _tab == 1,
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: switch (_tab) {
                  0 => _Feed(controller: c),
                  1 => _Events(controller: c),
                  2 => ChatListScreen(controller: c),
                  3 => _Bookmarks(controller: c),
                  _ => ProfileScreen(controller: c, embedded: true),
                },
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: _tab == 0 || _tab == 4
          ? FloatingActionButton(
              tooltip: 'Создать публикацию',
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: theme.colorScheme.onPrimary,
              elevation: 3,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              onPressed: _compose,
              child: const Icon(Icons.add_rounded, size: 29),
            )
          : null,
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(
            top: BorderSide(
              color: theme.colorScheme.outline.withValues(alpha: .6),
            ),
          ),
        ),
        child: SafeArea(
          top: false,
          child: ContentWidth(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 7),
              child: Row(
                children: List.generate(5, (index) {
                  const labels = [
                    'Лента',
                    'События',
                    'Чаты',
                    'Избранное',
                    'Профиль',
                  ];
                  const icons = [
                    Icons.space_dashboard_outlined,
                    Icons.calendar_month_outlined,
                    Icons.chat_bubble_outline_rounded,
                    Icons.bookmark_border_rounded,
                    Icons.person_outline_rounded,
                  ];
                  const selectedIcons = [
                    Icons.space_dashboard_rounded,
                    Icons.calendar_month_rounded,
                    Icons.chat_bubble_rounded,
                    Icons.bookmark_rounded,
                    Icons.person_rounded,
                  ];
                  final active = _tab == index;
                  return Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(15),
                      onTap: () => _select(index),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 7),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: active
                                    ? theme.colorScheme.primary.withValues(
                                        alpha: .1,
                                      )
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(11),
                              ),
                              child: Icon(
                                active ? selectedIcons[index] : icons[index],
                                color: active
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.onSurfaceVariant,
                                size: 22,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              labels[index],
                              maxLines: 1,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: active
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: active
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Feed extends StatelessWidget {
  const _Feed({required this.controller});
  final PulseController controller;
  @override
  Widget build(BuildContext context) {
    final c = controller;
    final theme = Theme.of(context);
    return RefreshIndicator(
      onRefresh: () => c.loadFeed(
        categoryId: c.selectedCategory,
        query: c.searchQuery,
        mode: c.feedMode,
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 15, 20, 100),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  'В университете',
                  style: theme.textTheme.headlineMedium,
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  dateLabel(DateTime.now()),
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Новости, события и люди УУНИТ',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 9,
            runSpacing: 6,
            children: [
              for (final mode in ['all', 'following'])
                Padding(
                  padding: const EdgeInsets.only(right: 22),
                  child: InkWell(
                    onTap: () async {
                      if (mode == 'following' &&
                          !await requireAuth(context, c)) {
                        return;
                      }
                      if (context.mounted) {
                        await perform(
                          context,
                          () => c.loadFeed(
                            mode:
                                mode == 'all' &&
                                    c.user?.interests.isNotEmpty == true
                                ? 'interests'
                                : mode,
                            categoryId: c.selectedCategory,
                          ),
                        );
                      }
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          mode == 'all' ? 'Для вас' : 'Подписки',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color:
                                c.feedMode == mode ||
                                    mode == 'all' && c.feedMode == 'interests'
                                ? theme.colorScheme.onSurface
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          height: 3,
                          width: mode == 'all' ? 58 : 78,
                          decoration: BoxDecoration(
                            color:
                                c.feedMode == mode ||
                                    mode == 'all' && c.feedMode == 'interests'
                                ? theme.colorScheme.primary
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => showTopics(context, c),
              icon: const Icon(Icons.tune_rounded, size: 17),
              label: const Text('Мои темы'),
            ),
          ),
          const SizedBox(height: 17),
          _Categories(controller: c),
          const SizedBox(height: 22),
          if (c.error != null) _ErrorBanner(controller: c),
          if (c.posts.isEmpty && !c.loading)
            EmptyState(
              icon: c.feedMode == 'following'
                  ? Icons.people_outline_rounded
                  : Icons.search_off_rounded,
              title: c.feedMode == 'following'
                  ? 'Здесь будут ваши подписки'
                  : 'Публикаций пока нет',
              description: c.feedMode == 'following'
                  ? 'Подпишитесь на авторов в их профилях. Их новости появятся в этой ленте.'
                  : 'Попробуйте выбрать другую категорию или изменить поиск.',
            ),
          if (c.loading && c.posts.isEmpty)
            ...List.generate(3, (_) => const _LoadingCard()),
          for (var i = 0; i < c.posts.length; i++) ...[
            if (i == 1)
              Padding(
                padding: const EdgeInsets.only(top: 5, bottom: 17),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Последние публикации',
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    Icon(
                      Icons.south_rounded,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            PostCard(
              controller: c,
              post: c.posts[i],
              featured: i == 0 && c.searchQuery.isEmpty,
              onTap: () => openPost(context, c, c.posts[i]),
              onBookmark: () async {
                if (await requireAuth(context, c) && context.mounted) {
                  await perform(context, () => c.bookmark(c.posts[i].id));
                }
              },
              onAuthor: () => openProfile(context, c, c.posts[i].author.id),
            ),
            const SizedBox(height: 18),
          ],
        ],
      ),
    );
  }
}

class _Categories extends StatelessWidget {
  const _Categories({required this.controller, this.eventsOnly = false});
  final PulseController controller;
  final bool eventsOnly;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 7),
          child: ChoiceChip(
            label: const Text('Все'),
            selected: controller.selectedCategory == null,
            selectedColor: Theme.of(context).colorScheme.primary,
            labelStyle: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: controller.selectedCategory == null
                  ? Theme.of(context).colorScheme.onPrimary
                  : Theme.of(context).colorScheme.onSurface,
            ),
            backgroundColor: Theme.of(context).colorScheme.surface,
            onSelected: (_) => perform(
              context,
              () => controller.loadFeed(
                mode: controller.feedMode,
                eventsOnly: eventsOnly,
              ),
            ),
          ),
        ),
        for (final category in controller.categories)
          Padding(
            padding: const EdgeInsets.only(right: 7),
            child: ChoiceChip(
              label: Text(category.name),
              selected: controller.selectedCategory == category.id,
              selectedColor: Theme.of(context).colorScheme.primary,
              labelStyle: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: controller.selectedCategory == category.id
                    ? Theme.of(context).colorScheme.onPrimary
                    : Theme.of(context).colorScheme.onSurface,
              ),
              backgroundColor: Theme.of(context).colorScheme.surface,
              onSelected: (_) => perform(
                context,
                () => controller.loadFeed(
                  categoryId: category.id,
                  mode: controller.feedMode,
                  eventsOnly: eventsOnly,
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class _Events extends StatefulWidget {
  const _Events({required this.controller});
  final PulseController controller;
  @override
  State<_Events> createState() => _EventsState();
}

class _EventsState extends State<_Events> {
  DateTime? _day;
  bool _free = false;
  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final theme = Theme.of(context);
    final now = DateTime.now();
    final events = c.posts
        .where(
          (post) =>
              post.isEvent &&
              (_day == null ||
                  post.eventStart?.toLocal().year == _day!.year &&
                      post.eventStart?.toLocal().month == _day!.month &&
                      post.eventStart?.toLocal().day == _day!.day) &&
              (!_free ||
                  post.price.isEmpty ||
                  [
                    '0',
                    'бесплатно',
                    'свободный вход',
                  ].contains(post.price.toLowerCase())),
        )
        .toList();
    return RefreshIndicator(
      onRefresh: () => c.loadFeed(
        eventsOnly: true,
        categoryId: c.selectedCategory,
        mode: c.feedMode,
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 15, 20, 30),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Text('События', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text(
            'Лекции, встречи и мероприятия УУНИТ',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 23),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(8, (index) {
                final date = DateTime(now.year, now.month, now.day + index - 1);
                final active = index == 0 ? _day == null : _day == date;
                const weekdays = ['ПН', 'ВТ', 'СР', 'ЧТ', 'ПТ', 'СБ', 'ВС'];
                return Padding(
                  padding: const EdgeInsets.only(right: 9),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(15),
                    onTap: () =>
                        setState(() => _day = index == 0 ? null : date),
                    child: Container(
                      width: 62,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: active
                            ? theme.colorScheme.primary
                            : theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            index == 0 ? 'ДАТЫ' : weekdays[date.weekday - 1],
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              letterSpacing: .8,
                              color: active
                                  ? theme.colorScheme.onPrimary.withValues(
                                      alpha: .7,
                                    )
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 7),
                          Text(
                            index == 0 ? 'Все' : '${date.day}',
                            style: TextStyle(
                              fontSize: index == 0 ? 18 : 22,
                              fontWeight: FontWeight.w700,
                              color: active
                                  ? theme.colorScheme.onPrimary
                                  : theme.colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 19),
          Wrap(
            spacing: 9,
            runSpacing: 6,
            children: [
              FilterChip(
                label: const Text('Бесплатно'),
                avatar: Icon(
                  Icons.confirmation_number_outlined,
                  size: 16,
                  color: _free
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
                selected: _free,
                onSelected: (value) => setState(() => _free = value),
              ),
              FilterChip(
                label: const Text('Друзья идут'),
                avatar: const Icon(Icons.people_outline_rounded, size: 16),
                selected: c.feedMode == 'friends',
                onSelected: (value) async {
                  if (value && !await requireAuth(context, c)) return;
                  if (context.mounted) {
                    await perform(
                      context,
                      () => c.loadFeed(
                        mode: value ? 'friends' : 'all',
                        eventsOnly: true,
                        categoryId: c.selectedCategory,
                      ),
                    );
                  }
                },
              ),
              if (_day != null)
                ActionChip(
                  label: const Text('Все даты'),
                  avatar: const Icon(Icons.close_rounded, size: 15),
                  onPressed: () => setState(() => _day = null),
                ),
            ],
          ),
          const SizedBox(height: 15),
          _Categories(controller: c, eventsOnly: true),
          const SizedBox(height: 23),
          if (c.error != null) _ErrorBanner(controller: c),
          if (c.loading && events.isEmpty) const _LoadingCard(),
          if (events.isEmpty && !c.loading)
            const EmptyState(
              icon: Icons.event_available_outlined,
              title: 'На эти даты событий нет',
              description: 'Выберите другой день или посмотрите все события.',
            ),
          for (final post in events)
            Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: PostCard(
                controller: c,
                post: post,
                onTap: () => openPost(context, c, post),
                onBookmark: () async {
                  if (await requireAuth(context, c) && context.mounted) {
                    await perform(context, () => c.bookmark(post.id));
                  }
                },
                onAuthor: () => openProfile(context, c, post.author.id),
              ),
            ),
        ],
      ),
    );
  }
}

class _Bookmarks extends StatelessWidget {
  const _Bookmarks({required this.controller});
  final PulseController controller;
  @override
  Widget build(BuildContext context) {
    final c = controller;
    return RefreshIndicator(
      onRefresh: c.loadSavedPosts,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 15, 20, 30),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Text('Избранное', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text(
            'Сохранённые новости и события',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 25),
          if (c.user == null)
            EmptyState(
              icon: Icons.bookmark_border_rounded,
              title: 'Сохраните важное',
              description:
                  'Войдите, чтобы сохранять новости и мероприятия в своём профиле.',
              label: 'Войти',
              action: () async {
                if (await requireAuth(context, c) && context.mounted) {
                  await perform(context, c.loadSavedPosts);
                }
              },
            )
          else if (c.savedPosts.isEmpty && !c.loading)
            const EmptyState(
              icon: Icons.bookmark_border_rounded,
              title: 'Пока ничего не сохранено',
              description:
                  'Нажмите на закладку в карточке публикации, чтобы добавить её сюда.',
            ),
          for (final post in c.savedPosts)
            Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: PostCard(
                controller: c,
                post: post,
                onTap: () => openPost(context, c, post),
                onBookmark: () => perform(context, () => c.bookmark(post.id)),
                onAuthor: () => openProfile(context, c, post.author.id),
              ),
            ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.controller});
  final PulseController controller;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.error.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          Icon(
            Icons.wifi_off_rounded,
            color: Theme.of(context).colorScheme.error,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              controller.error!,
              style: const TextStyle(fontSize: 12),
            ),
          ),
          IconButton(
            tooltip: 'Настроить подключение',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SettingsScreen(controller: controller),
              ),
            ),
            icon: const Icon(Icons.settings_outlined, size: 20),
          ),
        ],
      ),
    ),
  );
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 18),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(22),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 165,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(13),
          ),
        ),
        const SizedBox(height: 18),
        Container(
          height: 16,
          width: 240,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        const SizedBox(height: 11),
        Container(
          height: 13,
          width: 180,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
      ],
    ),
  );
}
