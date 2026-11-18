# Sinov jurnali

Har bosqichning qabul sinovlari natijasi shu yerga yoziladi: nima ishladi, nima ishlamadi, nima hali sinalmagan.

Sinov kompyuteri: MacBook Pro, Apple M2 Pro, 16 GB, macOS 27.2.1, Rosetta 2 o'rnatilgan.

## 1-bosqich. Yadro (`KoprikKit` + `koprik` CLI)

### 2026-11-17: kod va avtomatik testlar

| Tekshiruv | Natija |
|---|---|
| `swift build` | o'tdi |
| `swift test`: 72 test, 18 to'plam | hammasi o'tdi |

Avtomatik testlar qamraydi: muhit quruvchi, sozlamalar qatlamlari, dvigatel o'rnatish, yuklab olish, bottle yaratish/nusxalash/snapshot/tiklash, Wine jarayoni va log, VDF/ACF o'qish, `.lnk` o'qish, Windows yo'llari, PE fayl (haqiqiy `notepad.exe` dan import jadvali va ikonka), log tahlilchisi, `.app` launcher, retseptlar, dasturlar do'koni, grafika backendini almashtirish (fayllar to'g'ri almashadi va Wine'ning o'z nusxalari qaytadi).

### 2026-11-17: go/no-go sinovlari haqiqiy dvigatel bilan

Dvigatel: `frankea/winecx-gptk` `runtime-v4.8.3` (Wine 11.19, DXMT 0.80, DXVK 1.10.3, MoltenVK 1.4.2). Yuklab olish 479 MB, sha256 mos keldi, diskda 1.3 GB.

| # | Sinov | Natija |
|---|---|---|
| 1 | `koprik bottle create test && koprik run test notepad` oyna ochadi | **o'tdi.** "Untitled - Notepad" oynasi chiqdi |
| 2 | 7-Zip o'rnatuvchisi `/S` bilan o'rnatiladi | **o'tdi.** 7.8 soniya, `C:\Program Files\7-Zip` to'ldi, Start Menu yorliqlari paydo bo'ldi, kutubxona ularni o'zi topdi |
| 3 | Steam o'rnatiladi va do'kon sahifasi chiziladi | **o'tdi, DXVK bilan.** Batafsil quyida |
| 4 | DX11 o'yin DXMT bilan; DX12 o'yin D3DMetal bilan | **DX11 o'tdi** (Brawlhalla, DXMT). DX12: GPTK import qilinmagan, sinalmadi |
| 5 | Backend almashtirish mexanizmi | **aniqlandi.** Quyida |

### 5-sinov: backend qanday almashadi

Dvigatel ichini ko'rib va frankea/Whisky manbasini o'qib aniqlandi:

- DXMT va DXVK oddiy Windows DLL'lari (`Libraries/DXMT/x64`, `Libraries/DXVK/x64`). Ular bottle'ning `system32`/`syswow64` papkasiga nusxalanadi va `WINEDLLOVERRIDES` bilan tanlanadi (`dxgi,d3d10core,d3d11=n,b`, DXMT uchun yana `winemetal=b`).
- D3DMetal dvigatelning o'ziga o'rnatiladi: GPTK'dagi DLL'lar Wine'ning `x86_64-windows` dagi Direct3D DLL'lari o'rniga, `x86_64-unix/{d3d10,d3d11,d3d12,dxgi}.so` esa `../../external/libd3dshared.dylib` ga simvolik havola (nusxa emas). Dvigatel ichidagi `lib/external/README` shuni yozadi.
- wined3d: Wine'ning o'z DLL'lari va `WINED3DMETAL=0`.
- DXMT va DXVK bir xil fayl nomlarini ishlatgani uchun bir bottle'da bir paytda bittasi turadi. `Graphics.prepare` ishga tushirishdan oldin fayllarni almashtiradi (faqat mazmuni farq qilsa yozadi).

