<div align="center">
  <img src="rubygram.jpeg" alt="Rubygram Banner" width="100%">
</div>


<p align="center">
  <a href="https://github.com/b-1-o/Rubygram/actions/workflows/build.yml">
    <img src="https://github.com/b-1-o/Rubygram/actions/workflows/build.yml/badge.svg?branch=ghost-mode-dev" alt="Build Status">
  </a>
  <img src="https://img.shields.io/badge/iOS-13.0%2B-blue.svg" alt="iOS Version">
  <img src="https://img.shields.io/badge/Swift-5.x-orange.svg" alt="Swift Version">
  <img src="https://img.shields.io/badge/License-GPLv3-green.svg" alt="License">
</p>

---

##  О проекте

**Rubygram** — это неофициальный клиент Telegram для iOS, основанный на открытом исходном коде Telegram-iOS и форке **Biogram**. 

Наша главная цель — предоставить пользователям максимальный контроль над своей приватностью и расширенные возможности кастомизации, вдохновленные лучшими решениями из **AyuGram** и **Swiftgram**.

## 👻 Ghost Mode (Режим призрака)

Мы полностью переосмыслили подход к приватности. Все настройки скрыты в удобном меню **«Возможности Rubygram»**. Переключатели работают мгновенно, без необходимости перезапуска клиента.

### Скрытие активности
-  **Don't Read Messages** — отключение отправки статуса «прочитано». Собеседник не узнает, что вы открыли чат.
-  **Don't Send Typing** — скрытие индикатора «печатает...».
-  **Don't Send Online** — блокировка статуса «онлайн». Вы не появитесь в сети, даже если открыли приложение.
-  **Don't Send Upload Progress** — скрытие процесса загрузки медиафайлов.

### Сохранение истории и медиа
-  **Save Deleted Messages** — сообщения, удаленные собеседником, **не исчезают из чата**. Они остаются на своих местах с аккуратной иконкой мусорной корзины рядом со временем.
-  **Save Deleted Media** — сохранение удаленных фотографий, видео, голосовых сообщений и кружков.
-  **Save Expiring Media (TTL)** — сохранение одноразовых фото и видео (view-once). Даже после просмотра они остаются в чате.
-  **Глобальный архив** — все удаленные сообщения доступны в отдельном меню, разделенном на вкладки: *Чаты, Медиа, Файлы, Голосовые, Кружки*. Даже если вы удалите сам чат, история останется в архиве.

##  Кастомизация (Наследие Biogram)

-  **3D-карточки профиля** — уникальный дизайн карточки с поддержкой материалов и кастомных артефактов.
-  **Анонимные номера** — декоративные виртуальные номера для вашего профиля.
-  **Алиасы и цвета** — настройка цветов профиля и альтернативных имен.
-  **Коллекционные подарки** — отображение стикеров и подарков в профиле.

## 🛠 Технический стек

Проект использует гибридный стек, характерный для Telegram-iOS:
- **Swift** — основной язык (UI, бизнес-логика).
- **Objective-C / C++** — низкоуровневые компоненты и мосты.
- **TDLib (Telegram Database Library)** — работа с протоколом MTProto.
- **Bazel** — система сборки.

##  Сборка и установка

В данный момент проект находится в активной разработке (ветка `ghost-mode-dev`).

### Сборка через GitHub Actions
Самый простой способ получить `.ipa` файл — запустить CI:
1. Перейдите в раздел **Actions** вашего форка.
2. Выберите workflow **Rubygram CI**.
3. Нажмите **Run workflow**, выбрав ветку `ghost-mode-dev`.
4. После успешной сборки скачайте артефакт `Rubygram.ipa`.

### Локальная сборка
Требуется Mac с установленным Xcode 15+ и Python 3.
```bash
# Клонирование
git clone https://github.com/b-1-o/Rubygram.git
cd Rubygram

# Переключение на ветку разработки
git checkout ghost-mode-dev

# Сборка
python3 build-system/Make/Make.py \
  --overrideBazelVersion \
  build \
  --configuration debug_arm64 \
  --buildNumber 1 \
  --configurationPath build-system/appstore-configuration.json \
  --xcodeManagedCodesigning
