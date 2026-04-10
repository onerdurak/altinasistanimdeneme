import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../modeller.dart';

/// Global premium abonelik durumu yöneticisi
/// Tek seferlik destekler süre kazandırır, aylık abonelik süresince aktif kalır
class PremiumManager {
  static bool _isSubscriptionActive = false;
  static DateTime? _premiumExpiry;

  /// Premium durumunu kontrol et (abonelik aktif VEYA süre dolmamış)
  static bool get isPremium {
    if (_isSubscriptionActive) return true;
    if (_premiumExpiry != null && _premiumExpiry!.isAfter(DateTime.now())) {
      return true;
    }
    return false;
  }

  /// Premium durum metni
  static String get premiumStatusText {
    if (_isSubscriptionActive) return "Aktif Abonelik ✓";
    if (_premiumExpiry != null && _premiumExpiry!.isAfter(DateTime.now())) {
      final days = _premiumExpiry!.difference(DateTime.now()).inDays;
      if (days > 30) {
        final months = (days / 30).floor();
        return "$months ay kaldı";
      }
      return "$days gün kaldı";
    }
    return "";
  }

  /// Uygulama açılışında çağır — cache'den hızlı oku
  static Future<void> checkPremiumStatus() async {
    final prefs = await SharedPreferences.getInstance();
    _isSubscriptionActive =
        prefs.getBool('is_subscription_active') ?? false;
    String? expiryStr = prefs.getString('premium_expiry');
    if (expiryStr != null) {
      _premiumExpiry = DateTime.tryParse(expiryStr);
    }
    // Geriye uyumluluk: eski bool flag kontrol
    if (prefs.getBool('is_premium') == true &&
        !_isSubscriptionActive &&
        _premiumExpiry == null) {
      _isSubscriptionActive = true;
    }
  }

  /// Aylık abonelik aktif/pasif
  static Future<void> setSubscriptionActive(bool value) async {
    _isSubscriptionActive = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_subscription_active', value);
    await prefs.setBool('is_premium', value);
  }

  /// Tek seferlik destek → premium süre ekle (ay bazında)
  static Future<void> addPremiumMonths(int months) async {
    DateTime base =
        (_premiumExpiry != null && _premiumExpiry!.isAfter(DateTime.now()))
            ? _premiumExpiry!
            : DateTime.now();
    _premiumExpiry =
        DateTime(base.year, base.month + months, base.day);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'premium_expiry', _premiumExpiry!.toIso8601String());
  }

  /// Ürün ID → premium süre eşleştirmesi
  static const Map<String, int> productPremiumMonths = {
    'destek_100': 6,
    'destek_200': 12,
    'destek_500': 24,
    'destek_1000': 48,
    'bronz_destek': 6,
    'gumus_destek': 12,
    'altin_destek': 24,
    'platin_destek': 48,
  };

  /// Abonelik ürün ID'leri
  static const Set<String> subscriptionIds = {
    'aylik20plan',
    'aylik_destek',
  };

  /// Satın alma işlendiğinde çağır (global listener tarafından)
  static Future<void> handlePurchase(String productId) async {
    if (subscriptionIds.contains(productId)) {
      await setSubscriptionActive(true);
    } else if (productPremiumMonths.containsKey(productId)) {
      await addPremiumMonths(productPremiumMonths[productId]!);
    }
  }

  /// Legacy setter (geriye uyumluluk)
  static Future<void> setPremium(bool value) async {
    await setSubscriptionActive(value);
  }
}

class SupportDeveloperPage extends StatefulWidget {
  const SupportDeveloperPage({super.key});

  @override
  State<SupportDeveloperPage> createState() => _SupportDeveloperPageState();
}

class _SupportDeveloperPageState extends State<SupportDeveloperPage> {
  final InAppPurchase _inAppPurchase = InAppPurchase.instance;
  late StreamSubscription<List<PurchaseDetails>> _subscription;
  List<ProductDetails> _products = [];
  bool _isAvailable = false;
  bool _isLoading = true;

