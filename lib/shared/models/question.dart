/// Represents a single answer option for a question.
class Option {
  final String id;
  final String text;
  final bool isCorrect;

  const Option({
    required this.id,
    required this.text,
    this.isCorrect = false,
  });

  factory Option.fromMap(Map<String, dynamic> map) {
    return Option(
      id: map['id'] as String? ?? '',
      text: map['text'] as String? ?? '',
      isCorrect: map['is_correct'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'text': text,
      'is_correct': isCorrect,
    };
  }
}

/// Represents a single question inside a quiz.
class Question {
  final String id;
  final String quizId;
  final String text;
  final String type; // multiple_choice, true_false, short_answer
  final List<Option> options;
  final String? correctAnswer;
  final int points;
  final int order;
  final String? explanation;
  final String? imageUrl;

  const Question({
    required this.id,
    required this.quizId,
    required this.text,
    this.type = 'multiple_choice',
    this.options = const [],
    this.correctAnswer,
    this.points = 1,
    this.order = 0,
    this.explanation,
    this.imageUrl,
  });

  String get cleanText {
    return text.replaceAll(RegExp(r'\[diagram:\s*[^\]]+\]'), '').trim();
  }

  factory Question.fromMap(Map<String, dynamic> map) {
    final optionsRaw = map['options'] as List<dynamic>?;
    final rawText = map['text'] as String? ?? '';
    final rawExplanation = map['explanation'] as String?;
    String? imgUrl = map['image_url'] as String?;
    if (imgUrl == null || imgUrl.isEmpty) {
      final match = RegExp(r'\[diagram:\s*(https?://[^\s\]]+|data:image[^\s\]]+)\]')
          .firstMatch(rawText);
      if (match != null) {
        imgUrl = match.group(1);
      } else if (rawExplanation != null) {
        final expMatch = RegExp(r'\[diagram:\s*(https?://[^\s\]]+|data:image[^\s\]]+)\]')
            .firstMatch(rawExplanation);
        if (expMatch != null) {
          imgUrl = expMatch.group(1);
        }
      }
    }

    return Question(
      id: map['id'] as String,
      quizId: map['quiz_id'] as String? ?? '',
      text: rawText,
      type: map['type'] as String? ?? 'multiple_choice',
      options: optionsRaw
          ?.map((e) => Option.fromMap(e as Map<String, dynamic>))
          .toList() ??
          const [],
      correctAnswer: map['correct_answer'] as String?,
      points: map['points'] as int? ?? 1,
      order: map['order'] as int? ?? 0,
      explanation: rawExplanation,
      imageUrl: imgUrl,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'quiz_id': quizId,
      'text': text,
      'type': type,
      'options': options.map((e) => e.toMap()).toList(),
      'correct_answer': correctAnswer,
      'points': points,
      'order': order,
      'explanation': explanation,
      'image_url': imageUrl,
    };
  }
}