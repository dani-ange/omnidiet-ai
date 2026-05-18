import 'dart:io'; 
import 'dart:convert'; 
import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'dart:math' as math;

import '../models/chat_message.dart';
import '../services/nutrition_database.dart';
import '../profile_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

enum Intent { recipeSingle, recipeList, nutritionEducation, generalConversational }

class _ChatScreenState extends State<ChatScreen> {
  static const platform = MethodChannel('com.ai.litertlm/chat');
  static const streamChannel = EventChannel('com.ai.litertlm/stream');

  final List<ChatMessage> _messages = [];
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FlutterTts _flutterTts = FlutterTts();
  final ImagePicker _picker = ImagePicker();

  bool _isInitialized = false;
  bool _isBusy = false;
  String? _patientProfilePrompt;
  String? _synchronizedUserName;
  StreamSubscription? _streamSubscription;

  // 🌟 IMAGE PREVIEW STAGING VARIABLES
  String? _stagedImagePath;

  @override
  void initState() {
    super.initState();
    _bootstrapChatEngine();
  }

  Future<void> _bootstrapChatEngine() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      _synchronizedUserName = prefs.getString('user_name') ?? "Danielle";
      _patientProfilePrompt = prefs.getString('saved_profile') ?? "No specific dietary restrictions.";

      await _flutterTts.setLanguage("en-US");
      await _flutterTts.setSpeechRate(0.5);

      final reply = await platform.invokeMethod('initModel', {'killSessions': true});
      debugPrint("Native Engine Response: $reply");

      setState(() {
        _isInitialized = true;
      });
      
