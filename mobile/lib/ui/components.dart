import 'dart:convert';
import 'package:flutter/material.dart';
import '../domain/controller.dart';
import '../domain/models.dart';

const ink = Color(0xFF111D35);
const cobalt = Color(0xFF3459E6);
const uunitViolet = Color(0xFF4D19CC);
const uunitLilac = Color(0xFFCBB8FF);
const uunitDeep = Color(0xFF2A1468);
const warmPaper = Color(0xFFF5F5F2);
const muted = Color(0xFF7A8292);

Color parseColor(String value, [Color fallback = cobalt]) {
  final hex = value.replaceFirst('#', '');
  return Color(
    int.tryParse(hex.length == 6 ? 'FF$hex' : hex, radix: 16) ??
        fallback.toARGB32(),
  );
}

String mediaUrl(PulseController controller, String value) {
  // These immutable demo covers are bundled in both APKs, keeping the first
  // review fast even when the temporary tunnel is slow. User uploads use HTTPS.
  if (RegExp(
    r'^/media/covers/(campus|coding|science|sport|culture|community)\.jpg$',
  ).hasMatch(value)) {
    return 'assets/demo/${value.split('/').last}';
  }
  if (value.isEmpty ||
      value.startsWith('http') ||
      value.startsWith('data:') ||
      value.startsWith('assets/')) {
    return value;
  }
  return '${controller.baseUrl.replaceFirst(RegExp(r'/+$'), '')}/${value.replaceFirst(RegExp(r'^/+'), '')}';
}

const monthNames = [
  'января',
  'февраля',
  'марта',
  'апреля',
  'мая',
  'июня',
  'июля',
  'августа',
  'сентября',
  'октября',
  'ноября',
  'декабря',
];
const shortMonthNames = [
  'янв',
  'фев',
  'мар',
  'апр',
  'май',
  'июн',
  'июл',
  'авг',
  'сен',
  'окт',
  'ноя',
  'дек',
];
String dateLabel(DateTime? value, {bool time = false}) {
  if (value == null) return '';
  final date = value.toLocal();
  final label = '${date.day} ${monthNames[date.month - 1]}';
  return time
      ? '$label · ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}'
      : label;
}

String relativeDate(DateTime? value) {
  if (value == null) return '';
  final diff = DateTime.now().difference(value.toLocal());
  if (diff.inMinutes < 1) return 'Только что';
  if (diff.inMinutes < 60) return '${diff.inMinutes} мин назад';
  if (diff.inHours < 24) return '${diff.inHours} ч назад';
  if (diff.inDays == 1) return 'Вчера';
  return dateLabel(value);
}

String countLabel(int count, String one, String few, String many) {
  if (count % 100 >= 11 && count % 100 <= 14) return '$count $many';
  return '$count ${count % 10 == 1
      ? one
      : count % 10 >= 2 && count % 10 <= 4
      ? few
      : many}';
}

void notifyError(BuildContext context, Object error) {
  final message = error.toString().replaceFirst(
    RegExp(r'^(Exception|StateError|ApiException):\s*'),
    '',
  );
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
  );
}

Future<bool> perform(
  BuildContext context,
  Future<void> Function() action, {
  String? success,
}) async {
  try {
    await action();
    if (context.mounted && success != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(success), behavior: SnackBarBehavior.floating),
      );
    }
    return true;
  } catch (error) {
    if (context.mounted) notifyError(context, error);
    return false;
  }
}

class ContentWidth extends StatelessWidget {
  const ContentWidth({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    heightFactor: 1,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 760),
      child: Padding(padding: padding, child: child),
    ),
  );
}

class PulseImage extends StatelessWidget {
  const PulseImage(
    this.source, {
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.errorBuilder,
    this.loadingBuilder,
    this.offline = false,
  });
  final String source;
  final double? width, height;
  final BoxFit fit;
  final ImageErrorWidgetBuilder? errorBuilder;
  final ImageLoadingBuilder? loadingBuilder;
  final bool offline;
  @override
  Widget build(BuildContext context) {
    Widget fallback(Object error) =>
        errorBuilder?.call(context, error, null) ??
        SizedBox(width: width, height: height);
    if (source.startsWith('assets/')) {
      return Image.asset(
        source,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: errorBuilder,
      );
    }
    if (source.startsWith('data:')) {
      try {
        return Image.memory(
          base64Decode(source.substring(source.indexOf(',') + 1)),
          width: width,
          height: height,
          fit: fit,
          errorBuilder: errorBuilder,
        );
      } catch (error) {
        return fallback(error);
      }
    }
    if (offline) return fallback(StateError('Изображение недоступно в демо.'));
    return Image.network(
      source,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: errorBuilder,
      loadingBuilder: loadingBuilder,
    );
  }
}

