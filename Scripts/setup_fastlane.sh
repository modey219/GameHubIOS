#!/bin/bash
# ============================================================
# GameHub iOS - Fastlane Configuration
# بناء تلقائي باستخدام Fastlane
# ============================================================

# Gemfile
cat > Gemfile << 'GEMFILE'
source "https://rubygems.org"

gem "fastlane", "~> 2.220"
gem "cocoapods", "~> 1.15"
GEMFILE

# fastlane/Fastfile
cat > fastlane/Fastfile << 'FASTFILE'
default_platform(:ios)

platform :ios do
  desc "Build Box64 and Wine from source"
  lane :build_dependencies do
    # بناء Box64
    sh("cd ../.. && bash Scripts/build_box64.sh")
    
    # بناء Wine
    sh("cd ../.. && bash Scripts/build_wine.sh")
    
    # نسخ الملفات
    sh("mkdir -p GameHub/Resources/binaries")
    sh("cp build/box64 GameHub/Resources/binaries/")
    sh("cp build/sysroot/usr/bin/wine64 GameHub/Resources/binaries/")
  end

  desc "Build Debug IPA (unsigned)"
  lane :build_debug do
    build_dependencies
    
    gym(
      project: "GameHub.xcodeproj",
      scheme: "GameHub",
      configuration: "Debug",
      sdk: "iphoneos",
      output_directory: "./build",
      output_name: "GameHub-debug.ipa",
      export_method: "development",
      codesigning_identity: "",
      xcargs: "CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO"
    )
  end

  desc "Build Release IPA (unsigned)"
  lane :build_release do
    build_dependencies
    
    gym(
      project: "GameHub.xcodeproj",
      scheme: "GameHub",
      configuration: "Release",
      sdk: "iphoneos",
      output_directory: "./build",
      output_name: "GameHub.ipa",
      export_method: "development",
      codesigning_identity: "",
      xcargs: "CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO"
    )
  end

  desc "Build Signed IPA for App Store"
  lane :build_signed do
    build_dependencies
    
    # تحميل الشهادة
    api_key = app_store_connect_api_key(
      key_id: ENV["APP_STORE_KEY_ID"],
      issuer_id: ENV["APP_STORE_ISSUER_ID"],
      key_content: ENV["APP_STORE_CONNECT_API_KEY"],
      is_key_content_base64: true
    )

    gym(
      project: "GameHub.xcodeproj",
      scheme: "GameHub",
      configuration: "Release",
      sdk: "iphoneos",
      output_directory: "./build",
      output_name: "GameHub-signed.ipa",
      export_method: "app-store",
      export_options: {
        provisioningProfiles: {
          "com.gamehub.ios" => "GameHub Distribution"
        }
      }
    )
  end

  desc "Upload to TestFlight"
  lane :upload_testflight do
    build_signed
    
    upload_to_testflight(
      api_key: app_store_connect_api_key(
        key_id: ENV["APP_STORE_KEY_ID"],
        issuer_id: ENV["APP_STORE_ISSUER_ID"],
        key_content: ENV["APP_STORE_CONNECT_API_KEY"],
        is_key_content_base64: true
      ),
      ipa: "./build/GameHub-signed.ipa",
      skip_waiting_for_build_processing: true
    )
  end

  desc "Upload to GitHub Release"
  lane :upload_github do
    build_release
    
    version = get_version_number(xcodeproj: "GameHub.xcodeproj")
    
    # رفع إلى GitHub
    sh("cd ../.. && gh release create v#{version} ./build/GameHub.ipa --title 'GameHub iOS v#{version}' --draft")
  end

  # === Emergency lanes ===

  desc "Quick build without dependencies"
  lane :quick_build do
    gym(
      project: "GameHub.xcodeproj",
      scheme: "GameHub",
      configuration: "Debug",
      sdk: "iphoneos",
      output_directory: "./build",
      output_name: "GameHub-quick.ipa",
      export_method: "development",
      codesigning_identity: "",
      xcargs: "CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO"
    )
  end

  desc "Clean build folder"
  lane :clean do
    clean_build_artifacts
    sh("rm -rf ../build")
  end
end
FASTFILE

echo "[+] Fastlane configuration created"
echo "    Usage:"
echo "      fastlane build_debug    # Build unsigned debug IPA"
echo "      fastlane build_release  # Build unsigned release IPA"
echo "      fastlane build_signed   # Build signed IPA for App Store"
echo "      fastlane upload_testflight  # Upload to TestFlight"
echo "      fastlane upload_github  # Upload to GitHub Release"
