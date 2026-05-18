import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/recipe.dart';
import 'recipe_stepper_card.dart';

class RecipeMenuCard extends StatelessWidget {
  final List<dynamic> matches;
  final Future<Map<String, dynamic>?> Function(String) onFetchRecipe;

  const RecipeMenuCard({
    super.key, 
    required this.matches, 
    required this.onFetchRecipe
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: matches.map((match) {
        return CollapsibleRecipeTile(
          match: match,
          onFetchRecipe: onFetchRecipe,
        );
      }).toList(),
    );
  }
}

// --- THE NEW ACCORDION TILE ---
class CollapsibleRecipeTile extends StatefulWidget {
  final dynamic match;
  final Future<Map<String, dynamic>?> Function(String) onFetchRecipe;

  const CollapsibleRecipeTile({
    super.key, 
    required this.match, 
    required this.onFetchRecipe
  });

  @override
  State<CollapsibleRecipeTile> createState() => _CollapsibleRecipeTileState();
}

class _CollapsibleRecipeTileState extends State<CollapsibleRecipeTile> {
  bool _isExpanded = false;
  bool _isLoading = false;
  bool _isSaved = false; // 🌟 Tracks if the user liked this recipe
  Map<String, dynamic>? _fullRecipeData;

  // 🌟 SAFELY extract the name without using the ?[] operator on dynamic types!
  String _getRecipeName() {
    if (widget.match is Map) {
      if (widget.match['recipe'] != null && widget.match['recipe']['name'] != null) {
        return widget.match['recipe']['name'].toString();
      } else if (widget.match['name'] != null) {
        return widget.match['name'].toString();
      }
    }
    return "Unknown Recipe";
  }

  // 🌟 THE SAVE LOGIC: Pushes the recipe to the Home Screen!
  Future<void> _saveToFavorites() async {
    if (_isSaved) return; // Prevent spam clicking

    setState(() {
      _isSaved = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final String? existingJson = prefs.getString('saved_recipes');
      List<dynamic> savedList = [];

      if (existingJson != null) {
        savedList = jsonDecode(existingJson);
      }

      // Safely grab the recipe payload to save
      Map<String, dynamic> recipeData = widget.match is Map && widget.match['recipe'] != null 
          ? widget.match['recipe'] 
          : widget.match;

      // Check for duplicates
      bool alreadySaved = savedList.any((r) => r['name'] == recipeData['name']);

      if (!alreadySaved) {
        savedList.insert(0, recipeData); // Add to the top of the list
        await prefs.setString('saved_recipes', jsonEncode(savedList));

        // Show a nice success toast!
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("${recipeData['name']} saved to your Home Screen! ❤️"),
              backgroundColor: const Color(0xFF0F766E),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint("Failed to save recipe: $e");
    }
  }

  void _toggleExpand() async {
    String recipeName = _getRecipeName();

    if (recipeName == "Unknown Recipe") return; // Failsafe

    if (!_isExpanded && _fullRecipeData == null) {
      setState(() {
        _isExpanded = true; // Arrow flips instantly!
        _isLoading = true;  // Spinner shows up!
      });

      // Fetch the exact data using the safe string
      final data = await widget.onFetchRecipe(recipeName);

      if (mounted) {
        setState(() {
          _fullRecipeData = data;
          _isLoading = false;
        });
      }
    } else {
      // Toggle it open/closed if we already fetched it
      setState(() {
        _isExpanded = !_isExpanded;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    String recipeName = _getRecipeName();

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
        side: BorderSide(color: _isExpanded ? const Color(0xFF0EA5E9) : Colors.transparent, width: 1.5),
      ),
      child: Column(
        children: [
          // 1. THE HEADER
          ListTile(
            title: Text(recipeName, style: const TextStyle(fontWeight: FontWeight.bold)),
            // 🌟 THE UPGRADED TRAILING ACTIONS
            trailing: Row(
              mainAxisSize: MainAxisSize.min, // Keeps the row tight
              children: [
                IconButton(
                  icon: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Icon(
                      _isSaved ? Icons.favorite : Icons.favorite_border,
                      key: ValueKey<bool>(_isSaved),
                      color: _isSaved ? Colors.redAccent : Colors.grey.shade400,
                      size: 24,
                    ),
                  ),
                  onPressed: _saveToFavorites,
                ),
                Icon(
                  _isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                  color: const Color(0xFF0F766E),
                ),
              ],
            ),
            onTap: _toggleExpand,
          ),

          // 2. THE DROPDOWN CONTENT
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: !_isExpanded
                ? const SizedBox.shrink()
                : _isLoading
                    ? const Padding(
                        padding: EdgeInsets.all(20.0),
                        child: Center(child: CircularProgressIndicator(color: Color(0xFF0F766E))),
                      )
                    : _fullRecipeData != null
                        ? Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
                            child: RecipeStepperCard(
                              recipe: RecipePayload.fromJson(_fullRecipeData!),
                            ),
                          )
                        : const Padding(
                            padding: EdgeInsets.all(16.0),
                            child: Text("Error loading recipe details."),
                          ),
          ),
        ],
      ),
    );
  }
}