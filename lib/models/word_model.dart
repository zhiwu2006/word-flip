class Word {
  final String word;
  final String chineseMeaning;
  final Map<String, String> phrases;
  final List<String> exampleSentences;  // 包含中英文例句

  Word({
    required this.word,
    required this.chineseMeaning,
    required this.phrases,
    required this.exampleSentences,
  });

  factory Word.fromJson(Map<String, dynamic> json) {
    return Word(
      word: json['word'] as String,
      chineseMeaning: json['chinese_meaning'] as String,
      phrases: Map<String, String>.from(json['phrases'] as Map),
      exampleSentences: List<String>.from(json['example_sentences'] as List),
    );
  }

  Map<String, dynamic> toJson() => {
    'word': word,
    'chinese_meaning': chineseMeaning,
    'phrases': phrases,
    'example_sentences': exampleSentences,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Word &&
          runtimeType == other.runtimeType &&
          word == other.word &&
          chineseMeaning == other.chineseMeaning;

  @override
  int get hashCode => word.hashCode ^ chineseMeaning.hashCode;
}
