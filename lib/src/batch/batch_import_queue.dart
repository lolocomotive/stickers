enum BatchImportMediaKind { picture, video, gif }

class BatchImportItem {
  final String path;
  final BatchImportMediaKind kind;

  const BatchImportItem({
    required this.path,
    required this.kind,
  });
}

class BatchImportQueue {
  final List<BatchImportItem> items;
  final void Function()? onChanged;
  int _activeIndex = -1;

  BatchImportQueue(List<BatchImportItem> items, {this.onChanged})
      : items = List.unmodifiable(items);

  int get total => items.length;

  int get activeNumber => _activeIndex + 1;

  bool get hasNext => _activeIndex + 1 < items.length;

  BatchImportItem? next() {
    if (!hasNext) return null;
    _activeIndex++;
    return items[_activeIndex];
  }
}
