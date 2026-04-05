# Altın Asistanım

Türkiye'ye özel, offline-first altın, döviz ve kripto portföy takip uygulaması.

## Özellikler

- **Canlı Piyasa Verileri** — Altın (24K, 22K, 14K, çeyrek, yarım, tam, ata, reşat, hamit, gremse), döviz (USD, EUR, GBP), kripto (BTC, ETH) ve gümüş fiyatları anlık takip
- **Çift Kaynaklı Motor** — Binance (hızlı, döviz/kripto) + Google Sheets (altın/gümüş) karma veri motoru
- **Ticker Simülasyonu** — Gerçek veri çekimleri arasında 5 saniyelik mikro fiyat hareketleri
- **Portföy Yönetimi** — Kişisel kasa, alacak ve borç takibi emtia bazında
- **İnteraktif Grafikler** — Gün içi, aylık ve yıllık fiyat grafikleri (cubic bezier, tooltip destekli)
- **Hızlı Erişim Izgarası** — 4x4 özelleştirilebilir emtia kartları, fiyat yönüne göre animasyonlu glow efekti
- **Offline-First** — İnternet olmasa bile son önbellek verileriyle çalışır
- **Güvenlik** — PIN kilidi ve biyometrik kimlik doğrulama desteği
- **Geçmiş Veriler** — Google Sheets + Binance Klines ile yıllara dayanan fiyat geçmişi

## Teknik Altyapı

| Katman | Teknoloji |
|--------|-----------|
| Framework | Flutter (Dart) |
| Durum Yönetimi | Provider + setState |
| Veri Kaynakları | Binance REST API, Google Sheets CSV |
| Yerel Depolama | SharedPreferences |
| Güvenlik | local_auth (biyometrik), PIN |
| CI/CD | Codemagic (iOS TestFlight) |

## Proje Yapısı

```
lib/
├── main.dart                   # Uygulama giriş noktası, navigasyon
├── modeller.dart               # Veri modelleri (AssetType, PortfolioItem, AppTheme)
├── piyasa_motoru.dart          # Piyasa veri motoru (API, cache, simülasyon)
├── bilesenler/
│   ├── grafikler.dart          # İnteraktif grafik widget'ları
│   └── ortak_araclar.dart      # Ortak UI bileşenleri (AssetCoin, MiniStat)
└── sayfalar/
    ├── ana_ekran.dart           # Ana sayfa, hızlı erişim ızgarası
    ├── detay_sayfalari.dart     # Emtia detay sayfası (grafik + geçmiş)
    ├── piyasa_sayfalari.dart    # Tam piyasa listesi
    ├── portfoy_sayfalari.dart   # Portföy yönetimi sayfaları
    ├── destek_sayfasi.dart      # Uygulama içi satın alma / destek
    └── guvenlik_sayfalari.dart  # PIN, hakkında, yasal uyarı
```

## Kurulum

```bash
git clone https://github.com/onerdurak/altinasistanimdeneme.git
cd altinasistanimdeneme
flutter pub get
flutter run
```

## APK Oluşturma

```bash
flutter build apk --release
```

Oluşan APK: `build/app/outputs/flutter-apk/app-release.apk`

## Google Sheets Backend

Uygulama, altın ve gümüş fiyatlarını bir Google Sheets tablosundan çeker. Sheets backend'i Google Apps Script ile çalışır ve şu görevleri yerine getirir:

- **Truncgil API** ile canlı altın/döviz verisi
- **CoinGecko API** ile kripto verisi
- **Kalibrasyon sistemi** ile kuyumcu satış/alış fiyat katsayıları
- **GOOGLEFINANCE** fonksiyonu ile BİST 30 hisse takibi
- Gece 23:00'te otomatik geçmiş veri kaydı

## Lisans

Bu proje özel bir projedir. Tüm hakları saklıdır.
