import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'providers/parent_dashboard_provider.dart';
import 'screens/main_navigation_shell.dart';

import 'services/system_notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await SystemNotificationService.instance.initialize();
  } catch (e) {
    debugPrint('SystemNotificationService init suppressed: $e');
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
        builder: (context, child) {
          final mediaQuery = MediaQuery.of(context);
          return MediaQuery(
            data: mediaQuery.copyWith(
              // Clamps text scaler to prevent UI overflow on large font accessibility settings
              textScaler: mediaQuery.textScaler.clamp(
                minScaleFactor: 0.85,
                maxScaleFactor: 1.15,
              ),
            ),
            child: child ?? const SizedBox.shrink(),
          );
        },
        home: const MainNavigationShell(),
      ),
    );
  }
}
