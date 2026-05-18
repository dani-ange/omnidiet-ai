import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart'; // REQUIRED FOR compute()
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image/image.dart' as img;

import '../widgets/image_marker_painter.dart';
import '../services/nutrition_database.dart'; // 🌟 ADDED DATABASE SERVICE

// ====================================================================
// 🔍 THE BACKGROUND ISOLATE WORKER (Prevents OOM Crashes)
// ====================================================================
Future<List<String?>> _processPlateCropsInBackground(Map<String, dynamic> params) async {
  String imagePath = params['imagePath'];
  List<List<dynamic>> boxes = params['boxes'];
  String tempDirPath = params['tempDir'];

  try {
    final imageFile = File(imagePath);
    img.Image? originalImage = img.decodeImage(imageFile.readAsBytesSync());
    if (originalImage == null) return List.filled(boxes.length, null);

    originalImage = img.bakeOrientation(originalImage);
    List<String?> croppedPaths = [];

    for (int i = 0; i < boxes.length; i++) {
      List<dynamic> box = boxes[i];
      double safeYMin = math.min(box[0].toDouble(), box[2].toDouble());
      double safeYMax = math.max(box[0].toDouble(), box[2].toDouble());
      double safeXMin = math.min(box[1].toDouble(), box[3].toDouble());
      double safeXMax = math.max(box[1].toDouble(), box[3].toDouble());

      int yMin = (safeYMin * originalImage.height).toInt().clamp(0, originalImage.height - 1);
      int xMin = (safeXMin * originalImage.width).toInt().clamp(0, originalImage.width - 1);
      int yMax = (safeYMax * originalImage.height).toInt().clamp(0, originalImage.height);
      int xMax = (safeXMax * originalImage.width).toInt().clamp(0, originalImage.width);

      int width = (xMax - xMin).clamp(1, originalImage.width);
      int height = (yMax - yMin).clamp(1, originalImage.height);

      img.Image croppedImage = img.copyCrop(originalImage, x: xMin, y: yMin, width: width, height: height);
      final croppedPath = '$tempDirPath/plate_crop_${DateTime.now().millisecondsSinceEpoch}_$i.jpg';
      File(croppedPath).writeAsBytesSync(img.encodeJpg(croppedImage));
      croppedPaths.add(croppedPath);
    }
    return croppedPaths;
  } catch (e) {
    return List.filled(boxes.length, null);
  }
}

enum PlateStep { capture, correction, audit }

class PlateAnalyzerScreen extends StatefulWidget {
  const PlateAnalyzerScreen({super.key});

  @override
  State<PlateAnalyzerScreen> createState() => _PlateAnalyzerScreenState();
}

class _PlateAnalyzerScreenState extends State<PlateAnalyzerScreen> {
  static const platform = MethodChannel('com.ai.litertlm/chat');
  static const streamChannel = EventChannel('com.ai.litertlm/stream');

  PlateStep _currentStep = PlateStep.capture;
  final ImagePicker _picker = ImagePicker();
  StreamSubscription? _streamSubscription;

  // State Variables
  String? _stagedImagePath;
  bool _isBusy = false;
  List<Map<String, dynamic>> _plateItems = [];
  String _auditStreamResponse = "";

  // User Profile Data
  String? _patientProfilePrompt;
  String _userLanguage = "English";
  String _userSex = "Not Specified";

  @override
  void initState() {
    super.initState();
    _loadPatientProfile();
  }

