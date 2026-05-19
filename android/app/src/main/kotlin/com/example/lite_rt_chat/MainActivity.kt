package com.example.lite_rt_chat

import android.util.Log
import androidx.lifecycle.lifecycleScope
import com.google.ai.edge.litertlm.*
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.collect
import java.io.File

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.ai.litertlm/chat"
    private val STREAM_CHANNEL = "com.ai.litertlm/stream"
    private var conversation: Conversation? = null
    private var engine: Engine? = null

    private var eventSink: EventChannel.EventSink? = null

    // 🌟 Track active generation
    private var generationJob: Job? = null

    override fun configureFlutterEngine(
        flutterEngine: FlutterEngine
    ) {

        super.configureFlutterEngine(flutterEngine)

        // =====================================================
        // 🌟 EVENT CHANNEL
        // =====================================================

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            STREAM_CHANNEL
        ).setStreamHandler(

            object : EventChannel.StreamHandler {

                override fun onListen(
                    arguments: Any?,
                    sink: EventChannel.EventSink?
                ) {

                    eventSink = sink

                    Log.d(
                        "GEMMA_DEBUG",
                        "✅ Flutter stream connected"
                    )
                }

                override fun onCancel(arguments: Any?) {

                    eventSink = null

                    Log.d(
                        "GEMMA_DEBUG",
                        "❌ Flutter stream disconnected"
                    )
                }
            }
        )

        // =====================================================
        // 🌟 METHOD CHANNEL
        // =====================================================

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->

            when (call.method) {

                // =================================================
                // INIT MODEL
                // =================================================

                "initModel" -> {
                    initModel(result)
                }

                // =================================================
                // START GENERATION
                // =================================================

                "startGeneration" -> {

                    val text =
                        call.argument<String>("text") ?: ""

                    val imagePath =
                        call.argument<String>("imagePath")

                    val audioPath =
                        call.argument<String>("audioPath")

                    generateResponse(
                        text,
                        imagePath,
                        audioPath
                    )

                    result.success(null)
                }
                        "generateOnce" -> {

                            val text =
                                call.argument<String>("text") ?: ""

                            val imagePath =
                                call.argument<String>("imagePath")

                            val audioPath =
                                call.argument<String>("audioPath")

                            generateSingleResponse(
                                text,
                                imagePath,
                                audioPath,
                                result
                            )
                        }
                // =================================================
                // CANCEL GENERATION
                // =================================================

                "cancelGeneration" -> {

                    generationJob?.cancel()

                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }
    }

    // =========================================================
    // 🌟 INIT MODEL
    // =========================================================

// =========================================================
    // 🌟 INIT MODEL
    // =========================================================
    private fun initModel(result: MethodChannel.Result) {
        val modelFile = File(filesDir, "gemma-4-E2B-it.litertlm")

        if (!modelFile.exists()) {
            result.error("FILE_NOT_FOUND", "Missing model at ${modelFile.absolutePath}", null)
            return
        }

        lifecycleScope.launch(Dispatchers.IO) {
            try {
                // 🌟 CLEAN LINGER LOCKS: Force-close conversation session memory locks cleanly
                try {
                    conversation?.close()
                    conversation = null
                    Log.d("GEMMA_DEBUG", "🧹 Dropped persistent conversation session memory locks.")
                } catch (_: Exception) {}

                // 🌟 GLOBAL SINGLETON GUARD: If engine is already warm, return success instantly
                if (engine != null) {
                    Log.d("GEMMA_DEBUG", "⚡ Engine already active. Bypassing dual-allocation pass.")
                    withContext(Dispatchers.Main) {
                        result.success("Gemma engine already warm in global background context")
                    }
                    return@launch
                }

                val config = EngineConfig(
                    modelPath = modelFile.absolutePath,
                    backend = Backend.CPU(),
                    visionBackend = Backend.CPU(),
                    audioBackend = Backend.CPU()
                )

                engine = Engine(config)
                engine?.initialize()

                Log.d("GEMMA_DEBUG", "✅ Cold-boot engine initialization successful.")
                withContext(Dispatchers.Main) {
                    result.success("Gemma initialized successfully")
                }

            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    result.error("INIT_FAILED", e.message, null)
                }
            }
        }
    }
    // =========================================================
    // 🌟 GENERATION
    // =========================================================
