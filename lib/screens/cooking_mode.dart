
import 'package:flutter/material.dart';
import '../models/recipe.dart'; // Make sure to import your model!

class CookingModeScreen extends StatefulWidget {
  final RecipePayload recipe;
  const CookingModeScreen({super.key, required this.recipe});

  @override
  State<CookingModeScreen> createState() => _CookingModeScreenState();
}

class _CookingModeScreenState extends State<CookingModeScreen> {
  int _currentStep = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Dark focus mode
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text("Cooking Mode", style: TextStyle(color: Colors.white)),
        leading: IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
      ),
      body: Column(
        children: [
          LinearProgressIndicator(
            value: (_currentStep + 1) / widget.recipe.steps.length,
            backgroundColor: Colors.white10,
            color: const Color(0xFF2DD4BF),
          ),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(30.0),
                child: Text(
                  widget.recipe.steps[_currentStep],
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 28, color: Colors.white, fontWeight: FontWeight.w500, height: 1.4),
                ),
              ),
            ),
          ),
          _buildNavigation()
        ],
      ),
    );
  }

  Widget _buildNavigation() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 50, left: 20, right: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (_currentStep > 0)
            ElevatedButton(onPressed: () => setState(() => _currentStep--), child: const Text("PREVIOUS"))
          else const SizedBox(width: 100),
          
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0EA5E9)),
            onPressed: () {
              if (_currentStep < widget.recipe.steps.length - 1) {
                setState(() => _currentStep++);
              } else {
                Navigator.pop(context); // Finish
              }
            },
            child: Text(_currentStep == widget.recipe.steps.length - 1 ? "FINISH" : "NEXT STEP"),
          ),
        ],
      ),
    );
  }
}