  Future<void> _loadPatientProfile() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _patientProfilePrompt = prefs.getString('saved_profile') ?? "No medical restrictions provided.";
      _userLanguage = prefs.getString('prof_language') ?? "English";
      _userSex = prefs.getString('prof_sex') ?? "Not Specified";
    });
  }

  @override
  void dispose() {
    _streamSubscription?.cancel();
    platform.invokeMethod('cancelGeneration');
    super.dispose();
  }

  // ===========================================================================
  // 📸 PHASE 1: THE VISUAL PLATE SCANNER
  // ===========================================================================
  Future<void> _scanPlate(ImageSource source) async {
    final XFile? image = await _picker.pickImage(source: source, maxWidth: 512, maxHeight: 512, imageQuality: 60);
    if (image == null) return;

    setState(() {
      _stagedImagePath = image.path;
      _isBusy = true;
      _currentStep = PlateStep.capture;
    });

    const String visionPrompt = """
    You are an expert clinical vision system analyzing a plate of cooked food.
    Identify every distinct food component on this plate.
    Return ONLY a strict JSON array. No markdown formatting, no conversational text.
    For each item, provide:
    1. "name": Your best guess of the cooked food (e.g., "Jollof Rice", "Fried Plantain").
    2. "box": The bounding box [y_min, x_min, y_max, x_max] as relative floats strictly between 0.00 and 1.00.
    3. "plate_coverage": An estimated integer (1 to 100) representing what percentage of the plate's surface area this item takes up.
    
    Example output:
    [
      {"name": "Garri Fufu", "box": [0.10, 0.05, 0.50, 0.45], "plate_coverage": 60},
      {"name": "Ndole", "box": [0.50, 0.45, 0.90, 0.95], "plate_coverage": 40}
    ]
    """;

    try {
      try { await platform.invokeMethod('cancelGeneration'); } catch (_) {}
      
      final reply = await platform.invokeMethod('generateOnce', {
        'text': visionPrompt,
        'imagePath': image.path,
        'audioPath': null,
      });

      if (reply == null || reply.toString().trim().isEmpty) throw Exception("Engine returned empty data.");

      String cleanJson = reply.toString().trim();
      final match = RegExp(r'\[.*\]', dotAll: true).firstMatch(cleanJson);
      if (match != null) cleanJson = match.group(0)!;

      List<dynamic> parsedList = jsonDecode(cleanJson);
      List<Map<String, dynamic>> rawItems = List<Map<String, dynamic>>.from(parsedList);

      // Sanitize boxes
      for (var item in rawItems) {
        if (item['box'] != null && item['box'] is List) {
          List<dynamic> box = item['box'];
          for (int i = 0; i < box.length; i++) {
            double val = double.tryParse(box[i].toString()) ?? 0.0;
            if (val > 1.0) val = val / 1000.0;
            box[i] = val.clamp(0.0, 1.0);
          }
        }
      }

      // Background Crop
      final directory = await getTemporaryDirectory();
      List<List<dynamic>> boxesToCrop = rawItems.where((i) => i['box'] != null).map((i) => i['box'] as List<dynamic>).toList();
      
      if (boxesToCrop.isNotEmpty) {
        List<String?> croppedPaths = await compute(_processPlateCropsInBackground, {
          'imagePath': image.path,
          'boxes': boxesToCrop,
          'tempDir': directory.path,
        });

        for (int i = 0; i < boxesToCrop.length; i++) {
          rawItems[i]['imagePath'] = croppedPaths[i];
        }
      }

      setState(() {
        _plateItems = rawItems;
        _currentStep = PlateStep.correction;
        _isBusy = false;
      });

    } catch (e) {
      debugPrint("Plate Scan Error: $e");
      setState(() { _isBusy = false; });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Failed to analyze plate. Try again!")));
    }
  }

  // ===========================================================================
  // 🩺 PHASE 3: THE CLINICAL NUTRITION AUDIT (GROUNDED VIA RAG OMNI-SEARCH)
  // ===========================================================================
  Future<void> _runPlateAudit() async {
    setState(() {
      _isBusy = true;
      _currentStep = PlateStep.audit;
      _auditStreamResponse = "";
    });

    // 1. Compile clean string representations of user confirmed plate allocations
    List<String> confirmedDishes = _plateItems.map((item) => item['name'].toString()).toList();
    String mealListString = _plateItems.map((item) => "- ${item['name']} [Takes up ${item['plate_coverage']}% of plate]").join("\n");

    // 🌟 2. THE MASTER OMNI-SEARCH COUPLING
    // Intelligently queries the database, resolving deep constituent metrics for cooked components
    final NutritionDatabase db = NutritionDatabase();
    String comprehensivePlateFacts = db.getAgileFacts(confirmedDishes);

    // 3. Build the structurally bounded context prompt Matrix
    final String auditPrompt = """
    [CLINICAL PLATE AUDITOR MODE]
    Patient Profile: $_patientProfilePrompt


    [VERIFIED DATABASE KNOWLEDGE]
    Use these exact facts to audit the meal. Pay close attention to the constituent ingredient values:
    $comprehensivePlateFacts
    [/VERIFIED DATABASE KNOWLEDGE]

    User's Confirmed Plate (Surface Area Allocation):
    $mealListString

    YOUR MISSION:
    Act as a strict but empathetic clinical dietitian. Evaluate this specific cooked meal against the Patient's medical profile and health goals.
    🛑 CRITICAL SAFETY PROTOCOL (NON-FOOD INGREDIENTS GATEWAY):
    Analyze the user ingredients list input carefully: "$mealListString".
    If the ingredients typed or scanned consist of non-food items, inedible objects, dangerous substances, rocks/stones, sand, petroleum/gasoil, machinery, chemicals, or materials with absolutely NO culinary value in African cuisine, you MUST enforce this backup procedure:
    2. DO NOT make up or hallucinate a recipe utilizing these elements.
    3. Respond directly and friendly in plain text to explain that these elements cannot be digested or cooked. Say it warmly like an empathetic Cameroonian grandmother (e.g., "Ah, my child, we cannot cook with sand and gasoil oh! Please give me real market ingredients like cassava, groundnuts, or tomatoes, and let's prepare something healthy for you.").

    1. THE HEALTH VERDICT: Is this meal safe for their medical conditions? Explain *why* by explicitly pointing to specific constituent ingredients found in the [VERIFIED DATABASE KNOWLEDGE] block (e.g., explaining hidden cholesterol limits because of Red Palm Oil).
    2. THE PORTION AUDIT: Analyze the plate coverage surface area percentages. If the starchy carbohydrate takes up more than 30% of the plate and they have a weight-loss or blood-sugar regulation goal, gently correct them.
    3. ACTIONABLE ADVICE: Do NOT use absolute grams or ounces. Suggest portion adjustments using visual relational sizes (e.g., "Reduce the Fufu to the size of your closed fist", or "Make sure the leafy vegetables cover half the plate").
    
    Stream your response cleanly in Markdown format without conversational fluff wrappers.
    """;

    try {
      await _streamSubscription?.cancel();
      await platform.invokeMethod('startGeneration', {
        'text': auditPrompt,
        'imagePath': null,
        'audioPath': null,
      });

      _streamSubscription = streamChannel.receiveBroadcastStream().listen((dynamic event) {
        final Map<dynamic, dynamic> map = event;
        if (map['type'] == 'token') {
          setState(() { _auditStreamResponse += map['content']; });
        } else if (map['type'] == 'done') {
          setState(() { _isBusy = false; });
        }
      });
    } catch (e) {
      setState(() { _isBusy = false; });
    }
  }

  // ===========================================================================
  // 🧱 VISUAL DECK BUILDERS
  // ===========================================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: const Text('Plate Analyzer', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        flexibleSpace: Container(decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF0F766E), Color(0xFF0EA5E9)]))),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _buildStepCard(step: "1", title: "Scan Your Plate", active: _currentStep == PlateStep.capture, body: _buildCaptureUi()),
            const SizedBox(height: 16),
            _buildStepCard(step: "2", title: "Verify & Correct", active: _currentStep == PlateStep.correction, body: _buildCorrectionUi()),
            const SizedBox(height: 16),
            _buildStepCard(step: "3", title: "Clinical Audit Report", active: _currentStep == PlateStep.audit, body: _buildAuditUi()),
          ],
        ),
      ),
    );
  }

  Widget _buildCaptureUi() {
    return Column(
      children: [
        if (_stagedImagePath != null && File(_stagedImagePath!).existsSync())
          Container(
            height: 250,
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12)),
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.file(File(_stagedImagePath!), fit: BoxFit.cover)),
                if (_plateItems.isNotEmpty)
                  CustomPaint(painter: ImageMarkerPainter(_plateItems.map((e) => {'box_2d': e['box'], 'label': '${e['plate_coverage']}%'}).toList())),
              ],
            ),
          ),
        if (_isBusy && _currentStep == PlateStep.capture)
          const Padding(padding: EdgeInsets.all(16.0), child: CircularProgressIndicator(color: Color(0xFF0F766E)))
        else
          Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton.icon(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F766E), foregroundColor: Colors.white), onPressed: () => _scanPlate(ImageSource.camera), icon: const Icon(Icons.camera_alt), label: const Text("Camera")),
              ElevatedButton.icon(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0EA5E9), foregroundColor: Colors.white), onPressed: () => _scanPlate(ImageSource.gallery), icon: const Icon(Icons.photo_library), label: const Text("Gallery")),
            ],
          ),
      ],
    );
  }

  Widget _buildCorrectionUi() {
    if (_plateItems.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        const Text("Gemma has estimated your plate. Tap any text box to correct the food name or percentage before auditing!", style: TextStyle(color: Colors.blueGrey, fontSize: 13, height: 1.4)),
        const SizedBox(height: 16),
        ..._plateItems.asMap().entries.map((entry) {
          int index = entry.key;
          Map<String, dynamic> item = entry.value;
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.teal.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.teal.shade100)),
            child: Row(
              children: [
                if (item['imagePath'] != null && File(item['imagePath']).existsSync())
                  ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.file(File(item['imagePath']), width: 60, height: 60, fit: BoxFit.cover))
                else
                  Container(width: 60, height: 60, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.fastfood, color: Colors.white)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    children: [
                      TextFormField(
                        initialValue: item['name'],
                        decoration: const InputDecoration(labelText: "Food Name", isDense: true),
                        onChanged: (val) => _plateItems[index]['name'] = val,
                      ),
                      TextFormField(
                        initialValue: item['plate_coverage'].toString(),
                        decoration: const InputDecoration(labelText: "% of Plate", isDense: true, suffixText: "%"),
                        keyboardType: TextInputType.number,
                        onChanged: (val) => _plateItems[index]['plate_coverage'] = int.tryParse(val) ?? item['plate_coverage'],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F766E), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            onPressed: _runPlateAudit,
            icon: const Icon(Icons.health_and_safety),
            label: const Text("Confirm & Audit Plate", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }

  Widget _buildAuditUi() {
    if (_auditStreamResponse.isEmpty) return const Center(child: Padding(padding: EdgeInsets.all(16.0), child: CircularProgressIndicator(color: Color(0xFF0F766E))));
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF0F766E).withOpacity(0.3))),
      child: MarkdownBody(data: _auditStreamResponse, styleSheet: MarkdownStyleSheet(p: const TextStyle(fontSize: 15, color: Color(0xFF334155), height: 1.5))),
    );
  }

  Widget _buildStepCard({required String step, required String title, required bool active, required Widget body}) {
    final int currentIdx = _currentStep.index;
    final int stepIdx = int.parse(step) - 1;
    final bool revealed = active || currentIdx > stepIdx;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 250),
      opacity: revealed ? 1.0 : 0.4,
      child: Card(
        color: Colors.white,
        elevation: active ? 4 : 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: active ? const Color(0xFF0F766E) : Colors.transparent, width: 1.5)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(radius: 12, backgroundColor: active ? const Color(0xFF0F766E) : Colors.grey, child: Text(step, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold))),
                  const SizedBox(width: 10),
                  Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: active ? const Color(0xFF0F766E) : Colors.black87)),
                ],
              ),
              if (revealed) ...[const Divider(height: 24), body]
            ],
          ),
        ),
      ),
    );
  }
}