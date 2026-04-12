import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../modeller.dart';

/// Global premium abonelik durumu yöneticisi
/// Aylık abonelik süresince Premium aktif kalır
class PremiumManager {
  static bool _isSubscriptionActive = false;

  /// Premium durumunu kontrol et
  static bool get isPremium => _isSubscriptionActive;

  /// Premium durum metni
  static String get premiumStatusText {
    if (_isSubscriptionActive) return "Aktif Abonelik";
    return "";
  }

  /// Abonelik ürün ID'leri (Apple + Google)
  static const Set<String> subscriptionIds = {
    'aylik20plan',
    'aylik_destek',
  };

  /// Uygulama açılışında çağır — cache'den hızlı oku
  static Future<void> checkPremiumStatus() async {
    final prefs = await SharedPreferences.getInstance();
    _isSubscriptionActive =
        prefs.getBool('is_subscription_active') ?? false;
    // Geriye uyumluluk: eski bool flag kontrol
    if (prefs.getBool('is_premium') == true && !_isSubscriptionActive) {
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

  /// Satın alma işlendiğinde çağır
  static Future<void> handlePurchase(String productId) async {
    if (subscriptionIds.contains(productId)) {
      await setSubscriptionActive(true);
    }
  }

  /// Legacy setter
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

  // Platform bazlı product ID'ler (sadece aylık abonelik)
  static final Set<String> _googleIds = {'aylik20plan'};
  static final Set<String> _appleIds = {'aylik_destek'};

  Set<String> get _kIds => Platform.isIOS ? _appleIds : _googleIds;
  String get _subscriptionId => Platform.isIOS ? 'aylik_destek' : 'aylik20plan';

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
          PremiumManager.handlePurchase(purchaseDetails.productID);
          setState(() {});
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text("Abonelik aktif! Premium özellikler açıldı 💛"),
              backgroundColor: AppTheme.goldMain));
        }
        if (purchaseDetails.pendingCompletePurchase) {
          _inAppPurchase.completePurchase(purchaseDetails);
        }
      }
    }
  }

  void _buySubscription(ProductDetails product) {
    final param = PurchaseParam(productDetails: product);
    _inAppPurchase.buyNonConsumable(purchaseParam: param);
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
    ProductDetails? subProduct;
    try {
      subProduct = _products.firstWhere((p) => p.id == _subscriptionId);
    } catch (_) {
      subProduct = null;
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
                    const Icon(Icons.workspace_premium,
                        size: 80, color: AppTheme.goldMain),
                    const SizedBox(height: 20),
                    const Text(
                      "Premium ile Borsa sekmesi, BIST 100 canlı takip ve portföye hisse ekleme gibi özellikler açılır.",
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
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.verified,
                                color: AppTheme.goldMain, size: 20),
                            SizedBox(width: 8),
                            Text("Premium Aktif Abonelik",
                                style: TextStyle(
                                    color: AppTheme.goldMain,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13)),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 30),

                    // --- AYLIK ABONELİK KARTI ---
                    if (subProduct != null) ...[
                      Container(
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
                        child: Column(children: [
                          const Icon(Icons.star_rounded,
                              color: AppTheme.goldMain, size: 32),
                          const SizedBox(height: 10),
                          const Text("AYLIK ABONELİK",
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.2)),
                          const SizedBox(height: 5),
                          const Text(
                              "Abonelik süresince tüm Premium özellikler aktif kalır.",
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
                                  foregroundColor: Colors.black,
                                  shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(12))),
                              onPressed: () =>
                                  _buySubscription(subProduct!),
                              child: Text(
                                  "${subProduct.price} / Ay",
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
                        ]),
                      ),
                      const SizedBox(height: 24),
                    ],

                    // Yasal linkler
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        GestureDetector(
                          onTap: () => launchUrl(Uri.parse(
                              'https://onerdurak.github.io/altin-asistanim-privacy/privacy-policy.html#terms')),
                          child: const Text("Kullanım Koşulları",
                              style: TextStyle(
                                  color: AppTheme.goldMain,
                                  fontSize: 12,
                                  decoration: TextDecoration.underline,
                                  decorationColor: AppTheme.goldMain)),
                        ),
                        const Text("  •  ",
                            style: TextStyle(
                                color: Colors.white38, fontSize: 12)),
                        GestureDetector(
                          onTap: () => launchUrl(Uri.parse(
                              'https://onerdurak.github.io/altin-asistanim-privacy/privacy-policy.html')),
                          child: const Text("Gizlilik Politikası",
                              style: TextStyle(
                                  color: AppTheme.goldMain,
                                  fontSize: 12,
                                  decoration: TextDecoration.underline,
                                  decorationColor: AppTheme.goldMain)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Geri Yükle
                    Center(
                      child: TextButton.icon(
                        onPressed: _restorePurchases,
                        icon: const Icon(Icons.restore,
                            color: AppTheme.goldMain, size: 20),
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
