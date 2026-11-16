# Sinov jurnali

Har bosqichning qabul sinovlari natijasi shu yerga yoziladi: nima ishladi, nima ishlamadi, nima hali sinalmagan.

## 1-bosqich. Yadro (`KoprikKit` + `koprik` CLI)

### 2026-11-17: kod va avtomatik testlar

**Holat: kod yozildi, avtomatik testlar o'tdi. Haqiqiy Wine bilan hali sinalmagan.**

| Tekshiruv | Natija |
|---|---|
| `swift build` | o'tdi |
| `swift test`: 44 test, 8 to'plam | hammasi o'tdi |
| CLI'ni soxta dvigatel bilan boshidan oxirigacha yurgizish | o'tdi |

Avtomatik testlar nimani qamraydi:

- muhit quruvchi: prefiks, `PATH`, MSync/ESync, backend uchun DLL override'lar, HUD va boshqa kalitlar, foydalanuvchi o'zgaruvchilarining ustunligi, mezbon muhitdagi begona Wine o'zgaruvchilarini tozalash;
- sozlamalar qatlamlari (dvigatel → bottle → dastur → bir martalik);
- dvigatel manbalari URL'lari, sha256 hisoblash va `shasum` faylini o'qish;
- dvigatelni papkadan va arxivdan o'rnatish, ichma-ich joylashgan Wine'ni topish, buzuq arxivda iz qoldirmaslik, takroriy o'rnatishni rad etish;
- yuklab olish (progress, mavjud faylni almashtirish, xato holati);
- bottle yaratish, Wine xato bersa tozalash, nom tekshiruvi, qayta nomlash, nusxalash (simvolik havolalar bilan), snapshot va tiklash, o'chirish;
- Wine jarayonini ishga tushirish, logga yozish, chiqish kodini qaytarish, log oqimi.

Bu testlar **soxta dvigatel** bilan ishlaydi: `wine64` o'rniga chaqiruvlarni yozib boradigan shell skript. Ular bizning kodimiz to'g'ri buyruq va muhitni berishini tasdiqlaydi, lekin haqiqiy Wine'ning o'zini tutishini tasdiqlamaydi.

CLI sinovida topilib tuzatilgan xato: `koprik run` da dastur nomidan keyin yozilgan `--verbose`, `--backend` kabi parametrlar dasturga argument bo'lib ketayotgan edi. Endi parametrlar istalgan joyda yozilishi mumkin; chiziqcha bilan boshlanadigan dastur argumentlari `--` dan keyin beriladi.

### Go/no-go sinovlari (haqiqiy dvigatel kerak, hali o'tkazilmagan)

| # | Sinov | Holat |
|---|---|---|
| 1 | `koprik bottle create test && koprik run test notepad` oyna ochadi | kutilmoqda |
| 2 | 7-Zip o'rnatuvchisi `/S` bilan o'rnatiladi | kutilmoqda |
| 3 | Steam o'rnatiladi va do'kon sahifasi chiziladi | kutilmoqda |
| 4 | Bitta DX11 o'yin DXMT bilan; GPTK importidan keyin bitta DX12 o'yin D3DMetal bilan | kutilmoqda |
| 5 | Backendni almashtirish mexanizmini aniqlash (jarayon muhiti orqalimi yoki DLL nusxalashmi) | kutilmoqda |

Boshlash uchun: `koprik engine install gaming` (479 MB yuklab oladi, sha256 bilan tekshiradi).

Ma'lum taxminiy joy: `WineEnvironment.backendOverrides` dagi DXMT va DXVK override'lari hujjatlarga asoslangan; winecx-gptk dvigatelida ichki DXMT va import qilingan D3DMetal o'rtasida tanlov qanday bo'lishi 5-sinovda aniqlanadi.
