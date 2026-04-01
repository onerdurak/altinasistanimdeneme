import 'dart:async';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import '../modeller.dart';
import 'guvenlik_sayfalari.dart';

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

  // Yeni ID'miz 'aylik20plan' sisteme eklendi
  final Set<String> _kIds = {
    'destek_100',
    'destek_200',
    'destek_500',
    'destek_1000',
    'aylik20plan'
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
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text("Desteğiniz için sonsuz teşekkürler! 💛"),
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
    if (product.id == 'aylik20plan') {
      _inAppPurchase.buyNonConsumable(purchaseParam: purchaseParam);
    } else {
      // Tek seferlik destek
      _inAppPurchase.buyConsumable(purchaseParam: purchaseParam);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Ürünleri listelemek için ayırıyoruz
    List<ProductDetails> oneTimeProducts =
        _products.where((p) => p.id != 'aylik20plan').toList();
    ProductDetails? subscriptionProduct;
    try {
      subscriptionProduct = _products.firstWhere((p) => p.id == 'aylik20plan');
    } catch (e) {
      subscriptionProduct = null;
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Geliştiriciye Destek Ol")),
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
                      "Altın Asistanım'ı faydalı bulduysanız ve ücretsiz kalmasına katkıda bulunmak isterseniz aşağıdaki paketlerden birini seçerek destek olabilirsiniz.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Colors.white70, fontSize: 15, height: 1.5),
                    ),
                    const SizedBox(height: 30),

                    // --- TEK SEFERLİK ÜRÜNLER ---
                    ...oneTimeProducts.map((product) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                            color: AppTheme.card,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white10)),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 4),
                          title: Text(
                              product.title
                                  .replaceAll('(Altın Asistanım)', '')
                                  .trim(),
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white)),
                          subtitle: const Text("Tek Seferlik",
                              style:
                                  TextStyle(color: Colors.grey, fontSize: 11)),
                          trailing: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.goldMain,
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
                                  "Her ay düzenli destek olarak projenin büyümesine en büyük katkıyı sağlayın.",
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
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const FullDisclaimerPage()),
                            ),
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
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const FullDisclaimerPage()),
                            ),
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
                    ]
                  ],
                ),
    );
  }
}
