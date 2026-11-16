# Reja: "Ko'prik" — CrossOver o'rnini bosuvchi shaxsiy macOS dasturi

## Context

CrossOver pullik (rasmiy do'konda CrossOver+ 54 USD/yil, Life 494 USD). Maqsad: pul to'lamasdan, faqat shaxsiy foydalanish uchun, Windows dasturlari va o'yinlarini (Steam, Epic/GOG, Battle.net/EA/Ubisoft, ish dasturlari, ixtiyoriy `.exe`) macOS'da ishlatadigan, CrossOver'ning barcha imkoniyatlarini qamraydigan va undan qulayroq, ko'proq imkoniyatli o'z dasturimizni qurish.

Qaror qilingan: **noldan o'z SwiftUI dasturimiz**; Wine dvigateli tayyor ochiq build'lardan olinadi, keyinroq o'zimiz yig'amiz. Ishchi nom: **Ko'prik** (identifikatorlarda `Koprik`); 0-bosqichda bir qatorda o'zgartirsa bo'ladi.

Muhit (tekshirilgan): macOS 27.2.1, Apple M2 Pro, 16 GB RAM, 181 GB bo'sh, Xcode 27.2, Swift 6.4.2, Rosetta 2 ishlayapti, Homebrew 7.0.7. `/Applications/Whisky.app` 2.3.5 o'rnatilgan, lekin hech qachon sozlanmagan (bottle va Wine yo'q). Loyiha papkasi `/Users/xazratbek/programming/crossover` da faqat `CROSSOVER.md` bor, git yo'q.

### Halol chegaralar ("CrossOver'dan yaxshiroq" nimani anglatadi)

Yaxshiroq bo'la oladigan joylar: interfeys va qulaylik, har bir dastur uchun alohida sozlama, yangiroq komponentlar (Wine 11.19 + CrossOver 26.3 yamoqlari, DXMT 0.80, MoltenVK 1.4.2, GPTK 4 beta; CrossOver 26.3 da Wine 11.0, DXMT 0.72, D3DMetal 3.0), snapshot va orqaga qaytarish, do'konlar bilan to'g'ridan-to'g'ri ishlash, diagnostika.

Yaxshiroq bo'la olmaydigan joylar, reja bularni yashirmaydi:

- **Yadro darajasidagi anti-cheat** (Vanguard, Ricochet, EA Javelin, ko'p EAC/BattlEye o'yinlari) hech bir Wine vositasida ishlamaydi. Dastur buni yuklab olishdan oldin ogohlantiradi, lekin tuzata olmaydi.
- **Rosetta 2:** Apple rasmiy sahifasi bo'yicha Rosetta macOS 27 gacha mavjud; macOS 28 (2027 oxiri) dan faqat ayrim eski o'yinlar uchun qoladi. Hozirgi barcha ochiq Wine dvigatellari x86_64 va Rosetta'ga tayanadi. Mahalliy arm64 Wine `com.apple.developer.cross-architecture-support` entitlement'ini talab qiladi, uni Apple o'z ixtiyori bilan beradi. Yechim yo'q, faqat kuzatuv (9-bosqich). Amaliy qoida: arm64 dvigatel paydo bo'lmaguncha macOS 28 ga yangilamaslik.
- **D3DMetal (DX12 uchun asosiy yo'l)** faqat CrossOver'dan olingan Wine build'larida ishlaydi va Apple litsenziyasi ostida. Shuning uchun dasturga qo'shib tarqatilmaydi: foydalanuvchi GPTK'ni Apple saytidan o'zi yuklaydi, dastur import qiladi.
- **Retseptlar bazasi:** CodeWeavers'da minglab sinalgan retsept va xodimlar bor. Biz jamoat bazalariga (ProtonDB, umu-protonfixes, Lutris, frankea GameDB) tayanamiz.
- CrossOver'ning yopiq kodi, interfeysi va retseptlari **ko'chirilmaydi**. Faqat LGPL manba (`crossover-sources-26.3.0.tar.gz`) va ochiq loyihalardan foydalaniladi. Whisky'dan kod olinsa (GPL-3), loyiha GPL-3 bo'ladi: shaxsiy foydalanishda muammo emas, tarqatilsa manba ochilishi shart.

---

## 0-bosqich. Hujjatni yangilash va loyiha skeleti

### 0.1 `CROSSOVER.md` ni tasdiqlangan faktlar bilan tuzatish

Plan rejimida tahrir qilib bo'lmadi, shuning uchun bu birinchi ish. Fayl: `/Users/xazratbek/programming/crossover/CROSSOVER.md`. Rasmiy saytdan 2026-11-16 da o'qilgan faktlar:

| Band | Tuzatish |
|---|---|
| Narx (3-bo'lim) | CrossOver+ **54.00 USD**, 12 oy email va telefon yordami, yangilanishlar, CrossOver Preview'ga kirish. CrossOver Life **494.00 USD**, umrbod. Sinov 14 kun, bepul. Manba: `codeweavers.com/store`. `[tasdiqlanmagan]` belgisi olib tashlanadi; "74 USD" o'chiriladi; mahsulot nomi "Life" |
| CrossOver 27 (23-bo'lim) | **Chiqmagan.** Rasmiy changelog va Homebrew cask (`crossover` 26.3.0) oxirgi relizni 26.3.0 (2026-07-21) deb ko'rsatadi. Rasmiy blog ro'yxati: 2026-07-31 "CrossOver Preview: native ARM64 for macOS" (FEX tegi bilan), 2026-06-19 PortJump posti "In late 2027, macOS 28 will drop support for Rosetta", 2026-08-31 anti-cheat posti. Apple iqtibosi: Rosetta "will be available through macOS 27"; macOS 28 dan faqat eski o'yinlar uchun |
| Versiyalar jadvali (18.1, 22) | 22.0.0 = **Wine 7.7** (7.0 emas), interfeys to'liq qayta ishlangan, Linux'da DX12 boshlanishi. 23.0.0: Mac'da DX12 boshlanishi, DXVK 1.10.3, EA App, dasturlarni o'chirish imkoniyati. **23.5.0 (2023-09-27): D3DMetal kaliti, GPTK, Sonoma, GStreamer.** 23.6.0: CS2, Sonoma'da chop etish. **23.7.0: MSync**, Stage Manager. 21.0.0: DXVK 1.7, Wine Mono, Dark Mode. 20.0.0: ChromeOS, Big Sur, Mac'da DX11. 20.0.1: "Apple Silicon'ga tayyorgarlik". 19.0.0: Wine 4.12-1. `[tasdiqlanmagan]` belgilar olib tashlanadi |
| Changelog (22) | 26.0.0 va 25.0.0 o'yinlar ro'yxati to'liq yoziladi (matn olingan); 19.0.0 – 23.7.1 yozuvlari qo'shiladi |
| CLI va shell (14) | Mac'da rasmiy yo'l: bottle ustida o'ng tugma + **Option** bosilganda "Run Command" "Open Shell" ga aylanadi; `wine --cx-app prog.exe`, `wine cmd` |
| Disklar (7, 8.8) | Har bottle'da uchta disk: **C:** bottle ildizi, **Y:** uy papkasi, **Z:** disk ildizi. "Expired bottle" xatosi ko'pincha `dosdevices/z:` havolasi yo'qolganidan |
| Windows versiyasi | Rasmiy usul: Control Panels > Wine Configuration > Applications. `cxbottle.conf` rasmiy hujjatda hanuz tilga olinmaydi (faqat forum va uchinchi tomon qo'llanmasi); belgi qoladi |
| O'chirish (13) | CrossOver Removal Tool; qo'lda: `~/Library/Application Support/CrossOver`, `~/Library/Preferences/com.codeweavers.*`, `~/Applications/CrossOver`, ilova |
| Quyi tizimlar (18.7) | Chop etish: ba'zi printerlarda ishlamaydi, rasmiy aylanma yo'l PDFwriter virtual printeri. Klaviatura: Command sukut bo'yicha Alt; registr `HKCU\Software\Wine\Mac Driver` da `LeftOptionIsAlt`, `RightOptionIsAlt`, `LeftCommandIsCtrl`, `RightCommandIsCtrl` = `Y`. Kontrollerlar: Xbox One, Xbox Series, DualShock 4, DualSense muntazam sinaladi; o'yin XInput'ni qo'llashi shart; Windows drayverlari o'rnatilmaydi. Unlisted muammolar: "The-Kitchen-Sink.cxarchive" bog'liqliklar arxivi |
| Muhit o'zgaruvchilari (15) | Whisky manba kodidan tasdiqlangan: `WINEESYNC`, `WINEMSYNC` (MSync uchun `WINEESYNC=1` ham kerak), `MTL_HUD_ENABLED`, `METAL_CAPTURE_ENABLED`, `ROSETTA_ADVERTISE_AVX`, `D3DM_SUPPORT_DXR`, `DXVK_ASYNC`, `DXVK_HUD`. `D3DM_ENABLE_METALFX`, `D3DM_MTL4` hanuz tasdiqlanmagan |
| Cheklovlar (21) | Rosetta AVX va AVX2 ni tarjima qiladi, AVX512 ni yo'q (Apple). Steamworks: yadro darajasidagi himoya qo'llanmaydi. Linux anti-cheat jadvali (Valorant, Fortnite, Apex, R6 Siege, Warzone, Battlefield 6 bloklangan). Tasdiqlanmay qolganlar: UWP/Store, dongle'lar, Denuvo, OpenGL chegarasining aniq raqami, unumdorlik o'lchovlari |
| Muqobillar (24) | Whisky arxivlangan (GitHub: 2025-05-11); **frankea/Whisky** 3.10.1 (2026-11-15) faol; Heroic 2.22.4; Bottles 67.6; Lutris 0.5.22; DXMT 0.80 (MIT'dan LGPL'ga o'tmoqda); MoltenVK 1.4.2 (Vulkan 1.4); upstream DXVK 3.1.1; vkd3d-proton 3.1; winetricks 20260125 |
| Kompaniya (25) | Sayt navigatsiyasida PortJump va ExecMode xizmatlari tasdiqlandi; manba sahifasi komponentlari ro'yxati (Wine, vkd3d, GnuTLS, cabextract, Samba, Sparkle, PyObjC, wine-mono, FAudio, SDL) |

26-bo'limdagi "tasdiqlanmagan" ro'yxat shunga mos qisqartiriladi.

### 0.2 `docs/KOMPONENTLAR.md` yaratish

Qurilish komponentlari tadqiqotini saqlab qo'yish (versiyalar, URL andozalari, litsenziyalar). Mazmuni shu rejaning [Ilova](#ilova-tasdiqlangan-komponentlar) qismidan olinadi.

### 0.3 Loyiha skeleti

```
/Users/xazratbek/programming/crossover/
  CROSSOVER.md
  docs/KOMPONENTLAR.md
  project.yml               # XcodeGen spetsifikatsiyasi (.xcodeproj shundan yaratiladi)
  KoprikKit/                # Swift package: butun mantiq, UI'siz, testlar bilan
    Package.swift
    Sources/KoprikKit/{Engine,Bottle,Wine,Graphics,Install,Library,Compat,Diagnostics,Integration,Util}/
    Sources/koprik/         # CLI bajariluvchi target
    Tests/KoprikKitTests/
  Koprik/                   # SwiftUI ilova (yupqa qatlam)
    App/ Views/ Settings/ Resources/ Koprik.entitlements Info.plist
  KoprikThumbnail/          # Quick Look kengaytmasi (.exe ikonkalari)
  Recipes/                  # o'rnatish retseptlari (JSON)
  GameDB/                   # har o'yin uchun tuzatishlar (JSON)
  scripts/                  # build va reliz skriptlari
  appcast.xml
```

- `brew install xcodegen create-dmg` (foydalanuvchi tasdig'i bilan).
- Deployment target **macOS 26.0**, faqat arm64, Swift 6 qat'iy concurrency. Liquid Glass API'lari mavjudlik tekshiruvisiz ishlatiladi.
- App Sandbox **o'chiq** (Wine jarayonlarini ishga tushirish uchun shart; Whisky ham shunday).
- `git init` va birinchi commit `git-ops` agentiga topshiriladi.

---

## Arxitektura

### Modullar (`KoprikKit`)

| Modul | Vazifasi |
|---|---|
| `Engine` | Dvigatellar do'koni: manifest, yuklab olish, sha256 tekshiruvi, ochish, versiyalar yonma-yon, yangilash va orqaga qaytarish |
| `Bottle` | Bottle modeli, yaratish (shablondan APFS klon), nusxalash, snapshot, eksport/import, disklar, registr yordamchilari |
| `Wine` | Muhit quruvchi (`WineEnvironment`), `Process` ishga tushiruvchi, log oqimi, `wineserver` nazorati, jarayonlar ro'yxati |
| `Graphics` | Komponentlar (DXMT, DXVK, MoltenVK, GPTK importi), backend tanlash, Auto qoidalari |
| `Install` | Retsept dvigateli, o'rnatuvchini ishga tushirish, winetricks, bog'liqlik to'plamlari, o'rnatuvchi keshi |
| `Library` | Dasturlar va o'yinlar kutubxonasi, PE ikonka/metadata, `.lnk` o'qish, Steam kutubxonasini skanerlash, do'kon adapterlari (legendary, gogdl) |
| `Compat` | ProtonDB, AreWeAntiCheatYet, GameDB; ogohlantirishlar va avtomatik tuzatishlar |
| `Diagnostics` | Log tahlilchisi (ma'lum xato andozalari → tavsiya), hisobot yig'ish |
| `Integration` | `.app` launcher yaratish, fayl assotsiatsiyalari, URL sxemasi, App Intents |

Holat: `actor` lar (`EngineStore`, `BottleStore`, `ProcessSupervisor`), UI modellari `@Observable` + `@MainActor`.

### Dvigatel strategiyasi

Dvigatel = Wine daraxti + `engine.json` (id, Wine versiyasi, manba, arxitektura, `d3dmetalCapable`, ichidagi komponent versiyalari). Bir nechta dvigatel yonma-yon turadi, har bottle o'zinikiga bog'lanadi (CrossOver'da bitta, almashtirib bo'lmaydi).

1. **O'yin dvigateli (sukut):** `frankea/winecx-gptk` relizi `Libraries.tar.gz` (+ `.sha256`, `WhiskyWineVersion.plist`). Wine 11.19 + CrossOver 26.3 yamoqlari, DXMT 0.80, DXVK 1.10.3, MoltenVK 1.4.2, SDL2 2.32.10; macOS 27 va GPTK 4.0 beta 3 bilan sinalgan. D3DMetal ishlay oladigan yagona tayyor ochiq build.
2. **Toza dvigatel (ish dasturlari, zaxira):** `Gcenx/macOS_Wine_builds` (`wine-devel`/`wine-staging` 11.21, `wine-stable` 11.0_1).
3. **Mahalliy import:** papkadan, shu jumladan o'zimiz yig'gan dvigatel (9-bosqich).

Xavf: 1-manba bitta ko'ngilli qo'lida. Yumshatish: abstraksiya uch manbani ham qo'llaydi; 9-bosqichda o'z yig'ish quvuri.

Grafika komponentlari alohida boshqariladi: DXMT (`dxmt-v0.80-builtin.tar.gz`), DXVK-macOS 1.10.3, MoltenVK, va **GPTK importi** (foydalanuvchi Apple'dan yuklagan DMG yoki papkani ko'rsatadi; dastur `redist/lib` ichidagi `external` va `wine` qismlarini dvigatelga joylaydi, GPTK ichidagi Read Me bo'yicha).

### Wine'ni ishga tushirish

`Process` + dvigatel `bin/wine64`, dastur uchun `wine start /unix <yo'l>`. Muhit Whisky manba kodida tasdiqlangan to'plamga asoslanadi: `WINEPREFIX`, `WINEDEBUG=fixme-all`, `WINEDLLOVERRIDES`, `WINEMSYNC`/`WINEESYNC`, `DXVK_HUD`, `DXVK_ASYNC`, `MTL_HUD_ENABLED`, `ROSETTA_ADVERTISE_AVX`, `D3DM_SUPPORT_DXR`. Qatlamlar tartibi: dvigatel sukutlari → GameDB → bottle sozlamasi → dastur sozlamasi → bir martalik "Run with Options".

Qayta ishlatiladigan namunalar (o'qib, o'zimizcha yoziladi yoki GPL-3 ostida olinadi): `frankea/Whisky` dagi `WhiskyKit/Sources/WhiskyKit/Wine/Wine.swift` (muhit), `Whisky/BottleSettings.swift`, `PE/` (PE va ikonka parseri), `ShellLink.swift` (`.lnk`), `WhiskyWine/WhiskyWineInstaller.swift`, `Whisky/Utils/Winetricks.swift`.

### Diskdagi tuzilish

```
~/Library/Application Support/Koprik/
  Engines/<id>/            engine.json + Wine daraxti
  Components/{dxmt,dxvk,moltenvk,gptk}/<versiya>/
  Bottles/<uuid>/          bottle.json, prefix/ (WINEPREFIX), programs/<id>.json, snapshots/, logs/
  Templates/<engine>-<winver>/   tayyor prefikslar (APFS klon manbai)
  Cache/{installers,artwork,compat}/
~/Applications/Koprik/     yaratilgan .app launcherlar
```

Sozlamalar oddiy JSON (`Codable`), bottle bilan birga ko'chadi. Ma'lumotlar bazasi yo'q.

---

## CrossOver imkoniyatlari va bizdagi ustunlik

| CrossOver'da | Ko'prik'da |
|---|---|
| Bottle yaratish, nusxalash, nomlash, o'chirish, arxiv | Hammasi, ustiga: shablondan APFS klon orqali bir soniyada yaratish, o'chirish Savatga |
| Grafik backend faqat bottle bo'yicha | **Har dastur uchun alohida** backend, sinxronizatsiya, HUD, muhit, argumentlar, Windows versiyasi, DLL override, til |
| "Auto" backend (yopiq baza) | Auto: GameDB qoidasi, bo'lmasa PE importlarini tahlil qilish (`d3d12.dll` → D3DMetal, `d3d11.dll` → DXMT, `d3d9.dll` → wined3d/DXVK), sababi interfeysda ko'rsatiladi |
| Bitta dvigatel | Bir nechta dvigatel, bottle'ga bog'lash, yangilash va orqaga qaytarish |
| O'rnatishni bekor qilish bottle'ni buzishi mumkin | Har o'rnatish, bog'liqlik va dvigatel almashtirishdan oldin **avtomatik snapshot**; bekor qilish = tiklash |
| CrossTie retseptlari | O'z JSON retseptlarimiz + to'liq winetricks GUI + Lutris o'rnatuvchilarini import qilish (imkon qadar) |
| Steam, Epic, GOG faqat Windows launcherlari orqali | Launcherlar ham, ustiga Epic `legendary` va GOG `gogdl` orqali launchersiz; Steam kutubxonasi skanerlanib har o'yin alohida kartochka |
| Moslik: yulduzlar | ProtonDB darajasi + anti-cheat holati; bloklangan o'yin uchun yuklashdan oldin ogohlantirish |
| Run Command, debug log | Jonli log oynasi, filtr, **log tahlilchisi** (yetishmayotgan DLL → qaysi bog'liqlik), bir tugmada hisobot |
| Control Panels | winecfg, regedit, taskmgr, Simulate Reboot, Internet, kontrollerlar paneli, ustiga jarayonlar ro'yxati va bittalab to'xtatish |
| Klaviatura xaritasi registr fayli orqali | Sozlamada kalitlar (Command = Ctrl, Option = Alt) |
| Z: har doim butun diskka ochiq | Disklar muharriri va **"cheklangan bottle"** rejimi (Y: va Z: siz, faqat tanlangan papkalar) |
| Launcher ikonkalari | Haqiqiy `.app` launcherlar, Spotlight, Dock, menyu satri paneli, global tezkor ishga tushirgich, Shortcuts, `koprik://` sxemasi, Quick Look ikonkalari |
| Published bottle, ChromeOS, Linux | Qamrovdan tashqari (bitta foydalanuvchi, faqat macOS) |
| Sparkle yangilanish | Ilova uchun Sparkle; dvigatel, komponent va GameDB uchun alohida yangilovchi |
| yo'q | O'yin vaqti hisobi, artwork, to'plamlar, sevimlilar, disk sarfi va tozalash, saqlangan o'yinlar zaxirasi, Whisky bottle'larini import qilish, `koprik` CLI, o'zbek/ingliz/rus interfeysi |

---

## UI/UX loyihasi

Tamoyillar: sukut bo'yicha bir tugma ("Auto"), murakkab sozlamalar yashirin lekin yaqin (inspektor), har xavfli amal qaytariladigan, holat doim ko'rinadi (ishlayapti nuqtasi, dvigatel va backend belgisi), har joyga klaviaturadan yetish.

- **Asosiy oyna:** `NavigationSplitView` + `.inspector` (`macos-patterns` andozasi).
  - Chap panel: *Kutubxona* (Hammasi, O'yinlar, Dasturlar, Sevimlilar, Yaqinda), *Do'konlar* (Steam, Epic, GOG), *Bottle'lar*, *O'rnatish*, *Faoliyat* (yuklab olish va o'rnatish navbati).
  - Markaz: artwork yoki PE ikonkali kartochkalar to'ri; ustiga borganda Play; ro'yxat ko'rinishi ham bor.
  - O'ng inspektor: tanlangan dastur yoki bottle uchun yorliqlar: Umumiy, Grafika, Unumdorlik, Muhit, Fayllar, Log.
  - Asboblar paneli: qidiruv, "+" (o'rnatish yoki `.exe` qo'shish), Run Command, ko'rinish almashtirgich.
- **Sudrab tashlash:** `.exe`, `.msi`, `.lnk` ni oynaga yoki Dock ikonkasiga tashlash; dastur o'rnatuvchi yoki portativligini aniqlab, mos oqimni taklif qiladi.
- **Cmd+K buyruqlar palitrasi:** dasturni ishga tushirish, bottle amallari, sozlamalar.
- **Birinchi ishga tushirish:** 3 qadam: Rosetta tekshiruvi (yo'q bo'lsa o'rnatishni taklif), dvigatelni yuklash (progress bilan), ixtiyoriy GPTK importi (DX12 nima uchun kerakligi tushuntiriladi).
- **Sozlamalar oynasi:** `macos-settings-ui` andozasi bo'yicha (`NSWindowController` + `.fullSizeContentView`, guruhlangan `Form`): Umumiy, Dvigatellar, Grafika komponentlari, Do'konlar (akkauntlar), Integratsiya, Yangilanishlar, Kengaytirilgan.
- **Menyu satri paneli:** `MenuBarExtra(.window)`: yaqinda ishlatilganlar, ishlayotgan bottle'lar, "Hammasini to'xtatish".
- **Bo'sh holatlar** foydali: nima qilish kerakligi va tashlash maydoni.
- Bajarishda yuklanadigan skill'lar: `axiom-swiftui` (qurish), `design` (Liquid Glass, animatsiya), `swiftui-pro` (ko'rib chiqish), `ui-ux-pro-max`.

---

## Bosqichlar

Har bosqich oxirida `swift test` va `xcodebuild` yashil, hamda ko'rsatilgan qabul sinovi o'tgan bo'lishi kerak.

### 1-bosqich. Yadro (CLI orqali, interfeyssiz)

`Engine`, `Bottle`, `Wine` modullari va `koprik` CLI.

- Dvigatelni yuklash, sha256, ochish; Rosetta tekshiruvi.
- Bottle yaratish (`wineboot`), dasturni ishga tushirish, logni faylga va oqimga yozish, `wineserver -k`.
- **Go/no-go sinovlari** (natija keyingi bosqichlarni belgilaydi):
  1. `koprik bottle create test && koprik run test notepad.exe` oyna ochadi.
  2. 7-Zip o'rnatuvchisi `/S` bilan o'rnatiladi, fayl paydo bo'ladi.
  3. Steam o'rnatiladi va do'kon sahifasi chiziladi (forumda 2026-10-31 atrofida Steam buzilgani xabar qilingan; frankea 4.8.3 ishlaydi deydi; o'zimizda tekshiriladi).
  4. Bitta DX11 o'yin DXMT bilan, GPTK import qilingach bitta DX12 o'yin D3DMetal bilan ishga tushadi.
  5. Backendni almashtirish mexanizmi aniqlanadi (frankea `Wine.swift` ni o'qib): jarayon darajasida muhit orqali mumkinmi yoki DLL nusxalash kerakmi. Bu "har dastur uchun backend" ning qanday amalga oshishini hal qiladi.

### 2-bosqich. Ilova qobig'i

Asosiy oyna, birinchi ishga tushirish oqimi, bottle ro'yxati va yaratish, PE ikonkali dasturlar to'ri, ishga tushirish, sudrab tashlash, sozlamalar oynasi karkasi, menyu buyruqlari va yorliqlar.
Qabul: ilovani ochib, dvigatelni yuklab, `.exe` ni tashlab ishga tushirish sichqoncha bilan to'liq bajariladi.

### 3-bosqich. Bottle boshqaruvi (CrossOver bilan tenglik)

Shablonlar (Windows 7/10/11, 64-bit), nusxalash (`clonefile`), qayta nomlash, Savatga o'chirish, snapshot va tiklash, eksport/import (`.koprikbottle`: manifest + `tar.zst`), disklar muharriri va cheklangan rejim, Control Panels, Simulate Reboot, Quit All / Force Quit, jarayonlar ro'yxati, bottle va dastur sozlamalari, muhit va DLL override muharrirlari, Run Command, Run with Options, jonli log, C: diskni ochish, dasturni o'chirish (`wine uninstaller`), `.app` launcher yaratish.
Qabul: `CROSSOVER.md` ning 8, 10, 11-bo'limlaridagi har bir amal ilovada bajariladi; snapshotdan tiklash bottle'ni aynan oldingi holatga qaytaradi.

### 4-bosqich. Grafika va unumdorlik

Komponentlar boshqaruvchisi, GPTK importi, backend tanlash va Auto, HUD'lar (Metal, DXVK), MSync/ESync, Retina (`RetinaMode` registri), DLSS/MetalFX, AVX e'loni, DXR, FPS chegarasi, DXVK async.
Qabul: bitta o'yinda backendni interfeysdan almashtirib, HUD orqali haqiqatan o'zgarganini ko'rish.

### 5-bosqich. Dastur o'rnatish

- Ixtiyoriy `.exe`/`.msi` uchun o'rnatish oqimi (yangi yoki mavjud bottle, oldindan snapshot, xavfsiz bekor qilish).
- Retsept dvigateli (JSON): bottle shabloni, winetricks verblari, sha256 li yuklab olishlar, jim o'rnatish argumentlari, registr o'zgarishlari, muhit, launcher ta'riflari.
- Boshlang'ich retseptlar: Steam, Epic Games Launcher, GOG Galaxy, Battle.net, EA app, Ubisoft Connect, Rockstar, 7-Zip, Notepad++, MetaTrader, Microsoft Office (sinab ko'riladi).
- Winetricks GUI (verblar ro'yxati, o'rnatilgan holati) va tayyor to'plamlar ("O'yinlar uchun asosiy": `corefonts`, `vcrun2022`, `d3dcompiler_47`; ".NET dasturlari": `dotnet48`).
- Steam kutubxonasini skanerlash (`libraryfolders.vdf`, `appmanifest_*.acf`) va o'yinni to'g'ridan-to'g'ri `-applaunch` bilan ochish.
Qabul: Steam, Battle.net va bitta ish dasturi retsept orqali aralashuvsiz o'rnatiladi.

### 6-bosqich. Kutubxona, do'konlar, moslik

- Epic: `legendary` 0.21.1; GOG: `heroic-gogdl` 1.4.0 (kirish, ro'yxat, yuklab olish, bottle'ga o'rnatish, ishga tushirish).
- Artwork (Steam `appdetails`; SteamGridDB ixtiyoriy, kalit bilan), o'yin vaqti, to'plamlar.
- ProtonDB darajasi, AreWeAntiCheatYet `games.json` (MIT), anti-cheat ogohlantirishi.
- GameDB: o'z JSON formatimiz; boshlang'ich to'ldirish umu-protonfixes (BSD-2) va frankea GameDB'dan qo'lda ko'chirib moslash.
Qabul: Epic'dan bepul bir o'yin va GOG'dan bir o'yin Windows launchersiz yuklanib o'ynaladi; Valorant qidirilganda bloklangani ko'rsatiladi.

### 7-bosqich. macOS integratsiyasi va sayqal

Quick Look kengaytmasi, fayl assotsiatsiyalari, menyu satri paneli, global tezkor tugma, App Intents, `koprik://`, kontrollerlar paneli (GameController holati, hidraw/SDL kalitlari), klaviatura kalitlari, shrift va PDF chop etish yordamchilari, disk sarfi va tozalash, log tahlilchisi, saqlangan o'yinlar zaxirasi, Whisky bottle'larini import, lokalizatsiya (uz, en, ru), VoiceOver va klaviatura bilan boshqarish, dizayn ko'rigi.

### 8-bosqich. Yangilanish va reliz (`macos-auto-update`, `macos-release`)

- Sparkle 2.10.1 SPM orqali, `UpdaterManager` (skill'dagi namuna), `SUFeedURL`, `SUPublicEDKey`, Sozlamalarda "Yangilanishlarni tekshirish".
- Imzolash: pullik Apple Developer akkaunti yo'q deb faraz qilinadi, shuning uchun notarizatsiyasiz, mahalliy imzo bilan. Bu shaxsiy Mac'da yetarli; boshqa Mac'ga tarqatish uchun Developer ID kerak bo'ladi.
- Reliz quvuri: versiyani oshirish → `xcodebuild archive` → `create-dmg` → `sign_update` → `appcast.xml` → GitHub Release. Git va GitHub qismi `git-ops` agentiga. Appcast raw URL orqali o'qiladi, shuning uchun repozitoriy ochiq bo'lishi yoki appcast boshqa joyda turishi kerak; bu shu bosqichda hal qilinadi.
- Tekshiriladi: notarizatsiyasiz build'da Sparkle yangilanishi Gatekeeper to'sig'isiz o'rnatilishi.

### 9-bosqich. O'z dvigatelimiz va Rosetta'dan keyingi davr (uzoq muddatli)

- `crossover-sources-26.3.0.tar.gz` (149 MB, LGPL) yoki `dappermint/winecx` dan `frankea/winecx-gptk` retsepti bo'yicha o'zimiz yig'ish (Unix yarmi x86_64 Rosetta ostida, PE yarmi mingw-w64 GCC bilan).
- arm64 yo'lini kuzatish: CrossOver ARM64 Preview manbasi, FEX, frankea tajribalari. macOS 28 chiqishidan oldin qaror.

---

## Tekshirish

- **Birlik testlari** (`cd KoprikKit && swift test`): muhit quruvchi qatlamlari, PE va `.lnk` parserlari, retsept va GameDB parserlari, VDF/ACF parseri, dvigatel manifesti, snapshot yo'llari.
- **Build** (`macos-build` skill): `xcodegen generate`, so'ng `xcodebuild build -project Koprik.xcodeproj -scheme Koprik -configuration Debug -destination "platform=macOS"`.
- **Integratsiya (CLI, avtomatik):** bottle yaratish → `wine --version` → 7-Zip jim o'rnatish → fayl borligini tekshirish → snapshot → o'zgartirish → tiklash → solishtirish.
- **Qo'lda matritsa** (har bosqichdan keyin kengayadi): Steam (kirish, bir DX11 va bir DX12 o'yin), Epic va GOG o'yini, Battle.net, bitta ish dasturi, portativ `.exe`, `.msi`.
- **Interfeys:** ilovani ishga tushirib skrinshot orqali ko'rish (`run` skill), har ekran uchun yorug' va qorong'i rejim.
- Har qabul sinovi natijasi `docs/SINOV.md` ga yoziladi: nima ishladi, nima ishlamadi.

## Ish tartibi

- Git va GitHub ishlari `git-ops`, tashqi ma'lumot `researcher`, server ishlari `deployer` agentiga (standart qoida).
- `brew install`, katta yuklab olishlar (dvigatel ~yuzlab MB, Steam) va GitHub repozitoriy yaratishdan oldin tasdiq so'raladi.
- Bosqichlar ketma-ket; 1-bosqichning go/no-go sinovlari o'tmaguncha interfeysga o'tilmaydi.

---

## Ilova: tasdiqlangan komponentlar

(2026-11-16 holatiga; GitHub API va rasmiy sahifalardan.)

| Komponent | Versiya | Manba | Litsenziya |
|---|---|---|---|
| frankea/Whisky (namuna) | app 3.10.1 (2026-11-15) | github.com/frankea/Whisky | GPL-3.0 |
| frankea/winecx-gptk (dvigatel) | v4.8.3: Wine 11.19 + CrossOver 26.3 yamoqlari | relizdagi `Libraries.tar.gz`, `.sha256`, `WhiskyWineVersion.plist` | LGPL (Wine) |
| Gcenx Wine build'lari | devel/staging 11.21 (2026-10-31); stable 11.0_1 | `github.com/Gcenx/macOS_Wine_builds/releases/download/<tag>/wine-<kanal>-<tag>-osx64.tar.xz` | LGPL |
| CrossOver manbasi | 26.3.0, 149 MB | `media.codeweavers.com/pub/crossover/source/crossover-sources-26.3.0.tar.gz` | LGPL/GPL qismlar |
| DXMT | v0.80 (2026-04-23), D3D10/11 | `github.com/3Shain/dxmt/releases/download/v0.80/dxmt-v0.80-builtin.tar.gz` | MIT (0.80), keyin LGPL |
| DXVK-macOS | v1.10.3-20230507-repack | github.com/Gcenx/DXVK-macOS | Zlib |
| MoltenVK | v1.4.2 (2026-07-24), Vulkan 1.4 | github.com/KhronosGroup/MoltenVK | Apache-2.0 |
| Game Porting Toolkit | 4 (beta); Gcenx paketi 3.0-3 | developer.apple.com/games/game-porting-toolkit | Apple litsenziyasi, qo'shib tarqatilmaydi |
| winetricks | 20260125 | github.com/Winetricks/winetricks | LGPL-2.1 |
| legendary (Epic) | 0.21.1 | github.com/derrod/legendary | GPL-3.0 |
| heroic-gogdl (GOG) | v1.4.0 | github.com/Heroic-Games-Launcher/heroic-gogdl | GPL-3.0 |
| umu-protonfixes | faol | github.com/Open-Wine-Components/umu-protonfixes | BSD-2-Clause |
| AreWeAntiCheatYet | `games.json` | raw.githubusercontent.com/AreWeAntiCheatYet/AreWeAntiCheatYet/master/games.json | MIT |
| ProtonDB (norasmiy) | | `protondb.com/api/v1/reports/summaries/<appid>.json` | shartlari tekshirilmagan |
| Steam do'koni | | `store.steampowered.com/api/appdetails?appids=<id>` | shartlari tekshirilmagan |
| Lutris API | | `lutris.net/api/games`, `lutris.net/api/installers` | o'rnatuvchilar litsenziyasi noaniq |
| Sparkle | 2.10.1 (2026-10-25) | github.com/sparkle-project/Sparkle | MIT |

Muhim texnik faktlar:

- D3DMetal faqat CrossOver'dan olingan Wine'da ishlaydi (yuklanayotganda uning unixcall ichki qismini yamaydi).
- DXMT o'rnatish: `winemetal.so` → `lib/wine/x86_64-unix/`, `winemetal.dll` → `lib/wine/x86_64-windows/` va prefiks `system32`; `WINEDLLOVERRIDES="dxgi,d3d11,d3d10core=n,b"`.
- DXVK o'rnatish: `x64/*.dll` → `system32`, `x32/*.dll` → `syswow64`, override'lar.
- Whisky saqlash tuzilishi (import uchun): `~/Library/Containers/com.isaacmarovitz.Whisky/BottleVM.plist` (`paths`), har bottle'da `Metadata.plist`, `Program Settings/<exe>.plist`.
- Tekshirilishi kerak (bajarish paytida): GPTK 4 fayl tuzilishi, DXMT konfiguratsiya kalitlari, Steam `steamwebhelper` uchun bayroqlar, DXVK 3.x ning MoltenVK 1.4.2 ustida ishlashi, ProtonDB va Steam API shartlari.
