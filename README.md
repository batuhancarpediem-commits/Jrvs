# JARVIS (insan silüetli arayüz)

Eski APK'daki (`com.batuhan.jarvis`) özelliklerin hepsi korunarak yeniden yazıldı.
Yuvarlak "orb" yerine **insan silüeti** çizen `HoloView` geldi ve konuşmaya göre hareket eder.

## Kurulum
1. Android Studio (Koala veya üstü) ile bu klasörü aç, Gradle senkronizasyonunu bekle.
2. Telefonu bağla, Run. Ya da `Build > Build APK(s)`.
3. Uygulamada AYARLAR'dan Gemini API anahtarını gir.

## Özellikler
- Gemini (google_search aracı açık), konuşma geçmişi (son 20 mesaj)
- Türkçe ses tanıma + Türkçe TTS
- "Jarvis ..." uyanma kelimesi (MİKROFON AÇIK düğmesi)
- Jarvis / Ultron kişilik ve renk modu (mavi / kırmızı)
- Yerel komutlar: uygulama aç, numara ara, alarm kur, zamanlayıcı, WhatsApp mesajı,
  pil / RAM / depolama, saat ve tarih, geçmişi sil
- Zamanlayıcı kısayolları ve bildirim

## HoloView hareketleri
| Durum | Hareket |
|---|---|
| Konuşuyor | Her kelimede nabız, ağız açılır, baş sallanır, göğüste ses spektrumu, silüetten dışa dalgalar |
| Dinliyor | Mikrofon seviyesiyle başın yanındaki parantezler genişler, gözler büyür |
| Düşünüyor | Tarama bandı hızlanır, sinir ağı titrer, baş yana yatar, üstte yanıp sönen noktalar |
| Boşta | Nefes alma, göz kırpma, yavaş tarama |

Kelime vurguları `UtteranceProgressListener.onRangeStart` ile gelir. TTS motoru bunu vermezse
animasyon kendi ritmini üretir.
