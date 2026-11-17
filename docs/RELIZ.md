# Reliz va yangilanish

## Hozirgi holat

- `scripts/release.sh <versiya> <build>` Release build, ad hoc imzo va `.dmg` yaratadi. Sinab ko'rilgan: ishlaydi.
- Sparkle 2 ilovaga ulangan (`Koprik/App/UpdaterManager.swift`), lekin **o'chiq**: `Info.plist` da `SUFeedURL` hali `OWNER` o'rinbosari bilan, `SUPublicEDKey` bo'sh. Bunday build'da yangilovchi umuman ishga tushmaydi va Sozlamalar > Yangilanishlar sahifasi buni yozadi.
- Pullik Apple Developer akkaunti yo'q deb faraz qilingan: notarizatsiya yo'q. Shu Mac'da muammo emas; boshqa Mac'da birinchi ochishda o'ng tugma > Open kerak.

## Yangilanishni yoqish uchun nima qilish kerak

Bu qadamlar tashqi xizmatlarga tegadi, shuning uchun foydalanuvchi qaroridan keyin qilinadi.

1. Ilovani Xcode'da bir marta build qiling, shunda Sparkle vositalari DerivedData'ga tushadi.
2. Kalit yarating: `find ~/Library/Developer/Xcode/DerivedData -name generate_keys -type f | head -1` va uni ishga tushiring. Shaxsiy kalit Keychain'da qoladi, chop etilgan ochiq kalitni `project.yml` dagi `SUPublicEDKey` ga yozing.
3. Appcast qayerda turishini tanlang. GitHub'dagi raw URL faqat ochiq repozitoriyda ishlaydi. Yopiq repozitoriy bo'lsa, appcast'ni GitHub Pages yoki boshqa statik joyga qo'ying. Shu URL `SUFeedURL` ga yoziladi.
4. `scripts/release.sh 0.2.0 2 https://github.com/<owner>/<repo>/releases/download/v0.2.0` — `.dmg` imzolanadi, `appcast.xml` ga yozuv qo'shiladi.
5. `.dmg` ni GitHub Release'ga yuklash va `appcast.xml` ni push qilish (`git-ops` agenti orqali).

## Tekshirish ro'yxati

- `codesign --verify --deep --strict build/release/Koprik.app` o'tadi.
- `.dmg` ochiladi, ilovani Applications'ga sudrab tashlasa ishga tushadi.
- Yangilanish yoqilgandan keyin: eski versiyani o'rnatib, "Yangilanishlarni tekshirish" yangisini topib o'rnatishi.
