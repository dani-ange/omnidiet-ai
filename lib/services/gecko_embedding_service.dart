import 'dart:math';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'dart:io'; // 🌟 Add this at the top for Directory and File
import 'package:dart_sentencepiece_tokenizer/dart_sentencepiece_tokenizer.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

class GeckoEmbeddingService {
Interpreter? _interpreter;
  late final SentencePieceTokenizer _tokenizer;

  bool _initialized = false;

  bool get isReady => _initialized;

  Future<void> init() async {
    if (_initialized) return;

    try {
      // Load TFLite model
      _interpreter = await Interpreter.fromAsset(
        'assets/models/Gecko_1024_quant.tflite',
      );

      // Load tokenizer model
      final modelBytes = await rootBundle.load(
        'assets/models/sentencepiece.model',
      );

      _tokenizer = SentencePieceTokenizer.fromBytes(
        modelBytes.buffer.asUint8List(),
      );

      _initialized = true;

      final inputShape =
          _interpreter?.getInputTensor(0).shape;

      final outputShape =
          _interpreter?.getOutputTensor(0).shape;

      print("✅ Gecko initialized");
      print("📥 Input shape: $inputShape");
      print("📤 Output shape: $outputShape");
    } catch (e, stack) {
      print("❌ Gecko init failed: $e");
      print(stack);

      rethrow;
    }
  }
  // 🌟 ADD THIS NEW METHOD 🌟

// ... your existing code ...

 Future<void> initFromBytes(
  Uint8List tfliteBytes,
  Uint8List tokenizerBytes,
) async {
  if (_initialized) return;

  try {
    // Load model from memory
    _interpreter = Interpreter.fromBuffer(
      tfliteBytes,
    );

    // Load tokenizer from memory
    _tokenizer =
        SentencePieceTokenizer.fromBytes(
      tokenizerBytes,
    );

    // ✅ THIS WAS MISSING
    _initialized = true;

    final inputShape =
        _interpreter?.getInputTensor(0).shape;

    final outputShape =
        _interpreter?.getOutputTensor(0).shape;

    debugPrint(
      "✅ Gecko initialized from bytes",
    );

    debugPrint(
      "📥 Input shape: $inputShape",
    );

    debugPrint(
      "📤 Output shape: $outputShape",
    );
  } catch (e, stack) {
    debugPrint(
      "❌ Failed to init Gecko from bytes: $e",
    );

    debugPrint(stack.toString());

    rethrow;
  }
} 
  
// 🌟 1. Add the Normalizer Helper
  List<double> _l2Normalize(List<double> vector) {
    double sum = 0.0;
    for (double v in vector) {
      sum += v * v;
    }
    
    double magnitude = math.sqrt(sum);
    if (magnitude == 0) return vector; 

    return vector.map((v) => v / magnitude).toList();
  }

  // 🌟 2. Update your embedText function
  Future<List<double>> embedText(String text) async {
    if (!_initialized) {
      throw Exception("GeckoEmbeddingService not initialized");
    }

    try {
      // Tokenize
      List<int> tokens = List<int>.from(_tokenizer.encode(text).ids);

      // Read required sequence length
      final inputShape = _interpreter?.getInputTensor(0).shape;
      final int requiredLength = inputShape!.last;

      // Truncate
      if (tokens.length > requiredLength) {
        tokens = tokens.sublist(0, requiredLength);
      }

      // Pad
      while (tokens.length < requiredLength) {
        tokens.add(0);
      }

      // Use strict int32 tensor
      final input = [Int32List.fromList(tokens)];

      // Dynamically read embedding size
      final outputShape = _interpreter?.getOutputTensor(0).shape;
      final int embeddingSize = outputShape!.last;

      final output = List.generate(
        1,
        (_) => List.filled(embeddingSize, 0.0),
      );

      // Run inference
      _interpreter?.run(input, output);

      // 🌟 3. Extract, Normalize, and Return! 🌟
      List<double> rawVector = List<double>.from(output[0]);
      return _l2Normalize(rawVector);
      
    } catch (e, stack) {
      print("❌ Embedding failed: $e");
      print(stack);
      return [];
    }
  }
// 🌟 THE ENTERPRISE UPGRADE: Normalized Dot Product 🌟
  // Because our Python script and our embedText function both L2 Normalize 
  // the vectors, Cosine Similarity becomes a simple, ultra-fast Dot Product!
  double cosineSimilarity(
    List<double> normalizedA,
    List<double> normalizedB,
  ) {
    if (normalizedA.isEmpty || normalizedB.isEmpty) return 0.0;
    if (normalizedA.length != normalizedB.length) return 0.0;

    double dotProduct = 0.0;

    // Zero square roots. Zero division. Just pure, fast multiplication!
    for (int i = 0; i < normalizedA.length; i++) {
      dotProduct += normalizedA[i] * normalizedB[i];
    }

    return dotProduct;
  } 
  Future<void> dispose() async {
  _interpreter?.close();
  _interpreter = null;
  debugPrint("✅ Gecko Interpreter Closed");
}
}