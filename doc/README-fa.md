# Tailscale با Amnezia-WG 1.5

[![GitHub Release](https://img.shields.io/github/v/release/LiuTangLei/tailscale)](https://github.com/LiuTangLei/tailscale/releases/latest) [![Platform Support](https://img.shields.io/badge/platform-Linux%20|%20macOS%20|%20Windows%20|%20Android-blue)](https://github.com/LiuTangLei/tailscale/releases/latest) [![License](https://img.shields.io/badge/license-BSD--3--Clause-green)](LICENSE)

کلاینت بهبودیافته Tailscale با قابلیت مبهم‌سازی **Amnezia-WG 1.5**: شامل ترافیک زائد، امضاهای پروتکل و پنهان‌سازی دست‌دهی (handshake) و هدر (header) برای مقابله با DPI و مسدودسازی. تا زمانی که ویژگی‌های AWG را فعال نکنید، مانند Tailscale معمولی عمل می‌کند.

**📚 زبان‌ها:** [English](README.md) | [中文](doc/README-zh.md) | [فارسی](doc/README-fa.md) | [Русский](doc/README-ru.md)

## 🚀 نصب

| پلتفرم | دستور / اقدام |
|---|---|
| لینوکس | `curl -fsSL https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-linux.sh | bash` |
| macOS | `curl -fsSL https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-macos.sh | bash` |
| ویندوز (PowerShell ادمین) | `iwr -useb https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-windows.ps1 | iex` |
| اندروید | دانلود APK: [نسخه‌ها](https://github.com/LiuTangLei/tailscale-android/releases) |

نسخه اندروید در حال حاضر از همگام‌سازی پیکربندی AWG (دریافت) از یک دستگاه دیگر که قبلاً پیکربندی شده، پشتیبانی می‌کند. از دکمه Sync در داخل برنامه استفاده کنید:

![نمونه همگام‌سازی AWG در اندروید](doc/sync1.jpg)

### میرورها (اختیاری)

اگر GitHub کند یا مسدود است، می‌توانید یک میرور پیشوند (مثلاً `https://your-mirror-site.com`) را از طریق [gh-proxy](https://github.com/hunshcn/gh-proxy) خودتان میزبانی کنید:

```bash
# لینوکس
curl -fsSL https://your-mirror-site.com/https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-linux.sh | bash -s -- --mirror https://your-mirror-site.com

# macOS
curl -fsSL https://your-mirror-site.com/https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-macos.sh | bash -s -- --mirror https://your-mirror-site.com
```

```powershell
# ویندوز
$scriptContent = (iwr -useb https://your-mirror-site.com/https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-windows.ps1).Content; $scriptBlock = [scriptblock]::Create($scriptContent); & $scriptBlock -MirrorPrefix \'https://your-mirror-site.com/\'
```

سیاست اجرایی PowerShell (در صورت مسدود بودن): `Set-ExecutionPolicy RemoteSigned` (یا `Bypass -Scope Process`)

## ⚡ شروع سریع

> نکته: `tailscale amnezia-wg` → `tailscale awg` (نام مستعار)

۱. وارد شوید:

```bash
# رسمی
tailscale up
# Headscale
tailscale up --login-server https://your-headscale-domain
```

۲. دستگاه اول (تولید مقادیر اصلی مشترک):

```bash
tailscale awg set
```

برای H1 تا H4 کلمه `random` را وارد کنید تا مقادیر امن ۳۲ بیتی به صورت خودکار تولید شوند.

۳. همگام‌سازی دستگاه‌های دیگر:
   - دسکتاپ: `tailscale awg sync`
   - اندروید: روی دکمه Sync ضربه بزنید (تصویر بالا را ببینید)
۴. تنظیمات اختیاری برای هر دستگاه: دستور `tailscale awg set` را دوباره اجرا کرده و فقط فیلدهای غیرمشترک را تغییر دهید (S1/S2/H1–H4 را بدون تغییر باقی بگذارید).
۵. دستورات مفید:

```bash
tailscale awg get     # نمایش JSON
tailscale awg reset   # بازگشت به WireGuard معمولی
```

## 🛡️ ویژگی‌ها

### ترافیک زائد و امضاها

بسته‌های جعلی و امضاهای پروتکل را برای فرار از DPI اضافه کنید. با دستگاه‌های استاندارد Tailscale سازگار است:

```bash
# ترافیک زائد پایه
tailscale awg set \'{\"jc\":4,\"jmin\":64,\"jmax\":256}\'

# با امضاهای پروتکل (i1-i5)
tailscale awg set \'{\"jc\":2,\"jmin\":64,\"jmax\":128,\"i1\":\"<b 0xc0><r 16>\",\"i2\":\"<b 0x40><r 12>\"}\'
```

### پنهان‌سازی پروتکل

نیاز دارد که تمام دستگاه‌ها از این نسخه (fork) با تنظیمات یکسان استفاده کنند (امضاهای ix نیازی به تطابق ندارند):

```bash
# مبهم‌سازی دست‌دهی (s1/s2 باید در تمام دستگاه‌ها یکسان باشد)
tailscale awg set \'{\"s1\":10,\"s2\":15}\'

# با فیلدهای هدر (h1-h4 برای مبهم‌سازی پروتکل، باید در تمام دستگاه‌ها یکسان باشد)
tailscale awg set \'{\"s1\":10,\"s2\":15,\"h1\":3946285740,\"h2\":1234567890,\"h3\":987654321,\"h4\":555666777}\'

# ترکیب با امضاها (i1-i5 می‌تواند در هر دستگاه متفاوت باشد)
tailscale awg set \'{\"s1\":10,\"s2\":15,\"h1\":3946285740,\"h2\":1234567890,\"h3\":987654321,\"h4\":555666777,\"i1\":\"<b 0xc0><r 32><c><t>\"}\'
```

## 🎯 پیکربندی

پایه (با کلاینت‌های استاندارد کار می‌کند):

| نوع | JSON | سازگار |
|---|---|---|
| فقط ترافیک زائد | `{\"jc\":4,\"jmin\":64,\"jmax\":256}` | ✅ بله |
| زائد + امضا | `{\"jc\":2,\"jmin\":64,\"jmax\":128,\"i1\":\"<b 0xc0><r 16>\"}` | ✅ بله |

پیشرفته (تمام دستگاه‌ها باید از این نسخه استفاده کرده و مقادیر S1/S2/H1–H4 را به اشتراک بگذارند):

| هدف | مثال | نکات |
|---|---|---|
| پیشوندهای دست‌دهی | `{\"s1\":10,\"s2\":15}` | s1/s2: ۰–۶۴ بایت |
| مبهم‌سازی هدر | `{\"s1\":10,\"s2\":15,\"h1\":123456,\"h2\":789012,\"h3\":345678,\"h4\":901234}` | همه h1–h4 را تنظیم کنید |
| ترکیبی | `{\"jc\":2,\"s1\":10,\"s2\":15,\"h1\":123456,\"h2\":789012,\"h3\":345678,\"h4\":901234,\"i1\":\"<b 0xc0><r 16>\"}` | ترافیک زائد/امضاها اختیاری است |

پارامترها:

- jc (۰–۱۰) با jmin/jmax (۶۴–۱۰۲۴): تعداد بسته‌های زائد و محدوده اندازه آن‌ها
- i1–i5: زنجیره امضای اختیاری (زبان کوچک با فرمت هگز)
- s1/s2 (۰–۶۴ بایت): پیشوندهای پدینگ دست‌دهی (باید در تمام دستگاه‌های AWG یکسان باشد)
- h1–h4 (اعداد صحیح ۳۲ بیتی): مبهم‌سازی هدر (همه یا هیچکدام؛ باید یکسان باشد). مقادیر تصادفی و منحصربه‌فرد انتخاب کنید (پیشنهاد: بین ۵ تا ۲۱۴۷۴۸۳۶۴۷)

نکات: تعداد زیاد بسته‌های زائد یا زنجیره‌های امضای طولانی باعث افزایش تأخیر و مصرف پهنای باند می‌شود.

## 📊 پشتیبانی از پلتفرم‌ها

| پلتفرم | معماری | وضعیت |
|---|---|---|
| لینوکس | x86_64, ARM64 | ✅ کامل |
| macOS | Intel, Apple Silicon | ✅ کامل |
| ویندوز | x86_64, ARM64 | ✅ نصب‌کننده |
| اندروید | ARM64, ARM | ✅ APK (AWG فقط همگام‌سازی) |

## 🔄 مهاجرت از Tailscale رسمی

۱. نصب‌کننده را اجرا کنید - فایل‌های باینری به طور خودکار جایگزین می‌شوند در حالی که تنظیمات شما حفظ می‌شود.
۲. احراز هویت و پیکربندی موجود شما بدون تغییر باقی می‌ماند.
۳. با مبهم‌سازی پایه شروع کنید: `tailscale awg set \'{\"jc\":4,\"jmin\":64,\"jmax\":256}\'`

## ⚠️ نکات

- تا زمانی که پیکربندی AWG اعمال نشود، مانند نسخه معمولی عمل می‌کند.
- ترافیک زائد/امضاها با کلاینت‌های استاندارد سازگار هستند (مقادیر می‌توانند در هر دستگاه متفاوت باشند).
- s1/s2 و h1–h4 نیاز دارند که هر دستگاه در حال ارتباط، مقادیر یکسانی را به اشتراک بگذارد.
- از پیکربندی‌های خود نسخه پشتیبان تهیه کنید (با استفاده از `tailscale awg get`).

## 🛠️ استفاده پیشرفته

### پیکربندی فیلد هدر (h1-h4)

مبهم‌سازی پروتکل برای فرار از شناسایی WireGuard. باید هر ۴ مقدار را تنظیم کنید یا هیچکدام:

```bash
# دستگاه اول: تولید مقادیر تصادفی (برای هر h1-h4 کلمه \'random\' را وارد کنید)
tailscale awg set  # هنگام درخواست، همه h1, h2, h3, h4 را تنظیم کنید

# دریافت پیکربندی JSON
tailscale awg get

# کل JSON را در دستگاه‌های دیگر کپی کنید (باید شامل همه h1-h4 باشد)
tailscale awg set \'{\"s1\":10,\"s2\":15,\"h1\":3946285740,\"h2\":1234567890,\"h3\":987654321,\"h4\":555666777}\'
```

### ایجاد امضاهای پروتکل

۱. ترافیک واقعی را با Wireshark ضبط کنید.
۲. الگوهای هگز را از هدرها استخراج کنید.
۳. فرمت را بسازید: `<b 0xHEX>` (ثابت)، `<r LENGTH>` (تصادفی)، `<c>` (شمارنده)، `<t>` (مهر زمانی).
۴. مثال: `<b 0xc0000000><r 16><c><t>` = هدر شبه-QUIC + ۱۶ بایت تصادفی + شمارنده + مهر زمانی.

### بسته‌های مبهم‌سازی I1–I5 (زنجیره امضا) و CPS (امضای پروتکل سفارشی)

قبل از هر دست‌دهی "ویژه" (هر ۱۲۰ ثانیه)، کلاینت ممکن است تا پنج بسته UDP سفارشی (I1–I5) را در فرمت CPS برای تقلید پروتکل ارسال کند.

**فرمت CPS:**

```text
i{n} = <tag1><tag2><tag3>...<tagN>
```

**انواع تگ:**

| تگ | فرمت | توضیحات | محدودیت‌ها |
|---|---|---|---|
| b | `<b hex_data>` | بایت‌های ثابت برای شبیه‌سازی پروتکل‌ها | طول دلخواه |
| c | `<c>` | شمارنده بسته (۳۲ بیتی، ترتیب بایت شبکه) | یکتا در هر زنجیره |
| t | `<t>` | مهر زمانی یونیکس (۳۲ بیتی، ترتیب بایت شبکه) | یکتا در هر زنجیره |
| r | `<r length>` | بایت‌های تصادفی امن از نظر رمزنگاری | طول ≤ ۱۰۰۰ |

**مثال:**

```text
i1 = <b 0xf6ab3267fa><c><b 0xf6ab><t><r 10>
```

> ⚠️ اگر i1 تنظیم نشده باشد، کل زنجیره (I2–I5) نادیده گرفته می‌شود.

#### ضبط بسته‌های مبهم‌سازی واقعی با Wireshark

۱. Amnezia-WG را شروع کرده و پارامترهای i1–I5 را پیکربندی کنید.
۲. از Wireshark برای نظارت بر پورت UDP استفاده کنید (مثلاً فیلتر: `udp.port == 51820`).
۳. بسته‌های مبهم‌سازی را مشاهده و تحلیل کرده و در صورت نیاز امضاهای پروتکل را استخراج کنید.

برای جزئیات بیشتر، به [مستندات رسمی Amnezia-WG](https://docs.amnezia.org/documentation/instructions/new-amneziawg-selfhosted) مراجعه کنید.

## 🐛 عیب‌یابی

### تأیید نصب

```bash
tailscale version          # بررسی نسخه کلاینت
tailscale awg get          # تأیید پشتیبانی از Amnezia-WG
```

### مشکلات اتصال

```bash
# بازنشانی به WireGuard استاندارد
tailscale awg reset

# ابتدا تنظیمات پایه را امتحان کنید
tailscale awg set \'{\"jc\":2,\"jmin\":64,\"jmax\":128}\'

# بررسی لاگ‌ها (لینوکس)
sudo journalctl -u tailscaled -f
```

### مشکلات PowerShell در ویندوز

از حالت تعاملی برای جلوگیری از مشکلات مربوط به escape کردن JSON استفاده کنید:

```powershell
tailscale awg set  # راه‌اندازی تعاملی
```

## 🤝 پیوندها و پشتیبانی

- نسخه‌ها: [LiuTangLei/tailscale](https://github.com/LiuTangLei/tailscale/releases)
- فایل APK اندروید: [tailscale-android](https://github.com/LiuTangLei/tailscale-android/releases)
- مشکلات نصب‌کننده: [ردیاب مشکلات](https://github.com/LiuTangLei/tailscale-awg-installer/issues)
- مستندات Amnezia-WG: [مستندات رسمی](https://docs.amnezia.org/documentation/instructions/new-amneziawg-selfhosted)

## 📄 مجوز

مجوز BSD 3-Clause (مانند نسخه اصلی Tailscale)

---

**سلب مسئولیت**: فقط برای استفاده آموزشی و حفظ حریم خصوصی قانونی. مسئولیت رعایت قوانین بر عهده شماست.