import 'package:flutter/material.dart';

import 'brand.dart';
import 'state/console_controller.dart';
import 'theme/alpaca_theme.dart';
import 'ui/console_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const VideoRunApp());
}

class VideoRunApp extends StatefulWidget {
  const VideoRunApp({super.key});

  @override
  State<VideoRunApp> createState() => _VideoRunAppState();
}

class _VideoRunAppState extends State<VideoRunApp> {
  late final ConsoleController _controller = ConsoleController()..boot();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: appName,
      debugShowCheckedModeBanner: false,
      theme: AlpacaTheme.dark(),
      home: ConsolePage(controller: _controller),
    );
  }
}
