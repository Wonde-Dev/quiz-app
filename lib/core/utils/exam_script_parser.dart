/// Represents a parsed question ready to be added to a quiz.
class ParsedQuestion {
  final String text;
  final String type; // 'multiple_choice', 'true_false', 'fill_in_blank', 'short_answer'
  final List<Map<String, dynamic>> options;
  final String? correctAnswer;
  final String? explanation;
  final String? imageUrl;
  final int points;

  const ParsedQuestion({
    required this.text,
    required this.type,
    this.options = const [],
    this.correctAnswer,
    this.explanation,
    this.imageUrl,
    this.points = 1,
  });

  Map<String, dynamic> toMap(int order) {
    final effectiveText = (imageUrl != null && imageUrl!.isNotEmpty)
        ? '$text\n[diagram: $imageUrl]'
        : text;

    return {
      'text': effectiveText,
      'type': type,
      'points': points,
      'order': order,
      'options': options,
      'correct_answer': correctAnswer,
      'explanation': explanation,
      'image_url': imageUrl,
    };
  }
}

/// Smart parser that transforms text scripts into structured questions:
/// - Choose (Multiple Choice)
/// - True or False
/// - Blank Space (Fill in the Blank)
/// - Description (Short Answer / Essay)
class ExamScriptParser {
  static const sampleScript = '''
1. Which organelle is known as the powerhouse of the cell?
A. Nucleus
B. Mitochondria
C. Ribosome
D. Chloroplast
Answer: B
Explanation: Mitochondria generate most of the cell's ATP supply.

2. Photosynthesis takes place in animal cells. (True/False)
Answer: False
Explanation: Photosynthesis occurs in chloroplasts of plant cells and algae.

3. Pure water freezes at ______ degrees Celsius under normal pressure.
Answer: 0

4. Describe Newton's Third Law of Motion and give one everyday example.
Answer: For every action, there is an equal and opposite reaction. Example: When jumping off a small boat, your feet push the boat backward while propelling you forward.
''';

  static const sampleAnswerKey = '''
1. B
2. False
3. 0
4. For every action, there is an equal and opposite reaction.
''';

  /// Parses a complete exam script containing questions (and optional embedded answers).
  static List<ParsedQuestion> parse(String script, {String? answerKeyScript}) {
    if (script.trim().isEmpty) return [];

    final rawBlocks = _splitIntoBlocks(script);
    final questions = <ParsedQuestion>[];

    for (final block in rawBlocks) {
      if (block.trim().isEmpty) continue;
      final parsed = _parseSingleBlock(block);
      if (parsed != null) {
        questions.add(parsed);
      }
    }

    if (answerKeyScript != null && answerKeyScript.trim().isNotEmpty) {
      return mergeAnswerKey(questions, answerKeyScript);
    }

    return questions;
  }

  /// Splits script into question blocks using question numbering or double newlines.
  static List<String> _splitIntoBlocks(String text) {
    final lines = text.split('\n');
    final blocks = <String>[];
    StringBuffer currentBlock = StringBuffer();

    final questionStartPattern = RegExp(
      r'^\s*(?:Q(?:uestion)?\s*\d+[\s:.)-]|(?:\d+)[\s:.)-])\s*',
      caseSensitive: false,
    );

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trim();

      if (trimmed.isEmpty) {
        // If block already has content, look ahead to see if next non-empty line starts a question
        if (currentBlock.isNotEmpty) {
          int nextIndex = i + 1;
          while (nextIndex < lines.length && lines[nextIndex].trim().isEmpty) {
            nextIndex++;
          }
          if (nextIndex < lines.length && questionStartPattern.hasMatch(lines[nextIndex])) {
            blocks.add(currentBlock.toString().trim());
            currentBlock = StringBuffer();
            continue;
          }
        }
      }

      if (questionStartPattern.hasMatch(line) && currentBlock.isNotEmpty) {
        blocks.add(currentBlock.toString().trim());
        currentBlock = StringBuffer();
      }

      currentBlock.writeln(line);
    }

    if (currentBlock.isNotEmpty && currentBlock.toString().trim().isNotEmpty) {
      blocks.add(currentBlock.toString().trim());
    }

