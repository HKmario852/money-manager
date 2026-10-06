<div align="center">

<img src="../assets/logo.svg" width="96" alt="Money Expense 로고">

# Money Expense

**지출을 알아서 기록해 주는, 개인정보를 지키는 Android 가계부 앱.**

[![Latest release](https://img.shields.io/github/v/release/HKmario852/money-manager?display_name=release&label=release)](https://github.com/HKmario852/money-manager/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/HKmario852/money-manager/total)](https://github.com/HKmario852/money-manager/releases)
[![CI](https://img.shields.io/github/actions/workflow/status/HKmario852/money-manager/ci.yml?branch=main&label=CI)](https://github.com/HKmario852/money-manager/actions/workflows/ci.yml)
![Platform](https://img.shields.io/badge/platform-Android-3DDC84?logo=android&logoColor=white)
![Flutter](https://img.shields.io/badge/Flutter-02569B?logo=flutter&logoColor=white)

[English](../../README.md) · [繁體中文](README.zh-TW.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md) · **한국어** · [Español](README.es.md)

<img src="../screenshots/home.png" width="250" alt="홈"> <img src="../screenshots/stats.png" width="250" alt="통계"> <img src="../screenshots/places.png" width="250" alt="돈을 쓴 곳">

</div>

> [!NOTE]
> 앱 화면은 **번체 중국어(광둥어)로만** 제공됩니다. 홍콩용으로 만들어져 기본 통화는 홍콩 달러이며 AlipayHK, 옥토퍼스, 타오바오를 지원합니다.

<details>
<summary>스크린샷 더 보기</summary>
<br>
<p align="center">
<img src="../screenshots/inbox.png" width="250" alt="확인 대기">
<img src="../screenshots/app-spending.png" width="250" alt="앱 결제">
<img src="../screenshots/budgets.png" width="250" alt="예산">
<img src="../screenshots/add.png" width="250" alt="지출 기록">
</p>
<p align="center"><sub>스크린샷은 <a href="../../tool/screenshots/screenshots_test.dart">tool/screenshots</a>가 가상의 데모 데이터로 만듭니다.</sub></p>
</details>

## ✨ 기능

- 🔔 **결제를 자동으로 기록**: 결제 알림을 읽습니다(AlipayHK, Google Play, Google Wallet, 옥토퍼스, WeChat Pay, HSBC 또는 허용한 아무 앱). 새 결제는 '확인 대기'에 들어가며, 한 건씩 또는 한 번에 모두 확인할 수 있습니다.
- 📧 **Gmail 영수증**: 내 Google 계정에서 실행되는 Apps Script를 통해 가져옵니다. 스크립트는 앱이 제공하므로 붙여 넣기만 하면 됩니다.
- 🎮 **Google Play 구매 내역**: Google Takeout zip을 가져와 앱·게임별 지출을 확인합니다.
- 🛍️ **타오바오 주문**: 타오바오 '导出订单' Excel 파일이나 JSON 내보내기를 가져와, 주문일 환율로 위안화를 홍콩 달러로 환산합니다. 주문 상품도 저장하며, 내보내기에 사진이 있으면 함께 보여 줍니다.
- 🚇 **옥토퍼스**: 휴대폰 NFC로 카드를 태그해 잔액을 읽거나, 옥토퍼스 앱 스크린샷을 Gemini로 읽습니다.
- 📊 **돈을 쓴 곳**: 카테고리·주·월·연도별 통계, 가게/장소별 지출, 앱별 지출.
- 🎯 **예산**: 월 전체 예산과 카테고리별 예산, 그리고 하루에 더 쓸 수 있는 금액.
- ⌨️ **빠른 직접 입력**: 숫자 키패드, 태그, 템플릿, 영수증 사진.
- 🔒 **개인정보 보호**: 데이터는 휴대폰에만 저장됩니다. 지문 잠금과 비밀번호로 AES 암호화한 백업을 선택할 수 있습니다.
- ⬆️ **앱 내 업데이트**: 이 저장소의 GitHub Releases에서 업데이트합니다.

## 📥 다운로드

1. [**Releases**](https://github.com/HKmario852/money-manager/releases/latest)에서 최신 `.apk`를 내려받습니다.
2. Android 휴대폰에서 열고, 브라우저나 파일 관리자의 앱 설치를 허용합니다.
3. 이후 새 버전은 **設定 › 檢查更新**에 나타나며, 데이터를 유지한 채 덮어 설치됩니다.

> [!WARNING]
> 이 앱은 Google Play에 없습니다. 알림 접근 권한을 요청하기 때문에 Google Play 프로텍트가 경고하거나 설치를 막을 수 있습니다. 설치 후 알림 접근을 켤 수 없다면 Android 설정에서 이 앱의 페이지를 열고 **제한된 설정 허용**을 선택하세요.

## 🚀 빠른 시작

1. **처음 실행**: 통화를 고르고 첫 계좌(예: 현금)를 만듭니다.
2. **자동 기록 켜기**: **設定 › 自動記錄**에서 알림 접근을 허용하고, 읽어도 되는 결제 앱을 고릅니다.
3. **결제 확인**: 앱을 열 때마다 새 결제를 가져옵니다. 홈 화면의 **待確認**을 눌러 확인하세요. 고른 카테고리와 계좌는 다음에 같은 가게에 자동으로 적용됩니다.
4. **선택 가져오기**(모두 **設定 › 自動記錄**에 있음):
   - Gmail 영수증
   - Play 구매 내역이 담긴 Google Takeout zip
   - 타오바오 주문 파일
5. **돈을 쓴 곳 보기**: **統計**에서 전체를, **邊度使錢**에서 가게별로, **App 課金**에서 앱 지출을 확인합니다.

## ⚙️ 설정

모두 선택 사항이며 앱의 **設定 › 自動記錄**에서 설정합니다.

| 설정 | 하는 일 |
| --- | --- |
| 알림 접근 | 결제 알림을 읽을 수 있게 합니다. Android 전용. |
| 허용한 앱 | 이 앱들의 알림만 저장합니다. 다른 앱은 고를 수 있도록 이름만 표시합니다. |
| Gmail 영수증 | 내 Google 계정에 배포할 Apps Script를 제공합니다. 앱은 스크립트 검색 조건에 맞는 영수증을 가져옵니다. |
| Gemini API 키 | 기본 규칙으로 인식하지 못한 알림과 이메일, 옥토퍼스 스크린샷을 읽습니다. 키는 Android 보안 저장소에 보관됩니다. ⚠️ 일부 지역(예: 홍콩)에서는 Gemini를 쓸 수 없습니다. |
| 자동 확인 | 가게의 카테고리와 계좌를 이미 알면 묻지 않고 기록합니다. |

## 🛠️ 소스에서 빌드

[Flutter SDK](https://docs.flutter.dev/get-started/install)(stable 채널)와 Android SDK가 필요합니다.

```bash
git clone https://github.com/HKmario852/money-manager.git
cd money-manager
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter test
flutter run                 # 연결된 휴대폰이나 에뮬레이터에서 실행
flutter build apk --release
```

`android/key.properties`가 없으면 release 빌드는 디버그 키로 서명되므로, 공식 릴리스 위에 덮어 설치할 수 없습니다. 서명, CI, 스크린샷, 코드 구조는 [docs/DEVELOPMENT.md](../DEVELOPMENT.md)(영어)를 참고하세요.

## 🧰 기술 스택

- **언어와 UI**: [Flutter](https://flutter.dev)와 Dart, Material 3.
- **상태 관리**: [Riverpod](https://riverpod.dev).
- **저장소**: [Drift](https://drift.simonbinder.eu)(SQLite), 복식부기 장부.
- **Android 네이티브(Kotlin)**: 알림 읽기, 옥토퍼스 NFC, 앱 아이콘.
- **릴리스**: `main`에 푸시할 때마다 GitHub Actions가 테스트·빌드하고 서명된 APK를 게시합니다.

## 🔐 개인정보

- 기록, 영수증, 설정은 **내 휴대폰에만** 저장됩니다. Android 시스템 백업은 꺼져 있으니 데이터를 옮길 때는 앱의 백업 기능을 쓰세요.
- 계정도 분석도 없습니다. 앱은 다음 경우에만 인터넷에 연결합니다.
  - GitHub Releases에서 업데이트 확인
  - 선택 사항인 Gmail 스크립트와 Gemini
  - Google Play나 App Store에서 앱 아이콘 가져오기
  - 위안화→홍콩 달러 환율([frankfurter.dev](https://frankfurter.dev), [open.er-api.com](https://open.er-api.com))
  - 타오바오 상품 사진
- 알림 내용은 허용한 앱의 것만 저장합니다.

> [!IMPORTANT]
> 개인 프로젝트이며 은행이나 금융 상품이 아닙니다. 알림과 영수증은 최선을 다해 읽을 뿐이라 금액이 빠지거나 잘못 읽힐 수 있으니 기록을 꼭 확인하세요. Google Play, 타오바오, AlipayHK, 옥토퍼스 등은 각 소유자의 상표이며, 이 앱은 그 어느 곳과도 관련이 없습니다.

## 📄 라이선스

**아직 라이선스가 없습니다**. 모든 권리는 작성자에게 있습니다. 코드를 읽을 수는 있지만, 재사용하려면 허락이 필요합니다.

[Flutter](https://flutter.dev), [Drift](https://drift.simonbinder.eu), [Riverpod](https://riverpod.dev), [fl_chart](https://pub.dev/packages/fl_chart), [Material Symbols](https://fonts.google.com/icons)로 만들었습니다. 환율은 [유럽중앙은행(Frankfurter 경유)](https://frankfurter.dev) 자료입니다.
