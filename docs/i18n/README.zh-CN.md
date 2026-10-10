<div align="center">

<img src="../assets/logo.svg" width="96" alt="Money Expense 标志">

# Money Expense

**一款注重隐私、会自动帮你记账的 Android 记账 App。**

[![Latest release](https://img.shields.io/github/v/release/HKmario852/money-manager?display_name=release&label=release)](https://github.com/HKmario852/money-manager/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/HKmario852/money-manager/total)](https://github.com/HKmario852/money-manager/releases)
[![CI](https://img.shields.io/github/actions/workflow/status/HKmario852/money-manager/ci.yml?branch=main&label=CI)](https://github.com/HKmario852/money-manager/actions/workflows/ci.yml)
![Platform](https://img.shields.io/badge/platform-Android-3DDC84?logo=android&logoColor=white)
![Flutter](https://img.shields.io/badge/Flutter-02569B?logo=flutter&logoColor=white)

[English](../../README.md) · [繁體中文](README.zh-TW.md) · **简体中文** · [日本語](README.ja.md) · [한국어](README.ko.md) · [Español](README.es.md)

<img src="../screenshots/home.png" width="250" alt="首页"> <img src="../screenshots/stats.png" width="250" alt="统计"> <img src="../screenshots/places.png" width="250" alt="钱花在哪里">

</div>

> [!NOTE]
> App 界面只有**繁体中文（粤语）**，为香港用户设计：默认港币，支持 AlipayHK、八达通和淘宝。

<details>
<summary>更多截图</summary>
<br>
<p align="center">
<img src="../screenshots/inbox.png" width="250" alt="待确认">
<img src="../screenshots/app-spending.png" width="250" alt="App 内购">
<img src="../screenshots/budgets.png" width="250" alt="预算">
<img src="../screenshots/add.png" width="250" alt="记一笔">
</p>
<p align="center"><sub>截图由 <a href="../../tool/screenshots/screenshots_test.dart">tool/screenshots</a> 用虚构的演示数据生成。</sub></p>
</details>

## ✨ 功能

- 🔔 **自动记录付款**：读取付款通知（AlipayHK、Google Play、Google Wallet、八达通、微信支付、HSBC，或任何你允许的 App）。新付款先进入“待确认”，可以逐笔确认，也可以一键全部确认。
- 📧 **Gmail 收据**：通过在你自己 Google 账户中运行的 Apps Script 读取。脚本由 App 提供，粘贴即可。
- 🎮 **Google Play 记录**：导入 Google Takeout 压缩包，查看每个 App 或游戏花了多少钱。
- 🛍️ **淘宝订单**：导入淘宝“导出订单”的 Excel 或 JSON 导出文件，按每笔订单当天的汇率从人民币换算成港币。商品明细也会保留，导出文件里有图片时一并显示。
- 🚇 **八达通**：用手机 NFC 贴卡读取余额，或用 Gemini 识别八达通 App 的截图。
- 📊 **钱花在哪里**：按分类、周、月、年统计，按商店/地点和按 App 查看支出。
- 🎯 **预算**：设置月度总预算和分类预算，并显示每天还能花多少。
- ⌨️ **快速手动记账**：数字键盘、标签、常用模板和收据照片。
- 🔒 **隐私**：数据只保存在手机上。可选指纹锁，备份可用密码 AES 加密。
- ⬆️ **App 内更新**：直接从本仓库的 GitHub Releases 更新。

## 📥 下载

1. 从 [**Releases**](https://github.com/HKmario852/money-manager/releases/latest) 下载最新的 `.apk`。
2. 在 Android 手机上打开，并允许浏览器或文件管理器安装应用。
3. 以后的新版本会出现在 **設定 › 檢查更新**，直接覆盖安装，数据会保留。

> [!WARNING]
> 本 App 没有上架 Google Play。因为它需要通知使用权，Google Play 保护机制可能会发出警告或拦截安装。如果安装后系统不允许开启通知使用权，请在 Android 设置中打开本 App 的页面，选择**允许受限制的设置**。

## 🚀 快速上手

1. **首次启动**：选择货币，并创建第一个账户（例如现金）。
2. **开启自动记录**：在 **設定 › 自動記錄** 中授予通知使用权，再选择允许读取的付款 App。
3. **确认付款**：每次打开 App 都会收集新付款。点击首页的 **待確認** 逐一确认。你选过的分类和账户，下次同一商户会自动套用。
4. **可选导入**（都在 **設定 › 自動記錄**）：
   - Gmail 收据
   - 包含 Play 购买记录的 Google Takeout 压缩包
   - 淘宝订单文件
5. **查看钱花在哪里**：**統計** 看总览，**邊度使錢** 看每家商店，**App 課金** 看 App 支出。

## ⚙️ 配置

以下全部可选，在 App 的 **設定 › 自動記錄** 中设置。

| 设置 | 作用 |
| --- | --- |
| 通知使用权 | 让 App 读取付款通知。仅限 Android。 |
| 允许的 App | 只保留这些 App 的通知。其他 App 只记录名称，方便你选择。 |
| Gmail 收据 | 提供一段 Apps Script，部署在你自己的 Google 账户中。之后 App 会获取符合脚本搜索条件的收据。 |
| Gemini API key | 识别内置规则认不出的通知和邮件，以及八达通截图。Key 保存在 Android 安全存储中。⚠️ 部分地区（例如香港）无法使用 Gemini。 |
| 自动入账 | 已知商户的分类和账户时直接入账，无需确认。 |

## 🛠️ 从源码构建

需要 [Flutter SDK](https://docs.flutter.dev/get-started/install)（stable 渠道）和 Android SDK。

```bash
git clone https://github.com/HKmario852/money-manager.git
cd money-manager
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter test
flutter run                 # 在已连接的手机或模拟器上运行
flutter build apk --release
```

没有 `android/key.properties` 时，release 版本会用 debug key 签名，因此无法覆盖安装官方版本。签名、CI、截图和代码结构见 [docs/DEVELOPMENT.md](../DEVELOPMENT.md)（英文）。

## 🧰 技术栈

- **语言和界面**：[Flutter](https://flutter.dev) 和 Dart，Material 3。
- **状态管理**：[Riverpod](https://riverpod.dev)。
- **存储**：[Drift](https://drift.simonbinder.eu)（SQLite），复式记账。
- **Android 原生（Kotlin）**：通知读取、八达通 NFC 和 App 图标。
- **发布**：每次推送到 `main`，GitHub Actions 都会测试、构建并发布已签名的 APK。

## 🔐 隐私

- 你的记录、收据和设置**只保存在你的手机上**。Android 系统备份已关闭，迁移数据请用 App 自带的备份功能。
- 无需注册，没有统计分析。App 仅在以下情况联网：
  - 到 GitHub Releases 检查更新；
  - 可选的 Gmail 脚本和 Gemini（会收到它们要读取的收据、通知或截图内容）；
  - 从 Google Play 或 App Store 获取 App 图标；
  - 人民币兑港币汇率（[frankfurter.dev](https://frankfurter.dev)、[open.er-api.com](https://open.er-api.com)）；
  - 淘宝商品图片。
- 只保留你允许的 App 的通知内容。

> [!IMPORTANT]
> 这是个人项目，不是银行或金融产品。识别通知和收据只能尽力而为，金额可能漏记或识别错误，请自行核对。Google Play、淘宝、AlipayHK、八达通等名称是其所有者的商标，本 App 与它们没有任何关联。

## 📄 许可证

以 [MIT 许可证](../../LICENSE) 发布。

基于 [Flutter](https://flutter.dev)、[Drift](https://drift.simonbinder.eu)、[Riverpod](https://riverpod.dev)、[fl_chart](https://pub.dev/packages/fl_chart) 和 [Material Symbols](https://fonts.google.com/icons) 构建。汇率来自[欧洲央行（经 Frankfurter）](https://frankfurter.dev)。
