import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Import your dashboard screen
import '../profile_screen.dart';
import 'home_screen.dart';

class ModelDownloadScreen extends StatefulWidget {
  const ModelDownloadScreen({super.key});

  @override
  State<ModelDownloadScreen> createState() => _ModelDownloadScreenState();
}

class _ModelDownloadScreenState extends State<ModelDownloadScreen> {
  bool _isModelReady = false;
  bool _isDownloading = false;
  bool _isPaused = false;

  double _downloadProgress = 0.0;
  String _downloadStatusText = "Checking system...";

  CancelToken? _cancelToken;

  // ==========================================
  // 🌟 MODEL DOWNLOAD ARCHITECTURE CONFIG
  // ==========================================
  final String _modelFileName = 'gemma-4-E2B-it.litertlm';
  final String _modelDownloadUrl =
      'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm?download=true';

  // Exact expected file size for the on-device LLM pipeline
  final int _expectedTotalBytes = 2583085056;

  @override
  void initState() {
    super.initState();
    _checkIfModelExists();
  }

  // 🌟 FIXED: Resolves path down to the clean root parent 'files' directory to sync with Kotlin filesDir
  Future<String> _getTargetModelPath() async {
    final Directory documentsDir = await getApplicationDocumentsDirectory();
    // documentsDir.path gives us: /data/user/0/your.package.name/app_flutter
    // documentsDir.parent.path gives us: /data/user/0/your.package.name
    final String rootAppDir = documentsDir.parent.path;

    // This forms: /data/user/0/your.package.name/files/gemma-4-E2B-it.litertlm
    // Which matches Kotlin's File(filesDir, "gemma-4-E2B-it.litertlm") 100% perfectly!
    return '$rootAppDir/files/$_modelFileName';
  }

  Future<void> _checkIfModelExists() async {
    try {
      final modelPath = await _getTargetModelPath();
      final file = File(modelPath);

      if (file.existsSync() && file.lengthSync() == _expectedTotalBytes) {
        setState(() {
          _isModelReady = true;
          _downloadStatusText = "Local LLM Engine fully verified and ready!";
          _downloadProgress = 1.0;
        });
      } else {
        setState(() {
          _isModelReady = false;
          _downloadStatusText =
              "Local LLM model missing or incomplete. Download required.";
          _downloadProgress = 0.0;
        });
      }
    } catch (e) {
      setState(() {
        _downloadStatusText = "System check failed: $e";
      });
    }
  }

  // 1. Add these new tracking fields inside your _ModelDownloadScreenState class
  int _speedSampleStart = 0;
  String _etaText = "";

  // 2. Replace your _startOrResumeDownload method with this version:
  Future<void> _startOrResumeDownload() async {
    try {
      final modelPath = await _getTargetModelPath();
      final file = File(modelPath);

      // Ensure the 'files' directory exists
      if (!file.parent.existsSync()) {
        file.parent.createSync(recursive: true);
      }

      int existingBytes = 0;
      if (file.existsSync()) {
        existingBytes = file.lengthSync();
      }

      if (existingBytes == _expectedTotalBytes) {
        setState(() {
          _isModelReady = true;
          _isDownloading = false;
        });
        return;
      }

      setState(() {
        _isDownloading = true;
        _isPaused = false;
        _downloadStatusText = "Connecting to model repository...";
        _etaText = ""; // Reset ETA on start
      });

      _cancelToken = CancelToken();
      final dio = Dio();

      // CRITICAL RESUME FIX:
      // To append bytes instead of overwriting, we must pass the deleteOnError: false flag
      // and let Dio know we are handling a partial file range.
      Options options = Options(
        responseType: ResponseType.bytes,
        headers: existingBytes > 0 ? {'range': 'bytes=$existingBytes-'} : {},
      );

      // Track the moment the network stream actually starts for accurate speed math
      _speedSampleStart = DateTime.now().millisecondsSinceEpoch;

      await dio.download(
        _modelDownloadUrl,
        modelPath,
        cancelToken: _cancelToken,
        options: options,
        deleteOnError: false, // CRITICAL: Don't delete the file on pause/cancel
        onReceiveProgress: (received, total) {
          // 'received' is the bytes downloaded in THIS session.
          int currentReceived = existingBytes + received;

          // --- ETA & SPEED CALCULATION ---
          final int now = DateTime.now().millisecondsSinceEpoch;
          final int durationMs = now - _speedSampleStart;

          String etaString = "";
          if (durationMs > 500 && received > 0) {
            // Bytes per millisecond * 1000 = Bytes per second
            double bytesPerSec = (received / durationMs) * 1000;
            int remainingBytes = _expectedTotalBytes - currentReceived;

            if (bytesPerSec > 0 && remainingBytes > 0) {
              int secondsRemaining = (remainingBytes / bytesPerSec).round();

              // Format into readable string (HH:MM:SS or MM:SS)
              if (secondsRemaining >= 3600) {
                int hours = secondsRemaining ~/ 3600;
                int minutes = (secondsRemaining % 3600) ~/ 60;
                etaString = "Estimated time remaining: ${hours}h ${minutes}m";
              } else if (secondsRemaining >= 60) {
                int minutes = secondsRemaining ~/ 60;
                int seconds = secondsRemaining % 60;
                etaString = "Estimated time remaining: ${minutes}m ${seconds}s";
              } else {
                etaString = "Estimated time remaining: ${secondsRemaining}s";
              }
            }
          }
          // ---------------------------------

          setState(() {
            _downloadProgress = currentReceived / _expectedTotalBytes;
            double progressPercent = _downloadProgress * 100;
            _etaText = etaString;
            _downloadStatusText =
                "Downloading local brain: ${progressPercent.toStringAsFixed(1)}%\n"
                "(${(currentReceived / (1024 * 1024)).toStringAsFixed(1)} MB / "
                "${(_expectedTotalBytes / (1024 * 1024)).toStringAsFixed(1)} MB)";
          });
        },
      );

      // Verify final file footprint
      // CRITICAL RESUME FIX: We need to refresh the file instance properties from the disk
      // because file.lengthSync() can sometimes cache old file stats in Dart.
      final freshFileCheck = File(modelPath);
      if (freshFileCheck.existsSync() &&
          freshFileCheck.lengthSync() == _expectedTotalBytes) {
        setState(() {
          _isModelReady = true;
          _isDownloading = false;
          _downloadStatusText = "Download complete! Engine ready.";
          _downloadProgress = 1.0;
          _etaText = "";
        });
      } else {
        setState(() {
          _isDownloading = false;
          _downloadStatusText =
              "File integrity size mismatch. Please re-download.";
          _etaText = "";
        });
      }
    } catch (e) {
      setState(() {
        _isDownloading = false;
        _etaText = "";
        if (CancelToken.isCancel(e as DioException)) {
          _isPaused = true;
          _downloadStatusText = "Download paused by user.";
        } else {
          _downloadStatusText = "Network error: ${e.toString()}";
        }
      });
    }
  }

