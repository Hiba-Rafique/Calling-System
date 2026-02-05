#!/bin/bash

# iOS Build Script for Flutter App
# This script builds the Flutter app as an IPA file for iOS

echo "🔨 Starting iOS build process..."

# Check if we're on macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    echo "❌ iOS builds can only be created on macOS"
    exit 1
fi

# Check if Xcode is installed
if ! command -v xcodebuild &> /dev/null; then
    echo "❌ Xcode is not installed. Please install Xcode from the App Store."
    exit 1
fi

# Navigate to frontend directory
cd frontend || exit 1

echo "📦 Getting Flutter dependencies..."
flutter pub get

echo "🍎 Installing CocoaPods dependencies..."
cd ios
pod install --repo-update
cd ..

echo "🔨 Building iOS IPA..."
flutter build ios --release --no-codesign

# Check if build was successful
if [ $? -eq 0 ]; then
    echo "✅ iOS build completed successfully!"
    echo "📱 IPA file location: build/ios/ipa/"
    ls -la build/ios/ipa/
else
    echo "❌ iOS build failed!"
    exit 1
fi
