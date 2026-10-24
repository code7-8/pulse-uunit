import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/domain/models.dart';
import 'package:pulse/ui/post_screen.dart';
import 'package:pulse/ui/pulse_app.dart';
import 'helpers/fake_pulse_controller.dart';

Future<void> configureViewport(WidgetTester tester, double width) async {
  final previousErrorHandler = FlutterError.onError;
  FlutterError.onError = (details) {
    debugPrint(details.toString());
    previousErrorHandler?.call(details);
  };
  addTearDown(() => FlutterError.onError = previousErrorHandler);
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 900);
  tester.platformDispatcher.textScaleFactorTestValue = 1.3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

void expectHealthyLayout(WidgetTester tester) {
  expect(
    tester.takeException(),
    isNull,
    reason: 'The visible screen must lay out without Flutter errors.',
  );
}

void main() {
  testWidgets(
    'A new reply is rendered below its parent before the next thread',
    (tester) async {
      await configureViewport(tester, 430);
      final controller = FakePulseController();
      controller.comments.add(
        CampusComment(
          id: 'comment-2',
          body: 'Отдельное обсуждение',
          author: const UserProfile(id: '4', name: 'Мария'),
          createdAt: DateTime.now(),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CommentsSheet(controller: controller, postId: 'news-1'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ответить').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Ответ первому участнику');
      await tester.tap(find.byTooltip('Отправить комментарий'));
      await tester.pumpAndSettle();
      final parent = tester.getTopLeft(
        find.text(controller.comments.first.body),
      );
      final reply = tester.getTopLeft(find.text('Ответ первому участнику'));
      final next = tester.getTopLeft(find.text('Отдельное обсуждение'));
      expect(reply.dy, greaterThan(parent.dy));
      expect(reply.dy, lessThan(next.dy));
      expect(reply.dx, greaterThan(parent.dx));
      expect(find.text('Ответ: Никита Фёдоров'), findsOneWidget);
      expectHealthyLayout(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );
  for (final width in [360.0, 390.0, 430.0]) {
    testWidgets(
      'Friends and chat remain usable at ${width.toInt()}px with keyboard',
      (tester) async {
        await configureViewport(tester, width);
        addTearDown(tester.view.resetViewInsets);
        final controller = FakePulseController();
        await tester.pumpWidget(PulseApp(controller: controller));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Профиль').last);
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(find.text('Друзья'), 180);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Друзья').first);
        await tester.pumpAndSettle();
        expect(find.text('Найти друзей'), findsWidgets);
        expectHealthyLayout(tester);
        await tester.tap(find.text('Поиск'));
        await tester.pumpAndSettle();
        expect(find.text('Имя или институт'), findsOneWidget);
        expectHealthyLayout(tester);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        await tester.tap(find.text('Чаты').last);
        await tester.pumpAndSettle();
        expect(find.text('Пока нет переписок'), findsOneWidget);
        expectHealthyLayout(tester);

        await tester.tap(find.text('События').last);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text(controller.allPosts.last.title));
        await tester.pumpAndSettle();
        await tester.tap(find.text(controller.allPosts.last.title));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Михаил Александров').first);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Написать'));
        await tester.tap(find.text('Написать'));
        await tester.pumpAndSettle();
        expect(find.text('Сообщение'), findsOneWidget);
        tester.view.viewInsets = const FakeViewPadding(bottom: 310);
        await tester.pumpAndSettle();
        expectHealthyLayout(tester);
        await tester.enterText(
          find.byType(TextField).last,
          'Привет! Давай встретимся перед лекцией у главного корпуса.',
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Отправить'));
        await tester.pumpAndSettle();
        expect(controller.messages.single['body'], contains('перед лекцией'));
        expect(
          find.text(controller.messages.single['body'] as String),
          findsOneWidget,
        );
        controller.setAppearance(mode: ThemeMode.dark);
        await tester.pumpAndSettle();
        expectHealthyLayout(tester);
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
      },
    );
  }

  testWidgets(
    'Comment reply composer handles keyboard and sends the parent ID',
    (tester) async {
      await configureViewport(tester, 360);
      addTearDown(tester.view.resetViewInsets);
      final controller = FakePulseController();
      await tester.pumpWidget(PulseApp(controller: controller));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(controller.allPosts.first.title));
      await tester.pumpAndSettle();
      await tester.tap(find.text(controller.allPosts.first.title));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Комментарии · 2'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ответить'));
      tester.view.viewInsets = const FakeViewPadding(bottom: 310);
      await tester.pumpAndSettle();
      expect(find.text('Ответ: Никита Фёдоров'), findsOneWidget);
      expectHealthyLayout(tester);
      await tester.enterText(
        find.byType(TextField).last,
        'Да, студенты первого курса тоже могут участвовать.',
      );
      await tester.tap(find.byTooltip('Отправить комментарий'));
      await tester.pumpAndSettle();
      expect(controller.lastComment, startsWith('Да, студенты'));
      expect(controller.lastCommentParent, 'comment-1');
      expectHealthyLayout(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );

  testWidgets(
    'Moderator must provide a reason before returning a publication',
    (tester) async {
      await configureViewport(tester, 360);
      final controller = FakePulseController(moderator: true);
      await tester.pumpWidget(PulseApp(controller: controller));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Профиль').last);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Модерация'), 220);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Модерация'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(controller.allPosts.first.title));
      await tester.pumpAndSettle();
      await tester.tap(find.text(controller.allPosts.first.title));
      await tester.pumpAndSettle();
      await tester.tap(find.text('На доработку'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Отправить'));
      await tester.pumpAndSettle();
      expect(find.text('Укажите понятную причину'), findsOneWidget);
      expect(controller.moderationDecision, isNull);
      await tester.enterText(
        find.byType(TextFormField),
        'Добавьте точный адрес и время начала встречи.',
      );
      await tester.tap(find.text('Отправить'));
      await tester.pumpAndSettle();
      expect(controller.moderationDecision, 'return');
      expect(controller.moderationReason, contains('точный адрес'));
      expectHealthyLayout(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );

  for (final width in [360.0, 390.0, 430.0, 760.0]) {
    testWidgets(
      'Readable feed and working navigation at ${width.toInt()}px / 130% text',
      (tester) async {
        await configureViewport(tester, width);
        final controller = FakePulseController();
        await tester.pumpWidget(PulseApp(controller: controller));
        await tester.pumpAndSettle();
        expect(controller.initializeCalls, 1);
        expect(find.text('В университете'), findsOneWidget);
        expect(find.text('Лента'), findsOneWidget);
        expect(find.text('События'), findsOneWidget);
        expect(find.text('Чаты'), findsOneWidget);
        expect(find.text('Избранное'), findsOneWidget);
        expect(find.text('Профиль'), findsOneWidget);
        // A bottom navigation bar must leave enough height for the editorial card.
        expect(tester.getTopLeft(find.text('Лента')).dy, greaterThan(700));
        expect(find.text(controller.allPosts.first.title), findsOneWidget);
        expectHealthyLayout(tester);

        await tester.tap(find.text('События').last);
        await tester.pumpAndSettle();
        expect(find.text('Друзья идут'), findsOneWidget);
        expect(find.text(controller.allPosts.last.title), findsOneWidget);
        expectHealthyLayout(tester);

        await tester.tap(find.text('Избранное').last);
        await tester.pumpAndSettle();
        expect(find.text('Пока ничего не сохранено'), findsOneWidget);
        expectHealthyLayout(tester);

        await tester.tap(find.text('Профиль').last);
        await tester.pumpAndSettle();
        expect(find.text('Александра Константинопольская'), findsWidgets);
        expect(find.text('Редактировать'), findsOneWidget);
        expectHealthyLayout(tester);

        await tester.tap(find.byTooltip('Настройки'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Тёмная'));
        await tester.pumpAndSettle();
        expect(controller.themeMode, ThemeMode.dark);
        expect(
          Theme.of(tester.element(find.text('Палитра'))).brightness,
          Brightness.dark,
        );
        expect(
          controller.initializeCalls,
          1,
          reason: 'Changing the theme must keep the same application session.',
        );
        expectHealthyLayout(tester);
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
      },
    );

    testWidgets(
      'Event editor remains usable at ${width.toInt()}px / 130% text',
      (tester) async {
        await configureViewport(tester, width);
        final controller = FakePulseController();
        await tester.pumpWidget(PulseApp(controller: controller));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Создать публикацию'));
        await tester.pumpAndSettle();
        expect(find.text('Новая публикация'), findsOneWidget);
        await tester.tap(find.text('Событие').first);
        await tester.pumpAndSettle();
        expectHealthyLayout(tester);
        await tester.ensureVisible(find.text('Дата и время'));
        await tester.pumpAndSettle();
        expect(find.text('О событии'), findsOneWidget);
        expect(find.text('Место проведения'), findsOneWidget);
        expect(find.text('На проверку'), findsOneWidget);
        expectHealthyLayout(tester);
        await tester.ensureVisible(
          find.text('Ссылка на регистрацию · необязательно'),
        );
        await tester.pumpAndSettle();
        expectHealthyLayout(tester);
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
      },
    );
  }

  testWidgets('A complete news draft is created then submitted from the editor', (
    tester,
  ) async {
    await configureViewport(tester, 390);
    final controller = FakePulseController();
    await tester.pumpWidget(PulseApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Создать публикацию'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).first,
      'Открытая встреча проектной команды',
    );
    await tester.ensureVisible(find.text('Категория'));
    await tester.tap(find.text('Категория'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Кампус').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(TextFormField).at(1));
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'Приглашаем студентов на открытую встречу команды. Обсудим проекты и возможности участия.',
    );
    await tester.tap(find.text('На проверку'));
    await tester.pumpAndSettle();
    expect(controller.lastCreatedFields?['category'], 'campus');
    expect(controller.lastCreatedFields?['submit'], isFalse);
    expect(controller.lastCreatedFields!.containsKey('category_id'), isFalse);
    expect(controller.submitted, isTrue);
    expect(find.text(controller.lastCreatedFields!['title'] as String), findsWidgets);
    expectHealthyLayout(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets(
    'Guest can open connection settings while the server is offline',
    (tester) async {
      await configureViewport(tester, 360);
      final controller = FakePulseController(signedIn: false)
        ..error = 'Нет соединения с сервером';
      await tester.pumpWidget(PulseApp(controller: controller));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Настроить подключение'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Подключение к серверу'), 250);
      await tester.tap(find.text('Подключение к серверу'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Адрес сервера'));
      expect(find.text('Адрес сервера'), findsOneWidget);
      expectHealthyLayout(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );
}
