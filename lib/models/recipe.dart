class RecipePayload {
  final String name;
  final List<String> ingredients;
  final List<String> steps;
  final Map<String, dynamic> nutrition;
  // 🌟 ADD THIS LINE:
  final List<String>? missingIngredients; 

  RecipePayload({
    required this.name,
    required this.ingredients,
    required this.steps,
    required this.nutrition,
    this.missingIngredients, // Add to constructor
  });

  // 🌟 Update your Factory to handle the incoming JSON
  factory RecipePayload.fromJson(Map<String, dynamic> json) {
  return RecipePayload(
    name: json['name'] ?? 'Unknown Recipe',
    
    // 🌟 THE FIX: Check for 'ingredients' OR 'ingredients_needed'
    ingredients: List<String>.from(json['ingredients'] ?? json['ingredients_needed'] ?? []),
    
    steps: List<String>.from(json['steps'] ?? []),
    nutrition: Map<String, dynamic>.from(json['nutrition'] ?? {}),
    missingIngredients: json['missingIngredients'] != null 
        ? List<String>.from(json['missingIngredients']) 
        : null,
  );
}
}