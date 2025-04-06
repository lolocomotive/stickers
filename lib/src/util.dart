bool isValidURL(String input){
  final url = Uri.tryParse(input);
  if(url == null) return false;
  if(url.scheme != "http" && url.scheme != "https") return false;
  if(url.host.isEmpty) return false;
  return url.isAbsolute;
}