import 'package:flutter/material.dart';
import '../domain/controller.dart';
import '../domain/models.dart';
import 'components.dart';
import 'account_screens.dart';
import 'compose_screen.dart';

class PostGallery extends StatefulWidget {
  const PostGallery({
    super.key,
    required this.controller,
    required this.post,
    this.height = 250,
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
  });
  final PulseController controller;
  final CampusPost post;
  final double height;
  final BorderRadius borderRadius;
  @override
  State<PostGallery> createState() => _PostGalleryState();
}

class _PostGalleryState extends State<PostGallery> {
  int _page = 0;
  @override
  Widget build(BuildContext context) {
    final images = widget.post.images;
    if (images.isEmpty) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: widget.borderRadius,
      child: SizedBox(
        height: widget.height,
        child: Stack(
          children: [
            PageView.builder(
              itemCount: images.length,
              onPageChanged: (value) => setState(() => _page = value),
              itemBuilder: (context, index) => GestureDetector(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => _PhotoViewer(
                      controller: widget.controller,
                      images: images,
                      initial: index,
                    ),
                  ),
                ),
                child: PulseImage(
                  mediaUrl(widget.controller, images[index]),
                  width: double.infinity,
                  height: widget.height,
                  fit: BoxFit.cover,
                  offline: widget.controller.baseUrl.startsWith('demo:'),
                  loadingBuilder: (context, child, progress) => progress == null
                      ? child
                      : ColoredBox(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest,
                          child: const Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                  errorBuilder: (_, _, _) =>
                      const Center(child: Icon(Icons.broken_image_outlined)),
                ),
              ),
            ),
            if (images.length > 1)
              Positioned(
                right: 12,
                top: 12,
                child: _PhotoCount(text: '${_page + 1} / ${images.length}'),
              ),
            if (images.length > 1)
              Positioned(
                bottom: 12,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    images.length,
                    (index) => Container(
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: index == _page ? 18 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: index == _page ? Colors.white : Colors.white54,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PhotoCount extends StatelessWidget {
  const _PhotoCount({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class _PhotoViewer extends StatefulWidget {
  const _PhotoViewer({
    required this.controller,
    required this.images,
    required this.initial,
  });
  final PulseController controller;
  final List<String> images;
  final int initial;
  @override
  State<_PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<_PhotoViewer> {
  late final PageController _pages = PageController(
    initialPage: widget.initial,
  );
  late int _page = widget.initial;
  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      title: Text('${_page + 1} / ${widget.images.length}'),
    ),
    body: PageView.builder(
      controller: _pages,
      itemCount: widget.images.length,
      onPageChanged: (value) => setState(() => _page = value),
      itemBuilder: (_, index) => InteractiveViewer(
        minScale: 1,
        maxScale: 4,
        child: Center(
          child: PulseImage(
            mediaUrl(widget.controller, widget.images[index]),
            fit: BoxFit.contain,
            offline: widget.controller.baseUrl.startsWith('demo:'),
            errorBuilder: (_, _, _) =>
                const Icon(Icons.broken_image_outlined, color: Colors.white),
          ),
        ),
      ),
    ),
  );
}

Future<void> showTopics(
  BuildContext context,
  PulseController controller,
) async {
  if (!await requireAuth(context, controller) || !context.mounted) return;
  var busy = false;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => StatefulBuilder(
      builder: (context, setState) => AnimatedBuilder(
        animation: controller,
        builder: (context, _) => SizedBox(
          height: MediaQuery.sizeOf(context).height * .75,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 10, 22, 24),
            children: [
              Text(
                'Мои темы',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 10),
              const Text(
                'Новости выбранных тем появятся в «Подписках» вместе с публикациями авторов.',
              ),
              const SizedBox(height: 18),
              for (final category in controller.categories)
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: Text(category.name),
                  value:
                      controller.user?.interests.contains(category.id) == true,
                  onChanged: busy
                      ? null
                      : (_) async {
                          setState(() => busy = true);
                          await perform(
                            context,
                            () => controller.toggleTopic(category.id),
                          );
                          if (context.mounted) setState(() => busy = false);
                        },
                ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Готово'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class AiReviewPanel extends StatefulWidget {
  const AiReviewPanel({
    super.key,
    required this.controller,
    required this.post,
    required this.onChanged,
  });
  final PulseController controller;
  final CampusPost post;
  final Future<void> Function() onChanged;
  @override
  State<AiReviewPanel> createState() => _AiReviewPanelState();
}

class _AiReviewPanelState extends State<AiReviewPanel> {
  bool _busy = false;
  @override
  Widget build(BuildContext context) {
    final review = widget.post.aiReview;
    if (review == null) return const SizedBox.shrink();
    final status = review['status'];
    const titles = {
      'queued': 'Ожидает проверки ИИ',
      'running': 'ИИ проверяет публикацию',
      'approved': 'ИИ: явных нарушений не найдено',
      'changes_requested': 'ИИ предлагает исправления',
      'appealed': 'Отправлено на перепроверку человеку',
      'manual': 'Требуется проверка модератором',
      'unavailable': 'Публикация передана модератору',
    };
    if (!titles.containsKey(status)) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 14, bottom: 10),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                status == 'approved'
                    ? Icons.verified_outlined
                    : Icons.fact_check_outlined,
                size: 21,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  titles[status]!,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            (review['reason']?.toString().isNotEmpty ?? false)
                ? review['reason'].toString()
                : 'Проверяются текст и фотографии. Обновите экран через несколько секунд.',
            style: const TextStyle(fontSize: 12, height: 1.5),
          ),
          const SizedBox(height: 7),
          Text(
            'Итоговое решение принимает человек.',
            style: theme.textTheme.bodySmall,
          ),
          if (status == 'changes_requested' &&
              widget.post.author.id == widget.controller.user?.id)
            TextButton(
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ComposeScreen(
                      controller: widget.controller,
                      post: widget.post,
                    ),
                  ),
                );
                await widget.onChanged();
              },
              child: const Text('Исправить публикацию'),
            ),
          if (status == 'changes_requested' &&
              widget.post.author.id == widget.controller.user?.id)
            TextButton(
              onPressed: _busy
                  ? null
                  : () async {
                      setState(() => _busy = true);
                      final ok = await perform(
                        context,
                        () => widget.controller.appealPost(widget.post.id),
                        success: 'Перепроверку проведёт модератор',
                      );
                      if (ok) await widget.onChanged();
                      if (mounted) setState(() => _busy = false);
                    },
              child: const Text('Запросить проверку человеком'),
            ),
        ],
      ),
    );
  }
}
