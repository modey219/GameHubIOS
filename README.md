# GameHub iOS

### تشغيل ألعاب الكمبيوتر على iPhone بدون إنترنت أو سحابة

---

## كيف يعمل

```
 juego.exe (PC)
       ↓
    Box64 (ترجمة x86_64 → ARM64)
       ↓
    Wine (واجهة Windows API)
       ↓
    MoltenVK (Vulkan → Metal)
       ↓
    Metal (رسومات iPhone)
```

**1. حمّل الـ IPA:**
- من تبويب **Actions** → آخر build
- في الأسفل ستجد **Artifacts** → **GameHub-iOS**
- حمّل الملف

**2. ثبّت على iPhone:**

| الطريقة | الموقع | السهولة |
|---------|--------|---------|
| **AltStore** | [altstore.io](https://altstore.io) | سهل |
| **Sideloadly** | [sideloadly.io](https://sideloadly.io) | سهل |
| **Scarlet** | [scarletinstall.com](https://scarletinstall.com) | سهل |
| **Xcode** (oppfinder USB) | مثبت على Mac | متوسط |

**3. فعّل JIT:**
- ثبّت **StikDebug** من App Store
- افتح StikDebug → اضغط "Enable JIT"
- اختر GameHub
- عد إلى GameHub وابدأ اللعب

---

## ربط اللعبة

### إضافة لعبة

1. افتح GameHub
2. اضغط **+** في المكتبة
3. حدد ملف `.exe` من Files App
4. اضغط **Add Game**

### نقل ملفات من الكمبيوتر

```
الطريقة 1 (USB):
  - وصّل iPhone بالكمبيوتر
  - افتح Finder → iPhone → File Sharing → GameHub
  - اسحب ملفات اللعبة

الطريقة 2 (WiFi - WebDAV):
  - في GameHub اذهب للإعدادات
  - فعّل WebDAV Server
  - على الكمبيوتر افتح المتصفح
  - اكتب: http://IPHONE_IP:8080
  - ارفع ملفات اللعبة

الطريقة 3 (Cloud):
  - ارفع ملفات اللعبة على Google Drive / iCloud
  - حمّلها على iPhone من Files App
  - في GameHub اختر Import
```

---

## إعدادات مهمة

### رسومات
| الإعداد | القيمة | ملاحظة |
|---------|--------|--------|
| GPU Driver | MoltenVK | الأفضل لـ iOS |
| DXVK | مفعّل | لألعاب DirectX 11 |
| VKD3D | مفعّل | لألعاب DirectX 12 |
| Max FPS | 60 | قلّل للألعاب الثقيلة |
| VSync | مفعّل | يمنع الت撕裂 |

### Box64
| الإعداد | القيمة | ملاحظة |
|---------|--------|--------|
| Dynarec | مفعّل | **يتطلب JIT** |
| Big Block | مفعّل | تسريع |
| Strong Memory | مفعّل | استقرار |
| Safe Flags | مفعّل | أمان |

---

## حل المشاكل

### "اللعبة بطيئة"
- تأكد JIT مفعّل (StikDebug)
- قلّل Max FPS
- أ关闭 VSync

### "لا يوجد صوت"
- غيّر Audio Driver في الإعدادات
- جرّب Core Audio بدل PulseAudio

### "اللعبة لا تعمل"
- تأكد ملف `.exe` هو Win64 (وليس Win32)
- جرّب تغيير Renderer
- فعّل Debug logging

### "JIT لا يعمل"
- تأكد StikDebug مثبّت
- أعد تشغيل StikDebug ثم GameHub
- في Worst case: استخدم JIT-less mode (بطيء)

---

## المواصفات المطلوبة

- iPhone 12 أو أحدث
- iOS 15.0+
- مساحة حرة: 2GB+
- لا يحتاج إنترنت بعد التثبيت

---

## الملفات

```
GameHubiOS/
├── GameHub/                 # الكود الرئيسي
│   ├── GameHubApp.swift     # نقطة البداية
│   ├── SwiftUI/             # الواجهات
│   └── Core/                # المحرك
│       ├── Box64/           # ترجمة x86
│       ├── Wine/            # Windows API
│       ├── Graphics/        # MoltenVK
│       ├── JIT/             # StikDebug
│       ├── Input/           # يد تحكم
│       └── Audio/           # صوت
├── Scripts/                 # سكربتات البناء
├── .github/workflows/       # بناء سحابي
└── README.md                # هذا الملف
```

---

## الترخيص

MIT License - مفتوح المصدر
