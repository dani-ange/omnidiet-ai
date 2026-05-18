import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/chat_screen.dart'; // Adjust path if needed

class ProfileScreen extends StatefulWidget {
  final bool isFirstTime; 
  const ProfileScreen({super.key, this.isFirstTime = false}); 

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const platform = MethodChannel('com.ai.litertlm/chat');
  final ImagePicker _picker = ImagePicker();

  // Form Controllers
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _ageController = TextEditingController();
  final TextEditingController _weightController = TextEditingController();
  final TextEditingController _medicalNotesController = TextEditingController();

  // Dropdown Variables
  String _selectedGoal = 'Maintain Weight';
  final List<String> _goals = ['Lose Weight', 'Build Muscle', 'Maintain Weight', 'Manage Health Condition'];

  String _selectedSex = 'Not Specified';
  final List<String> _sexOptions = ['Not Specified', 'Male', 'Female'];

  String _selectedLanguage = 'English';
  final List<String> _languages = [
    'English', 
    'Français (French)', 
    'Cameroonian Pidgin', 
    'Swahili', 
    'Español (Spanish)'
  ];

  bool _isScanningNote = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadExistingProfile();
  }

  // --- 1. PERSISTENCE: LOAD SAVED DATA ---
  Future<void> _loadExistingProfile() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _nameController.text = prefs.getString('prof_name') ?? '';
      _ageController.text = prefs.getString('prof_age') ?? '';
      _weightController.text = prefs.getString('prof_weight') ?? '';
      _selectedGoal = prefs.getString('prof_goal') ?? 'Maintain Weight';
      _medicalNotesController.text = prefs.getString('prof_medical') ?? '';
      _selectedSex = prefs.getString('prof_sex') ?? 'Not Specified';
      _selectedLanguage = prefs.getString('prof_language') ?? 'English';
      _isLoading = false;
    });
  }

  // --- 2. AI VISION: READ MEDICAL NOTES (CAMERA & GALLERY) ---
  Future<void> _scanMedicalDocument(ImageSource source) async {
    // 🌟 MASSIVE OOM FIX: Aggressively downscale to 512x512 to prevent Native Engine memory crashes!
    final XFile? image = await _picker.pickImage(
      source: source, 
      maxWidth: 512,     // 🌟 Change from 800 to 512
      maxHeight: 512,    // 🌟 Change from 800 to 512
      imageQuality: 50   // 🌟 Compress slightly more to save RAM
    );
    
    if (image == null) return;

    setState(() { _isScanningNote = true; });

    try {
      // Defensively cancel any running generations
      try { await platform.invokeMethod('cancelGeneration'); } catch (_) {}
      // 🌟 FIX: Change 'startGeneration' to 'generateOnce' so it returns the full text instead of null!
      final reply = await platform.invokeMethod('generateOnce', {
        'text': "You are a medical AI. Read this patient's 'Carnet de Santé', dietary guide, or lab results. Extract ONLY the dietary restrictions, allergies, and relevant health conditions. Summarize them in a short, bulleted list. Do not include conversational filler.",
        'imagePath': image.path,
        'audioPath': null,
      });

      // 🌟 FIX 2: Safely check if the reply is null before trying to print it!
      if (reply != null && reply.toString().trim().isNotEmpty) {
        setState(() {
          String currentNotes = _medicalNotesController.text;
          String extractedText = reply.toString().trim();
          
          _medicalNotesController.text = currentNotes.isEmpty 
              ? extractedText 
              : "$currentNotes\n\n[AI Extracted Carnet Data]:\n$extractedText";
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("✅ Medical notes extracted successfully!"), backgroundColor: Color(0xFF0F766E))
          );
        }
      } else {
        throw Exception("Engine returned empty data.");
      }

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("❌ Failed to read document: $e"))
        );
      }
    } finally {
      setState(() { _isScanningNote = false; });
    }
  }

  // --- 3. PERSISTENCE: SAVE TO MEMORY & GENERATE PROMPT ---
  Future<void> _saveAndExit() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_first_time', false);
    // 1. Save raw data to device memory
    await prefs.setString('prof_name', _nameController.text.trim());
    await prefs.setString('prof_age', _ageController.text.trim());
    await prefs.setString('prof_weight', _weightController.text.trim());
    await prefs.setString('prof_goal', _selectedGoal);
    await prefs.setString('prof_medical', _medicalNotesController.text.trim());
    await prefs.setString('prof_sex', _selectedSex);
    await prefs.setString('prof_language', _selectedLanguage);

    // 2. 🌟 THE MAGIC: Generate the "System Prompt" that dictates the AI's personality and rules!
    String masterPrompt = """
[PATIENT PROFILE]
Name: ${_nameController.text.isNotEmpty ? _nameController.text : 'User'}
Age: ${_ageController.text.isNotEmpty ? _ageController.text : 'Unknown'}
Weight: ${_weightController.text.isNotEmpty ? _weightController.text : 'Unknown'}
Biological Sex: $_selectedSex
Primary Goal: $_selectedGoal
Medical/Dietary Notes & Restrictions: 
${_medicalNotesController.text.isNotEmpty ? _medicalNotesController.text : 'None reported.'}
[/PATIENT PROFILE]

🌟 CRITICAL COMMUNICATION RULE: You MUST speak, respond, and format your entire answer exclusively in $_selectedLanguage. If the language is Pidgin, use authentic Cameroonian Pidgin English slang.

You must strictly adhere to this patient profile. Never suggest food that violates their medical notes or allergies. Tailor your nutritional advice to help them achieve their Primary Goal, accounting for their Biological Sex in macro calculations.
""";

    // Save the compiled prompt
    await prefs.setString('saved_profile', masterPrompt);

    // 3. Smart Navigation Router
    if (mounted) {
      if (widget.isFirstTime) {
        Navigator.pushReplacement(
          context, 
          MaterialPageRoute(builder: (context) => const ChatScreen())
        );
      } else {
        Navigator.pop(context, {'prompt': masterPrompt});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator(color: Color(0xFF0F766E))));

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('My Health Profile', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0F766E), Color(0xFF0EA5E9)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- BASIC INFO CARD ---
            _buildSectionTitle("Basic Information"),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
              ),
              child: Column(
                children: [
                  _buildTextField("Name", Icons.person, _nameController),
                  const Divider(height: 24),
                  Row(
                    children: [
                      Expanded(child: _buildTextField("Age", Icons.cake, _ageController, isNumber: true)),
                      const SizedBox(width: 16),
                      Expanded(child: _buildTextField("Weight (kg)", Icons.monitor_weight, _weightController, isNumber: true)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // --- 🌟 DEMOGRAPHICS & PREFERENCES CARD ---
            _buildSectionTitle("Demographics & Agent Language"),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
              ),
              child: Column(
                children: [
                  _buildDropdownRow(
                    label: "Biological Sex (For Macros)", 
                    icon: Icons.biotech, 
                    value: _selectedSex, 
                    items: _sexOptions, 
                    onChanged: (v) => setState(() => _selectedSex = v!)
                  ),
                  const Divider(height: 24),
                  _buildDropdownRow(
                    label: "Agent Language", 
                    icon: Icons.language, 
                    value: _selectedLanguage, 
                    items: _languages, 
                    onChanged: (v) => setState(() => _selectedLanguage = v!)
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // --- GOALS CARD ---
            _buildSectionTitle("Primary Goal"),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedGoal,
                  isExpanded: true,
                  icon: const Icon(Icons.keyboard_arrow_down, color: Color(0xFF0F766E)),
                  items: _goals.map((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500, color: Color(0xFF334155))),
                    );
                  }).toList(),
                  onChanged: (newValue) => setState(() => _selectedGoal = newValue!),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // --- MEDICAL NOTES & AI SCANNER ---
            _buildSectionTitle("Medical & Dietary Notes"),
            
            // 🌟 NEW: Dual Scanner Buttons (Camera & Gallery)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.teal.shade50, borderRadius: BorderRadius.circular(16)),
              child: Column(
                children: [
                  const Row(
                    children: [
                      Icon(Icons.document_scanner, color: Color(0xFF0F766E)),
                      SizedBox(width: 8),
                      Expanded(child: Text("Have a dietary sheet or Carnet de Santé? Scan it to auto-fill restrictions!", style: TextStyle(fontSize: 13, color: Color(0xFF0F766E), fontWeight: FontWeight.w600))),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_isScanningNote)
                    const LinearProgressIndicator(color: Color(0xFF0EA5E9))
                  else
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F766E), foregroundColor: Colors.white), 
                            onPressed: () => _scanMedicalDocument(ImageSource.camera), 
                            icon: const Icon(Icons.camera_alt, size: 16), 
                            label: const Text("Camera")
                          )
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0EA5E9), foregroundColor: Colors.white), 
                            onPressed: () => _scanMedicalDocument(ImageSource.gallery), 
                            icon: const Icon(Icons.photo_library, size: 16), 
                            label: const Text("Gallery")
                          )
                        ),
                      ],
                    )
                ],
              ),
            ),

            // --- AI VISION TEXT AREA WITH LOADING OVERLAY ---
            Container(
              padding: const EdgeInsets.all(16),
              // Lock the height so the loading spinner stays perfectly centered
              constraints: const BoxConstraints(minHeight: 150), 
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _isScanningNote ? Colors.grey.shade300 : const Color(0xFF0EA5E9).withOpacity(0.3),
                  width: _isScanningNote ? 1 : 2,
                ),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // 1. The actual text field
                  TextField(
                    controller: _medicalNotesController,
                    maxLines: 5,
                    enabled: !_isScanningNote, // 🌟 Lock the keyboard while AI is thinking!
                    decoration: const InputDecoration(
                      hintText: "Type allergies or medical conditions manually, or use the scanner above to let AI read your doctor notes.",
                      hintStyle: TextStyle(color: Colors.black38, fontSize: 14),
                      border: InputBorder.none,
                    ),
                  ),
                  
                  // 2. 🌟 THE FROSTED GLASS LOADING OVERLAY 🌟
                  if (_isScanningNote)
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.85), // Blurs out the existing text slightly
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              height: 30, width: 30,
                              child: CircularProgressIndicator(color: Color(0xFF0EA5E9), strokeWidth: 3),
                            ),
                            SizedBox(height: 12),
                            Text(
                              "AI is reading your document...",
                              style: TextStyle(color: Color(0xFF0F766E), fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 40),

            // --- SAVE BUTTON ---
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F766E),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 2,
                ),
                onPressed: _saveAndExit,
                child: const Text("Save Profile & Boot AI", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // UI Helper Function for Section Titles
  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, left: 4.0),
      child: Text(
        title,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blueGrey, letterSpacing: 1.2),
      ),
    );
  }

  // UI Helper Function for Text Fields
  Widget _buildTextField(String label, IconData icon, TextEditingController controller, {bool isNumber = false}) {
    return TextField(
      controller: controller,
      keyboardType: isNumber ? TextInputType.number : TextInputType.name,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: const Color(0xFF0F766E)),
        border: InputBorder.none,
      ),
    );
  }

  // UI Helper Function for Dropdown Rows
  Widget _buildDropdownRow({required String label, required IconData icon, required String value, required List<String> items, required Function(String?) onChanged}) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF0F766E)),
        const SizedBox(width: 12),
        Expanded(
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              icon: const Icon(Icons.keyboard_arrow_down, color: Color(0xFF0F766E)),
              hint: Text(label, style: const TextStyle(color: Colors.black38)),
              items: items.map((String val) {
                return DropdownMenuItem<String>(
                  value: val,
                  child: Text(val, style: const TextStyle(fontWeight: FontWeight.w500, color: Color(0xFF334155), fontSize: 14)),
                );
              }).toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}