import 'package:uuid/uuid.dart';

const uuid = Uuid(); // The ID generator!

enum MessageType { text, system, nutritionCard, visionBoundingBox, recipeCard, recipeMenu,structuredRecipe }

// --- 1. THE UPGRADED MESSAGE MODEL ---
class ChatMessage {
  final String id;   // 🔑 The Unique ID for editing/deleting
  String text;       // ✏️ Removed 'final' so it can be edited!
  final bool isUser;
  final String? imagePath;
  final Map<String, dynamic>? dataPayload;
  final MessageType type;
  // This holds the raw data from Gemma + Cropped image paths
  final List<Map<String, dynamic>>? unifiedCartData;
  final List<String>? recipeIds; // To hold the IDs for the UI Card
  final String? sourcesRawText; // 🌟 Grounded database reference tracing payload

  ChatMessage({
    String? id, // If no ID is passed, we generate one automatically!
    required this.text,
    this.isUser = false,
    this.imagePath,
    this.dataPayload,
    this.unifiedCartData, // Add it to the constructor
    this.recipeIds,
    this.sourcesRawText, // 🌟 Wire up parameter
    MessageType? type,
    bool isSystem = false,
  })  : id = id ?? uuid.v4(), // Automatically generate a unique UUIDv4
        type = type ?? (isSystem ? MessageType.system : MessageType.text);

  bool get isSystem => type == MessageType.system;

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'isUser': isUser,
        'imagePath': imagePath,
        'dataPayload': dataPayload,
        'type': type.name,
        // Save the interactive data
        'unifiedCartData': unifiedCartData, 
        'recipeIds': recipeIds,
        'sourcesRawText': sourcesRawText, // 🌟 Serialize to persistent JSON
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id'],
        text: json['text'],
        isUser: json['isUser'] ?? false,
        imagePath: json['imagePath'],
        dataPayload: json['dataPayload'],
        // Load the interactive data
        unifiedCartData: json['unifiedCartData'] != null 
            ? List<Map<String, dynamic>>.from(json['unifiedCartData']) 
            : null,
        recipeIds: json['recipeIds'] != null 
            ? List<String>.from(json['recipeIds']) 
            : null,
        sourcesRawText: json['sourcesRawText'], // 🌟 Hydrate field from storage cache
        type: MessageType.values.firstWhere(
            (e) => e.name == json['type'],
            orElse: () => json['isSystem'] == true ? MessageType.system : MessageType.text),
      );

  // 🌟 UPDATE copyWith to include the new fields safely
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
    String? sourcesRawText, // 🌟 Included in pipeline state modification mutator
  }) {
    return ChatMessage(
      id: id ?? this.id,
      text: text ?? this.text,
      isUser: isUser ?? this.isUser,
      isSystem: isSystem ?? (type == MessageType.system),
      imagePath: imagePath ?? this.imagePath,
      dataPayload: dataPayload ?? this.dataPayload,
      type: type ?? this.type,
      unifiedCartData: unifiedCartData ?? this.unifiedCartData,
      recipeIds: recipeIds ?? this.recipeIds,
      sourcesRawText: sourcesRawText ?? this.sourcesRawText, // 🌟 Map structural update parameter
    );
  }
}

// --- 2. THE NEW SESSION MODEL (For Phase 3) ---
class ChatSession {
  final String id;
  String title;
  List<ChatMessage> messages;
  DateTime lastUpdated;

  ChatSession({
    String? id,
    this.title = "New Chat",
    required this.messages,
    DateTime? lastUpdated,
  })  : id = id ?? uuid.v4(),
        lastUpdated = lastUpdated ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'messages': messages.map((m) => m.toJson()).toList(),
        'lastUpdated': lastUpdated.toIso8601String(),
      };

  factory ChatSession.fromJson(Map<String, dynamic> json) => ChatSession(
        id: json['id'],
        title: json['title'] ?? "Saved Chat",
        messages: (json['messages'] as List<dynamic>?)
                ?.map((item) => ChatMessage.fromJson(item))
                .toList() ??
            [],
        lastUpdated: json['lastUpdated'] != null 
            ? DateTime.parse(json['lastUpdated']) 
            : DateTime.now(),
      );
}