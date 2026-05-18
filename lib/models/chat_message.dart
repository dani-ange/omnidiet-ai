import 'package:uuid/uuid.dart';

const uuid = Uuid(); 

enum MessageType { text, system, nutritionCard, visionBoundingBox, recipeCard, recipeMenu, structuredRecipe }

// --- 1. THE UPGRADED MESSAGE MODEL ---
class ChatMessage {
  final String id;   
  String text;       
  final bool isUser;
  final String? imagePath;
  final Map<String, dynamic>? dataPayload;
  final MessageType type;
  final List<Map<String, dynamic>>? unifiedCartData;
  final List<String>? recipeIds; 
  final String? sourcesRawText; 
  final DateTime timestamp; // 🌟 ADDING MISSING PROP FIELD

  ChatMessage({
    String? id, 
    required this.text,
    this.isUser = false,
    this.imagePath,
    this.dataPayload,
    this.unifiedCartData, 
    this.recipeIds,
    this.sourcesRawText, 
    DateTime? timestamp, // 🌟 ADDING PARAMETER TO CONSTRUCTOR
    MessageType? type,
    bool isSystem = false,
  })  : id = id ?? uuid.v4(), 
        timestamp = timestamp ?? DateTime.now(), // 🌟 AUTO-FALLBACK TO PRESENT TIME
        type = type ?? (isSystem ? MessageType.system : MessageType.text);

  // ===========================================================================
  // 💾 MAP SERIALIZERS (Fixes cache loads and background saves instantly)
  // ===========================================================================
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'text': text,
      'isUser': isUser,
      'imagePath': imagePath,
      'dataPayload': dataPayload,
      'type': type.index, // Serialize enum via index mapping
      'unifiedCartData': unifiedCartData,
      'recipeIds': recipeIds,
      'sourcesRawText': sourcesRawText,
      'timestamp': timestamp.toIso8601String(), // 🌟 CONVERT TO STRING FOR STORAGE
    };
  }

  factory ChatMessage.fromMap(Map<String, dynamic> map) {
    return ChatMessage(
      id: map['id'],
      text: map['text'] ?? '',
      isUser: map['isUser'] ?? false,
      imagePath: map['imagePath'],
      dataPayload: map['dataPayload'] != null ? Map<String, dynamic>.from(map['dataPayload']) : null,
      type: MessageType.values[map['type'] ?? 0],
      unifiedCartData: map['unifiedCartData'] != null ? List<Map<String, dynamic>>.from(map['unifiedCartData']) : null,
      recipeIds: map['recipeIds'] != null ? List<String>.from(map['recipeIds']) : null,
      sourcesRawText: map['sourcesRawText'],
      timestamp: map['timestamp'] != null ? DateTime.parse(map['timestamp']) : DateTime.now(), // 🌟 RE-PARSE SAFE ISO TIME
    );
  }

  ChatMessage copyWith({
    String? id,
    String? text,
    bool? isUser,
    bool? isSystem,
    String? imagePath,
    Map<String, dynamic>? dataPayload,
    MessageType? type,
    List<Map<String, dynamic>>? unifiedCartData,
    List<String>? recipeIds,
    String? sourcesRawText,
    DateTime? timestamp, // 🌟 WIRING UP PROP EXTENSIONS
  }) {
    return ChatMessage(
      id: id ?? this.id,
      text: text ?? this.text,
      isUser: isUser ?? this.isUser,
      imagePath: imagePath ?? this.imagePath,
      dataPayload: dataPayload ?? this.dataPayload,
      type: type ?? this.type,
      unifiedCartData: unifiedCartData ?? this.unifiedCartData,
      recipeIds: recipeIds ?? this.recipeIds,
      sourcesRawText: sourcesRawText ?? this.sourcesRawText,
      timestamp: timestamp ?? this.timestamp, // 🌟 REDIRECT TO ACTIVE VALUE MAPS
    );
  }
}