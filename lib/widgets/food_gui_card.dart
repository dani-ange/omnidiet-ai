import 'package:flutter/material.dart';

class FoodGuiCard extends StatelessWidget {
  final Map<String, dynamic> foodData;

  const FoodGuiCard({Key? key, required this.foodData}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Safely extract data with fallbacks
    final String name = foodData['name'] ?? 'Unknown Dish';
    final String summary = foodData['summary'] ?? 'Nutritional breakdown.';
    final String calories = foodData['calories']?.toString() ?? '0';
    final String protein = foodData['protein']?.toString() ?? '0g';
    final String carbs = foodData['carbs']?.toString() ?? '0g';
    final String fat = foodData['fat']?.toString() ?? '0g';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- HEADER GRADIENT ---
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF0F766E), Color(0xFF0EA5E9)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Icon(Icons.restaurant, color: Colors.white70, size: 24),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          "VERIFIED",
                          style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    name,
                    style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    summary,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),

            // --- NUTRITION STATS ---
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  // Calories Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.local_fire_department, color: Colors.orangeAccent, size: 28),
                      const SizedBox(width: 8),
                      Text(
                        calories,
                        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Color(0xFF334155)),
                      ),
                      const Text(
                        " kcal",
                        style: TextStyle(fontSize: 16, color: Colors.grey, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16.0),
                    child: Divider(color: Color(0xFFE2E8F0), thickness: 1),
                  ),
                  
                  // Macros Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildMacroStat("Protein", protein, const Color(0xFF0EA5E9)),
                      Container(width: 1, height: 40, color: const Color(0xFFE2E8F0)),
                      _buildMacroStat("Carbs", carbs, const Color(0xFF10B981)),
                      Container(width: 1, height: 40, color: const Color(0xFFE2E8F0)),
                      _buildMacroStat("Fat", fat, const Color(0xFFF59E0B)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Helper widget for the macro blocks
  Widget _buildMacroStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}