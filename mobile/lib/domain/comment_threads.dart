import 'models.dart';

class CommentThreadEntry {
  const CommentThreadEntry(this.comment, this.depth, this.parent);
  final CampusComment comment;
  final int depth;
  final CampusComment? parent;
}

/// Preserve root/sibling order while keeping every reply beside its parent.
/// Missing parents and malformed cycles must never hide a comment.
List<CommentThreadEntry> threadComments(List<CampusComment> comments) {
  final byId = {for (final comment in comments) comment.id: comment};
  final children = <String, List<CampusComment>>{};
  final roots = <CampusComment>[];
  for (final comment in comments) {
    final parent = comment.parentId;
    if (parent == null || parent == comment.id || !byId.containsKey(parent)) {
      roots.add(comment);
    } else {
      (children[parent] ??= []).add(comment);
    }
  }
  final result = <CommentThreadEntry>[];
  final visited = <String>{};
  void append(CampusComment root) {
    final pending = <CommentThreadEntry>[
      CommentThreadEntry(root, 0, byId[root.parentId]),
    ];
    while (pending.isNotEmpty) {
      final entry = pending.removeLast();
      if (!visited.add(entry.comment.id)) continue;
      result.add(entry);
      for (final child
          in (children[entry.comment.id] ?? <CampusComment>[]).reversed) {
        pending.add(CommentThreadEntry(child, entry.depth + 1, entry.comment));
      }
    }
  }

  for (final root in roots) {
    append(root);
  }
  for (final comment in comments) {
    if (!visited.contains(comment.id)) append(comment);
  }
  return result;
}
