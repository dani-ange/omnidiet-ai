import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 🌟 IMPORT ALL ROUTE TARGETS CLEANLY
import 'services/nutrition_database.dart';
import 'screens/landing_screen.dart';
import 'screens/model_download_screen.dart';
import 'screens/home_screen.dart';

void main() async {
  // 1. Ensure Flutter binding loops are initialized for background IO tasks
  WidgetsFlutterBinding.ensureInitialized();

  // 2. Initialize and pre-load your unified local HD4A nutrition database into RAM
  final db = NutritionDatabase();
  await db.init();

  // 3. Open SharedPreferences to check user configuration state parameters
  final prefs = await SharedPreferences.getInstance();
  final String userName = prefs.getString('prof_name') ?? "User";
  
  // Look for a custom onboarding tracking flag (defaults to true if key is absent)
  final bool isFirstTime = prefs.getBool('is_first_time') ?? true;

  // 4. Check for the local 2.4 GB LiteRT LLM file presence and size integrity on device
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
    debugPrint("Startup system diagnostics engine pass failed: $e");
  }

  // 5. 🚦 THE ROUTING GATEWAY CORE
  Widget initialScreen;

  if (isFirstTime) {
    // Stage A: Completely brand new install -> Onboarding Presentation
    initialScreen = const LandingScreen();
  } else if (!isModelReady) {
    // Stage B: Profile built via landing, but 2.4 GB engine files are missing
    initialScreen = const ModelDownloadScreen();
  } else {
    // Stage C: Fully operational returning user -> Main App Dashboard
    initialScreen = HomeScreen(userName: userName);
  }

  // 6. Run the application with the dynamically calculated entry path
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