private fun generateSingleResponse(
    text: String,
    imagePath: String?,
    audioPath: String?,
    result: MethodChannel.Result
) {

    lifecycleScope.launch(Dispatchers.IO) {

        var conversation: Conversation? = null

        try {

            val config = ConversationConfig(
                systemInstruction = Contents.of(
                    "You are a precise vision extraction AI."
                )
            )

            conversation =
                engine?.createConversation(config)

            val contents =
                mutableListOf<Content>()

            if (!audioPath.isNullOrEmpty()) {
                contents.add(
                    Content.AudioFile(audioPath)
                )
              }

            if (!imagePath.isNullOrEmpty()) {
                contents.add(
                    Content.ImageFile(imagePath)
                )
            }

            contents.add(Content.Text(text))

            val response =
                conversation?.sendMessage(
                    Contents.of(
                        *contents.toTypedArray()
                    )
                )

            val finalText =
                response.toString()

            withContext(Dispatchers.Main) {

                result.success(finalText)
            }

        } catch (e: Exception) {

            withContext(Dispatchers.Main) {

                result.error(
                    "GENERATION_ERROR",
                    e.message,
                    null
                )
            }

        } finally {
            // 🌟 FIXED: Force-close the active conversation instance immediately to clear the session lock
            try {
                conversation?.close()
                conversation = null 
                Log.d("GEMMA_DEBUG", "🧹 Native single session memory forcefully cleared.")
            } catch (_: Exception) {}
        }
    }
}
 private fun generateResponse(
        text: String,
        imagePath: String?,
        audioPath: String?
    ) {
        // 🌟 Cancel previous generation
        generationJob?.cancel()

        generationJob = lifecycleScope.launch(Dispatchers.IO) {
            var conversation: Conversation? = null

            try {
                Log.d("GEMMA_DEBUG", "🚀 Starting Hybrid generation")

                // =============================================
                // CREATE CONVERSATION
                // =============================================
                val config = ConversationConfig(
                    systemInstruction = Contents.of(
                        "You are a helpful multimodal AI assistant."
                    )
                )
                conversation = engine?.createConversation(config)

                // =============================================
                // BUILD CONTENTS
                // =============================================
                val contents = mutableListOf<Content>()

                if (!audioPath.isNullOrEmpty()) {
                    contents.add(Content.AudioFile(audioPath))
                }
                if (!imagePath.isNullOrEmpty()) {
                    contents.add(Content.ImageFile(imagePath))
                }
                contents.add(Content.Text(text))

               // =============================================
// 🌟 THE UPGRADED HYBRID ROUTER WITH STREAMING VISION SUPPORT
// =============================================
if (!imagePath.isNullOrEmpty()) {
    val isStructuralScan = text.contains("expert culinary vision system") || text.contains("strict JSON array")

    if (isStructuralScan) {
        // 📸 TOP BUTTON: Strict Structural Scan Mode -> Maintain Blocking Response for RAM Safety
        Log.d("GEMMA_DEBUG", "Starting blocking vision analysis for structural ingredient scanning...")
        
        val response = conversation?.sendMessage(Contents.of(*contents.toTypedArray()))
        val fullText = response?.toString() ?: ""
        
        withContext(Dispatchers.Main) {
            eventSink?.success(mapOf("type" to "token", "content" to fullText))
        }
    } else {
        // 📸 BOTTOM BAR CAMERA: Conversational Vision Mode -> STREAM TOKENS LIVE!
        Log.d("GEMMA_DEBUG", "Starting async streaming text-and-image conversation...")
        
        val flow = conversation?.sendMessageAsync(Contents.of(*contents.toTypedArray()))
        var previousText = ""

        flow?.collect { partialMessage ->
            val fullText = partialMessage?.toString() ?: ""
            val delta = fullText.removePrefix(previousText)
            previousText = fullText

            if (delta.isNotEmpty()) {
                withContext(Dispatchers.Main) {
                    eventSink?.success(mapOf("type" to "token", "content" to delta))
                }
            }
        }
    }
} else {
    // 💬 PURE TEXT MODE: Asynchronous (Fast Streaming!)
    Log.d("GEMMA_DEBUG", "Starting async text stream...")
    
    val flow = conversation?.sendMessageAsync(Contents.of(*contents.toTypedArray()))
    var previousText = ""

    flow?.collect { partialMessage ->
        val fullText = partialMessage?.toString() ?: ""
        val delta = fullText.removePrefix(previousText)
        previousText = fullText

        if (delta.isNotEmpty()) {
            withContext(Dispatchers.Main) {
                eventSink?.success(mapOf("type" to "token", "content" to delta))
            }
        }
    }
}
                // =============================================
                // COMPLETE (Runs for both modes)
                // =============================================
                withContext(Dispatchers.Main) {
                    eventSink?.success(
                        mapOf(
                            "type" to "done"
                        )
                    )
                }

                Log.d("GEMMA_DEBUG", "✅ Generation completed")

            } catch (e: CancellationException) {
                Log.d("GEMMA_DEBUG", "🛑 Generation cancelled")
            } catch (e: Exception) {
                Log.e("GEMMA_DEBUG", "💥 Error: ${e.message}")
                withContext(Dispatchers.Main) {
                    eventSink?.success(
                        mapOf(
                            "type" to "error",
                            "message" to (e.message ?: "Unknown error")
                        )
                    )
                }
            } finally {
                try {
                    conversation?.close()
                } catch (_: Exception) {
                }
                conversation = null
            }
        }
    }
    // =========================================================
    // 🌟 CLEANUP
    // =========================================================

    override fun onDestroy() {

        generationJob?.cancel()

        try {
            engine?.close()
        } catch (_: Exception) {
        }

        super.onDestroy()
    }
}