bool isValidURL(String input) {
  final url = Uri.tryParse(input);
  if (url == null) return false;
  if (url.scheme != "http" && url.scheme != "https") return false;
  if (url.host.isEmpty) return false;
  return url.isAbsolute;
}

String? titleValidator(String? value) {
  if (value == null || value.isEmpty) {
    return 'Please enter a title';
  }
  return null;
}

String? authorValidator(String? value) {
  if (value == null || value.isEmpty) {
    return 'Please enter an author';
  }
  return null;
}
