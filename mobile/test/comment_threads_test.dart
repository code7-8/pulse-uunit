import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/domain/comment_threads.dart';
import 'package:pulse/domain/models.dart';

CampusComment comment(String id, {String? parent}) => CampusComment.fromJson({
  'id': id,
  'body': 'Комментарий $id',
  'parent_id': parent,
  'author': {'id': id, 'name': 'Автор $id'},
  'created_at': '2026-10-24T01:00:00Z',
});

void main() {
  test(
    'New replies render immediately after their parent instead of at the end',
    () {
      final result = threadComments([
        comment('1'),
        comment('2'),
        comment('3', parent: '1'),
        comment('4', parent: '1'),
      ]);
      expect(result.map((e) => e.comment.id), ['1', '3', '4', '2']);
      expect(result.map((e) => e.depth), [0, 1, 1, 0]);
      expect(result[1].parent?.author.name, 'Автор 1');
    },
  );
  test(
    'Replies to replies stay in the same branch with a stable sibling order',
    () {
      final result = threadComments([
        comment('1'),
        comment('2'),
        comment('3', parent: '1'),
        comment('4', parent: '1'),
        comment('5', parent: '3'),
      ]);
      expect(result.map((e) => e.comment.id), ['1', '3', '5', '4', '2']);
      expect(result[2].depth, 2);
      expect(result[2].parent?.id, '3');
    },
  );
  test('Missing parents and cycles never drop or duplicate comments', () {
    final result = threadComments([
      comment('1', parent: 'missing'),
      comment('2', parent: '3'),
      comment('3', parent: '2'),
      comment('4', parent: '4'),
    ]);
    expect(result.map((e) => e.comment.id).toSet(), {'1', '2', '3', '4'});
    expect(result.length, 4);
  });
}