  // Platform bazlı product ID'ler
  // Google Play: destek_100, destek_200, destek_500, destek_1000, aylik20plan
  // App Store: bronz_destek, gumus_destek, altin_destek, platin_destek, aylik_destek
  static final Set<String> _googleIds = {
    'destek_100',
    'destek_200',
    'destek_500',
    'destek_1000',
    'aylik20plan',
  };

  static final Set<String> _appleIds = {
    'bronz_destek',
    'gumus_destek',
    'altin_destek',
    'platin_destek',
    'aylik_destek',
  };

  Set<String> get _kIds => Platform.isIOS ? _appleIds : _googleIds;

  // Abonelik ID'si platforma göre
  String get _subscriptionId => Platform.isIOS ? 'aylik_destek' : 'aylik20plan';

  // Ürün isim eşleştirmesi (her iki platform için)
  static const Map<String, String> _tierNames = {
    'destek_100': 'Bronz Destek',
    'destek_200': 'Gümüş Destek',
    'destek_500': 'Altın Destek',
    'destek_1000': 'Platin Destek',
    'bronz_destek': 'Bronz Destek',
    'gumus_destek': 'Gümüş Destek',
    'altin_destek': 'Altın Destek',
    'platin_destek': 'Platin Destek',
  };

  // Tier ikonları
  static const Map<String, IconData> _tierIcons = {
    'Bronz Destek': Icons.workspace_premium,
    'Gümüş Destek': Icons.workspace_premium,
    'Altın Destek': Icons.workspace_premium,
    'Platin Destek': Icons.diamond,
  };

  // Tier renkleri
  static const Map<String, Color> _tierColors = {
    'Bronz Destek': Color(0xFFFFD700),
    'Gümüş Destek': Color(0xFFFFD700),
    'Altın Destek': Color(0xFFFFD700),
    'Platin Destek': Color(0xFFFFD700),
  };

  // Ürün ID → Premium süre açıklaması
  static const Map<String, String> _tierPremiumLabel = {
    'destek_100': '6 Ay Premium',
    'destek_200': '12 Ay Premium',
    'destek_500': '24 Ay Premium',
    'destek_1000': '48 Ay Premium',
    'bronz_destek': '6 Ay Premium',
    'gumus_destek': '12 Ay Premium',
    'altin_destek': '24 Ay Premium',
    'platin_destek': '48 Ay Premium',
  };

