# Qurilish komponentlari: ochiq manbali asoslar

Tadqiqot sanasi: 2026-11-16. Manbalar: GitHub API (`gh api`), Homebrew JSON API, rasmiy sahifalar. `[tasdiqlanmagan]` belgisi qo'yilgan joylar bajarish paytida tekshirilishi kerak.

Bu hujjat Ko'prik dasturi (CrossOver o'rnini bosuvchi shaxsiy macOS dasturi) nimalardan yig'ilishini qayd etadi. Reja: [REJA.md](REJA.md). CrossOver ma'lumotnomasi: [../CROSSOVER.md](../CROSSOVER.md).

---

## 1. Whisky: namuna arxitektura

**Whisky-App/Whisky** (GPL-3.0): SwiftUI'da yozilgan Wine interfeysi. Egasi 2025-05-11 da arxivlagan; oxirgi reliz v2.3.5 (2025-04-05). Minimal talab: macOS Sonoma 14.0, Apple Silicon. Muallif (Isaac Marovitz) to'xtatish sababini shunday tushuntirgan: loyiha Wine hamjamiyatiga foyda keltirmadi, qiziqishi so'ndi; foydalanuvchilarga CrossOver'ni tavsiya qilgan.

### Repozitoriy tuzilishi

| Papka | Vazifasi |
|---|---|
| `Whisky/` | SwiftUI ilova: bottle yaratish, sozlama, dasturlar, pin'lar, winetricks, birinchi sozlash |
| `WhiskyKit/` | Swift package (`platforms: [.macOS(.v14)]`, bog'liqlik: SemanticVersion). Butun mantiq |
| `WhiskyCmd/` | Buyruq qatori interfeysi (`Main.swift`) |
| `WhiskyThumbnail/` | Quick Look kengaytmasi: `PEFile(url:)` va `bestIcon()` orqali `.exe` ikonkasi |
| `Libraries/` | `cabextract` |

`WhiskyKit` ichidagi asosiy fayllar: `Wine/Wine.swift`, `Whisky/Bottle.swift`, `Whisky/BottleSettings.swift`, `Whisky/BottleData.swift`, `Whisky/Program.swift`, `Whisky/ProgramSettings.swift`, `WhiskyWine/WhiskyWineInstaller.swift`, `PE/` (PE parseri: `PortableExecutable.swift`, `COFFFileHeader.swift`, `OptionalHeader.swift`, `Section.swift`, `RSRC/`), `ShellLink.swift` (`.lnk`), `Tar.swift`, `Rosetta2.swift`.

### Saqlash tuzilishi

| Narsa | Joyi |
|---|---|
| Konteyner ildizi | `~/Library/Containers/com.isaacmarovitz.Whisky` |
| Bottle'lar ro'yxati | `<konteyner>/BottleVM.plist` (`paths` massivi) |
| Bottle | `<konteyner>/Bottles/<bottle>/` |
| Bottle sozlamalari | `<bottle>/Metadata.plist` (XML plist) |
| Dastur sozlamalari | `<bottle>/Program Settings/<exe-nomi>.plist` |
| Wine dvigateli | `~/Library/Application Support/com.isaacmarovitz.Whisky/Libraries/` (`Wine/bin/wine64`, `wineserver`) |
| Dvigatel versiyasi | `Libraries/WhiskyWineVersion.plist` |

Bottle sozlamalari maydonlari: `name`, `pins`, `blocklist`, `wineVersion`, `windowsVersion` (sukut `win10`), `enhancedSync` (sukut `msync`), `avxEnabled`, `metalHud`, `metalTrace`, `dxrEnabled`, `dxvk` (sukut `false`), `dxvkAsync` (sukut `true`), `dxvkHud`. Ular ichki strukturalarga guruhlangan (`BottleInfo`, `BottleWineConfig`, `BottleMetalConfig`, `BottleDXVKConfig`); plist'dagi aniq kalit yo'llari `[tasdiqlanmagan]`.

Dastur sozlamalari: `locale`, `environment: [String: String]`, `arguments: String`. Kamchilik (koddagi izoh): fayl `.exe` nomi bo'yicha, shuning uchun bir xil nomli ikki dastur to'qnashadi. **Ko'prik'da dastur identifikatori to'liq yo'ldan olinadi.**

### Wine'ni ishga tushirishda beriladigan muhit

Manba: `WhiskyKit/Sources/WhiskyKit/Wine/Wine.swift` (`constructWineEnvironment`) va `BottleSettings.swift` (`environmentVariables(wineEnv:)`).

Doim:

| O'zgaruvchi | Qiymat |
|---|---|
| `WINEPREFIX` | bottle yo'li |
| `WINEDEBUG` | `fixme-all` |
| `GST_DEBUG` | `1` |

Sozlama yoqilganda:

| Sozlama | O'zgaruvchilar |
|---|---|
| DXVK | `WINEDLLOVERRIDES=dxgi,d3d9,d3d10core,d3d11=n,b` |
| DXVK HUD | `DXVK_HUD=full`, yoki `devinfo,fps,frametimes`, yoki `fps` |
| DXVK async | `DXVK_ASYNC=1` |
| ESync | `WINEESYNC=1` |
| MSync | `WINEMSYNC=1` **va** `WINEESYNC=1` (D3DMetal ESync belgisiga qaraydi) |
| Metal HUD | `MTL_HUD_ENABLED=1` |
| Metal trace | `METAL_CAPTURE_ENABLED=1` |
| AVX | `ROSETTA_ADVERTISE_AVX=1` |
| DXR | `D3DM_SUPPORT_DXR=1` |

Winetricks yoki Terminal buyrug'i uchun: `PATH` boshiga Wine `bin` papkasi, `WINE=wine64`.

### Dvigatelni yuklash

Whisky qattiq yozilgan URL'dan oladi: `https://data.getwhisky.app/Wine/Libraries.tar.gz`, versiya `https://data.getwhisky.app/Wine/WhiskyWineVersion.plist`. Arxiv `Tar.untar` bilan Application Support'ga ochiladi. Build x86_64, Rosetta 2 ostida ishlaydi.

### Winetricks integratsiyasi

`winetricks` skripti va `verbs.txt` (kategoriya, verb, tavsif) dvigatel papkasida. Buyruq Terminal'da AppleScript (`do script`) orqali ishga tushadi:

```
PATH="<wine bin>:<cabextract>:$PATH" WINE=wine64 WINEPREFIX="<bottle>" "<libraries>/winetricks" <verb>
```

Ko'prik'da Terminal ochilmaydi: jarayon ilova ichida ishga tushib, chiqishi log oynasiga oqadi.

### Entitlement'lar

Whisky: `com.apple.security.cs.allow-unsigned-executable-memory`, `apple-events`, `audio-input`, `camera`. **App Sandbox yoqilmagan**; shuning uchun ixtiyoriy Wine jarayonlarini ishga tushira oladi.

---

## 2. frankea/Whisky: faol fork

GPL-3.0, 1107 yulduz, oxirgi push 2026-11-16. Asl loyiha bilan bog'liq emas. Talab: Apple Silicon, macOS Sequoia 15.0+. Bundle id `com.franke.Whisky`. O'rnatish: `brew install --cask frankea/whisky/whisky`.

Qo'shilganlari: asl Whisky bottle'larini joyida o'qib ko'chirish, **GameDB** (80 dan ortiq o'yin uchun tayyor sozlamalar), kontroller qo'llovi, Steam/Epic/EA App/Rockstar/Battle.net uchun launcher profillari, DXMT sukut bo'yicha D3D11 backend'i, telemetriya ixtiyoriy va sukut bo'yicha o'chiq.

| Ilova relizi | Sana |
|---|---|
| app-v3.10.1 | 2026-11-15 |
| app-v3.10.0 | 2026-11-15 |
| app-v3.9.2 | 2026-11-13 |
| app-v3.8.0 | 2026-11-12 |
| app-v3.7.0 | 2026-08-30 |

### Dvigatel: frankea/winecx-gptk

| Reliz | Sana | Holat |
|---|---|---|
| v4.8.3 | 2026-11-15 | barqaror |
| v4.8.4-beta.1 | 2026-11-15 | beta |
| v4.6.4-beta.1 | 2026-08-29 | beta |

Reliz fayllari (teg `runtime-v4.8.3`): `Libraries.tar.gz`, `Libraries.tar.gz.sha256`, `WhiskyWineVersion.plist`.

v4.8.3 tarkibi:

- **Wine 11.19 + CrossOver 26.3 ning macOS yamoqlari** ("codeweavers' crossover 26.3 wine changes, rebased onto upstream wine 11.19"; manba daraxti `dappermint/winecx`, tarmoq `wine1119`). CrossOver 26.3 ning o'z Wine 11.0 asosiga nisbatan farqi 221 fayl.
- DXVK 1.10.3, DXMT 0.80, MoltenVK 1.4.2, SDL2 2.32.10 (kontrollerlar).
- D3DMetal ichida yo'q: foydalanuvchi Apple GPTK'ni Sozlamalar orqali import qiladi, keyin avtomatik joylanadi.
- macOS 27 va Game Porting Toolkit 4.0 beta 3 bilan sinalgan.
- Steam do'koni va qalqib chiquvchi oynalari GPTK'siz ham chiziladi.

Yig'ish usuli (README): Unix yarmi x86_64 uchun Rosetta ostida; PE yarmi **mingw-w64 GCC** bilan (llvm-mingw emas: u "Steam'ning CM login'ini to'xtatib qo'yadi"); freetype, gnutls, gstreamer va boshqalar belgilangan nixpkgs'dan; MoltenVK Khronos relizidan; dylib yo'llari `@loader_path` ga qayta yoziladi.

Muhim yamoqlar: D3DMetal ko'prigi (jarayonlararo Metal qatlamlari, "winemac: host cross-process metal layers over CAContext"), ntdll SEH tuzatishi, d3dkmt adapter identifikatori, GStreamer video-pool tuzatishi, video interposer'lar va MetalFX ko'priklari.

**Asosiy cheklov (README'dan):** "apple's game porting toolkit / d3dmetal payload only executes on crossover-derived wine builds, it patches their unixcall internals at load time". Ya'ni D3DMetal oddiy Wine'da ishlamaydi.

Minimal macOS bo'yicha ziddiyat: reliz eslatmasi "macOS 15", README "macOS 27 va 26, deployment floor 26.0" deydi `[tasdiqlanmagan]`. Bizning Mac (27.2.1) ikkalasiga ham mos.

Boshqa fork'lar (ochilmagan, holati `[tasdiqlanmagan]`): Crosswire, Uncorked, Bourbon, rum.

---

## 3. Boshqa Wine build'lari

### Gcenx/macOS_Wine_builds

`.tar.xz` paketlar, uch kanal: `wine-stable`, `wine@devel`, `wine@staging`.

| Teg | Sana | Fayllar |
|---|---|---|
| 11.21 | 2026-10-31 | `wine-devel-11.21-osx64.tar.xz`, `wine-staging-11.21-osx64.tar.xz` |
| 11.20 | 2026-10-29 | devel, staging |
| 11.18 | 2026-09-25 | devel, staging |
| 11.0_1 | 2026-04-16 | `wine-stable-11.0_1-osx64.tar.xz` |

URL andozasi: `https://github.com/Gcenx/macOS_Wine_builds/releases/download/<teg>/wine-<kanal>-<teg>-osx64.tar.xz`

- Stable 11.0_1: `wine-gecko-2.47.4`, `wine-mono-10.4.1` birga; `GStreamer.framework` alohida o'rnatilishi kerak; macOS Catalina va yuqori.
- Devel/staging 11.21: `wine-gecko-2.47.4`, `wine-mono-11.3.0`, GStreamer.framework 1.28.1 ichida.
- MoltenVK ichida bor-yo'qligi `[tasdiqlanmagan]`. DXMT va D3DMetal yo'q.
- Homebrew cask'lari orqada: `wine@devel` va `wine@staging` 11.16, `wine-stable` 11.0_1. Ilova bundle ichida binarlar `Contents/Resources/wine/bin/` da.
- Antivirus bu paketlarni xato belgilashi mumkin (PE binarlari MinGW-GCC bilan).
- `gcenx/wine/wine-crossover` cask'i hozir tap ro'yxatida yo'q `[tasdiqlanmagan]`.

### Upstream Wine

`wine-11.0` barqaror teg: 2026-01-13. Ishlab chiqish tarmog'i: `wine-11.22` (2026-11-13).

### CodeWeavers manbasi

- `https://media.codeweavers.com/pub/crossover/source/crossover-sources-26.3.0.tar.gz`: 149 054 023 bayt, 2026-07-21. `26.1.0` ham mavjud. Papka ro'yxati yopiq (403).
- Sahifa: `https://www.codeweavers.com/crossover/source`. CodeWeavers har loyiha uchun asl saytidan foydalanishni tavsiya qiladi.
- `Gcenx/winecx` va `CodeWeavers/winecx` repozitoriylari mavjud emas (404). Ochiq CrossOver asosli daraxt: `dappermint/winecx`.
- DXMT wiki bo'yicha CodeWeavers manbasidan yig'ilgan "FOSS CrossOver Wine 24+" DXMT uchun asos bo'la oladi.

### Qaysi asos qaysi maqsadga

| Maqsad | Asos |
|---|---|
| Direct3D 11 o'yinlar, ish dasturlari | Oddiy Wine (Gcenx 11.21) + DXMT yoki DXVK yetarli |
| Direct3D 12, D3DMetal | Faqat CrossOver asosli build: frankea `Libraries.tar.gz` yoki o'zimiz yig'gan |

---

## 4. Grafik qatlamlar

### Apple Game Porting Toolkit (D3DMetal)

- Apple sahifasi: `https://developer.apple.com/games/game-porting-toolkit/`, "Download Game Porting Toolkit 4" tugmasi. Yuklab olish uchun Apple akkaunti kerak.
- `apple/game-porting-toolkit` GitHub repozitoriysi D3DMetal emas, agent ko'nikmalari plagini (Apache-2.0; macOS 27 va Xcode 27 talab qiladi).
- Gcenx paketi: `game-porting-toolkit-<versiya>.tar.xz`, oxirgisi 3.0-3 (2026-03-03); avvalgilari 3.0 (2025-12-05), 2.1 (2025-03-12). Cask `game-porting-toolkit` 3.0-3; Gcenx Wine cask'lari bilan to'qnashadi.
- **O'rnatish:** GPTK redist ichidagi `lib` papkasidan `external` va `wine` qismlarini Wine kutubxona papkasiga nusxalash. Bir qo'llanmada `x86_64-unix` ichida `nvngx-on-metalfx.so` ni `nvngx.so` ga qayta nomlash aytilgan (DLSS uchun). Aniq fayllar ro'yxati `[tasdiqlanmagan]`: DMG ichidagi Read Me bo'yicha bajariladi.
- Kalitlar: `D3DM_SUPPORT_DXR=1` (Whisky kodida); `D3DM_MTL4=0` GPTK 4 da Metal 3 backend'iga qaytaradi `[tasdiqlanmagan, forum]`.
- **Litsenziya:** matni olinmadi. Gcenx: "Apple'ning License.pdf shartlariga rioya qiling". Sikarugir D3DMetal'ni tijoriy portlarda ishlatib bo'lmasligini yozadi. Apple forumida CrossOver va Whisky tarqatishi ruxsat etilganmi degan savolga javob topilmadi. **Xulosa: D3DMetal ilovaga qo'shilmaydi, foydalanuvchi o'zi yuklab import qiladi.**

### DXMT (3Shain/dxmt)

- v0.80, 2026-04-23. Fayl: `dxmt-v0.80-builtin.tar.gz` (18.7 MB). Avvalgilari: v0.74 (2026-03-10), v0.73 (2026-01-21). v0.81 va v1.0 rejada.
- Qamrovi: Direct3D 11 va 10. D3D12 yo'q.
- Litsenziya: v0.80 MIT ostidagi oxirgi reliz, keyingilari LGPL.
- Wine talabi: manba kamida Wine 8; `winemac.drv` belgilari eksport qilingan bo'lishi kerak (`include/winemacdrv.h`).
- **O'rnatish:**
  - `winemetal.so` → `<wine>/lib/wine/x86_64-unix/`
  - `winemetal.dll` → `<wine>/lib/wine/x86_64-windows/` va `<prefix>/drive_c/windows/system32/`
  - `d3d11.dll`, `dxgi.dll`, ixtiyoriy `d3d10core.dll`: builtin build'da Wine papkasiga, aks holda prefiks `system32` ga
  - `WINEDLLOVERRIDES="dxgi,d3d11,d3d10core=n,b"` (wiki: `native,builtin` qo'ymang)
- DLSS va MetalFX yo'llari mavjud (reliz eslatmalarida NVEXT, MTLFX temporal scaler tuzatishlari). Konfiguratsiya kalitlari `[tasdiqlanmagan]`: wiki'ning "Vendor Extensions" sahifasi o'qilishi kerak.

### DXVK

- macOS uchun: `Gcenx/DXVK-macOS`, `v1.10.3-20230507-repack` (2024-07-23). Fayllar: `dxvk-macOS-async-v1.10.3-20230507-repack.tar.gz` va `...-builtin.tar.gz`. Zlib.
- O'rnatish: `x64/*.dll` → `drive_c/windows/system32`, `x32/*.dll` → `syswow64`; `d3d11` va `d3d10core` uchun override. O'chirish: DLL va override'larni olib tashlab `wineboot -u`.
- Upstream `doitsujin/dxvk` v3.1.1 (2026-09-15). MoltenVK 1.4.2 ustida ishlashi `[tasdiqlanmagan]`.

### MoltenVK

v1.4.2 (2026-07-24), "Vulkan 1.4 ning qatlamli realizatsiyasi", Apache-2.0. Fayllar: `MoltenVK-macos.tar`, `MoltenVK-all.tar`.

### vkd3d-proton

v3.1 (2026-10-28), LGPL-2.1. macOS'da MoltenVK orqali ishlashi `[tasdiqlanmagan]`; frankea D3D12 ni D3DMetal orqali yo'naltiradi.

### wined3d

Wine'ning o'z realizatsiyasi; DXVK yoki DXMT DLL'lari bo'lmasa sukut. macOS'da OpenGL cheklovi ta'sir qiladi.

---

## 5. Bog'liqliklar va tuzatish bazalari

| Vosita | Versiya | Litsenziya | Foydasi |
|---|---|---|---|
| winetricks | 20260125 | LGPL-2.1 | `corefonts`, `vcrun2019`, `vcrun2022`, `dotnet35`, `dotnet48`, `d3dcompiler_43`, `d3dcompiler_47`, `d3dx9`, `xact` va boshqa verblar. Har verb skriptda `w_metadata <nom> <kategoriya>` qatori. `brew install winetricks` yoki skriptni o'zi |
| umu-protonfixes | faol | BSD-2-Clause | Har do'kon uchun papka (`gamefixes-steam`, `-gog`, `-egs`, `-amazon`, `-battlenet`, `-ea`). Har o'yin uchun Python fayl (`gamefixes-steam/10220.py`, ichida `util.protontricks(...)`). Proton'dan tashqarida adapter kerak |
| umu-database | | GPL-3.0 | CSV: `TITLE,STORE,CODENAME,UMU_ID,...`. Do'kon identifikatorlarini bog'lash uchun |
| Lutris | v0.5.22 | GPL-3.0 | Ochiq API: `GET https://lutris.net/api/games?search=<q>`, `GET https://lutris.net/api/installers?search=<q>&page_size=<n>`; 15 622 o'rnatuvchi. O'rnatuvchilar litsenziyasi noaniq |
| Heroic | v2.22.4 | GPL-3.0 | macOS'da Wine-Staging + DXMT ni tavsiya qiladi. Wiki'dagi "Steam for Windows on macOS" qo'llanmasi 2026-04-19 dan ishlamaydi deb belgilangan |
| Mythic | | GPL-3.0 | GPTK asosidagi o'z dvigateli (`MythicApp/Engine`); macOS 14+ |
| Sikarugir | faol | Configure.app LGPL-2.1 | Wineskin uslubidagi `.app` o'rovchi; macOS 14.6+ |
| Bottles | 67.6 | GPL-3.0 | `bottlesdevs/components` YAML manifestlari (Linux uchun) |

---

## 6. Moslik ma'lumotlari manbalari

| Manba | So'rov | Kalit | Izoh |
|---|---|---|---|
| ProtonDB | `https://www.protondb.com/api/v1/reports/summaries/<appid>.json` | yo'q | Norasmiy. Javob: `tier`, `bestReportedTier`, `confidence`, `score`, `total`, `trendingTier` |
| AreWeAntiCheatYet | `https://raw.githubusercontent.com/AreWeAntiCheatYet/AreWeAntiCheatYet/master/games.json` | yo'q | MIT, ~470 KB. Maydonlar: `name`, `native`, `status`, `anticheats`, `notes`, `updates`, `reference` |
| Steam do'koni | `https://store.steampowered.com/api/appdetails?appids=<id>` | yo'q | Nom, turi, `header_image`. Chegaralari hujjatlanmagan |
| Lutris | yuqorida | yo'q | |
| SteamGridDB | `https://www.steamgriddb.com/api/v2` | kerak (Bearer) | Artwork |
| IGDB | Twitch OAuth | kerak | |
| PCGamingWiki | `https://www.pcgamingwiki.com/w/api.php` | yo'q | Ixtiyoriy Cargo so'rovlari taqiqlangan |
| AppleGamingWiki | | | API Cloudflare ortida, tekshirib bo'lmadi |

Foydalanish shartlari va chegaralar hech biri uchun tekshirilmagan; shaxsiy foydalanishda so'rovlar kam va keshlangan bo'ladi.

---

## 7. Do'konlar bilan Windows launcherlarsiz ishlash

| Do'kon | Vosita | Versiya | Litsenziya |
|---|---|---|---|
| Epic Games Store | `derrod/legendary` | 0.21.1 (2026-09-08) | GPL-3.0 |
| GOG | `Heroic-Games-Launcher/heroic-gogdl` | v1.4.0 (2026-10-28) | GPL-3.0 |
| Amazon Games | `nile` | joyi topilmadi | `[tasdiqlanmagan]` |

Steam uchun Windows klienti Wine ichida ishlatiladi. Ma'lum muammolar:

- `steamwebhelper` (CEF) tarixiy og'riqli joy (WineHQ 49839-xato).
- CrossOver forumida Steam 2026-10-31 atrofida buzilgani va tuzatish keyingi Preview'da va'da qilingani aytilgan `[ikkilamchi]`.
- `-no-cef-sandbox`, `-cef-disable-gpu` bayroqlari tasdiqlanmadi.
- frankea 4.8.3: do'kon va qalqib chiquvchi oynalar GPTK'siz ham chiziladi. **1-bosqichda o'zimiz tekshiramiz.**

Battle.net, EA app, Ubisoft Connect: xabarlar aralash, 2026 uchun ishonchli holat yo'q; frankea'da ular uchun launcher profillari bor.

---

## 8. Apple Silicon'da x86 kodning kelajagi

- **Apple (support.apple.com/en-us/102527, 2026-09-21):** "Rosetta is available for any Mac with Apple silicon using macOS 27 or earlier." macOS 28 dan faqat ayrim eski, qo'llab-quvvatlanmayotgan o'yinlar uchun.
- frankea README: dvigatel x86_64, Rosetta orqali ishlaydi; "d3dmetal ships x86_64 only", shuning uchun D3D12 ishi, video interposer'lar va MetalFX ko'priklari Apple ularni arm64 uchun yig'masa arm64'ga o'ta olmaydi.
- Mahalliy arm64 Wine macOS'da manzil maydonining past 4 GB qismini talab qiladi; arm64 uni `__PAGEZERO` sifatida band qiladi. Yagona yo'l `com.apple.developer.cross-architecture-support` entitlement'i (Apple ixtiyori bilan). CrossOver arm64 build'ida bor; o'zi imzolangan binar shu satr bilan ishga tushirilmaydi.
- FEX (`FEX-Emu/FEX`, MIT, `FEX-2611.1`), box64 (v0.4.4), Hangover (`hangover-11.16`, faqat arm64 Linux). frankea: "o'z FEX build'imiz arm64 Mac'da 64-bit va 32-bit x86 Windows kodini bajaradi".

**Xulosa:** macOS 27 da hammasi ishlaydi. macOS 28 ga o'tish arm64 dvigatel masalasi hal bo'lguncha kechiktiriladi.

---

## 9. Ilovani yig'ish va yangilash

- **Sparkle** 2.10.1 (2026-10-25). `Info.plist`: `SUFeedURL`, `SUPublicEDKey`. `generate_keys` (maxfiy kalit Keychain'da), `generate_appcast <papka>` yoki `sign_update <dmg>`. Har relizda `CFBundleVersion` oshiriladi.
- **Sandbox:** yoqilmaydi (Whisky ham shunday).
- **Hardened runtime entitlement'lari** (faqat notarizatsiya qilinsa kerak bo'ladi): `com.apple.security.cs.allow-jit`, `allow-unsigned-executable-memory`, `disable-library-validation`, `allow-dyld-environment-variables`. Aniq zarur to'plam `[tasdiqlanmagan]`.
- **Karantin:** yuklab olingan fayllarda `com.apple.quarantine` atributi; `xattr -dr com.apple.quarantine <yo'l>` bilan olib tashlanadi `[tasdiqlanmagan]`. Ilova o'zi `URLSession` bilan yuklagan arxivlarda bu odatda qo'yilmaydi.
- **Imzo:** shaxsiy Mac uchun mahalliy imzo yetarli. Boshqa Mac'ga tarqatish uchun Developer ID va notarizatsiya.
- **Muhit:** macOS 27.2.1, Xcode 27.2 (27B52), Swift 6.4.2.
