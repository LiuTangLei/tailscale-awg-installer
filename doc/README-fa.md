# Tailscale با Amnezia-WG 1.5

Tailscale با پشتیبانی از **Amnezia-WG 1.5** — پروتکل مخفی‌سازی برای عبور از DPI و فیلترینگ.

**📚 زبان‌ها:** [English](../README.md) | [中文](README-zh.md) | [فارسی](README-fa.md) | [Русский](README-ru.md)

## 🚀 نصب

**لینوکس:**

```bash
curl -fsSL https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-linux.sh | bash
```

**مک‌اواس:**

```bash
curl -fsSL https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-macos.sh | bash
```

**ویندوز (PowerShell به عنوان مدیر):**

```powershell
iwr -useb https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-windows.ps1 | iex
```

### دانلود از میرور (برای مناطق با محدودیت)

توصیه می‌شود از دامنه میرور اختصاصی خودتان (مثلاً <https://your-mirror-site.com>) استفاده کنید تا از مسدود شدن میرورهای عمومی جلوگیری شود. برای راه‌اندازی سریع می‌توانید از [gh-proxy](https://github.com/hunshcn/gh-proxy) استفاده کنید.

```bash
# لینوکس:
curl -fsSL https://your-mirror-site.com/https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-linux.sh | bash -s -- --mirror https://your-mirror-site.com
```

```bash
# مک‌اواس:
curl -fsSL https://your-mirror-site.com/https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-macos.sh | bash -s -- --mirror https://your-mirror-site.com
```

```powershell
# ویندوز:
$scriptContent = (iwr -useb https://your-mirror-site.com/https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-windows.ps1).Content;$scriptBlock = [scriptblock]::Create($scriptContent); & $scriptBlock -MirrorPrefix 'https://your-mirror-site.com/'
```

**مشکل اجرای اسکریپت در PowerShell:**

```powershell
# اگر اجرای اسکریپت مسدود است:
Set-ExecutionPolicy RemoteSigned
# یا
Set-ExecutionPolicy Bypass -Scope Process
```

## ⚡ شروع سریع

1. طبق راهنمای بالا نصب کنید
2. وارد Tailscale شوید:

```bash
# کنترل پنل رسمی
tailscale up

# برای Headscale
tailscale up --login-server https://your-headscale-domain
```

3. در صورت نیاز مخفی‌سازی را فعال کنید:

```bash
# دور زدن پایه DPI (سازگار با همه نودها)
tailscale amnezia-wg set '{"jc":4,"jmin":64,"jmax":256}'

# مشاهده تنظیمات فعلی
tailscale amnezia-wg get

# تنظیم تعاملی
tailscale amnezia-wg set

# بازگشت به WireGuard استاندارد
tailscale amnezia-wg reset
```

## 🛡️ قابلیت‌های Amnezia-WG

### ترافیک جعلی و امضاها

امکان افزودن پکت‌های جعلی و امضاهای پروتکل برای عبور از DPI — سازگار با نودهای استاندارد Tailscale:

```bash
# ترافیک جعلی پایه
tailscale amnezia-wg set '{"jc":4,"jmin":64,"jmax":256}'

# با امضاهای پروتکل (i1-i5)
tailscale amnezia-wg set '{"jc":2,"jmin":64,"jmax":128,"i1":"<b 0xc0><r 16>","i2":"<b 0x40><r 12>"}'
```

### مخفی‌سازی پروتکل

برای مخفی‌سازی، همه نودها باید این فورک را با تنظیمات یکسان اجرا کنند (امضاهای ix می‌تواند متفاوت باشد):

```bash
# مخفی‌سازی دست‌دهی (s1/s2 باید یکسان باشد)
tailscale amnezia-wg set '{"s1":10,"s2":15}'

# فیلدهای header (h1-h4 باید یکسان باشد)
tailscale amnezia-wg set '{"s1":10,"s2":15,"h1":3946285740,"h2":1234567890,"h3":987654321,"h4":555666777}'

# ترکیب با امضاها (i1-i5 می‌تواند متفاوت باشد)
tailscale amnezia-wg set '{"s1":10,"s2":15,"h1":3946285740,"h2":1234567890,"h3":987654321,"h4":555666777,"i1":"<b 0xc0><r 32><c><t>"}'
```

## 🎯 راهنمای پیکربندی

**پیکربندی‌های پایه (سازگار با کلاینت‌های استاندارد):**

| نوع       | پیکربندی                                              | وضعیت        |
| --------- | ----------------------------------------------------- | ------------ |
| فقط جعلی  | `{"jc":4,"jmin":64,"jmax":256}`                       | ✅ استاندارد |
| جعلی+امضا | `{"jc":2,"jmin":64,"jmax":128,"i1":"<b 0xc0><r 16>"}` | ✅ استاندارد |

**پیکربندی‌های پیشرفته (همه نودها باید فورک باشند):**

| هدف     | مثال                                                                                             | توضیح            |
| ------- | ------------------------------------------------------------------------------------------------ | ---------------- |
| دست‌دهی | `{"s1":10,"s2":15}`                                                                              | s1/s2: ۰–۶۴      |
| هدر     | `{"s1":10,"s2":15,"h1":123456,"h2":789012,"h3":345678,"h4":901234}`                              | h1–h4: ۳۲بیتی    |
| ترکیبی  | `{"jc":2,"s1":10,"s2":15,"h1":123456,"h2":789012,"h3":345678,"h4":901234,"i1":"<b 0xc0><r 16>"}` | jc/i1-i5 اختیاری |

> ⚠️ پکت‌های جعلی (jc) و زنجیره‌های امضای طولانی (i1–i5) می‌تواند باعث افزایش تأخیر و مصرف پهنای باند شود. با احتیاط استفاده کنید.

### توضیح پارامترها

- **jc**: تعداد پکت‌های جعلی (۰–۱۰، نیازمند jmin/jmax)
- **jmin/jmax**: اندازه پکت جعلی (۶۴–۱۰۲۴ بایت، فقط با jc)
- **i1-i5**: امضای پروتکل (hex-string)
- **s1/s2**: پیشوند دست‌دهی (۰–۶۴ بایت، همه نودها یکسان)
- **h1-h4**: هدرهای مخفی‌سازی (۴ مقدار ۳۲بیتی، همه نودها یکسان، ترجیحاً متفاوت، بازه ۵–۲۱۴۷۴۸۳۶۴۷)

### بازه‌های رسمی

| پارامتر    | بازه         | توضیح                  |
| ---------- | ------------ | ---------------------- |
| I1-I5      | hex-string   | امضا برای تقلید پروتکل |
| S1, S2     | ۰–۶۴ بایت    | پیشوند دست‌دهی         |
| Jc         | ۰–۱۰         | تعداد پکت جعلی         |
| Jmin, Jmax | ۶۴–۱۰۲۴ بایت | اندازه پکت جعلی        |
| H1-H4      | ۰–۴۲۹۴۹۶۷۲۹۵ | مقادیر ۳۲بیتی برای هدر |

## 📊 پشتیبانی پلتفرم‌ها

| پلتفرم  | معماری‌ها            | وضعیت                   |
| ------- | -------------------- | ----------------------- |
| لینوکس  | x86_64, ARM64        | ✅ پشتیبانی کامل        |
| مک‌اواس | Intel, Apple Silicon | ✅ پشتیبانی کامل        |
| ویندوز  | x86_64, ARM64        | ✅ نصب‌کننده PowerShell |

## 🔄 مهاجرت از Tailscale رسمی

1. نصب‌کننده را اجرا کنید — فایل‌های اجرایی جایگزین می‌شوند اما تنظیمات شما حفظ می‌شود
2. احراز هویت و پیکربندی شما بدون تغییر باقی می‌ماند
3. برای شروع، مخفی‌سازی پایه را فعال کنید: `tailscale amnezia-wg set '{"jc":4,"jmin":64,"jmax":256}'`

## ⚠️ نکات مهم

- رفتار پیش‌فرض: تا زمانی که مخفی‌سازی فعال نشود، مثل نسخه رسمی عمل می‌کند
- پکت‌های جعلی (jc) و امضاها (i1-i5): با هر نود Tailscale سازگار است، هر نود می‌تواند مقادیر متفاوت داشته باشد
- مخفی‌سازی (s1/s2) و هدرها (h1-h4): همه نودها باید مقادیر یکسان داشته باشند
- تنظیمات پایه تأثیر کمی بر عملکرد دارد

## 🛠️ استفاده پیشرفته

### پیکربندی هدرها (h1-h4)

مخفی‌سازی پروتکل برای عبور از تشخیص WireGuard. باید هر ۴ مقدار را تنظیم کنید یا هیچ‌کدام:

```bash
# نود اول: مقادیر تصادفی بسازید (برای هر h1-h4 بنویسید random)
tailscale amnezia-wg set  # h1, h2, h3, h4 را هنگام درخواست وارد کنید

# دریافت JSON پیکربندی
tailscale amnezia-wg get

# کپی JSON به سایر نودها (باید همه h1-h4 باشد)
tailscale amnezia-wg set '{"s1":10,"s2":15,"h1":3946285740,"h2":1234567890,"h3":987654321,"h4":555666777}'
```

### ساخت امضای پروتکل

1. ترافیک واقعی را با Wireshark ضبط کنید
2. الگوهای hex را از هدرها استخراج کنید
3. فرمت: `<b 0xHEX>` (ثابت)، `<r LENGTH>` (تصادفی)، `<c>` (شمارنده)، `<t>` (timestamp)
4. مثال: `<b 0xc0000000><r 16><c><t>` = هدر شبیه QUIC + ۱۶ بایت تصادفی + شمارنده + timestamp

### پکت‌های I1–I5 (زنجیره امضا) و CPS (امضای سفارشی)

قبل از هر دست‌دهی "ویژه" (تقریباً هر ۱۲۰ ثانیه)، کلاینت می‌تواند تا ۵ پکت UDP سفارشی (I1–I5) را در قالب CPS برای تقلید پروتکل ارسال کند.

**قالب CPS:**

```text
i{n} = <tag1><tag2><tag3>...<tagN>
```

**انواع تگ:**

| تگ  | فرمت           | توضیحات                                 | محدودیت        |
| --- | -------------- | --------------------------------------- | -------------- |
| b   | `<b hex_data>` | بایت ثابت برای تقلید پروتکل             | طول دلخواه     |
| c   | `<c>`          | شمارنده پکت (۳۲بیت، network order)      | یکتا در زنجیره |
| t   | `<t>`          | timestamp یونیکس (۳۲بیت، network order) | یکتا در زنجیره |
| r   | `<r length>`   | بایت تصادفی امن رمزنگاری                | length ≤ 1000  |

**مثال:**

```text
i1 = <b 0xf6ab3267fa><c><b 0xf6ab><t><r 10>
```

> ⚠️ اگر i1 تنظیم نشود، کل زنجیره (I2–I5) نادیده گرفته می‌شود.

#### ضبط پکت‌های واقعی با Wireshark

1. Amnezia-WG را اجرا و i1–i5 را تنظیم کنید
2. با Wireshark پورت UDP را مانیتور کنید (مثلاً فیلتر: `udp.port == 51820`)
3. پکت‌ها را بررسی و امضاها را استخراج کنید

برای جزئیات بیشتر: [مستندات رسمی Amnezia-WG](https://docs.amnezia.org/documentation/instructions/new-amneziawg-selfhosted)

## 🐛 عیب‌یابی

### بررسی نصب

```bash
tailscale version          # بررسی نسخه کلاینت
tailscale amnezia-wg get   # بررسی پشتیبانی Amnezia-WG
```

### مشکلات اتصال

```bash
# بازگشت به WireGuard استاندارد
tailscale amnezia-wg reset

# ابتدا تنظیمات پایه را امتحان کنید
tailscale amnezia-wg set '{"jc":2,"jmin":64,"jmax":128}'

# مشاهده لاگ‌ها (لینوکس)
sudo journalctl -u tailscaled -f
```

### مشکلات PowerShell

برای جلوگیری از مشکل escape کردن JSON، از حالت تعاملی استفاده کنید:

```powershell
tailscale amnezia-wg set  # تنظیمات تعاملی
```

## 🤝 لینک و پشتیبانی

- **انتشار باینری**: [LiuTangLei/tailscale](https://github.com/LiuTangLei/tailscale/releases)
- **گزارش مشکل نصب**: [GitHub Issues](https://github.com/LiuTangLei/tailscale-awg-installer/issues)
- **مستندات Amnezia-WG**: [مستندات رسمی](https://docs.amnezia.org/documentation/instructions/new-amneziawg-selfhosted)

## 📄 مجوز

مجوز BSD 3-Clause (همانند Tailscale)

---

**⚠️ سلب مسئولیت: فقط برای استفاده قانونی و آموزشی. مسئولیت رعایت قوانین با کاربر است.**

# Tailscale با Amnezia-WG 1.5

[![GitHub Release](https://img.shields.io/github/v/release/LiuTangLei/tailscale)](https://github.com/LiuTangLei/tailscale/releases/latest)
[![Platform Support](https://img.shields.io/badge/platform-Linux%20|%20macOS%20|%20Windows-blue)](https://github.com/LiuTangLei/tailscale/releases/latest)
[![License](https://img.shields.io/badge/license-BSD--3--Clause-green)](LICENSE)

Tailscale با پروتکل **Amnezia-WG 1.5** برای تحریف DPI و دور زدن سانسور.

## 🚀 نصب

**Linux:**

```bash
curl -fsSL https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-linux.sh | bash
```

**macOS:**

```bash
curl -fsSL https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-macos.sh | bash
```

**Windows (PowerShell به عنوان Admin):**

```powershell
iwr -useb https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-windows.ps1 | iex
```

### گزینه‌های نصب

**دانلود از طریق Mirror (اگر GitHub در کشور شما کند یا مسدود است):**

توصیه می‌شود از دامنه mirror خودتان استفاده کنید (مثل <https://your-mirror-site.com>) تا از مسدود شدن mirror های عمومی جلوگیری کنید. می‌توانید با استفاده از [gh-proxy](https://github.com/hunshcn/gh-proxy) mirror خودتان را راه‌اندازی کنید.

```bash
# Linux:
curl -fsSL https://your-mirror-site.com/https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-linux.sh | bash -s -- --mirror https://your-mirror-site.com
```

```bash
# macOS:
curl -fsSL https://your-mirror-site.com/https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-macos.sh | bash -s -- --mirror https://your-mirror-site.com
```

```powershell
# Windows:
$scriptContent = (iwr -useb https://your-mirror-site.com/https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-windows.ps1).Content;$scriptBlock = [scriptblock]::Create($scriptContent); & $scriptBlock -MirrorPrefix 'https://your-mirror-site.com/'
```

**مشکلات execution policy در PowerShell:**

```powershell
# اگر اجرای script مسدود شده:
Set-ExecutionPolicy RemoteSigned
# یا
Set-ExecutionPolicy Bypass -Scope Process
```

## ⚡ شروع سریع

1. **نصب** با استفاده از دستورات بالا
2. **وارد شدن** به Tailscale:

```bash
# صفحه کنترل رسمی
tailscale up

# کاربران Headscale
tailscale up --login-server https://your-headscale-domain
```

3. **فعال کردن obfuscation** در صورت نیاز:

```bash
# دور زدن پایه DPI (سازگار با هر peer)
tailscale amnezia-wg set '{"jc":4,"jmin":64,"jmax":256}'

# بررسی تنظیمات فعلی
tailscale amnezia-wg get

# تنظیمات تعاملی
tailscale amnezia-wg set

# بازگشت به WireGuard استاندارد
tailscale amnezia-wg reset
```

## 🛡️ ویژگی‌های Amnezia-WG

### ترافیک آشغال و امضاها

اضافه کردن پکت‌های جعلی و امضاهای پروتکل برای دور زدن DPI. سازگار با peer های استاندارد Tailscale:

```bash
# ترافیک آشغال پایه
tailscale amnezia-wg set '{"jc":4,"jmin":64,"jmax":256}'

# با امضاهای پروتکل (i1-i5)
tailscale amnezia-wg set '{"jc":2,"jmin":64,"jmax":128,"i1":"<b 0xc0><r 16>","i2":"<b 0x40><r 12>"}'
```

### تحریف پروتکل

نیاز به استفاده تمام node ها از این fork با تنظیمات یکسان (امضاهای ix نیازی به تطبیق ندارند):

```bash
# obfuscation دست‌دادن (s1/s2 باید در تمام node ها مطابقت داشته باشند)
tailscale amnezia-wg set '{"s1":10,"s2":15}'

# با فیلدهای header (h1-h4 برای obfuscation پروتکل، باید در تمام node ها مطابقت داشته باشند)
tailscale amnezia-wg set '{"s1":10,"s2":15,"h1":3946285740,"h2":1234567890,"h3":987654321,"h4":555666777}'

# ترکیب با امضاها (i1-i5 می‌تواند در هر node متفاوت باشد)
tailscale amnezia-wg set '{"s1":10,"s2":15,"h1":3946285740,"h2":1234567890,"h3":987654321,"h4":555666777,"i1":"<b 0xc0><r 32><c><t>"}'
```

## 🎯 راهنمای پیکربندی

**پیکربندی‌های پایه (سازگار با کلاینت‌های استاندارد):**

| نوع            | پیکربندی                                              | وضعیت     |
| -------------- | ----------------------------------------------------- | --------- |
| **فقط آشغال**  | `{"jc":4,"jmin":64,"jmax":256}`                       | ✅ سازگار |
| **آشغال+امضا** | `{"jc":2,"jmin":64,"jmax":128,"i1":"<b 0xc0><r 16>"}` | ✅ سازگار |

**پیکربندی‌های پیشرفته (نیاز به استفاده این fork در تمام گره‌ها):**

| نوع             | پیکربندی                                                                                         | وضعیت           |
| --------------- | ------------------------------------------------------------------------------------------------ | --------------- |
| **obfuscation** | `{"s1":10,"s2":15,"h1":123456,"h2":789012,"h3":345678,"h4":901234}`                              | ❌ نیاز به fork |
| **کامل**        | `{"jc":2,"s1":10,"s2":15,"h1":123456,"h2":789012,"h3":345678,"h4":901234,"i1":"<b 0xc0><r 16>"}` | ❌ نیاز به fork |

> **سطح مخفی‌کاری**: استفاده از انواع پارامترهای بیشتر (jc/i1-i5/s1-s2/h1-h4) obfuscation بهتری ارائه می‌دهد، اما از پکت‌های آشغال (jc) و امضاهای (i1-i5) زیاد جلوگیری کنید تا از اتلاف پهنای باند و مشکلات تأخیر پیشگیری شود.

### توضیح پارامترها

- **jc**: تعداد پکت‌های آشغال (0-10، باید jmin/jmax را با هم تنظیم کرد)
- **jmin/jmax**: محدوده اندازه پکت آشغال بر حسب بایت (64-1024، هنگام استفاده از jc لازم است)
- **i1-i5**: پکت‌های امضای پروتکل برای تقلید (hex-blob دلخواه)
- **s1/s2**: پیشوندهای تصادفی برای پکت‌های Init/Response (0-64 بایت، نیاز به تطبیق مقادیر در تمام node ها)
- **h1-h4**: obfuscation پروتکل (مقادیر 32 بیتی، باید تمام 4 تا را تنظیم کرد یا هیچ‌کدام، نیاز به تطبیق مقادیر در تمام node ها)

### محدوده پارامترهای رسمی

| پارامتر        | محدوده          | توضیحات                                     |
| -------------- | --------------- | ------------------------------------------- |
| **I1-I5**      | hex-blob دلخواه | پکت‌های امضا برای تقلید پروتکل              |
| **S1, S2**     | 0-64 بایت       | پیشوندهای تصادفی برای پکت‌های Init/Response |
| **Jc**         | 0-10            | تعداد پکت‌های آشغال دنبال I1-I5             |
| **Jmin, Jmax** | 64-1024 بایت    | محدوده اندازه پکت‌های آشغال تصادفی          |
| **H1-H4**      | 0-4294967295    | مقادیر 32 بیتی برای obfuscation پروتکل      |

## 📊 پشتیبانی از پلتفرم‌ها

| پلتفرم      | معماری‌ها            | وضعیت                     |
| ----------- | -------------------- | ------------------------- |
| **Linux**   | x86_64, ARM64        | ✅ کاملاً پشتیبانی می‌شود |
| **macOS**   | Intel, Apple Silicon | ✅ کاملاً پشتیبانی می‌شود |
| **Windows** | x86_64, ARM64        | ✅ نصب‌کننده PowerShell   |

## 🔄 مهاجرت از Tailscale رسمی

1. نصب‌کننده را اجرا کنید - به طور خودکار فایل‌های باینری را جایگزین می‌کند در حالی که تنظیمات شما را حفظ می‌کند
2. احراز هویت و پیکربندی موجود شما بدون تغییر باقی می‌ماند
3. با obfuscation پایه شروع کنید: `tailscale amnezia-wg set '{"jc":4,"jmin":64,"jmax":256}'`

## ⚠️ نکات مهم

- **رفتار پیش‌فرض**: دقیقاً مثل Tailscale رسمی کار می‌کند تا زمانی که obfuscation را فعال کنید
- **پکت‌های آشغال (jc) و امضاها (i1-i5)**: با هر peer Tailscale سازگار است، شامل کلاینت‌های استاندارد. هر node می‌تواند از مقادیر متفاوتی استفاده کند
- **تحریف پروتکل (s1/s2) و فیلدهای header (h1-h4)**: نیاز به استفاده تمام node ها از این fork با مقادیر یکسان
- **عملکرد**: overhead حداقل با تنظیمات پایه

## 🛠️ استفاده پیشرفته

### پیکربندی فیلدهای Header (h1-h4)

obfuscation پروتکل برای دور زدن تشخیص WireGuard. باید تمام 4 مقدار را تنظیم کرد یا هیچ‌کدام:

```bash
# node اول: تولید مقادیر تصادفی (برای هر h1-h4 'random' وارد کنید)
tailscale amnezia-wg set  # تمام h1, h2, h3, h4 را هنگام درخواست تنظیم کنید

# JSON پیکربندی را دریافت کنید
tailscale amnezia-wg get

# کل JSON را به node های دیگر کپی کنید (باید شامل تمام h1-h4 باشد)
tailscale amnezia-wg set '{"s1":10,"s2":15,"h1":3946285740,"h2":1234567890,"h3":987654321,"h4":555666777}'
```

### ایجاد امضاهای پروتکل

1. ترافیک واقعی را با Wireshark ضبط کنید
2. الگوهای hex را از header ها استخراج کنید
3. فرمت ساخت: `<b 0xHEX>` (ثابت), `<r LENGTH>` (تصادفی), `<c>` (شمارنده), `<t>` (timestamp)
4. مثال: `<b 0xc0000000><r 16><c><t>` = header شبیه QUIC + 16 بایت تصادفی + شمارنده + timestamp

### پکت‌های Obfuscation I1–I5 (زنجیره امضا) و CPS (امضای پروتکل سفارشی)

قبل از هر دست‌دادن "خاص" (هر 120 ثانیه)، کلاینت ممکن است تا پنج پکت UDP سفارشی (I1–I5) را در فرمت CPS برای تقلید پروتکل ارسال کند.

**فرمت CPS:**

```text
i{n} = <tag1><tag2><tag3>...<tagN>
```

**انواع Tag:**

| Tag | فرمت           | توضیحات                                    | محدودیت‌ها             |
| --- | -------------- | ------------------------------------------ | ---------------------- |
| b   | `<b hex_data>` | بایت‌های ثابت برای تقلید پروتکل‌ها         | طول دلخواه             |
| c   | `<c>`          | شمارنده پکت (32-bit، ترتیب بایت شبکه)      | منحصر به فرد در زنجیره |
| t   | `<t>`          | timestamp یونیکس (32-bit، ترتیب بایت شبکه) | منحصر به فرد در زنجیره |
| r   | `<r length>`   | بایت‌های تصادفی امن رمزنگاری               | length ≤ 1000          |

**مثال:**

```text
i1 = <b 0xf6ab3267fa><c><b 0xf6ab><t><r 10>
```

> ⚠️ اگر i1 تنظیم نشده باشد، کل زنجیره (I2–I5) نادیده گرفته می‌شود.

#### ضبط پکت‌های Obfuscation واقعی با Wireshark

1. Amnezia-WG را راه‌اندازی کنید و پارامترهای i1–i5 را پیکربندی کنید
2. از Wireshark برای نظارت بر پورت UDP استفاده کنید (مثلاً فیلتر: `udp.port == 51820`)
3. پکت‌های obfuscation را مشاهده و تجزیه و تحلیل کنید، امضاهای پروتکل را در صورت نیاز استخراج کنید

برای جزئیات بیشتر، [مستندات رسمی Amnezia-WG](https://docs.amnezia.org/documentation/instructions/new-amneziawg-selfhosted) را ببینید

## 🐛 عیب‌یابی

### تأیید نصب

```bash
tailscale version          # بررسی نسخه کلاینت
tailscale amnezia-wg get   # تأیید پشتیبانی Amnezia-WG
```

### مشکلات اتصال

```bash
# بازگشت به WireGuard استاندارد
tailscale amnezia-wg reset

# ابتدا تنظیمات پایه را امتحان کنید
tailscale amnezia-wg set '{"jc":2,"jmin":64,"jmax":128}'

# بررسی log ها (Linux)
sudo journalctl -u tailscaled -f
```

### مشکلات Windows PowerShell

از حالت تعاملی برای جلوگیری از مشکلات escape کردن JSON استفاده کنید:

```powershell
tailscale amnezia-wg set  # تنظیمات تعاملی
```

## 🤝 لینک‌ها و پشتیبانی

- **انتشارات باینری**: [LiuTangLei/tailscale](https://github.com/LiuTangLei/tailscale/releases)
- **مشکلات نصب‌کننده**: [GitHub Issues](https://github.com/LiuTangLei/tailscale-awg-installer/issues)
- **مستندات Amnezia-WG**: [مستندات رسمی](https://docs.amnezia.org/documentation/instructions/new-amneziawg-selfhosted)

## 📄 مجوز

مجوز BSD 3-Clause (مشابه Tailscale)

---

**⚠️ سلب مسئولیت**: فقط برای اهداف آموزشی و حریم خصوصی مشروع. کاربران مسئول رعایت قوانین قابل اجرا هستند.
