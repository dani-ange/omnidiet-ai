# OmniDiet AI — Privacy-First, Fully Offline AI Nutrition Ecosystem

OmniDiet AI is an enclosed, confidential, edge-computed mobile intelligence framework designed to assist patients managing chronic metabolic conditions like type 2 diabetes. 

By executing a large language model entirely on-device, the system operates with **zero internet dependencies and absolute data privacy**, making it fully viable for rural communities, open markets, and environments with poor connectivity.

## 🚀 Core Functionalities

* **Model Download & Upkeep Module:** Built-in gatekeeper diagnostic script that verifies model integrity ($2.4\text{ GB}$) and supports chunk-based downloads with pause/resume functionality.
* **Patient Profile Customization:** Clinically custom boundaries (e.g., sodium limits, allergen blocks) stored locally in a secure sandbox to shape every AI response.
* **Global Info Hub (Proactive Chat):** A high-speed conversational terminal featuring the proactive *OmniDiet Chef* persona, delivering suitability verdicts, metabolic explanations, and preparation safety tips.
* **Kitchen Chef Module (Vision Wizard):** Multimodal ingredient processing that isolates items via computer vision, paints bounding boxes, crops low-confidence items for verification, and generates custom 1-Day to 7-Day meal strategy plans.
* **Vision Plate Analyzer:** Spatial detection module that analyzes post-preparation meal layout ratios (starches vs. proteins vs. greens) against the patient profile to prevent glycemic spikes.

## 🛠️ Tech Stack & Grounding Data

* **Frontend:** Flutter SDK & Dart Language (Asynchronous state tracking, CustomPaint vector boundaries).
* **On-Device AI Engine:** Google AI Edge LiteRT (formerly TensorFlow Lite) LLM Inference SDK running `gemma-4-E2B-it.litertlm`.
* **Local Reference Data:** Decoupled, local JSON nutrition asset derived strictly from the **FAO AGRIS repository** (*Comprehensive Database for Nutrient Composition of Major Food Items and Underutilized Plant Species in Africa, 2025*).

## 🧠 Engineering Triumphs

* **Dynamic Session Purging:** Solved mobile memory resource crashes (`FAILED_PRECONDITION`) between screen context switches by mapping custom frontend flags to clear native background coroutine locks on initialization.
* **Decoupled JSON Architecture:** Dropped secondary embedding models (`Gecko_1024_quant.tflite`) to eliminate out-of-memory app terminations, replacing them with dynamic raw string matching over local database matrices.

---

## 📂 Developer Setup: Model File Provisioning Options

The application expects the $2.4\text{ GB}$ model binary (`gemma-4-E2B-it.litertlm`) to reside within the application's internal sandboxed filesystem namespace. Developers can provision this file using either the built-in download screen or via the direct **Android Debug Bridge (ADB)** side-loading option below:

### Option: Manual Model Transfer via ADB
For rapid internal development deployments, connect your physical evaluation hardware via USB and use the following scoped commands sequentially to capture your device number and stage the weights directly into the secure application data tree:

```bash
# 1. Identify attached hardware targets and copy your device's serial number string ID
adb devices

# 2. Push the local binary payload to the shared temporary storage directory
adb -s 15331455BD002732 push "C:\Users\HP ZBOOK\Downloads\gemma-4-E2B-it.litertlm" /data/local/tmp/

# 3. Duplicate the asset into the app's sandboxed internal files path using runtime privileges
adb -s 15331455BD002732 shell "run-as com.example.lite_rt_chat cp /data/local/tmp/gemma-4-E2B-it.litertlm files/"

# 4. Verify successful file size and transfer positioning allocations
adb -s 15331455BD002732 shell "run-as com.example.lite_rt_chat ls -lh files/"

# 5. Flush the temporary folder storage space to keep system memory clean
adb -s 15331455BD002732 shell "rm /data/local/tmp/gemma-4-E2B-it.litertlm"