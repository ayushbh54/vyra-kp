import 'package:flutter/material.dart';

/// Authentic WhatsApp Design System & Palette
/// Replicates WhatsApp's signature dark and light interfaces with exact color values and typography.
class WhatsAppTheme {
  // Dark Mode Palette (WhatsApp Standard Dark Theme)
  static const Color darkBackground = Color(0xFF121B22); // Main scaffold background
  static const Color darkSurface = Color(0xFF1F2C34);    // App bar, cards, bottom bar
  static const Color darkTealGreen = Color(0xFF00A884);  // Accent teal green (active tabs, FAB, badges)
  static const Color darkIncomingBubble = Color(0xFF202C33); // Incoming message bubble
  static const Color darkOutgoingBubble = Color(0xFF005D4B); // Outgoing message bubble
  static const Color darkTextPrimary = Color(0xFFE9EDEF);    // High contrast title text
  static const Color darkTextSecondary = Color(0xFF8696A0);  // Muted timestamps, subtitles
  static const Color darkDivider = Color(0xFF222D34);        // Separators between chat rows
  static const Color darkBlueTicks = Color(0xFF53BDEB);      // Read receipt double checkmarks
  static const Color darkDeletedBadge = Color(0xFFDC2626);   // Red warning tag for deleted messages
  static const Color darkDeletedCard = Color(0xFF2D1515);    // Soft reddish background for deleted bubble

  // Convenience Aliases
  static const Color scaffoldBg = darkBackground;
  static const Color appBarBg = darkSurface;
  static const Color primaryGreen = darkTealGreen;
  static const Color textPrimary = darkTextPrimary;
  static const Color textSecondary = darkTextSecondary;
  static const Color dividerColor = darkDivider;
  static const Color blueTick = darkBlueTicks;
  static const Color deletedColor = darkDeletedBadge;
  static const Color cardBg = darkSurface;
  static const Color accentBlue = Color(0xFF3B82F6);

  // Light Mode Palette
  static const Color lightHeaderGreen = Color(0xFF008069);
  static const Color lightBackground = Color(0xFFEFEAE2);
  static const Color lightIncomingBubble = Color(0xFFFFFFFF);
  static const Color lightOutgoingBubble = Color(0xFFE7FFDB);

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: darkBackground,
      colorScheme: const ColorScheme.dark(
        primary: darkTealGreen,
        secondary: darkTealGreen,
        surface: darkSurface,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: darkSurface,
        elevation: 0,
        iconTheme: IconThemeData(color: darkTextSecondary),
        titleTextStyle: TextStyle(
          color: darkTextSecondary,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: darkTealGreen,
        unselectedLabelColor: darkTextSecondary,
        indicatorColor: darkTealGreen,
        labelStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 0.5),
        unselectedLabelStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: darkTealGreen,
        foregroundColor: Colors.white,
        elevation: 4,
      ),
    );
  }
}
