import 'dart:io'; // NEW: Fixes 'File' and 'Platform' errors
import 'dart:convert'; // NEW: Fixes 'jsonEncode' and 'jsonDecode' errors
import 'dart:typed_data';
import 'dart:async';

import 'dart:isolate';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter/services.dart'; // REQUIRED FOR THE CLIPBOARD!
import 'dart:math' as math;
import '../models/recipe.dart';
import '../services/gecko_embedding_service.dart';
import '../widgets/food_gui_card.dart'; // NEW: Import the UI card
import '../services/nutrition_database.dart';
import '../widgets/recipe_menu_card.dart';
import '../widgets/recipe_stepper_card.dart'; // NEW: Import the UI card
import '../widgets/image_marker_painter.dart'; // NEW: Import the UI card
import '../models/chat_message.dart';
import '../profile_screen.dart';
import '../guidebook_screen.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import '../widgets/unified_ingredient_cart.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'dart:io';
import 'package:flutter/services.dart';

import 'home_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

enum Intent { recipeList, recipeSingle, nutrition, general }

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  static const platform = MethodChannel('com.ai.litertlm/chat');
  String currentDocumentContext = "";
  final TextEditingController _textController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  final ScrollController _scrollController = ScrollController();
  final GeckoEmbeddingService _geckoService = GeckoEmbeddingService();
  List<Map<String, dynamic>> _semanticDatabase = [];
  final AudioRecorder _audioRecorder = AudioRecorder();
  final FlutterTts _flutterTts = FlutterTts();
  bool _isRecording = false;
  String? _recordedAudioPath;

  // --- PHASE 3: SESSION STATE MANAGEMENT ---
  List<ChatSession> _sessions = [];
  ChatSession _activeSession = ChatSession(
    messages: [],
  ); // Starts empty by default
  bool _isCookingMode = false;
List<String> _memorizedIngredients = [];

  // THE MAGIC TRICK: This getter tricks the rest of your app into thinking
  // nothing changed. Every time your code says "_messages.add()", it is
  // secretly adding it to the _activeSession!
  List<ChatMessage> get _messages => _activeSession.messages;
  bool _isBusy = false;
  bool _isInitialized = false;
  File? _selectedImage;
  String? _patientProfilePrompt;
  String? _userName;
  String? _userGoal;
  // Note: We use _sessions instead of _chatHistory now!

  Intent _detectUserIntent(String text) {
    final input = text.toLowerCase();

    // 1. Recipe Keywords (High Intent)
    // 1. Single Recipe: "a recipe", "one recipe", or specific dish name
    if (input.contains("a recipe") ||
        input.contains("one recipe") ||
        input.contains("show me the recipe")) {
      return Intent.recipeSingle;
    }

    // 2. Recipe List: "some recipes", "list recipes", "options"
    if (input.contains("some recipes") ||
        input.contains("list recipes") ||
        input.contains("what can I make")) {
      return Intent.recipeList;
    }
    // 2. Nutrition Keywords (Factual)
    if (input.contains("calories") ||
        input.contains("protein") ||
        input.contains("healthy") ||
        input.contains("nutrition")) {
      return Intent.nutrition;
    }

    // Default to general conversation
    return Intent.general;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initTTS();
    _loadDataAndBootEngine();
  }

  Future<void> _initTTS() async {
    // 1. Stop any stuck audio processes from previous app crashes
    await _flutterTts.stop();

    // 2. DO NOT force "en-US" or any specific engine.
    // We will let the itel phone use its default system language so it doesn't fail!

    // 3. Keep the natural, fluid pacing
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setPitch(1.0);

    await _flutterTts.awaitSpeakCompletion(true);
  }

  // --- NEW: THE WAV REPAIRMAN ---
  Future<File> _repairWavFile(File wavFile) async {
    final bytes = await wavFile.readAsBytes();
    if (bytes.length < 44) return wavFile; // Safety check

    final byteData = ByteData.view(bytes.buffer);

    // Android's lazy MediaRecorder leaves bytes 4-7 and 40-43 as zeroes.
    // We manually calculate and inject the exact file sizes to fix the corruption!
    byteData.setUint32(4, bytes.length - 8, Endian.little);
    byteData.setUint32(40, bytes.length - 44, Endian.little);

    await wavFile.writeAsBytes(bytes, flush: true);
    return wavFile;
  }

  Future<void> _startRecording() async {
    if (await _audioRecorder.hasPermission()) {
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/gemma_audio_${DateTime.now().millisecondsSinceEpoch}.wav';

      await _flutterTts.stop();

      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: path,
      );

      setState(() {
        _isRecording = true;
      });
    }
  }

  Future<void> _stopRecording() async {
    if (_isRecording) {
      final path = await _audioRecorder.stop();
      setState(() {
        _isRecording = false;
      });

      await Future.delayed(const Duration(milliseconds: 500));

      if (path != null) {
        final audioFile = File(path);

        if (audioFile.existsSync() && audioFile.lengthSync() > 0) {
          // --- FIX APPLIED: Repair the file before sending! ---
          final repairedWav = await _repairWavFile(audioFile);

          setState(() {
            _recordedAudioPath = repairedWav.path;
          });

          _sendMessage(isVoiceNote: true);
        } else {
          setState(() {
            _messages.add(
              ChatMessage(
                text: "❌ Error: Microphone didn't record properly.",
                isSystem: true,
              ),
            );
          });
        }
      }
    }
  }

  Future<void> _loadDataAndBootEngine() async {
    try {
      debugPrint("🚀 BOOT CHECK 1: Loading SharedPrefs...");
      final prefs = await SharedPreferences.getInstance();
      _patientProfilePrompt = prefs.getString('saved_profile');

      setState(() {
        _userName = prefs.getString('prof_name');
        _userGoal = prefs.getString('prof_goal');
      });

      // Load ALL sessions
      final String? sessionsJson = prefs.getString('chat_sessions');
      if (sessionsJson != null) {
        final List<dynamic> decodedList = jsonDecode(sessionsJson);
        setState(() {
          _sessions = decodedList
              .map((item) => ChatSession.fromJson(item))
              .toList();
          if (_sessions.isNotEmpty) {
            _activeSession = _sessions.first; // Load the most recent chat
          }
        });
      }

      // If it's a completely fresh install, create the very first session
      if (_sessions.isEmpty) {
        setState(() {
          _activeSession = ChatSession(
            messages: [
              ChatMessage(
                text: "Welcome to your personal AI Nutritionist.",
                isSystem: true,
              ),
            ],
          );
          _sessions.add(_activeSession);
        });
      }

    
     
      debugPrint("🚀 BOOT CHECK 4: Initializing Chat Engine...");
      _scrollToBottom();
      //_initEngine();

      debugPrint("✅ BOOT FULLY COMPLETE!");
    } catch (e, stacktrace) {
      // 🌟 IF ANYTHING FAILS, IT GETS CAUGHT HERE INSTEAD OF FREEZING!
      debugPrint("🚨 CRITICAL BOOT FAILURE: $e");
      debugPrint("🚨 STACKTRACE: $stacktrace");
    }
  }

 
  Future<void> _saveChatHistory() async {
    final prefs = await SharedPreferences.getInstance();

    // Auto-generate a title based on the user's first message if it's still "New Chat"
    if (_activeSession.title == "New Chat" && _messages.length > 1) {
      final firstUserMsg = _messages.firstWhere(
        (m) => m.isUser,
        orElse: () => ChatMessage(text: "Chat"),
      );
      _activeSession.title = firstUserMsg.text.length > 20
          ? "${firstUserMsg.text.substring(0, 20)}..."
          : firstUserMsg.text;
    }

    _activeSession.lastUpdated = DateTime.now(); // Stamp the time

    // Save the entire list of sessions to device memory
    final String jsonString = jsonEncode(
      _sessions.map((s) => s.toJson()).toList(),
    );
    await prefs.setString('chat_sessions', jsonString);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _initEngine() async {
    setState(() {
      _isBusy = true;
      _messages.add(
        ChatMessage(text: "Waking up AI Engine...", isSystem: true),
      );
    });

    try {
      await platform.invokeMethod('initModel');
      setState(() {
        _messages.removeWhere((m) => m.text == "Waking up AI Engine...");
        _isInitialized = true;
      });
    } on PlatformException catch (e) {
      setState(() {
        _messages.add(
          ChatMessage(text: "❌ Engine Error: ${e.message}", isSystem: true),
        );
      });
    } finally {
      setState(() {
        _isBusy = false;
      });
    }
  }

Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,    // 🌟 CRITICAL FIX: Cap the width
      maxHeight: 800,   // 🌟 CRITICAL FIX: Cap the height
      imageQuality: 70, // 🌟 CRITICAL FIX: Compress the file size
    );
    if (image != null) {
      setState(() {
        _selectedImage = File(image.path);
      });
    }
  }

  // 🌟 REQUIRED IMPORTS


