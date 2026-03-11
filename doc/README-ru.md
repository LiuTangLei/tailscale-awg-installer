# Tailscale с Amnezia‑WG 2.0 (v1.88.2+)

[![GitHub Release](https://img.shields.io/github/v/release/LiuTangLei/tailscale)](https://github.com/LiuTangLei/tailscale/releases/latest)
[![Поддерживаемые платформы](https://img.shields.io/badge/platform-Linux%20|%20macOS%20|%20Windows%20|%20OpenWrt%20|%20Android-blue)](https://github.com/LiuTangLei/tailscale/releases/latest)
[![Лицензия](https://img.shields.io/badge/license-BSD--3--Clause-green)](../LICENSE)

Этот проект добавляет в Tailscale обфускацию Amnezia‑WG 2.0: мусорный трафик, сигнатуры протоколов, маскировку рукопожатия и заголовков. Пока вы не включили AWG-параметры, поведение соответствует обычному Tailscale.

Языки: [English](../README.md) | [中文](README-zh.md) | [فارسی](README-fa.md) | [Русский](README-ru.md)

Документация AWG 1.5: [README-awg-v1.5.md](README-awg-v1.5.md)

## Установка

| Платформа | Команда / действие |
| --- | --- |
| Linux | `curl -fsSL https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-linux.sh \| bash` |
| macOS* | `curl -fsSL https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-macos.sh \| bash` |
| Windows | `iwr -useb https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-windows.ps1 \| iex` |
| OpenWrt | См. [Установка OpenWrt](#установка-openwrt) |
| Android | Загрузите APK из [releases](https://github.com/LiuTangLei/tailscale-android/releases) |

- macOS: установщик использует CLI-версию `tailscaled`. Если обнаружен официальный Tailscale.app, будет предложено удалить его во избежание конфликтов.
- Android: пока поддерживается только получение AWG-конфигурации через Sync.

![Пример синхронизации AWG на Android](sync1.jpg)

## Docker Compose

В репозитории есть `docker-compose.yml` для запуска `tailscaled` с поддержкой AWG.

- Состояние хранится в каталоге `./tailscale-state` рядом с compose-файлом, поэтому состояние узла и параметры AWG сохраняются после перезапуска контейнера и перезагрузки хоста.
- Если вы переходите со старого bind mount `/var/lib/tailscale:/var/lib/tailscale`, сначала скопируйте существующее состояние:

```bash
docker compose down
cp -a /var/lib/tailscale ./tailscale-state
# обновите docker-compose.yml
docker compose up -d
```

Базовый сценарий:

1. Поднимите сервис: `docker compose up -d`
2. Авторизуйтесь в контейнере: `docker compose exec tailscaled tailscale up`
3. Выполняйте AWG-команды так же, например: `docker compose exec tailscaled tailscale awg sync`

Если вы используете Headscale, добавьте к `tailscale up` параметр `--login-server https://your-headscale-domain`.

Необязательный alias на хосте:

```bash
alias tailscale='docker exec -it tailscaled tailscale'
```

Этот alias действует только в текущем shell. Чтобы сохранить его после перезагрузки или открытия нового терминала, добавьте его в `~/.bashrc` или `~/.zshrc`, затем перезагрузите shell.

## Установка OpenWrt

Стандартная команда:

```bash
wget -O /usr/bin/install.sh https://raw.githubusercontent.com/LiuTangLei/openwrt-tailscale-awg/main/install_en.sh && chmod +x /usr/bin/install.sh && /usr/bin/install.sh
```

Для регионов с ограниченным доступом к GitHub:

```bash
wget -O /usr/bin/install.sh https://ghfast.top/https://raw.githubusercontent.com/LiuTangLei/openwrt-tailscale-awg/main/install.sh && chmod +x /usr/bin/install.sh && /usr/bin/install.sh
```

Скрипт основан на [GuNanOvO/openwrt-tailscale](https://github.com/GuNanOvO/openwrt-tailscale).

## Зеркала

Если GitHub работает медленно или недоступен, можно использовать собственное префиксное зеркало, например `https://your-mirror-site.com`:

```bash
# Linux
curl -fsSL https://your-mirror-site.com/https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-linux.sh | bash -s -- --mirror https://your-mirror-site.com

# macOS
curl -fsSL https://your-mirror-site.com/https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-macos.sh | bash -s -- --mirror https://your-mirror-site.com
```

```powershell
# Windows
$scriptContent = (iwr -useb https://your-mirror-site.com/https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-windows.ps1).Content; $scriptBlock = [scriptblock]::Create($scriptContent); & $scriptBlock -MirrorPrefix 'https://your-mirror-site.com/'
```

Если PowerShell блокирует выполнение, используйте `Set-ExecutionPolicy RemoteSigned` или `Bypass -Scope Process`.

## Быстрый старт

Подсказка: `tailscale amnezia-wg` равно `tailscale awg`.

1. Войдите в сеть:

```bash
# Официальный control plane
tailscale up

# Headscale
tailscale up --login-server https://your-headscale-domain
```

2. Настройте AWG:

```bash
tailscale awg set
```

На шаге автогенерации нажмите Enter, чтобы получить рекомендуемые значения для всех параметров, кроме `i1`-`i5`.

3. Синхронизируйте другие устройства:

- Desktop: `tailscale awg sync`
- Android: кнопка Sync в приложении

4. Проверяйте или сбрасывайте настройки при необходимости:

```bash
tailscale awg get
tailscale awg reset
```

## Готовые пресеты

| Цель | Пример | Совместимость |
| --- | --- | --- |
| Базовый мусорный трафик | `tailscale awg set '{"jc":4,"jmin":64,"jmax":256}'` | Работает со стандартными узлами Tailscale |
| Мусорный трафик + сигнатуры | `tailscale awg set '{"jc":2,"jmin":64,"jmax":128,"i1":"<b 0x40><r 12>"}'` | Работает со стандартными узлами Tailscale |
| Маскировка рукопожатия | `tailscale awg set '{"s1":10,"s2":15,"s3":8,"s4":0}'` | Все AWG-узлы должны иметь одинаковые `s1`-`s4` |
| Полная маскировка | `tailscale awg set '{"s1":10,"s2":15,"s3":8,"s4":0,"h1":{"min":100000,"max":200000},"h2":{"min":300000,"max":350000},"h3":{"min":400000,"max":450000},"h4":{"min":500000,"max":550000}}'` | Все AWG-узлы должны иметь одинаковые `s1`-`s4` и `h1`-`h4` |
| Полная маскировка + сигнатуры | `tailscale awg set '{"s1":10,"s2":15,"s3":8,"s4":0,"h1":{"min":100000,"max":200000},"h2":{"min":300000,"max":350000},"h3":{"min":400000,"max":450000},"h4":{"min":500000,"max":550000},"i1":"<b 0xc0><r 32><c><t>"}'` | `i1`-`i5` могут отличаться, но `s1`-`s4` и `h1`-`h4` должны совпадать |

## Справочник по параметрам

- `jc`, `jmin`, `jmax`: количество и размер мусорных пакетов.
- `i1`-`i5`: необязательная CPS-цепочка сигнатур.
- `s1`-`s4`: поля префикса или padding в рукопожатии; должны совпадать у всех AWG-узлов.
- `h1`-`h4`: диапазоны полей заголовков в виде `{"min": low, "max": high}`. Либо задаются все четыре, либо ни один. Диапазоны не должны пересекаться и должны совпадать у всех AWG-узлов.

Слишком большие значения мусорного трафика и длинные сигнатурные цепочки увеличивают задержку и расход трафика.

## Поддержка платформ

| Платформа | Архитектура | Статус |
| --- | --- | --- |
| Linux | x86_64, ARM64 | ✅ Полная |
| macOS | Intel, Apple Silicon | ✅ Полная |
| Windows | x86_64, ARM64 | ✅ Установщик |
| OpenWrt | Различные | ✅ Скрипт |
| Android | ARM64, ARM | ✅ APK (только sync AWG) |

## Дополнительно: сигнатуры протоколов

Формат CPS:

```text
i{n} = <tag1><tag2>...<tagN>
```

Теги:

- `<b 0xHEX>`: статические байты
- `<r N>`: криптографически стойкие случайные байты
- `<c>`: счетчик
- `<t>`: timestamp

Пример:

```text
i1 = <b 0xf6ab3267fa><c><b 0xf6ab><t><r 10>
```

Если `i1` не задан, `i2`-`i5` пропускаются.

## Устранение неполадок

Проверьте установку:

```bash
tailscale version
tailscale awg get
```

Если соединение ломается, сначала вернитесь к обычному WireGuard и попробуйте простой пресет:

```bash
tailscale awg reset
tailscale awg set '{"jc":2,"jmin":64,"jmax":128}'
sudo journalctl -u tailscaled -f
```

В Windows PowerShell удобнее использовать интерактивный режим:

```powershell
tailscale awg set
```

## Ссылки

- Releases: <https://github.com/LiuTangLei/tailscale/releases>
- Android APK: <https://github.com/LiuTangLei/tailscale-android/releases>
- Установщик (issues): <https://github.com/LiuTangLei/tailscale-awg-installer/issues>
- Amnezia-WG docs: <https://docs.amnezia.org/documentation/instructions/new-amneziawg-selfhosted/#how-to-extract-a-protocol-signature-for-amneziawg-manually>

## Лицензия

BSD 3-Clause, как и у upstream Tailscale.


