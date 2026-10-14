import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'providers/whatsapp_viewer_provider.dart';
import 'screens/whatsapp_home_screen.dart';
import 'theme/whatsapp_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: WhatsAppTheme.darkSurface,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => WhatsAppViewerProvider()),
      ],
      child: const WhatsAppViewerApp(),
    ),
  );
}

class WhatsAppViewerApp extends StatelessWidget {
  const WhatsAppViewerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WhatsApp Chat Viewer',
      debugShowCheckedModeBanner: false,
      theme: WhatsAppTheme.darkTheme,
      home: const WhatsAppHomeScreen(),
    );
  }
}
