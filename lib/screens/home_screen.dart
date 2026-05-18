import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 🌟 YOUR APP MODULES & SCREENS
import 'chat_screen.dart';
import 'kitchen_chef_screen.dart';
import '../profile_screen.dart'; 
import '../guidebook_screen.dart'; 
import 'plate_analyzer_screen.dart';
import '../models/recipe.dart';
import '../widgets/recipe_stepper_card.dart';

class HomeScreen extends StatefulWidget {
  final String userName;
  const HomeScreen({super.key, required this.userName});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _dailyFact = "Loading your daily nutrition fact...";
  List<Map<String, dynamic>> _savedRecipes = [];
  String? _patientProfilePrompt; 
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    final prefs = await SharedPreferences.getInstance();
    
    final String? recipesJson = prefs.getString('saved_recipes');
    if (recipesJson != null) {
      final List<dynamic> decoded = jsonDecode(recipesJson);
      _savedRecipes = List<Map<String, dynamic>>.from(decoded);
    } else {
      _savedRecipes = [];
    }

    _patientProfilePrompt = prefs.getString('saved_profile');

    String today = DateTime.now().toIso8601String().substring(0, 10); 
    String? lastFactDate = prefs.getString('fact_date');

    if (lastFactDate != today) {
      try {
        final String response = await rootBundle.loadString('assets/african_crops.json');
        final List<dynamic> crops = jsonDecode(response);
        
        final random = Random();
        final crop = crops[random.nextInt(crops.length)];
        
        String newFact = "💡 Did you know? 100g of ${crop['name']} provides ${crop['protein']} of protein and only ${crop['calories']} calories. A great local superfood!";
        
        await prefs.setString('fact_date', today);
        await prefs.setString('daily_fact', newFact);
        _dailyFact = newFact;
      } catch (e) {
        _dailyFact = "💡 Did you know? Baobab fruit contains 6x more Vitamin C than oranges!";
      }
    } else {
      _dailyFact = prefs.getString('daily_fact') ?? "Stay healthy today!";
    }