class PulseAvatar extends StatelessWidget {
  const PulseAvatar({
    super.key,
    required this.user,
    this.radius = 22,
    this.onTap,
    this.controller,
  });
  final UserProfile user;
  final double radius;
  final VoidCallback? onTap;
  final PulseController? controller;
  @override
  Widget build(BuildContext context) {
    final background = parseColor(user.avatarColor);
    final foreground = Theme.of(context).brightness == Brightness.dark
        ? Color.lerp(background, Colors.white, .4)!
        : background;
    final avatar = CircleAvatar(
      radius: radius,
      backgroundColor: background.withValues(alpha: .13),
      child: ClipOval(
        child: SizedBox(
          width: radius * 2,
          height: radius * 2,
          child: user.avatarUrl.isNotEmpty
              ? PulseImage(
                  controller == null
                      ? user.avatarUrl
                      : mediaUrl(controller!, user.avatarUrl),
                  fit: BoxFit.cover,
                  offline: controller?.baseUrl.startsWith('demo:') ?? false,
                  errorBuilder: (_, _, _) => _initials(foreground),
                )
              : _initials(foreground),
        ),
      ),
    );
    return onTap == null
        ? avatar
        : InkWell(
            borderRadius: BorderRadius.circular(radius),
            onTap: onTap,
            child: avatar,
          );
  }

  Widget _initials(Color color) => Center(
    child: Text(
      user.initials,
      style: TextStyle(
        color: color,
        fontSize: radius * .66,
        fontWeight: FontWeight.w700,
        letterSpacing: -.5,
      ),
    ),
  );
}

class CoverImage extends StatelessWidget {
  const CoverImage({
    super.key,
    required this.controller,
    required this.post,
    this.height,
    this.borderRadius = BorderRadius.zero,
  });
  final PulseController controller;
  final CampusPost post;
  final double? height;
  final BorderRadius borderRadius;
  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            parseColor(post.category?.color ?? '#3459E6'),
            const Color(0xFF111D35),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -30,
            bottom: -70,
            child: Icon(
              post.isEvent ? Icons.event_outlined : Icons.article_outlined,
              size: 250,
              color: Colors.white.withValues(alpha: .07),
            ),
          ),
          Center(
            child: Icon(
              post.isEvent
                  ? Icons.event_available_outlined
                  : Icons.school_outlined,
              color: Colors.white.withValues(alpha: .8),
              size: 45,
            ),
          ),
        ],
      ),
    );
    final cover = ClipRRect(
      borderRadius: borderRadius,
      child: post.coverUrl.isEmpty
          ? placeholder
          : PulseImage(
              mediaUrl(controller, post.coverUrl),
              width: double.infinity,
              height: height,
              fit: BoxFit.cover,
              offline: controller.baseUrl.startsWith('demo:'),
              errorBuilder: (_, _, _) => placeholder,
              loadingBuilder: (context, child, progress) => progress == null
                  ? child
                  : Container(
                      height: height,
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      child: const Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ),
            ),
    );
    return Stack(
      children: [
        cover,
        if (post.images.length > 1)
          Positioned(
            right: 12,
            bottom: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.photo_library_outlined,
                    color: Colors.white,
                    size: 14,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '${post.images.length}',
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class CategoryPill extends StatelessWidget {
  const CategoryPill({
    super.key,
    required this.label,
    this.color,
    this.light = false,
    this.icon,
  });
  final String label;
  final Color? color;
  final bool light;
  final IconData? icon;
  @override
  Widget build(BuildContext context) {
    final original = color ?? Theme.of(context).colorScheme.primary;
    final tint = !light && Theme.of(context).brightness == Brightness.dark
        ? Color.lerp(original, Colors.white, .28)!
        : original;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: light
            ? Colors.white.withValues(alpha: .94)
            : tint.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: light ? ink : tint),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: light ? ink : tint,
              letterSpacing: .1,
            ),
          ),
        ],
      ),
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.status});
  final String status;
  static String label(String status) => switch (status) {
    'published' => 'Опубликовано',
    'pending' || 'pending_review' || 'submitted' => 'На проверке',
    'ai_review' => 'На проверке ИИ',
    'rejected' => 'Отклонено',
    'returned' || 'changes_requested' || 'needs_changes' => 'Нужны изменения',
    'draft' => 'Черновик',
    _ => status,
  };
  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'published' => const Color(0xFF278363),
      'rejected' => const Color(0xFFC25353),
      'returned' ||
      'changes_requested' ||
      'needs_changes' => const Color(0xFFB7832F),
      'draft' => muted,
      _ => cobalt,
    };
    return CategoryPill(label: label(status), color: color);
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.description,
    this.action,
    this.label,
  });
  final IconData icon;
  final String title;
  final String? description, label;
  final VoidCallback? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 52),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: .07),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Icon(
            icon,
            color: Theme.of(context).colorScheme.primary,
            size: 31,
          ),
        ),
        const SizedBox(height: 22),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        if (description != null) ...[
          const SizedBox(height: 10),
          Text(
            description!,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.6,
            ),
          ),
        ],
        if (action != null && label != null) ...[
          const SizedBox(height: 22),
          FilledButton(onPressed: action, child: Text(label!)),
        ],
      ],
    ),
  );
}

