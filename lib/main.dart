import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // 🌟 Required for MethodChannel
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/nutrition_database.dart';
import 'screens/landing_screen.dart';
import 'screens/model_download_screen.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize and pre-load your local database asset index into RAM
  final db = NutritionDatabase();
  await db.init();

  final prefs = await SharedPreferences.getInstance();
  final String userName = prefs.getString('prof_name') ?? "User";
  final bool isFirstTime = prefs.getBool('is_first_time') ?? true;

  bool isModelReady = false;
  try {
    final Directory documentsDir = await getApplicationDocumentsDirectory();
    final String rootAppDir = documentsDir.parent.path;
    final String targetModelPath = '$rootAppDir/files/gemma-4-E2B-it.litertlm';
    final File modelFile = File(targetModelPath);

    if (modelFile.existsSync() && modelFile.lengthSync() == 2583085056) {
      isModelReady = true;
    }
  } catch (e) {
    debugPrint("Startup diagnostics failed: $e");
  }

  // 🌟 GLOBAL INITIALIZATION: Wakes up the local model instantly during boot sequence
  if (!isFirstTime && isModelReady) {
    try {
      const bootPlatform = MethodChannel('com.ai.litertlm/chat');
      final response = await bootPlatform.invokeMethod('initModel');
      debugPrint("🚀 Global Boot Engine Activation: $response");
    } catch (e) {
      debugPrint("💥 Global Boot Engine Activation Failed: $e");
    }
  }

  Widget initialScreen;
  if (isFirstTime) {
    initialScreen = const LandingScreen();
  } else if (!isModelReady) {
    initialScreen = const ModelDownloadScreen();
  } else {
    initialScreen = HomeScreen(userName: userName);
  }

  runApp(MyApp(initialScreen: initialScreen));
}

class MyApp extends StatelessWidget {
  final Widget initialScreen;
  const MyApp({super.key, required this.initialScreen});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OmniDiet AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F766E)),
        useMaterial3: true,
      ),
      home: initialScreen,
    );
  }
}