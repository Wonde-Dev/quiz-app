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
  });

  factory Question.fromMap(Map<String, dynamic> map) {
    final optionsRaw = map['options'] as List<dynamic>?;
    return Question(
      id: map['id'] as String,
      quizId: map['quiz_id'] as String? ?? '',
      text: map['text'] as String? ?? '',
      type: map['type'] as String? ?? 'multiple_choice',
      options: optionsRaw
          ?.map((e) => Option.fromMap(e as Map<String, dynamic>))
          .toList() ??
          const [],
      correctAnswer: map['correct_answer'] as String?,
      points: map['points'] as int? ?? 1,
      order: map['order'] as int? ?? 0,
      explanation: map['explanation'] as String?,
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
    };
  }
}