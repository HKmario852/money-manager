<div align="center">

<img src="docs/assets/logo.svg" width="96" alt="Money Expense logo">

# Money Expense

**A private Android expense tracker that records your spending for you.**

[![Latest release](https://img.shields.io/github/v/release/HKmario852/money-manager?display_name=release&label=release)](https://github.com/HKmario852/money-manager/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/HKmario852/money-manager/total)](https://github.com/HKmario852/money-manager/releases)
[![CI](https://img.shields.io/github/actions/workflow/status/HKmario852/money-manager/ci.yml?branch=main&label=CI)](https://github.com/HKmario852/money-manager/actions/workflows/ci.yml)
![Platform](https://img.shields.io/badge/platform-Android-3DDC84?logo=android&logoColor=white)
![Flutter](https://img.shields.io/badge/Flutter-02569B?logo=flutter&logoColor=white)

**English** · [繁體中文](docs/i18n/README.zh-TW.md) · [简体中文](docs/i18n/README.zh-CN.md) · [日本語](docs/i18n/README.ja.md) · [한국어](docs/i18n/README.ko.md) · [Español](docs/i18n/README.es.md)

<img src="docs/screenshots/home.png" width="250" alt="Home"> <img src="docs/screenshots/stats.png" width="250" alt="Stats"> <img src="docs/screenshots/places.png" width="250" alt="Where the money goes">

</div>

> [!NOTE]
> The app's interface is in **Traditional Chinese (Cantonese)** only, and it is made for Hong Kong: HKD by default, with AlipayHK, Octopus and Taobao support.

<details>
<summary>More screenshots</summary>
<br>
<p align="center">
<img src="docs/screenshots/inbox.png" width="250" alt="Waiting for confirmation">
<img src="docs/screenshots/app-spending.png" width="250" alt="Spending per app">
<img src="docs/screenshots/budgets.png" width="250" alt="Budgets">
<img src="docs/screenshots/add.png" width="250" alt="Add an expense">
</p>
<p align="center"><sub>Rendered from made-up demo data by <a href="tool/screenshots/screenshots_test.dart">tool/screenshots</a>.</sub></p>
</details>

## ✨ Features

- 🔔 **Records payments by itself** from payment notifications (AlipayHK, Google Play, Google Wallet, Octopus, WeChat Pay, HSBC, or any app you allow). New payments wait in a list where you confirm them one by one or all at once.
- 📧 **Gmail receipts** through a small Google Apps Script that runs in your own Google account. The app gives you the script to paste.
- 🎮 **Google Play history**: import your Google Takeout zip and see what you spent on each app or game.
- 🛍️ **Taobao orders**: import the Excel file from Taobao's 导出订单 or a JSON export, converted from CNY to HKD at each order day's rate. Order items are kept too, with pictures when the export includes them.
- 🚇 **Octopus**: tap the card on the phone (NFC) to read its balance, or read screenshots of the Octopus app with Gemini.
- 📊 **Where the money goes**: stats by category, week, month and year, spending per shop or place, and spending per app.
- 🎯 **Budgets**: one for the whole month and one per category, with what you can still spend per day.
- ⌨️ **Fast manual entry** with a keypad, tags, templates and receipt photos.
- 🔒 **Private**: records stay on the phone in an encrypted database. Optional fingerprint lock and password-encrypted (AES) backups. Gemini and the Gmail script send text to Google only if you turn them on.
- ⬆️ **In-app updates** from this repository's GitHub Releases.

## 📥 Download

1. Download the latest `.apk` from [**Releases**](https://github.com/HKmario852/money-manager/releases/latest).
2. Open it on your Android phone and allow installing from your browser or file manager.
3. Later versions show up in **設定 › 檢查更新** and install over the old one, keeping your data.

> [!WARNING]
> The app is not on Google Play. Google Play Protect may warn about it or block it, because it asks for notification access. If the system blocks notification access after installing, open the app's page in Android Settings and choose **Allow restricted settings**.

## 🚀 Quick start

1. **First launch:** choose your currency and enter your first account (for example cash).
2. **Turn on auto recording:** go to **設定 › 自動記錄**, give the app notification access, then pick the payment apps it may read.
3. **Confirm payments:** the app picks up new payments each time you open it. Tap **待確認** on the home screen and confirm them. The categories and accounts you choose are remembered for the same shop next time.
4. **Optional imports** (all in **設定 › 自動記錄**):
   - Gmail receipts
   - a Google Takeout zip with your Play purchases
   - a Taobao order file
5. **See where the money goes:** check **統計** for the overview, **邊度使錢** for each shop and **App 課金** for app spending.

## ⚙️ Configuration

Everything is optional and set inside the app under **設定 › 自動記錄**.

| Setting | What it does |
| --- | --- |
| Notification access | Lets the app read payment notifications. Android only. |
| Allowed apps | Only notifications from these apps are kept. Other apps are only listed by name so you can pick them. |
| Gmail receipts | Gives you an Apps Script to deploy in your own Google account. The app then fetches receipts that match the script's search. |
| Gemini API key | Reads notifications and emails the built-in rules don't recognise, and Octopus screenshots. The key is stored in Android's secure storage. ⚠️ Gemini is not available in every region (for example Hong Kong). |
| Auto confirm | Records payments without asking when the shop's category and account are already known. |

## 🛠️ Build from source

You need the [Flutter SDK](https://docs.flutter.dev/get-started/install) (stable channel) and the Android SDK.

```bash
git clone https://github.com/HKmario852/money-manager.git
cd money-manager
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter test
flutter run                 # on a connected phone or emulator
flutter build apk --release
```

Without an `android/key.properties`, the release build is signed with the debug key, so it can't update an installed official release. Signing, CI, screenshots and the code layout are covered in [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).

## 🧰 Tech stack

- **Language and UI:** [Flutter](https://flutter.dev) and Dart, with Material 3.
- **State:** [Riverpod](https://riverpod.dev).
- **Storage:** [Drift](https://drift.simonbinder.eu) on SQLite, as a double-entry ledger.
- **Android code (Kotlin):** notification listener, Octopus NFC reader and app icons.
- **Release:** GitHub Actions builds and tests every push, and publishes a signed APK when the version in `pubspec.yaml` changes.

## 🔐 Privacy

- Your records, receipts and settings are stored **only on your phone**. The database is encrypted (SQLite3 Multiple Ciphers) with a key kept in Android's Keystore-protected storage. Android backup is turned off, so use the app's own backup to move data.
- No account and no analytics. The app only connects to the internet for:
  - checking GitHub Releases for updates;
  - the optional Gmail script and Gemini, which receive the text of receipts, notifications or screenshots they read;
  - app icons from Google Play or the App Store;
  - CNY→HKD exchange rates ([frankfurter.dev](https://frankfurter.dev), [open.er-api.com](https://open.er-api.com));
  - Taobao product pictures.
- Notification text is only kept for the apps you allow.

> [!IMPORTANT]
> This is a personal project, not a bank or financial product. It reads notifications and receipts on a best-effort basis: amounts can be missed or misread, so check what it records. Google Play, Taobao, AlipayHK, Octopus and the other names are trademarks of their owners. The app is not affiliated with any of them.

## 📄 License

Released under the [MIT License](LICENSE).

Built with [Flutter](https://flutter.dev), [Drift](https://drift.simonbinder.eu), [Riverpod](https://riverpod.dev), [fl_chart](https://pub.dev/packages/fl_chart) and [Material Symbols](https://fonts.google.com/icons). Exchange rates come from the [European Central Bank via Frankfurter](https://frankfurter.dev).