    setState(() { _isLoading = false; });
  }

  // ===========================================================================
  // 🗑️ CENTRALIZED DELETE ENGINE
  // ===========================================================================
  Future<void> _confirmAndDeleteRecipe(Map<String, dynamic> targetItem) async {
    final String itemName = targetItem['name'] ?? 'Saved Strategy';
    final bool isPlan = targetItem['isMealPlan'] == true;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.delete_sweep_rounded, color: Colors.redAccent, size: 24),
            const SizedBox(width: 8),
            Text(isPlan ? "Delete Meal Plan?" : "Delete Recipe?"),
          ],
        ),
        content: Text(
          "Are you sure you want to completely remove '$itemName' from your dashboard items? This cannot be undone.",
          style: const TextStyle(color: Color(0xFF475569), fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel", style: TextStyle(color: Colors.blueGrey, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              try {
                final prefs = await SharedPreferences.getInstance();
                
                setState(() {
                  _savedRecipes.removeWhere((element) => element['name'] == targetItem['name']);
                });

                await prefs.setString('saved_recipes', jsonEncode(_savedRecipes));
                
                if (context.mounted) {
                  Navigator.pop(context); 
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text("🗑️ Successfully deleted '$itemName'"),
                      backgroundColor: Colors.redAccent,
                    ),
                  );
                }
              } catch (e) {
                debugPrint("Delete task error: $e");
              }
            },
            child: const Text("Delete", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildSideDrawer(BuildContext context) {
    return Drawer(
      backgroundColor: const Color(0xFF0F172A), 
      child: Column(
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xFF0F766E), Color(0xFF0EA5E9)])),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircleAvatar(radius: 35, backgroundColor: Colors.white24, child: Icon(Icons.person, color: Colors.white, size: 40)),
                  const SizedBox(height: 10),
                  Text(widget.userName, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                ListTile(
                  leading: const Icon(Icons.health_and_safety, color: Color(0xFF2DD4BF)),
                  title: const Text("Health Profile", style: TextStyle(color: Colors.white70)),
                  subtitle: const Text("Edit allergies & restrictions", style: TextStyle(color: Colors.white38, fontSize: 11)),
                  onTap: () async {
                    Navigator.pop(context);
                    await Navigator.push(context, MaterialPageRoute(builder: (context) => const ProfileScreen()));
                    _loadDashboardData(); 
                  },
                ),
                const Divider(color: Colors.white12),
                ListTile(
                  leading: const Icon(Icons.menu_book, color: Color(0xFF0EA5E9)),
                  title: const Text("Dietary Guidebook", style: TextStyle(color: Colors.white70)),
                  subtitle: const Text("Read clinical nutrition rules", style: TextStyle(color: Colors.white38, fontSize: 11)),
                  onTap: () {
                    Navigator.pop(context);
                    if (_patientProfilePrompt == null || _patientProfilePrompt!.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please set up your profile first to unlock the Guidebook!")));
                      return;
                    }
                    Navigator.push(context, MaterialPageRoute(builder: (context) => GuidebookScreen(patientProfile: _patientProfilePrompt!)));
                  },
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white24),
          ListTile(leading: const Icon(Icons.logout, color: Colors.redAccent), title: const Text("Log Out", style: TextStyle(color: Colors.white70)), onTap: () {}),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9), 
      drawer: _buildSideDrawer(context), 
      body: CustomScrollView(
        slivers: [
          _buildPremiumAppBar(),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildChatCTA(context), 
                  const SizedBox(height: 16),
                  
                  GestureDetector(
                    onTap: () async {
                      await Navigator.push(context, MaterialPageRoute(builder: (context) => const KitchenChefScreen()));
                      _loadDashboardData();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFF0F766E), Color(0xFF115E59)]),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [BoxShadow(color: const Color(0xFF0F766E).withOpacity(0.2), blurRadius: 10, offset: const Offset(0, 4))],
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.soup_kitchen, color: Color(0xFF2DD4BF), size: 24),
                          const SizedBox(width: 12),
                          const Expanded(child: Text("Launch Kitchen Chef Wizard", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15))),
                          Icon(Icons.arrow_forward_ios, size: 12, color: Colors.white.withOpacity(0.8)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  GestureDetector(
                    onTap: () async {
                      await Navigator.push(context, MaterialPageRoute(builder: (context) => const PlateAnalyzerScreen()));
                      _loadDashboardData();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFF0EA5E9), Color(0xFF0369A1)]), 
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [BoxShadow(color: const Color(0xFF0EA5E9).withOpacity(0.2), blurRadius: 10, offset: const Offset(0, 4))],
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.restaurant, color: Colors.white, size: 24),
                          const SizedBox(width: 12),
                          const Expanded(child: Text("Launch Plate Analyzer", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15))),
                          Icon(Icons.arrow_forward_ios, size: 12, color: Colors.white.withOpacity(0.8)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Your Saved Strategies", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF1E293B), letterSpacing: -0.5)),
                      if (_savedRecipes.isNotEmpty)
                        Text("${_savedRecipes.length} saved", style: const TextStyle(color: Color(0xFF0F766E), fontWeight: FontWeight.bold, fontSize: 13)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildSavedRecipesCarousel(),
                  
                  const SizedBox(height: 32),
                  const Text("Today's Nutrition Fact", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF1E293B), letterSpacing: -0.5)),
                  const SizedBox(height: 16),
                  _buildFactCard(),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPremiumAppBar() {
    return SliverAppBar(
      expandedHeight: 140,
      floating: false,
      pinned: true,
      elevation: 0,
      backgroundColor: const Color(0xFF0F766E),
      iconTheme: const IconThemeData(color: Colors.white), 
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.only(left: 48, bottom: 16), 
        title: Text("Welcome back,\n${widget.userName}", style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white, fontSize: 18, height: 1.2)),
        background: Stack(
          fit: StackFit.expand,
          children: [
            Container(decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF0F766E), Color(0xFF0EA5E9)]))),
            Positioned(right: -50, top: -50, child: CircleAvatar(radius: 100, backgroundColor: Colors.white.withOpacity(0.05))),
          ],
        ),
      ),
      actions: [
        IconButton(icon: const Icon(Icons.person, color: Colors.white), onPressed: () => Scaffold.of(context).openDrawer()),
      ],
    );
  }

  Widget _buildChatCTA(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        await Navigator.push(context, MaterialPageRoute(builder: (context) => const ChatScreen()));
        _loadDashboardData(); 
      },
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [BoxShadow(color: const Color(0xFF0EA5E9).withOpacity(0.1), blurRadius: 20, offset: const Offset(0, 10))],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFF0EA5E9).withOpacity(0.1), shape: BoxShape.circle),
              child: const Icon(Icons.auto_awesome, color: Color(0xFF0EA5E9), size: 28),
            ),
            const SizedBox(width: 16),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Ask Gemma AI", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Color(0xFF1E293B))),
                  SizedBox(height: 4),
                  Text("Scan food or plan your next meal", style: TextStyle(color: Colors.blueGrey, fontSize: 13)),
                ],
              ),
            ),
            Container(padding: const EdgeInsets.all(8), decoration: const BoxDecoration(color: Color(0xFF0F766E), shape: BoxShape.circle), child: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.white)),
          ],
        ),
      ),
    );
  }

  Widget _buildSavedRecipesCarousel() {
    if (_isLoading) return const Center(child: CircularProgressIndicator(color: Color(0xFF0F766E)));
    if (_savedRecipes.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.grey.shade200)),
        child: Column(
          children: [
            Icon(Icons.bookmark_border, size: 40, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            const Text("No saved recipes yet", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
          ],
        ),
      );
    }

    return SizedBox(
      height: 165,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        itemCount: _savedRecipes.length,
        itemBuilder: (context, index) {
          final item = _savedRecipes[index];
          final bool isPlan = item['isMealPlan'] == true; 
          
          return GestureDetector(
            onTap: () => _showUnifiedStrategyBottomSheet(context, item),
            onLongPress: () => _confirmAndDeleteRecipe(item),
            child: Container(
              width: 260,
              margin: const EdgeInsets.only(right: 16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: isPlan 
                    ? const LinearGradient(colors: [Color(0xFFF97316), Color(0xFFEA580C)])
                    : (index % 2 == 0 
                        ? const LinearGradient(colors: [Color(0xFF1E293B), Color(0xFF334155)])
                        : const LinearGradient(colors: [Color(0xFF0F766E), Color(0xFF115E59)])),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 5))],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          item['name'] ?? 'Saved Strategy', 
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16, height: 1.2),
                          maxLines: 2, overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Icon(isPlan ? Icons.calendar_month : Icons.restaurant_menu, color: Colors.white70, size: 20),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (isPlan) ...[
                        Text("${(item['recipes'] as List?)?.length ?? 0} Recipes Bound", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
                        const SizedBox(height: 2),
                        const Text("Multi-Recipe Plan Pack", style: TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.bold)),
                      ] else ...[
                        Text("${item['nutrition']?['Calories'] ?? 'N/A'} Profile", style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text("${(item['ingredients_needed'] as List?)?.length ?? 0} ingredients", style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12)),
                      ]
                    ],
                  )
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFactCard() {
    if (_isLoading) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Colors.orange.shade400, Colors.deepOrange.shade500]),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.orange.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 8))],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle), child: const Icon(Icons.lightbulb_outline, color: Colors.white, size: 24)),
          const SizedBox(width: 16),
          Expanded(child: Text(_dailyFact, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15, height: 1.4))),
        ],
      ),
    );
  }

  void _showUnifiedStrategyBottomSheet(BuildContext context, Map<String, dynamic> item) {
    final bool isPlan = item['isMealPlan'] == true;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true, 
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.82, 
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
        child: Column(
          children: [
            Container(margin: const EdgeInsets.only(top: 12, bottom: 16), height: 5, width: 50, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10))),
            
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item['name'] ?? 'Saved Strategy', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF1E293B), height: 1.2)),
                        const SizedBox(height: 8),
                        Text(isPlan ? "📅 Complete Diet Plan Bundle" : "🍲 Standalone Traditional Dish", style: const TextStyle(color: Colors.blueGrey, fontSize: 13, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 26),
                    onPressed: () {
                      Navigator.pop(context); 
                      _confirmAndDeleteRecipe(item); 
                    },
                  )
                ],
              ),
            ),
            const Divider(height: 30, color: Colors.black12),
            
            if (isPlan) ...[
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  itemCount: (item['recipes'] as List?)?.length ?? 0,
                  itemBuilder: (context, idx) {
                    final subRecipe = item['recipes'][idx];
                    final List<dynamic> subIngs = subRecipe['ingredients_needed'] ?? [];
                    
                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.orange.shade100)
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(subRecipe['name'] ?? 'Plan Dish', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFFEA580C))),
                          const SizedBox(height: 8),
                          Text("Ingredients: ${subIngs.join(', ')}", style: const TextStyle(fontSize: 12, color: Colors.blueGrey), maxLines: 2, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 12),
                          
                          SizedBox(
                            width: double.infinity,
                            height: 38,
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.soup_kitchen, size: 14, color: Colors.white),
                              label: const Text("Start Cooking This Dish 🍳", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEA580C), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                              onPressed: () {
                                Navigator.pop(context);
                                _launchCookingStepper(context, subRecipe);
                              },
                            ),
                          )
                        ],
                      ),
                    );
                  },
                ),
              )
            ] else ...[
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  children: [
                    Row(
                      children: [
                        _buildNutritionBadge("🔥 ${item['nutrition']?['Calories'] ?? '?'}"),
                        const SizedBox(width: 8),
                        _buildNutritionBadge("🥩 ${item['nutrition']?['Protein'] ?? '?'} Profile"),
                      ],
                    ),
                    const SizedBox(height: 24),
                    const Text("Ingredients Implemented", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                    const SizedBox(height: 12),
                    if (item['ingredients_needed'] != null)
                      ...(item['ingredients_needed'] as List).map((ing) => Padding(
                            padding: const EdgeInsets.only(bottom: 10.0),
                            child: Row(
                              children: [
                                const Icon(Icons.check_circle, color: Color(0xFF0EA5E9), size: 18),
                                const SizedBox(width: 12),
                                Expanded(child: Text(ing.toString(), style: const TextStyle(fontSize: 15, color: Colors.blueGrey))),
                              ],
                            ),
                          )),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -5))]),
                child: SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F766E), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                    onPressed: () {
                      Navigator.pop(context); 
                      _launchCookingStepper(context, item);
                    },
                    child: const Text("Start Cooking 🍳", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _launchCookingStepper(BuildContext context, Map<String, dynamic> targetRecipeMap) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: const Color(0xFFF8FAFC),
          appBar: AppBar(
            title: const Text('Cooking Mode', style: TextStyle(fontWeight: FontWeight.bold)),
            backgroundColor: const Color(0xFF0F766E),
            foregroundColor: Colors.white,
            elevation: 0,
          ),
          body: Padding(
            padding: const EdgeInsets.all(16.0),
            child: RecipeStepperCard(recipe: RecipePayload.fromJson(targetRecipeMap)),
          ),
        ),
      ),
    );
  }

  Widget _buildNutritionBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: const Color(0xFF0EA5E9).withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: const TextStyle(color: Color(0xFF0F766E), fontWeight: FontWeight.w800, fontSize: 13)),
    );
  }
}