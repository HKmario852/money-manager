<div align="center">

<img src="../assets/logo.svg" width="96" alt="Money Expense 標誌">

# Money Expense

**一個注重私隱、會自動幫你記帳的 Android 記帳 App。**

[![Latest release](https://img.shields.io/github/v/release/HKmario852/money-manager?display_name=release&label=release)](https://github.com/HKmario852/money-manager/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/HKmario852/money-manager/total)](https://github.com/HKmario852/money-manager/releases)
[![CI](https://img.shields.io/github/actions/workflow/status/HKmario852/money-manager/ci.yml?branch=main&label=CI)](https://github.com/HKmario852/money-manager/actions/workflows/ci.yml)
![Platform](https://img.shields.io/badge/platform-Android-3DDC84?logo=android&logoColor=white)
![Flutter](https://img.shields.io/badge/Flutter-02569B?logo=flutter&logoColor=white)

[English](../../README.md) · **繁體中文** · [简体中文](README.zh-CN.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Español](README.es.md)

<img src="../screenshots/home.png" width="250" alt="首頁"> <img src="../screenshots/stats.png" width="250" alt="統計"> <img src="../screenshots/places.png" width="250" alt="邊度使錢">

</div>

> [!NOTE]
> App 介面只有**繁體中文（粵語）**，為香港而設：預設港幣，支援 AlipayHK、八達通和淘寶。

<details>
<summary>更多截圖</summary>
<br>
<p align="center">
<img src="../screenshots/inbox.png" width="250" alt="待確認">
<img src="../screenshots/app-spending.png" width="250" alt="App 課金">
<img src="../screenshots/budgets.png" width="250" alt="預算">
<img src="../screenshots/add.png" width="250" alt="記一筆">
</p>
<p align="center"><sub>截圖由 <a href="../../tool/screenshots/screenshots_test.dart">tool/screenshots</a> 用虛構示範資料產生。</sub></p>
</details>

## ✨ 功能

- 🔔 **自動記錄付款**：讀取付款通知（AlipayHK、Google Play、Google Wallet、八達通、WeChat Pay、HSBC，或任何你允許的 App）。新付款會先放進「待確認」，可以逐筆確認，也可以一鍵全確認。
- 📧 **Gmail 收據**：透過在你自己 Google 帳戶裡執行的 Apps Script 讀取。腳本由 App 提供，你只要貼上即可。
- 🎮 **Google Play 紀錄**：匯入 Google Takeout 壓縮檔，看看每個 App 或遊戲花了多少。
- 🛍️ **淘寶訂單**：匯入淘寶「导出订单」的 Excel 或 JSON 匯出檔，按每張訂單當日匯率由人民幣換成港幣。商品明細也會保留，匯出檔有圖片的話會一併顯示。
- 🚇 **八達通**：用手機 NFC 拍卡讀取餘額，或用 Gemini 讀取八達通 App 的截圖。
- 📊 **錢花到哪裡**：按分類、週、月、年統計，按商店/地方和按 App 查看支出。
- 🎯 **預算**：設定全月總預算和分類預算，並顯示每日還可以花多少。
- ⌨️ **快速手動記帳**：數字鍵盤、Tag、常用模板和收據相片。
- 🔒 **私隱**：資料只存在手機裡。可選指紋鎖，備份可用密碼 AES 加密。
- ⬆️ **App 內更新**：直接從本 repo 的 GitHub Releases 更新。

## 📥 下載

1. 從 [**Releases**](https://github.com/HKmario852/money-manager/releases/latest) 下載最新的 `.apk`。
2. 在 Android 手機上開啟，並允許瀏覽器或檔案管理員安裝 App。
3. 之後的新版本會出現在 **設定 › 檢查更新**，直接覆蓋安裝，資料會保留。

> [!WARNING]
> 本 App 沒有上架 Google Play。由於它需要通知存取權，Google Play 保護機制可能會發出警告或封鎖它。如果安裝後系統不讓你開啟通知存取權，請到 Android 設定裡本 App 的頁面，選擇**允許受限制的設定**。

## 🚀 快速開始

1. **首次啟動**：選擇貨幣，並建立第一個帳戶（例如現金）。
2. **開啟自動記錄**：到 **設定 › 自動記錄** 給予通知存取權，再揀選可以讀取的付款 App。
3. **確認付款**：每次開啟 App 都會收集新付款。按首頁的 **待確認** 逐一確認。你選過的分類和帳戶，下次同一商戶會自動套用。
4. **可選匯入**（都在 **設定 › 自動記錄**）：
   - Gmail 收據
   - 含 Play 購買紀錄的 Google Takeout 壓縮檔
   - 淘寶訂單檔
5. **查看錢花到哪裡**：**統計** 看總覽，**邊度使錢** 看每間商店，**App 課金** 看 App 支出。

## ⚙️ 設定

以下全部可選，在 App 的 **設定 › 自動記錄** 裡設定。

| 設定 | 作用 |
| --- | --- |
| 通知存取權 | 讓 App 讀取付款通知。只限 Android。 |
| 允許的 App | 只保留這些 App 的通知。其他 App 只會記下名稱，方便你揀選。 |
| Gmail 收據 | 提供一段 Apps Script，部署在你自己的 Google 帳戶。App 之後會取得符合腳本搜尋條件的收據。 |
| Gemini API key | 讀取內建規則認不出的通知和電郵，以及八達通截圖。Key 存在 Android 的安全儲存區。⚠️ 部分地區（例如香港）不能使用 Gemini。 |
| 自動入帳 | 已知商戶的分類和帳戶時，直接入帳，不用再確認。 |

## 🛠️ 從原始碼建置

需要 [Flutter SDK](https://docs.flutter.dev/get-started/install)（stable channel）和 Android SDK。

```bash
git clone https://github.com/HKmario852/money-manager.git
cd money-manager
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter test
flutter run                 # 在已連接的手機或模擬器上執行
flutter build apk --release
```

沒有 `android/key.properties` 時，release 版本會用 debug key 簽署，所以不能覆蓋安裝官方版本。簽署、CI、截圖和程式碼結構請看 [docs/DEVELOPMENT.md](../DEVELOPMENT.md)（英文）。

## 🧰 技術

- **語言和介面**：[Flutter](https://flutter.dev) 和 Dart，Material 3。
- **狀態管理**：[Riverpod](https://riverpod.dev)。
- **儲存**：[Drift](https://drift.simonbinder.eu)（SQLite），複式記帳。
- **Android 原生（Kotlin）**：通知讀取、八達通 NFC 和 App 圖示。
- **發佈**：每次推送到 `main`，GitHub Actions 都會測試、建置並發佈已簽署的 APK。

## 🔐 私隱

- 你的紀錄、收據和設定**只存在你的手機**。Android 系統備份已關閉，搬資料請用 App 內的備份功能。
- 不用註冊，沒有分析追蹤。App 只會在以下情況連網：
  - 到 GitHub Releases 檢查更新；
  - 可選的 Gmail 腳本和 Gemini（會收到它們要讀取的收據、通知或截圖內容）；
  - 從 Google Play 或 App Store 取得 App 圖示；
  - 人民幣兌港幣匯率（[frankfurter.dev](https://frankfurter.dev)、[open.er-api.com](https://open.er-api.com)）；
  - 淘寶商品圖片。
- 只會保留你允許的 App 的通知內容。

> [!IMPORTANT]
> 這是個人專案，不是銀行或金融產品。讀取通知和收據只能盡力而為，金額可能漏記或讀錯，請自行核對。Google Play、淘寶、AlipayHK、八達通等名稱是其擁有者的商標，本 App 與它們沒有任何關係。

## 📄 授權

以 [MIT 授權條款](../../LICENSE) 發佈。

使用 [Flutter](https://flutter.dev)、[Drift](https://drift.simonbinder.eu)、[Riverpod](https://riverpod.dev)、[fl_chart](https://pub.dev/packages/fl_chart) 和 [Material Symbols](https://fonts.google.com/icons) 製作。匯率來自[歐洲央行（經 Frankfurter）](https://frankfurter.dev)。
