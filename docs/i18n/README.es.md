<div align="center">

<img src="../assets/logo.svg" width="96" alt="Logo de Money Expense">

# Money Expense

**Una app privada de gastos para Android que apunta tus pagos por ti.**

[![Latest release](https://img.shields.io/github/v/release/HKmario852/money-manager?display_name=release&label=release)](https://github.com/HKmario852/money-manager/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/HKmario852/money-manager/total)](https://github.com/HKmario852/money-manager/releases)
[![CI](https://img.shields.io/github/actions/workflow/status/HKmario852/money-manager/ci.yml?branch=main&label=CI)](https://github.com/HKmario852/money-manager/actions/workflows/ci.yml)
![Platform](https://img.shields.io/badge/platform-Android-3DDC84?logo=android&logoColor=white)
![Flutter](https://img.shields.io/badge/Flutter-02569B?logo=flutter&logoColor=white)

[English](../../README.md) · [繁體中文](README.zh-TW.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · **Español**

<img src="../screenshots/home.png" width="250" alt="Inicio"> <img src="../screenshots/stats.png" width="250" alt="Estadísticas"> <img src="../screenshots/places.png" width="250" alt="Dónde se va el dinero">

</div>

> [!NOTE]
> La interfaz de la app está **solo en chino tradicional (cantonés)** y está pensada para Hong Kong: dólares de Hong Kong por defecto, con soporte para AlipayHK, Octopus y Taobao.

<details>
<summary>Más capturas</summary>
<br>
<p align="center">
<img src="../screenshots/inbox.png" width="250" alt="Pendientes de confirmar">
<img src="../screenshots/app-spending.png" width="250" alt="Gasto por app">
<img src="../screenshots/budgets.png" width="250" alt="Presupuestos">
<img src="../screenshots/add.png" width="250" alt="Añadir un gasto">
</p>
<p align="center"><sub>Capturas generadas con datos de demostración inventados por <a href="../../tool/screenshots/screenshots_test.dart">tool/screenshots</a>.</sub></p>
</details>

## ✨ Funciones

- 🔔 **Apunta los pagos sola** a partir de las notificaciones de pago (AlipayHK, Google Play, Google Wallet, Octopus, WeChat Pay, HSBC o cualquier app que permitas). Los pagos nuevos esperan en una lista donde los confirmas uno a uno o todos a la vez.
- 📧 **Recibos de Gmail** mediante un pequeño Google Apps Script que se ejecuta en tu propia cuenta de Google. La app te da el script para pegarlo.
- 🎮 **Historial de Google Play**: importa el zip de Google Takeout y mira cuánto has gastado en cada app o juego.
- 🛍️ **Pedidos de Taobao**: importa el Excel de 导出订单 de Taobao o una exportación en JSON, convertido de CNY a HKD con el tipo de cambio del día de cada pedido. También guarda los artículos, con fotos si la exportación las incluye.
- 🚇 **Octopus**: acerca la tarjeta al móvil (NFC) para leer el saldo, o lee capturas de la app de Octopus con Gemini.
- 📊 **Dónde se va el dinero**: estadísticas por categoría, semana, mes y año; gasto por tienda o lugar y gasto por app.
- 🎯 **Presupuestos**: uno para todo el mes y otro por categoría, con lo que aún puedes gastar al día.
- ⌨️ **Entrada manual rápida** con teclado numérico, etiquetas, plantillas y fotos de recibos.
- 🔒 **Privada**: los datos se quedan en el móvil. Bloqueo con huella opcional y copias de seguridad cifradas con contraseña (AES).
- ⬆️ **Actualizaciones desde la app** a través de las GitHub Releases de este repositorio.

## 📥 Descarga

1. Descarga el `.apk` más reciente desde [**Releases**](https://github.com/HKmario852/money-manager/releases/latest).
2. Ábrelo en tu móvil Android y permite instalar apps desde el navegador o el gestor de archivos.
3. Las versiones nuevas aparecen en **設定 › 檢查更新** y se instalan encima de la anterior, sin perder datos.

> [!WARNING]
> La app no está en Google Play. Google Play Protect puede avisar o bloquearla porque pide acceso a las notificaciones. Si después de instalarla el sistema no te deja activar ese acceso, abre la página de la app en los Ajustes de Android y elige **Permitir ajustes restringidos**.

## 🚀 Primeros pasos

1. **Primer inicio:** elige tu moneda y crea tu primera cuenta (por ejemplo, efectivo).
2. **Activa el registro automático:** en **設定 › 自動記錄**, da acceso a las notificaciones y elige qué apps de pago puede leer.
3. **Confirma los pagos:** la app recoge los pagos nuevos cada vez que la abres. Toca **待確認** en la pantalla de inicio y confírmalos. La categoría y la cuenta que elijas se recuerdan para la misma tienda.
4. **Importaciones opcionales** (todas en **設定 › 自動記錄**):
   - recibos de Gmail
   - un zip de Google Takeout con tus compras de Play
   - un archivo de pedidos de Taobao
5. **Mira dónde se va el dinero:** **統計** para el resumen, **邊度使錢** por tienda y **App 課金** para el gasto en apps.

## ⚙️ Configuración

Todo es opcional y se configura dentro de la app, en **設定 › 自動記錄**.

| Ajuste | Qué hace |
| --- | --- |
| Acceso a notificaciones | Permite a la app leer las notificaciones de pago. Solo Android. |
| Apps permitidas | Solo se guardan las notificaciones de estas apps. Las demás solo se listan por nombre para que puedas elegirlas. |
| Recibos de Gmail | Te da un Apps Script para desplegar en tu propia cuenta de Google. Después la app obtiene los recibos que coinciden con la búsqueda del script. |
| Clave de API de Gemini | Lee las notificaciones y correos que las reglas integradas no reconocen, y las capturas de Octopus. La clave se guarda en el almacenamiento seguro de Android. ⚠️ Gemini no está disponible en todas las regiones (por ejemplo, Hong Kong). |
| Confirmación automática | Apunta los pagos sin preguntar cuando ya conoce la categoría y la cuenta de la tienda. |

## 🛠️ Compilar desde el código

Necesitas el [SDK de Flutter](https://docs.flutter.dev/get-started/install) (canal stable) y el SDK de Android.

```bash
git clone https://github.com/HKmario852/money-manager.git
cd money-manager
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter test
flutter run                 # en un móvil conectado o un emulador
flutter build apk --release
```

Sin un `android/key.properties`, la compilación release se firma con la clave de depuración, así que no puede instalarse encima de una versión oficial. La firma, la CI, las capturas y la estructura del código están en [docs/DEVELOPMENT.md](../DEVELOPMENT.md) (en inglés).

## 🧰 Tecnologías

- **Lenguaje e interfaz:** [Flutter](https://flutter.dev) y Dart, con Material 3.
- **Estado:** [Riverpod](https://riverpod.dev).
- **Almacenamiento:** [Drift](https://drift.simonbinder.eu) sobre SQLite, como libro de partida doble.
- **Código Android (Kotlin):** lector de notificaciones, lector NFC de Octopus e iconos de apps.
- **Publicación:** GitHub Actions prueba, compila y publica un APK firmado en cada push a `main`.

## 🔐 Privacidad

- Tus registros, recibos y ajustes se guardan **solo en tu móvil**. La copia de seguridad de Android está desactivada; usa la copia de la propia app para mover tus datos.
- Sin cuenta y sin analíticas. La app solo se conecta a internet para:
  - buscar actualizaciones en GitHub Releases;
  - el script de Gmail y Gemini, si los activas;
  - iconos de apps desde Google Play o la App Store;
  - tipos de cambio CNY→HKD ([frankfurter.dev](https://frankfurter.dev), [open.er-api.com](https://open.er-api.com));
  - fotos de productos de Taobao.
- Solo se guarda el texto de las notificaciones de las apps que permites.

> [!IMPORTANT]
> Es un proyecto personal, no un banco ni un producto financiero. Lee notificaciones y recibos lo mejor que puede: puede saltarse importes o leerlos mal, así que revisa lo que apunta. Google Play, Taobao, AlipayHK, Octopus y los demás nombres son marcas de sus propietarios. La app no tiene relación con ninguno de ellos.

## 📄 Licencia

**Todavía no tiene licencia**, así que el autor se reserva todos los derechos. Puedes leer el código, pero necesitas permiso para reutilizarlo.

Hecha con [Flutter](https://flutter.dev), [Drift](https://drift.simonbinder.eu), [Riverpod](https://riverpod.dev), [fl_chart](https://pub.dev/packages/fl_chart) y [Material Symbols](https://fonts.google.com/icons). Los tipos de cambio son del [Banco Central Europeo a través de Frankfurter](https://frankfurter.dev).
