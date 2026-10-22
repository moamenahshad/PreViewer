<img width="76" height="76" alt="أيقونة PreViewer" src="https://github.com/user-attachments/assets/62a7305d-c1c2-4c68-bf42-c1c8ed8e8e97" />

# PreViewer

[English](README.md)

PreViewer هو تطبيق macOS أصلي وخفيف لعرض مستندات PDF وDjVu. صُمم للقراءة: افتح المستند، تصفح الصفحات، ابحث عندما يتوفر نص، حدد النص وانسخه، واترك ملفاتك دون تعديل.

تتبع الواجهة أسلوب Preview المألوف في macOS، مع نافذة ترحيب، والمستندات الأخيرة، والصور المصغرة، والتمرير المستمر، وأدوات التكبير، والقوائم الأصلية، والسحب والإفلات، والمظهرين الفاتح والداكن.

<img width="732" height="824" alt="نافذة ترحيب PreViewer" src="https://github.com/user-attachments/assets/0d779d16-7ca6-4bb4-bf0a-847a3727630b" />

## الإصدار الحالي

**PreViewer 0.1.2 Beta** متوفر حاليًا لأجهزة Mac التي تعمل بمعمارية Intel.

نزّل ملف ZIP من [صفحة الإصدارات في GitHub](https://github.com/moamenahshad/PreViewer/releases)، وافتحه، ثم اسحب `PreViewer.app` إلى مجلد Applications. الإصدار التجريبي غير موثق بتوقيع Apple Developer مدفوع، لذلك قد يطلب macOS تأكيد الفتح في المرة الأولى.

## الميزات

- عرض ملفات PDF و`.djvu` و`.djv`
- تصفح الصفحات عبر شريط الصور المصغرة
- التمرير المستمر والتنقل بين الصفحات
- التكبير والتصغير والحجم الفعلي وملاءمة النافذة
- البحث في نص PDF ونص DjVu المتاح
- تحديد النص ونسخه من مستندات DjVu التي تحتوي على مناطق كلمات
- نافذة ترحيب مع المستندات الأخيرة
- سحب الملفات وإفلاتها داخل التطبيق
- قوائم macOS الأصلية واختصارات لوحة المفاتيح وقائمة النقر بالزر الأيمن
- دعم العربية والإنجليزية مع تخطيط من اليمين إلى اليسار للعربية
- دعم المظهر الفاتح والداكن
- قراءة فقط؛ لا يتم تعديل الملفات المصدر
- تصدير DjVu إلى PDF مع خيارات الجودة والدقة

## ما لم يُنفذ بعد

يركز PreViewer حاليًا على القراءة وتصدير DjVu إلى PDF. الميزات التالية غير متوفرة في هذا الإصدار:

- التحويل من PDF إلى DjVu
- OCR
- التعليقات والتحرير
- ضغط MRC
- فتح ملفات PDF المحمية التي تتطلب كلمة مرور
- دعم Apple Silicon

## متطلبات النظام

- جهاز Mac بمعمارية Intel (`x86_64`)
- macOS 26 أو أحدث
- لا يحتاج المستخدم إلى Homebrew أو MacPorts أو أدوات سطر أوامر لتشغيل التطبيق

هدف النشر الحالي هو macOS 26 لأن مكتبات DjVu الأصلية المضمنة تتطلبه. سيُدرس دعم Apple Silicon بعد نضج إصدار Intel وقارئ المستندات.

## البناء من المصدر

يتطلب البناء Xcode 26.5. الاعتماديات موجودة داخل المستودع، ولا يتم تثبيت أي شيء عبر Homebrew أو MacPorts.

```sh
xcodebuild -project 'DjVu Preview.xcodeproj' -scheme 'DjVu Preview' \
  -configuration Debug -destination 'platform=macOS,arch=x86_64' \
  -derivedDataPath Build -jobs 1 CODE_SIGNING_ALLOWED=NO build

xcodebuild -project 'DjVu Preview.xcodeproj' -scheme 'DjVu Preview' \
  -configuration Debug -destination 'platform=macOS,arch=x86_64' \
  -derivedDataPath Build -jobs 1 -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO test
```

ينتج التطبيق في `Build/Build/Products/Debug/PreViewer.app`. يحتفظ مشروع Xcode والمخطط بالاسم التاريخي `DjVu Preview`، بينما اسم المنتج واسم الحزمة الظاهر للمستخدم هو `PreViewer`.

## القارئ

يستخدم عرض PDF والبحث فيه إطار PDFKit. تُفك صفحات DjVu عند الحاجة باستخدام DjVuLibre المضمنة وتُعرض مباشرة داخل القارئ؛ لا يتم إنشاء PDF وسيط عند فتح DjVu. يمكن لمناطق الكلمات الموجودة في DjVu توفير تحديد النص ونسخه والبحث فيه دون OCR.

يحافظ القارئ على استهلاك الذاكرة ضمن حدود مناسبة للكتب الكبيرة: تُعطى الصفحات المرئية الأولوية، وتُلغى مهام الصفحات البعيدة، وتُنشأ الصور المصغرة عند الحاجة، وللصور النقطية وDjVu ذاكرات تخزين محدودة. لا تتجاوز المعاينات 4096 بكسل على الحافة الطويلة.

يمكن لشريط المحتويات عرض العلامات الرقمية الداخلية عندما يوفرها ملف DjVu. تُعطل الوجهات غير المدعومة. يتولى PDFKit مخططات PDF.

## تصدير DjVu إلى PDF

عند فتح مستند DjVu، اختر **ملف > تصدير** (`Shift-Command-E`). تتيح نافذة التصدير اختيار الجودة والدقة، وتحديد الوجهة، ومتابعة التقدم، والإلغاء الآمن. يبقى ملف DjVu المصدر دون تعديل.

يعتمد التصدير على صورة الصفحة المفكوكة. يمكن تحويل نص مناطق الكلمات الموجودة إلى طبقة PDF غير مرئية وقابلة للتحديد؛ لا يتم تنفيذ OCR. تُحفظ البيانات الوصفية المدعومة والعلامات الرقمية للصفحات عند توفرها. تُدمج طبقات DjVu ولا تُصدّر كطبقات MRC.

## اختصارات لوحة المفاتيح

| الإجراء | الاختصار |
| --- | --- |
| فتح / الترحيب / إغلاق | Command-O / Command-N / Command-W |
| بحث / النتيجة التالية / السابقة | Command-F / Command-G / Shift-Command-G |
| الصفحة السابقة / التالية | Command-Up / Command-Down |
| إظهار الصور المصغرة | Option-Command-1 |
| تكبير / تصغير | Command-Plus / Command-Minus |
| الحجم الفعلي / ملاءمة النافذة | Command-0 / Command-9 |
| تصدير DjVu | Shift-Command-E |
| ملء الشاشة | Control-Command-F |

## التوثيق

- [البنية](Documentation/architecture.md)
- [دليل الاختبار](Documentation/testing.md)
- [ملاحظات تنفيذ DjVu](Documentation/djvu.md)
- [القيود المعروفة](Documentation/limitations.md)
- [معلومات الترخيص](Documentation/licensing.md)
- [إشعارات الاعتماديات](Vendor/DjVuLibre/NOTICE.md)

## الترخيص

لا يتضمن PreViewer موارد Preview الخاصة بApple أو كودًا مملوكًا لمحولات تجارية. كود DjVuLibre المضمن مرخص بموجب GPL-2.0-or-later. يجب أن يلتزم أي توزيع بالترخيص، بما في ذلك إشعارات الترخيص ومتطلبات توفير المصدر المقابلة. لا يعلن التطبيق حاليًا عن ترخيص جذر مستقل؛ راجع [Documentation/licensing.md](Documentation/licensing.md) قبل إعادة توزيع نسخ معدلة.

## الملاحظات

هذا إصدار تجريبي مبكر. عند العثور على مشكلة، أرفق إصدار macOS، ومعمارية الجهاز، ونوع الملف، والخطوات التي تعيد المشكلة في GitHub Issue.
