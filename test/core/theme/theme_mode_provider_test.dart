import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/core/theme/theme_mode_provider.dart';

void main() {
  test('theme cycles through system, dark, and light modes', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(themeModeProvider), ThemeMode.system);
    container.read(themeModeProvider.notifier).cycle();
    expect(container.read(themeModeProvider), ThemeMode.dark);
    container.read(themeModeProvider.notifier).cycle();
    expect(container.read(themeModeProvider), ThemeMode.light);
    container.read(themeModeProvider.notifier).cycle();
    expect(container.read(themeModeProvider), ThemeMode.system);
  });
}
