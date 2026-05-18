import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:shared_preferences/shared_preferences.dart'; // NEW

class GuidebookScreen extends StatefulWidget {
  final String patientProfile;

  const GuidebookScreen({super.key, required this.patientProfile});

  @override
  State<GuidebookScreen> createState() => _GuidebookScreenState();
}

class _GuidebookScreenState extends State<GuidebookScreen> {
  static const platform = MethodChannel('com.ai.litertlm/chat');
  
  String? _generatedGuide;
  bool _isGenerating = true;
  String _errorMessage = "";

  @override
  void initState() {
    super.initState();
    _loadOrGenerateGuide();
  }

  Future<void> _loadOrGenerateGuide() async {
    final prefs = await SharedPreferences.getInstance();
    
    // 1. Check what is saved on the phone
    final savedProfile = prefs.getString('saved_profile');
    final savedGuide = prefs.getString('saved_guide');

    // 2. If we have a guide AND the profile hasn't changed, load it instantly!
    if (savedGuide != null && savedProfile == widget.patientProfile) {
      setState(() {
        _generatedGuide = savedGuide;
        _isGenerating = false;
      });
      return;
    }

    // 3. Otherwise, generate a new one
    _generateEncyclopedia(prefs);
  }

  Future<void> _generateEncyclopedia(SharedPreferences prefs) async {
    final String masterPrompt = """
Based on the following patient profile, generate a comprehensive, structured dietary guide formatted in Markdown. 
Do NOT include pleasantries or conversational text. Output ONLY the guide.

Patient Profile:
${widget.patientProfile}

Structure the guide EXACTLY like this:
# My Personalized Food Guide

## 🥩 Proteins
*   **Accepted:** [List 3-5 affordable/available foods here]
*   **Forbidden:** [List foods they MUST avoid based on restrictions]

## 🍞 Carbohydrates
*   **Accepted:** [List 3-5 foods]
*   **Forbidden:** [List foods to avoid]

## 🥦 Vegetables & Fruits
*   **Accepted:** [List 3-5 foods]
*   **Forbidden:** [List foods to avoid]

## 🥛 Dairy & Fats
*   **Accepted:** [List 3-5 foods]
*   **Forbidden:** [List foods to avoid]

## ⚠️ Strict Rules to Remember
* [List 2-3 absolute rules based on their medical notes]
""";

    try {
      final String rawResponse = await platform.invokeMethod('startGeneration', {'text': masterPrompt});
      final String cleanResponse = rawResponse.replaceAll(RegExp(r'<think>.*?</think>', dotAll: true), '').trim();

      // 4. Save the new guide and the current profile so we don't have to do this again
      await prefs.setString('saved_guide', cleanResponse);
      await prefs.setString('saved_profile', widget.patientProfile);

      setState(() {
        _generatedGuide = cleanResponse;
        _isGenerating = false;
      });
    } on PlatformException catch (e) {
      setState(() {
        _errorMessage = "Failed to generate guide: ${e.message}";
        _isGenerating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Food Guide'),
        backgroundColor: Colors.teal, 
        foregroundColor: Colors.white,
        actions: [
          // NEW: A button to manually force a regeneration if they want
          if (!_isGenerating)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: "Regenerate Guide",
              onPressed: () async {
                setState(() => _isGenerating = true);
                final prefs = await SharedPreferences.getInstance();
                _generateEncyclopedia(prefs);
              },
            )
        ],
      ),
      body: _isGenerating
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  CircularProgressIndicator(color: Colors.teal),
                  SizedBox(height: 16),
                  Text("Gemma is writing your personalized encyclopedia..."),
                  Text("(This may take 15-30 seconds)", style: TextStyle(color: Colors.grey)),
                ],
              ),
            )
          : _errorMessage.isNotEmpty
              ? Center(child: Text(_errorMessage, style: const TextStyle(color: Colors.red)))
              : Markdown(
                  data: _generatedGuide ?? "No guide generated.",
                  styleSheet: MarkdownStyleSheet(
                    h1: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.teal),
                    h2: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.deepPurple),
                    p: const TextStyle(fontSize: 16, height: 1.5),
                    listBullet: const TextStyle(fontSize: 16, color: Colors.deepPurple),
                  ),
                ),
    );
  }
}