### 3-sinov: Steam

| Backend | Natija |
|---|---|
| DXMT | Steam ishga tushadi, lekin `steamwebhelper` (Chromium) GPU jarayoni 2 daqiqa osiladi, keyin oyna **qop-qora**. Log: `CreateSwapChain: cross-process swapchain not supported yet` (DXMT boshqa jarayon oynasiga chiza olmaydi) |
| DXMT + `-cef-disable-gpu` | oyna 12 s da chiqadi, lekin baribir qora |
| wined3d | 6 s da chiqadi, qora. Chromium log: `link failed but did not provide an info log` (sheyder bog'lanmadi) |
| **DXVK** | **15 s da chiqadi, to'liq chiziladi**: kirish oynasi, QR kod, keyin do'kon va kutubxona |
| DXMT tizimda + DXVK faqat `steamwebhelper` yonida | oyna umuman chiqmadi (2 daqiqa) |

Xulosa va kodga kiritilgan o'zgarish: do'kon launcherlari (Steam, Epic, GOG Galaxy, Battle.net, EA, Ubisoft, Rockstar) "Auto" rejimida **DXVK** bilan ochiladi. Interfeysda sababi yoziladi.

Steam uchun qo'shilgan muhit: `STEAM_DISABLE_CEF_SANDBOX=1`, `CEF_DISABLE_SANDBOX=1`, `STEAM_RUNTIME=0`, `MTL_DEBUG_LAYER=0`, `GST_DEBUG=1` (frankea/Whisky bilan bir xil).

Foydalanuvchi o'z akkauntiga o'zi kirdi (parol Ko'prik orqali kiritilmaydi). Do'kon sahifasi, rasmlar, savat, yuklab olish paneli to'g'ri chizildi.

### Topilgan buglar

| # | Bug | Holat |
|---|---|---|
| B1 | Steam DXMT va wined3d'da qora oyna | DXVK sukut qilib tuzatildi |
| B2 | `steam.exe -shutdown` dan keyin bitta `steamwebhelper.exe` Wine loader qulfida osilib qoladi (`RtlpWaitForCriticalSection ... loader.c: loader_section wait timed out`), yangi Steam ishga tushmaydi | Launcher endi Steam'ni qayta ishga tushirishda shu jarayon qolsa butun bottle'ni (`wineserver -k`) to'xtatadi |
| B3 | Bepul o'yin uchun `appmanifest_*.acf` yozish yuklab olishni boshlamaydi: avval akkauntga litsenziya qo'shilishi kerak | `steam://install/<appid>` ishlatiladi |
| B4 | Bottle yaratish 95 soniya (`wineboot`) | Dvigatel+Windows versiyasi bo'yicha tayyor prefiks shabloni saqlanadi, keyingi bottle APFS klon bilan **0.42 s** da yaratiladi |
| B5 | `gldriverquery.exe` `SDL2.dll` topa olmaydi | zararsiz: Steam'ning OpenGL tekshiruvi, Steam ishlashiga ta'sir qilmaydi |

| B6 | Steam orqali (`-applaunch`) ochilgan o'yin ishlab turgan Steam'ning muhiti va DLL'larini oladi, o'yin uchun tanlangan sozlamalar ishlamaydi | Steam o'yinlari endi o'yin `.exe` sidan `SteamAppId` bilan to'g'ridan-to'g'ri ochiladi |
| B7 | `koprik run --detach` bilan ochilgan Wine terminal jarayon guruhida qoladi: terminal yopilsa Steam va o'yin ham o'ladi | Wine `posix_spawn` + `POSIX_SPAWN_SETSID` bilan alohida sessiyada ochiladi |
| B8 | Steam overlay (ikkinchi Chromium) GPU jarayoni Wine'da yo'q `D3DKMTSetProcessSchedulingPriorityClass` ni chaqirib yiqiladi, keyin Steam "Stalled cross-thread pipe" bilan o'zini yopadi, keyingi o'yin `c0000409` bilan yiqiladi | Ko'prik Steam'ni ochishdan oldin `localconfig.vdf` da overlay'ni o'chiradi. Shundan keyin 6 marta ketma-ket ochish/yopish muammosiz |
| B9 | O'lgan server ortidan qolgan "yetim" Wine jarayonlari (`steam.exe` 123% CPU), `wineserver -k` ularni ko'rmaydi | `stopAll` ishchi papkasi bottle ichida bo'lgan jarayonlarni ham o'ldiradi (`lsof -d cwd`) |
| B10 | Bottle ishlayaptimi degan tekshiruv server soket faylining borligiga qaragan. Fayl o'lgan serverdan keyin ham qoladi, natijada Steam DXMT bilan ochilib qora oynada qotgan va akkauntga kirmagan | Soketga haqiqatan ulanib tekshiriladi |
| B11 | Yordamchi buyruqlar (`taskkill`, winetricks) MSync'siz ishga tushgan: `Server is running with WINEMSYNC but this process is not` | Yordamchilar bottle'ning sinxronizatsiya rejimini oladi |
| B12 | Unix yo'li bilan ochilgan `steam.exe` `ps` da `/Users/...` bo'lib ko'rinadi va tanilmagan, Steam 6 marta ochib yuborilgan | Steam Windows yo'li bilan ochiladi, `ps` tahlili Unix yo'lli `.exe` larni ham taniydi |
| B13 | Foundation `Process.waitUntilExit()` uzoq ishlaydigan CLI ichida qaytmay qolgan | `ProcessRunner` ham `posix_spawn` + `waitpid` ga o'tkazildi |
| B14 | Brawlhalla'ning `.exe` si 185 KB (Adobe AIR), 512 KB chegarasi uni o'tkazib yuborgan | O'yin papkasi nomiga mos `.exe` birinchi tanlanadi |
| B15 | `release.sh` qoldirgan Release nusxasi `koprik://` havolalarini o'ziga olgan | Skript oraliq nusxani ro'yxatdan chiqarib o'chiradi |

### 4-sinov: Brawlhalla (Steam, bepul, Adobe AIR, Direct3D 11)

O'rnatish: `steam://install/291550`, 1.53 GB, ~15 Mbit/s da 15 daqiqa. O'yin akkauntga kirdi, menyu, kunlik bonus, "Training Ground" to'g'ri chizildi. Anti-cheat ro'yxatida EAC "Supported", ProtonDB "Gold" (653 hisobot); ilova ikkalasini ham ko'rsatadi.

Yakuniy tartib (bitta buyruq yoki bitta Play tugmasi): Steam yopiq bo'lsa fonda (`-silent`, DXVK) ochiladi, akkauntga kirishi kutiladi, o'yin o'z papkasidagi DXMT DLL'lari bilan ochiladi. Steam'ning `system32` dagi DXVK'siga tegilmaydi.

| Holat | O'yin oynasi chiqishi |
|---|---|
| Steam yopiq, sovuq holat | 27 s (Steam ochilishi va kirishi bilan) |
| Steam ochiq | 11 s |
| O'yinni yopish (`koprik stop`) | 4.7-8 s, Steam ishlashda qoladi |

Backendlar solishtiruvi, bir xil menyu, Metal HUD (oyna fonda bo'lgani uchun o'yin FPS'ni 5-11 ga cheklagan, shuning uchun asosiy ko'rsatkich GPU vaqti va xotira):

| Backend | GPU xotira (Metal) | Ilova xotirasi | GPU vaqti/kadr | CPU |
|---|---|---|---|---|
| **DXMT** (sukut) | **77.9 MB** | **2.47 GB** | 0.57 ms | 40-120% |
| DXVK | 463.0 MB | 2.87 GB | 0.83 ms | 56-191% |
| wined3d | 164.2 MB | 2.55 GB | 0.45 ms, lekin FPS ikki baravar past | 123% |

Xulosa: DXMT GPU xotirasini DXVK'dan 6 baravar kam ishlatadi va GPU vaqti 31% kam, shuning uchun o'yinlar uchun sukut to'g'ri.

Hal qilinmagan:

- **Game Mode o'chiq** (HUD: "Game Mode Off", "Composited"). macOS Game Mode'ni faqat `LSSupportsGameMode` li `.app` bundle'ga beradi; bu dvigatelda Wine bundle'siz ishlaydi. Symlink orqali bundle sinab ko'rildi, ishlamadi (Wine o'zining haqiqiy yo'lidan qayta ishga tushadi). Yechim: Wine'ni bundle ichida yig'ish (9-bosqich).
- **Haqiqiy FPS** o'lchanmadi: o'yinni oldingi planga chiqarish foydalanuvchining ochiq oynasini almashtirib yuborardi.
- DX12 / D3DMetal: Game Porting Toolkit import qilinmagan.

### 2026-11-17 kech: FPS, kechikish, istalgan .exe

**FPS va klaviatura kechikishi (Brawlhalla, 4 kishilik jang, oyna oldinda):**

| Holat | FPS | Metal HUD |
|---|---|---|
| Boshlang'ich (foydalanuvchi o'lchagan) | 30-55 | Composited, Game Mode Off |
| `CaptureDisplaysForFullscreen=Y` (eksklyuziv to'liq ekran) | 89-111 | **Direct**, Game Mode Off |
| + Wine "Koprik Game.app" bundle ichidan | 88-110, menyuda 115 | **Direct, Game Mode On** |

- "Direct": kadr kompozitorsiz to'g'ridan-to'g'ri ekranga chiqadi. Bir kadrlik (8-16 ms) kechikish yo'qoladi.
- Game Mode: macOS faqat Launch Services'da `LSSupportsGameMode` li bundle sifatida tanilgan jarayonga beradi. Topilgan yo'llar: yuklovchiga joylangan plist ishlamadi (`bundleID=NULL`), symlink ham ishlamadi (Wine haqiqiy yo'lga qaytadi), hard link ham ishlamadi (`ntdll.so` topilmaydi). Ishlagan usul: `Contents/MacOS` = `x86_64-unix` ning APFS kloni, `x86_64-unix -> .` symlinki, Windows DLL papkalariga symlinklar, bundle ildizida `lib` elementlariga symlinklar. Bola jarayonlar (o'yin) ham shu yerdan ochiladi, chunki ntdll `wineloader` ni o'z papkasidan oladi.
- GPU har kadrga 0.35-0.42 ms sarflaydi, demak 110 FPS chegarasi Adobe AIR'ning Rosetta ostidagi asosiy oqimi (protsessor). 120 Hz ekranda o'yin 9.1 ms kadr oralig'ida barqaror turadi.

**Istalgan .exe (Chrome kengaytmasi ulanmagani uchun installerlar rasmiy manzillardan yuklandi):**

| Dastur | Natija |
|---|---|
| Notion (electron-builder NSIS, 119 MB) | Avval "Notion is running" bilan to'xtagan. Sabab: Wine'ning `powershell.exe` stub'i har doim 0 qaytaradi, installer esa PowerShell'dan "ilova ishlayaptimi" deb so'raydi. Stub sukut bo'yicha o'chirildi. Jim o'rnatish 10.6 s, kutubxonada avtomatik paydo bo'ldi. DXMT'da oyna bo'sh, DXVK'da to'g'ri; Chromium/Electron ilovalari endi avtomatik DXVK oladi |
| Zoom Workplace (182 MB) | `/silent` bilan 17 s da o'rnatildi, 9 s da ochildi, DXMT'da to'g'ri chizildi |

Topilgan qo'shimcha buglar: B16 Wine `find.exe` hech qachon moslik topmaydi (bu installerlar uchun muhim emas edi); B17 XcodeGen `entitlements` faylini `properties` berilmasa bo'sh qilib qayta yozadi, natijada Quick Look kengaytmasi sandbox'siz qolib yuklanmagan; B18 `codesign --deep` kengaytma entitlement'larini o'chiradi.

**Quick Look:** kengaytma ro'yxatdan o'tdi, `qlmanage -t` `.exe` uchun ikonka chizadi.

### 2026-11-17 kechqurun: DX12, havolalar, izolyatsiya

**DX12 / D3DMetal.** Foydalanuvchi Apple'dan "Evaluation environment for Windows games 4.0 beta 3" (26.6 MB) ni yukladi; `koprik engine import-gptk` 4 s da import qildi (Apple imzosi tekshirildi), "Koprik Game.app" qayta qurildi. Kichik bepul DX12 o'yin topilmagani uchun `scripts/dx12-test/dx12test.cpp` (mingw-w64 bilan yig'ilgan, qurilma + swapchain + har kadr tozalash) ishlatildi:

| Natija | |
|---|---|
| Adapter | "AMD Compatibility Mode" (D3DMetal), 12 GB |
| Maksimal daraja | Direct3D 12_2 |
| FPS (15 s) | o'rtacha 120.0, min 119.9, max 120.1 (120 Hz ekran) |
| Auto backend | D3DMetal ("The program uses Direct3D 12") |

**Havolalar (Notion login).** Wine'ning `start notion://...` buyrug'i HKCU'da ro'yxatdan o'tgan protokollarni topmaydi ("no application associated", B19). Ko'prik endi protokollarni registrdan o'qiydi, har bottle uchun `~/Applications/Koprik/Links/<bottle> Links.app` (AppleScript applet) yaratadi va ishlovchi buyruqni o'zi ishga tushiradi. Mac'da `open "notion://www.notion.so/koprik-link-test"` 13 s da `Notion.exe notion://www.notion.so/koprik-link-test` ni ochdi. Haqiqiy login foydalanuvchi akkaunti bilan sinalmagan.

**Izolyatsiya.** Oddiy bottle'da `cmd /c echo ... > Z:\Users\<u>\Desktop\...` Mac ish stoliga **yozdi** (xavf isbotlandi). Izolyatsiyalangan bottle (`sandbox-exec` + Seatbelt profili):

| Hujum | Natija |
|---|---|
| Ish stoliga yozish (Z: olib tashlangan) | yo'q |
| Ish stoliga yozish (Z: ataylab qaytarilgan) | **Access denied** |
| `Documents` dagi faylni o'qish | **Access denied** |
| Notepad, o'rnatuvchilar | ishlaydi |
| `Downloads` dan ochilgan `.exe` | bottle ichiga nusxalanib, "Sandbox" bottle'da ishladi |

Topilgan: B20 Seatbelt `/var` emas `/private/var` ni solishtiradi (profil yo'llari `realpath` dan o'tkaziladi); B21 sandbox'da yo'llar uchun metama'lumot o'qish ruxsati kerak, aks holda `could not load ntdll.so`; B22 `install.sh` ishlab turgan ilovani yopolmagan, eski kod havolalarga javob bergan.

**Notion: xira matn va sichqoncha/klaviatura kechikishi (2026-11-17).** Matn xira edi: Wine 1x chizar, macOS uni Retina ekranga 2x cho'zardi. Bottle'lar endi sukut bo'yicha `RetinaMode=Y`, `LogPixels=192` va shrift silliqlash bilan ishlaydi (`BottleConfig.highResolution`, bottle ishga tushganda qo'llanadi).

Kechikish ScreenCaptureKit o'lchagichi bilan o'lchandi: sichqoncha yon paneldagi qator ustiga olib borilgan paytdan hover rangi ekranda paydo bo'lguncha (12 urinish; 1 s dan oshganlari "qayd etilmagan" deb hisoblangan). Bottle nusxasida, foydalanuvchi ma'lumoti o'zgartirilmagan:

| Sozlama | Qayd etilgan | Median |
|---|---|---|
| DXVK, 1x | 5/12 va 8/12 (qolganlari 0.6-1 s+) | 32-41 ms |
| DXVK, Retina | 1/10 - 5/10 | o'lchab bo'lmaydi |
| `--disable-gpu` (dasturiy chizish) | 3/10 | 546+ ms |
| DXVK `maxFrameLatency=1` | 10/12 | 49 ms |
| `--in-process-gpu` | **12/12** | **38 ms** (20-61) |
| `--in-process-gpu` + Retina | **12/12** | **38 ms** (26-56) |

**Need for Speed: Most Wanted (2012), repack, izolyatsiyalangan bottle (2026-11-18).** Litsenziyasiz repack, shuning uchun avval tekshirildi: ClamAV (3.6 mln imzo) va o'z YARA qoidalarimiz (mayner, stealer, RAT, avtoyuklash) bilan o'rnatuvchi, uning ichidagi 29 fayl (`innoextract`) va o'rnatilgan 2791 fayl. Bitta fayl topildi: `EA.Game.RegFix.exe` (UPX + AutoIt, ClamAV `Win.Dropper.DarkKomet-9986221-0`). U o'rnatish paytida ishga tushmagan (EA registr kalitlarini Inno Setup o'zi yozgan), karantinga olindi. O'rnatish internetsiz (`--isolation full`) bajarildi: o'yin papkasidan tashqarida faqat ikkita yorliq yozildi, Run/RunOnce/xizmat/vazifa kalitlari yo'q, Wine jarayonlari uchun sandbox to'sig'i qayd etilmadi.

| O'lchov (1512x982, DXMT, Direct, Game Mode) | Natija |
|---|---|
| Menyu va videolar | 60.0 FPS (o'yinning o'z chegarasi), GPU 0.7 ms |
| Ochiq shahar, yuqori sozlamalar | 44.5-45.6 FPS, GPU 10.4 ms, asosiy oqim 97% (CPU, Rosetta) |
| Ochiq shahar, SSAO/motion blur/aks ettirish/LOD/VFX past, soya 1 | 56.1-56.6 FPS, GPU 7.5 ms |
| D3DMetal | ishlamaydi: o'yin 32-bit ("DirectX 10 or better graphics card is required") |
| DXVK | Vulkan istisnosi bilan yopiladi (32-bit, wow64) |

120 FPS bu o'yinda erishib bo'lmaydi: o'yin 60 da qulflangan (`VsyncInterval=0` ham o'zgartirmaydi), qulfni ochuvchi plagin faqat asl v1.5 `NFS13.exe` (13 684 056 bayt) bilan ishlaydi, repack'dagisi 14 544 896 bayt; ustiga ochiq shaharda protsessor ~56 FPS bilan chegaralaydi.

Topilgan va tuzatilgan: B25 Unicode bo'lmagan dasturlar matni buzilgan ("Ïðîâåðêà"): dastur/bottle uchun `language` (LANG/LC_ALL, ANSI kod sahifasi). B26 izolyatsiyalangan bottle tashqaridagi o'rnatuvchining faqat o'zini ko'chirardi, yonidagi arxivlarsiz repack ishlamasdi: endi dasturning o'z papkasi butunlay (APFS klon) ko'chiriladi. B27 D3DMetal 32-bit dasturlarni ishlata olmaydi: Auto ham, qo'lda tanlash ham 32-bitda DXMT'ga o'tadi. B28 Retina yoqiq bottle'da o'yin to'liq ekran uchun 3024x1964 ni tanladi, Wine ekrandan ikki baravar katta oyna ochdi va klaviatura o'yinga yetmadi: Retina endi "Automatic" (dasturlarda yoqiq, Direct3D/OpenGL o'yinlarida o'chiq). Sinov vositasi eslatmasi: DirectInput o'yinlari System Events tugmalarini emas, faqat HID darajasidagi `CGEvent` larni qabul qiladi.

**NFS: boshqaruv va saqlash (2026-11-18).** Foydalanuvchi WASD/Space ishlamayotganini aytdi. Tekshiruv: o'yin sarlavhasida `WINEDEBUG=+key` bilan W A S D Space Up yuborildi. HUD'siz hammasi Wine'ga yetdi, `--metal-hud` bilan D yutildi va undan keyingi tugmalar ham yetmadi. B32: Apple Metal HUD ilovaga Fn modifikatorli menyu qisqa tugmalarini qo'shadi (jurnalda "NSEventModifierFlagFunction specified to -setKeyEquivalentModifierMask"), macOS Fn'ni tashlab yuboradi va oddiy D HUD sozlamalar panelini ochib, klaviaturani o'yindan oladi. Ilovada HUD tugmasi va sozlamasi endi buni ogohlantiradi; o'ynash uchun HUD o'chiq bo'lishi kerak. 32-bitli DirectInput sinovi (`scripts/input-test/dinputtest.c`) ham shuni ko'rsatdi (`DIK` kodlari keladi, D'dan keyin fokus `#32769` ga o'tadi). Saqlash: `Documents/Criterion Games/.../Save/0/MUD.29.NFS13Save` yoziladi (sandbox ruxsat beradi), lekin o'yin progressni faqat prolog (birinchi poyga) tugagach saqlaydi; har safar oldin to'xtatilgani uchun boshidan boshlangan. FPS (ochiq shahar, protsessor cheklovi): MSync ~50, ESync ~45; MSync xatolari (`server_register_wait`) faqat o'yin majburan yopilganda yoziladi.

**O'z dvigatelimiz, engine-v0.1.0 (2026-11-18).** `.github/workflows/build-engine.yml` `macos-15-intel` da yig'di (`scripts/build-engine.sh`, dappermint/winecx `9f3f644`, Wine 11.19), 538 MB. Uch urinishda tuzatilgan: `wrc` `nls/locale.nls` ni topolmasdi (B29); `sfnt2fon` FreeType'siz yig'ilgan edi (B30); paketda Wine Mono va Gecko yo'q edi, har yangi bottle "Wine Mono Installer" oynasida to'xtardi (B31, skript endi Mono 11.3.0 va Gecko 2.47.4 ni qo'shadi). Mono/Gecko qo'shilgach: bottle 26 s da yaratildi, Notepad ochildi, NFS Most Wanted ochiq shaharda 54.9-56.0 FPS (tayyor winecx-gptk 4.8.3 da 56.1-56.6), Direct, Game Mode.

B24: Chromium GPU jarayoni bilan pipe orqali gaplashadi, Wine'da har xabar wineserver orqali o'tadi va ba'zilari bir soniyadan ko'p kutadi. Ko'prik endi Chromium/Electron dasturlariga `--in-process-gpu` beradi (`Launcher.chromiumArguments`). Foydalanuvchining o'z Notion'ida: 12/12, median 38 ms.

### Unumdorlik o'lchovlari

| O'lchov | Qiymat |
|---|---|
| Bottle yaratish, birinchi marta (`wineboot --init`) | 57-95 s |
| Bottle yaratish, shablondan | 0.42 s |
| Notepad oynasi chiqishi (sovuq bottle) | 7 s |
| 7-Zip jim o'rnatish | 7.8 s |
| Steam kirish oynasi chiqishi (DXVK) | 6-15 s |
| Steam yuklab olish tezligi | ~15 Mbit/s (internetga bog'liq) |
| Bo'sh bottle hajmi | 622 MB (klonlar diskda joy egallamaydi) |
