# Tailscale с Amnezia‑WG 2.0 (v1.88.2+)

[![GitHub Release](https://img.shields.io/github/v/release/LiuTangLei/tailscale)](https://github.com/LiuTangLei/tailscale/releases/latest)
[![Поддерживаемые платформы](https://img.shields.io/badge/platform-Linux%20|%20macOS%20|%20Windows%20|%20Android-blue)](https://github.com/LiuTangLei/tailscale/releases/latest)
[![Лицензия](https://img.shields.io/badge/license-BSD--3--Clause-green)](../LICENSE)

Улучшенный клиент Tailscale с обфускацией Amnezia‑WG 2.0: мусорный трафик, сигнатуры протоколов, маскировка рукопожатия и заголовков для обхода DPI и блокировок. По умолчанию ведет себя как официальный клиент, пока вы не включите параметры AWG.

Языки: [English](../README.md) | [中文](README-zh.md) | [فارسی](README-fa.md) | [Русский](README-ru.md)

Документация AWG 1.5: [README-awg-v1.5.md](README-awg-v1.5.md)

## Сломающие изменения (v1.88.2+)

- h1–h4 стали диапазонами [min, max] (включительно) вместо фиксированных значений; диапазоны не должны пересекаться
- добавлены s3 и s4 (в дополнение к s1, s2)
- интерактивная автогенерация: при `tailscale awg set` появится
    Do you want to generate random AWG parameters automatically? [Y/n]:
    нажмите Enter, чтобы автоматически сгенерировать все параметры, кроме i1–i5

Конфигурации 1.x несовместимы с 2.0. См. раздел «Миграция с 1.x».

## Установка

| Платформа | Команда / Действие |
| --- | --- |
| Linux | `curl -fsSL https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-linux.sh \| bash` |
| macOS* | `curl -fsSL https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-macos.sh \| bash` |
| Windows | `iwr -useb https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-windows.ps1 \| iex` |
| Android | Загрузите APK из [releases](https://github.com/LiuTangLei/tailscale-android/releases) |

macOS: скрипт использует CLI tailscaled; если обнаружен официальный Tailscale.app, вам предложат удалить его, чтобы избежать конфликтов.

Android может «получать» конфигурацию AWG с другого узла (кнопка Sync в приложении).

![Пример синхронизации AWG на Android](sync1.jpg)

## Быстрый старт

Подсказка: `tailscale amnezia-wg` = `tailscale awg`

1. Войти в сеть

```bash
tailscale up
# Headscale
tailscale up --login-server https://your-headscale-domain
```

1. Настроить AWG (автогенерация рекомендована)

```bash
tailscale awg set
```

Нажмите Enter при появлении запроса — все кроме i1–i5 будет сгенерировано.

1. Синхронизировать на другие устройства

- Desktop: `tailscale awg sync`
- Android: кнопка Sync

1. Тонкая настройка при необходимости: снова выполните `tailscale awg set`. Если сигнатуры не нужны — i1–i5 можно не задавать.

1. Полезные команды

```bash
tailscale awg get
tailscale awg reset
```

## Возможности и примеры

- Мусорный трафик и сигнатуры (совместимо со стандартными узлами)

```bash
tailscale awg set '{"jc":4,"jmin":64,"jmax":256}'
tailscale awg set '{"jc":2,"jmin":64,"jmax":128,"i1":"<b 0x40><r 12>"}'
```

- Маскировка протокола (все узлы должны использовать этот форк; s1–s4 и h1–h4 — одинаковы у всех; i1–i5 — необязательно одинаковые)

```bash
tailscale awg set '{"s1":10,"s2":15,"s3":8,"s4":0}'
tailscale awg set '{"s1":10,"s2":15,"s3":8,"s4":0,"h1":{"min":100000,"max":200000},"h2":{"min":300000,"max":350000},"h3":{"min":400000,"max":450000},"h4":{"min":500000,"max":550000}}'
tailscale awg set '{"s1":10,"s2":15,"s3":8,"s4":0,"h1":{"min":100000,"max":200000},"h2":{"min":300000,"max":350000},"h3":{"min":400000,"max":450000},"h4":{"min":500000,"max":550000},"i1":"<b 0xc0><r 32><c><t>"}'
```

## Справочник по настройке

- Базовое (совместимо со стандартными клиентами)

| Назначение | JSON | Совместимо |
| --- | --- | --- |
| Только мусор | `{"jc":4,"jmin":64,"jmax":256}` | ✅ |
| Мусор + сигнатуры | `{"jc":2,"jmin":64,"jmax":128,"i1":"<b 0xc0><r 16>"}` | ✅ |

- Продвинутое (узлы разделяют s1–s4 и h1–h4)

| Назначение | Пример | Примечания |
| --- | --- | --- |
| Префикс рукопожатия | `{"s1":10,"s2":15,"s3":8,"s4":0}` | значения s1–s4 совпадают у всех |
| Диапазоны заголовков | `{"s1":10,"s2":15,"s3":8,"s4":0,"h1":{"min":100000,"max":200000},"h2":{"min":300000,"max":350000},"h3":{"min":400000,"max":450000},"h4":{"min":500000,"max":550000}}` | h1–h4 — непересекающиеся диапазоны |
| Комбинация | `{"jc":2,"s1":10,"s2":15,"s3":8,"s4":0,"h1":{"min":100000,"max":200000},"h2":{"min":300000,"max":350000},"h3":{"min":400000,"max":450000},"h4":{"min":500000,"max":550000},"i1":"<b 0xc0><r 16>"}` | мусор/сигнатуры — опционально |

Параметры:

- jc (0–10), jmin/jmax (64–1024)
- i1–i5 — опциональная цепочка сигнатур
- s1–s4 — префикс/поля рукопожатия (совпадают у всех узлов AWG)
- h1–h4 — диапазоны заголовков {"min": min, "max": max}, четыре диапазона не пересекаются; либо заданы все, либо ни один; совпадают у всех

## Поддержка платформ

| Платформа | Архитектура | Статус |
| --- | --- | --- |
| Linux | x86_64, ARM64 | ✅ Полная |
| macOS | Intel, Apple Silicon | ✅ Полная |
| Windows | x86_64, ARM64 | ✅ Установщик |
| Android | ARM64, ARM | ✅ APK (только синхронизация AWG) |

## Миграция с 1.x

1. Обновите все узлы до v1.88.2+
1. При необходимости сбросьте старую конфигурацию 1.x

```bash
tailscale awg reset
```

1. Выполните `tailscale awg set` и нажмите Enter для автогенерации (кроме i1–i5)
1. Распространите `tailscale awg get` или используйте `tailscale awg sync`
1. Убедитесь, что s1–s4 и h1–h4 совпадают на всех маскируемых узлах, а диапазоны h1–h4 не пересекаются

Примечание: маскировка протокола между 1.x и 2.0 несовместима.

## Ссылки

- Releases: <https://github.com/LiuTangLei/tailscale/releases>
- Android APK: <https://github.com/LiuTangLei/tailscale-android/releases>
- Установщик (issues): <https://github.com/LiuTangLei/tailscale-awg-installer/issues>
- Amnezia‑WG docs: <https://docs.amnezia.org/documentation/instructions/new-amneziawg-selfhosted>

## Лицензия

BSD 3‑Clause (как у апстрима)

 
