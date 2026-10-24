import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:quiz_app/core/router/app_router.dart';
import 'package:quiz_app/core/theme/theme_mode_provider.dart';
import 'package:quiz_app/shared/widgets/screen_protection_gate.dart';

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);

    final lightBase = ThemeData.light().textTheme;
    final darkBase = ThemeData.dark().textTheme;

    final lightTextTheme = GoogleFonts.poppinsTextTheme(lightBase).copyWith(
      displayLarge: GoogleFonts.poppins(
        textStyle: lightBase.displayLarge,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.0,
      ),
      displayMedium: GoogleFonts.poppins(
        textStyle: lightBase.displayMedium,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.8,
      ),
      displaySmall: GoogleFonts.poppins(
        textStyle: lightBase.displaySmall,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.6,
      ),
      headlineLarge: GoogleFonts.poppins(
        textStyle: lightBase.headlineLarge,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
      headlineMedium: GoogleFonts.poppins(
        textStyle: lightBase.headlineMedium,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.4,
      ),
      headlineSmall: GoogleFonts.poppins(
        textStyle: lightBase.headlineSmall,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
      ),
      titleLarge: GoogleFonts.poppins(
        textStyle: lightBase.titleLarge,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
      titleMedium: GoogleFonts.poppins(
        textStyle: lightBase.titleMedium,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
      ),
      titleSmall: GoogleFonts.poppins(
        textStyle: lightBase.titleSmall,
        fontWeight: FontWeight.w500,
      ),
      bodyLarge: GoogleFonts.poppins(
        textStyle: lightBase.bodyLarge,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.1,
      ),
      bodyMedium: GoogleFonts.poppins(
        textStyle: lightBase.bodyMedium,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.15,
      ),
      labelLarge: GoogleFonts.poppins(
        textStyle: lightBase.labelLarge,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
      ),
    );

    final darkTextTheme = GoogleFonts.poppinsTextTheme(darkBase).copyWith(
      displayLarge: GoogleFonts.poppins(
        textStyle: darkBase.displayLarge,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.0,
      ),
      displayMedium: GoogleFonts.poppins(
        textStyle: darkBase.displayMedium,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.8,
      ),
      displaySmall: GoogleFonts.poppins(
        textStyle: darkBase.displaySmall,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.6,
      ),
      headlineLarge: GoogleFonts.poppins(
        textStyle: darkBase.headlineLarge,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
      headlineMedium: GoogleFonts.poppins(
        textStyle: darkBase.headlineMedium,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.4,
      ),
      headlineSmall: GoogleFonts.poppins(
        textStyle: darkBase.headlineSmall,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
      ),
      titleLarge: GoogleFonts.poppins(
        textStyle: darkBase.titleLarge,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
      titleMedium: GoogleFonts.poppins(
        textStyle: darkBase.titleMedium,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
      ),
      titleSmall: GoogleFonts.poppins(
        textStyle: darkBase.titleSmall,
        fontWeight: FontWeight.w500,
      ),
      bodyLarge: GoogleFonts.poppins(
        textStyle: darkBase.bodyLarge,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.1,
      ),
      bodyMedium: GoogleFonts.poppins(
        textStyle: darkBase.bodyMedium,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.15,
      ),
      labelLarge: GoogleFonts.poppins(
        textStyle: darkBase.labelLarge,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
      ),
    );

    return ScreenProtectionGate(
      child: MaterialApp.router(
        title: 'Ciro High Schools Quiz & Learning Portal',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF10B981),
            primary: const Color(0xFF10B981),
            secondary: const Color(0xFF059669),
            surface: Colors.white,
            surfaceContainerHighest: const Color(0xFFF0FDF4),
            surfaceContainerLow: const Color(0xFFF8FAFC),
            brightness: Brightness.light,
          ),
          scaffoldBackgroundColor: const Color(0xFFF8FAFC),
          cardTheme: CardThemeData(
            color: Colors.white,
            elevation: 0,
            shadowColor: const Color(0x08000000),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: Color(0xFFE2E8F0), width: 1.2),
            ),
          ),
          appBarTheme: AppBarTheme(
            backgroundColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            foregroundColor: const Color(0xFF0F172A),
            titleTextStyle: GoogleFonts.poppins(
              textStyle: lightBase.titleLarge,
              color: const Color(0xFF0F172A),
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            labelStyle: GoogleFonts.poppins(
              textStyle: lightBase.bodyMedium,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF64748B),
            ),
            hintStyle: GoogleFonts.poppins(
              textStyle: lightBase.bodyMedium,
              fontSize: 13,
              color: const Color(0xFF94A3B8),
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 1.2),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 1.2),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(
                color: Color(0xFF10B981),
                width: 2.0,
              ),
            ),
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 50),
              textStyle: GoogleFonts.poppins(
                textStyle: lightBase.labelLarge,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          outlinedButtonTheme: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 48),
              side: const BorderSide(color: Color(0xFFCBD5E1), width: 1.2),
              textStyle: GoogleFonts.poppins(
                textStyle: lightBase.labelLarge,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          textTheme: lightTextTheme,
        ),
        darkTheme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF10B981),
            brightness: Brightness.dark,
          ),
          cardTheme: CardThemeData(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          textTheme: darkTextTheme,
        ),
        themeMode: themeMode,
        routerConfig: router,
      ),
    );
  }
}