// 🌟 CHANNEL DEFINITIONS (Make sure these match your MainActivity.kt)
static const EventChannel _streamChannel = EventChannel('com.ai.litertlm/stream');

StreamSubscription? _streamSubscription;

// 🌟 THE FULL SEND MESSAGE FUNCTION
// 🌟 THE FULL SEND MESSAGE FUNCTION
// 🌟 THE UNLOCKED CONTEXT-AWARE SEND MESSAGE FUNCTION
// 🌟 THE UNLOCKED CONTEXT-AWARE TWO-PASS SEND MESSAGE FUNCTION
Future<void> _sendMessage({
  bool isVoiceNote = false,
  bool isHiddenTrigger = false,
}) async {
  if (!isVoiceNote && _textController.text.isEmpty && _selectedImage == null) return;

  await _flutterTts.stop();

  final String displayQuestion = isVoiceNote ? "🎤 [Voice Message]" : _textController.text;
  final String actualTextPrompt = _textController.text.isEmpty ? " " : _textController.text;
  final String? imagePathToPass = _selectedImage?.path;
  final String? audioPathToPass = isVoiceNote ? _recordedAudioPath : null;

  Intent intent = _detectUserIntent(actualTextPrompt);
  String contextualPrompt = "";
  String accumulatedText = "";
  
  final String aiMessageId = "ai_stream_${DateTime.now().millisecondsSinceEpoch}";
  final String userMessageId = "user_${DateTime.now().millisecondsSinceEpoch}";

  // =========================================================
  // 🌟 UI SETUP: ADD MESSAGES TO LIST
  // =========================================================
  setState(() {
    if (!isHiddenTrigger) {
      _messages.add(ChatMessage(
        text: displayQuestion,
        isUser: true,
        imagePath: imagePathToPass,
        id: userMessageId, 
      ));
    }

    _messages.add(ChatMessage(
      id: aiMessageId,
      text: "▌", 
      isUser: false,
      isSystem: false,
      type: MessageType.text,
    ));
    _isBusy = true;
  });

  if (!isHiddenTrigger) _textController.clear();
  setState(() { _selectedImage = null; _recordedAudioPath = null; });
  _scrollToBottom();
  await _saveChatHistory();

  // =========================================================
  // 🌟 UNIVERSAL MULTI-TIER GROUNDING ENGINE (RECIPES + CROPS)
  // =========================================================
  List<Map<String, dynamic>> localMatches = [];
  String groundedCropsPayload = "";

  // 1. THE INVENTORY SHRINKER (Rolling Window)
  // Extract up to the 10 most recent ingredients so we never exceed on-device token thresholds
  List<String> rawIngredients = currentDocumentContext
      .replaceAll("User has confirmed these ingredients: ", "")
      .replaceAll(".", "")
      .split(',')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  String safeInventory = rawIngredients.length > 10 
      ? rawIngredients.sublist(rawIngredients.length - 10).join(', ')
      : rawIngredients.join(', ');

  // 2. FIRST PASS: Extract clinical entities globally regardless of active user intent
  String parsingPrompt = """
    Analyze the user input and inventory. Extract any raw food ingredients, crops, or specific dish names mentioned that have real culinary or nutritional value.
    User: $actualTextPrompt
    Inventory: $safeInventory
    
    Convert them into a comma-separated list of formal, singular, lowercase English names.
    If nothing of value is found, return the word "none".
    Output ONLY the comma-separated list. Do not write sentences.
  """;

  String recipeContextPayload = "";

  try {
    final parseReply = await platform.invokeMethod('generateOnce', {
      'text': parsingPrompt,
      'imagePath': imagePathToPass,
      'audioPath': null,
    });

    String aiParsedEntities = parseReply.toString().trim();
    debugPrint("🤖 AI Universally Parsed Entities: $aiParsedEntities");

    if (aiParsedEntities.toLowerCase() != "none" && aiParsedEntities.isNotEmpty) {
      // Clean and split the entities returned by the upfront normalizer
      List<String> normalizedEntities = aiParsedEntities
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      // 🌟 REPLACED WITH AGIBLE OMNI-SEARCH:
      // This automatically checks if an element is a meal or item, unearths its sub-components,
      // and retrieves full macro distributions in millisecond time scales.
      final NutritionDatabase db = NutritionDatabase();
      String agileFacts = db.getAgileFacts(normalizedEntities);

      if (agileFacts.trim().isNotEmpty) {
        recipeContextPayload = "\n[VERIFIED LOCAL DATABASE REFERENCE DATA]:\n$agileFacts\n";
      }

      // Populate localMatches fallback so your custom menu tags (<recipemenu>) can still resolve cards
      localMatches = db.findMatchingRecipes(normalizedEntities);
    }
  } catch (e) {
    debugPrint("❌ Universal Parsing Pass Error: $e");
  }

  // 3. MERGE DATABASES INTO A SINGLE STRUCTURED REFERENCE BLOCK
  if (localMatches.isNotEmpty || groundedCropsPayload.isNotEmpty) {
    recipeContextPayload = "\n[VERIFIED LOCAL DATABASE REFERENCE DATA]:\n";
    
    if (localMatches.isNotEmpty) {
      recipeContextPayload += "\n--- MATCHED DISH DETAILS ---\n" +
          localMatches.map((m) => "- Dish Name: ${m['recipe']['name']}\n  Ingredients Needed: ${m['recipe']['ingredients_needed'].join(', ')}\n  Base Nutrition Profile: ${m['recipe']['nutrition'] ?? 'N/A'}\n  Prep Steps: ${m['recipe']['steps']?.join(' ') ?? ''}").join("\n");
    }
    
    if (groundedCropsPayload.isNotEmpty) {
      recipeContextPayload += "\n--- RAW MATERIAL NUTRITIONAL VALUES (PER 100G) ---\n" + groundedCropsPayload;
    }
  }
// =========================================================
  // 🌟 CONVERSATION MEMORY (Rolling Window)
  // =========================================================
  // Grab the last 4 valid back-and-forth messages to give the AI context without crashing the token limit.
  List<ChatMessage> validHistory = _messages.where((m) => !m.isSystem && m.id != userMessageId && m.id != aiMessageId).toList();
  
  String chatHistoryPayload = "";
  if (validHistory.isNotEmpty) {
    int startIndex = math.max(0, validHistory.length - 1); // Change 4 to however many messages you want to remember
    chatHistoryPayload = "\n[RECENT CONVERSATION HISTORY]:\n";
    for (int i = startIndex; i < validHistory.length; i++) {
      String role = validHistory[i].isUser ? "User" : "AI";
      chatHistoryPayload += "$role: ${validHistory[i].text}\n";
    }
  }
  // =========================================================
  // 🌟 PROMPT ROUTER (THE UNLOCKED CONTEXT PIPELINE)
  // =========================================================
  if (intent == Intent.recipeSingle || intent == Intent.recipeList) {
   contextualPrompt = """
      [NUTRITIONAL TUTOR MODE]
      Profile: $_patientProfilePrompt
            
      Local Database Context: $recipeContextPayload
      User Request: $actualTextPrompt
      
      YOUR INSTRUCTIONS:
      The user is asking about a recipe. Provide a brief, high-level overview of the dish and explain *why* it is healthy (or what to watch out for based on their medical profile).
      Do NOT generate a full step-by-step cooking guide. Remind them warmly that they can use the "Kitchen Chef Wizard" on the Home Screen to generate a complete, family-scaled meal plan.
      If the dish is in the local database, wrap its name in <recipemenu>Exact Recipe Name</recipemenu> so they can tap it.
    """;

  } else if (intent == Intent.nutrition) {
    contextualPrompt = """
      [NUTRITION MODE]
      Profile: $_patientProfilePrompt
      User Request: $actualTextPrompt
      Active Inventory: $safeInventory
      
      $recipeContextPayload
      
      INSTRUCTIONS:
      Answer the user's nutritional inquiry using structured Markdown Tables. 
      3. RULE OF CONCISENESS: Be extremely brief and straight to the point. Provide a 1-sentence introduction, list the options, and stop. Do NOT write long paragraphs.
      You must ground your calculations using the sub-component weights found in the RAW MATERIAL NUTRITIONAL VALUES block and match them accurately against the patient's specific health goals.
    """;

 } else {
   contextualPrompt = """
      [EDUCATIONAL KNOWLEDGE HUB MODE]
      Profile: $_patientProfilePrompt
      
      Local Database Context (If relevant): $recipeContextPayload
      Recent Chat History: $chatHistoryPayload
      
      User Request: $actualTextPrompt
      
      YOUR MISSION:
      You are the Gemma Nutritionist Educator. Your primary goal here is to EXPLAIN, EDUCATE, and INFORM. The user is here to learn.
      🛑 CRITICAL SAFETY PROTOCOL (NON-FOOD INGREDIENTS GATEWAY):
    Analyze the user request along with ingredients list input if present  carefully: "$actualTextPrompt".
    If the user request consist of  non-food items, inedible objects, dangerous substances, rocks/stones, sand, petroleum/gasoil, machinery, chemicals, or materials with absolutely NO culinary value in African cuisine, you MUST enforce this backup procedure:
    2. DO NOT make up or hallucinate an nutrien content or advice based on non edible substances.
    3. Respond directly and friendly in plain text to explain that these elements cannot be digested or cooked. Say it warmly like an empathetic Cameroonian grandmother (e.g., "Ah, my child, we cannot cook with sand and gasoil oh! Please give me real market ingredients like cassava, groundnuts, or tomatoes, and let's prepare something healthy for you.").

      1. BREAK IT DOWN: Explain complex nutritional, medical, or dietary concepts in very simple, easy-to-understand terms. Avoid overly dense clinical jargon.
      2. USE LOCAL ANALOGIES: Use relatable African/Cameroonian analogies to explain science (e.g., comparing fiber to a slow-burning wood fire, or explaining blood sugar using local staples like cassava or plantain).
      3. GROUNDED KNOWLEDGE: Use your deep internal knowledge combined with any provided Local Database Context to answer their questions factually.
      4. STAY IN CHARACTER: Act as a warm, empathetic health guide. Do NOT try to build daily meal plans here (the user has a separate Kitchen Chef tool for that).
      5. BE CONCISE: Keep paragraphs short and highly readable.
    """;
  }

  try {
    await _streamSubscription?.cancel();

    // =========================================================
    // 🌟 START LISTENING TO TOKEN STREAM
    // =========================================================
    _streamSubscription = _streamChannel.receiveBroadcastStream().listen(
      (event) {
        final Map<String, dynamic> data = Map<String, dynamic>.from(event);
        final String type = data['type'];

        if (type == 'token') {
          final String token = data['content'] ?? "";
          accumulatedText += token;

          final int index = _messages.indexWhere((m) => m.id == aiMessageId);
          if (index != -1) {
            // 🌟 REAL-TIME FILTER: Strip out raw tags on the fly sobrackets never leak during character generation
            String streamingTextCleaned = accumulatedText.replaceAll(RegExp(r'</?recipemenu>'), '');
            setState(() {
              _messages[index] = _messages[index].copyWith(
                text: streamingTextCleaned + "▌", 
              );
            });
            _scrollToBottom();
          }
        } 
        
        else if (type == 'done') {
          setState(() { _isBusy = false; });

          () async {
            String cleanResponse = accumulatedText
                .replaceAll(RegExp(r'<think>.*?</think>', dotAll: true), '')
                .trim();

            if (cleanResponse.startsWith('```json')) {
              cleanResponse = cleanResponse.replaceAll('```json', '').replaceAll('```', '').trim();
            }

            // Universal Tag Extractor
            final RegExp tagExp = RegExp(r'<recipemenu>(.*?)</recipemenu>', caseSensitive: false);
            final Iterable<RegExpMatch> tagMatches = tagExp.allMatches(cleanResponse);

            List<Map<String, dynamic>> finalUiMatches = [];
            
            for (final match in tagMatches) {
               String recipeName = match.group(1)?.trim() ?? "";
               try {
                 var found = localMatches.firstWhere((m) => 
                    m['recipe']['name'].toString().toLowerCase() == recipeName.toLowerCase());
                 if (!finalUiMatches.contains(found)) {
                    finalUiMatches.add(found);
                 }
               } catch (e) {
                 debugPrint("⚠️ AI referenced an asset outside pre-fetched collection: $recipeName");
               }
            }

            String textForUi = cleanResponse.replaceAll(RegExp(r'</?recipemenu>'), '');
            String speakableText = textForUi.replaceAll(RegExp(r'[*#_~`>]'), '');

            final int index = _messages.indexWhere((m) => m.id == aiMessageId);
            if (index != -1) {
              // 🌟 EXTRACT AGIBLE FACTS FOR ATTACHMENT
              // If your code uses agileFacts from above, make sure the variable is captured in scope
              String optionalSourcesText = recipeContextPayload.replaceAll("[VERIFIED LOCAL DATABASE REFERENCE DATA]:", "").trim();

              if (finalUiMatches.isNotEmpty) {
                setState(() {
                  _messages[index] = _messages[index].copyWith(
                    text: textForUi,
                    dataPayload: {'matches': finalUiMatches},
                    type: MessageType.recipeMenu,
                    sourcesRawText: optionalSourcesText.isNotEmpty ? optionalSourcesText : null, // 🌟 ATTACH HERE
                  );
                });
              } else {
                Map<String, dynamic>? extractedData;
                MessageType detectedType = MessageType.text;

                try {
                  final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(textForUi);
                  if (jsonMatch != null) {
                    final parsedJson = jsonDecode(jsonMatch.group(0)!);
                    if (parsedJson.containsKey('tool_used') && parsedJson['tool_used'] == 'getNutritionCard') {
                      extractedData = parsedJson['arguments'];
                      detectedType = MessageType.nutritionCard;
                      textForUi = "Here is the nutrition data.";
                    }
                  }
                } catch (_) {}

                setState(() {
                  _messages[index] = _messages[index].copyWith(
                    text: textForUi,
                    dataPayload: extractedData,
                    type: detectedType,
                    imagePath: detectedType == MessageType.visionBoundingBox ? imagePathToPass : null,
                    sourcesRawText: optionalSourcesText.isNotEmpty ? optionalSourcesText : null, // 🌟 ATTACH HERE
                  );
                });
              }
            }
            
            await _flutterTts.speak(speakableText);
            await _saveChatHistory();
          }();
        }
      },
      onError: (error) {
        debugPrint("❌ Streaming Error: $error");
        _updateMessage(aiMessageId, "❌ Error: $error");
      },
    );

    // =========================================================
    // 🌟 TRIGGER NATIVE EXECUTION (Second Pass Streaming)
    // =========================================================
    await platform.invokeMethod('startGeneration', {
      'text': contextualPrompt,
      'imagePath': null, // Managed up front in pass 1 extraction
      'audioPath': audioPathToPass,
    });

  } catch (e) {
    _updateMessage(aiMessageId, "❌ AI Initialization Error: $e");
  } finally {
    _scrollToBottom();
  }
}


