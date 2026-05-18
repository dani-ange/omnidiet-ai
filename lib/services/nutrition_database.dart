import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

class NutritionDatabase {
  // Singleton pattern ensuring the database loads into RAM exactly once
  static final NutritionDatabase _instance = NutritionDatabase._internal();
  factory NutritionDatabase() => _instance;
  NutritionDatabase._internal();

  List<dynamic> _crops = [];
  List<dynamic> _recipes = [];
  bool _isLoaded = false;

  /// Call this inside main.dart before runApp() to boot the data pool
  Future<void> init() async {
    if (_isLoaded) return;
    try {
      // Load raw JSON strings from the Flutter Asset Bundle
      final cropsJson = await rootBundle.loadString('assets/african_crops.json');
      _crops = jsonDecode(cropsJson);
      
      final recipesJson = await rootBundle.loadString('assets/african_recipes.json');
      _recipes = jsonDecode(recipesJson);
      
      _isLoaded = true;
      debugPrint("✅ Nutrition Database initialized successfully.");
    } catch (e) {
      debugPrint("❌ Critical: Failed to load Nutrition Database: $e");
    }
  }

  /// 🌟 THE AGILE OMNI-SEARCH ENGINE
  /// Accepts a clean array of normalized food items from your AI model 
  /// and automatically extracts full nutritional breakdowns.
  String getAgileFacts(List<String> searchTerms) {
    if (!_isLoaded) return "Database not initialized.";
    
    String masterFacts = "";
    List<String> unknownEntities = [];

    for (String term in searchTerms) {
      String query = term.toLowerCase().trim();
      bool found = false;

      // STEP 1: Scan Cooked Dishes Matrix (e.g., "Ndole", "Egusi Soup")
      for (var recipe in _recipes) {
        if (recipe['name'].toString().toLowerCase().contains(query)) {
          masterFacts += "\n🍲 [COOKED DISH]: ${recipe['name']}\n";
          
          if (recipe['nutrition'] != null) {
            var macro = recipe['nutrition'];
            masterFacts += "  - Target Performance Profile: Calories: ${macro['Calories']}, Protein: ${macro['Protein']}, Carbs: ${macro['Carbs']}, Fat: ${macro['Fat']}\n";
          }
          
          masterFacts += "  - Structural Constituent Raw Ingredients:\n";
          List<dynamic> targetIngredients = recipe['ingredients_needed'] ?? [];
          
          // Deep cross-reference to pull raw macro constraints for each sub-ingredient
          String subIngredientBreakdown = _getRawCropFactsOnly(targetIngredients.map((e) => e.toString()).toList());
          masterFacts += subIngredientBreakdown.split('\n').map((line) => '      $line').join('\n');
          
          found = true;
          break; 
        }
      }

      // STEP 2: If no dish matched, look for Raw Staple Staples (e.g., "Cassava", "Yam")
      if (!found) {
        for (var crop in _crops) {
          String mainName = crop['name'].toString().toLowerCase();
          List<dynamic> aliases = crop['aliases'] ?? [];

          if (mainName.contains(query) || aliases.any((a) => a.toString().toLowerCase().contains(query))) {
            masterFacts += "\n🌾 [RAW INGREDIENT]: ${crop['name']}\n";
            masterFacts += "  - Reference Metrics (per 100g): ${crop['calories']} kcal, Carbs: ${crop['carbs']}, Protein: ${crop['protein']}, Fat: ${crop['fat']}\n";
            found = true;
            break; 
          }
        }
      }

      if (!found) {
        unknownEntities.add(term);
      }
    }

    if (unknownEntities.isNotEmpty) {
      masterFacts += "\n⚠️ [UNKNOWN ENTITIES]: ${unknownEntities.join(', ')} (No explicit DB references. AI engine must evaluate with adaptive safe parameters).\n";
    }

    return masterFacts;
  }

  /// 🍳 KITCHEN CHEF FILTER: Scoring algorithm matching available ingredients to local recipes
  List<Map<String, dynamic>> findMatchingRecipes(List<String> availableIngredients, {int limit = 3}) {
    if (!_isLoaded) return [];

    List<String> userIngs = availableIngredients.map((e) => e.toLowerCase().trim()).toList();
    List<Map<String, dynamic>> scoringMatrix = [];

    for (var recipe in _recipes) {
      List<dynamic> neededRaw = recipe['ingredients_needed'] ?? [];
      List<String> needed = neededRaw.map((e) => e.toString().toLowerCase().trim()).toList();
      
      int intersectionCount = 0;
      List<String> missingItems = [];

      for (var ingredient in needed) {
        bool containsMatch = userIngs.any((userIng) => ingredient.contains(userIng) || userIng.contains(ingredient));
        if (containsMatch) {
          intersectionCount++;
        } else {
          missingItems.add(ingredient);
        }
      }

      if (intersectionCount > 0) {
        scoringMatrix.add({
          'recipe': recipe,
          'score': intersectionCount / needed.length,
          'missing': missingItems,
        });
      }
    }

    // Rank matching results by highest ingredient convergence density
    scoringMatrix.sort((a, b) => b['score'].compareTo(a['score']));
    return scoringMatrix.take(limit).toList();
  }

  /// Private internal utility for generating structural crop strings recursively
  String _getRawCropFactsOnly(List<String> ingredients) {
    String output = "";
    for (String item in ingredients) {
      String cleanItem = item.toLowerCase().trim();
      bool resolved = false;

      for (var crop in _crops) {
        String cropName = crop['name'].toString().toLowerCase();
        List<dynamic> aliases = crop['aliases'] ?? [];

        if (cropName.contains(cleanItem) || aliases.any((a) => a.toString().toLowerCase().contains(cleanItem))) {
          output += "- ${crop['name']}: ${crop['calories']} kcal (C: ${crop['carbs']}, P: ${crop['protein']}, F: ${crop['fat']})\n";
          resolved = true;
          break;
        }
      }
      if (!resolved) {
        output += "- $item: Macro data aggregated under generalized compound values.\n";
      }
    }
    return output;
  }
}