  void _pauseDownload() {
    if (_isDownloading) {
      _cancelToken?.cancel("Paused");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'System Setup',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0F766E), Color(0xFF0EA5E9)],
            ),
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Spacer(),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF0F766E).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _isModelReady
                    ? Icons.check_circle_outline
                    : Icons.cloud_download_outlined,
                size: 64,
                color: const Color(0xFF0F766E),
              ),
            ),
            const SizedBox(height: 32),
            const Text(
              "Local AI Core Setup",
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                _downloadStatusText,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF475569),
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 32),

            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: _downloadProgress,
                minHeight: 10,
                backgroundColor: Colors.grey.shade200,
                color: const Color(0xFF0F766E),
              ),
            ),
            const SizedBox(height: 8), // Small spacing
            // 🌟 ADD THIS ETA TEXT WIDGET HERE:
            if (_isDownloading && _etaText.isNotEmpty)
              Text(
                _etaText,
                style: const TextStyle(
                  color: Color(0xFF0F766E),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),

            const SizedBox(height: 24),

            if (!_isModelReady)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isDownloading
                          ? Colors.orange
                          : const Color(0xFF0F766E),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _isDownloading
                        ? _pauseDownload
                        : _startOrResumeDownload,
                    icon: Icon(
                      _isDownloading
                          ? Icons.pause_circle_filled
                          : Icons.play_circle_filled,
                    ),
                    label: Text(
                      _isDownloading
                          ? "Pause Download"
                          : (_isPaused ? "Resume Download" : "Start Download"),
                    ),
                  ),
                ],
              ),

            const Spacer(),

            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                // 🌟 THE SYNCED HANDOFF FIX
                onPressed: _isModelReady
                    ? () async {
                        // 1. Fetch current preference registry profiles right on execution tap
                        final prefs = await SharedPreferences.getInstance();

                        // 2. Look up if the true saved key exists
                        final String? savedName = prefs.getString('user_name');

                        if (context.mounted) {
                          // 3. Conditional Branching: Route based on profile existence
                          if (savedName == null || savedName.trim().isEmpty) {
                            // User hasn't set up a profile yet -> Send to Profile Screen
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                // Replace 'ProfileSetupScreen' with the exact class name of your setup screen
                                builder: (context) =>
                                    const ProfileScreen(),
                              ),
                            );
                          } else {
                            // Profile exists -> Inject the real extracted name straight into your home screen!
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    HomeScreen(userName: savedName),
                              ),
                            );
                          }
                        }
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E293B),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.shade300,
                  disabledForegroundColor: Colors.grey.shade500,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _isModelReady
                          ? "Enter the Kitchen"
                          : "Awaiting Model Files...",
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (_isModelReady) ...[
                      const SizedBox(width: 8),
                      const Icon(Icons.arrow_forward_rounded, size: 18),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