  @override
  void initState() {
    super.initState();
    final purchaseUpdated = _inAppPurchase.purchaseStream;
    _subscription = purchaseUpdated.listen((purchaseDetailsList) {
      _listenToPurchaseUpdated(purchaseDetailsList);
    }, onDone: () {
      _subscription.cancel();
    }, onError: (error) {
      // Hata durumu
    });
    _initStoreInfo();
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  Future<void> _initStoreInfo() async {
    final bool isAvailable = await _inAppPurchase.isAvailable();
    if (!isAvailable) {
      setState(() {
        _isAvailable = isAvailable;
        _isLoading = false;
      });
      return;
    }

    final ProductDetailsResponse productDetailResponse =
        await _inAppPurchase.queryProductDetails(_kIds);

    setState(() {
      _isAvailable = isAvailable;
      _products = productDetailResponse.productDetails;
      // Fiyata göre küçükten büyüğe sırala
      _products.sort((a, b) => a.rawPrice.compareTo(b.rawPrice));
      _isLoading = false;
    });
  }

  void _listenToPurchaseUpdated(List<PurchaseDetails> purchaseDetailsList) {
    for (var purchaseDetails in purchaseDetailsList) {
      if (purchaseDetails.status == PurchaseStatus.pending) {
        // Kullanıcı ödeme ekranında bekliyor
      } else {
        if (purchaseDetails.status == PurchaseStatus.error) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text("İşlem iptal edildi veya bir hata oluştu."),
              backgroundColor: AppTheme.neonRed));
        } else if (purchaseDetails.status == PurchaseStatus.purchased ||
            purchaseDetails.status == PurchaseStatus.restored) {
          // Yeni süre bazlı premium sistemi
          PremiumManager.handlePurchase(purchaseDetails.productID);
          setState(() {}); // UI güncelle
          final pid = purchaseDetails.productID;
          final months = PremiumManager.productPremiumMonths[pid];
          String msg;
          if (PremiumManager.subscriptionIds.contains(pid)) {
            msg = "Aylık abonelik aktif! Premium özellikler açıldı 💛";
          } else if (months != null) {
            msg = "Teşekkürler! $months ay Premium kazandınız 💛";
          } else {
            msg = "Desteğiniz için sonsuz teşekkürler! 💛";
          }
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(msg),
              backgroundColor: AppTheme.goldMain));
        }
        if (purchaseDetails.pendingCompletePurchase) {
          _inAppPurchase.completePurchase(purchaseDetails);
        }
      }
    }
  }

  void _buyProduct(ProductDetails product) {
    final PurchaseParam purchaseParam = PurchaseParam(productDetails: product);

    // Ürün abonelikse buyNonConsumable!
    if (product.id == _subscriptionId) {
      _inAppPurchase.buyNonConsumable(purchaseParam: purchaseParam);
    } else {
      // Tek seferlik destek
      _inAppPurchase.buyConsumable(purchaseParam: purchaseParam);
    }
  }

  Future<void> _restorePurchases() async {
    try {
      await _inAppPurchase.restorePurchases();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Geri yükleme sırasında bir hata oluştu."),
            backgroundColor: AppTheme.neonRed));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Ürünleri listelemek için ayırıyoruz
    List<ProductDetails> oneTimeProducts =
        _products.where((p) => p.id != _subscriptionId).toList();
    ProductDetails? subscriptionProduct;
    try {
      subscriptionProduct =
          _products.firstWhere((p) => p.id == _subscriptionId);
    } catch (e) {
      subscriptionProduct = null;
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Premium Paketler")),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.goldMain))
          : !_isAvailable
              ? const Center(
                  child: Text("Mağaza bağlantısı kurulamadı.",
                      style: TextStyle(color: Colors.white54)))
              : ListView(
                  padding: const EdgeInsets.all(20),
                  physics: const BouncingScrollPhysics(),
                  children: [
                    // Kalp simgesini temanın Gold rengine çevirdik
                    const Icon(Icons.favorite_rounded,
                        size: 80, color: AppTheme.goldMain),
                    const SizedBox(height: 20),
                    const Text(
                      "Premium ile Borsa sekmesi, BIST 100 canlı takip ve portföye hisse ekleme gibi özellikler açılır.\n\nAşağıdaki paketlerden birini seçerek Premium'a geçin!",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Colors.white70, fontSize: 15, height: 1.5),
                    ),
                    // Premium durum göstergesi
                    if (PremiumManager.isPremium) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                            color: const Color(0x1AFFD700),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: AppTheme.goldMain.withAlpha(80))),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.verified,
                                color: AppTheme.goldMain, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              "Premium: ${PremiumManager.premiumStatusText}",
                              style: const TextStyle(
                                  color: AppTheme.goldMain,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 30),

                    // --- TEK SEFERLİK ÜRÜNLER (Bronz/Gümüş/Altın/Platin) ---
                    ...oneTimeProducts.map((product) {
                      final tierName =
                          _tierNames[product.id] ?? product.title;
                      final tierColor =
                          _tierColors[tierName] ?? AppTheme.goldMain;
                      final tierIcon =
                          _tierIcons[tierName] ?? Icons.workspace_premium;
                      final premLabel =
                          _tierPremiumLabel[product.id] ?? 'Tek Seferlik';

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                            color: AppTheme.card,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color: tierColor.withOpacity(0.3))),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 4),
                          leading: Icon(tierIcon, color: tierColor, size: 28),
                          title: Text(tierName,
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: tierColor)),
                          subtitle: Text("Tek Seferlik · $premLabel",
                              style: const TextStyle(
                                  color: Colors.grey, fontSize: 11)),
                          trailing: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                                backgroundColor: tierColor,
                                foregroundColor: Colors.black,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10))),
                            onPressed: () => _buyProduct(product),
                            child: Text(product.price,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                          ),
                        ),
                      );
                    }),

                    const SizedBox(height: 20),

                    // --- AYLIK ABONELİK KARTI (Gold Temalı) ---
                    if (subscriptionProduct != null) ...[
                      const Divider(color: Colors.white10, thickness: 1),
                      const SizedBox(height: 20),
                      Center(
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  AppTheme.card,
                                  AppTheme.goldMain.withOpacity(0.08)
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: AppTheme.goldMain.withOpacity(0.4),
                                  width: 1.5),
                              boxShadow: [
                                BoxShadow(
                                    color: AppTheme.goldMain.withOpacity(0.05),
                                    blurRadius: 15,
                                    spreadRadius: 2)
                              ]),
                          child: Column(
                            children: [
                              const Icon(Icons.star_rounded,
                                  color: AppTheme.goldMain, size: 32),
                              const SizedBox(height: 10),
                              const Text("DÜZENLİ DESTEK",
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.2)),
                              const SizedBox(height: 5),
                              const Text(
                                  "Her ay düzenli destek olarak projenin büyümesine en büyük katkıyı sağlayın.\nAbonelik süresince Premium özellikler aktif kalır.",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      color: Colors.white70, fontSize: 12)),
                              const SizedBox(height: 15),
                              SizedBox(
                                width: double.infinity,
                                height: 50,
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                      backgroundColor: AppTheme.goldMain,
                                      foregroundColor: Colors
                                          .black, // Gold buton üzerinde siyah yazı
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(12))),
                                  onPressed: () =>
                                      _buyProduct(subscriptionProduct!),
                                  child: Text(
                                      "${subscriptionProduct.price} / Ay",
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16)),
                                ),
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                "Bu abonelik aylık olarak otomatik yenilenir. "
                                "İstediğiniz zaman Ayarlar > Apple Kimliği > "
                                "Abonelikler veya Google Play > Abonelikler "
                                "bölümünden iptal edebilirsiniz. İptal, mevcut "
                                "dönemin sonunda geçerli olur.",
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: Colors.white38,
                                    fontSize: 10,
                                    height: 1.4),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      // Apple Guideline 3.1.2(c) — abonelik ekranında zorunlu linkler
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          GestureDetector(
                            onTap: () => launchUrl(Uri.parse(
                                'https://onerdurak.github.io/altin-asistanim-privacy/privacy-policy.html#terms')),
                            child: const Text(
                              "Kullanım Koşulları",
                              style: TextStyle(
                                  color: AppTheme.goldMain,
                                  fontSize: 12,
                                  decoration: TextDecoration.underline,
                                  decorationColor: AppTheme.goldMain),
                            ),
                          ),
                          const Text("  •  ",
                              style: TextStyle(
                                  color: Colors.white38, fontSize: 12)),
                          GestureDetector(
                            onTap: () => launchUrl(Uri.parse(
                                'https://onerdurak.github.io/altin-asistanim-privacy/privacy-policy.html')),
                            child: const Text(
                              "Gizlilik Politikası",
                              style: TextStyle(
                                  color: AppTheme.goldMain,
                                  fontSize: 12,
                                  decoration: TextDecoration.underline,
                                  decorationColor: AppTheme.goldMain),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],

                    const SizedBox(height: 24),
                    // Satın Alımları Geri Yükle butonu (Apple Guideline 3.1.1)
                    Center(
                      child: TextButton.icon(
                        onPressed: _restorePurchases,
                        icon: const Icon(Icons.restore, color: AppTheme.goldMain, size: 20),
                        label: const Text(
                          "Satın Alımları Geri Yükle",
                          style: TextStyle(
                              color: AppTheme.goldMain,
                              fontSize: 13,
                              decoration: TextDecoration.underline,
                              decorationColor: AppTheme.goldMain),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
    );
  }
}
