
# Tailscale با AmneziaWG v2 و v3

[![GitHub Release](https://img.shields.io/github/v/release/LiuTangLei/tailscale)](https://github.com/LiuTangLei/tailscale/releases/latest)
[![Platform Support](https://img.shields.io/badge/platform-Linux%20|%20macOS%20|%20Windows%20|%20OpenWrt%20|%20Android%20|%20iOS-blue)](#پشتیبانی-پلتفرم)
[![License](https://img.shields.io/badge/license-BSD--3--Clause-green)](../LICENSE)

این پروژه فورک Tailscale دارای مبهم‌سازی AmneziaWG را نصب می‌کند و رفتار control plane رسمی Tailscale و Headscale را حفظ می‌کند. وقتی همه پارامترهای AWG غیرفعال باشند، مانند Tailscale استاندارد کار می‌کند.

از `v1.102.2` دو پروفایل پشتیبانی می‌شوند: **AWG v3** (پیشنهادی؛ محافظت هدر، padding محتوا و بازه‌های زمانی تصادفی) و **AWG v2** برای سازگاری با گره‌های قدیمی.

تنها استثنای سازگاری v2، تگ شمارنده قدیمی CPS یعنی `<c>` است. upstream پروژه AmneziaWG هنگام بازطراحی AWG 2 در `amneziawg-go v0.2.16` آن را حذف کرد. این تغییر در Tailscale `v1.98.5` این پروژه و از طریق `wireguard-go v0.0.20` وارد شد؛ آن نسخه upstream `amneziawg-go v0.2.17` را ادغام کرده بود. فقط `<c>` را از مقادیر قدیمی `i1` تا `i5` حذف کنید؛ سایر پارامترهای v2 همچنان پشتیبانی می‌شوند.

زبان‌ها: [English](../README.md) | [中文](README-zh.md) | [فارسی](README-fa.md) | [Русский](README-ru.md)

آرشیو نسخه قدیمی AWG 1.5: [README-awg-v1.5.md](README-awg-v1.5.md).

## نصب

نصب‌کننده‌ها آخرین release پایدار را انتخاب می‌کنند. هرجا مدل نصب پلتفرم اجازه دهد، وضعیت CLI/service و تنظیمات AWG را نگه می‌دارند، پروفایل قدیمی قابل‌دسترسی را فقط برای یافتن `<c>` می‌خوانند و پس از نصب راهنمای متناسب با نسخه نشان می‌دهند. نصب‌کننده هیچ پروفایل AWG را خودکار ایجاد یا بازنویسی نمی‌کند. هنگام جابه‌جایی macOS از Tailscale.app به سرویس CLI/utun باید دوباره وارد شوید، چون این دو مدل نصب وضعیت مشترک ندارند.

| پلتفرم | دستور / اقدام |
| --- | --- |
| لینوکس | `curl -fsSL https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-linux.sh \| bash` |
| macOS* | `curl -fsSL https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-macos.sh \| bash` |
| ویندوز (PowerShell ادمین) | `iwr -useb https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-windows.ps1 \| iex` |
| OpenWrt | [نصب OpenWrt](#نصب-openwrt) را ببینید |
| اندروید | APK را از [releases](https://github.com/LiuTangLei/tailscale-android/releases) دانلود کنید |
| iOS | کلاینت متن‌باز آزمایشی: [AwgScale](https://github.com/LiuTangLei/AwgScale) (نیازمند TrollStore یا امضای دارای Packet Tunnel entitlement) |

- macOS: نصب‌کننده از `tailscaled` در حالت CLI استفاده می‌کند. اگر Tailscale.app رسمی پیدا شود، برای جلوگیری از تداخل پیشنهاد حذف آن نمایش داده می‌شود.
- کلاینت‌های موبایل Android و iOS از تنظیم دستی AWG و همگام‌سازی تنظیمات AWG از گره‌های دیگر پشتیبانی می‌کنند.
- iOS: AwgScale آزمایشی و self-managed است، در App Store منتشر نشده و IPA فعلی برای TrollStore یا مسیر امضای Apple با Packet Tunnel entitlement است.

![Android Sync](sync1.jpg)

## Docker Compose

مخزن شامل `docker-compose.yml` برای اجرای `tailscaled` با پشتیبانی AWG است.

- وضعیت در پوشه `./tailscale-state` کنار فایل compose ذخیره می‌شود، بنابراین وضعیت نود و تنظیمات AWG بعد از ری‌استارت کانتینر یا ریبوت میزبان باقی می‌مانند.
- اگر از bind mount قدیمی `/var/lib/tailscale:/var/lib/tailscale` ارتقا می‌دهید، ابتدا وضعیت قبلی را کپی کنید:

```bash
docker compose down
mkdir -p ./tailscale-state
cp -a /var/lib/tailscale/. ./tailscale-state/
# docker-compose.yml را به‌روزرسانی کنید
docker compose up -d
```

روند پایه:

1. سرویس را اجرا کنید: `docker compose up -d`
2. داخل کانتینر احراز هویت کنید: `docker compose exec tailscaled tailscale up`
3. سپس دستورات AWG را مشابه نصب محلی اجرا کنید، مثلاً: `docker compose exec tailscaled tailscale awg sync`

اگر از Headscale استفاده می‌کنید، در `tailscale up` گزینه `--login-server https://your-headscale-domain` را اضافه کنید.

اینجا دو نام ممکن است با هم اشتباه شوند: سرویس/کانتینر Compose با نام `tailscaled` اجرا می‌شود، اما برنامه CLI داخل کانتینر `tailscale` است. بنابراین شکل مستقیم Docker این است:

```bash
docker exec -it tailscaled tailscale status
```

`docker exec tailscale status` معادل آن نیست: Docker ابتدا به دنبال کانتینری با نام `tailscale` می‌گردد و سپس تلاش می‌کند `status` را به عنوان یک برنامه داخل آن اجرا کند.

برای اینکه روی میزبان Linux مستقیماً از `tailscale ...` استفاده کنید، alias را در فایل راه‌اندازی shell ذخیره کنید:

```bash
printf "\nalias tailscale='docker exec -it tailscaled tailscale'\n" >> ~/.bashrc && . ~/.bashrc
```

برای Zsh از `~/.zshrc` استفاده کنید:

```bash
printf "\nalias tailscale='docker exec -it tailscaled tailscale'\n" >> ~/.zshrc && . ~/.zshrc
```

بعد از آن می‌توانید اجرا کنید:

```bash
tailscale up
tailscale awg get
```

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

در `v1.102.2+` برای ساخت پروفایل پیشنهادی AWG v3 کلید Enter را بزنید، یا برای ساخت پروفایل سازگار AWG v2 عدد `2` را وارد کنید.

3. سایر دستگاه‌ها را همگام‌سازی کنید:

- پلتفرم‌های CLI (Linux/macOS/Windows/OpenWrt): `tailscale awg sync`
- Android و iOS (AwgScale): در برنامه AWG را دستی تنظیم کنید یا تنظیمات را از گره دیگر sync کنید

4. در صورت نیاز بررسی یا ریست کنید:

```bash
tailscale awg get
tailscale awg validate # v1.102.2+
tailscale awg reset
```

## پیش‌تنظیم‌های پیکربندی

| هدف | مثال | سازگاری |
| --- | --- | --- |
| ترافیک زائد پایه | `tailscale awg set '{"jc":4,"jmin":64,"jmax":256}'` | با گره‌های استاندارد Tailscale کار می‌کند |
| ترافیک زائد + امضا | `tailscale awg set '{"jc":2,"jmin":64,"jmax":128,"i1":"<b 0x40><r 12>"}'` | با گره‌های استاندارد Tailscale کار می‌کند |
| پنهان‌سازی دست‌دهی | `tailscale awg set '{"s1":10,"s2":15,"s3":8,"s4":0}'` | همه گره‌های AWG باید `s1` تا `s4` یکسان داشته باشند |
| پنهان‌سازی کامل | `tailscale awg set '{"s1":10,"s2":15,"s3":8,"s4":0,"h1":{"min":100000,"max":200000},"h2":{"min":300000,"max":350000},"h3":{"min":400000,"max":450000},"h4":{"min":500000,"max":550000}}'` | همه گره‌های AWG باید `s1` تا `s4` و `h1` تا `h4` یکسان داشته باشند |
| پنهان‌سازی کامل + امضا | `tailscale awg set '{"s1":10,"s2":15,"s3":8,"s4":0,"h1":{"min":100000,"max":200000},"h2":{"min":300000,"max":350000},"h3":{"min":400000,"max":450000},"h4":{"min":500000,"max":550000},"i1":"<b 0xc0><r 32><t>"}'` | `i1` تا `i5` می‌توانند متفاوت باشند، اما `s1` تا `s4` و `h1` تا `h4` باید یکسان باشند |

## مرجع پارامترها

- `jc` همراه با `jmin` و `jmax`: تعداد و اندازه بسته‌های زائد.
- `i1` تا `i5`: زنجیره اختیاری CPS.
- `s1` تا `s4`: فیلدهای پیشوند یا padding دست‌دهی؛ باید روی همه گره‌های AWG یکسان باشند.
- `h1` تا `h4`: بازه‌های فیلد هدر با قالب `{"min": low, "max": high}`؛ یا هر چهار مقدار را تنظیم کنید یا هیچ‌کدام. بازه‌ها نباید هم‌پوشانی داشته باشند و باید بین گره‌ها یکسان باشند.

AWG v3 همچنین فیلدهای `header_protection_key`، `content_padding_addition`، `rekey_after_time`، `rekey_timeout`، `reject_after_time`، `keepalive_timeout` و `max_handshake_attempts` را اضافه می‌کند. کلید محافظت هدر و فیلدهای مشترک باید روی گره‌های v3 که با هم ارتباط دارند یکسان باشند؛ بازه‌های محلی padding و زمان‌بندی می‌توانند متفاوت باشند. v3 را فقط در یک سمت اتصال فعال نکنید.

مقادیر زیاد برای ترافیک زائد یا زنجیره‌های طولانی امضا باعث افزایش مصرف پهنای باند و تاخیر می‌شوند.

## پشتیبانی پلتفرم

| پلتفرم | معماری | وضعیت |
| --- | --- | --- |
| لینوکس | x86_64, ARM64 | ✅ کامل |
| macOS | Intel, Apple Silicon | ✅ کامل |
| ویندوز | x86_64, ARM64 | ✅ نصب‌کننده |
| OpenWrt | متنوع | ✅ اسکریپت |
| اندروید | ARM64, ARM | ✅ APK (تنظیم دستی AWG + sync) |
| iOS | iPhone/iPad (iOS 15+) | ✅ کلاینت آزمایشی (تنظیم دستی AWG + sync) |

نسخه‌های OpenWrt، Android و iOS جداگانه منتشر می‌شوند. پیش از sync کردن v3 نسخه واقعی client/core را بررسی کنید؛ اگر حتی یک گره هنوز v3 را پشتیبانی نمی‌کند، از v2 استفاده کنید.

## پیشرفته: امضاهای پروتکل

قالب CPS:

```text
i{n} = <tag1><tag2>...<tagN>
```

تگ‌ها:

- `<b 0xHEX>`: بایت‌های ثابت
- `<r N>`: بایت‌های تصادفی امن
- `<rc N>`: حروف تصادفی ASCII
- `<rd N>`: ارقام ده‌دهی تصادفی
- `<t>`: timestamp

مثال:

```text
i1 = <b 0xf6ab3267fa><b 0xf6ab><t><r 10>
```

اگر `i1` تنظیم نشده باشد، `i2` تا `i5` نادیده گرفته می‌شوند.

تگ `<c>` از `v1.98.5` پشتیبانی نمی‌شود. برای نمونه، `<b 0xc0><r 32><c><t>` را به `<b 0xc0><r 32><t>` تغییر دهید. نیازی به تغییر فیلدهای مشترک `s1` تا `s4` یا `h1` تا `h4` نیست.

## عیب‌یابی

برای بررسی نصب:

```bash
tailscale version
tailscale awg get
tailscale awg validate # v1.102.2+
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
- کلاینت iOS (AwgScale): <https://github.com/LiuTangLei/AwgScale>
- Issues نصب‌کننده: <https://github.com/LiuTangLei/tailscale-awg-installer/issues>
- مستندات Amnezia‑WG: <https://docs.amnezia.org/documentation/instructions/new-amneziawg-selfhosted/#how-to-extract-a-protocol-signature-for-amneziawg-manually>

## مجوز

BSD 3-Clause، همان مجوز upstream.
