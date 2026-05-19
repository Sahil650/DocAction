# 📱 DocAction — Premium Document Scanner

DocAction is a high-performance, premium document scanning mobile application built with Flutter. It combines advanced offline edge detection and optical character recognition (OCR) with a secure, cloud-synced backend to deliver a seamless, state-of-the-art document management experience.

---

## ✨ Key Features

*   **🔍 Smart Edge Detection:** Integrates high-performance native C++ OpenCV libraries for lightning-fast auto-cropping and perspective correction.
*   **📝 Offline OCR (Optical Character Recognition):** Leverages Google's ML Kit to instantly recognize and extract text from your scanned documents offline.
*   **☁️ Secure Cloud Synchronization:** Cross-device cloud sync for your user profile and scanned documents via a robust Flask API backend.
*   **🛡️ Production-Grade Security:** Hardened authentication flow featuring mandatory live connectivity verification and secure token-based storage.
*   **🎨 Premium Royal Blue Aesthetics:** Adheres to a custom, modern royal blue design language with responsive layouts, smooth animations, and high-fidelity micro-interactions.
*   **📂 Multi-level Document Organization:** Intuitive folder structures, sorting options, and interactive list layouts designed for quick access.

---

## 🛠️ Architecture & Tech Stack

### Frontend (Mobile App)
*   **Framework:** [Flutter](https://flutter.dev/) (Dart)
*   **State Management & Services:** Clean service-oriented architecture with decoupled authentication, storage, and scanning layers.
*   **Native Integrations:** Custom JNI/NDK OpenCV integrations, ONNX Runtime, and Google ML Kit.
*   **Icons:** Custom Lucide icons with advanced tree-shaking for a minimized binary footprint.

### Backend (Server API)
*   **Framework:** [Flask](https://flask.palletsprojects.com/) (Python)
*   **Database:** SQLite (local development instance with production-ready schema support)
*   **Libraries:** `python-dotenv` for secure environment variable management, `Flask-SQLAlchemy` ORM.

---

## 🚀 Getting Started

### Prerequisites
*   [Flutter SDK](https://docs.flutter.dev/get-started/install) (Stable channel)
*   [Python 3.10+](https://www.python.org/)
*   Android SDK / Android Emulator or iOS Device

---

### 💻 Installation & Setup

#### 1. Clone & Set Up local repository
```bash
git clone https://github.com/YOUR_GITHUB_USERNAME/doc_scanner_app.git
cd doc_scanner_app
```

#### 2. Start the Backend API Server
```bash
# Navigate to the backend directory
cd backend

# Create a virtual environment and activate it
python -m venv venv
# On Windows (PowerShell):
.\venv\Scripts\Activate.ps1
# On macOS/Linux:
source venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Create your local environment configuration
# Copy template and customize your secrets/host variables
cp .env.example .env

# Run the Flask app
python app.py
```

#### 3. Run the Flutter Application
```bash
# Navigate back to the root directory
cd ..

# Fetch Dart dependencies
flutter pub get

# Launch the app in debug mode
flutter run
```

---

## 📦 Building for Production

To compile the optimized release APK without R8 optimization warnings or size overhead:
```bash
flutter build apk --release
```
*The resulting production-ready APK will be located at `build/app/outputs/flutter-apk/app-release.apk`.*

---

## 📄 License
This project is licensed under the MIT License - see the LICENSE file for details.
