
# Tailscale با Amnezia‑WG 2.0 (v1.88.2+)

[![GitHub Release](https://img.shields.io/github/v/release/LiuTangLei/tailscale)](https://github.com/LiuTangLei/tailscale/releases/latest)
[![Platform Support](https://img.shields.io/badge/platform-Linux%20|%20macOS%20|%20Windows%20|%20OpenWrt%20|%20Android-blue)](https://github.com/LiuTangLei/tailscale/releases/latest)
[![License](https://img.shields.io/badge/license-BSD--3--Clause-green)](../LICENSE)

این پروژه نسخه تقویت‌شده Tailscale با پشتیبانی Amnezia‑WG 2.0 است. با فعال کردن پارامترهای AWG می‌توانید از ترافیک زائد، امضاهای پروتکل، و پنهان‌سازی دست‌دهی و هدر استفاده کنید. تا قبل از فعال‌سازی AWG، رفتار آن مانند Tailscale استاندارد است.

زبان‌ها: [English](../README.md) | [中文](README-zh.md) | [فارسی](README-fa.md) | [Русский](README-ru.md)

مستندات AWG 1.5: [README-awg-v1.5.md](README-awg-v1.5.md)

## نصب

| پلتفرم | دستور / اقدام |
| --- | --- |
| لینوکس | `curl -fsSL https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-linux.sh \| bash` |
| macOS* | `curl -fsSL https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-macos.sh \| bash` |
| ویندوز (PowerShell ادمین) | `iwr -useb https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-windows.ps1 \| iex` |
| OpenWrt | [نصب OpenWrt](#نصب-openwrt) را ببینید |
| اندروید | APK را از [releases](https://github.com/LiuTangLei/tailscale-android/releases) دانلود کنید |

- macOS: نصب‌کننده از `tailscaled` در حالت CLI استفاده می‌کند. اگر Tailscale.app رسمی پیدا شود، برای جلوگیری از تداخل پیشنهاد حذف آن نمایش داده می‌شود.
- اندروید: فعلاً فقط همگام‌سازی دریافت AWG پشتیبانی می‌شود.

![Android Sync](sync1.jpg)

## Docker Compose

مخزن شامل `docker-compose.yml` برای اجرای `tailscaled` با پشتیبانی AWG است.

- وضعیت در پوشه `./tailscale-state` کنار فایل compose ذخیره می‌شود، بنابراین وضعیت نود و تنظیمات AWG بعد از ری‌استارت کانتینر یا ریبوت میزبان باقی می‌مانند.
- اگر از bind mount قدیمی `/var/lib/tailscale:/var/lib/tailscale` ارتقا می‌دهید، ابتدا وضعیت قبلی را کپی کنید:

```bash
docker compose down
cp -a /var/lib/tailscale ./tailscale-state
# docker-compose.yml را به‌روزرسانی کنید
docker compose up -d
```

روند پایه:

1. سرویس را اجرا کنید: `docker compose up -d`
2. داخل کانتینر احراز هویت کنید: `docker compose exec tailscaled tailscale up`
3. سپس دستورات AWG را مشابه نصب محلی اجرا کنید، مثلاً: `docker compose exec tailscaled tailscale awg sync`

اگر از Headscale استفاده می‌کنید، در `tailscale up` گزینه `--login-server https://your-headscale-domain` را اضافه کنید.

Alias اختیاری روی میزبان:

```bash
alias tailscale='docker exec -it tailscaled tailscale'
```

این alias فقط برای shell فعلی معتبر است. برای ماندگاری، آن را به `~/.bashrc` یا `~/.zshrc` اضافه کنید و shell را دوباره بارگذاری کنید.

## نصب OpenWrt

دستور پیش‌فرض:

```bash
wget -O /usr/bin/install.sh https://raw.githubusercontent.com/LiuTangLei/openwrt-tailscale-awg/main/install_en.sh && chmod +x /usr/bin/install.sh && /usr/bin/install.sh
```

برای مناطق با دسترسی محدود به GitHub:

```bash
wget -O /usr/bin/install.sh https://ghfast.top/https://raw.githubusercontent.com/LiuTangLei/openwrt-tailscale-awg/main/install.sh && chmod +x /usr/bin/install.sh && /usr/bin/install.sh
```

این اسکریپت از [GuNanOvO/openwrt-tailscale](https://github.com/GuNanOvO/openwrt-tailscale) فورک شده است.

## میرورها

اگر GitHub کند یا مسدود است، می‌توانید یک میرور پیشوند مانند `https://your-mirror-site.com` راه‌اندازی کنید:

```bash
# لینوکس
curl -fsSL https://your-mirror-site.com/https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-linux.sh | bash -s -- --mirror https://your-mirror-site.com

# macOS
curl -fsSL https://your-mirror-site.com/https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-macos.sh | bash -s -- --mirror https://your-mirror-site.com
```

```powershell
# Windows
$scriptContent = (iwr -useb https://your-mirror-site.com/https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-windows.ps1).Content; $scriptBlock = [scriptblock]::Create($scriptContent); & $scriptBlock -MirrorPrefix 'https://your-mirror-site.com/'
```

اگر PowerShell اجرای اسکریپت را مسدود کرد، از `Set-ExecutionPolicy RemoteSigned` یا `Bypass -Scope Process` استفاده کنید.

## شروع سریع

نکته: `tailscale amnezia-wg` همان `tailscale awg` است.

1. وارد شبکه شوید:

```bash
# سرور رسمی
tailscale up

# Headscale
tailscale up --login-server https://your-headscale-domain
```

2. AWG را تنظیم کنید:

```bash
tailscale awg set
```

در پیام تولید خودکار Enter را بزنید تا برای همه گزینه‌ها به جز `i1` تا `i5` مقادیر پیشنهادی ساخته شود.

3. سایر دستگاه‌ها را همگام‌سازی کنید:

- دسکتاپ: `tailscale awg sync`
- اندروید: دکمه Sync در برنامه

4. در صورت نیاز بررسی یا ریست کنید:

```bash
tailscale awg get
tailscale awg reset
```

## پیش‌تنظیم‌های پیکربندی

| هدف | مثال | سازگاری |
| --- | --- | --- |
| ترافیک زائد پایه | `tailscale awg set '{"jc":4,"jmin":64,"jmax":256}'` | با گره‌های استاندارد Tailscale کار می‌کند |
| ترافیک زائد + امضا | `tailscale awg set '{"jc":2,"jmin":64,"jmax":128,"i1":"<b 0x40><r 12>"}'` | با گره‌های استاندارد Tailscale کار می‌کند |
| پنهان‌سازی دست‌دهی | `tailscale awg set '{"s1":10,"s2":15,"s3":8,"s4":0}'` | همه گره‌های AWG باید `s1` تا `s4` یکسان داشته باشند |
| پنهان‌سازی کامل | `tailscale awg set '{"s1":10,"s2":15,"s3":8,"s4":0,"h1":{"min":100000,"max":200000},"h2":{"min":300000,"max":350000},"h3":{"min":400000,"max":450000},"h4":{"min":500000,"max":550000}}'` | همه گره‌های AWG باید `s1` تا `s4` و `h1` تا `h4` یکسان داشته باشند |
| پنهان‌سازی کامل + امضا | `tailscale awg set '{"s1":10,"s2":15,"s3":8,"s4":0,"h1":{"min":100000,"max":200000},"h2":{"min":300000,"max":350000},"h3":{"min":400000,"max":450000},"h4":{"min":500000,"max":550000},"i1":"<b 0xc0><r 32><c><t>"}'` | `i1` تا `i5` می‌توانند متفاوت باشند، اما `s1` تا `s4` و `h1` تا `h4` باید یکسان باشند |

## مرجع پارامترها

- `jc` همراه با `jmin` و `jmax`: تعداد و اندازه بسته‌های زائد.
- `i1` تا `i5`: زنجیره اختیاری CPS.
- `s1` تا `s4`: فیلدهای پیشوند یا padding دست‌دهی؛ باید روی همه گره‌های AWG یکسان باشند.
- `h1` تا `h4`: بازه‌های فیلد هدر با قالب `{"min": low, "max": high}`؛ یا هر چهار مقدار را تنظیم کنید یا هیچ‌کدام. بازه‌ها نباید هم‌پوشانی داشته باشند و باید بین گره‌ها یکسان باشند.

مقادیر زیاد برای ترافیک زائد یا زنجیره‌های طولانی امضا باعث افزایش مصرف پهنای باند و تاخیر می‌شوند.

## پشتیبانی پلتفرم

| پلتفرم | معماری | وضعیت |
| --- | --- | --- |
| لینوکس | x86_64, ARM64 | ✅ کامل |
| macOS | Intel, Apple Silicon | ✅ کامل |
| ویندوز | x86_64, ARM64 | ✅ نصب‌کننده |
| OpenWrt | متنوع | ✅ اسکریپت |
| اندروید | ARM64, ARM | ✅ APK (فقط sync AWG) |

## پیشرفته: امضاهای پروتکل

قالب CPS:

```text
i{n} = <tag1><tag2>...<tagN>
```

تگ‌ها:

- `<b 0xHEX>`: بایت‌های ثابت
- `<r N>`: بایت‌های تصادفی امن
- `<c>`: شمارنده
- `<t>`: timestamp

مثال:

```text
i1 = <b 0xf6ab3267fa><c><b 0xf6ab><t><r 10>
```

اگر `i1` تنظیم نشده باشد، `i2` تا `i5` نادیده گرفته می‌شوند.

## عیب‌یابی

برای بررسی نصب:

```bash
tailscale version
tailscale awg get
```

اگر اتصال دچار مشکل شد، ابتدا به WireGuard استاندارد برگردید و با یک preset ساده شروع کنید:

```bash
tailscale awg reset
tailscale awg set '{"jc":2,"jmin":64,"jmax":128}'
sudo journalctl -u tailscaled -f
```

در PowerShell ویندوز، حالت تعاملی ساده‌تر است:

```powershell
tailscale awg set
```

## پیوندها

- Releases: <https://github.com/LiuTangLei/tailscale/releases>
- Android APK: <https://github.com/LiuTangLei/tailscale-android/releases>
- Issues نصب‌کننده: <https://github.com/LiuTangLei/tailscale-awg-installer/issues>
- مستندات Amnezia‑WG: <https://docs.amnezia.org/documentation/instructions/new-amneziawg-selfhosted/#how-to-extract-a-protocol-signature-for-amneziawg-manually>

## مجوز

BSD 3-Clause، همان مجوز upstream.
