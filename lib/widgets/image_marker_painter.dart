import 'package:flutter/material.dart';

class ImageMarkerPainter extends CustomPainter {
  final List<dynamic> boxes; // Expected format: [[ymin, xmin, ymax, xmax]]

  ImageMarkerPainter(this.boxes);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width == 0 || size.height == 0) return; // Safety catch

    final paint = Paint()
      ..color = Colors.greenAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0; // Slightly thicker so it's easy to see

    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    for (var item in boxes) {
      try {
        // A very forgiving check to ensure we have a Map
        if (item != null && item is Map) {
          
          // Check for either 'box_2d' or just 'box' just in case the AI hallucinates the key
          final String? boxKey = item.containsKey('box_2d') ? 'box_2d' : (item.containsKey('box') ? 'box' : null);
          
          if (boxKey != null) {
            // Safely cast the list
            final List<dynamic> box = List.from(item[boxKey]);
            final String label = item['label']?.toString() ?? 'DETECTED';

            // 🌟 THE FIX: Removed the "/ 1000". Gemma is already giving us 0.0 to 1.0!
            final double top = box[0] * size.height;
            final double left = box[1] * size.width;
            final double bottom = box[2] * size.height;
            final double right = box[3] * size.width;

            final rect = Rect.fromLTRB(left, top, right, bottom);

            // Draw Border
            canvas.drawRect(rect, paint);
            
            // Draw faint fill
            canvas.drawRect(
              rect,
              Paint()..color = Colors.greenAccent.withOpacity(0.25)..style = PaintingStyle.fill,
            );

            // Draw Label
            textPainter.text = TextSpan(
              text: ' ${label.toUpperCase()} ',
              style: const TextStyle(
                color: Colors.white, 
                backgroundColor: Colors.green,
                fontSize: 14, 
                fontWeight: FontWeight.bold,
                letterSpacing: 1.1,
              ),
            );
            textPainter.layout();
            textPainter.paint(canvas, Offset(left, top - 20));
          }
        }
      } catch (e) {
        debugPrint("Painter Error on item: $e"); 
      }
    }
  }
  
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}