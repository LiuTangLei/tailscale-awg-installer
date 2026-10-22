# Tailscale + AmneziaWG / QUIC

[English](../README.md) · [中文](README-zh.md) · [Русский](README-ru.md) · [انتشارها](https://github.com/LiuTangLei/tailscale/releases/latest)

یک فورک Tailscale با ترابری‌های AmneziaWG و QUIC مبهم‌سازی‌شده. با control plane رسمی Tailscale و Headscale کار می‌کند و تا زمانی که ترابری دیگری انتخاب نکنید، مانند Tailscale استاندارد رفتار می‌کند.

[![Release](https://img.shields.io/github/v/release/LiuTangLei/tailscale?label=release)](https://github.com/LiuTangLei/tailscale/releases/latest) [![Docker](https://img.shields.io/docker/v/ltlei/tailscale-awg?sort=semver&label=docker)](https://hub.docker.com/r/ltlei/tailscale-awg/tags)

شماره نسخه‌ها با upstream یکسان است: فورک `vX.Y.Z` بر پایه Tailscale `vX.Y.Z` است.

## قابلیت‌ها

- **سه ترابری در سطح گره**: WireGuard استاندارد (پیش‌فرض)، AWG v3 / v2 و QUIC.
- **AWG v3**: محافظت از هدر، padding محتوا و زمان‌بندی تصادفی. AWG v2 برای گره‌های قدیمی همچنان در دسترس است.
- **QUIC**: HTTP/3 روی TLS با BBRv3 تنظیم‌شده. گره‌ها به‌طور خودکار با کلید گره به هم اعتماد می‌کنند و نیازی به همگام‌سازی پارامتر نیست.
- **اتصال مجدد 0-RTT** بین گره‌های v1.104.2 و بالاتر، با بلیت‌های یک‌بارمصرف و بازگشت به دست‌دهی کامل. سازگاری با گره‌های QUIC نسخه v1.104.1 حفظ شده است.
- **پایداری بهتر در جابه‌جایی بسته‌ها**: بسته‌های QUIC که نامرتب می‌رسند دیگر به‌عنوان تکراری دور ریخته نمی‌شوند.
- **نقش سرور (اختیاری)**: با `tailscale awg server on` کلاینت‌ها هنگام اتصال به این گره از TLS ClientHello شبیه Chromium استفاده می‌کنند.
- **تغییر با یک فرمان** همراه با راه‌اندازی مجدد خودکار، و عیب‌یابی با `tailscale awg doctor`.
- **ارتقای امن**: نصب‌کننده‌ها SHA-256 را بررسی می‌کنند، در صورت خطا به حالت قبل برمی‌گردند و ترابری فعال را حفظ می‌کنند.

## نصب

| پلتفرم | نصب / دانلود | نسخه |
| --- | --- | --- |
| Linux | `curl -fsSL https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-linux.sh \| bash` | [![release](https://img.shields.io/github/v/release/LiuTangLei/tailscale?label=)](https://github.com/LiuTangLei/tailscale/releases/latest) |
| macOS | `curl -fsSL https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-macos.sh \| bash` | [![release](https://img.shields.io/github/v/release/LiuTangLei/tailscale?label=)](https://github.com/LiuTangLei/tailscale/releases/latest) |
| Windows (PowerShell با دسترسی Admin) | `iwr -useb https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-windows.ps1 \| iex` | [![release](https://img.shields.io/github/v/release/LiuTangLei/tailscale?label=)](https://github.com/LiuTangLei/tailscale/releases/latest) |
| Docker | `ltlei/tailscale-awg:latest` ([پایین‌تر](#docker)) | [![docker](https://img.shields.io/docker/v/ltlei/tailscale-awg?sort=semver&label=)](https://hub.docker.com/r/ltlei/tailscale-awg/tags) |
| OpenWrt | [نصب‌کننده، بسته‌ها و مخزن](https://github.com/LiuTangLei/openwrt-tailscale-awg) | [![openwrt](https://img.shields.io/github/v/release/LiuTangLei/openwrt-tailscale-awg?label=)](https://github.com/LiuTangLei/openwrt-tailscale-awg/releases/latest) |
| Android | [APK امضاشده](https://github.com/LiuTangLei/tailscale-android/releases/latest) | [![android](https://img.shields.io/github/v/release/LiuTangLei/tailscale-android?label=)](https://github.com/LiuTangLei/tailscale-android/releases/latest) |
| iOS | [AwgScale IPA](https://github.com/LiuTangLei/AwgScale/releases/latest) | [![ios](https://img.shields.io/github/v/release/LiuTangLei/AwgScale?include_prereleases&label=)](https://github.com/LiuTangLei/AwgScale/releases) |

- نصب دستی برای Linux، macOS، Windows، OpenWrt و موبایل: [manual installation guide](manual-install.md) (به انگلیسی).
- نصب‌کننده‌های دسکتاپ آخرین نسخه را روی x86_64 / ARM64 نصب می‌کنند. برای تثبیت نسخه `--version <tag>` (در Windows: `-Version <tag>`) را اضافه کنید. در Linux / macOS، `--uninstall` آن را حذف می‌کند.
- macOS از سرویس CLI/utun استفاده می‌کند؛ انتقال از Tailscale.app نیاز به ورود مجدد دارد.
- رابط گرافیکی Windows باید با نسخه پایه Tailscale این فورک یکسان باشد.
- iOS به TrollStore یا مجوز Packet Tunnel نیاز دارد؛ IPA برای App Store امضا نشده است.
- به‌روزرسانی با مدیر بسته سیستم ممکن است باینری‌های رسمی را برگرداند. اگر فرمان `tailscale awg` ناپدید شد، نصب‌کننده را دوباره اجرا کنید.

## آینه‌های GitHub

اگر GitHub کند یا مسدود است، پیشوند آینه را قبل از آدرس اسکریپت بگذارید و همان پیشوند را به نصب‌کننده بدهید. Linux و macOS از `--mirror` و Windows از `-MirrorPrefix` یا متغیر محیطی `MIRROR_PREFIX` استفاده می‌کنند.

```bash
# macOS: install-linux.sh را با install-macos.sh جایگزین کنید
curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-linux.sh \
  | bash -s -- --mirror https://ghfast.top
```

```powershell
$m = 'https://ghfast.top'
$code = (iwr -useb "$m/https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-windows.ps1").Content
& ([scriptblock]::Create($code)) -MirrorPrefix $m
```

| آینه | توضیح |
| --- | --- |
| `https://ghfast.top` | پیش‌فرض نصب‌کننده OpenWrt |
| `https://gh-proxy.org` | مورد استفاده نصب‌کننده OpenWrt |
| `https://gh-proxy.com` | GitHub API را هم پروکسی می‌کند |
| آینه شخصی | هر پروکسی با قالب `https://<mirror>/https://github.com/...`، مثلاً [gh-proxy](https://github.com/hunshcn/gh-proxy) روی Cloudflare Workers یا Docker |

- نصب‌کننده آخرین نسخه را از `api.github.com` می‌گیرد؛ ابتدا مستقیم و سپس از طریق آینه. بیشتر آینه‌ها API را پروکسی نمی‌کنند؛ اگر این کار ناموفق بود، از `gh-proxy.com` استفاده کنید یا `--version <tag>` را با نسخه نشان‌داده‌شده در نشان بالا اضافه کنید.
- آینه‌های عمومی سرویس‌های شخص ثالث هستند و ممکن است تغییر کنند یا از دسترس خارج شوند. برای سیستم‌های مهم از آینه شخصی استفاده کنید.
- OpenWrt: نصب‌کننده این آینه‌ها را خودکار امتحان می‌کند؛ برای آینه شخصی از `install.sh --custom-proxy` استفاده کنید.

## اتصال و پیکربندی

```bash
tailscale up
```

برای Headscale: `tailscale up --login-server https://your-headscale-domain`.

| کار | فرمان |
| --- | --- |
| انتخاب AWG v3 (پیش‌فرض)، v2 یا QUIC | `tailscale awg set` |
| فعال‌سازی QUIC | `tailscale awg set --yes quic` |
| نمایش / ذخیره JSON مربوط به AWG | `tailscale awg get` |
| اعمال JSON ذخیره‌شده | `tailscale awg set '<JSON>'` |
| کپی پروفایل یک گره سازگار آنلاین | `tailscale awg sync` |
| معرفی این گره به‌عنوان سرور QUIC | `tailscale awg server on` |
| بازگشت به WireGuard استاندارد | `tailscale awg reset` |
| حالت فعال / عیب‌یابی | `tailscale awg status` / `tailscale awg doctor` |

- فیلدهای مشترک گره‌های AWG باید یکسان باشند. یک بار پروفایل بسازید، JSON را ذخیره کنید و سپس توزیع یا همگام‌سازی کنید.
- QUIC روی کل گره اعمال می‌شود و همه گره‌های در ارتباط باید آن را فعال کنند. بازگشت خودکار به WireGuard وجود ندارد. فعال‌سازی QUIC پروفایل AWG را پاک می‌کند؛ اگر بعداً لازم دارید، ابتدا JSON را ذخیره کنید.
- تغییر ترابری سرویس محلی را دوباره راه‌اندازی می‌کند و VPN را برای مدت کوتاهی قطع می‌کند. راه دسترسی دیگری به سیستم‌های راه دور نگه دارید.

## Docker

از [docker-compose.yml](../docker-compose.yml) با `ltlei/tailscale-awg:latest` یا `:v1.104` (همیشه آخرین نسخه وصله) استفاده کنید. ایمیج‌ها برای amd64، arm64، arm/v7 و 386 موجودند.

```bash
curl -fsSLO https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/docker-compose.yml
docker compose pull
docker compose up -d
docker compose exec tailscaled tailscale up
```

برای Headscale، `--login-server https://your-headscale-domain` را اضافه کنید. برای ورود خودکار، `TS_AUTHKEY` را به‌صورت خصوصی بدهید و هرگز commit نکنید.

داخل کانتینر ابتدا تغییر ترابری را آماده کنید و سپس کانتینر را دوباره راه‌اندازی کنید:

```bash
docker compose exec tailscaled tailscale awg set --no-restart --yes quic
docker compose restart tailscaled
```

برای AWG، `--yes quic` را با `'<JSON>'` جایگزین کنید.

- فرمان `containerboot` ایمیج و **کل** پوشه `./tailscale-state` را نگه دارید. وضعیت زنده گره را بین چند daemon به اشتراک نگذارید.
- حالت TUN به `/dev/net/tun` و `NET_ADMIN` نیاز دارد و مسیرها فقط داخل کانتینر اعمال می‌شوند. Exit node و subnet router به forwarding و تأیید در control plane هم نیاز دارند. با `TS_AUTH_ONCE=true`، تغییرات بعدی مسیرها به `tailscale set` صریح نیاز دارند.
- بدون TUN یا دسترسی اضافه، **فقط** از [compose.userspace.yml](../compose.userspace.yml) استفاده کنید (`docker compose -f compose.userspace.yml up -d` و همان `-f` برای فرمان‌های بعدی). برنامه‌ها باید از پروکسی SOCKS5 روی `1055` یا HTTP روی `1056` استفاده کنند.

## عیب‌یابی

`tailscale version`، `tailscale netcheck`، `tailscale awg doctor` و `tailscale ping --tsmp <peer>` را بررسی کنید. موفقیت `tailscale ping` معمولی به‌تنهایی ثابت نمی‌کند که ترافیک برنامه‌ها کار می‌کند. هنگام ثبت [issue](https://github.com/LiuTangLei/tailscale-awg-installer/issues)، نسخه و نتیجه عیب‌یابی هر دو گره را ضمیمه کنید.

[مجوز BSD 3-Clause](../LICENSE) · [Tailscale](https://github.com/tailscale/tailscale) · [AmneziaWG](https://github.com/amnezia-vpn/amneziawg-go)
