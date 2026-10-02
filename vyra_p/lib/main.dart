import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'providers/parent_dashboard_provider.dart';
import 'screens/main_navigation_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint("Firebase initialization note: $e (using local reactive state)");
  }
  runApp(const VyraParentApp());
}

class VyraParentApp extends StatelessWidget {
  const VyraParentApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ParentDashboardProvider()),
      ],
      child: MaterialApp(
        title: 'Vyra Parent Control',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: const Color(0xFF0F172A),
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF38BDF8),
            secondary: Color(0xFF10B981),
            surface: Color(0xFF1E293B),
          ),
          textTheme: GoogleFonts.interTextTheme(
            ThemeData(brightness: Brightness.dark).textTheme,
          ),
          useMaterial3: true,
        ),
        home: const MainNavigationShell(),
      ),
    );
  }
}
