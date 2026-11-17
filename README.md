# SugarLeaf AI — Flutter mobile app

Cross-platform Android/iOS starter app for sugarcane leaf disease detection using the hosted Roboflow YOLOv11 model.

## Model configuration

- Roboflow project/model: `sugarcane-leaf-diseases/2`
- Hosted inference endpoint: `https://serverless.roboflow.com/sugarcane-leaf-diseases/2`
- Dataset classes: `Healthy`, `Banded`, `Brown-Spot`, `Dried`
- Dataset: https://universe.roboflow.com/leafdiseases1/sugarcane-leaf-diseases

The app sends a selected/captured image as base64 form data to the Roboflow hosted inference endpoint and displays bounding boxes, class labels, confidence scores, per-category detection counts (Healthy, Banded, Brown-Spot, Dried), category percentages, total detections, and recent scan history.

## Important API-key security note

For quick local testing, enter your own Roboflow API key in the app's Settings screen. The key is stored in the device's app preferences and sent as a Bearer authorization header. **Do not distribute this build publicly with a client-side API key.** For production, place Roboflow inference behind an authenticated backend (e.g. FastAPI/Cloud Run) and remove the client-side key setting.

## Run

1. Install Flutter SDK and Android Studio (Android) and Xcode (iOS; macOS required).
2. Create the platform scaffolding:
   ```bash
   flutter create --platforms=android,ios .
   ```
   Run this from this folder. If Flutter asks to overwrite `lib/main.dart`, keep the supplied file.
3. Fetch packages:
   ```bash
   flutter pub get
   ```
4. Run:
   ```bash
   flutter run
   ```
5. Open **Settings** in the app, paste your Roboflow API key, and save.
6. Capture or choose a clear sugarcane leaf photo and tap **Detect disease**.

## Android permissions

`image_picker` uses Android's system photo picker and camera intent. Add camera permission to `android/app/src/main/AndroidManifest.xml` inside `<manifest>` if required by your target Android version:
```xml
<uses-permission android:name="android.permission.CAMERA" />
```

## iOS permissions

Add these keys to `ios/Runner/Info.plist` inside the top-level `<dict>`:
```xml
<key>NSCameraUsageDescription</key>
<string>SugarLeaf AI uses the camera to capture sugarcane leaf images for disease screening.</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>SugarLeaf AI accesses selected photos for sugarcane leaf disease screening.</string>
```

## Notes and limitations

- The public Roboflow project page identifies model version 2 as a YOLOv11 object-detection model and lists 154 images and four classes.
- The published model metrics shown on the project page are modest (mAP@50 25.2%, precision 46.3%, recall 32.0%). Treat results as preliminary screening, not a definitive plant-health diagnosis.
- Internet connectivity is required for hosted inference.
- Verify the model's current API access, rate limits, and account terms in Roboflow before deployment.
- The app deliberately labels low-confidence/no-detection cases as inconclusive and does not invent a disease label.


## Category count and summary

After inference, the app groups every returned bounding-box prediction by class and displays:
- count per category (Healthy, Banded, Brown-Spot, Dried);
- percentage share of all detections;
- total detected regions;
- individual detection labels and confidence values.

**Counting interpretation:** the count is the number of YOLOv11 detection boxes per class, not necessarily the number of individual leaves or plants. It represents leaf counts only if the model was trained to return exactly one detection per leaf.

## Build an Android APK without upgrading your Mac

This repository includes a GitHub Actions workflow at `.github/workflows/build-android-apk.yml`.
It builds a signed **debug APK** in GitHub's cloud runner, so your macOS 13 machine does not need to run Flutter or Xcode.

1. Upload/commit the entire project, including the `.github` folder, to the repository's `main` or `master` branch.
2. Open the repository on GitHub and select **Actions**.
3. Choose **Build SugarLeaf AI Android APK**.
4. Click **Run workflow** (or wait for the push-triggered build).
5. Open the completed workflow run and download the artifact named `sugarleaf-ai-android-debug-apk`.
6. Extract the artifact ZIP. It contains `app-debug.apk`.
7. Transfer `app-debug.apk` to an Android phone and install it. Allow installation from that source if Android asks.

This is a debug/test APK, not a Play Store production release. It is generated and signed for testing by the Android build configuration. The Mac's macOS 13 limitation is bypassed because the build runs on GitHub-hosted Linux.

For a production release, configure Android app signing with a private keystore stored as GitHub Actions secrets. Never commit a keystore or passwords to the repository.
