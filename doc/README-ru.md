# Tailscale + AmneziaWG / QUIC

[English](../README.md) · [中文](README-zh.md) · [فارسی](README-fa.md) · [Релизы](https://github.com/LiuTangLei/tailscale/releases/latest)

**Current release: v1.104.4** — desktop, Docker, OpenWrt, Android and AwgScale.
Форк Tailscale с транспортами AmneziaWG и обфусцированным QUIC. Работает с официальным control plane Tailscale и с Headscale и ведёт себя как обычный Tailscale, пока вы не выберете другой транспорт.

[![Release](https://img.shields.io/github/v/release/LiuTangLei/tailscale?label=release)](https://github.com/LiuTangLei/tailscale/releases/latest) [![Docker](https://img.shields.io/docker/v/ltlei/tailscale-awg?sort=semver&label=docker)](https://hub.docker.com/r/ltlei/tailscale-awg/tags)

Номера версий совпадают с upstream: форк `vX.Y.Z` основан на Tailscale `vX.Y.Z`.

## Возможности

- **Три транспорта на уровне узла**: стандартный WireGuard (по умолчанию), AWG v3 / v2 и QUIC.
- **AWG v3**: защита заголовков, padding содержимого и случайные тайминги. AWG v2 оставлен для старых узлов.
- **QUIC**: HTTP/3 поверх TLS с настроенным BBRv3. Узлы доверяют друг другу по ключу узла автоматически, синхронизировать параметры не нужно.
- **Переподключение 0-RTT** между узлами v1.104.2+: одноразовые билеты и откат к полному рукопожатию. Совместимость с QUIC-узлами v1.104.1 сохранена.
- **Устойчивость к переупорядочиванию**: QUIC-пакеты, пришедшие не по порядку, больше не отбрасываются как дубликаты.
- **Роль сервера (опционально)**: после `tailscale awg server on` клиенты подключаются к этому узлу с TLS ClientHello в стиле Chromium.
- **Переключение одной командой** с автоматическим перезапуском и диагностика `tailscale awg doctor`.
- **Безопасное обновление**: установщики проверяют SHA-256, откатываются при ошибке и сохраняют текущий транспорт.

## Установка

| Платформа | Установка / загрузка | Версия |
| --- | --- | --- |
| Linux | `curl -fsSL https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-linux.sh \| bash` | [![release](https://img.shields.io/github/v/release/LiuTangLei/tailscale?label=)](https://github.com/LiuTangLei/tailscale/releases/latest) |
| macOS | `curl -fsSL https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-macos.sh \| bash` | [![release](https://img.shields.io/github/v/release/LiuTangLei/tailscale?label=)](https://github.com/LiuTangLei/tailscale/releases/latest) |
| Windows (PowerShell от администратора) | `iwr -useb https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-windows.ps1 \| iex` | [![release](https://img.shields.io/github/v/release/LiuTangLei/tailscale?label=)](https://github.com/LiuTangLei/tailscale/releases/latest) |
| Docker | `ltlei/tailscale-awg:latest` ([см. ниже](#docker)) | [![docker](https://img.shields.io/docker/v/ltlei/tailscale-awg?sort=semver&label=)](https://hub.docker.com/r/ltlei/tailscale-awg/tags) |
| OpenWrt | [Установщик, пакеты и репозиторий](https://github.com/LiuTangLei/openwrt-tailscale-awg) | [![openwrt](https://img.shields.io/github/v/release/LiuTangLei/openwrt-tailscale-awg?label=)](https://github.com/LiuTangLei/openwrt-tailscale-awg/releases/latest) |
| Android | [Подписанный APK](https://github.com/LiuTangLei/tailscale-android/releases/latest) | [![android](https://img.shields.io/github/v/release/LiuTangLei/tailscale-android?label=)](https://github.com/LiuTangLei/tailscale-android/releases/latest) |
| iOS | [AwgScale IPA](https://github.com/LiuTangLei/AwgScale/releases/latest) | [![ios](https://img.shields.io/github/v/release/LiuTangLei/AwgScale?label=)](https://github.com/LiuTangLei/AwgScale/releases/latest) |

- Ручная установка для Linux, macOS, Windows, OpenWrt и мобильных устройств: [manual installation guide](manual-install.md) (на английском).
- Установщики для ПК ставят последний релиз на x86_64 / ARM64. Чтобы закрепить версию, добавьте `--version <tag>` (Windows: `-Version <tag>`); на Linux / macOS `--uninstall` удаляет установку.
- На macOS используется служба CLI/utun; при переходе с Tailscale.app нужно войти заново.
- GUI для Windows должен совпадать с базовой версией Tailscale форка.
- Для iOS нужен TrollStore или entitlement Packet Tunnel; IPA не подписан для App Store.
- Обновление системным пакетным менеджером может вернуть официальные бинарники. Если команда `tailscale awg` пропала, запустите установщик снова.

## Зеркала GitHub

Если GitHub работает медленно или заблокирован, добавьте префикс зеркала к адресу скрипта и передайте тот же префикс установщику. Linux и macOS используют `--mirror`, Windows — `-MirrorPrefix` или переменную окружения `MIRROR_PREFIX`.

```bash
# macOS: замените install-linux.sh на install-macos.sh
curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-linux.sh \
  | bash -s -- --mirror https://ghfast.top
```

```powershell
$m = 'https://ghfast.top'
$code = (iwr -useb "$m/https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-windows.ps1").Content
& ([scriptblock]::Create($code)) -MirrorPrefix $m
```

| Зеркало | Примечание |
| --- | --- |
| `https://ghfast.top` | Используется по умолчанию в установщике OpenWrt |
| `https://gh-proxy.org` | Используется установщиком OpenWrt |
| `https://gh-proxy.com` | Проксирует и GitHub API |
| Своё | Любой прокси формата `https://<зеркало>/https://github.com/...`, например собственный [gh-proxy](https://github.com/hunshcn/gh-proxy) на Cloudflare Workers или в Docker |

- Установщик определяет последний релиз через `api.github.com` — сначала напрямую, затем через зеркало. Большинство зеркал не проксирует API; если запрос не удался, используйте `gh-proxy.com` или добавьте `--version <tag>` с версией из бейджа выше.
- Публичные зеркала — сторонние сервисы, они могут измениться или перестать работать. Для важных машин используйте своё зеркало.
- OpenWrt: установщик сам перебирает эти зеркала; для своего используйте `install.sh --custom-proxy`.

## Подключение и настройка

```bash
tailscale up
```

Для Headscale: `tailscale up --login-server https://your-headscale-domain`.

| Действие | Команда |
| --- | --- |
| Выбрать AWG v3 (по умолчанию), v2 или QUIC | `tailscale awg set` |
| Включить QUIC | `tailscale awg set --yes quic` |
| Показать / сохранить AWG JSON | `tailscale awg get` |
| Применить сохранённый JSON | `tailscale awg set '<JSON>'` |
| Скопировать профиль совместимого узла в сети | `tailscale awg sync` |
| Объявить узел QUIC-сервером | `tailscale awg server on` |
| Вернуться к стандартному WireGuard | `tailscale awg reset` |
| Активный режим / диагностика | `tailscale awg status` / `tailscale awg doctor` |

- У узлов AWG общие поля должны совпадать. Сгенерируйте профиль один раз, сохраните JSON и распространите его или используйте `sync`.
- QUIC действует на весь узел, и его должны включить все взаимодействующие узлы. Автоматического отката на WireGuard нет. Включение QUIC очищает профиль AWG — сохраните JSON заранее, если он понадобится.
- Смена транспорта перезапускает локальную службу и ненадолго прерывает VPN. Сохраните другой способ доступа к удалённым машинам.

## Docker

Используйте [docker-compose.yml](../docker-compose.yml) с образом `ltlei/tailscale-awg:latest` или `:v1.104` (следует за последним патч-релизом). Доступны amd64, arm64, arm/v7 и 386.

```bash
curl -fsSLO https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/docker-compose.yml
docker compose pull
docker compose up -d
docker compose exec tailscaled tailscale up
```

Для Headscale добавьте `--login-server https://your-headscale-domain`. Для входа без участия передавайте `TS_AUTHKEY` приватно и никогда не коммитьте его.

Внутри контейнера сначала подготовьте смену транспорта, затем перезапустите контейнер:

```bash
docker compose exec tailscaled tailscale awg set --no-restart --yes quic
docker compose restart tailscaled
```

Для AWG замените `--yes quic` на `'<JSON>'`.

- Сохраняйте команду образа `containerboot` и **весь** каталог `./tailscale-state`. Не используйте одно живое состояние узла в нескольких демонах.
- Режиму TUN нужны `/dev/net/tun` и `NET_ADMIN`; маршруты действуют внутри контейнера. Exit node и subnet router дополнительно требуют форвардинга и одобрения в control plane. При `TS_AUTH_ONCE=true` последующие изменения маршрутов требуют явного `tailscale set`.
- Без TUN и дополнительных прав используйте **только** [compose.userspace.yml](../compose.userspace.yml) (`docker compose -f compose.userspace.yml up -d` и тот же `-f` для остальных команд). Приложения должны работать через SOCKS5-прокси `1055` или HTTP-прокси `1056`.

## Диагностика

Проверьте `tailscale version`, `tailscale netcheck`, `tailscale awg doctor` и `tailscale ping --tsmp <peer>`. Успешный обычный `tailscale ping` ещё не означает, что трафик приложений проходит. В [issue](https://github.com/LiuTangLei/tailscale-awg-installer/issues) приложите версии и диагностику обоих узлов.

[Лицензия BSD 3-Clause](../LICENSE) · [Tailscale](https://github.com/tailscale/tailscale) · [AmneziaWG](https://github.com/amnezia-vpn/amneziawg-go)
