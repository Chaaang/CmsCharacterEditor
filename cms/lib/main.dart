import 'package:flutter/material.dart';
import 'pages/name_page.dart';
import 'pages/character_select_page.dart';
import 'pages/photo_page.dart';
import 'pages/editor_page.dart';
import 'pages/qr_page.dart';
import 'state/models.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Character Maker',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case CharacterSelectPage.routeName:
            final name = settings.arguments as String? ?? '';
            return MaterialPageRoute(
              builder: (_) => CharacterSelectPage(userName: name),
            );
          case PhotoPage.routeName:
            final args = settings.arguments as CharacterDesign;
            return MaterialPageRoute(
              builder: (_) => PhotoPage(design: args),
            );
          case EditorPage.routeName:
            final args = settings.arguments as CharacterDesign;
            return MaterialPageRoute(
              builder: (_) => EditorPage(design: args),
            );
          case QRPage.routeName:
            final url = settings.arguments as String;
            return MaterialPageRoute(
              builder: (_) => QRPage(url: url),
            );
          case '/':
          default:
            return MaterialPageRoute(builder: (_) => const NamePage());
        }
      },
    );
  }
}