void _updateMessage(String id, String newText) {
  final int index = _messages.indexWhere((m) => m.id == id);
  if (index != -1) {
    setState(() {
      _messages[index] = _messages[index].copyWith(text: newText);
    });
  }
}
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _flutterTts.stop();
    _audioRecorder.dispose();
    // 🌟 FIX: Force-cancel any running native generation thread when exiting the Chat Screen
    try {
      platform.invokeMethod('cancelGeneration');
      _streamSubscription?.cancel();
    } catch (e) {
      debugPrint("Stale stream sweep skipped: $e");
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _saveChatHistory();
    }
  }

  // --- PHASE 2: CUSTOM MESSAGE CONTROLS ---
  // --- PHASE 2: CUSTOM MESSAGE CONTROLS ---
  void _showMessageOptions(BuildContext context, ChatMessage msg) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            // 1. COPY (Now strictly for AI Messages)
            if (!msg.isUser && msg.type != MessageType.system)
              ListTile(
                leading: const Icon(Icons.copy, color: Colors.blueGrey),
                title: const Text('Copy AI Response'),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: msg.text));
                  Navigator.pop(context); // Close bottom sheet
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Copied to clipboard!")),
                  );
                },
              ),

            // 2. EDIT & RESEND (Now strictly for User Messages)
            if (msg.isUser)
              ListTile(
                leading: const Icon(
                  Icons.edit_document,
                  color: Color(0xFF0F766E),
                ), // Matched your theme color!
                title: const Text('Edit & Resend Prompt'),
                onTap: () {
                  Navigator.pop(context); // Close bottom sheet
                  _showEditAndResendDialog(msg);
                },
              ),
          ],
        ),
      ),
    );
  }

  // --- RAG ENGINE: FETCH FACTS FROM LOCAL DATABASE ---
  Future<String> _fetchGroundedFacts(List<String> userIngredients) async {
    // 1. Load the database from assets
    final String response = await rootBundle.loadString(
      'assets/african_crops.json',
    );
    final List<dynamic> database = jsonDecode(response);

    String groundedFacts = "";

    // 2. Search for each ingredient the user confirmed
    for (String ingredient in userIngredients) {
      String query = ingredient.toLowerCase().trim();
      bool found = false;

      for (var dbItem in database) {
        String mainName = dbItem['name'].toString().toLowerCase();
        List<dynamic> aliases = dbItem['aliases'] ?? [];

        // Match against name or aliases
        if (mainName.contains(query) ||
            query.contains(mainName) ||
            aliases.any((a) => query.contains(a.toString().toLowerCase()))) {
          groundedFacts +=
              "- **${dbItem['name']}** (per 100g): Calories: ${dbItem['calories']}, Protein: ${dbItem['protein']}, Carbs: ${dbItem['carbs']}, Fat: ${dbItem['fat']}\n";
          found = true;
          break;
        }
      }

      if (!found) {
        groundedFacts +=
            "- **$ingredient**: (No verified local data found in database. Estimate safely.)\n";
      }
    }
    return groundedFacts;
  }

  // --- 🌟 NEW: THE STOP COMMAND ---
