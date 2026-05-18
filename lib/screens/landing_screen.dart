import 'package:flutter/material.dart';

// 🌟 IMPORT YOUR ROUTE TARGET CLEARLY
import 'model_download_screen.dart';

class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Deep Slate Dark Premium Canvas
      body: Stack(
        children: [
          // 🌊 BACKGROUND ART 1: Ambient blur top-right glow
          Positioned(
            top: -100,
            right: -100,
            child: Container(
              width: 350,
              height: 350,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF0EA5E9).withOpacity(0.12),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0EA5E9).withOpacity(0.15),
                    blurRadius: 120,
                    spreadRadius: 60,
                  )
                ],
              ),
            ),
          ),

          // 🌊 BACKGROUND ART 2: Ambient blur bottom-left teal glow
          Positioned(
            bottom: -80,
            left: -80,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF0F766E).withOpacity(0.1),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0F766E).withOpacity(0.12),
                    blurRadius: 100,
                    spreadRadius: 40,
                  )
                ],
              ),
            ),
          ),
          
          SafeArea(
            child: CustomScrollView(
              slivers: [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const SizedBox(height: 16),

                        // =====================================================
                        // 🎨 NEW: ABSTRACT GEOMETRIC BRAND SHAPE ACCENT
                        // =====================================================
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            // Rotating background decorative ring
                            Container(
                              width: screenSize.width * 0.44,
                              height: screenSize.width * 0.44,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: const Color(0xFF2DD4BF).withOpacity(0.2),
                                  width: 2,
                                ),
                              ),
                            ),
                            // The Premium Organic Shape Container
                            Container(
                              width: screenSize.width * 0.38,
                              height: screenSize.width * 0.38,
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E293B),
                                // Generates a smooth fluid stylized shield boundary matrix
                                borderRadius: BorderRadius.circular(45),
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    const Color(0xFF0F766E),
                                    const Color(0xFF0F766E).withOpacity(0.4),
                                  ],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF0F766E).withOpacity(0.25),
                                    blurRadius: 20,
                                    offset: const Offset(0, 8),
                                  )
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(45),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    // Soft linear abstract layer lines
                                    Opacity(
                                      opacity: 0.15,
                                      child: CustomPaint(painter: _GeometricShapeLinePainter()),
                                    ),
                                    // High-fidelity central branding icon vector
                                    const Center(
                                      child: Icon(
                                        Icons.auto_awesome_motion_rounded,
                                        color: Color(0xFF2DD4BF),
                                        size: 48,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        
                        const SizedBox(height: 40),
                        
                        // Main App Title Branding
                        const Text(
                          "OmniDiet AI ",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -1.0,
                          ),
                        ),
                        const SizedBox(height: 8),
                        
                        // Subtitle baseline message hook
                        Text(
                          "Your Hyper-Local, On-Device Clinical Cooking Coach",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.grey.shade400,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            height: 1.4,
                          ),
                        ),
                        
                        const SizedBox(height: 44),
                        
                        // =====================================================
                        // 🌟 ENHANCED CARDS: VALUE PROPOSITION COMPONENT TREE
                        // =====================================================
                        _buildBeautifiedFeatureCard(
                          icon: Icons.camera_enhance_rounded,
                          title: "Vision Plate Analyzer",
                          description: "Snap or scan traditional Cameroonian plates to detect ingredient ratios instantly without data connections.",
                        ),
                        const SizedBox(height: 14),
                        _buildBeautifiedFeatureCard(
                          icon: Icons.soup_kitchen_rounded,
                          title: "Adaptive Clinical Kitchen",
                          description: "Input items on hand. Gemma morphs African recipes into customized portions matching your clinical targets.",
                        ),
                        const SizedBox(height: 14),
                        _buildBeautifiedFeatureCard(
                          icon: Icons.security_rounded,
                          title: "100% Secure & Offline",
                          description: "No internet leakage. Your entire diagnostic chart and meal configuration logs remain locally locked inside your phone hardware storage.",
                        ),
                        
                        const Spacer(),
                        const SizedBox(height: 24),
                        
                        // =====================================================
                        // 🚀 UPGRADED: NAVIGATION HANDOVER GATE TO DOWNLOADER
                        // =====================================================
                        SizedBox(
                          width: double.infinity,
                          height: 58,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0F766E), // Royal Teal Palette
                              foregroundColor: Colors.white,
                              elevation: 4,
                              shadowColor: const Color(0xFF0F766E).withOpacity(0.4),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            // 🌟 ROUTING ADJUSTMENT: Now hands over context directly to the download stream setup screen!
                            onPressed: () {
                              Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(builder: (context) => const ModelDownloadScreen()),
                              );
                            },
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  "Get Started & Setup Core",
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: -0.2),
                                ),
                                SizedBox(width: 10),
                                Icon(Icons.arrow_forward_rounded, size: 20, color: Color(0xFF2DD4BF)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Visual card builder abstracting layout complexity from the main widget branch
  Widget _buildBeautifiedFeatureCard({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withOpacity(0.65), // Semi-translucent dark slate plate
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withOpacity(0.06),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF0EA5E9).withOpacity(0.12), // Glowing round icon canvas
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: const Color(0xFF2DD4BF), size: 22), // Vivid mint neon details
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    color: Colors.grey.shade400,
                    fontSize: 13,
                    height: 1.4,
                    fontWeight: FontWeight.w400,
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

// Custom background painter detailing subtle organic lines inside the shield avatar graphic
class _GeometricShapeLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF2DD4BF).withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final path = Path()
      ..moveTo(0, size.height * 0.2)
      ..quadraticBezierTo(size.width * 0.5, size.height * 0.5, size.width, size.height * 0.3)
      ..moveTo(0, size.height * 0.6)
      ..quadraticBezierTo(size.width * 0.4, size.height * 0.8, size.width, size.height * 0.5);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}