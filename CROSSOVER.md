# CrossOver: to'liq ma'lumotnoma

Tadqiqot sanasi: 2026-11-16. Asosiy versiya: CrossOver 26.x (oxirgi reliz 26.3.0, 2026-07-21). Narx, changelog, versiyalar tarixi, manba sahifasi va yordam maqolalari shu kuni rasmiy saytdan to'g'ridan-to'g'ri o'qib tekshirilgan.

Bu hujjat CodeWeavers kompaniyasining CrossOver dasturi haqida: nima qiladi, har bir imkoniyati qanday ishlaydi, ichki tuzilishi, cheklovlari, narxi va muqobillari.

**Ishonchlilik belgilari.** Belgisiz yozilgan faktlar rasmiy manbadan (CodeWeavers yordam markazi, changelog, upstream loyiha hujjatlari) olingan. Qolganlari shunday belgilangan:

- `[forum]`: faqat CodeWeavers forumi yoki foydalanuvchi xabaridan, rasmiy sahifada tasdiqlanmagan.
- `[ikkilamchi]`: yangilik sayti, blog yoki Wikipedia'dan.
- `[tasdiqlanmagan]`: tadqiqotda manba topilmadi; umumiy Wine bilimi yoki eski ma'lumotga tayanadi.
- `[ziddiyat]`: manbalar bir-biriga zid, ikkala variant ham keltirilgan.

Eslatma: codeweavers.com blogining ro'yxat sahifasi (sarlavha, sana, kirish parchasi) o'qildi, lekin alohida postlar va forum sahifalari 403 qaytardi. Shuning uchun post ichidagi tafsilotlar ikkilamchi manbalardan.

---

## Mundarija

