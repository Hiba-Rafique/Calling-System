#!/bin/bash

# iOS Build Script for Flutter Calling System App
# This script builds the Flutter app as an IPA file for iOS with proper configuration

echo "🔨 Starting iOS build process for Calling System..."

# Check if we're on macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    echo "❌ iOS builds can only be created on macOS"
    echo "💡 Use Codemagic CI/CD for automated iOS builds"
    exit 1
fi

# Check if Xcode is installed
if ! command -v xcodebuild &> /dev/null; then
    echo "❌ Xcode is not installed. Please install Xcode from the App Store."
    exit 1
fi

# Navigate to frontend directory
cd frontend || exit 1

echo "🧹 Cleaning previous builds..."
flutter clean

echo "📦 Getting Flutter dependencies..."
flutter pub get

echo "🍎 Installing CocoaPods dependencies..."
cd ios
pod install --repo-update
pod update
cd ..

echo "🔨 Building iOS IPA with Calling System configuration..."
flutter build ios --release --no-codesign --export-options-plist=ios/ExportOptions.plist

# Check if build was successful
if [ $? -eq 0 ]; then
    echo "✅ iOS build completed successfully!"
    echo "📱 Calling System IPA file location: build/ios/ipa/"
    ls -la build/ios/ipa/
    echo "🎯 Ready for App Store submission or testing!"
else
    echo "❌ iOS build failed!"
    echo "🔧 Check the build logs above for errors"
    exit 1
fi
