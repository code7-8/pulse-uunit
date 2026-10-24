import 'package:flutter/material.dart';
import '../domain/controller.dart';
import '../domain/models.dart';
import 'components.dart';
import 'post_screen.dart';

class ComposeScreen extends StatefulWidget {
  const ComposeScreen({super.key, required this.controller, this.post});
  final PulseController controller;
  final CampusPost? post;
  @override
  State<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends State<ComposeScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _title,
      _body,
      _location,
      _price,
      _registration,
      _imageLink;
  late String _type, _cover;
  late List<String> _images;
  String? _category;
  DateTime? _start, _end;
  CampusPost? _saved;
  bool _busy = false, _uploading = false, _linkVisible = false;
  @override
  void initState() {
    super.initState();
    final post = widget.post;
    _title = TextEditingController(text: post?.title ?? '');
    _body = TextEditingController(text: post?.body ?? '');
    _location = TextEditingController(text: post?.location ?? '');
    _price = TextEditingController(text: post?.price ?? '');
    _registration = TextEditingController(text: post?.registrationUrl ?? '');
    _imageLink = TextEditingController(text: post?.coverUrl ?? '');
    _type = post?.type ?? 'news';
    _images = [...?post?.images];
    _cover = _images.firstOrNull ?? '';
    _category = post?.category?.id;
    _start = post?.eventStart?.toLocal();
    _end = post?.eventEnd?.toLocal();
    _saved = post;
  }