      await _loadChatHistory();
    } catch (e) {
      setState(() {
        _messages.add(ChatMessage(
          id: 'error_init',
          text: "System could not initialize local model files. Please verify system setup path parameters.",
          isUser: false,
          timestamp: DateTime.now(),
        ));
      });
    }
  }

  Future<void> _loadChatHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? historyJson = prefs.getString('serialized_chat_history');
      
      setState(() {
        _messages.clear();
        if (historyJson != null) {
          final List<dynamic> decoded = jsonDecode(historyJson);
          _messages.addAll(decoded.map((m) => ChatMessage.fromMap(m)).toList());
        } else {
          _messages.add(ChatMessage(
            id: 'welcome',
            text: "Hello $_synchronizedUserName! Welcome to the OmniDiet Educational Hub. Ask me any informational, food safety, or metabolic health questions to explore your detailed evaluation today.",
            isUser: false,
            timestamp: DateTime.now(),
          ));
        }
      });
      _scrollToBottom();
    } catch (e) {
      debugPrint("Cache read failure: $e");
    }
  }

  Future<void> _saveChatHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<Map<String, dynamic>> encoded = _messages.map((m) => m.toMap()).toList();
      await prefs.setString('serialized_chat_history', jsonEncode(encoded));
    } catch (e) {
      debugPrint("Cache write failure: $e");
    }
  }

  @override
  void dispose() {
    _streamSubscription?.cancel();
    _textController.dispose();
    _scrollController.dispose();
    _flutterTts.stop();
    super.dispose();
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

  Intent _classifyIntentLocally(String text) {
    final clean = text.toLowerCase();
    if (clean.contains('recipe') || clean.contains('cook') || clean.contains('prepare') || clean.contains('how to make')) {
      return clean.contains('plan') || clean.contains('list') ? Intent.recipeList : Intent.recipeSingle;
    }
    if (clean.contains('why') || clean.contains('what is') || clean.contains('vitamin') || clean.contains('sugar') || clean.contains('diabetic') || clean.contains('can i eat') || clean.contains('should i avoid')) {
      return Intent.nutritionEducation;
    }
    return Intent.generalConversational;
  }

  Future<void> _sendMessage() async {
    String actualTextPrompt = _textController.text.trim();
    // Allow sending if there's text OR if there's a staged image path present
    if (actualTextPrompt.isEmpty && _stagedImagePath == null) return;

    final String? imagePathToPass = _stagedImagePath;
    _textController.clear();
    
    // Clear the visual preview staging state cleanly before processing begins
    setState(() {
      _stagedImagePath = null;
      _isBusy = true;
    });

    final userMessageId = DateTime.now().millisecondsSinceEpoch.toString();

    setState(() {
      _messages.add(ChatMessage(
        id: userMessageId,
        text: actualTextPrompt.isEmpty ? "Analyzed Image Context" : actualTextPrompt,
        isUser: true,
        timestamp: DateTime.now(),
        imagePath: imagePathToPass,
      ));
    });
    _scrollToBottom();

    final Intent intent = _classifyIntentLocally(actualTextPrompt);
    String recipeContextPayload = "";

    // ===========================================================================
    // 🧠 FIRST PASS: Programmatic Upfront AI Ingredient/Entity Extraction
    // ===========================================================================
    String parsingPrompt = """
Analyze the user input. Extract any raw food ingredients, crops, or specific dish names mentioned that have real culinary or nutritional value.
User Input: $actualTextPrompt

Convert them into a comma-separated list of formal, singular, lowercase English names.
If nothing of value is found, return the word "none".
Output ONLY the comma-separated list. Do not write sentences or explanations.""";

    try {
      final parseReply = await platform.invokeMethod('generateOnce', {
        'text': parsingPrompt,
        'imagePath': imagePathToPass,
        'audioPath': null,
      });

      String aiParsedEntities = parseReply?.toString().trim() ?? "none";
      debugPrint("🤖 AI Universally Parsed Entities: $aiParsedEntities");

      if (aiParsedEntities.toLowerCase() != "none" && aiParsedEntities.isNotEmpty) {
        List<String> normalizedEntities = aiParsedEntities
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();

        final NutritionDatabase db = NutritionDatabase();
        String agileFacts = db.getAgileFacts(normalizedEntities);

        if (agileFacts.trim().isNotEmpty) {
          recipeContextPayload = agileFacts;
        }
      }
    } catch (e) {
      debugPrint("Upfront AI entity extraction pass bypassed or failed: $e");
    }

    // =========================================================================
    // 🧠 SECOND PASS: HIGHLY PROACTIVE EDUCATIONAL ENGINE
    // =========================================================================
    String contextualPrompt = "";

    if (intent == Intent.nutritionEducation || intent == Intent.recipeSingle || intent == Intent.recipeList) {
      contextualPrompt = """
Persona: You are an expert educational nutrition and metabolic health specialist.
Style: Thorough, proactive and Explain the scientific,  practical reasoning behind food interactions simply without theatrical language for a commom user to understand it simply.

Inputs:
- User Health Query: $actualTextPrompt

[VERIFIED LOCAL CROP NUTRITION DATABASE REFERENCE]
Use these parameters as your baseline numerical data layer. If an item is missing from this list, use your full internal global parametric memory:
$recipeContextPayload

[USER HEALTH PROFILE]
$_patientProfilePrompt

Proactive Clinical Instruction:
You must be highly proactive. Whenever the user asks about a food, a diet, or a health condition, automatically cross-reference it with their [USER HEALTH PROFILE]. Do not wait for them to explicitly ask how it affects their specific condition. Assume they want to know how it impacts *them*.

Safety Filter:
If ingredients contain non-food items, dangerous chemicals, or objects with no global culinary value, explain politely in text that these items are not edible and refuse to evaluate further.

Detailed Output Structure Requirements:
1. Direct Application to Profile: Address the user directly as $_synchronizedUserName. Explain exactly how the queried food or condition interacts with the specific restrictions and goals in their [USER HEALTH PROFILE]. Do not refer to them as "the user" or if addressing a third person.

""";
    } 
    else {
      contextualPrompt = """
Persona: You are OmniDiet Chef. You are a helpful, practical nutrition assistant.
Style: Concise, friendly. Provide proactive, conversational guidance based on the user's profile.

Inputs:
- User Input: $actualTextPrompt

[USER HEALTH PROFILE]
$_patientProfilePrompt

Task:
Respond directly to the user $_synchronizedUserName. Acknowledge their health profile proactively, and guide them toward exploring detailed educational food evaluations or utilizing the Kitchen Module to compile a structured meal strategy. Do not refer to them in the third person.""";
    }

    final aiMessageId = (DateTime.now().millisecondsSinceEpoch + 1).toString();
    setState(() {
      _messages.add(ChatMessage(
        id: aiMessageId,
        text: "",
        isUser: false,
        timestamp: DateTime.now(),
      ));
    });

    String accumulatedText = "";

    try {
      await _streamSubscription?.cancel();
      await platform.invokeMethod('startGeneration', {
        'text': contextualPrompt,
        'imagePath': imagePathToPass,
        'audioPath': null,
      });

      _streamSubscription = streamChannel.receiveBroadcastStream().listen((dynamic event) {
        final Map<dynamic, dynamic> map = event;
        final String type = map['type'] ?? '';

        if (type == 'token') {
          final String token = map['content'] ?? '';
          accumulatedText += token;

          final int idx = _messages.indexWhere((m) => m.id == aiMessageId);
          if (idx != -1) {
            setState(() {
              _messages[idx] = _messages[idx].copyWith(text: accumulatedText);
            });
            _scrollToBottom();
          }
        } 
        else if (type == 'done') {
          setState(() { _isBusy = false; });
          _streamSubscription?.cancel();

          () async {
            String cleanResponse = accumulatedText
                .replaceAll(RegExp(r'<think>.*?</think>', dotAll: true), '')
                .trim();

            if (cleanResponse.startsWith('```json')) {
              cleanResponse = cleanResponse.replaceAll('```json', '').replaceAll('```', '').trim();
            }

            final int index = _messages.indexWhere((m) => m.id == aiMessageId);
            if (index != -1) {
              String optionalSourcesText = recipeContextPayload
                  .replaceAll("[VERIFIED LOCAL DATABASE REFERENCE DATA]:", "")
                  .trim();

              setState(() {
                _messages[index] = _messages[index].copyWith(
                  text: cleanResponse,
                  type: MessageType.text, 
                  sourcesRawText: optionalSourcesText.isNotEmpty ? optionalSourcesText : null,
                );
              });
            }
            
            await _flutterTts.speak(cleanResponse.replaceAll(RegExp(r'[*#_~`>]'), ''));
            await _saveChatHistory();
          }();
        }
      }, onError: (err) {
        _handleChatError(aiMessageId, "Stream channel dropped connection: $err");
      });

    } catch (e) {
      _handleChatError(aiMessageId, "Native model initialization call failed: $e");
    }
  }

  void _handleChatError(String messageId, String errorText) {
    setState(() {
      _isBusy = false;
      final idx = _messages.indexWhere((m) => m.id == messageId);
      if (idx != -1) {
        _messages[idx] = _messages[idx].copyWith(text: "Error: $errorText");
      }
    });
  }

  Future<void> _stopGeneration() async {
    try {
      await platform.invokeMethod('cancelGeneration');
      _streamSubscription?.cancel();
      setState(() { _isBusy = false; });
    } catch (e) {
      debugPrint("Cancellation exception: $e");
    }
  }

  Future<void> _clearConversationHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('serialized_chat_history');
    setState(() {
      _messages.clear();
      _messages.add(ChatMessage(
        id: 'welcome_reset',
        text: "Hub history wiped out cleanly. Ready for your next global health target strategy evaluation!",
        isUser: false,
        timestamp: DateTime.now(),
      ));
    });
  }

  Future<void> _pickImage(ImageSource source) async {
    final XFile? img = await _picker.pickImage(source: source, maxWidth: 512, maxHeight: 512, imageQuality: 60);
    if (img != null) {
      // 🌟 STAGE FOR PREVIEW instead of instantly dispatching message chains
      setState(() {
        _stagedImagePath = img.path;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text("OmniDiet Hub", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        actions: [
          IconButton(icon: const Icon(Icons.delete_sweep, color: Colors.white), onPressed: _clearConversationHistory),
          IconButton(
            icon: const Icon(Icons.person_pin_outlined, color: Colors.white),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const ProfileScreen(isFirstTime: false))).then((_) {
              SharedPreferences.getInstance().then((prefs) {
                setState(() {
                  _synchronizedUserName = prefs.getString('user_name') ?? "Danielle";
                  _patientProfilePrompt = prefs.getString('saved_profile') ?? "No specific dietary restrictions.";
                });
              });
            }),
          ),
        ],
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [Color(0xFF0F766E), Color(0xFF0EA5E9)]),
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, idx) {
                final msg = _messages[idx];
                return _buildChatBubble(msg);
              },
            ),
          ),
          if (_isBusy)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8.0),
              child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0F766E))),
            ),
          // 🌟 INJECTED INTERACTIVE PREVIEW SHELF OVERLAY PANEL
          if (_stagedImagePath != null) _buildImagePreviewShelf(),
          _buildInputBarPanel(),
        ],
      ),
    );
  }

  Widget _buildChatBubble(ChatMessage msg) {
    final isUser = msg.isUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(14),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
        decoration: BoxDecoration(
          color: isUser ? const Color(0xFF0F766E) : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: isUser ? const Radius.circular(16) : const Radius.circular(0),
            bottomRight: isUser ? const Radius.circular(0) : const Radius.circular(16),
          ),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (msg.imagePath != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.file(File(msg.imagePath!), height: 160, fit: BoxFit.cover)),
              ),
            MarkdownBody(
              data: msg.text.isEmpty ? "Thinking..." : msg.text,
              selectable: true,
              styleSheet: MarkdownStyleSheet(
                p: TextStyle(fontSize: 15, height: 1.45, color: isUser ? Colors.white : const Color(0xFF334155)),
                listBullet: TextStyle(color: isUser ? Colors.white70 : const Color(0xFF0F766E)),
                h1: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isUser ? Colors.white : const Color(0xFF0F766E)),
                h2: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isUser ? Colors.white70 : const Color(0xFF0EA5E9)),
              ),
            ),
            
            if (msg.sourcesRawText != null)
              Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      color: Colors.amber.shade50.withOpacity(0.6),
                      child: ExpansionTile(
                        initiallyExpanded: false, 
                        iconColor: Colors.amber.shade900,
                        collapsedIconColor: Colors.amber.shade800,
                        leading: Icon(Icons.analytics_outlined, color: Colors.amber.shade900, size: 20),
                        title: Text(
                          "Grounded Nutritional References",
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.amber.shade900),
                        ),
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(left: 16.0, right: 16.0, bottom: 12.0),
                            child: Align(
                              alignment: Alignment.topLeft,
                              child: Text(
                                msg.sourcesRawText!,
                                style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.amber.shade900, height: 1.4),
                              ),
                            ),
                          )
                        ],
                      ),
                    ),
                  ),
                ),
              )
          ],
        ),
      ),
    );
  }

  Widget _buildImagePreviewShelf() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, -2))],
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              File(_stagedImagePath!),
              width: 55,
              height: 55,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Image Selected",
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                ),
                Text(
                  "Type context or comments in the bar below...",
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
          IconButton(
            icon: CircleAvatar(
              radius: 12,
              backgroundColor: Colors.red.shade50,
              child: Icon(Icons.close, size: 14, color: Colors.red.shade600),
            ),
            onPressed: () => setState(() => _stagedImagePath = null),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBarPanel() {
    return Container(
      padding: const EdgeInsets.all(12),
      color: Colors.white,
      child: SafeArea(
        child: Row(
          children: [
            IconButton(
              icon: Icon(
                Icons.add_photo_alternate_outlined, 
                color: _isBusy ? Colors.grey.shade400 : const Color(0xFF0F766E),
              ), 
              onPressed: _isBusy ? null : () => _pickImage(ImageSource.gallery),
            ),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(24)),
                child: TextField(
                  controller: _textController,
                  enabled: _isInitialized && !_isBusy,
                  decoration: InputDecoration(
                    hintText: _isInitialized ? "Ask OmniDiet Hub..." : "Warming up local AI...",
                    border: InputBorder.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              decoration: BoxDecoration(
                gradient: _isBusy
                    ? const LinearGradient(colors: [Colors.redAccent, Colors.red])
                    : const LinearGradient(colors: [Color(0xFF0F766E), Color(0xFF0EA5E9)]),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: Icon(_isBusy ? Icons.stop_circle_outlined : Icons.send, color: Colors.white),
                onPressed: !_isInitialized ? null : (_isBusy ? _stopGeneration : () => _sendMessage()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}