// --- 🌟 THE UPGRADED STOP COMMAND ---
  Future<void> _stopGeneration() async {
    // 1. Instantly kill the Dart stream listener so the UI stops taking updates
    await _streamSubscription?.cancel();
    _streamSubscription = null;

    // 2. Stop the audio voice note playback/TTS immediately
    await _flutterTts.stop();

    setState(() {
      _isBusy = false;
      
      // Clean up the trailing blinking cursor if it's currently on screen
      if (_messages.isNotEmpty && _messages.last.text.endsWith("▌")) {
        _messages.last = _messages.last.copyWith(
          text: _messages.last.text.replaceAll("▌", "").trim(),
        );
      }
      
      _messages.add(ChatMessage(text: "🛑 Generation stopped by user.", isSystem: true));
    });
    
    _scrollToBottom();
    _saveChatHistory();

    // 3. TELL THE NATIVE ENGINE TO CANCEL THE JOB
    try {
      // Swapped 'stopGeneration' to 'cancelGeneration' to match your Kotlin MainActivity!
      await platform.invokeMethod('cancelGeneration');
    } catch (e) {
      debugPrint("❌ Failed to pass cancellation signal to native engine: $e");
    }
  }

  // --- 🌟 NEW: LOAD A SESSION FROM HISTORY ---
  void _loadSession(int index) {
    setState(() {
      _activeSession = _sessions[index];
    });
    Navigator.pop(context); // Close the drawer
    _scrollToBottom();
  }
  // --- 5. THE CONVERSATIONAL CHECKOUT PHASE ---

  void _showEditAndResendDialog(ChatMessage msg) {
    final TextEditingController editController = TextEditingController(
      text: msg.text,
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Edit Response & Resend"),
        content: TextField(
          controller: editController,
          maxLines: null,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F766E),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              // 1. Save the edited text to the chat history
              setState(() {
                msg.text = editController.text;
              });
              _saveChatHistory();
              Navigator.pop(context);

              // 2. Immediately put the text in the prompt box and fire the engine!
              _textController.text = editController.text;
              _sendMessage();
            },
            child: const Text("Update & Resend"),
          ),
        ],
      ),
    );
  }

  // 🌟 THE NORMALIZER: Strips plurals and common food suffixes
  String _normalizeWord(String word) {
    String w = word.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '').trim();

    if (w.isEmpty) return w;

    // Handle specific food edge cases and plurals
    if (w.endsWith('ies'))
      return w.substring(0, w.length - 3) + 'y'; // cherries -> cherry
    if (w.endsWith('oes'))
      return w.substring(0, w.length - 2); // tomatoes -> tomato
    if (w.endsWith('os'))
      return w.substring(0, w.length - 1); // tomatos -> tomato
    if (w.endsWith('s') && !w.endsWith('ss'))
      return w.substring(
        0,
        w.length - 1,
      ); // peanuts -> peanut, plantains -> plantain

    return w;
  }

  Widget _buildEmptyState() {
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: const Color(0xFF0EA5E9).withOpacity(0.1), shape: BoxShape.circle),
              child: const Icon(Icons.auto_awesome, size: 64, color: Color(0xFF0F766E)),
            ),
            const SizedBox(height: 24),
            Text("Ready to cook, ${_userName ?? 'Chef'}?", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF1E293B), letterSpacing: -0.5)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 12),
              child: Text(
                "Scan ingredients, ask for recipes, or check nutrition facts tailored to your goals.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 16, height: 1.4),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(color: Colors.teal.shade50, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.teal.shade100)),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lightbulb_outline, color: Color(0xFF0F766E), size: 18),
                  SizedBox(width: 8),
                  Text("Tip: Tap the camera to scan food!", style: TextStyle(color: Color(0xFF0F766E), fontSize: 13, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 🌟 NEW: THE GLOWING PROCESSING PILL
  Widget _buildProcessingIndicator() {
    if (!_isBusy) return const SizedBox.shrink();
    
    return Positioned(
      bottom: 16,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(30),
            boxShadow: [BoxShadow(color: const Color(0xFF0F766E).withOpacity(0.2), blurRadius: 15, offset: const Offset(0, 5))],
            border: Border.all(color: const Color(0xFF0EA5E9).withOpacity(0.3)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0F766E))),
              SizedBox(width: 12),
              Text("Gemma is thinking...", style: TextStyle(color: Color(0xFF0F766E), fontWeight: FontWeight.w700, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }

  void _createNewChat() {
    setState(() {
      // 1. Create a fresh session
      _activeSession = ChatSession(
        messages: [
          ChatMessage(
            text: "New session started. How can I help?",
            isSystem: true,
          ),
        ],
        title: "New Chat",
      );
      // 2. Add it to the master list
      _sessions.insert(0, _activeSession);
    });
    _saveChatHistory();
    _scrollToBottom();
  }

  void _deleteSession(int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Chat?"),
        content: const Text("This action cannot be undone."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _sessions.removeAt(index);
                // If we delete the active chat, switch to the next available one
                if (_sessions.isNotEmpty) {
                  _activeSession = _sessions.first;
                } else {
                  _createNewChat(); // Always keep at least one session
                }
              });
              _saveChatHistory();
              Navigator.pop(context);
            },
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // =======================================================
  // 🌟 THE PREMIUM CHAT HISTORY DRAWER
  // =======================================================
  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: const Color(0xFF0B1120), // A richer, darker premium slate
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. SCULPTED PREMIUM HEADER
          Container(
            padding: const EdgeInsets.only(top: 60, left: 24, right: 24, bottom: 30),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF0F766E).withOpacity(0.95),
                  const Color(0xFF0EA5E9).withOpacity(0.85)
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 5))
              ],
              borderRadius: const BorderRadius.only(bottomRight: Radius.circular(40)),
            ),
            child: SizedBox(
              width: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, spreadRadius: 2)
                      ]
                    ),
                    child: const Icon(Icons.auto_awesome, color: Color(0xFF0F766E), size: 32),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    "Gemma Engine", 
                    style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -0.5)
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Dietary Discourse Hub", 
                    style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13, fontWeight: FontWeight.w500)
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // 2. QUICK "NEW CHAT" ACTION BUTTON
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: InkWell(
              onTap: () {
                Navigator.pop(context); // Close the drawer
                _createNewChat();
              },
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B), // Raised panel color
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF0EA5E9).withOpacity(0.3)),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 8, offset: const Offset(0, 4))
                  ]
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(color: const Color(0xFF0EA5E9).withOpacity(0.2), shape: BoxShape.circle),
                      child: const Icon(Icons.add, color: Color(0xFF0EA5E9), size: 18),
                    ),
                    const SizedBox(width: 12),
                    const Text("Start New Session", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 32),

          // 3. SECTION TITLE WITH COUNTER
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                const Text(
                  "CONVERSATIONS", 
                  style: TextStyle(color: Colors.blueGrey, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.5)
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(12)),
                  child: Text(
                    "${_sessions.length}", 
                    style: const TextStyle(color: Color(0xFF2DD4BF), fontSize: 11, fontWeight: FontWeight.bold)
                  ),
                )
              ],
            ),
          ),
          
          const SizedBox(height: 12),
          
          // 4. FLOATING CHAT CARDS
          Expanded(
            child: _sessions.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.forum_outlined, size: 48, color: Colors.blueGrey.withOpacity(0.2)),
                        const SizedBox(height: 12),
                        Text("No history yet.", style: TextStyle(color: Colors.blueGrey.shade600, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: _sessions.length,
                    itemBuilder: (context, index) {
                      final session = _sessions[index];
                      bool isActive = session == _activeSession; 
                      
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          // Glow effect for the active chat
                          gradient: isActive 
                            ? LinearGradient(colors: [const Color(0xFF0F766E).withOpacity(0.15), Colors.transparent])
                            : null,
                          color: isActive ? null : Colors.transparent,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isActive ? const Color(0xFF0F766E).withOpacity(0.5) : Colors.transparent,
                            width: 1.5,
                          ),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.only(left: 12, right: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          leading: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: isActive ? const Color(0xFF0F766E).withOpacity(0.2) : const Color(0xFF1E293B), 
                              borderRadius: BorderRadius.circular(12) // Squircle icon background
                            ),
                            child: Icon(Icons.chat_bubble_outline, color: isActive ? const Color(0xFF2DD4BF) : Colors.blueGrey, size: 18),
                          ),
                          title: Text(
                            session.title, 
                            style: TextStyle(
                              color: isActive ? Colors.white : Colors.blueGrey.shade300, 
                              fontWeight: isActive ? FontWeight.w800 : FontWeight.w600, 
                              fontSize: 14
                            ), 
                            maxLines: 1, 
                            overflow: TextOverflow.ellipsis
                          ),
                          trailing: isActive 
                            // Show a glowing arrow if active, otherwise show the delete button
                            ? const Padding(
                                padding: EdgeInsets.only(right: 8.0),
                                child: Icon(Icons.arrow_forward_ios, size: 14, color: Color(0xFF2DD4BF)),
                              ) 
                            : IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.white24, size: 20),
                                onPressed: () => _deleteSession(index),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                          onTap: () => _loadSession(index),
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
  // --- 2. THE SIMPLE INGREDIENT SCANNER TRIGGER ---
  void _pickFoodImageForRag() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return SafeArea(
          child: Wrap(
            children: <Widget>[
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  "Scan Ingredients",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.blueGrey,
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt, color: Color(0xFF0F766E)),
                title: const Text('Take a Photo'),
                onTap: () async {
                  Navigator.of(context).pop(); 
                  final XFile? image = await _picker.pickImage(
                    source: ImageSource.camera,
                    maxWidth: 800,    // 🌟 STOP THE OOM CRASH
                    maxHeight: 800,
                    imageQuality: 70,
                  );
                  if (image != null) _processIngredientImage(image.path);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.photo_library,
                  color: Color(0xFF0EA5E9),
                ),
                title: const Text('Choose from Gallery'),
                onTap: () async {
                  Navigator.of(context).pop(); 
                  final XFile? image = await _picker.pickImage(
                    source: ImageSource.gallery,
                    maxWidth: 800,    // 🌟 STOP THE OOM CRASH
                    maxHeight: 800,
                    imageQuality: 70,
                  );
                  if (image != null) _processIngredientImage(image.path);
                },
              ),
            ],
          ),
        );
      },
    );
  } // --- 3. THE BARE-BONES GEMMA SCANNER ---
  Future<void> _scanIngredientsSimple(String imagePath) async {
    setState(() {
      _isBusy = true;
      _messages.add(
        ChatMessage(text: "🔍 Scanning ingredients...", isSystem: true),
      );
    });
    _scrollToBottom();

    try {
      // 1. Send the image and a direct prompt straight to your offline Gemma model
      final reply = await platform.invokeMethod('generateOnce', {
        'text':
            "List the raw food ingredients you see in this image. Keep it brief and conversational.",
        'imagePath': imagePath,
        'audioPath': null,
      });

      // 2. Clean up the response
      String gemmaText = reply.toString().trim();

      setState(() {
        // 3. Remove the "Scanning..." message
        _messages.removeWhere((m) => m.text == "🔍 Scanning ingredients...");

        // 4. Display Gemma's answer along with the image they took!
        _messages.add(
          ChatMessage(text: gemmaText, isUser: false, imagePath: imagePath),
        );
      });

      // 5. Read it out loud! (Filtering out Markdown asterisks)
      await _flutterTts.speak(gemmaText.replaceAll(RegExp(r'[*#_~`>]'), ''));
    } catch (e) {
      setState(() {
        _messages.removeWhere((m) => m.text == "🔍 Scanning ingredients...");
        _messages.add(
          ChatMessage(text: "❌ Error scanning: $e", isSystem: true),
        );
      });
    } finally {
      setState(() {
        _isBusy = false;
      });
      _scrollToBottom();
      _saveChatHistory();
    }
  }

  // --- 4. THE MASTER AGENTIC PIPELINE ---
  // --- 4. THE MASTER AGENTIC PIPELINE (WITH DEBUGGING) ---
  // --- 4. THE MASTER AGENTIC PIPELINE ---
  Future<void> _processIngredientImage(String imagePath) async {
    setState(() {
      _isBusy = true;
      _messages.add(
        ChatMessage(
          text: "🔍 Analyzing ingredients and calculating bounding boxes...",
          isSystem: true,
        ),
      );
    });
    _scrollToBottom();

    // 1. Get the strict JSON list from Gemma
    List<Map<String, dynamic>>? rawItems = await _getIngredientsFromGemma(
      imagePath,
    );

    if (rawItems == null || rawItems.isEmpty) {
      setState(() {
        _messages.removeWhere((m) => m.text.contains("Analyzing ingredients"));
        _messages.add(
          ChatMessage(
            text:
                "❌ I couldn't clearly see any ingredients. Try another angle?",
            isSystem: true,
          ),
        );
        _isBusy = false;
      });
      return;
    }

    // 🌟 1.5 THE HALLUCINATION SANITIZER 🌟
    // Fixes Gemma's missing decimal points before the math breaks!
    for (var item in rawItems) {
      if (item['box'] != null && item['box'] is List) {
        List<dynamic> box = item['box'];
        for (int i = 0; i < box.length; i++) {
          double val = box[i].toDouble();
          if (val > 1.0) {
            // If Gemma outputs '545' instead of '0.545', we fix it here.
            val = val / 1000.0;
            // Safety clamp just in case it hallucinates something massive
            if (val > 1.0) val = 1.0;
          }
          box[i] = val; // Save the cleaned number back to the array
        }
      }
    }

    // 2. Loop through and crop EVERY item so the user can visually verify them!
    for (var item in rawItems) {
      if (item['box'] != null) {
        String? croppedPath = await _cropConfusingIngredient(
          imagePath,
          item['box'],
        );
        item['imagePath'] = croppedPath;
      }
    }

    // --- THE DEBUG BOUNDING BOX VISUALIZER ---
    List<Map<String, dynamic>> debugBoxes = rawItems
        .map(
          (item) => {
            // Pass the now-sanitized boxes directly to the painter
            'box_2d': item['box'],
            'label': item['name'],
          },
        )
        .toList();

    // 3. Summon the Debug Image AND the Unified Cart UI!
    setState(() {
      _messages.removeWhere((m) => m.text.contains("Analyzing ingredients"));

      _messages.add(
        ChatMessage(
          text: "Here is exactly where I saw those items:",
          isUser: false,
          imagePath: imagePath,
          type: MessageType.visionBoundingBox,
          dataPayload: {'boxes': debugBoxes},
        ),
      );

      _messages.add(
        ChatMessage(
          text: "Review time!",
          isUser: false,
          unifiedCartData: rawItems,
        ),
      );

      _isBusy = false;
    });

    _scrollToBottom();
    await _saveChatHistory();
  }

  void _startRecipeSearch(List<String> verifiedIngredients) async {
    String ingredientsText = verifiedIngredients.join(", ");

    setState(() {
      _messages.add(
        ChatMessage(
          text: "Ingredients confirmed: $ingredientsText",
          isUser: true,
        ),
      );
      _messages.add(
        ChatMessage(text: "Updating my knowledge base...", isSystem: true),
      );
    });
    _scrollToBottom();

    // 1. Get the grounded facts silently!
    String groundedFacts = await _fetchGroundedFacts(verifiedIngredients);

    // 2. Inject the facts into Gemma's memory and ask it to be conversational
    setState(() {
      _isBusy = true;
    });
    try {
      String prompt =
          """
$_patientProfilePrompt 

You are an expert, friendly African culinary nutritionist. I have just scanned and confirmed these ingredients: $ingredientsText.

[SYSTEM FACTS - STORE IN MEMORY]
Here is the verified nutritional data per 100g from our local database:
$groundedFacts
[/SYSTEM FACTS]

Acknowledge my ingredients in a warm tone. Then, provide a beautifully formatted Markdown table showing the nutritional breakdown based strictly on the facts above. Finally, ask me what kind of meal I want to make today. Ensure all advice aligns with my Patient Profile above.
""";
      final reply = await platform.invokeMethod('startGeneration', {
        'text': prompt,
        'imagePath': null,
        'audioPath': null,
      });

      setState(() {
        _messages.removeWhere(
          (m) => m.text.contains("Updating my knowledge base"),
        );
        _messages.add(
          ChatMessage(text: reply.toString().trim(), isUser: false),
        );
      });
    } catch (e) {
      setState(() {
        _messages.removeWhere(
          (m) => m.text.contains("Updating my knowledge base"),
        );
        _messages.add(
          ChatMessage(text: "❌ Error connecting to AI: $e", isSystem: true),
        );
      });
    } finally {
      setState(() {
        _isBusy = false;
      });
      _scrollToBottom();
      _saveChatHistory();
    }
  }