  @override
  void dispose() {
    for (final field in [
      _title,
      _body,
      _location,
      _price,
      _registration,
      _imageLink,
    ]) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate(bool end) async {
    final current =
        (end ? _end ?? _start : _start) ??
        DateTime.now().add(const Duration(days: 1));
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
      helpText: end ? 'Дата окончания' : 'Дата события',
      cancelText: 'Отмена',
      confirmText: 'Далее',
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: current.hour == 0 ? 18 : current.hour,
        minute: current.minute,
      ),
      helpText: 'Время',
      cancelText: 'Отмена',
      confirmText: 'Готово',
    );
    if (time == null || !mounted) return;
    final selected = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    setState(() {
      if (end) {
        _end = selected;
      } else {
        _start = selected;
        if (_end != null && _end!.isBefore(selected)) _end = null;
      }
    });
  }

  Future<void> _save({required bool submit}) async {
    if (!_form.currentState!.validate()) return;
    if (_type == 'event' && _start == null) {
      notifyError(context, 'Укажите дату и время события');
      return;
    }
    if (_type == 'event' && _end != null && _end!.isBefore(_start!)) {
      notifyError(context, 'Время окончания должно быть позже начала');
      return;
    }
    setState(() => _busy = true);
    try {
      final fields = <String, dynamic>{
        'type': _type,
        'title': _title.text.trim(),
        'body': _body.text.trim(),
        'cover_url': _cover,
        'image_urls': _images,
        'category': _category,
        'submit': false,
        'event_start': _type == 'event'
            ? _start?.toUtc().toIso8601String()
            : null,
        'event_end': _type == 'event' ? _end?.toUtc().toIso8601String() : null,
        'location': _type == 'event' ? _location.text.trim() : '',
        'price': _type == 'event' ? _price.text.trim() : '',
        'registration_url': _type == 'event' ? _registration.text.trim() : '',
      };
      _saved = _saved == null
          ? await widget.controller.createPost(fields)
          : await widget.controller.updatePost(_saved!.id, fields);
      if (submit) {
        await widget.controller.submitPost(_saved!.id);
        _saved = await widget.controller.loadPost(_saved!.id);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              submit
                  ? widget.controller.baseUrl.startsWith('demo:')
                        ? 'Публикация отправлена модератору'
                        : 'Публикация отправлена на проверку ИИ'
                  : 'Черновик сохранён',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
        if (submit) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute<void>(
              builder: (_) => PostScreen(
                controller: widget.controller,
                initialPost: _saved!,
              ),
            ),
            result: true,
          );
        } else {
          Navigator.of(context).pop(true);
        }
      }
    } catch (error) {
      if (mounted) notifyError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _addImageLink() {
    final url = _imageLink.text.trim();
    if (url.isEmpty || _images.contains(url)) return;
    if (_images.length >= 6) {
      notifyError(context, 'Можно добавить до 6 фотографий');
      return;
    }
    setState(() {
      _images.add(url);
      _cover = _images.first;
      _imageLink.clear();
    });
  }

  Future<void> _upload() async {
    setState(() => _uploading = true);
    try {
      final urls = await widget.controller.pickAndUploadImages(
        remaining: 6 - _images.length,
      );
      if (urls.isNotEmpty && mounted) {
        setState(() {
          _images.addAll(urls.where((url) => !_images.contains(url)));
          _cover = _images.first;
        });
      }
    } catch (error) {
      if (mounted) notifyError(context, error);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.post == null ? 'Новая публикация' : 'Редактировать публикацию',
        ),
      ),
      body: ContentWidth(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(21, 12, 21, 28),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Новость или событие',
                  style: theme.textTheme.headlineMedium,
                ),
                const SizedBox(height: 10),
                Text(
                  'Публикация появится в ленте после проверки модератором.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 25),
                Row(
                  children: [
                    for (final type in ['news', 'event']) ...[
                      Expanded(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(15),
                          onTap: () => setState(() => _type = type),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 17,
                            ),
                            decoration: BoxDecoration(
                              color: _type == type
                                  ? theme.colorScheme.primary.withValues(
                                      alpha: .08,
                                    )
                                  : theme.colorScheme.surface,
                              border: Border.all(
                                color: _type == type
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.outline,
                                width: _type == type ? 1.5 : 1,
                              ),
                              borderRadius: BorderRadius.circular(15),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  type == 'news'
                                      ? Icons.article_outlined
                                      : Icons.event_outlined,
                                  size: 19,
                                  color: _type == type
                                      ? theme.colorScheme.primary
                                      : theme.colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    type == 'news' ? 'Новость' : 'Событие',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: _type == type
                                          ? theme.colorScheme.primary
                                          : theme.colorScheme.onSurface,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (type == 'news') const SizedBox(width: 12),
                    ],
                  ],
                ),
                const SizedBox(height: 24),
                if (_images.isNotEmpty) ...[
                  SizedBox(
                    height: 125,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _images.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 9),
                      itemBuilder: (_, index) => SizedBox(
                        width: 125,
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: PulseImage(
                                  mediaUrl(widget.controller, _images[index]),
                                  fit: BoxFit.cover,
                                  offline: widget.controller.baseUrl.startsWith(
                                    'demo:',
                                  ),
                                  errorBuilder: (_, _, _) =>
                                      const Icon(Icons.broken_image_outlined),
                                ),
                              ),
                            ),
                            Positioned(
                              top: 3,
                              right: 3,
                              child: IconButton.filledTonal(
                                tooltip: 'Удалить фото ${index + 1}',
                                onPressed: _uploading
                                    ? null
                                    : () => setState(() {
                                        _images.removeAt(index);
                                        _cover = _images.firstOrNull ?? '';
                                      }),
                                icon: const Icon(Icons.close_rounded, size: 17),
                              ),
                            ),
                            Positioned(
                              left: 7,
                              bottom: 7,
                              child: Text(
                                index == 0 ? 'Обложка' : '${index + 1}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  backgroundColor: Colors.black54,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                if (_images.length < 6)
                  OutlinedButton.icon(
                    onPressed: _uploading ? null : _upload,
                    icon: _uploading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add_photo_alternate_outlined),
                    label: Text(
                      _uploading
                          ? 'Загружаем фотографии…'
                          : 'Добавить фото · ${_images.length}/6',
                    ),
                  ),
                const SizedBox(height: 5),
                Text(
                  'До 6 фотографий. Первая станет обложкой.',
                  style: theme.textTheme.bodySmall,
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () =>
                        setState(() => _linkVisible = !_linkVisible),
                    child: Text(
                      _linkVisible
                          ? 'Скрыть ссылку'
                          : 'Указать ссылку на изображение',
                      style: const TextStyle(fontSize: 10),
                    ),
                  ),
                ),
                if (_linkVisible) ...[
                  TextFormField(
                    controller: _imageLink,
                    keyboardType: TextInputType.url,
                    decoration: InputDecoration(
                      labelText: 'Ссылка на обложку',
                      suffixIcon: IconButton(
                        tooltip: 'Применить ссылку',
                        onPressed: () => _addImageLink(),
                        icon: const Icon(Icons.check_rounded),
                      ),
                    ),
                    onFieldSubmitted: (value) => _addImageLink(),
                  ),
                  const SizedBox(height: 15),
                ],
                TextFormField(
                  controller: _title,
                  minLines: 1,
                  maxLines: 3,
                  maxLength: 140,
                  textCapitalization: TextCapitalization.sentences,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    height: 1.4,
                    letterSpacing: -.4,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Заголовок',
                    hintText: 'О чём публикация?',
                    alignLabelWithHint: true,
                  ),
                  validator: (value) => (value ?? '').trim().length < 6
                      ? 'Добавьте заголовок от 6 символов'
                      : null,
                ),
                const SizedBox(height: 9),
                DropdownButtonFormField<String>(
                  initialValue:
                      widget.controller.categories.any(
                        (category) => category.id == _category,
                      )
                      ? _category
                      : null,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Категория'),
                  items: widget.controller.categories
                      .map(
                        (category) => DropdownMenuItem(
                          value: category.id,
                          child: Text(
                            category.name,
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => _category = value,
                  validator: (value) =>
                      value == null ? 'Выберите категорию' : null,
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _body,
                  minLines: 8,
                  maxLines: 20,
                  maxLength: 12000,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Текст публикации',
                    hintText: 'Расскажите подробности',
                    alignLabelWithHint: true,
                  ),
                  validator: (value) => (value ?? '').trim().length < 20
                      ? 'Добавьте текст от 20 символов'
                      : null,
                ),
                if (_type == 'event') ...[
                  const SizedBox(height: 17),
                  Text('О событии', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 18),
                  _DateField(
                    label: 'Дата и время',
                    value: _start == null
                        ? 'Выбрать'
                        : dateLabel(_start, time: true),
                    onTap: () => _pickDate(false),
                  ),
                  const SizedBox(height: 14),
                  _DateField(
                    label: 'Окончание · необязательно',
                    value: _end == null
                        ? 'Выбрать'
                        : dateLabel(_end, time: true),
                    onTap: () => _pickDate(true),
                    onClear: _end == null
                        ? null
                        : () => setState(() => _end = null),
                  ),
                  const SizedBox(height: 15),
                  TextFormField(
                    controller: _location,
                    maxLength: 200,
                    decoration: const InputDecoration(
                      labelText: 'Место проведения',
                      hintText: 'Корпус, аудитория или адрес',
                      prefixIcon: Icon(Icons.place_outlined),
                    ),
                    validator: (value) =>
                        _type == 'event' && (value ?? '').trim().isEmpty
                        ? 'Укажите место проведения'
                        : null,
                  ),
                  const SizedBox(height: 9),
                  TextFormField(
                    controller: _price,
                    maxLength: 80,
                    decoration: const InputDecoration(
                      labelText: 'Стоимость участия',
                      hintText: 'Бесплатно',
                      prefixIcon: Icon(Icons.confirmation_number_outlined),
                    ),
                  ),
                  const SizedBox(height: 9),
                  TextFormField(
                    controller: _registration,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: 'Ссылка на регистрацию · необязательно',
                      prefixIcon: Icon(Icons.link_rounded),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) return null;
                      final uri = Uri.tryParse(value.trim());
                      return uri == null ||
                              !['http', 'https'].contains(uri.scheme) ||
                              uri.host.isEmpty
                          ? 'Укажите полную ссылку с https://'
                          : null;
                    },
                  ),
                ],
                if (widget.post?.status == 'published') ...[
                  const SizedBox(height: 18),
                  Text(
                    'После изменения публикация снова пройдёт проверку.',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.6,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: ContentWidth(
          child: Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(top: BorderSide(color: theme.colorScheme.outline)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 13, 20, 13),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy || _uploading
                        ? null
                        : () => _save(submit: false),
                    child: const Text(
                      'Черновик',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _busy || _uploading
                        ? null
                        : () => _save(submit: true),
                    child: Text(
                      _busy ? 'Сохраняем…' : 'На проверку',
                      style: const TextStyle(fontSize: 12),
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

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
    this.onClear,
  });
  final String label, value;
  final VoidCallback onTap;
  final VoidCallback? onClear;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(14),
    child: InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.schedule_outlined),
        suffixIcon: onClear == null
            ? const Icon(Icons.expand_more_rounded)
            : IconButton(
                tooltip: 'Убрать дату окончания',
                onPressed: onClear,
                icon: const Icon(Icons.close_rounded, size: 18),
              ),
      ),
      child: Text(value, style: const TextStyle(fontSize: 13)),
    ),
  );
}
