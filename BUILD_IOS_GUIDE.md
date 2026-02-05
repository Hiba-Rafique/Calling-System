# iOS IPA Build Guide

## 📱 Prerequisites

### Required Tools:
- **macOS** (iOS builds can only be created on Mac)
- **Xcode** (latest version from App Store)
- **Flutter SDK** (stable channel)
- **CocoaPods** (`sudo gem install cocoapods`)
- **Apple Developer Account** (for distribution)

### Development Setup:
```bash
# Install Flutter
flutter channel stable
flutter upgrade

# Install CocoaPods
sudo gem install cocoapods

# Verify setup
flutter doctor
```

## 🔨 Build Methods

### Method 1: Local Build (macOS only)

1. **Run the build script:**
```bash
cd frontend
chmod +x build_ios.sh
./build_ios.sh
```

2. **Manual build:**
```bash
cd frontend
flutter pub get
cd ios
pod install --repo-update
cd ..
flutter build ios --release --no-codesign
```

3. **Locate IPA:**
```
build/ios/ipa/Runner.ipa
```

### Method 2: Codemagic CI/CD

1. **Push to GitHub/GitLab**
2. **Connect to Codemagic**
3. **Use the provided `codemagic.yaml`**
4. **Build automatically**

### Method 3: Xcode Build

1. **Open Xcode project:**
```bash
cd frontend/ios
open Runner.xcworkspace
```

2. **Configure in Xcode:**
   - Select target: Runner
   - Set Bundle Identifier
   - Set Team (Apple Developer)
   - Set Signing Certificate

3. **Build:**
   - Product → Archive
   - Distribute App → Ad Hoc/App Store

## 📋 Configuration Files

### Podfile (iOS Dependencies)
- Platform: iOS 13.0+
- Bitcode disabled
- Swift 5.0
- Proper architecture support

### Info.plist (App Permissions)
- Camera & Microphone access
- Background modes (VOIP, Audio, Notifications)
- Network security settings
- Notification permissions

### Codemagic.yaml (CI/CD)
- Automated iOS builds
- Flutter stable + Xcode latest
- CocoaPods installation
- IPA artifact collection

## 🔐 Code Signing

### Development Build (No Signing)
```bash
flutter build ios --release --no-codesign
```

### Distribution Build (Requires Apple Developer)
1. **Get certificates & provisioning profiles**
2. **Configure Xcode signing**
3. **Build with signing:**
```bash
flutter build ios --release
```

## 📱 Testing the IPA

### Install on Device:
1. **Connect iPhone via USB**
2. **Drag IPA to iTunes/Finder**
3. **Sync to device**
4. **Test calling features**

### TestFlight Distribution:
1. **Upload to App Store Connect**
2. **Create TestFlight build**
3. **Invite testers**
4. **Test background notifications**

## 🚨 Common Issues

### Pod Install Errors:
```bash
cd frontend/ios
pod deintegrate
pod install --repo-update
```

### Build Errors:
- Clean Flutter: `flutter clean`
- Update pods: `pod update`
- Check Xcode version compatibility

### Signing Issues:
- Verify Apple Developer account
- Check provisioning profiles
- Ensure Bundle Identifier matches

## 📊 Build Output

### IPA Location:
```
frontend/build/ios/ipa/Runner.ipa
```

### Build Size:
- **Debug**: ~150MB
- **Release**: ~80MB
- **Compressed**: ~25MB

### Supported Devices:
- **iOS 13.0+**
- **iPhone 6s and newer**
- **iPad Air 2 and newer**

## 🎯 Next Steps

1. **Build IPA locally** or **use Codemagic**
2. **Test on physical device**
3. **Verify background notifications**
4. **Test WebRTC calling**
5. **Submit to App Store** (if ready)

---

## 📞 Support

For build issues:
1. Check `flutter doctor -v`
2. Verify Xcode command line tools
3. Update CocoaPods dependencies
4. Check Apple Developer account status
