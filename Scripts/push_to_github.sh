#!/bin/bash
# ============================================================
# GameHub iOS - Push to GitHub
# شغّل هذا السكربت من داخل مجلد GameHubiOS
# ============================================================

set -e

echo "========================================="
echo "  رفع مشروع GameHub iOS إلى GitHub"
echo "========================================="
echo ""

# تحقق من وجود git
if ! command -v git &> /dev/null; then
    echo "[!] Git غير مثبّت. ثبّته أولاً:"
    echo "    brew install git"
    exit 1
fi

# تحقق من إعدادات git
if [ -z "$(git config user.name)" ]; then
    echo "أدخل اسمك:"
    read -p "Name: " git_name
    git config --global user.name "$git_name"
fi

if [ -z "$(git config user.email)" ]; then
    echo "أدخل بريدك الإلكتروني:"
    read -p "Email: " git_email
    git config --global user.email "$git_email"
fi

# اسم الريبو
echo ""
echo "أدخل مسار الريبو من GitHub:"
echo "(مثال: https://github.com/USERNAME/GameHubiOS.git)"
echo ""
read -p "Git repo URL: " REPO_URL

if [ -z "$REPO_URL" ]; then
    echo "[!] لم تدخل رابط الريبو"
    exit 1
fi

# تهيئة Git
echo "[1/5] تهيئة Git..."
git init
git branch -M main

# إضافة الملفات
echo "[2/5] إضافة الملفات..."
git add .

# الحذف الأولي
echo "[3/5] أول commit..."
git commit -m "feat: GameHub iOS - PC game emulator for iPhone

- Box64 for x86_64 → ARM64 translation
- Wine for Windows API support
- MoltenVK for Vulkan → Metal graphics
- SwiftUI interface with game library
- Container management system
- Touch/gamepad input mapping
- JIT support via StikDebug
- Audio via PulseAudio"

# ربط الريبو
echo "[4/5] ربط الريبو..."
git remote remove origin 2>/dev/null || true
git remote add origin "$REPO_URL"

# رفع الكود
echo "[5/5] رفع الكود..."
git push -u origin main

echo ""
echo "========================================="
echo "  تم الرفع بنجاح!"
echo "========================================="
echo ""
echo "الآن:"
echo "  1. افتح ريبو على GitHub"
echo "  2. اضغط تبويب Actions"
echo "  3. سترى البناء يعمل (30-60 دقيقة)"
echo "  4. بعد الانتهاء، حمّل الـ IPA من Artifacts"
echo ""
echo "للثبيت:"
echo "  - استخدم AltStore أو Sideloadly"
echo "  - أو Xcode: Devices & Simulators → +"
echo ""
