import 'dart:io';
import 'package:flutter/material.dart';

class UnifiedIngredientCart extends StatefulWidget {
  final List<Map<String, dynamic>> scannedItems;
  final Function(List<String>) onConfirm;

  const UnifiedIngredientCart({
    Key? key,
    required this.scannedItems,
    required this.onConfirm,
  }) : super(key: key);

  @override
  State<UnifiedIngredientCart> createState() => _UnifiedIngredientCartState();
}

class _UnifiedIngredientCartState extends State<UnifiedIngredientCart> {
  final List<Map<String, dynamic>> _editableItems = [];
  final TextEditingController _addController = TextEditingController();
  bool _isConfirmed = false;

  @override
  void initState() {
    super.initState();

    // 🌟 1. SCROLL-SURVIVAL: Check if this specific card was already confirmed in the past
    if (widget.scannedItems.isNotEmpty && widget.scannedItems.first['isConfirmed'] == true) {
      _isConfirmed = true;
    }

    // 2. Initialize the text fields
    for (var item in widget.scannedItems) {
      String initialText = item['name'] == 'Unknown' ? '' : (item['name'] ?? '');
      
      _editableItems.add({
        'imagePath': item['imagePath'],
        'controller': TextEditingController(text: initialText),
      });
    }
  }

  @override
  void dispose() {
    for (var item in _editableItems) {
      (item['controller'] as TextEditingController).dispose();
    }
    _addController.dispose();
    super.dispose();
  }

  void _removeItem(int index) {
    setState(() {
      (_editableItems[index]['controller'] as TextEditingController).dispose();
      _editableItems.removeAt(index);
    });
  }

  void _addManualItem() {
    if (_addController.text.trim().isNotEmpty) {
      setState(() {
        _editableItems.add({
          'imagePath': null, 
          'controller': TextEditingController(text: _addController.text.trim()),
        });
        _addController.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
        padding: const EdgeInsets.all(16.0),
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: BorderRadius.circular(16.0),
          border: Border.all(color: const Color(0xFF0EA5E9).withOpacity(0.5), width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "🛒 Review & Edit Ingredients",
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            // --- THE VISUAL EDITABLE LIST ---
            ..._editableItems.asMap().entries.map((entry) {
              int index = entry.key;
              var item = entry.value;
              
              return Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: Row(
                  children: [
                    // Tap-to-Zoom Image
                    GestureDetector(
                      onTap: () {
                        if (item['imagePath'] != null && File(item['imagePath']).existsSync()) {
                          showDialog(
                            context: context,
                            builder: (context) => Dialog(
                              backgroundColor: Colors.transparent,
                              insetPadding: const EdgeInsets.all(10),
                              child: InteractiveViewer(
                                panEnabled: true,
                                minScale: 1.0,
                                maxScale: 5.0,
                                child: Image.file(File(item['imagePath'])),
                              ),
                            ),
                          );
                        }
                      },
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8.0),
                        child: item['imagePath'] != null && File(item['imagePath']).existsSync()
                            ? Image.file(File(item['imagePath']), height: 50, width: 50, fit: BoxFit.cover)
                            : Container(
                                height: 50, width: 50, color: Colors.black54,
                                child: const Icon(Icons.restaurant, color: Colors.white38),
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    
                    // The Text Field
                    Expanded(
                      child: TextField(
                        controller: item['controller'],
                        enabled: !_isConfirmed, // Locks the text box after confirm!
                        style: TextStyle(color: _isConfirmed ? Colors.white70 : Colors.white),
                        decoration: InputDecoration(
                          hintText: "Name this item...",
                          hintStyle: const TextStyle(color: Colors.white38),
                          isDense: true,
                          filled: true,
                          fillColor: Colors.black54,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8.0), 
                            borderSide: BorderSide.none
                          ),
                        ),
                      ),
                    ),
                    
                    if (!_isConfirmed)
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                        onPressed: () => _removeItem(index),
                      )
                  ],
                ),
              );
            }).toList(),

            const Divider(color: Colors.white24, height: 24),

            // --- ACTION ROW ---
            if (!_isConfirmed) ...[
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _addController,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: "Add missing ingredient...",
                        hintStyle: const TextStyle(color: Colors.white38),
                        isDense: true,
                        filled: true,
                        fillColor: Colors.black38,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8.0),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onSubmitted: (_) => _addManualItem(),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle, color: Color(0xFF0EA5E9)),
                    onPressed: _addManualItem,
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // THE NEW CONFIRM BUTTON
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F766E),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () {
                    List<String> finalNames = [];
                    
                    // 🌟 Overwrite the AI's data with the User's exact text!
                    widget.scannedItems.clear(); 

                    for (var item in _editableItems) {
                      String text = (item['controller'] as TextEditingController).text.trim();
                      if (text.isNotEmpty) {
                        finalNames.add(text);
                        // Push the user's edits back into the persistent chat model
                        widget.scannedItems.add({
                          'name': text,
                          'imagePath': item['imagePath'],
                          'isConfirmed': true, // 🌟 This locks the card permanently!
                        });
                      }
                    }

                    if (finalNames.isNotEmpty) {
                      setState(() { _isConfirmed = true; });
                      widget.onConfirm(finalNames);
                    }
                  },
                  child: const Text("Confirm", style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ] else
              // WHAT IT SHOWS AFTER THEY CLICK THE BUTTON
              const Center(
                child: Text(
                  "✅ Confirmed",
                  style: TextStyle(color: Color(0xFF0EA5E9), fontWeight: FontWeight.bold),
                ),
              )
          ],
        ),
      ),
    );
  }
}