    return blocks;
  }

  /// Parses a single question block and determines its type automatically.
  static ParsedQuestion? _parseSingleBlock(String block) {
    final lines = block
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.isEmpty) return null;

    // 1. Extract Diagram / Image URL if present
    String? imageUrl;
    final imageRegex = RegExp(r'\[(?:diagram|image|img):\s*([^\]]+)\]', caseSensitive: false);
    for (int i = 0; i < lines.length; i++) {
      final m = imageRegex.firstMatch(lines[i]);
      if (m != null) {
        imageUrl = m.group(1)?.trim();
        lines[i] = lines[i].replaceAll(imageRegex, '').trim();
      }
    }

    // 2. Extract Answer and Explanation lines
    String? explicitAnswer;
    String? explicitExplanation;

    final answerRegex = RegExp(r'^(?:Answer|Ans|Key|Correct Answer):\s*(.*)$', caseSensitive: false);
    final explanationRegex = RegExp(r'^(?:Explanation|Reason|Note):\s*(.*)$', caseSensitive: false);

    final contentLines = <String>[];
    for (final line in lines) {
      final ansMatch = answerRegex.firstMatch(line);
      final expMatch = explanationRegex.firstMatch(line);

      if (ansMatch != null) {
        explicitAnswer = ansMatch.group(1)?.trim();
      } else if (expMatch != null) {
        explicitExplanation = expMatch.group(1)?.trim();
      } else {
        contentLines.add(line);
      }
    }

    if (contentLines.isEmpty) return null;

    // 3. Clean Question Header (e.g. "1. ", "Q1: ", "1) ")
    final headerRegex = RegExp(
      r'^(?:Q(?:uestion)?\s*\d+[\s:.)-]|(?:\d+)[\s:.)-])\s*',
      caseSensitive: false,
    );
    String questionLine = contentLines.first.replaceFirst(headerRegex, '').trim();

    // 4. Check for Multiple Choice Options in remaining content lines
    final optionRegex = RegExp(r'^\s*(\*?)\s*(?:\(?([A-Da-d])[\).\]:]|\[([A-Da-d])\])\s*(.*)$');
    final extractedOptions = <Map<String, dynamic>>[];
    final questionBodyLines = <String>[questionLine];

    bool readingOptions = false;
    for (int i = 1; i < contentLines.length; i++) {
      final line = contentLines[i];
      final optMatch = optionRegex.firstMatch(line);

      if (optMatch != null) {
        readingOptions = true;
        final isMarkedWithAsterisk = optMatch.group(1)?.contains('*') == true;
        final letter = (optMatch.group(2) ?? optMatch.group(3) ?? 'A').toLowerCase();
        final text = (optMatch.group(4) ?? '').trim();

        extractedOptions.add({
          'id': letter,
          'text': text,
          'is_marked': isMarkedWithAsterisk,
        });
      } else if (!readingOptions) {
        questionBodyLines.add(line);
      } else {
        // Line continuation of previous option
        if (extractedOptions.isNotEmpty) {
          final lastOpt = extractedOptions.last;
          lastOpt['text'] = '${lastOpt['text']} $line'.trim();
        }
      }
    }

    final fullQuestionText = questionBodyLines.join(' ').trim();

    // 5. CLASSIFY QUESTION TYPE:

    // A. TRUE / FALSE
    final tfIndicatorPattern = RegExp(r'(\(True\s*\/\s*False\)|\(T\s*\/\s*F\)|\[True\s*\/\s*False\]|\[T\s*\/\s*F\]|True\s+or\s+False:?)', caseSensitive: false);
    final isTrueFalseIndicator = tfIndicatorPattern.hasMatch(fullQuestionText);
    final isTwoOptionsTF = extractedOptions.length == 2 &&
        extractedOptions.any((o) => (o['text'] as String).toLowerCase().startsWith('true')) &&
        extractedOptions.any((o) => (o['text'] as String).toLowerCase().startsWith('false'));

    if (isTrueFalseIndicator || isTwoOptionsTF || _isTrueFalseAnswer(explicitAnswer)) {
      final cleanQText = fullQuestionText.replaceAll(tfIndicatorPattern, '').trim();
      final bool? isAnsTrue = _parseBoolAnswer(explicitAnswer);

      return ParsedQuestion(
        text: cleanQText,
        type: 'true_false',
        options: [
          {'id': 'a', 'text': 'True', 'is_correct': isAnsTrue == true},
          {'id': 'b', 'text': 'False', 'is_correct': isAnsTrue == false},
        ],
        correctAnswer: isAnsTrue != null ? (isAnsTrue ? 'True' : 'False') : null,
        explanation: explicitExplanation,
        imageUrl: imageUrl,
      );
    }

    // B. MULTIPLE CHOICE (Choose)
    if (extractedOptions.length >= 2) {
      String? correctId;
      if (explicitAnswer != null && explicitAnswer.isNotEmpty) {
        final firstChar = explicitAnswer.trim()[0].toLowerCase();
        if (RegExp(r'^[a-d]$').hasMatch(firstChar)) {
          correctId = firstChar;
        } else {
          // Check if explicitAnswer matches full text of an option
          final match = extractedOptions.firstWhere(
            (o) => (o['text'] as String).toLowerCase() == explicitAnswer!.toLowerCase(),
            orElse: () => {},
          );
          if (match.isNotEmpty) correctId = match['id'] as String;
        }
      }

      final finalizedOptions = extractedOptions.map((o) {
        final id = o['id'] as String;
        final isMarked = o['is_marked'] == true;
        final isCorrect = (correctId != null && id == correctId) || (correctId == null && isMarked);
        return {
          'id': id,
          'text': o['text'],
          'is_correct': isCorrect,
        };
      }).toList();

      return ParsedQuestion(
        text: fullQuestionText,
        type: 'multiple_choice',
        options: finalizedOptions,
        correctAnswer: correctId,
        explanation: explicitExplanation,
        imageUrl: imageUrl,
      );
    }

    // C. BLANK SPACE (Fill in the Blank)
    final blankPattern = RegExp(r'_{2,}|\[blank\]|\(\.\.\.\)|\.\.\.{2,}', caseSensitive: false);
    if (blankPattern.hasMatch(fullQuestionText) ||
        (explicitAnswer != null && explicitAnswer.split(' ').length <= 4 && !fullQuestionText.toLowerCase().startsWith('describe'))) {
      return ParsedQuestion(
        text: fullQuestionText,
        type: 'fill_in_blank',
        options: const [],
        correctAnswer: explicitAnswer,
        explanation: explicitExplanation,
        imageUrl: imageUrl,
      );
    }

    // D. DESCRIPTION / SHORT ANSWER / ESSAY
    return ParsedQuestion(
      text: fullQuestionText,
      type: 'short_answer',
      options: const [],
      correctAnswer: explicitAnswer ?? 'Teacher manual evaluation',
      explanation: explicitExplanation,
      imageUrl: imageUrl,
    );
  }

  /// Merges a separate answer key script into a list of parsed questions.
  static List<ParsedQuestion> mergeAnswerKey(
    List<ParsedQuestion> questions,
    String answerKeyScript,
  ) {
    final lines = answerKeyScript
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    final keyMap = <int, String>{};
    final keyPattern = RegExp(r'^\s*(?:Q(?:uestion)?\s*)?(\d+)[\s:.)-]+(.*)$', caseSensitive: false);

    int sequentialIndex = 0;
    for (final line in lines) {
      final m = keyPattern.firstMatch(line);
      if (m != null) {
        final qNum = int.tryParse(m.group(1) ?? '') ?? (sequentialIndex + 1);
        final ansVal = (m.group(2) ?? '').trim();
        keyMap[qNum - 1] = ansVal;
      } else {
        keyMap[sequentialIndex] = line.trim();
      }
      sequentialIndex++;
    }

    final updated = <ParsedQuestion>[];
    for (int i = 0; i < questions.length; i++) {
      final q = questions[i];
      final key = keyMap[i] ?? keyMap[i + 1];

      if (key == null || key.isEmpty) {
        updated.add(q);
        continue;
      }

      if (q.type == 'multiple_choice') {
        final targetLetter = key.trim()[0].toLowerCase();
        final newOptions = q.options.map((opt) {
          final isMatch = (opt['id'] as String).toLowerCase() == targetLetter ||
              (opt['text'] as String).trim().toLowerCase() == key.trim().toLowerCase();
          return {
            ...opt,
            'is_correct': isMatch,
          };
        }).toList();

        updated.add(ParsedQuestion(
          text: q.text,
          type: q.type,
          options: newOptions,
          correctAnswer: targetLetter,
          explanation: q.explanation,
          imageUrl: q.imageUrl,
          points: q.points,
        ));
      } else if (q.type == 'true_false') {
        final bool? isTrue = _parseBoolAnswer(key);
        final newOptions = [
          {'id': 'a', 'text': 'True', 'is_correct': isTrue == true},
          {'id': 'b', 'text': 'False', 'is_correct': isTrue == false},
        ];
        updated.add(ParsedQuestion(
          text: q.text,
          type: q.type,
          options: newOptions,
          correctAnswer: isTrue != null ? (isTrue ? 'True' : 'False') : key,
          explanation: q.explanation,
          imageUrl: q.imageUrl,
          points: q.points,
        ));
      } else {
        // Blank space or Description
        updated.add(ParsedQuestion(
          text: q.text,
          type: q.type,
          options: q.options,
          correctAnswer: key,
          explanation: q.explanation,
          imageUrl: q.imageUrl,
          points: q.points,
        ));
      }
    }

    return updated;
  }

  static bool _isTrueFalseAnswer(String? ans) {
    if (ans == null) return false;
    final lower = ans.trim().toLowerCase();
    return lower == 'true' || lower == 'false' || lower == 't' || lower == 'f';
  }

  static bool? _parseBoolAnswer(String? ans) {
    if (ans == null) return null;
    final lower = ans.trim().toLowerCase();
    if (lower == 'true' || lower == 't') return true;
    if (lower == 'false' || lower == 'f') return false;
    return null;
  }
}