// 🌟 PURE MATH HELPER: Doesn't need TFLite or Gecko to be initialized!
  double _calculateCosineSimilarity(List<double> vecA, List<double> vecB) {
    double dotProduct = 0.0;
    double normA = 0.0;
    double normB = 0.0;
    for (int i = 0; i < vecA.length; i++) {
      dotProduct += vecA[i] * vecB[i];
      normA += vecA[i] * vecA[i];
      normB += vecB[i] * vecB[i];
    }
    if (normA == 0 || normB == 0) return 0.0;
    return dotProduct / (math.sqrt(normA) * math.sqrt(normB));
  }

Future<List<Map<String, dynamic>>> _findGroundedRecipe(
    String normalizedInput, { 
    int limit = 3,
  }) async {
    debugPrint("\n================ CANONICAL SEARCH START ================");
    
    if (_semanticDatabase.isEmpty) return [];

    try {
      debugPrint("🔍 Normalized Input from AI: '$normalizedInput'");

      // 🌟 1. USE YOUR NORMALIZER: Clean plurals and typos (e.g. "tomatos" -> "tomato")
      List<String> userIngredients = normalizedInput
          .toLowerCase()
          .split(',')
          .map((e) => _normalizeWord(e.trim())) 
          .where((e) => e.isNotEmpty)
          .toList();

      List<Map<String, dynamic>> matchedRecipes = [];

      for (var dbItem in _semanticDatabase) {
        var recipe = dbItem['recipe'] ?? dbItem; 
        List<dynamic> neededRaw = recipe['ingredients_needed'] ?? [];
        
        List<String> needed = neededRaw.map((e) => e.toString().toLowerCase().trim()).toList();
        
        int matchCount = 0;
        List<String> missing = [];

        // 🌟 2. FUZZY SUBSTRING MATCHING
        for (var ingredient in needed) {
          bool isMatch = false;
          String normalizedRecipeIngredient = _normalizeWord(ingredient);

          // Check if the user's ingredient is anywhere INSIDE the recipe's ingredient string
          // (e.g., if user has "tomato", it will match "fresh tomatoes" or "chopped tomato")
          for (var userIng in userIngredients) {
            if (normalizedRecipeIngredient.contains(userIng) || ingredient.contains(userIng)) {
              isMatch = true;
              break;
            }
          }

          if (isMatch) {
            matchCount++;
          } else {
            missing.add(ingredient);
          }
        }

        // 3. Scoring
        if (matchCount > 0) {
          double matchScore = matchCount / needed.length; 
          matchedRecipes.add({
            'recipe': recipe,
            'score': matchScore,
            'missing': missing,
          });
        }
      }

      // 4. Sort and return
      matchedRecipes.sort((a, b) => b['score'].compareTo(a['score']));
      var finalWinners = matchedRecipes.take(limit).toList();

      debugPrint("🏆 CANONICAL SEARCH COMPLETE. TOP ${finalWinners.length} WINNERS:");
      for (var winner in finalWinners) {
        debugPrint("🥇 ${winner['recipe']['name']} (Match Score: ${(winner['score'] * 100).toStringAsFixed(1)}%)");
      }
      debugPrint("==================================================\n");

      return finalWinners;

    } catch (e) {
      debugPrint("❌ ALGORITHMIC SEARCH ERROR: $e");
      return [];
    }
  }
  
  // --- UTILITY 1: Force Gemma to output strict JSON data ---
  
  Future<List<Map<String, dynamic>>?> _getIngredientsFromGemma(
    String imagePath,
  ) async {
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
    ]
    """;

    try {
     final reply = await platform.invokeMethod(
  'generateOnce',
  {
    'text': prompt,
    'imagePath': imagePath,
    'audioPath': null,
  },
);
// 🌟 2. THE SAFETY GATE: If the engine is busy/locked, it returns null
    if (reply == null || reply.toString().trim().isEmpty) {
      debugPrint("⚠️ Native engine returned nothing. Is a session still open?");
      return null; 
    }
      String cleanJson = reply.toString().trim();

      // Strip markdown block if Gemma accidentally includes it
      if (cleanJson.startsWith('```json')) {
        cleanJson = cleanJson
            .replaceAll('```json', '')
            .replaceAll('```', '')
            .trim();
      } else if (cleanJson.startsWith('```')) {
        cleanJson = cleanJson.replaceAll('```', '').trim();
      }

      List<dynamic> parsedList = jsonDecode(cleanJson);
      return List<Map<String, dynamic>>.from(parsedList);
    } catch (e) {
      debugPrint("❌ JSON Parse Error: $e");
      return null;
    }
  }

  // --- UTILITY 2: The Digital Scissors (Image Cropping) ---
  // --- UTILITY 2: The Digital Scissors (Bulletproof Version) ---
  // --- UTILITY 2: The Digital Scissors (Bulletproof Math Version) ---
  Future<String?> _cropConfusingIngredient(
    String originalImagePath,
    List<dynamic> box,
  ) async {
    try {
      final imageFile = File(originalImagePath);
      img.Image? originalImage = img.decodeImage(imageFile.readAsBytesSync());
      if (originalImage == null) return null;

      originalImage = img.bakeOrientation(originalImage);

      // 1. Grab the raw floats from Gemma
      double val0 = box[0].toDouble();
      double val1 = box[1].toDouble();
      double val2 = box[2].toDouble();
      double val3 = box[3].toDouble();

      // 🌟 THE AUTO-CORRECTOR:
      // Even if Gemma swaps max and min, this forces the smaller number to always be Min!
      double safeYMin = math.min(val0, val2);
      double safeYMax = math.max(val0, val2);
      double safeXMin = math.min(val1, val3);
      double safeXMax = math.max(val1, val3);

      // 2. Convert to exact pixels and clamp to image boundaries
      int yMin = (safeYMin * originalImage.height).toInt().clamp(
        0,
        originalImage.height - 1,
      );
      int xMin = (safeXMin * originalImage.width).toInt().clamp(
        0,
        originalImage.width - 1,
      );
      int yMax = (safeYMax * originalImage.height).toInt().clamp(
        0,
        originalImage.height,
      );
      int xMax = (safeXMax * originalImage.width).toInt().clamp(
        0,
        originalImage.width,
      );

      int width = (xMax - xMin).clamp(1, originalImage.width);
      int height = (yMax - yMin).clamp(1, originalImage.height);

      // Command Flutter to cut the image
      img.Image croppedImage = img.copyCrop(
        originalImage,
        x: xMin,
        y: yMin,
        width: width,
        height: height,
      );

      // Save it to the cache
      final directory = await getTemporaryDirectory();
      final croppedPath =
          '${directory.path}/crop_${DateTime.now().millisecondsSinceEpoch}.jpg';
      File(croppedPath).writeAsBytesSync(img.encodeJpg(croppedImage));

      return croppedPath;
    } catch (e) {
      debugPrint("❌ Crop error: $e");
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
   return Scaffold(
      // 🌟 FIX 1: Attach to endDrawer so it slides in from the right!
      endDrawer: _buildDrawer(), 
      appBar: AppBar(
        // The Back Button safely stays on the left
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
          onPressed: () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => HomeScreen(userName: _userName ?? "Chef"),
              ),
            );
          },
        ),
        title: const Text(
          'OmniDiet AI',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0F766E), Color(0xFF0EA5E9)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        actions: [
          // 1. New Chat Button
          IconButton(
            icon: const Icon(Icons.add_comment_outlined, color: Colors.white),
            tooltip: 'New Chat',
            onPressed: _createNewChat,
          ),
          
          // 🌟 FIX 2: Replaced the Camera, Profile, and Guidebook buttons 
          // with a clean Hamburger menu that opens the Chat History drawer!
          Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.menu, color: Colors.white),
              tooltip: 'Chat History',
              onPressed: () => Scaffold.of(context).openEndDrawer(),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 20,
                    ),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];

                      // --- 🌟 NEW: THE UNIFIED INGREDIENT CART ---
                      // If this message contains cart data, render the interactive widget!
                      // --- 🌟 THE CART INTERCEPTOR ---
                      if (msg.unifiedCartData != null) {
                        return UnifiedIngredientCart(
                          scannedItems: msg.unifiedCartData!,
                          onConfirm: (finalList) {
                            setState(() {
                              // We store the confirmed items in a variable instead of firing a recipe immediately
                              currentDocumentContext =
                                  "User has confirmed these ingredients: ${finalList.join(', ')}.";

                              _messages.add(
                                ChatMessage(
                                  text:
                                      "Ingredients confirmed! 🥗 I've noted them down. Would you like a recipe suggestion, nutritional insights, or help with something else?",
                                  isSystem: true,
                                ),
                              );
                            });
                            _saveChatHistory();
                          },
                        );
                      }

                      // --- SYSTEM MESSAGES ---
                      if (msg.isSystem || msg.type == MessageType.system) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16.0),
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                msg.text,
                                style: TextStyle(
                                  color: Colors.grey.shade700,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        );
                      }

                      // --- USER & AI CHAT BUBBLES ---
                      return GestureDetector(
                        onLongPress: () => _showMessageOptions(context, msg),
                        child: Align(
                          alignment: msg.isUser
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 16.0),
                            padding: const EdgeInsets.all(16),
                            constraints: BoxConstraints(
                              maxWidth: MediaQuery.of(context).size.width * 0.8,
                            ),
                            decoration: BoxDecoration(
                              color: msg.isUser
                                  ? const Color(0xFF0F766E)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(24).copyWith(
                                bottomRight: msg.isUser
                                    ? const Radius.circular(4)
                                    : null,
                                bottomLeft: !msg.isUser
                                    ? const Radius.circular(4)
                                    : null,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // 1. IMAGE & BOUNDING BOX LAYER
                                // 1. IMAGE & BOUNDING BOX LAYER
                                if (msg.imagePath != null &&
                                    File(msg.imagePath!).existsSync())
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      bottom: 12.0,
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      // 🌟 Add a SizedBox to constrain the height
                                      child: SizedBox(
                                        height:
                                            300, // Keeps the image contained while zooming
                                        width: double.infinity,
                                        // 🌟 THE MAGIC WIDGET:
                                        child: InteractiveViewer(
                                          panEnabled:
                                              true, // Allow panning around
                                          boundaryMargin: const EdgeInsets.all(
                                            20,
                                          ), // Let them pull slightly past the edge
                                          minScale: 1.0, // Normal size
                                          maxScale:
                                              5.0, // Let them zoom in up to 5x!
                                          child: Stack(
                                            alignment: Alignment.center,
                                            children: [
                                              Image.file(
                                                File(msg.imagePath!),
                                                fit: BoxFit.contain,
                                              ),
                                              if (msg.type ==
                                                      MessageType
                                                          .visionBoundingBox &&
                                                  msg.dataPayload != null)
                                                Positioned.fill(
                                                  child: CustomPaint(
                                                    painter: ImageMarkerPainter(
                                                      msg.dataPayload!['boxes'],
                                                    ),
                                                    child: Container(),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                // 2. THE PERFECT RENDER SWITCH
                                Builder(
                                  builder: (context) {
                                    switch (msg.type) {
                                      case MessageType.nutritionCard:
                                        return FoodGuiCard(
                                          foodData: msg.dataPayload!,
                                        );
                                      // 🌟 ADD THIS CASE HERE 🌟
                                      case MessageType.recipeMenu:

                                      
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      // 1. The conversational text layer stays perfectly intact!
      MarkdownBody(
        data: msg.text,
        selectable: true,
        styleSheet: MarkdownStyleSheet(
          p: TextStyle(
            fontSize: 16,
            color: msg.isUser ? Colors.white : const Color(0xFF334155),
            height: 1.5,
          ),
          strong: TextStyle(
            fontWeight: FontWeight.w800,
            color: msg.isUser ? Colors.white : const Color(0xFF0F766E),
          ),
        ),
      ),
      
      // =========================================================
      // 🌟 THE NEW VISUAL SEPARATOR 🌟
      // =========================================================
      const SizedBox(height: 20),
      Row(
        children: [
          Expanded(child: Divider(color: const Color(0xFF0F766E).withOpacity(0.3), thickness: 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: Row(
              children: [
                const Icon(Icons.restaurant_menu, size: 16, color: Color(0xFF0F766E)),
                const SizedBox(width: 6),
                Text(
                  "RECOMMENDED DISHES",
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: msg.isUser ? Colors.white70 : const Color(0xFF0F766E),
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: Divider(color: const Color(0xFF0F766E).withOpacity(0.3), thickness: 1)),
        ],
      ),
      const SizedBox(height: 16),

      // =========================================================
      // 🌟 THE INTERACTIVE MENU CARD (WITH FIXED MISSING LOGIC)
      // =========================================================
      RecipeMenuCard(
        matches: msg.dataPayload!['matches'],
        onFetchRecipe: (String recipeName) async {
          try {
            // 1. Grab the matches list directly from the payload
            List<dynamic> matchesList = msg.dataPayload!['matches'];
            
            // 2. Find the exact recipe the user just tapped
            var exactMatch = matchesList.firstWhere(
              (m) => m['recipe']['name'] == recipeName,
              orElse: () => null,
            );

            if (exactMatch == null) return null;

            // 3. 🌟 THE FIX: Stop recalculating! 
            // _findGroundedRecipe already did the math perfectly, so we just pass its 'missing' array directly!
            return {
              ...exactMatch['recipe'],
              'missingIngredients': exactMatch['missing'] ?? [], 
            };
            
          } catch (e) {
            debugPrint("Fetch Error: $e");
            return null;
          }
        },
      ),
    ],
  );
                                      
                                      
                                      case MessageType.recipeCard:
                                        return RecipeStepperCard(
                                          recipe: RecipePayload.fromJson(
                                            msg.dataPayload!,
                                          ),
                                        );

                                      case MessageType.visionBoundingBox:
                                        return Text(
                                          msg.text,
                                          style: TextStyle(
                                            color: Colors.grey.shade500,
                                            fontStyle: FontStyle.italic,
                                          ),
                                        );

                                      case MessageType.text:
                                      default:
                                        // 🌟 THE PREMIUM MARKDOWN RENDERER 🌟
                                        return MarkdownBody(
                                          data: msg.text,
                                          selectable:
                                              true, // Lets the user highlight and copy specific words!
                                          styleSheet: MarkdownStyleSheet(
                                            // 1. Standard Text Styling
                                            p: TextStyle(
                                              fontSize: 16,
                                              color: msg.isUser
                                                  ? Colors.white
                                                  : const Color(0xFF334155),
                                              height: 1.5,
                                            ),
                                            strong: TextStyle(
                                              fontWeight: FontWeight.w800,
                                              color: msg.isUser
                                                  ? Colors.white
                                                  : const Color(
                                                      0xFF0F766E,
                                                    ), // Highlights bold text in your brand color
                                            ),

                                            // 2. Beautiful Table Styling
                                            // 2. Beautiful Table Styling
                                            tableBorder: TableBorder.all(
                                              color: msg.isUser
                                                  ? Colors.white38
                                                  : Colors.grey.shade300,
                                              width: 1,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            tableCellsPadding:
                                                const EdgeInsets.symmetric(
                                                  vertical: 12,
                                                  horizontal: 16,
                                                ),

                                            // 🌟 THE FIX: Removed the invalid decoration property and made the text Teal!
                                            tableHead: const TextStyle(
                                              fontWeight: FontWeight.w900,
                                              fontSize: 16,
                                              color: Color(0xFF0F766E),
                                            ),
                                            tableBody: TextStyle(
                                              color: msg.isUser
                                                  ? Colors.white
                                                  : const Color(0xFF334155),
                                            ),

                                            // 3. Lists and Quotes
                                            listBullet: TextStyle(
                                              color: msg.isUser
                                                  ? Colors.white
                                                  : const Color(0xFF0EA5E9),
                                              fontSize: 18,
                                            ),
                                            blockquote: const TextStyle(
                                              fontStyle: FontStyle.italic,
                                              color: Colors.blueGrey,
                                            ),
                                            blockquoteDecoration: BoxDecoration(
                                              border: const Border(
                                                left: BorderSide(
                                                  color: Color(0xFF0EA5E9),
                                                  width: 4,
                                                ),
                                              ),
                                              color: Colors.blueGrey.shade50,
                                            ),
                                            blockquotePadding:
                                                const EdgeInsets.all(12),
                                          ),
                                        );
                                    }
                                  },
                                ),
                             // =======================================================
                                // 📚 🌟 NEW: COLLAPSIBLE VERIFIED MEDICAL SOURCES SECTION
                                // =======================================================
                                if (!msg.isUser && msg.sourcesRawText != null && msg.sourcesRawText!.isNotEmpty)
                                  Theme(
                                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                                    child: Container(
                                      margin: const EdgeInsets.only(top: 14),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF8FAFC), // Ultra-clean subtle gray contrast panel
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: const Color(0xFF0F766E).withOpacity(0.15)),
                                      ),
                                      child: ExpansionTile(
                                        tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                                        leading: const Icon(Icons.verified_user_rounded, color: Color(0xFF0F766E), size: 18),
                                        title: const Text(
                                          "Verified Database Sources",
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Color(0xFF0F766E),
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 0.3,
                                          ),
                                        ),
                                        children: [
                                          Padding(
                                            padding: const EdgeInsets.only(left: 14, right: 14, bottom: 14),
                                            child: Align(
                                              alignment: Alignment.centerLeft,
                                              child: MarkdownBody(
                                                data: msg.sourcesRawText!,
                                                styleSheet: MarkdownStyleSheet(
                                                  p: const TextStyle(fontSize: 12, color: Color(0xFF475569), height: 1.4),
                                                  strong: const TextStyle(color: Color(0xFF0F766E), fontWeight: FontWeight.bold),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),

                                // --- 3. THE DEVELOPER DEBUG DROPDOWN ---
                                if (!msg.isUser && msg.dataPayload != null)
                                  Theme(
                                    data: Theme.of(context).copyWith(
                                      dividerColor: Colors.transparent,
                                    ),
                                    child: ExpansionTile(
                                      tilePadding: EdgeInsets.zero,
                                      title: const Text(
                                        "🐛 Debug: View Raw Payload",
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.blueGrey,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(12),
                                          width: double.infinity,
                                          decoration: BoxDecoration(
                                            color: Colors.black87,
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: Text(
                                            // This prints the exact JSON map the UI received!
                                            jsonEncode(msg.dataPayload),
                                            style: const TextStyle(
                                              color: Colors.greenAccent,
                                              fontSize: 11,
                                              fontFamily: 'monospace',
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),

          // 1. IMAGE PREVIEW (Your existing logic, perfected)
          if (_selectedImage != null)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 8.0,
              ),
              child: Row(
                children: [
                  Stack(
                    alignment: Alignment.topRight,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(
                          _selectedImage!,
                          height: 80,
                          width: 80,
                          fit: BoxFit.cover,
                        ),
                      ),
                      GestureDetector(
                        onTap: () => setState(() => _selectedImage = null),
                        child: Container(
                          margin: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.redAccent,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

          // 2. MAIN INPUT DOCK
          Container(
            padding: const EdgeInsets.only(
              left: 16,
              right: 16,
              bottom: 24,
              top: 8,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              border: Border(top: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              children: [
                // Camera Button
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.camera_alt),
                    color: const Color(0xFF0F766E),
                    onPressed: _isBusy || !_isInitialized ? null : _pickImage,
                  ),
                ),
                const SizedBox(width: 8),

                // Voice/Mic Button (Your Animated Mic)
                GestureDetector(
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Press and hold to record!"),
                      ),
                    );
                  },
                  onLongPress: _isBusy || !_isInitialized
                      ? null
                      : _startRecording,
                  onLongPressUp: _isBusy || !_isInitialized
                      ? null
                      : _stopRecording,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: EdgeInsets.all(_isRecording ? 12 : 8),
                    decoration: BoxDecoration(
                      color: _isRecording
                          ? Colors.redAccent
                          : Colors.grey.shade200,
                      shape: BoxShape.circle,
                      boxShadow: _isRecording
                          ? [
                              BoxShadow(
                                color: Colors.red.withOpacity(0.5),
                                blurRadius: 10,
                                spreadRadius: 2,
                              ),
                            ]
                          : [],
                    ),
                    child: Icon(
                      _isRecording ? Icons.mic : Icons.mic_none,
                      color: _isRecording
                          ? Colors.white
                          : const Color(0xFF0F766E),
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Text Field
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 5,
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: _textController,
                      enabled: !_isBusy && _isInitialized,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: _isRecording
                            ? 'Release to send...'
                            : (_isInitialized
                                  ? 'Ask about a meal...'
                                  : 'Engine loading...'),
                        hintStyle: TextStyle(
                          color: _isRecording
                              ? Colors.redAccent
                              : Colors.grey.shade400,
                        ),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // 🌟 THE DYNAMIC SEND / STOP BUTTON 🌟
                Container(
                  decoration: BoxDecoration(
                    // If busy, show Red. If ready, show your Teal Gradient.
                    gradient: _isBusy
                        ? const LinearGradient(
                            colors: [Colors.redAccent, Colors.red],
                          )
                        : const LinearGradient(
                            colors: [Color(0xFF0F766E), Color(0xFF0EA5E9)],
                          ),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    // Toggle between Send and Stop icons
                    icon: Icon(
                      _isBusy ? Icons.stop_circle_outlined : Icons.send,
                      color: Colors.white,
                    ),
                    onPressed: !_isInitialized
                        ? null
                        : (_isBusy
                              ? _stopGeneration
                              : () => _sendMessage(isVoiceNote: false)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}