1. [CrossOver nima](#1-crossover-nima)
2. [Platformalar va tizim talablari](#2-platformalar-va-tizim-talablari)
3. [Narx, litsenziya, sinov muddati](#3-narx-litsenziya-sinov-muddati)
4. [CrossOver'ni o'rnatish va ro'yxatdan o'tkazish](#4-crossoverni-ornatish-va-royxatdan-otkazish)
5. [Asosiy oyna](#5-asosiy-oyna)
6. [Windows dasturlarini o'rnatish](#6-windows-dasturlarini-ornatish)
7. [Dasturlarni ishga tushirish va tizim integratsiyasi](#7-dasturlarni-ishga-tushirish-va-tizim-integratsiyasi)
8. [Bottle'lar](#8-bottlelar)
9. [Advanced Settings: grafika va unumdorlik](#9-advanced-settings-grafika-va-unumdorlik)
10. [Control Panels](#10-control-panels)
11. [Run Command, Run with Options, debug log](#11-run-command-run-with-options-debug-log)
12. [Preferences (dastur sozlamalari)](#12-preferences-dastur-sozlamalari)
13. [Muammolarni tuzatish vositalari](#13-muammolarni-tuzatish-vositalari)
14. [Buyruq qatori vositalari](#14-buyruq-qatori-vositalari)
15. [Konfiguratsiya fayllari va muhit o'zgaruvchilari](#15-konfiguratsiya-fayllari-va-muhit-ozgaruvchilari)
16. [Bottle hook skriptlari](#16-bottle-hook-skriptlari)
17. [CrossTie: o'rnatish retseptlari](#17-crosstie-ornatish-retseptlari)
18. [Texnik arxitektura](#18-texnik-arxitektura)
19. [O'yinlar: launcherlar va anti-cheat](#19-oyinlar-launcherlar-va-anti-cheat)
20. [Moslik bazasi, reytinglar, qo'llab-quvvatlash](#20-moslik-bazasi-reytinglar-qollab-quvvatlash)
21. [Cheklovlar](#21-cheklovlar)
22. [Versiyalar tarixi va changelog](#22-versiyalar-tarixi-va-changelog)
23. [CrossOver 27 va ARM64 kelajagi](#23-crossover-27-va-arm64-kelajagi)
24. [Muqobillar](#24-muqobillar)
25. [CodeWeavers kompaniyasi](#25-codeweavers-kompaniyasi)
26. [Tasdiqlanmagan va ziddiyatli joylar](#26-tasdiqlanmagan-va-ziddiyatli-joylar)
27. [Manbalar](#27-manbalar)

---

## 1. CrossOver nima

CrossOver Windows dasturlari va o'yinlarini macOS, Linux va ChromeOS'da Windows'ning o'zini o'rnatmasdan ishga tushiradigan tijoriy dastur. U virtual mashina emas va emulyator ham emas: Windows API chaqiruvlarini mezbon tizim chaqiruvlariga tarjima qiluvchi **Wine** qatlamiga asoslangan.

CodeWeavers Wine ustiga quyidagilarni qo'shadi:

- grafik interfeys (bottle boshqaruvi, o'rnatish yordamchisi, sozlamalar);
- har bir dastur uchun avtomatik o'rnatish retseptlari (CrossTie);
- o'yinlar uchun grafik tarjima qatlamlari to'plami (D3DMetal, DXMT, DXVK, vkd3d, MoltenVK) va har o'yin uchun backend tanlovchi baza;
- Wine'ga o'z yamoqlari va texnik yordam.

CodeWeavers ishlatadigan GPL va LGPL loyihalar manbasi har reliz uchun ochiq e'lon qilinadi: `codeweavers.com/crossover/source` sahifasida `crossover-sources-26.3.0.tar.gz` (149 MB). Ichidagi loyihalar: Wine, vkd3d, GnuTLS, cabextract, Samba, po4a, Sparkle, PyObjC, PyXDG, libxml2, libxslt, wine-mono, FAudio, SDL va Perl XML modullari. Grafik interfeys va retseptlar bazasi yopiq `[tasdiqlanmagan]`.

Windows litsenziyasi kerak emas, qayta yuklash kerak emas, Windows dasturi mezbon tizim oynasi sifatida ishlaydi.

---

## 2. Platformalar va tizim talablari

### macOS (CrossOver 26)

- Intel Mac yoki Apple Silicon (M1 va yangiroq).
- macOS 10.15 yoki yangiroq (joriy qo'llanma bo'yicha).
- 1 GB bo'sh joy, ustiga har bir Windows dasturi uchun joy.
- Denuvo himoyali o'yinlar Sonoma (14) dan boshlab ishlaydi (23.5.0 changelog).
- D3DMetal 3.0 (GPTK 3) Apple Silicon va macOS 14+ talab qiladi `[ikkilamchi, Gcenx relizlari]`.

CrossOver 27 dan boshlab: faqat Apple Silicon va macOS Sonoma (14) yoki yangiroq. Batafsil [23-bo'limda](#23-crossover-27-va-arm64-kelajagi).

### Linux

- x86 mos kompyuter.
- glibc 2.31 yoki yangiroq, Python 3.5+, GTK 3.18+, PyGObject 3.20+.
- X.Org, XRender va GLX kengaytmalari bilan.
- 1 GB bo'sh joy, ustiga dasturlar uchun joy.
- NTSync uchun Linux yadrosi 6.14+ va `ntsync` moduli.
- ARM64 Linux uchun preview 2025 yil noyabrdan `[ikkilamchi]`.

### ChromeOS

- CrossOver ChromeOS'ning Linux muhiti (Crostini) ichida ishlaydi; Linux versiyasi qo'llanmalari amal qiladi.
- Linux VM diski sukut bo'yicha 5 GB, bu kam; kamida 10 GB tavsiya etiladi.
- Qo'llab-quvvatlanadigan distrolar: Debian va Fedora. Arch va openSUSE Leap qo'llab-quvvatlanmaydi.
- `.deb` paketi ishlatiladi; Linux muhiti uchun Intel protsessor kerak; maktab yoki ish beruvchi boshqaruvi Linux muhitini bloklashi mumkin `[ikkilamchi]`.
- Rasmiy ChromeOS maqolasi oxirgi marta 2024-01-15 da yangilangan.

---

## 3. Narx, litsenziya, sinov muddati

| Mahsulot | Nima beradi | Narx |
|---|---|---|
| CrossOver Free | 14 kunlik sinov | bepul |
| CrossOver+ | To'liq versiya; 12 oy email va telefon orqali yordam; 12 oy yangilanish va tuzatishlar; CrossOver Preview'ga kirish; yangilashda maxsus narx | **54.00 USD** |
| CrossOver Life | To'liq versiya; yangilash to'lovisiz; cheksiz email va telefon yordami; umrbod yangilanishlar; CrossOver Preview; CodeWeavers sovg'alari | **494.00 USD** |

Narxlar rasmiy do'kon sahifasidan (`codeweavers.com/store`, 2026-11-16). CrossOver Life narxi yonida "No Refunds" izohi bor. Promo-kod boshqa takliflar bilan qo'shilmaydi, bitta buyurtmaga bitta kod.

Litsenziya shartlari (rasmiy licensing sahifasi):

- Litsenziya **foydalanuvchi boshiga**: bitta odam istalgan miqdordagi kompyuterga o'rnatishi mumkin.
- Yordam muddati tugagach, shu muddat ichida chiqqan versiyalardan foydalanish huquqi saqlanadi; yangi versiyalar uchun yangilash kerak.
- Yangilash chegirmasi yordam muddati tugaganidan keyin 30 kungacha amal qiladi (foizi ko'rsatilmagan).
- Ta'lim chegirmasi: CrossOver+ uchun 30%, Life uchun 20%. Xariddan oldin Sales bilan bog'lanish kerak.
- Pulni qaytarish: 30 kun ichida, agar litsenziya faollashtirilmagan bo'lsa. Faollashtirilgan bo'lsa, avval texnik yordam bilan ishlash talab etiladi.
- Korporativ hajmli litsenziya shartlari topilmadi.

Sinov muddati:

- 14 kun, to'liq funksional.
- 14 kundan keyin o'rnatilgan Windows dasturlari o'chiriladi (ishga tushmaydi); dastur vaqti-vaqti bilan eslatadi.

---

## 4. CrossOver'ni o'rnatish va ro'yxatdan o'tkazish

### macOS

1. CodeWeavers saytidan zip faylni yuklab oling.
2. Finder'da zip'ni oching (odatda Downloads papkasida).
3. CrossOver'ni ishga tushiring. U **Move to Applications Folder** (tavsiya etiladi) yoki **Do Not Move** ni taklif qiladi. **Don't ask again** belgisi bu so'rovni o'chiradi.
4. Faqat Applications papkasidagi o'rnatish barcha foydalanuvchilar uchun mavjud bo'ladi.

### Linux

Uch xil paket bor:

- **.deb** (Debian, Ubuntu, Mint): tizim darajasida `/opt/cxoffice` ga o'rnatiladi, Windows dasturlari `~/.cxoffice` da.
  ```bash
  sudo apt update
  sudo apt install ./crossover_25.1.0-1.deb
  ```
- **.rpm** (RHEL, Fedora): joylashuv bir xil. Fayl menejerida o'ng tugma, **Open With Software Install**. Terminalda:
  ```bash
  sudo dnf install ./crossover-23.5.0-1.rpm
  ```
  Rasmiy qo'llanmada `sudo dnf local install` deb yozilgan, bu nostandart ko'rinadi.
- **.bin** (umumiy; bog'liqliklarni avtomatik o'rnatmaydi):
  - bitta foydalanuvchi uchun: `~/cxoffice` ga o'rnatiladi. `chmod +x install-crossover-23.5.0.bin`, keyin ishga tushiring;
  - barcha foydalanuvchilar uchun: `sudo` bilan ishga tushiring, `/opt/cxoffice` ga o'rnatiladi.

Fayl nomlaridagi versiyalar qo'llanmadagi misollar; joriy versiya nomi boshqacha bo'ladi.

### ChromeOS

Linux muhitini yoqing, diskni kamida 10 GB qiling, `.deb` paketni o'rnating. Muhim nozik joy: CrossOver yuklab olishni so'ragan o'rnatuvchilar ChromeOS **Downloads** papkasiga tushadi, CrossOver esa Linux **Downloads** papkasidan qidiradi. Faylni Linux ichiga ko'chiring yoki Downloads papkasini Linux bilan ulashing.

### Ro'yxatdan o'tkazish (unlock)

Ro'yxatdan o'tmagan CrossOver sinov rejimida ochiladi. Dialog tugmalari:

- macOS: **Try Now**, **Buy** (do'konni ochadi), **Unlock with Purchase Info**.
- Linux: **Try Now**, **Buy Now**, **Register**.

Email va parol bilan ochish: **CrossOver > Unlock CrossOver** (Linux'da asosiy menyudagi **Unlock CrossOver**), codeweavers.com email va parolini kiriting, **Unlock**. Barcha foydalanuvchilar uchun ochishda Mac foydalanuvchi nomi va paroli so'raladi.

Faollashtirish kodi bilan (uchinchi tomondan sotib olingan nusxalar): **Enter an Activation Code**, so'ng forma. Mavjud codeweavers.com akkauntidan foydalaning yoki email va yangi parol bilan yangisini yarating.

Linux buyruq qatoridan:

```bash
sudo -H /opt/cxoffice/bin/cxregister     # tizim o'rnatishi
sudo -H ~/cxoffice/bin/cxregister        # foydalanuvchi o'rnatishi
```

---

## 5. Asosiy oyna

Oyna uch qismdan iborat:

- **Chap panel (sidebar):** **Home**, **Install** va **Bottles** ro'yxati (har bir bottle alohida qator).
- **Markaz:** tanlangan ko'rinish mazmuni.
  - **Home:** barcha bottle'lardagi o'rnatilgan dasturlar ikonkalari.
  - **Install:** qidiruv satri va dasturlar plitkalari; yuqori o'ngda **Install an unlisted application**.
  - **Bottle ko'rinishi:** shu bottle ichidagi launcherlar.
- **O'ng panel (bottle tanlanganda):** **Run with Options** va **Run Command** tugmalari, hamda **Bottle Actions**, **Advanced Settings**, **Control Panels**, **Bottle Details** bo'limlari.

Home'da ikonkaga o'ng tugma: **Hide from Home** (ikonkani yashiradi, dasturni o'chirmaydi) va **Show in Home** (qaytaradi).

CrossOver 26 da macOS Tahoe uchun interfeys yangilangan.

---

## 6. Windows dasturlarini o'rnatish

CrossOver har bir dasturni **bottle** ichiga o'rnatadi. Sukut bo'yicha har bir dastur o'z bottle'ini oladi. Dasturlar ikki turga bo'linadi:

- **Listed:** moslik bazasida yozuvi va CrossTie retsepti bor.
- **Unlisted:** retsept yo'q, qo'lda o'rnatiladi.

### 6.1 Listed dastur

1. **Install** ko'rinishida qidiruv satriga nomini yozing, plitkani bosing.
2. O'rnatish tafsilotlari (o'rnatuvchi, bottle, bog'liqliklar) imkon bo'lsa avtomatik to'ldiriladi. Har bir tayyor tafsilot belgi oladi.
3. Hammasi tayyor bo'lgach **Install** ni bosing.

**Edit** orqali boshqa o'rnatuvchi faylni tanlash (**Choose Installer**) yoki bottle turini o'zgartirish mumkin.

O'rnatuvchi va bog'liqliklar bepul tarqatiladigan bo'lsa, CrossOver ularni o'zi yuklab oladi. Manba turlari ro'yxati (fayl, yuklab olish, disk, Steam) va bog'liqlik paketlarining to'liq ro'yxati rasmiy qo'llanmada berilmagan `[tasdiqlanmagan]`.

### 6.2 Advanced Options

**Install** tugmasi yonidagi ochiluvchi menyu:

- **Create log file:** o'rnatish jarayonining debug logini yozadi. **Wine logging channels** maydoni oldindan to'ldirilgan va tahrirlanadi. **Change** (Mac) yoki **Log file** maydoni log joyini belgilaydi. **Done** bilan yakunlanadi.
- **Application language:** mavjud tillardan tanlash.
- **Items to install:** bog'liqliklar ro'yxati. Mac'da **+** va **-** bilan qo'shish va olib tashlash, **Revert** o'zgarishlarni bekor qiladi. Linux'da tugmalar **Add**, **Remove**, **Reset**. **Done** bilan yakunlanadi.

### 6.3 O'rnatishni yakunlash

Windows o'rnatuvchisi dialoglariga javob bering (litsenziya, savollar). O'rnatish qotib qolgandek ko'rinsa ham CrossOver'da **Cancel** ni bosmang: qo'llanma buning tuzatib bo'lmas muammoga va bottle'ni o'chirishga olib kelishi mumkinligidan ogohlantiradi. Tugagach ikonka **Home** va bottle ichida paydo bo'ladi.

### 6.4 Unlisted dastur

Alohida bottle tavsiya etiladi, chunki mavjud bottle'ga o'rnatish undagi boshqa dasturlarni buzishi mumkin.

1. Install ekranining yuqori o'ngidagi **Install an unlisted application** ni bosing.
2. O'rnatuvchi fayl uchun **Edit**, faylni tanlang, **Choose Installer**.
3. Bottle uchun **Edit**. **New Bottle Name** ni kiriting, **New Bottle Type** ro'yxatidan tanlang, **Done**.
4. **Install**. CrossOver bottle yaratadi va o'rnatuvchini ishga tushiradi.
5. O'rnatuvchi qadamlarini bajaring; sukut qiymatlar odatda mos keladi.
6. Tugagach CrossOver bottle mazmunini ko'rsatadi. Dastur ikonkasini ikki marta bosing.

Launcher ikonkasi yaratilmasa, **Run Command** orqali qo'lda yarating.

### 6.5 O'rnatuvchisiz dastur (alohida .exe)

1. **Bottle > New Bottle**: nom kiriting, turini tanlang, **Create**.
2. `.exe` faylni chap paneldagi bottle ustiga sudrab tashlang. **Run Command** ochiladi. **Run** ni bosing.
3. Ixtiyoriy: **Save Command as a Launcher** (Linux'da **Create Launcher**). `.exe` ko'chirilsa yoki o'chirilsa launcher ishlamay qoladi.

---

## 7. Dasturlarni ishga tushirish va tizim integratsiyasi

### macOS

- Bottle yoki **Home** ko'rinishida ikonkani ikki marta bosing.
- Har bir dastur Apps launcher'da ikonka oladi; uni Dock'ka sudrab qo'yish mumkin. Dasturni ishga tushirish CrossOver'ni ham ochadi.
- Ikonkalar yaratiladigan papka Preferences'dagi **Program Folder** bilan belgilanadi.

### Linux

- Ish stoli integratsiyasi menyu yozuvlarini yaratadi (masalan Xfce'da **Windows Applications** menyusi). GNOME'da ish stoli qidiruvidan foydalaning.
- `.bin` o'rnatishlari `~/cxoffice/bin` da buyruq yorliqlarini yaratadi, masalan `~/cxoffice/bin/winword letter.doc`.
- Yorliqlar ro'yxati: `grep -l desktopdata/cxmenu ~/cxoffice/bin/*`
- Yorliq dasturning eng oxirgi o'rnatilgan versiyasini ishga tushiradi.
- Fayl assotsiatsiyalari va menyular **Edit Associations** va **Edit Menus** control panellari orqali tahrirlanadi.
- Yorliq papkalari `cxoffice.conf` dagi **PrivateShortcutDirs** (shaxsiy bottle'lar) va **ManagedShortcutDirs** (published bottle'lar) bilan belgilanadi.

### Buyruq qatoridan ishga tushirish

```bash
/opt/cxoffice/bin/wine --bottle bottle-nomi --cx-app winword.exe   # tizim o'rnatishi
~/cxoffice/bin/wine --bottle bottle-nomi --cx-app winword.exe      # foydalanuvchi o'rnatishi
```

Bottle ichidagi bajariluvchi fayllarni topish:

```bash
find ~/.cxoffice -iname "*.exe"
```

Ogohlantirish: `.exe` fayllar orasida tizim vositalari va yordamchi komponentlar bor; ularni tasodifiy ishga tushirish bottle'ga zarar yetkazishi mumkin.

### Windows disklarini mezbon papkalarga bog'lash

Har bir bottle'da sukut bo'yicha uchta disk bor: **C:** bottle ildizi, **Y:** uy papkangiz, **Z:** Mac diskining ildizi. Tashqi disklar, CD/DVD va USB tizimga ulanganda avtomatik harf oladi. Ba'zi CD/DVD'lar nusxa himoyasi sababli avval **D:** sifatida bog'lanishi kerak.

- macOS, grafik usul: **Wine Configuration > Drives**, **Add**, **Browse**, **Apply**, **Ok**. Masalan papkani **D:** diskiga bog'lash.
- Linux, terminal:
  ```bash
  ln -s /path/to/folder ~/.cxoffice/bottle-nomi/dosdevices/d:
  ln -s /dev/sda1 ~/.cxoffice/bottle-nomi/dosdevices/d::
  ```
- Bog'langan papka ildizidagi maxsus fayllar: `.windows-serial` (disk seriya raqami) va `.windows-label` (tom yorlig'i):
  ```bash
  echo 123456 > /path/to/folder/.windows-serial
  echo TestLabel > /path/to/folder/.windows-label
  ```

### Klaviatura

macOS'da **Command** tugmasi sukut bo'yicha Windows **Alt** vazifasini bajaradi. O'zgartirish bottle registri orqali (`regedit`, kalit `HKEY_CURRENT_USER\Software\Wine\Mac Driver`); CodeWeavers tayyor `.reg` fayllarini beradi (`OptionIsAlt.reg`, `CommandIsCtrl.reg`):

| Maqsad | Qiymatlar |
|---|---|
| Option tugmasi Alt bo'lsin | `"LeftOptionIsAlt"="Y"`, `"RightOptionIsAlt"="Y"` |
| Command tugmasi Ctrl bo'lsin | `"LeftCommandIsCtrl"="Y"`, `"RightCommandIsCtrl"="Y"` |

Sozlama shu bottle'dagi barcha dasturlarga ta'sir qiladi. Registr faylini import qilishda Downloads papkasi `My Computer > Y: > Downloads` orqali topiladi.

---

## 8. Bottle'lar

### 8.1 Tushuncha

Bottle bitta mustaqil virtual Windows muhiti. Ichida:

- standart papkalari bilan C: disk;
- Windows registri;
- shu bottle uchun CrossOver sozlamalari;
- o'rnatilgan dasturlar va foydalanuvchi ma'lumotlari.

Bottle'lar bir-biridan ajratilgan: bittasidagi dastur, kutubxona yoki sozlama boshqasiga ta'sir qilmaydi. Shuning uchun har bir dasturga alohida bottle tavsiya etiladi.

### 8.2 Bottle turlari (shablonlar)

Shablon nomlari: `win98`, `win2000`, `winxp`, `winvista`, `win7`, `win8`, `win10`, `win11`. 64-bit variant `_64` qo'shimchasi bilan, masalan `win10_64`.

CrossOver 26 sukut bo'yicha 64-bit bottle yaratadi. 32-bit bottle'lar eskirgan deb belgilangan va faqat Preferences'dagi **Enable deprecated 32-bit bottles** yoqilganda yaratiladi; CrossOver 27 da butunlay olib tashlanadi. CodeWeavers bo'yicha deyarli barcha 32-bit dasturlar 64-bit bottle'da ishlaydi.

### 8.3 Bottle menyusi (menyu satri)

| Buyruq | Vazifasi |
|---|---|
| **New Bottle** | Bo'sh bottle; Windows versiyasi tanlanadi |
| **Duplicate Bottle** | Yangi nom bilan nusxa |
| **Rename Bottle** | Nomni tahrirlanadigan qiladi |
| **Export Bottle to Archive** | Siqilgan nusxa (`.cxarchive`). Arxivlash paytida bottle'dan foydalanib bo'lmaydi. Katta o'zgarishlardan yoki boshqa kompyuterga ko'chishdan oldin tavsiya etiladi |
| **Import Bottle Archive** | `.cxarchive` faylni tiklaydi |
| **Publish Bottle** | Bottle'ni kompyuterdagi barcha foydalanuvchilarga ochadi |
| **Update Published Bottle** | O'zgarishlarni published nusxaga yuboradi |
| **Open Shell** (Mac) | Bottle muhitida terminal. Chap paneldagi bottle ustida o'ng tugma bosib, **Option** ushlab turilsa **Run Command** **Open Shell** ga aylanadi; terminal kerakli muhit o'zgaruvchilarini o'rnatib, `drive_c` ga o'tadi. `wine cmd` Windows buyruq qatorini ochadi, `wine --cx-app dastur.exe` dasturni ishga tushiradi. Qo'llanma buni ilg'or va kafolatlanmagan deb ataydi |

### 8.4 Bottle Actions (o'ng panel)

- **Open C: Drive:** bottle C: diskini fayl menejerida ochadi.
- **Install Applications Into Bottle:** Install ko'rinishini shu bottle maqsad qilib ochadi.
- **Quit All Applications:** bottle'dagi hamma dasturni yopadi. Muvaffaqiyatsiz bo'lsa tugma **Force Quit** ga aylanadi; saqlanmagan ish yo'qolishi mumkin.
- **Delete Bottle:** butunlay o'chiradi, qaytarib bo'lmaydi.

### 8.5 Bottle Details

Bottle'dagi dasturlar va komponentlar ro'yxati hamda **Description** maydoni. Dasturni o'chirish: ustiga o'ng tugma, **Uninstall**, Windows so'rovlariga javob bering. Qaytarib bo'lmaydi va shu bottle'dagi boshqa dasturlarni buzishi mumkin.

### 8.6 Published (umumiy) bottle'lar

Ko'p foydalanuvchili kompyuterlar uchun: administrator bottle'ni bir marta sozlaydi, qolgan foydalanuvchilar undan foydalanadi.

- **Bottle > Publish Bottle**. Avval shaxsiy ma'lumotlarni (keshlangan parollar, foydalanuvchi nomlari) olib tashlang.
- Sukut nomi: `published_MavjudBottleNomi`. Administrator paroli kerak.
- Boshqa foydalanuvchilar o'z uy papkasida shu nomli **stub bottle** oladi.
- O'zgarishlar **Bottle > Update Published Bottle** orqali yuboriladi.

### 8.7 Diskdagi joylashuv

| | macOS | Linux |
|---|---|---|
| Foydalanuvchi bottle'lari | `~/Library/Application Support/CrossOver/Bottles` | `~/.cxoffice` |
| Published bottle'lar | `/Library/Application Support/CrossOver/Bottles` | `/opt/cxoffice/etc` |
| Stub bottle'lar | foydalanuvchi bottle papkasi | `~/.cxoffice` |

`[ziddiyat]` Mac User Guide published nusxa `CrossOver.app/Contents/SharedSupport/CrossOver` ichida deydi, Linux User Guide esa `~/cxoffice` deydi. Jadvaldagi qiymatlar aniqroq bo'lgan Advanced Configuration sahifalaridan.

Joylashuvni o'zgartirish (macOS):

```bash
# shaxsiy bottle papkasi
defaults write com.codeweavers.CrossOver.plist BottleDir /path/to/bottle/dir
# published bottle'lar qidiriladigan papka
defaults write com.codeweavers.CrossOver.plist ManagedBottleDirs /path/to/shared/bottle/dir
```

Qoidalar: tarmoq diskidan foydalanmang; shaxsiy papka published bottle'lar papkasiga qaramasligi kerak; boshqa fayl tizimli tashqi disk bottle'larni buzishi mumkin. Grafik usul: Preferences'dagi **Bottle Folder**.

Linux'da joylashuv `CX_BOTTLE_PATH` va `CX_MANAGED_BOTTLE_PATH` orqali o'zgaradi ([15-bo'lim](#15-konfiguratsiya-fayllari-va-muhit-ozgaruvchilari)).

### 8.8 Bottle ichki tuzilishi

Bottle Wine prefiksi (`WINEPREFIX`) hisoblanadi. Standart Wine tuzilishi `[tasdiqlanmagan: CrossOver uchun rasmiy sahifada sanab o'tilmagan]`:

- `drive_c/`: C: disk (`Program Files`, `windows`, `users`).
- `dosdevices/`: disk harflari simvolik havolalar sifatida (`c:`, `d:`, `d::` qurilma uchun). Bu rasmiy sahifadagi misollarda tasdiqlangan.
- `system.reg`, `user.reg`, `userdef.reg`: registr fayllari (HKLM, HKCU, sukut foydalanuvchi).
- `cxbottle.conf`: bottle darajasidagi CrossOver sozlamalari `[forum]`. Rasmiy yordam markazida bu fayl tilga olinmaydi; faqat forum va uchinchi tomon qo'llanmalarida uchraydi.
- `scripts.d/`: bottle darajasidagi hook skriptlar (rasmiy tasdiqlangan).

"Expired bottle" xatosi: litsenziya joyida bo'lsa ham chiqsa, sabab odatda `dosdevices` ichidagi **z:** havolasi yo'qolgani. Rasmiy tuzatish: yangi bottle yaratib, uning `dosdevices/z:` havolasini buzilgan bottle'ning `dosdevices` papkasiga nusxalash.

---

## 9. Advanced Settings: grafika va unumdorlik

### 9.1 macOS (CrossOver 26)

**Advanced Settings > Graphics** ostida bitta backend tanlanadi. Tanlov bottle'dagi barcha dasturlarga ta'sir qiladi.

| Tanlov | Nima | Qamrovi |
|---|---|---|
| **Auto** | CodeWeavers bazasidan har o'yin uchun backend tanlaydi; bazada yo'q bo'lsa wined3d | sukut qiymat |
| **DXMT** | Metal asosidagi Direct3D 11 tarjimasi | D3D11 (upstream bo'yicha D3D10 ham) |
| **D3DMetal** | Apple Game Porting Toolkit tarjima qatlami | DirectX 11 va 12 |
| **DXVK** | Vulkan asosidagi tarjima (macOS'da MoltenVK orqali Metal'ga) | Direct3D 10 va 11 |
| **Wine** | wined3d, Wine'ning o'z Direct3D realizatsiyasi | eski API'lar, umumiy holat |

Qo'shimcha kalitlar:

- **DLSS:** DLSS'ni MetalFX orqali yoqadi. Faqat D3DMetal yoki DXMT bilan va o'yinning o'z sozlamasida DLSS yoqilgan bo'lsagina ishlaydi.
- **MSync:** Mach semaforlariga asoslangan sinxronizatsiya. Ba'zi dasturlarda unumdorlikni oshiradi, boshqalarida farq qilmaydi.
- **High Resolution Mode:** piksel ikkilashni o'chiradi va 192 DPI xabar qiladi (Retina aniqligi). Ba'zi dasturlar noto'g'ri chizadi.
- **Performance Enhanced Graphics (CSMT):** sukut bo'yicha yoqilgan; 23.x dan beri kalit ko'rsatilmaydi.

Amaliy tavsiya: **Auto** dan boshlang; backend, MSync yoki High Resolution Mode ni faqat unumdorlik yoki tasvir muammosi bo'lganda o'zgartiring `[ikkilamchi]`. Backend almashtirilgach bottle'ni qayta ishga tushirish kerak bo'lishi mumkin; ba'zi o'yinlar D3DMetal'da qulab, DXVK'da ishlaydi `[forum]`.

25.1.0 da "msync yoqilganda Steam yuklab olishlari" tuzatilgan, ya'ni MSync Steam bilan muammo tug'dirgan.

### 9.2 Linux

Linux qo'llanmasidagi grafik tanlovlar: **Auto**, **DXVK**, **Wine** (wined3d), **High-Resolution Mode**. D3DMetal va DXMT faqat macOS'da (ular Metal'ga bog'liq).

Linux'da CrossOver 26 yadro qo'llasa **NTSync** dan foydalanadi (yadro 6.14+):

```bash
sudo modprobe ntsync
echo ntsync | sudo tee /etc/modules-load.d/ntsync.conf
```

### 9.3 ESync haqida

`[ziddiyat]` Bir manbada ESync va MSync ikkalasi bottle kalitlari (sukut o'chiq) deyilgan; boshqa manbada ESync CrossOver 26 da olib tashlangan (Linux'da NTSync, Mac'da MSync). CrossOver Mac 26 Advanced Settings sahifasida faqat MSync sanalgan, shuning uchun 26 da ESync kaliti yo'q deb hisoblash to'g'riroq. Changelog bo'yicha: ESync Linux'da 20.0.4 davrida "tajribaviy" edi; MSync macOS'ga 23.7.0 (2023-11-27) da qo'shilgan; Linux'da 26.0.0 dan NTSync.

---

## 10. Control Panels

Qo'llanma tizim sozlamalari uchun mezbon OS vositalaridan foydalanishni maslahat beradi, chunki Windows control panellarining aksariyati qo'llab-quvvatlanmaydi.

| Panel | macOS | Linux | Vazifasi |
|---|---|---|---|
| **Wine Configuration** | ha | ha | `winecfg`: Windows versiyasi, kutubxona override'lari, disklar, grafika, audio |
| **Game Controllers** | ha | ha | Kontroller sozlash. **Disable hidraw** simli Sony kontrollerlarga yordam beradi, lekin Sony'ning ilg'or funksiyalarini o'chiradi |
| **Simulate Reboot** | ha | ha | Windows qayta yuklanishini taqlid qiladi (o'rnatuvchi reboot so'raganda) |
| **Task Manager** | ha | ha | Qotgan jarayonlarni to'xtatadi |
| **Internet Settings** | ha | ha | Tarmoq sozlamalari |
| **Edit Associations** | yo'q | ha | Fayl turlari assotsiatsiyalari |
| **Edit Menus** | yo'q | ha | Ish stoli menyu yozuvlari |

Registry Editor alohida panel sifatida sanalmagan; u **Run Command** orqali `regedit` yozib ochiladi.

---

## 11. Run Command, Run with Options, debug log

### Run Command

Bottle ichida ixtiyoriy buyruqni ishga tushiradi: Wine vositalari (`regedit`, `notepad`, `cmd`, `winecfg`) yoki ikonkasi yo'q dasturlar.

- **Browse:** C: diskdan `.exe` topish (Program Files'dan boshlang), tanlang, **Run**.
- **Save Command as Launcher** (Mac) yoki **Create Launcher** (Linux): yorliq yaratadi.

### Run with Options

Debug log yozish hamda buyruq qatori parametrlari va muhit o'zgaruvchilarini berish uchun.

Grafik usulda log olish:

1. Chap panelda **Bottles** ostidan dastur bottle'ini oching, launcherini tanlang.
2. O'ng panelda **Run with Options**.
3. **Create log file** ni belgilang.
4. **Wine logging channels** ga kanallarni yozing yoki **+** menyusidan tanlang.
5. Ixtiyoriy: **Log file** maydonida yo'lni o'zgartiring.
6. **Run**.
7. Muammoni takrorlang; dasturni va **Run Command** dialogini yoping.
8. `.cxlog` faylga o'ng tugma, **Compress**, texnik yordamga yuboring.

Terminal usuli (Linux, paket o'rnatishi):

```bash
CX_LOG=~/cxlog.txt CX_DEBUGMSG=+seh,+tid /opt/cxoffice/bin/wine --bottle "bottle-nomi" --cx-app launcher.exe
```

- `CX_LOG`: log fayl yo'li.
- `CX_DEBUGMSG`: kanallar ro'yxati; asosiy log uchun tushirib qoldiring.
- `.bin` foydalanuvchi o'rnatishi uchun `~/cxoffice/bin/wine`.

Kanallar: `+seh,+tid` boshlang'ich to'plam. Forumda `+seh,+trace,+ntdll` ham tavsiya etilgan `[forum]`. Loglash dasturni sezilarli sekinlashtiradi.

O'rnatish paytidagi log: Install ekranidagi **Advanced Options > Create log file**.

---

## 12. Preferences (dastur sozlamalari)

Sozlamalar har bir foydalanuvchi uchun alohida.

### macOS (CrossOver > Settings)

**Online Integration**
- **Check for CrossOver Updates:** yangilanishlarni tekshirish.
- **Remind About Submitting Ratings:** reyting yuborishni eslatish.

**System Integration**
- **Bottle Folder** (**Reset** bilan): bottle'lar saqlanadigan joy. Boshqa fayl tizimli tashqi diskdan foydalanmang.
- **Program Folder** (**Reset** bilan): dastur ikonkalari yaratiladigan joy.

**Installer Assistant**
- **Automatically Download New Installation Recipes:** retseptlar ro'yxatini sinxronlaydi.
- **Hide Entries for Untested and Known-Not-To-Work Software:** 1 yulduzli, 2 yulduzli va baholanmagan dasturlarni yashiradi.
- **Launch Installer Assistant:** `.exe` ni ikki marta bosganda o'rnatishni boshlaydi. O'chirilgan bo'lsa CrossOver `.exe` ni mavjud bottle'da ishga tushiradi.
- **Enable deprecated 32-bit bottles:** 64-bit bottle dasturni buzgan hollar uchun. CrossOver 27 da olib tashlanadi.
- **Cache of Downloaded Installers** (**Clear** bilan): joy bo'shatish yoki qayta o'rnatish muammolarini tuzatish uchun keshni tozalaydi.

### Linux

**Online Integration:** **Installation Recipes**, **CrossOver Updates**, **Submitting Ratings**.

**Bottles:** **Select the default bottle location** (**Select**, **Reset**); **Enable deprecated 32-bit bottles**.

**Installer Assistant:**
- **Include Entries for Untested and Known-Not-To-Work Software** (Mac'dagining teskarisi: belgilansa ko'rsatadi);
- **Install Recommended Linux Packages:** kerakli Linux paketlarini avtomatik o'rnatish;
- **Downloaded Installers** (**Clear**): kesh `~/.cxoffice/installers` da.

**User Interface:** **Use Default Window Decorations**.

---

## 13. Muammolarni tuzatish vositalari

- **Clear and Rebuild Programs** (Mac): Dock yoki Launchpad'dan ishga tushirish ishlamasa dastur ikonkalarini qayta yaratadi.
- **Repair Bottles** (Mac): bottle'larni qayta skanerlaydi va antivirus o'chirgan fayllarni tiklaydi. CrossOver'ni antivirus skanerlashidan chiqarib qo'yish tavsiya etiladi.
- **CrossOver > Check For Updates:** yangilanishni yuklab qo'llaydi. Litsenziya muddati tugagan bo'lsa do'konga yo'naltiradi.
- **Simulate Reboot**, **Task Manager**, **Quit All Applications / Force Quit**: qotgan holatlar uchun.
- **Export Bottle to Archive:** xavfli o'zgarishdan oldin zaxira.
- **Cache of Downloaded Installers > Clear:** buzilgan o'rnatuvchi keshi uchun.
- **Debug log** ([11-bo'lim](#11-run-command-run-with-options-debug-log)): texnik yordam uchun.

### Unlisted dastur ishlamasa (rasmiy tartib)

1. Moslik bazasidan dasturni qidiring: boshqa foydalanuvchilarning baho izohlari, Tips bo'limi va forum.
2. **Bog'liqliklarni qo'shing.** Tez yo'l: CodeWeavers tayyorlagan `The-Kitchen-Sink.cxarchive` arxivini (ko'p uchraydigan bog'liqliklar to'plami) **Bottle > Import Bottle Archive** orqali import qilib, dasturni shu bottle'ga o'rnatish. Aniq bog'liqlik ma'lum bo'lsa, uni Install ekranidan qidirib o'rnating.
3. **Wine Configuration > Libraries:** DLL override. **Native** haqiqiy Windows DLL'ini, **Builtin** Wine'nikini ishlatadi; yangi DLL "New override for library" maydoni orqali qo'shiladi.
4. **Windows versiyasini almashtiring:** Control Panels > Wine Configuration > Applications. Eng ishonchlisi dasturni boshqa Windows versiyali yangi bottle'ga qayta o'rnatish, chunki o'rnatuvchi versiyaga qarab registrga turli kalitlar yozadi.
5. **Registr:** Run Command'da `regedit`. Rasmiy misol: `HKEY_CURRENT_USER\Software\Wine\Direct3D` ichida `renderer` satr qiymatini `vulkan` qilish.

Texnik yordam unlisted dasturlar uchun so'ralmagan loglarni ko'rib chiqmaydi.

### CrossOver'ni o'chirish

- **CrossOver Removal Tool:** rasmiy vosita, CrossOver fayllari, o'rnatilgan Windows dasturlari va ilovaning o'zini o'chiradi. Avval kerakli bottle'larni arxivlang. Birinchi ochishda macOS xavfsizlik ogohlantirishi chiqadi; o'ng tugma, **Open** bilan ochiladi.
- **Qo'lda:** `~/Library/Application Support/CrossOver` papkasi, `~/Library/Preferences` dagi `com.codeweavers` bilan boshlanuvchi fayllar, `~/Applications/CrossOver` papkasi (bo'lsa) va Applications'dagi ilova.
- Linux uchun o'chirish tartibi qo'llanmada yoritilmagan.

---

## 14. Buyruq qatori vositalari

Joylashuv:

- Linux, paket o'rnatishi: `/opt/cxoffice/bin`
- Linux, `.bin` foydalanuvchi o'rnatishi: `~/cxoffice/bin`
- macOS: `CrossOver.app/Contents/SharedSupport/CrossOver/bin` `[forum]`. Rasmiy yo'l: **Open Shell** (bottle ustida o'ng tugma + Option). Rasmiy izoh: Mac'da terminaldan ishga tushirish Linux'dagidan murakkabroq, chunki avval bir qator muhit o'zgaruvchilari o'rnatilishi kerak; Open Shell buni o'zi bajaradi. Keyin `wine --cx-app dastur.exe` yoki `wine cmd`. CodeWeavers bu yo'ldagi amallarning deyarli hammasi qo'llab-quvvatlanmasligini aytadi.

| Vosita | Vazifasi | Misol |
|---|---|---|
| `wine` | Dasturni bottle ichida ishga tushirish | `wine --bottle NOM --cx-app prog.exe` |
| `cxrun` | Bottle'da buyruq ishga tushirish `[forum, eski]` | `cxrun --bottle NOM --command prog.exe` |
| `cxstart` | Dastur ishga tushiruvchi; loglarda uchraydi, foydalanuvchi uchun hujjatlanmagan | `cxstart --bottle NOM prog.exe` |
| `cxbottle` | Bottle boshqaruvi va paketlash | `cxbottle --bottle Notepad++ --deb --rpm` |
| `cxinstaller` | CrossOver Software Installer'ni ochadi | |
| `cxregister` | Litsenziyani ro'yxatdan o'tkazish | `sudo -H /opt/cxoffice/bin/cxregister` |
| `cxreset` | Noto'g'ri ishlayotgan Windows dasturlarini to'xtatadi | |
| `cxmenu` | Menyu yozuvlarini boshqarish | quyida |
| `cxassoc` | Fayl assotsiatsiyalarini boshqarish | quyida |
| `cxtie` | CrossTie fayl turini ro'yxatdan o'tkazish | `cxtie --register` |

Umumiy (faqat o'qish uchun, tarmoqdagi) o'rnatishni har bir tizimda root sifatida ulash:

```bash
/common/software/cxoffice/bin/cxmenu --ro-desktopdata --crossover --install
/common/software/cxoffice/bin/cxassoc --ro-desktopdata --crossover --install
/common/software/cxoffice/bin/cxtie --register
/common/software/cxoffice/bin/cxbottle --ro-desktopdata --bottle bottle-nomi --install
```

`cxbottle --deb --rpm` bottle'ni tarqatish uchun distro paketiga aylantiradi: sozlangan dasturni ko'p kompyuterga yoyish usuli.

Vositalarning to'liq flag ro'yxati tekshirilmadi; har birini `--help` bilan ko'ring.

---

## 15. Konfiguratsiya fayllari va muhit o'zgaruvchilari

### 15.1 Fayllar

| Fayl | Platforma | Vazifasi |
|---|---|---|
| `~/Library/Preferences/com.codeweavers.CrossOver.plist` | macOS | Dastur sozlamalari; kalitlar `BottleDir`, `ManagedBottleDirs` |
| `~/.cxoffice/cxoffice.conf` | Linux | Foydalanuvchi darajasidagi konfiguratsiya |
| `/opt/cxoffice/etc/cxoffice.conf` | Linux | Tizim darajasidagi konfiguratsiya |
| `<bottle>/cxbottle.conf` | ikkalasi | Bottle darajasidagi sozlamalar `[forum]` |
| `~/.cxoffice/installers` | Linux | Yuklab olingan o'rnatuvchilar keshi |

`cxoffice.conf` misoli (Linux, rasmiy):

```ini
[EnvironmentVariables]
"CX_BOTTLE_PATH"="/extra/bottles:~/.cxoffice"
"CX_MANAGED_BOTTLE_PATH"="/extra/published_bottles"
```

Shu faylda **PrivateShortcutDirs** va **ManagedShortcutDirs** ham bor.

Bottle uchun alohida muhit o'zgaruvchisi `[forum]`: bottle ildizidagi `cxbottle.conf` ning `[EnvironmentVariables]` bo'limiga qator qo'shiladi, masalan `"DXVK_HUD" = "1"`. Ishlagani xabar qilingan, joriy relizda tekshirilmagan. Rasmiy yo'l: **Run with Options**.

Forumda Windows versiyasi `cxbottle.conf` da saqlanishi (`WindowsVersion` yoki shablon nomi) aytilgan `[forum]`. Rasmiy usul faylni tahrirlash emas: Control Panels > Wine Configuration > Applications (Mac va Linux'da bir xil).

### 15.2 CrossOver o'zgaruvchilari

| O'zgaruvchi | Ma'nosi |
|---|---|
| `CX_ROOT` | CrossOver o'rnatilgan papka (absolyut yo'l) |
| `CX_BOTTLE` | Joriy bottle nomi |
| `WINEPREFIX` | Bottle papkasi (absolyut yo'l) |
| `CX_BOTTLE_PATH` | Bottle'lar qidiriladigan yo'llar, ikki nuqta bilan ajratiladi; yangi bottle faqat birinchisida yaratiladi. Linux sukuti `~/.cxoffice` |
| `CX_MANAGED_BOTTLE_PATH` | Published bottle'lar joyi. Linux sukuti `/opt/cxoffice/etc` |
| `CX_LOG` | Debug log fayli yo'li |
| `CX_DEBUGMSG` | Loglash kanallari, masalan `+seh,+tid` |

Forum eslatmasi: `CX_BOTTLE_PATH` aynan Bottles papkasining o'ziga qaratilmaguncha ishlamagan `[forum]`.

Grafik backend muhit o'zgaruvchisi bilan emas, bottle sozlamasi (interfeys) orqali tanlanadi.

### 15.3 Wine o'zgaruvchilari

- `WINEDEBUG`: kanallar bo'yicha loglash; sintaksis `sinf+kanal`, `+` yoki `-` bilan (masalan `warn+all`). WineHQ hujjatida tasdiqlangan.
- `WINEDLLOVERRIDES`: har bir DLL uchun `native` yoki `builtin` yuklash tartibi. WineHQ hujjatida tasdiqlangan.
- `WINEESYNC=1`: ESync. `WINEMSYNC=1`: MSync; u bilan birga `WINEESYNC=1` ham berilishi kerak, chunki D3DMetal ESync belgisiga qaraydi. Ikkalasi Whisky manba kodida (`WhiskyKit/.../Wine/Wine.swift`) tasdiqlangan.
- `WINEFSYNC`: FSync, faqat uni qo'llaydigan Linux build'larida `[tasdiqlanmagan]`.

### 15.4 Grafik qatlam o'zgaruvchilari

DXVK (upstream `dxvk.conf` bo'yicha):

- `DXVK_HUD`: HUD elementlari (FPS va hokazo), `dxvk.hud` ni bosib o'tadi.
- `DXVK_HDR`: `dxgi.enableHDR` sukutini belgilaydi.
- `DXVK_DEBUG=markers`: debug utils.
- `DXVK_FILTER_DEVICE_NAME`: GPU filtri.
- Konfig sukutlari: `dxvk.tearFree=Auto`, `dxvk.tilerMode=Auto`, `d3d11.maxFeatureLevel=12_1`, `dxgi.maxFrameRate=0`.

MoltenVK (Runtime User Guide bo'yicha):

- `MVK_CONFIG_DEBUG`: SPIR-V va MSL'ni loglaydi.
- `MVK_CONFIG_USE_MTLHEAP`: `VK_EXT_image_2d_view_of_3d` uchun kerak.
- `MVK_CONFIG_AUTO_GPU_CAPTURE_SCOPE` (0/1/2), `MVK_CONFIG_AUTO_GPU_CAPTURE_OUTPUT_FILE`.
- Ustuvorlik: `VK_EXT_layer_settings`, keyin muhit o'zgaruvchilari, keyin build sozlamalari. Minimal macOS 12.0.

Apple / D3DMetal. Apple'ning o'z sahifalarida hujjatlanmagan; quyidagilar Whisky manba kodida ishlatilgani uchun amalda tasdiqlangan:

- `MTL_HUD_ENABLED=1`: Metal unumdorlik HUD'i. Tizim bo'yicha: `launchctl setenv MTL_HUD_ENABLED 1`, o'chirish `launchctl unsetenv MTL_HUD_ENABLED`.
- `METAL_CAPTURE_ENABLED=1`: Metal kadrlarini Xcode'da ushlashga ruxsat.
- `ROSETTA_ADVERTISE_AVX=1`: Rosetta ostida AVX borligini dasturga e'lon qilish.
- `D3DM_SUPPORT_DXR=1`: D3DMetal'da nurlar izlashni (DXR) yoqish.
- `D3DM_ENABLE_METALFX=1` (MetalFX) va `D3DM_MTL4=0` (GPTK 4 da Metal 4 o'rniga Metal 3): faqat uchinchi tomon blogi va forum xabarida `[tasdiqlanmagan]`.
- `D3DM` loglardagi prefiks ham: GPTK xabarlari shu bilan boshlanadi.

Whisky ishga tushirishda doim beradigan asosiy to'plam: `WINEPREFIX`, `WINEDEBUG=fixme-all`, `GST_DEBUG=1`; DXVK yoqilganda `WINEDLLOVERRIDES=dxgi,d3d9,d3d10core,d3d11=n,b`, `DXVK_ASYNC=1`, `DXVK_HUD`.

DXMT: README'da muhit o'zgaruvchilari hujjatlanmagan; `dxmt.conf` fayli mavjud.

---

## 16. Bottle hook skriptlari

Hook: bottle hayot siklining ma'lum bosqichlarida avtomatik ishlaydigan shell skript. Korporativ yoyishda disk bog'lash, registrni tozalash kabi ishlar uchun.

Joylashuv:

- macOS, foydalanuvchi: `~/Library/Application Support/CrossOver/support/scripts.d`
- Linux, foydalanuvchi: `~/.cxoffice/scripts.d`
- Linux, tizim: `/opt/cxoffice/support/scripts.d`
- Bitta bottle uchun: bottle ildizidagi `scripts.d` papkasi.

Nomlash: `nn.nom`, bu yerda `nn` ikki xonali o'nlik son (bajarilish tartibi). Nomda nuqta yoki tilda bo'lmasligi kerak. Misol: `10.remap_drive`. Skript bajariluvchi bo'lishi shart.

Skriptga beriladigan muhit: `CX_ROOT`, `CX_BOTTLE`, `WINEPREFIX`.

Birinchi argument (hodisa turi):

| Argument | Qachon |
|---|---|
| `create <shablon>` | Bottle yaratilganda |
| `restore` | Arxivdan tiklanganda |
| `upgrade-from <eski-bottle-versiyasi>` | Bottle yangi CrossOver versiyasiga yangilanganda |
| `pre-create-stub <published-wineprefix>` | Stub yaratilishidan oldin |
| `create-stub <published-wineprefix>` | Stub yaratilganda |
| `pre-update-stub <published-wineprefix>` | Stub yangilanishidan oldin |
| `update-stub <published-wineprefix>` | Stub yangilanganda |

Misol: Y: diskini olib tashlab, H: ni uy papkasiga bog'lash:

```sh
#!/bin/sh
rm "$WINEPREFIX/dosdevices/y:"
if [ ! -d "$WINEPREFIX/dosdevices/h:" ]
then
 ln -s -f "$HOME" "$WINEPREFIX/dosdevices/h:"
fi
```

Rasmiy sahifada ikkinchi misol ham bor: `create-stub` yoki `update-stub` hodisasida registr kalitini o'chirish.

---

## 17. CrossTie: o'rnatish retseptlari

CrossTie (`.tie` fayl; avvalgi nomi C4P, eski kengaytma `.c4p`) CrossOver'ga dasturni qanday o'rnatishni aytuvchi XML retsept. CrossOver 10.x dan beri ishlatiladi.

Retsept nimalar qila oladi:

- o'rnatuvchini qayerdan olishni ko'rsatish (yuklab olish, fayl, CD);
- bottle turini va bog'liqliklarni belgilash;
- registr yozuvlarini qo'shish, DLL'larni qo'shish yoki almashtirish;
- dastur yorliqlarini yaratish.

Tuzilishi: ildiz element `<c4p>`, dastur yozuvlari `<app appid="com.codeweavers.c4.NNNN">`. Teg guruhlari:

- **File framework:** fayl karkasi (autorun tegi shu yerda).
- **Application Profile:** dasturlar ro'yxatida ko'rinadigan ma'lumot.
- **Installation Profile:** uch bosqich: Pre-Installation (bog'liqliklar, bottle turlari, yuklab olishlar), Installation, Post-Installation.
- **CD Profile:** CD'ni tanib olish.
- **Advanced Profile:** cheklangan shartli tarmoqlanish.

Ma'lum bo'lmagan joylar: bog'liqliklar XML'da aniq qanday e'lon qilinishi; imzolash sxemasi va ishonchsiz retsept ogohlantirishi `[tasdiqlanmagan]`. Forumdagi xodim javobiga ko'ra CodeWeavers har bir tie faylni sinab chiqa olmaydi `[forum]`.

Yangi retseptlar Preferences'dagi **Automatically Download New Installation Recipes** orqali avtomatik yuklanadi.

---

## 18. Texnik arxitektura

### 18.1 Wine bilan munosabat

| CrossOver | Wine asosi |
|---|---|
| 19.0.0 | 4.12 |
| 20 | 5.0 |
| 21.0 | 6.0 |
| 22.0 | 7.7 |
| 23.0 | 8.0.1 |
| 24.0 | 9.0 |
| 25.0 | 10.0 |
| 26.0 – 26.3 | 11.0 |
| 27 | topilmadi |

(19 dan 26 gacha rasmiy changelog'dan. Wikipedia 22.0 uchun 7.0 deb yozadi; changelog'da 7.7. Har reliz "so'nggi Wine'dan tanlangan yamoqlar"ni ham o'z ichiga oladi.)

Qatlamlar (yuqoridan pastga):

1. Windows dasturi (PE bajariluvchi fayl).
2. Wine DLL'lari: Windows API realizatsiyasi.
3. `ntdll` va Unix kutubxonalari: PE kodidan mezbon tizim chaqiruvlariga o'tish.
4. `wineserver`: jarayonlar, oqimlar, sinxronizatsiya obyektlari, registrni boshqaruvchi markaziy jarayon.
5. Drayverlar: macOS'da `winemac.drv` (oynalar, kiritish) va `winecoreaudio.drv` (ovoz).
6. Grafik tarjima: Direct3D dan Metal, Vulkan yoki OpenGL'ga.
7. Apple Silicon'da: x86_64 kodini ARM64'ga tarjima qiluvchi Rosetta 2.

### 18.2 32-bit dasturlar

- macOS Catalina 32-bit kodni olib tashlagach, CrossOver 19 **wine32on64** ni joriy qildi: o'zgartirilgan LLVM 32-bit dasturlar 64-bit Wine jarayonida ishlashi uchun o'tkazgich (thunk) kod hosil qiladi.
- Wine 11.0 (2026 yil yanvar) upstream **yangi WoW64** rejimini to'liq qo'llaydi: 32-bit Windows kodi 64-bit Unix kutubxonalari ustida ishlaydi `[ikkilamchi]`.
- Natija: CrossOver 26 da 32-bit bottle'lar eskirgan, 27 da yo'q. 32-bit dasturlarning o'zi 64-bit bottle ichida ishlayveradi.

### 18.3 Rosetta 2 va ARM64

- Windows dasturlari x86/x86_64. Apple Silicon'da CrossOver 26 ularni Rosetta 2 orqali ishlatadi.
- CodeWeavers 2026 yil iyun: "bizning ARM64 CrossOver build'imiz Rosetta 2'siz ishlaydi" `[ikkilamchi: blog parchasi]`.
- Mahalliy ARM64 preview 2026-07-31 da e'lon qilingan (rasmiy blog ro'yxati: "CrossOver Preview: The right to bear ARM64 on Mac", teglar orasida `fex`). Post kirishida: Rosetta 2 deyarli yo'qolganda ham CrossOver ishlashda davom etadi.
- **Apple'ning rasmiy jadvali.** Ishlab chiquvchilar hujjati: Rosetta "will be available through macOS 27" umumiy maqsadli vosita sifatida; undan keyin faqat Intel freymvorklariga tayanadigan eski, qo'llab-quvvatlanmayotgan o'yinlar uchun qism funksiyalar qoladi. Apple yordam sahifasi (2026-09-21): macOS 28 dan Rosetta faqat ayrim eski o'yinlar uchun. macOS 26.4 dan Rosetta'ga tayanadigan dasturlar ochilganda ogohlantirish chiqishi mumkin. CodeWeavers PortJump posti (2026-06-19): "In late 2027, macOS 28 will drop support for Rosetta".
- Rosetta AVX va AVX2 ni tarjima qiladi, AVX512 ni tarjima qilmaydi; yadro kengaytmalarini va x86_64 virtual mashinalarini ham tarjima qilmaydi (Apple hujjati).
- Mahalliy arm64 Wine'ning to'sig'i: 32-bit kod uchun manzil maydonining past 4 GB qismi kerak, arm64 macOS esa uni majburiy `__PAGEZERO` sifatida band qiladi. Chiqish yo'li `com.apple.developer.cross-architecture-support` entitlement'i, uni Apple o'z ixtiyori bilan beradi; CrossOver'ning arm64 build'ida u bor `[ikkilamchi: frankea/winecx-gptk README]`.

### 18.4 Grafik stek

| Qatlam | Tarjima | Platforma | CrossOver'dagi versiya |
|---|---|---|---|
| wined3d | Direct3D dan OpenGL yoki Vulkan'ga | hammasi | Wine bilan birga |
| DXVK | D3D10/11 dan Vulkan'ga | Linux; macOS'da MoltenVK ustida | 21.0: 1.7; 23.0: 1.10.3 |
| MoltenVK | Vulkan dan Metal'ga | macOS | 22.0: 1.1.10; 23.0: 1.2.3; 24.0: 1.2.5; 25.0: 1.2.10 |
| vkd3d | D3D12 dan Vulkan'ga | hammasi | 22.0: 1.4; 22.1: 1.5; 23.0: 1.8; 24.0: 1.10; 25.0: 1.14; 26.0: 1.18 |
| D3DMetal | D3D11/12 dan Metal'ga (Apple GPTK) | macOS, Apple Silicon | 23.5.0 da qo'shilgan; 25.0: 2.1; 26.0: 3.0 |
| DXMT | D3D11/10 dan Metal'ga | macOS, Apple Silicon | 25.0 da qo'shilgan; 26.0: v0.72 |

Upstream'dagi joriy versiyalar (2026-11-16) CrossOver 26.3 dagidan yangiroq: DXMT v0.80 (2026-04-23), MoltenVK 1.4.2 (Vulkan 1.4), DXVK 3.1.1, vkd3d-proton 3.1. macOS'da DXVK uchun eng ko'p sinalgan varianti hanuz 1.10.3.

Izohlar:

- wined3d tarixi: 21.0 dan macOS'da D3D10/11 o'yinlar uchun Vulkan backend'i sukut bo'yicha; 23.0 da geometriya sheyderlari va transform feedback uchun boshlang'ich qo'llov.
- DXMT (`github.com/3Shain/dxmt`) Apple Silicon'da Metal 3.1 ni mo'ljallaydi. Litsenziyasi: v0.80 gacha MIT, undan keyingi relizlar LGPL (v0.80 reliz eslatmasi).
- D3DMetal faqat CrossOver'dan olingan Wine build'larida ishlaydi: yuklanayotganda uning ichki unixcall qismini yamaydi `[ikkilamchi: frankea/winecx-gptk README]`.
- DXVK'ga nisbatan DXMT unumdorligi o'yinga qarab farq qiladi `[ikkilamchi, zaif manba]`.
- CrossOver 25.0 dan beri **Auto** rejimi har o'yin uchun sozlamalarni avtomatik yoqadigan bazaga tayanadi.
- macOS OpenGL'ni 4.1 da to'xtatgan; undan yuqorisini talab qiladigan dasturlar wined3d OpenGL yo'lida ishlamaydi `[tasdiqlanmagan]`.

### 18.5 Apple Game Porting Toolkit (GPTK)

| Versiya | Qachon | Yangiliklar |
|---|---|---|
| 1.0 | WWDC 2023 | D3DMetal birinchi marta `[tasdiqlanmagan]` |
| 2.0 | WWDC 2024 | AVX/AVX2, nurlar izlash `[ikkilamchi]` |
| 2.1 | | CrossOver 25.0 – 25.1.1 da |
| 3.0 | WWDC 2025; 2025-12-05 yangilangan | Metal 4, sparse buffer va teksturalar, MetalFX Frame Interpolation va Denoising `[ikkilamchi]`. CrossOver 26.0 da |
| 4 | WWDC 2026 (357-sessiya), beta | Agentli kodlash ko'nikmalari (`/plugin marketplace add apple/game-porting-toolkit`), baholash muhitida Metal 4 `[ikkilamchi: AppleInsider]`. Apple sahifasida "Download Game Porting Toolkit 4" tugmasi bor. Bitta sinovda (M4 Pro, 24 GB) GTA V 106 dan 176 kadr/s ga, Red Dead Redemption 2 60 dan 75 ga chiqqan; sozlamalar va aniqlik ko'rsatilmagan `[ikkilamchi]` |

CrossOver'ga D3DMetal birinchi marta 23.5.0 da (2023-09-27) kirgan: "Support for translation layer from the game porting toolkit", "New D3DMetal toggle".

D3DMetal Apple litsenziyasi (License.pdf) ostida; CodeWeavers uni qaysi shartlarda tarqatishi tasdiqlanmadi. Jamoat loyihalari (Gcenx, Sikarugir) uni baholash uchun deb belgilaydi va tijoriy portlarda ishlatib bo'lmasligini yozadi.

### 18.6 Sinxronizatsiya

Windows dasturlari sinxronizatsiya obyektlaridan (mutex, event, semaphore) juda ko'p foydalanadi. Wine'da ular sukut bo'yicha `wineserver` orqali o'tadi, bu sekin. Tezlashtirish usullari:

- **ESync:** eventfd asosida.
- **MSync:** Mach semaforlari asosida, macOS uchun. CrossOver'da bottle kaliti.
- **NTSync:** Linux yadrosi moduli, Windows NT sinxronizatsiya semantikasini yadro ichida amalga oshiradi. Wine 11 qo'llaydi, CrossOver 26 yadro 6.14+ da ishlatadi.

### 18.7 Boshqa tizimlar

- **Ovoz:** macOS'da `winecoreaudio.drv` (CoreAudio). Linux'da PulseAudio va ALSA `[tasdiqlanmagan]`.
- **.NET:** Wine Mono 21.0 dan birga keladi: 21.1 da 6.3, 22.0 da 7.2, 23.0 da 7.4, 24.0 da 8.1, 25.0 da 9.4.0, 26.0 da 10.4.1. Haqiqiy .NET Framework kerak bo'lsa, retsept bog'liqlik sifatida o'rnatadi `[tasdiqlanmagan]`.
- **Media:** macOS'da GStreamer qo'llovi 23.5.0 dan. Wine'da H.264 dekodlash GStreamer `vtdec` orqali, faqat `stream-format=avc` bilan `[ikkilamchi]`.
- **Kontrollerlar** (rasmiy maqola): Xbox One, Xbox Series, DualShock 4 va DualSense muntazam sinaladi. O'yin kamida Windows XInput'ni qo'llashi kerak. Windows kontroller drayverlarini o'rnatib bo'lmaydi, chunki ostida Windows yo'q. Maslahatlar: simli Sony kontrollerida **Disable hidraw**; Bluetooth o'rniga USB; Steam'da Settings > Controller sozlamasini tekshirish. Tarixi: 22.1.0 da SDL yangilanishi, 25.1.0 da simli Xbox One va 8BitDo Pro tuzatilgan.
- **Chop etish:** macOS Sonoma'da 23.6.0 dan ishlaydi. Ba'zi printerlarda, ayniqsa PostScript'siz purkagichlarda, Windows dasturidan chop etish ishlamaydi. Rasmiy aylanma yo'l: Mac'ga **PDFwriter** virtual printerini o'rnatib, PDF'ga chop etish va uni Preview'dan chiqarish.
- **Oynalar:** Stage Manager 23.7.0 dan qo'llanadi; Dark Mode 21.0 dan.
- **Shriftlar, wine-gecko (MSHTML), bufer va sudrab tashlash:** tadqiq qilinmadi `[tasdiqlanmagan]`.

---

## 19. O'yinlar: launcherlar va anti-cheat

### Launcherlar

Changelog bo'yicha qo'llab-quvvatlash holati:

| Launcher | Holat |
|---|---|
| Steam | Ishlaydi; Install ekranidagi Steam plitkasi retsept orqali bottle turi, bog'liqliklar va yuklab olishni o'zi sozlaydi. 20.0.0 da Steam qo'llovi yaxshilangan; 21.2.0 va 25.1.0 da ulanish, 25.1.0 da MSync bilan yuklab olish tuzatilgan |
| Battle.net | Ishlaydi; har bir Battle.net yangilanishidan keyin tez-tez tuzatish chiqadi (23.7.1, 24.0.4, 24.0.6, 24.0.7, 26.1.0) |
| Epic Games Store | 25.0.0 dan qo'llanadi (Mac); 26.3.0 da yuklab olish tuzatilgan |
| GOG Galaxy | 25.0.0 dan qo'llanadi; 26.3.0 da yuklanmaslik tuzatilgan |
| EA app | 23.0.0 dan qo'llanadi; 25.0.1 va 25.1.0 da tuzatishlar |
| Ubisoft Connect | 22.1.0, 24.0.4 va 25.1.0 da tuzatishlar |
| Rockstar Games Launcher | 21.1.0 dan qo'llanadi (GTA V bilan); 21.2.0 va 24.0.5 da tuzatishlar |
| HoYoPlay | 24.0.4 dan ishlaydi |
| Heroic Games Launcher | Yordam markazida "Using the Heroic Games Launcher with CrossOver" maqolasi bor (mazmuni o'qilmadi) |

Qonuniyat: launcherlar o'zini yangilaganda CrossOver'da buzilib turadi va CodeWeavers nuqtali reliz bilan tuzatadi. Shuning uchun faol yangilanish muddati o'yinchilar uchun muhim.

Changelog'da nomi tilga olingan o'yinlar: Helldivers 2, Kingdom Come: Deliverance II, Clair Obscur: Expedition 33, Cronos: The New Dawn, Death Stranding 2, Diablo IV, Red Dead Redemption 2, Street Fighter 6, The Last of Us Part 1, Tekken 8, Age of Mythology: Retold, Path of Exile 2, Elite Dangerous, Far Cry 6, Horizon Zero Dawn, Anno 1800, Planet Zoo, Guild Wars 2, Tomb Raider I-III Remastered.

### Anti-cheat

Rasmiy pozitsiya (yordam markazi, 2025-03-14):

- Anti-cheat tizimlari Windows'ning juda past darajasida ishlaydi va CrossOver tarjima qatlami bilan mos emas; o'yin ishga tushmaydi.
- CodeWeavers anti-cheat muammolarini qo'llab-quvvatlamaydi va tuzatishga urinmaydi. Sabab sifatida DMCA keltiriladi: himoya va anti-cheat'ni aylanib o'tish qonunan mumkin emas.
- Yagona yo'l: o'yin ishlab chiquvchisi o'z tomonida o'zgartirish kiritishi.

Ma'lum holatlar:

| O'yin | Anti-cheat | Holat |
|---|---|---|
| Elden Ring | Easy Anti-Cheat | Onlayn ishlamaydi; EAC o'chirilsa yakka rejim ishlashi xabar qilingan `[forum]` |
| The Crew 2 | BattlEye | Bloklangan |
| War Thunder | BattlEye | Ishga tushmaydi `[forum]` |
| The Division 2 | | Anti-cheat xatosi |
| Star Wars: Squadrons | EAC | O'ynab bo'lmaydi |
| Fall Guys | EAC | Qotadi |
| Insurgency: Sandstorm | | Onlayn 1-2 daqiqadan keyin uziladi |
| VRChat | | Ishga tushmaydi |
| Apex Legends | | "Failed to load the anti-cheat module" (CrossOver 25) `[forum]` |
| Marvel Rivals | | Anti-cheat'ga qaramay ishlagani xabar qilingan `[forum]` |

CodeWeavers 2026-08-31 da shu mavzuda alohida blog posti chiqargan: "Why do most games with anti-cheat not work with CrossOver Mac?".

Mashhur o'yinlarning Linux'dagi (Wine/Proton) holati; macOS'da bundan yaxshi bo'lishi kutilmaydi:

| O'yin | Anti-cheat | Linux holati | Manba |
|---|---|---|---|
| Valorant | Vanguard (yadro) | Bloklangan | areweanticheatyet, 2024-01 |
| League of Legends | Vanguard | Ishlamaydi (Riot 2024 da e'lon qilgan) | `[ikkilamchi]` |
| Fortnite | EAC | Bloklangan | areweanticheatyet, 2024-06 |
| Apex Legends | EAC | Bloklangan | areweanticheatyet, 2024-10 |
| Rainbow Six Siege | BattlEye | Bloklangan (onlayn) | areweanticheatyet, 2024-03 |
| Call of Duty Warzone | Ricochet (yadro) | Ishlamaydi | `[ikkilamchi]` |
| Battlefield 6 | EA Javelin | Ishga tushishdan bosh tortadi | `[ikkilamchi]` |
| PUBG | BattlEye | Ishlamaydi (yozuv 2021 yildan, eskirgan bo'lishi mumkin) | areweanticheatyet |
| Roblox | Hyperion | Wine'ni sukut bo'yicha bloklaydi | `[ikkilamchi]` |
| Genshin Impact | miHoYo Protect | Proton'da ishlagani xabar qilingan | `[ikkilamchi]` |

GTA Online, Destiny 2, CS2, Dota 2, Rust, Escape from Tarkov, EA Sports FC bo'yicha tekshirilgan ma'lumot yo'q.

Nega Linux'da ba'zan ishlaydi: Steamworks hujjati bo'yicha Proton Easy Anti-Cheat va BattlEye'ni qayta kompilyatsiyasiz qo'llaydi, lekin har o'yin uchun ishlab chiquvchi buni o'zi yoqishi kerak. Yadro darajasidagi yechimlar Proton'da ham qo'llanmaydi. macOS uchun bunday yoqish mexanizmi tasdiqlanmagan.

---

## 20. Moslik bazasi, reytinglar, qo'llab-quvvatlash

### Reyting tizimi (yulduzlar)

| Yulduz | Nomi | Ma'nosi |
|---|---|---|
| 0 | Unknown / Unrated | Baholanmagan; har bir dastur shu holatdan boshlanadi |
| 1 | Will Not Install | O'rnatuvchi ishlamaydi |
| 2 | Installs, Will Not Run | O'rnatiladi, lekin ishga tushganda yopiladi yoki qotadi |
| 3 | Limited Functionality | Ishlaydi, lekin jiddiy kamchiliklar bilan |
| 4 | Runs Well | Asosiy funksiya ishlaydi, mayda nosozliklar |
| 5 | Runs Great | Deyarli hammasi ishlaydi, Windows'dagidek |

Baho foydalanuvchi qayergacha yeta olganiga asoslanadi: o'rnatish, ishga tushirish, keyin funksionallik. Baholarni xodimlar va foydalanuvchilar yuboradi; tekshirish jarayoni tavsiflanmagan. Tizim yulduzlarda, medallarda emas.

### Qo'llab-quvvatlash kanallari

- Yordam markazi: `support.codeweavers.com`.
- Compatibility Center: har bir dastur sahifasi, maslahatlar va forum yorlig'i.
- Email orqali texnik yordam (faol litsenziya muddatida).
- Forumlar.
- CrossOver Preview: CrossOver+ va Life xaridorlariga beriladi (do'kon sahifasida ikkala mahsulotda "Access to CrossOver Preview"). Nightly build'lar faqat xabar qilingan xatoni takrorlash uchun `[ikkilamchi]`.
- BetterTester / Advocate dasturi: joriy qoidalari tasdiqlanmadi (faqat 2021-2024 sahifalari).

---

## 21. Cheklovlar

Tasdiqlangan:

- **Yadro darajasidagi anti-cheat** ishlamaydi va tuzatilmaydi ([19-bo'lim](#19-oyinlar-launcherlar-va-anti-cheat)).
- **Windows control panellarining aksariyati** qo'llab-quvvatlanmaydi.
- **D3DMetal va DXMT faqat macOS'da**, D3DMetal 3.0 faqat Apple Silicon'da.
- **DLSS** faqat D3DMetal yoki DXMT bilan.
- **High Resolution Mode** ba'zi dasturlarni noto'g'ri chizadi.
- **Antivirus** bottle fayllarini o'chirib yuborishi mumkin.
- **Tarmoq disklari va boshqa fayl tizimli tashqi disklar** bottle saqlash uchun yaramaydi.
- **O'zini yangilaydigan launcherlar** vaqti-vaqti bilan buziladi.
- **O'rnatishni bekor qilish** bottle'ni tuzatib bo'lmas holatga keltirishi mumkin.
- **ChromeOS:** faqat Linux muhiti orqali, Intel protsessor, Downloads papkasi nozikligi.
- **Windows drayverlari** o'rnatilmaydi (kontroller drayverlari misolida rasmiy tasdiqlangan). Wine'da yadro rejimi yo'q, shuning uchun `.sys` drayverlar yuklanmaydi; Steamworks hujjati ham yadro darajasidagi yechimlar qo'llanmasligini aytadi.
- **AVX512** talab qiladigan kod ishlamaydi: Rosetta AVX va AVX2 ni tarjima qiladi, AVX512 ni yo'q.
- **Chop etish** ba'zi printerlarda ishlamaydi (PDFwriter aylanma yo'li).
- **DXMT** faqat Direct3D 10 va 11; DX12 uchun D3DMetal kerak.
- **Rosetta 2 ga bog'liqlik:** CrossOver 26 x86_64, macOS 28 dan Rosetta deyarli yo'qoladi ([23-bo'lim](#23-crossover-27-va-arm64-kelajagi)).

Qisman tasdiqlangan:

- **Nusxa himoyasi va DRM:** Valve Steamworks hujjatida anti-tamper va DRM'ni tavsiya qilmaydi va ularni Wine muhitida to'liq ishlatish vaqt olishini yozadi. Eski Wine wiki sahifasi bo'yicha SafeDisc 2.x ishlaydi, SafeDisc 3.x, SecuROM 5 va yuqori, StarForce ishlamaydi `[ikkilamchi, eskirgan bo'lishi mumkin]`. Denuvo Anti-Tamper: CrossOver 23.5.0 dan Sonoma'da ishlaydi (changelog).
- **USB litsenziya kalitlari:** 2018 yilgi WineHQ xato hisoboti bo'yicha oddiy Wine HASP, Sentinel va Hardlock dongle'larini qo'llamaydi `[ikkilamchi, eski]`.
- **OpenGL:** macOS'da eskirgan deb e'lon qilingan (10.14 dan) va 4.1 Core darajasida to'xtagan `[ikkilamchi]`; 4.3 va yuqorisini talab qiladigan dasturlar wined3d OpenGL yo'lida ishlamaydi. Zink (MoltenVK ustida OpenGL) macOS'da "tajribaviy, juda cheklangan" (Mesa hujjati).

Tasdiqlanmagan `[tasdiqlanmagan]`:

- Microsoft Store / UWP / MSIX dasturlari va PC Game Pass;
- D3DMetal'ning aniq DirectX 12 feature level'i, mesh shader, DirectStorage va HDR qo'llovi;
- Media Foundation va o'yin ichidagi video roliklar.

Unumdorlik: 2024 – 2026 yillar uchun CrossOver yoki GPTK'ni mahalliy Windows, Parallels yoki mahalliy macOS portlari bilan solishtirgan ishonchli o'lchov topilmadi. Apple faqat Rosetta tarjimasi "vaqt oladi" va dasturlar sekinroq ishlashi mumkinligini aytadi, raqam bermaydi.

---

## 22. Versiyalar tarixi va changelog

### Asosiy relizlar

| Versiya | Sana | Wine | Asosiy yangilik |
|---|---|---|---|
| 19.0.0 | 2019-12-10 | 4.12-1 | Catalina'da 32-bit dasturlar; Python 3; FAudio 19.10 |
| 20.0.0 | 2020-10-13 | 5.0 | ChromeOS uchun maxsus qo'llov (konteynerlar); Big Sur; Mac'da DirectX 11 o'yinlar; Steam yaxshilangan; yangi brending |
| 20.0.1 – 20.0.4 | 2020-11 – 2021-01 | 5.0 | Apple Silicon'ga tayyorgarlik va M1 tuzatishlari |
| 21.0.0 | 2021-08-03 | 6.0 | DXVK 1.7; Wine Mono birga keladi; Dark Mode; D3D10/11 uchun wined3d Vulkan backend'i sukut bo'yicha |
| 21.1.0 | 2021-11-29 | 6.0 | Rockstar Games Launcher va GTA V; macOS Monterey |
| 22.0.0 | 2022-08-23 | 7.7 | Interfeys to'liq qayta ishlangan; vkd3d 1.4; MoltenVK 1.1.10; Linux'da DirectX 12 boshlanishi |
| 22.1.0 | 2023-02-14 | 7.7 | Mac'da 32-bit DirectX 10/11 o'yinlar; vkd3d 1.5; SDL yangilanishi |
| 23.0.0 | 2023-08-16 | 8.0.1 | Mac'da DirectX 12 boshlanishi (Diablo II: Resurrected, Diablo IV); DXVK 1.10.3; vkd3d 1.8; MoltenVK 1.2.3; EA App; dasturlarni o'chirish imkoniyati |
| 23.5.0 | 2023-09-27 | 8.0.1 | **Game Porting Toolkit tarjima qatlami, D3DMetal kaliti**; Sonoma; Baldur's Gate 3; Denuvo o'yinlari; GStreamer |
| 23.6.0 | 2023-10-18 | 8.0.1 | Counter-Strike 2, Warframe; Sonoma'da chop etish |
| 23.7.0 | 2023-11-27 | 8.0.1 | **MSync**; MoltenVK tezlashtirilgan; Fallout 4; Stage Manager |
| 24.0.0 | 2024-02-22 | 9.0 | Wine Mono 8.1, vkd3d 1.10, MoltenVK 1.2.5 |
| 25.0.0 | 2025-03-11 | 10.0 | D3DMetal 2.1, DXMT, har o'yin uchun sozlamalar bazasi, GOG va Epic |
| 26.0.0 | 2026-02-10 | 11.0 | D3DMetal 3.0, DXMT v0.72, NTSync, Tahoe interfeysi |
| 27 | e'lon 2026-06-11 | ? | Intel Mac va 32-bit bottle'lar olib tashlanadi; ARM64 |

### To'liq changelog (rasmiy sahifadan)

**26.3.0 (2026-07-21)**
- Diablo IV o'yin yangilanishidan keyin ishga tushmasligi tuzatildi.
- Mac'da Epic Games Launcher yuklab olishlari ishlamasligi tuzatildi.
- GOG Galaxy klienti yuklanmasligi tuzatildi.

**26.2.0 (2026-06-09)**
- Helldivers 2 o'yin yangilanishidan keyin ishga tushmasligi tuzatildi.
- 32-bit bottle'lar uchun qo'shimcha ogohlantirishlar.

**26.1.0 (2026-04-09)**
- macOS'da Death Stranding 2 uchun aylanma yechim.
- Ko'plab Unity o'yinlarida sichqoncha kiritishi tuzatildi.
- Quicken'da "Add account" oynasi buzilishi tuzatildi.
- Ba'zi foydalanuvchilarda Battle.net o'rnatilmasligi tuzatildi.

**26.0.0 (2026-02-10)**
- Yadro: Wine 11.0 (6000 dan ortiq yaxshilanish); Wine Mono 10.4.1; vkd3d 1.18.
- macOS: D3DMetal 3.0; DXMT v0.72; macOS Tahoe uchun interfeys. Ko'plab o'yinlar tuzatildi: Helldivers 2, Kingdom Come: Deliverance II, Clair Obscur: Expedition 33, Age of Empires IV: Anniversary Edition, Warhammer 40,000: Darktide, God of War Ragnarök, Starfield, Final Fantasy VII Rebirth, Company of Heroes 3, Planet Coaster 2, CloverPit, PowerWash Simulator 2, Silent Hill f, Jurassic World Evolution 2, Assetto Corsa EVO, The Outer Worlds 2, Final Fantasy Tactics - The Ivalice Chronicles, Trails in the Sky 1st Chapter, Mafia: The Old Country, Hell is Us, Cronos: The New Dawn.
- Linux: qo'llaydigan yadrolarda NTSync.

**25.1.1 (2025-09-15)**
- macOS: Intel Mac'larda Tahoe uchun tuzatish.

**25.1.0 (2025-08-12)**
- macOS: Ubisoft; EA app; simli Xbox One kontrollerlari; 8BitDo Pro kontrollerlari; boshqa kontroller muammolari; MSync yoqilganda Steam yuklab olishlari; Steam ulanish muammolari.
- Linux: Office 365 Outlook'ga kirish; Office 2016 qulashi.

**25.0.1 (2025-04-23)**
- Hamma platforma: Guild Wars 2 qulashi.
- macOS: oxirgi EA App yangilanishi; ikkilangan kiritish.

**25.0.0 (2025-03-11)**
- Yadro: Wine 10.0 (5000 dan ortiq yaxshilanish); Wine Mono 9.4.0; vkd3d 1.14.
- macOS: MoltenVK 1.2.10; sozlamalarni har o'yin uchun avtomatik yoqadigan yangi baza; Red Dead Redemption 2; DXMT qo'shildi; GOG Galaxy va Epic Games Store.
- D3DMetal 2.1, Apple Silicon'da yangi o'yinlar: Street Fighter 6, Need for Speed Heat, Nioh 2 - The Complete Edition, Teardown, Age of Wonders 4, Dragon's Dogma 2, The Last of Us Part 1.
- Boshqa tuzatilgan o'yinlar: Tekken 8, Age of Mythology: Retold, Path of Exile 2, Elite Dangerous, Monster Hunter Rise, Hero's Land, Manor Lords, Fallout 76, Far Cry 6.

**24.0.7 (2025-01-28):** macOS: Battle.net yangilanishi uchun qo'shimcha tuzatish.

**24.0.6 (2025-01-21):** hamma platforma: Battle.net yangilanishi. Linux: Fedora 41 da ro'yxatdan o'tish.

**24.0.5 (2024-09-11):** macOS: Rockstar Games Launcher yangilanishi.

**24.0.4 (2024-07-03):** macOS: Diablo IV yangilanishi; Ubisoft Connect yangilanishi; HoYoPlay launcher ishlaydi. Hamma platforma: Battle.net doim yangilanish ko'rsatishi.

**24.0.3 (2024-05-15):** macOS: `explorer.exe` qotishi.

**24.0.2 (2024-04-29):** Linux: ChromeOS'da parol so'rovi.

**24.0.1 (2024-03-21):** macOS: Diablo IV yangilanishi; Tomb Raider I-III Remastered.

**24.0.0 (2024-02-22)**
- Yadro: Wine 9.0 (7000 dan ortiq yaxshilanish); Wine Mono 8.1; vkd3d 1.10; interfeys yaxshilanishlari.
- macOS: Horizon Zero Dawn, Anno 1800, Planet Zoo, The Binding of Isaac: Rebirth, Age of Empires III: Definitive Edition; MoltenVK 1.2.5.
- Linux: yangi Office 365 o'rnatuvchilari ishlaydi; PowerPoint 2016/365 qulashlari.

**23.7.1 (2023-12-05):** hamma platforma: Battle.net yangilanishi.

**23.7.0 (2023-11-27)**, macOS: MoltenVK unumdorligi yaxshilangan; MSync qo'shildi; Fallout 4 va Steam'dagi Diablo IV o'ynaladi; Marvel Snap'da Apple login; Stage Manager qo'llanadi.

**23.6.0 (2023-10-18)**: macOS: Counter-Strike 2 va Warframe; Sonoma'da chop etish ishlaydi. Hamma platforma: Quicken yangilanishdan keyin qulamaydi.

**23.5.0 (2023-09-27)**
- macOS: Game Porting Toolkit tarjima qatlami; yangi D3DMetal kaliti; macOS Sonoma; Baldur's Gate 3 Ventura va Sonoma'da; Denuvo o'yinlari Sonoma'da; GStreamer qo'llovi.
- Linux: Debian 13, openSUSE 15.1, Ubuntu 23.10 uchun moslik.

**23.0.1 (2023-09-07)**, macOS: Quicken qulashlari; reytinglarni CrossOver ichidan yuborish tiklandi; Monterey'da Steam qora ekrani; o'rnatishdan keyingi tasodifiy qulash.

**23.0.0 (2023-08-16)**
- Yadro: Wine 8.0.1 (5000 dan ortiq yaxshilanish) va so'nggi Wine'dan tanlangan yamoqlar; Wine Mono 7.4; vkd3d 1.8; DXVK 1.10.3; EA App qo'llovi; dasturlarni o'chirish imkoniyati.
- macOS: DirectX 12 o'yinlari uchun boshlang'ich qo'llov (Diablo II: Resurrected, Diablo IV); geometriya sheyderlari va transform feedback; MoltenVK 1.2.3.
- Linux: Wayland'da Office 365; Diablo IV.

**22.1.1 (2023-04-04):** WeChat ishga tushishdagi qulash; macOS Ventura'da xotira muammolari.

**22.1.0 (2023-02-14)**
- Yadro: wined3d yaxshilanishlari; vkd3d 1.5; Ubisoft Connect yangilanishi.
- macOS: 32-bit DirectX 10/11 o'yinlar; SDL yangilanishi bilan kontrollerlar; bo'sh oynalar muammosi; GTA Online qulashi.
- Linux: Adobe Acrobat Reader 11; Fedora 37 va openSUSE Tumbleweed bog'liqliklari.

**22.0.1 (2022-09-27):** .NET o'rnatish xatolari; macOS'da Quicken va MetaTrader qotishi, Xbox simsiz kontrollerlari; Linux'da RPM yangilanishi.

**22.0.0 (2022-08-23)**
- Yadro: Wine 7.7 (10 000 dan ortiq yaxshilanish); **interfeys to'liq qayta ishlangan**; Wine Mono 7.2; vkd3d 1.4.
- ChromeOS: Office 2016/365 xatolari.
- macOS: o'yin unumdorligi; MoltenVK 1.1.10; Rocket League wined3d bilan o'ynaladi.
- Linux: DirectX 12 uchun boshlang'ich qo'llov; Office 2016/365 xatolari.

**21.2.0 (2022-03-22)**: Wine Mono 7.0; wined3d; Halo: Master Chief Collection'da ovoz; Steam ulanish vaqti. macOS: Unity o'yinlarida sichqoncha; M1'da Rockstar Games Launcher va Quicken. ChromeOS va Linux: Office 365 chizish muammolari.

**21.1.0 (2021-11-29)**: Rockstar Games Launcher va Grand Theft Auto V; Wine Mono 6.3; wined3d; Quicken. macOS: Monterey qo'llovi. Linux: Outlook 2016/365 tiklandi.

**21.0.0 (2021-08-03)**
- Yadro: Wine 6.0 (8300 yaxshilanish); DXVK 1.7; Wine Mono endi birga keladi.
- macOS: Dark Mode; D3D10/11 o'yinlar uchun Vulkan WineD3D backend'i sukut bo'yicha; Skyrim SE M1'da WineD3D bilan.
- ChromeOS: tezroq ishga tushish. Linux: Office 2016/365 ko'p monitorli sozlamalar va faollashtirish; FL Studio 20.8.

**20.0.4 (2021-01-27)**: macOS: Big Sur kalitlar zanjiri; Intel Mac'da Bluetooth Xbox One kontrolleri; Apple Silicon'da 640x480 rejimini so'ragan eski o'yinlar uchun aylanma yo'l; CrossTie fayl bosilganda qulash. Linux: Ubuntu 20.10; tajribaviy esync xatosi.

**20.0.2 (2020-11-11)** va **20.0.1 (2020-11-10)**: Office 365 ga kirish; GOG o'yinlarida qora ekran; World of Warcraft va Fallout 76 qulashlari. macOS: Apple Silicon'ga tayyorgarlik; Sonic Generations, Team Fortress 2, Skyrim grafikasi; Xbox 360 kontrolleri. ChromeOS va Linux: 64-bit bottle'larda regedit.

**20.0.0 (2020-10-13)**
- Yadro: Wine 5.0 (3400 yaxshilanish); CrossOver ichida dasturlarni baholash; yangi brending va ko'rinish.
- ChromeOS: konteynerlar orqali maxsus qo'llov.
- macOS: Big Sur (macOS 11); Steam va Steam o'yinlari yaxshilangan; DirectX 11 o'yinlar.
- Linux: CrossOver o'zini yangilay oladi.

**19.0.2 (2020-06-12)** va **19.0.1 (2020-01-14)**: Microsoft Office o'rnatuvchilari; 64-bit bottle'larda .NET; FAudio. macOS: antivirus buzgan bottle'larni tuzatish vositasi (Repair Bottles); imzolash va hardening qayta ko'rilgan.

**19.0.0 (2019-12-10)**: macOS Catalina (10.15) da 32-bit dasturlar; Wine 4.12-1 (5000 yaxshilanish); FAudio 19.10; Python 3.

Changelog sahifasi 13.0.0 (2013-11-12) gacha boradi.

---

## 23. CrossOver 27 va ARM64 kelajagi

2026-06-11 da CodeWeavers "CrossOver 27 da nima qoladi va nima ketadi" postini e'lon qilgan `[ikkilamchi: blog parchasi va yangilik saytlari]`:

- **Intel Mac qo'llovi tugaydi.** Faqat Apple Silicon. Intel foydalanuvchilari CrossOver 26 da qoladi, u boshqa yangilanmaydi.
- **Minimal macOS: Sonoma (14).** CodeWeavers bo'yicha foydalanuvchilarning 97% i Sonoma yoki yangiroqda.
- **32-bit bottle'lar ishlamaydi.** Yangilangandan keyin mavjud 32-bit bottle'larga kirib bo'lmaydi. Yangilashdan oldin ma'lumotlarni eksport qilish tavsiya etiladi.
- **ARM64 build'lar** Mac va Linux uchun; Rosetta 2'siz ishlaydi, x86 tarjimasi FEX orqali.

**Reliz holati: CrossOver 27 hali chiqmagan** (2026-11-16 holatiga). Dalillar:

- rasmiy changelog'ning eng yangi yozuvi 26.3.0 (2026-07-21), 27 yozuvi yo'q;
- Homebrew `crossover` cask'i 26.3.0 ni ko'rsatadi;
- rasmiy manba sahifasi "Download FOSS Code for CrossOver 26.3.0" deydi;
- rasmiy blog ro'yxatida 27 reliz posti yo'q. Oxirgi tegishli postlar: 2026-06-19 PortJump (macOS 28 Rosetta'ni tashlaydi), 2026-07-31 ARM64 Preview, 2026-08-24 "Why app and game updates can break support for CrossOver", 2026-08-31 anti-cheat.

Chiqish sanasi haqidagi taxminlar ikkilamchi manbalarda turlicha ("2026 oxiri", "2027 boshi"); bir sayt e'lon sanasini reliz sanasi deb xato ko'rsatgan. Forumda 2026-08-21 sanali "CrossOver 27 Preview ARM64" build'i tilga olingan, u hali Intel va ARM64 Wine'ni birga olib yurgan va Rosetta talab qilgan `[forum]`. ARM64 Preview macOS 26.5 yoki yangirog'ini talab qilishi va D3DMetal'siz ekani bitta parchada aytilgan `[tasdiqlanmagan]`.

Amaliy xulosa: barqaror versiya 26.3.0; 27 holatini `codeweavers.com/crossover/changelog` dan tekshiring. 32-bit bottle'ingiz bo'lsa, yangilashdan oldin **Export Bottle to Archive** qiling va dasturni 64-bit bottle'ga qayta o'rnating.

---

## 24. Muqobillar

| Vosita | Yondashuv | Narx | Holat (2026) |
|---|---|---|---|
| **CrossOver** | Wine, grafik interfeys, retseptlar, texnik yordam | pullik, 14 kun sinov | faol |
| Wine (WineHQ, Gcenx build'lari) | Sof Wine, qo'lda sozlash | bepul | faol; Gcenx `wine-devel`/`wine-staging` 11.21 (2026-10-31), `wine-stable` 11.0_1; wine-mono va wine-gecko birga, 11.20 dan GStreamer ham. Upstream Wine: 11.0 barqaror (2026-01-13), ishlab chiqish tarmog'i 11.22 |
| Whisky | Wine va GPTK uchun oddiy Mac interfeysi (SwiftUI, GPL-3.0) | bepul | arxivlangan: GitHub bo'yicha 2025-05-11 (oxirgi reliz 2.3.5, 2025-04-05); muallif CrossOver'ni tavsiya qilgan |
| frankea/Whisky | Whisky'ning faol jamoat fork'i | bepul, GPL-3.0 | v3.10.1 (2026-11-15); dvigateli Wine 11.19 + CrossOver 26.3 yamoqlari, DXMT 0.80, DXVK 1.10.3, MoltenVK 1.4.2; GPTK'ni foydalanuvchi import qiladi; macOS 27 da sinalgan; 80 dan ortiq o'yin uchun tayyor sozlamalar |
| Sikarugir (avval Kegworks) | Wineskin vorisi, dasturni `.app` ga o'rovchi | bepul | faol (2026-11); macOS 14.6+; D3DMetal, DXMT (sukut), DXVK kalitlari |
| Apple GPTK to'g'ridan-to'g'ri | D3DMetal, terminal orqali | bepul (baholash litsenziyasi) | GPTK 4 beta |
| Heroic Games Launcher | Epic, GOG, Amazon uchun launcher | bepul, GPL-3.0 | v2.22.4 (2026-10-15); Apple Silicon'da Wine-Staging + DXMT ni tavsiya qiladi |
| Mythic | Mac uchun o'yin launcheri, GPTK asosida | bepul, GPL-3.0 | macOS 14+ |
| Porting Kit | Tayyor o'rovchilar | bepul `[tasdiqlanmagan]` | |
| PlayOnMac | Wine interfeysi | | topilmadi |
| Proton / Steam Play | Linux'da Steam ichidagi Wine (Valve va CodeWeavers) | bepul | faol |
| Bottles | Linux'da Wine prefiks boshqaruvchisi | bepul, GPL-3.0 | 67.6 (2026-11-04) |
| Lutris | Linux o'yin menejeri | bepul, GPL-3.0 | v0.5.22 (2026-02-25); ochiq API'da 15 000 dan ortiq o'rnatuvchi |
| Parallels Desktop | Virtual mashina, ARM Windows 11 | Standard 99.99 USD/yil, Pro 119.99, Business 149.99 `[ikkilamchi]`; 14 kun sinov | faol |
| VMware Fusion | Virtual mashina | shaxsiy foydalanishga bepul `[ikkilamchi]` | |
| UTM | QEMU asosidagi virtual mashina | bepul, ochiq kodli | |
| GeForce NOW | Bulutli o'yin | Free 0; Performance 9.99 USD/oy; Ultimate 19.99 USD/oy `[ikkilamchi]` | faol |

Qachon nima:

- **CrossOver:** Windows'ni o'rnatmasdan, kam resurs bilan, tayyor retseptlar va texnik yordam bilan dastur va o'yin ishlatish. DX12 o'yinlari Mac'da D3DMetal orqali.
- **Virtual mashina (Parallels):** yuqori moslik kerak bo'lgan ish dasturlari, drayver talab qiladigan dasturlar. Windows litsenziyasi va ko'proq RAM kerak; Parallels'da DirectX 11.1 chegarasi `[ikkilamchi]`.
- **GeForce NOW:** anti-cheat'li onlayn o'yinlar (bulutda haqiqiy Windows ishlaydi).
- **Bepul Wine vositalari:** qo'lda sozlashga tayyor bo'lsangiz.

---

## 25. CodeWeavers kompaniyasi

- Bosh ofis: Saint Paul, Minnesota, AQSH.
- Asos solingan yili `[ziddiyat]`: CodeWeavers haqidagi Wikipedia maqolasi 1996 (konsalting firmasi sifatida), CrossOver maqolasi 2000 (venchur sarmoya bilan) deydi.
- CrossOver Office 2002 yilda chiqqan; venchur mablag' tugagach Wine ishini CrossOver savdosi moliyalagan `[ikkilamchi]`.
- 2023 yil aprelda kompaniya xodimlar mulki trastiga (employee ownership trust) o'tgan. Asoschi Jeremy White 7 yil aksiyador bo'lib qoladi, keyin trast yagona egaga aylanadi. Bosh direktor: James Ramey.
- Valve bilan 2016 yildan beri Proton ustida shartnoma asosida ishlaydi; yaxshilanishlarning ko'pi upstream Wine'ga qaytadi.
- Boshqa mahsulotlari (rasmiy sayt navigatsiyasi): **PortJump** (dastur yoki o'yinni Mac va Linux'ga ko'chirish xizmati) va **ExecMode** (texnik konsalting).
- 2026 yil sentyabr: asoschi Jeremy White blogga qaytgan ("I flunked retirement") va Docker/Kubernetes orqali Windows dasturlarini yoyishga qaratilgan "CrossOver Enterprise Cloud Edition" g'oyasi uchun yordam so'ragan.
- Wine commit'laridagi ulushi tasdiqlanmadi.

---

## 26. Tasdiqlanmagan va ziddiyatli joylar

### 2026-11-16 da tasdiqlanganlar (avval ochiq turgan)

| Savol | Javob | Manba |
|---|---|---|
| CrossOver 27 chiqqanmi | Yo'q; oxirgi reliz 26.3.0 | rasmiy changelog, manba sahifasi, Homebrew cask |
| Narxlar | CrossOver+ 54.00 USD, Life 494.00 USD | rasmiy do'kon |
| D3DMetal va MSync qachon qo'shilgan | 23.5.0 va 23.7.0 | rasmiy changelog |
| 22.0 ning Wine asosi | 7.7 | rasmiy changelog |
| Rosetta 2 jadvali | macOS 27 gacha; macOS 28 dan faqat eski o'yinlar | Apple hujjati va yordam sahifasi |
| `WINEESYNC`, `WINEMSYNC`, `MTL_HUD_ENABLED`, `ROSETTA_ADVERTISE_AVX`, `D3DM_SUPPORT_DXR` | Mavjud va ishlatiladi | Whisky manba kodi |
| CrossOver'ni o'chirish | Removal Tool va qo'lda yo'llar | rasmiy yordam maqolasi |
| Chop etish, klaviatura, kontrollerlar | 7, 18.7-bo'limlarda | rasmiy yordam maqolalari |
| Whisky arxivlangan sana | 2025-05-11 | GitHub API |
| DXMT litsenziyasi | v0.80 gacha MIT, keyin LGPL | reliz eslatmasi |
| Mashhur anti-cheat o'yinlari (Linux) | 19-bo'limdagi jadval | areweanticheatyet va boshqalar |

### Hanuz ochiq

1. **`cxbottle.conf`** nomi, tuzilishi va `[EnvironmentVariables]` sintaksisi: faqat forum va uchinchi tomon qo'llanmasi. Rasmiy hujjat faqat `cxoffice.conf` ni tilga oladi. Sinov versiyasi arxivini (387 MB) ochib tekshirishga urinildi, lekin yuklab olish juda sekin bo'lib tugamadi.
2. **Published bottle joyi:** qo'llanmalar va Advanced Configuration sahifalari turlicha.
3. **ESync** CrossOver 26 da bor-yo'qligi.
4. **macOS'dagi CLI vositalarining to'liq ro'yxati** va flag'lari.
5. **`D3DM_ENABLE_METALFX`, `D3DM_MTL4`, `WINEFSYNC`** va DXMT konfiguratsiya kalitlari.
6. **GPTK 1.0 va 2.0 tafsilotlari** Apple sahifasidan; D3DMetal'ning aniq DX12 feature level'i, mesh shader, DirectStorage, HDR.
7. **CrossTie:** bog'liqliklar sintaksisi, imzolash.
8. **O'rnatuvchi manbalari** va bog'liqlik paketlari ro'yxati.
9. **Microsoft Store / UWP / Game Pass**, iLok va boshqa dongle'lar macOS'da, Media Foundation.
10. **Anti-cheat o'yinlarining aynan macOS'dagi holati** va GTA Online, Destiny 2, CS2, Dota 2, Rust, Tarkov, EA FC.
11. **Shriftlar, wine-gecko, bufer va sudrab tashlash, Linux ovozi.**
12. **Unumdorlik o'lchovlari** (mahalliy Windows yoki Parallels bilan solishtirma).
13. **CrossOver 27 ning chiqish sanasi va Wine asosi**; ARM64 Preview tafsilotlari.
14. **BetterTester dasturi**, hajmli litsenziyalar, Linux'da o'chirish tartibi.
15. **Kompaniya asos solingan yili** (1996 yoki 2000), Wine commit'laridagi ulushi.
16. **CodeWeavers'ning D3DMetal'ni tarqatish shartlari.**

---

## 27. Manbalar

Rasmiy CodeWeavers:

- https://www.codeweavers.com/crossover/changelog
- https://support.codeweavers.com/en_US/user-guides/crossover-mac-user-guide
- https://support.codeweavers.com/en_US/user-guides/crossover-linux-user-guide
- https://support.codeweavers.com/en_US/miscellanous/advanced-settings-in-crossover-mac-26
- https://support.codeweavers.com/advanced-crossover-mac-configuration
- https://support.codeweavers.com/advanced-crossover-linux-configuration
- https://support.codeweavers.com/change-the-bottle-directory-in-crossover-mac
- https://support.codeweavers.com/2-creating-a-debug-log
- https://support.codeweavers.com/en_US/getting-started/installing-an-unlisted-application
- https://support.codeweavers.com/chrome-os
- https://support.codeweavers.com/crosstie-data-startpage
- https://support.codeweavers.com/c4-data-installation-profile
- https://codeweavers.helpjuice.com/en_US/anti-cheat
- https://www.codeweavers.com/compatibility/rating-system
- https://www.codeweavers.com/store (narxlar)
- https://www.codeweavers.com/store/licensing
- https://www.codeweavers.com/products/faq/pricing/
- https://www.codeweavers.com/crossover/source (manba tarball'i va komponentlar ro'yxati)
- https://www.codeweavers.com/blog (ro'yxat sahifasi: sarlavha, sana, parcha)
- https://support.codeweavers.com/en_US/getting-started/using-the-crossover-removal-tool
- https://support.codeweavers.com/en_US/miscellanous/run-a-windows-app-from-terminal
- https://support.codeweavers.com/en_US/miscellanous/use-the-windows-command-prompt-in-crossover
- https://support.codeweavers.com/en_US/miscellanous/printing-documents-from-applications-within-crossover
- https://support.codeweavers.com/en_US/miscellanous/Remap%20the%20Option%20key%20to%20be%20the%20Alt%20key
- https://support.codeweavers.com/en_US/troubleshooting/using-controllers-in-crossover
- https://support.codeweavers.com/en_US/miscellanous/change-the-windows-version-of-an-existing-bottle
- https://support.codeweavers.com/en_US/miscellanous/fixing-an-expired-bottle
- https://support.codeweavers.com/en_US/common-actions/editing-bottle-registry-keys
- https://support.codeweavers.com/en_US/troubleshooting/troubleshooting-unlisted-applications-cxmac
- https://support.codeweavers.com/en_US/purchasing/installing-steam-in-crossover
- https://formulae.brew.sh/api/cask/crossover.json (joriy versiya)
- https://www.codeweavers.com/compatibility/crossover/tips/elden-ring/easy-anti-cheat-issue
- https://www.codeweavers.com/compatibility/crossover/tips/the-crew-2/doesnt-work-battleye-anti-cheat
- https://www.codeweavers.com/blog/mjohnson/2026/06/11/whats-in-and-whats-out-for-crossover-27 (403, faqat parcha)
- https://www.codeweavers.com/blog/mjohnson/2026/02/10/crossover-26-cures-artificial-incompatibility-with-windows-games-on-mac (403, faqat parcha)
- https://www.codeweavers.com/support/forums/announce?msg=345881&t=24

Upstream loyihalar va Apple:

- https://github.com/3Shain/dxmt
- https://github.com/doitsujin/dxvk/blob/master/dxvk.conf
- https://github.com/KhronosGroup/MoltenVK/blob/main/Docs/MoltenVK_Runtime_UserGuide.md
- https://github.com/Gcenx/game-porting-toolkit/releases
- https://github.com/Gcenx/macOS_Wine_builds/releases
- https://github.com/frankea/Whisky
- https://github.com/frankea/winecx-gptk
- https://github.com/Whisky-App/Whisky (manba kodi: `WhiskyKit/Sources/WhiskyKit/Wine/Wine.swift`)
- https://github.com/3Shain/dxmt/releases/tag/v0.80
- https://github.com/Sikarugir-App/Sikarugir
- https://github.com/AreWeAntiCheatYet/AreWeAntiCheatYet
- https://partner.steamgames.com/doc/steamdeck/proton
- https://docs.mesa3d.org/drivers/zink.html
- https://developer.apple.com/documentation/apple-silicon/about-the-rosetta-translation-environment
- https://support.apple.com/en-us/102527 (Rosetta mavjudligi)
- https://developer.apple.com/games/game-porting-toolkit/
- https://developer.apple.com/videos/play/wwdc2026/357/
- https://www.winehq.org/announce/8.14

Ikkilamchi:

- https://en.wikipedia.org/wiki/CrossOver_(software)
- https://en.wikipedia.org/wiki/CodeWeavers
- https://phoronix.com/news/crossover-26
- https://www.omgubuntu.co.uk/2026/02/crossover-26-released
- https://en.linuxadictos.com/Crossover-26-raises-the-bar-for-Windows-games-on-Mac-and-Linux.html
- https://linuxiac.com/wine-11-0-brings-fully-supported-wow64-mode/
- https://www.gigazine.net/news/20260612-crossover-27-removes-legacy-support-mac-intel/
- https://borncity.com/news/crossover-27-codeweavers-streicht-intel-support-komplett/
- https://www.ithinkdiff.com/crossover-preview-native-arm64-support-rosetta-2/
- https://www.parallels.com/blogs/crossover-drops-intel-mac-support-what-it-means-for-you/
- https://appleinsider.com/articles/26/06/08/game-porting-toolkit-4-ushers-in-support-for-agentic-coding
- https://mybyways.com/blog/updating-crossover-to-gameporting-toolkit-3-0
- https://machow2.com/crossover-mac-review/
- https://machow2.com/kegworks-officially-renamed-to-sikarugir/
- https://www.macrumors.com/2025/04/23/whisky-ends-mac-gaming-tool-crossover/
- https://tech.slashdot.org/story/23/05/19/2043214/codeweavers-now-controlled-by-an-employee-ownership-trust
- https://linuxiac.com/bottles-65-released-with-over-100-changes-for-windows-apps-on-linux/
- https://tech-insider.org/heroic-vs-lutris-vs-bottles-2026/
- https://macmyths.com/how-much-is-geforce-now-a-month-current-us-prices-and-plans/
- https://macmyths.com/apps/mythic/
