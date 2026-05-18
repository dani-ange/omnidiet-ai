import 'package:flutter/material.dart';
import '../models/recipe.dart';
import '../screens/cooking_mode.dart'; // Make sure to import your model!

class RecipeStepperCard extends StatefulWidget {
  final RecipePayload recipe;
  const RecipeStepperCard({super.key, required this.recipe});

  @override
  State<RecipeStepperCard> createState() => _RecipeStepperCardState();
}

class _RecipeStepperCardState extends State<RecipeStepperCard> {
  int _currentStep = 0;
  final PageController _pageController = PageController();

  // The total pages = 1 (Ingredients page) + Number of steps
  int get _totalPages => 1 + widget.recipe.steps.length;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF0EA5E9).withOpacity(0.3)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15, offset: const Offset(0, 5))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // HEADER
          Row(
            children: [
              const Icon(Icons.restaurant_menu, color: Color(0xFF0F766E)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.recipe.name,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF1E293B)),
                ),
              ),
            ],
          ),
          const Divider(height: 24, color: Colors.black12),
          
          // THE SWIPEABLE CONTENT
          SizedBox(
            height: 280, // Fixed height so the UI doesn't jump around
            child: PageView.builder(
              controller: _pageController,
              onPageChanged: (index) => setState(() => _currentStep = index),
              itemCount: _totalPages,
              itemBuilder: (context, index) {
                
                // PAGE 0: THE INGREDIENT CHECKLIST
                if (index == 0) {
                  return _buildIngredientPage();
                }
                
                // PAGES 1+: THE COOKING STEPS
                final stepIndex = index - 1;
                return _buildStepPage(stepIndex, widget.recipe.steps[stepIndex]);
              },
            ),
          ),

          const Divider(height: 24, color: Colors.black12),

 // PROGRESS & NAVIGATION FOOTER
Row(
  mainAxisAlignment: MainAxisAlignment.spaceBetween,
  children: [
    // Back Button
    IconButton(
      icon: Icon(Icons.arrow_back_ios, size: 16, color: _currentStep > 0 ? const Color(0xFF0F766E) : Colors.grey.shade300),
      onPressed: _currentStep > 0 ? () => _pageController.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.ease) : null,
    ),
    
    // 🌟 THE FIX: Wrap the dots in an Expanded and FittedBox
    Expanded(
      child: FittedBox(
        fit: BoxFit.scaleDown, // This shrinks the dots safely if they get too wide!
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center, // Center the dots
          children: List.generate(_totalPages, (index) {
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: _currentStep == index ? 20 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: _currentStep == index ? const Color(0xFF0EA5E9) : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(4),
              ),
            );
          }),
        ),
      ),
    ),
    
    // Forward Button
    IconButton(
      icon: Icon(Icons.arrow_forward_ios, size: 16, color: _currentStep < _totalPages - 1 ? const Color(0xFF0F766E) : Colors.grey.shade300),
      onPressed: _currentStep < _totalPages - 1 ? () => _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.ease) : null,
    ),
  ],
),
        ],
      ),
    );
  }

  // --- UI HELPER: INGREDIENTS PAGE ---
  // --- UI HELPER: INGREDIENTS PAGE ---
Widget _buildIngredientPage() {
  return SingleChildScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
// 🌟 PLACE IT HERE (Top of the Column)
        if (widget.recipe.missingIngredients != null && widget.recipe.missingIngredients!.isNotEmpty)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "Missing: ${widget.recipe.missingIngredients!.join(', ')}",
                    style: TextStyle(
                      color: Colors.orange.shade900,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),

        const Text("Prep Checklist", 
          style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0EA5E9))),
        const SizedBox(height: 12),
        ...widget.recipe.ingredients.map((ingredient) => Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.check_circle_outline, size: 18, color: Color(0xFF0F766E)),
              const SizedBox(width: 8),
              // Expanded prevents right overflow if ingredient text is long
              Expanded(child: Text(ingredient, 
                style: const TextStyle(color: Color(0xFF334155), height: 1.3))),
            ],
          ),
        )).toList(),
        const SizedBox(height: 12),
        
        // Macros Tag
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: Colors.teal.shade50, borderRadius: BorderRadius.circular(8)),
          child: Text(
            "Macros: ${widget.recipe.nutrition['Calories']} kcal • ${widget.recipe.nutrition['Protein']} Protein",
            style: const TextStyle(fontSize: 12, color: Color(0xFF0F766E), fontWeight: FontWeight.bold),
          ),
        ),

        const SizedBox(height: 20),

        // 🌟 MOVED START COOKING BUTTON HERE 🌟
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F766E),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.play_circle_fill, color: Colors.white),
            label: const Text("START COOKING", 
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => CookingModeScreen(recipe: widget.recipe)),
              );
            },
          ),
        ),
      ],
    ),
  );
}

// --- UI HELPER: STEP PAGE (CLEANED UP) ---
Widget _buildStepPage(int stepIndex, String instruction) {
  return Center(
    child: SingleChildScrollView(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF0EA5E9).withOpacity(0.1), 
              borderRadius: BorderRadius.circular(20)
            ),
            child: Text("STEP ${stepIndex + 1}", 
              style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0EA5E9), letterSpacing: 1.5)),
          ),
          const SizedBox(height: 20),
          Text(
            instruction,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, color: Color(0xFF1E293B), height: 1.5),
          ),
          // 🗑️ BUTTON REMOVED FROM HERE
        ],
      ),
    ),
  );
}
}