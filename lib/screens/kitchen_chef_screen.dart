import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart'; 

// 🌟 HOOKING DIRECTLY TO YOUR APP DATA PACKS
import '../models/chat_message.dart';
import '../services/nutrition_database.dart';
import '../widgets/unified_ingredient_cart.dart';
import '../widgets/image_marker_painter.dart'; 

class KitchenChefScreen extends StatefulWidget {
  const KitchenChefScreen({super.key});

  @override
  State<KitchenChefScreen> createState() => _KitchenChefScreenState();
}

enum ChefStep { inputStaging, verificationCart, parameterForms, completeReveal }

class _KitchenChefScreenState extends State<KitchenChefScreen> {
  static const platform = MethodChannel('com.ai.litertlm/chat');
  static const streamChannel = EventChannel('com.ai.litertlm/stream');
  String? _patientProfilePrompt; 

  @override
  void initState() {
    super.initState();
    _loadPatientProfile(); 
  }

  Future<void> _loadPatientProfile() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _patientProfilePrompt = prefs.getString('saved_profile') ?? "No specific dietary restrictions.";
    });
  }
  
  ChefStep _currentStep = ChefStep.inputStaging;
  StreamSubscription? _streamSubscription;
  final TextEditingController _textController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  // Workflow Core Staging Variables
  String? _stagedImagePath;
  List<Map<String, dynamic>> _unifiedCartItems = [];
  List<Map<String, dynamic>> _rawDetectedItemsWithBoxes = []; 
  String _chefNarrativeStreamResponse = "";
  bool _isEngineBusy = false;

  // Step 3 Selections
  String _selectedScale = "Household Family Meal"; 
  String _selectedScope = "Single Meal"; 
  String _selectedTarget = "Dinner";

  @override
  void dispose() {
    _streamSubscription?.cancel();
    _textController.dispose();
    platform.invokeMethod('cancelGeneration'); 
    super.dispose();
  }

  // ===========================================================================
  // 📸 UTILITY 1: STRICT JSON VISION EXTRACTION
  // ===========================================================================
  Future<List<Map<String, dynamic>>?> _getIngredientsFromGemma(String imagePath) async {
    String prompt = """
    You are an expert culinary vision system. Identify every distinct raw ingredient in this image.
    Return ONLY a strict JSON array. No markdown formatting, no backticks, and no conversational text.
    For each item, provide:
    1. "name": Your best guess of the ingredient name.
    2. "box": The bounding box [y_min, x_min, y_max, x_max] as relative floats strictly between 0.00 and 1.00. 
    CRITICAL: y_max MUST be greater than y_min. x_max MUST be greater than x_min.
    3. "confidence": "high" if certain, or "low" if unsure.
    
    Example output:
    [
      {"name": "Tomato", "box": [0.10, 0.05, 0.30, 0.25], "confidence": "high"}
    ]""";

    try {
      try {
        await platform.invokeMethod('cancelGeneration');
        await _streamSubscription?.cancel();
      } catch (_) {}

      final reply = await platform.invokeMethod('generateOnce', {
        'text': prompt,
        'imagePath': imagePath,
        'audioPath': null,
      });

      if (reply == null || reply.toString().trim().isEmpty) return null;
      
      String cleanJson = reply.toString().trim();
      
      final match = RegExp(r'\[.*\]', dotAll: true).firstMatch(cleanJson);
      if (match != null) {
        cleanJson = match.group(0)!;
      } else {
        cleanJson = cleanJson.replaceAll('```json', '').replaceAll('```', '').trim();
      }

      List<dynamic> parsedList = jsonDecode(cleanJson);
      return List<Map<String, dynamic>>.from(parsedList);
    } catch (e) {
      debugPrint("❌ JSON Vision Parse Error: $e");
      return null;
    }
  }

  // ===========================================================================
  // ✂️ UTILITY 2: IMAGE CROPPING MECHANICS
  // ===========================================================================
  Future<String?> _cropConfusingIngredient(String originalImagePath, List<dynamic> box) async {
    try {
      final imageFile = File(originalImagePath);
      img.Image? originalImage = img.decodeImage(imageFile.readAsBytesSync());
      if (originalImage == null) return null;

      originalImage = img.bakeOrientation(originalImage);

      double safeYMin = math.min(box[0].toDouble(), box[2].toDouble());
      double safeYMax = math.max(box[0].toDouble(), box[2].toDouble());
      double safeXMin = math.min(box[1].toDouble(), box[3].toDouble());
      double safeXMax = math.max(box[1].toDouble(), box[3].toDouble());

      int yMin = (safeYMin * originalImage.height).toInt().clamp(0, originalImage.height - 1);
      int xMin = (safeXMin * originalImage.width).toInt().clamp(0, originalImage.width - 1);
      int yMax = (safeYMax * originalImage.height).toInt().clamp(0, originalImage.height);
      int xMax = (safeXMax * originalImage.width).toInt().clamp(0, originalImage.width);

      img.Image croppedImage = img.copyCrop(originalImage, x: xMin, y: yMin, width: (xMax - xMin).clamp(1, originalImage.width), height: (yMax - yMin).clamp(1, originalImage.height));

      final directory = await getTemporaryDirectory();
      final croppedPath = '${directory.path}/chef_crop_${DateTime.now().millisecondsSinceEpoch}.jpg';
      File(croppedPath).writeAsBytesSync(img.encodeJpg(croppedImage));

      return croppedPath;
    } catch (e) {
      return null;
    }
  }

  // ===========================================================================
  // 🚀 PIPELINE LIFECYCLES
  // ===========================================================================
  Future<void> _processImageInput(ImageSource source) async {
    final XFile? image = await _picker.pickImage(source: source, maxWidth: 512, maxHeight: 512, imageQuality: 50);
    if (image == null) return;

    setState(() {
      _stagedImagePath = image.path;
      _isEngineBusy = true;
    });

    try {
      List<Map<String, dynamic>>? rawItems = await _getIngredientsFromGemma(image.path);

      if (rawItems == null || rawItems.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Could not resolve ingredients clearly. Try a better angle!")));
        setState(() { _isEngineBusy = false; });
        return;
      }

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

      for (var item in rawItems) {
        if (item['box'] != null) {
          item['imagePath'] = await _cropConfusingIngredient(image.path, item['box']);
        }
      }

      setState(() {
        _rawDetectedItemsWithBoxes = rawItems;
        _unifiedCartItems = rawItems;
        _currentStep = ChefStep.verificationCart; 
        _isEngineBusy = false;
      });
      
    } catch (e) {
      debugPrint("Image Pipeline Crash: $e");
      setState(() { _isEngineBusy = false; });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  void _processTextInput() {
    if (_textController.text.trim().isEmpty) return;
    List<String> items = _textController.text.split(',');
    setState(() {
      _unifiedCartItems = items.map<Map<String, dynamic>>((e) => {
        'name': e.trim(), 
        'confidence': 'high',
        'box': null,
        'imagePath': null
      }).toList();
      _currentStep = ChefStep.verificationCart;
    });
  }

  void _executeFinalChefStream(String confirmedCsvList) async {
    setState(() {
      _isEngineBusy = true;
      _currentStep = ChefStep.completeReveal;
      _chefNarrativeStreamResponse = "";
    });

    List<String> verifiedIngredients = confirmedCsvList
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final NutritionDatabase db = NutritionDatabase();
    String comprehensiveDatabaseFacts = db.getAgileFacts(verifiedIngredients);

    String scaleText = "Single portion preparation strategy.";
    if (_selectedScale == "Household Family Meal") {
      scaleText = "Communal shared meal strategy. Advise user on safe personal limits from the main dish.";
    }

    String scopePrompt = "Target Window: $_selectedTarget. Create a single recipe card.";
    if (_selectedScope == "Full 1-Day Plan") {
      scopePrompt = "Create a 1-Day Meal Plan (Breakfast, Lunch, Snack, Dinner) using separate sequential recipe cards.";
    } else if (_selectedScope == "Full 7-Day Plan") {
      scopePrompt = "Create a 7-Day Menu Plan grouped sequentially by days.";
    }

    // 🌟 HIGH-OPTIMIZATION GLOBAL PROMPT ARCHITECTURE (40% SHORTER, DETERMINISTIC, NO THEATRE)
    final String finalChefPrompt = """
Persona: You are OmniDiet Chef. You help users create healthier, culturally fluid global meals based on available ingredients and health targets.
Style: Concise, practical, friendly. Keep explanations under 2 sentences. Avoid repetition.

Inputs:
- Ingredients: $confirmedCsvList
- Meal Scope: $_selectedScope ($scopePrompt)
- Scale: $_selectedScale ($scaleText)

[NUTRITION FACTS]
Use these facts for absolute calculation accuracy. If an ingredient is missing from this database list, use your internal global memory to determine its parameters:
$comprehensiveDatabaseFacts

[USER HEALTH PROFILE]
$_patientProfilePrompt

Safety Filter:
If ingredients contain non-food items, dangerous chemicals, or objects with no global culinary value (e.g., sand, rocks, gasoil, petroleum), you must:
1. Do not generate recipe cards.
2. Explain politely in plain text that these items are not edible.
3. Ask the user for real food ingredients.

Output Requirements:
1. Write a 2-sentence friendly health intro matching the user profile before any recipe cards.
2. Every recipe card must use this exact format structure:

[RECIPE_START]
[TITLE] Recipe Name
[INGREDIENTS]
- Item (Custom portion scaled to health constraints)
[STEPS]
1. Preparation step instruction.
2. Cooking step instruction.
[RECIPE_END]

3. Finish with a short health summary block at the end. Stream output text directly:""";

    try {
      await _streamSubscription?.cancel();
      _isEngineBusy = true; 
      
      await platform.invokeMethod('startGeneration', {
        'text': finalChefPrompt,
        'imagePath': null,
        'audioPath': null,
      });

      _streamSubscription = streamChannel.receiveBroadcastStream().listen((dynamic event) {
        final Map<dynamic, dynamic> map = event;
        if (map['type'] == 'token') {
          setState(() {
            _chefNarrativeStreamResponse += map['content'];
          });
        } else if (map['type'] == 'done') {
          setState(() {
            _isEngineBusy = false; 
          });
        }
      }, onError: (_) {
        setState(() { _isEngineBusy = false; });
      });
    } catch (e) {
      debugPrint("Streaming pass exception: $e");
      setState(() { _isEngineBusy = false; });
    }
  }

  void _savePlanToDashboard() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? existing = prefs.getString('saved_recipes');
      List<dynamic> savedRecipesList = existing != null ? jsonDecode(existing) : [];

      List<Map<String, dynamic>> extractedChildRecipes = [];
      
      if (_chefNarrativeStreamResponse.contains('[RECIPE_START]')) {
        List<String> segments = _chefNarrativeStreamResponse.split('[RECIPE_START]');
        for (int i = 1; i < segments.length; i++) {
          String chunk = segments[i];
          if (chunk.contains('[RECIPE_END]')) {
            String recipeBlock = chunk.split('[RECIPE_END]')[0];
            String title = RegExp(r'\[TITLE\](.*)', caseSensitive: false).firstMatch(recipeBlock)?.group(1)?.trim() ?? "Tailored Special";
            String ingredientsPart = recipeBlock.split(RegExp(r'\[INGREDIENTS\]', caseSensitive: false))[1]
                                               .split(RegExp(r'\[STEPS\]', caseSensitive: false))[0].trim();
            List<String> components = ingredientsPart.split('\n').map((e) => e.replaceAll(RegExp(r'^[-\*\+]\s*'), '').trim()).where((e) => e.isNotEmpty).toList();
            String stepsPart = recipeBlock.split(RegExp(r'\[STEPS\]', caseSensitive: false))[1].trim();
            List<String> executionSteps = stepsPart.split('\n').map((e) => e.replaceAll(RegExp(r'^\d+[\.\)]\s*'), '').trim()).where((e) => e.isNotEmpty).toList();

            extractedChildRecipes.add({
              'name': title,
              'ingredients_needed': components,
              'steps': executionSteps,
              'nutrition': {'Calories': 'Balanced', 'Protein': 'Adaptive'}
            });
          }
        }
      }

      if (extractedChildRecipes.isEmpty) {
        extractedChildRecipes.add({
          'name': _selectedScope == "Single Meal" ? "Custom $_selectedTarget" : "$_selectedScope Plan",
          'ingredients_needed': _unifiedCartItems.map((e) => e['name'].toString()).toList(),
          'steps': [_chefNarrativeStreamResponse],
          'nutrition': {'Calories': 'Varies', 'Protein': 'Clinical'}
        });
      }

      if (_selectedScope == "Single Meal") {
        var targetMeal = extractedChildRecipes.first;
        savedRecipesList.removeWhere((element) => element['name'] == targetMeal['name']);
        savedRecipesList.insert(0, targetMeal);
      } else {
        String planBundleName = _selectedScope == "Full 1-Day Plan" ? "My 1-Day Meal Strategy" : "My 7-Day Nutrition Matrix";
        Map<String, dynamic> planBundlePayload = {
          'name': planBundleName,
          'isMealPlan': true, 
          'nutrition': {'Calories': 'Full Plan', 'Protein': 'Distributed'},
          'ingredients_needed': _unifiedCartItems.map((e) => e['name'].toString()).toList(),
          'recipes': extractedChildRecipes, 
        };
        savedRecipesList.removeWhere((element) => element['name'] == planBundlePayload['name']);
        savedRecipesList.insert(0, planBundlePayload);
      }

      await prefs.setString('saved_recipes', jsonEncode(savedRecipesList));
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_selectedScope == "Single Meal" 
              ? "✅ Saved recipe to Dashboard!" 
              : "✅ Saved complete plan bundle (${extractedChildRecipes.length} recipes) to Dashboard!"), 
            backgroundColor: const Color(0xFF0F766E)
          )
        );
      }
    } catch (e) {
      debugPrint("Dashboard Serialization Exception: $e");
    }
  }

 // ===========================================================================
  // 🎨 UI COMPONENTS & RENDERFLEX OVERFLOW WORKAROUNDS
  // ===========================================================================
  Widget _buildPersistentInteractiveImage() {
    if (_stagedImagePath == null || !File(_stagedImagePath!).existsSync()) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10, bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 10, offset: const Offset(0, 4))],
        border: Border.all(color: const Color(0xFF0F766E).withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                const Icon(Icons.zoom_in, color: Color(0xFF0F766E), size: 18),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    "Pinch to Zoom Scanned Ingredients",
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF0F766E)),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: Colors.teal.shade50, borderRadius: BorderRadius.circular(8)),
                  child: Text(
                    "${_rawDetectedItemsWithBoxes.length} Items",
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF0F766E)),
                  ),
                )
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1),
          ClipRRect(
            borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(16), bottomRight: Radius.circular(16)),
            child: SizedBox(
              height: 250,
              width: double.infinity,
              child: InteractiveViewer(
                panEnabled: true,
                boundaryMargin: const EdgeInsets.all(40),
                minScale: 1.0,
                maxScale: 4.0,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.file(File(_stagedImagePath!), fit: BoxFit.contain),
                    if (_rawDetectedItemsWithBoxes.isNotEmpty)
                      Positioned.fill(
                        child: CustomPaint(
                          painter: ImageMarkerPainter(
                            _rawDetectedItemsWithBoxes.map((e) => {'box_2d': e['box'], 'label': e['name']}).toList(),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kitchen Chef Module', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        flexibleSpace: Container(decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF0F766E), Color(0xFF0EA5E9)]))),
      ),
      backgroundColor: const Color(0xFFF1F5F9),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // 🌟 Step 1: Input controls stay at index slot 0
            _buildStepCard(step: "1", title: "Staged Culinary Inputs", active: _currentStep == ChefStep.inputStaging, body: _buildStep1Ui()),
            
            // 🌟 THE CRITICAL MOVE: Image Preview mounts directly BELOW Step 1 card instead of above it
            _buildPersistentInteractiveImage(),
            
            const SizedBox(height: 16),
            _buildStepCard(step: "2", title: "Ingredient Cart Verification", active: _currentStep == ChefStep.verificationCart, body: _buildStep2Ui()),
            const SizedBox(height: 16),
            _buildStepCard(step: "3", title: "Target Configurations Profile", active: _currentStep == ChefStep.parameterForms, body: _buildStep3Ui()),
            const SizedBox(height: 16),
            _buildStepCard(step: "4", title: "Personalized Kitchen Strategy", active: _currentStep == ChefStep.completeReveal, body: _buildStep4Ui()),
          ],
        ),
      ),
    );
  }

  Widget _buildStep1Ui() {
    // 🌟 DYNAMIC ACTIVE EVALUATOR: Becomes true if either an image is loaded or manually converted into cards
    final bool inputsShouldBeLocked = _stagedImagePath != null || _unifiedCartItems.isNotEmpty;

    return Column(
      children: [
        if (_isEngineBusy && _currentStep == ChefStep.inputStaging)
          const LinearProgressIndicator(color: Color(0xFF0F766E))
        else ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: inputsShouldBeLocked ? Colors.grey.shade300 : const Color(0xFF0F766E), 
                  foregroundColor: inputsShouldBeLocked ? Colors.grey.shade500 : Colors.white
                ), 
                onPressed: inputsShouldBeLocked ? null : () => _processImageInput(ImageSource.camera), 
                icon: const Icon(Icons.camera_alt), 
                label: const Text("Live Scan")
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: inputsShouldBeLocked ? Colors.grey.shade300 : const Color(0xFF0EA5E9), 
                  foregroundColor: inputsShouldBeLocked ? Colors.grey.shade500 : Colors.white
                ), 
                onPressed: inputsShouldBeLocked ? null : () => _processImageInput(ImageSource.gallery), 
                icon: const Icon(Icons.photo_library), 
                label: const Text("Gallery Pick")
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _textController,
            enabled: !inputsShouldBeLocked, // Locks typing channel dynamically
            decoration: InputDecoration(
              hintText: inputsShouldBeLocked ? "Inputs loaded. Proceed to verify below." : "Or type manually (e.g. Eggs, salmon, rice)...",
              fillColor: inputsShouldBeLocked ? Colors.grey.shade100 : Colors.transparent,
              filled: inputsShouldBeLocked,
              suffixIcon: IconButton(
                icon: Icon(Icons.arrow_circle_right_outlined, color: inputsShouldBeLocked ? Colors.grey.shade400 : const Color(0xFF0F766E)), 
                onPressed: inputsShouldBeLocked ? null : _processTextInput
              ),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          )
        ]
      ],
    );
  }

  Widget _buildStep2Ui() {
    if (_unifiedCartItems.isEmpty) return const SizedBox.shrink();
    return UnifiedIngredientCart(
      scannedItems: _unifiedCartItems,
      onConfirm: (finalItemsList) {
        setState(() {
          _unifiedCartItems = finalItemsList.map((e) => {'name': e}).toList();
          _currentStep = ChefStep.parameterForms; 
        });
      },
    );
  }

  Widget _buildStep3Ui() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("👥 SERVING COOKING SCALE", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF0F766E))),
        Row(
          children: [
            ChoiceChip(label: const Text("Single Person"), selected: _selectedScale == "Single Person", onSelected: (v) => setState(() => _selectedScale = "Single Person")),
            const SizedBox(width: 8),
            ChoiceChip(label: const Text("Household Family"), selected: _selectedScale == "Household Family Meal", onSelected: (v) => setState(() => _selectedScale = "Household Family Meal")),
          ],
        ),
        const SizedBox(height: 12),
        const Text("⏰ TEMPORAL PLAN SCOPE", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF0F766E))),
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(label: const Text("Single Meal"), selected: _selectedScope == "Single Meal", onSelected: (v) => setState(() => _selectedScope = "Single Meal")),
            ChoiceChip(label: const Text("Full 1-Day Plan"), selected: _selectedScope == "Full 1-Day Plan", onSelected: (v) => setState(() => _selectedScope = "Full 1-Day Plan")),
            ChoiceChip(label: const Text("7-Day Matrix"), selected: _selectedScope == "Full 7-Day Plan", onSelected: (v) => setState(() => _selectedScope = "Full 7-Day Plan")),
          ],
        ),
        const SizedBox(height: 12),
        
        if (_selectedScope == "Single Meal") ...[
          const Text("🍲 CULINARY WINDOW TARGET", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF0F766E))),
          DropdownButton<String>(
            value: _selectedTarget,
            isExpanded: true,
            items: ["Breakfast", "Lunch", "Dinner", "Snack"].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
            onChanged: (v) => setState(() => _selectedTarget = v!),
          ),
          const SizedBox(height: 16),
        ],

        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F766E), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            onPressed: () => _executeFinalChefStream(_unifiedCartItems.map((e) => e['name']).join(', ')),
            child: const Text("Compile Kitchen Plan", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        )
      ],
    );
  }

  Widget _buildSpecializedScheduleUi(String rawStreamText) {
    List<Widget> outputComponents = [];
    
    if (!rawStreamText.contains('[RECIPE_START]')) {
      if (_chefNarrativeStreamResponse.trim().isNotEmpty) {
         outputComponents.add(MarkdownBody(data: rawStreamText, styleSheet: MarkdownStyleSheet(p: const TextStyle(fontSize: 15, height: 1.4))));
      }
      
      if (_isEngineBusy || rawStreamText.trim().isEmpty) {
        outputComponents.add(
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
            child: Row(
              children: [
                const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0F766E))),
                const SizedBox(width: 16),
                Text("Gemma is designing your plan...", style: TextStyle(fontSize: 14, fontStyle: FontStyle.italic, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        );
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: outputComponents);
    }

    List<String> textSegments = rawStreamText.split('[RECIPE_START]');
    
    if (textSegments[0].trim().isNotEmpty) {
      outputComponents.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 16.0),
          child: MarkdownBody(data: textSegments[0].trim(), styleSheet: MarkdownStyleSheet(p: const TextStyle(fontSize: 15, height: 1.4))),
        ),
      );
    }

    for (int i = 1; i < textSegments.length; i++) {
      try {
        String chunk = textSegments[i];
        if (chunk.contains('[RECIPE_END]')) {
          List<String> bodyAndTrailing = chunk.split('[RECIPE_END]');
          String mainRecipeBlock = bodyAndTrailing[0];

          String title = RegExp(r'\[TITLE\](.*)', caseSensitive: false).firstMatch(mainRecipeBlock)?.group(1)?.trim() ?? "Adaptive Master Recipe";
          String ingredientsSection = mainRecipeBlock.split(RegExp(r'\[INGREDIENTS\]', caseSensitive: false))[1]
                                                    .split(RegExp(r'\[STEPS\]', caseSensitive: false))[0].trim();
          List<String> rawIngredients = ingredientsSection.split('\n').map((e) => e.replaceAll(RegExp(r'^[-\*\+]\s*'), '').trim()).where((e) => e.isNotEmpty).toList();
          String stepsSection = mainRecipeBlock.split(RegExp(r'\[STEPS\]', caseSensitive: false))[1].trim();
          List<String> rawSteps = stepsSection.split('\n').map((e) => e.replaceAll(RegExp(r'^\d+[\.\)]\s*'), '').trim()).where((e) => e.isNotEmpty).toList();

          outputComponents.add(
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.teal.shade50.withOpacity(0.4),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF0F766E).withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Theme(
                    data: ThemeData(iconTheme: const IconThemeData(color: Color(0xFF0F766E))),
                    child: Row(
                      children: [
                        const Icon(Icons.healing_rounded, size: 20),
                        const SizedBox(width: 8),
                        Expanded(child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F766E)))),
                      ],
                    ),
                  ),
                  const Divider(height: 20),
                  const Text("🛒 ADAPTED CLINICAL INGREDIENTS", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueGrey, letterSpacing: 0.8)),
                  const SizedBox(height: 6),
                  ...rawIngredients.map((ing) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3.0),
                    child: Row(
                      children: [
                        const Icon(Icons.health_and_safety_outlined, color: Color(0xFF0EA5E9), size: 12),
                        const SizedBox(width: 8),
                        Expanded(child: Text(ing, style: const TextStyle(fontSize: 14, color: Color(0xFF334155)))),
                      ],
                    ),
                  )),
                  const SizedBox(height: 14),
                  const Text("🍳 MODIFIED PREPARATION INSTRUCTIONS", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueGrey, letterSpacing: 0.8)),
                  const SizedBox(height: 6),
                  ...rawSteps.asMap().entries.map((entry) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 8,
                          backgroundColor: const Color(0xFF0F766E),
                          child: Text("${entry.key + 1}", style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Text(entry.value, style: const TextStyle(fontSize: 14, color: Color(0xFF334155), height: 1.3))),
                      ],
                    ),
                  )),
                ],
              ),
            ),
          );

          if (bodyAndTrailing.length > 1 && bodyAndTrailing[1].trim().isNotEmpty) {
            outputComponents.add(
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12.0),
                child: MarkdownBody(
                  data: bodyAndTrailing[1].trim(), 
                  styleSheet: MarkdownStyleSheet(p: const TextStyle(fontSize: 15, height: 1.4, color: Color(0xFF334155)))
                ),
              ),
            );
          }
        }
      } catch (e) {
         // Safe layout pass catch block
      }
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: outputComponents);
  }

  Widget _buildStep4Ui() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSpecializedScheduleUi(_chefNarrativeStreamResponse),
        
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.bookmark_added, color: Colors.white),
            label: Text(
              _isEngineBusy ? "Generating strategy..." : "Save ${_selectedScope == 'Single Meal' ? 'Recipe' : 'Plan'} to Dashboard", 
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: _isEngineBusy ? Colors.grey.shade400 : const Color(0xFF0EA5E9), 
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
            ),
            onPressed: _isEngineBusy || _chefNarrativeStreamResponse.isEmpty || _chefNarrativeStreamResponse.contains('not edible') ? null : _savePlanToDashboard,
          ),
        )
      ],
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: active ? const Color(0xFF0F766E) : Colors.transparent, width: 1.5),
        ),
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
              if (revealed) ...[
                const Divider(height: 24),
                body,
              ]
            ],
          ),
        ),
      ),
    );
  }
}