class PostCard extends StatelessWidget {
  const PostCard({
    super.key,
    required this.controller,
    required this.post,
    required this.onTap,
    this.featured = false,
    this.onBookmark,
    this.onAuthor,
  });
  final PulseController controller;
  final CampusPost post;
  final VoidCallback onTap;
  final VoidCallback? onBookmark, onAuthor;
  final bool featured;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (featured || post.coverUrl.isNotEmpty)
              Stack(
                children: [
                  CoverImage(
                    controller: controller,
                    post: post,
                    height: featured ? 235 : 184,
                  ),
                  Positioned(
                    left: 16,
                    top: 16,
                    child: CategoryPill(
                      label:
                          post.category?.name ??
                          (post.isEvent ? 'Событие' : 'Новости'),
                      light: true,
                      icon: post.isEvent ? Icons.event_outlined : null,
                    ),
                  ),
                  if (onBookmark != null)
                    Positioned(
                      right: 12,
                      top: 12,
                      child: IconButton.filledTonal(
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white.withValues(alpha: .95),
                          foregroundColor: ink,
                        ),
                        tooltip: post.isBookmarked
                            ? 'Убрать из избранного'
                            : 'Сохранить',
                        onPressed: onBookmark,
                        icon: Icon(
                          post.isBookmarked
                              ? Icons.bookmark_rounded
                              : Icons.bookmark_border_rounded,
                          size: 21,
                        ),
                      ),
                    ),
                  if (post.isEvent && post.eventStart != null)
                    Positioned(
                      left: 16,
                      bottom: 15,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: ink.withValues(alpha: .82),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Text(
                          dateLabel(post.eventStart, time: true),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 17, 18, 15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!featured && post.coverUrl.isEmpty) ...[
                    CategoryPill(label: post.category?.name ?? 'Новости'),
                    const SizedBox(height: 12),
                  ],
                  Text(
                    post.title,
                    maxLines: featured ? 3 : 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: featured ? 25 : 20,
                      height: 1.19,
                      letterSpacing: -.6,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  if (post.preview.isNotEmpty) ...[
                    const SizedBox(height: 9),
                    Text(
                      post.preview.replaceAll('\n', ' '),
                      maxLines: featured ? 2 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.55,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (post.isEvent && post.location.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(
                          Icons.place_outlined,
                          size: 14,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            post.location,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        if (post.price.isNotEmpty)
                          Text(
                            post.price,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 17),
                  Row(
                    children: [
                      PulseAvatar(
                        controller: controller,
                        user: post.author,
                        radius: 13,
                        onTap: onAuthor,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: GestureDetector(
                          onTap: onAuthor,
                          child: Text(
                            post.author.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        relativeDate(post.publishedAt ?? post.createdAt),
                        style: TextStyle(
                          fontSize: 10,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Icon(
                        post.myReaction != null
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        size: 14,
                        color: post.myReaction != null
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${post.reactionsCount}',
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Icon(
                        Icons.mode_comment_outlined,
                        size: 13,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${post.commentsCount}',
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
