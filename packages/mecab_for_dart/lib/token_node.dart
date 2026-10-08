/// Class that represent one token from mecab's output.
class TokenNode {
  /// The surface form of the token (how it appears in the text)
  String surface = "";
  /// A list of features of this token (varies depending on the dictionar you
  /// are using)
  List<String> features = [];

  TokenNode(String item) {
    var arr = item.split('\t');
    if (arr.isNotEmpty) {
      surface = arr[0];
    }
    if (arr.length == 2) {
      features = arr[1].split(',');
    } else {
      features = [];
    }
  }
}