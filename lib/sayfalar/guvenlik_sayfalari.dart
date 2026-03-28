import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../modeller.dart';

class PinEntryScreen extends StatefulWidget {
  final String currentPin;
  final Function(String) onPinChanged;
  const PinEntryScreen(
      {super.key, required this.currentPin, required this.onPinChanged});
  @override
  State<PinEntryScreen> createState() => _PinEntryScreenState();
}

class _PinEntryScreenState extends State<PinEntryScreen> {
  final _pinCtrl = TextEditingController();
  late String _localPin;

  @override
  void initState() {
    super.initState();
    _localPin = widget.currentPin;
  }

  void _openChangePinPage() {
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (c) => ChangePinPage(
                currentPin: _localPin,
                onPinChanged: (newPin) {
                  setState(() => _localPin = newPin);
                  widget.onPinChanged(newPin);
                })));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
          title: const Text("Kilidi Aç"),
          leading: IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.white54),
              onPressed: () => Navigator.pop(context, false))),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(),
            const Icon(Icons.lock_outline, size: 80, color: AppTheme.goldMain),
            const SizedBox(height: 20),
            const Text("Uygulama şifrenizi giriniz\n(Varsayılan: 0000)",
                textAlign: TextAlign.center,
                style:
                    TextStyle(color: Colors.grey, fontSize: 16, height: 1.5)),
            const SizedBox(height: 40),
            TextField(
                controller: _pinCtrl,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 4,
                autofocus: true,
                style: const TextStyle(
                    color: Colors.white, fontSize: 32, letterSpacing: 15),
                textAlign: TextAlign.center,
                decoration: const InputDecoration(counterText: "")),
            const SizedBox(height: 40),
            ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.goldMain,
                    foregroundColor: Colors.black,
                    minimumSize: const Size(double.infinity, 55),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12))),
                onPressed: () {
                  if (_pinCtrl.text == _localPin) {
                    Navigator.pop(context, true);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text("Hatalı Şifre!"),
                        backgroundColor: AppTheme.neonRed));
                    _pinCtrl.clear();
                  }
                },
                child: const Text("KİLİDİ AÇ",
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
            const Spacer(),
            TextButton.icon(
                onPressed: _openChangePinPage,
                icon: const Icon(Icons.password, color: Colors.white54),
                label: const Text("Şifreyi Değiştir",
                    style: TextStyle(
                        color: Colors.white54,
                        decoration: TextDecoration.underline))),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

class ChangePinPage extends StatefulWidget {
  final String currentPin;
  final Function(String) onPinChanged;
  const ChangePinPage(
      {super.key, required this.currentPin, required this.onPinChanged});
  @override
  State<ChangePinPage> createState() => _ChangePinPageState();
}

class _ChangePinPageState extends State<ChangePinPage> {
  final _oldPinCtrl = TextEditingController();
  final _newPinCtrl = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Şifre Değiştir")),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text("Uygulamanın varsayılan şifresi 0000'dır.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 16)),
            const SizedBox(height: 40),
            TextField(
                controller: _oldPinCtrl,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 4,
                decoration: const InputDecoration(
                    labelText: "Mevcut Şifreniz",
                    labelStyle: TextStyle(color: Colors.grey),
                    counterText: ""),
                style: const TextStyle(
                    color: Colors.white, letterSpacing: 10, fontSize: 24),
                textAlign: TextAlign.center),
            const SizedBox(height: 20),
            TextField(
                controller: _newPinCtrl,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 4,
                decoration: const InputDecoration(
                    labelText: "Yeni Şifre (4 Haneli)",
                    labelStyle: TextStyle(color: Colors.grey),
                    counterText: ""),
                style: const TextStyle(
                    color: Colors.white, letterSpacing: 10, fontSize: 24),
                textAlign: TextAlign.center),
            const SizedBox(height: 40),
            ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.goldMain,
                    padding: const EdgeInsets.symmetric(vertical: 16)),
                onPressed: () {
                  if (_oldPinCtrl.text != widget.currentPin) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text("Mevcut şifre hatalı!"),
                        backgroundColor: AppTheme.neonRed));
                    return;
                  }
                  if (_newPinCtrl.text.length != 4) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text("Yeni şifre tam 4 haneli olmalı!"),
                        backgroundColor: AppTheme.neonRed));
                    return;
                  }
                  widget.onPinChanged(_newPinCtrl.text);
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text("Şifreniz başarıyla değiştirildi!"),
                      backgroundColor: AppTheme.neonGreen));
                },
                child: const Text("KAYDET",
                    style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                        fontSize: 16))),
            const Spacer(),
            Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: AppTheme.neonRed.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: AppTheme.neonRed.withOpacity(0.5))),
                child: const Text(
                    "Not: Şifreyi unutursanız uygulamayı silip yeniden yüklemeniz gerekmektedir. Bu durumda cihazınızdaki kayıtlı portföy verileri sıfırlanacaktır.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: AppTheme.neonRed, fontSize: 13, height: 1.5)))
          ],
        ),
      ),
    );
  }
}

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});
  Widget _buildGuideSection(IconData icon, String title, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 25),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: AppTheme.goldMain, size: 28),
        const SizedBox(width: 15),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 5),
          Text(desc,
              style: const TextStyle(
                  color: Colors.white70, fontSize: 14, height: 1.5)),
        ]))
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Hakkında ve Kılavuz")),
      body: ListView(
        padding: const EdgeInsets.all(24),
        physics: const BouncingScrollPhysics(),
        children: [
          Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.goldMain, width: 3)),
              child: const Center(
                  child: Text("< | >",
                      style: TextStyle(
                          color: AppTheme.goldMain,
                          fontSize: 24,
                          fontWeight: FontWeight.w900)))),
          const SizedBox(height: 15),
          const Text("ALTIN ASİSTANIM",
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AppTheme.goldMain,
                  fontSize: 22,
                  fontWeight: FontWeight.bold)),
          const Text("Sürüm 1.0.15",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 40),
          const Text("NASIL KULLANILIR?",
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.goldMain,
                  letterSpacing: 1.2)),
          const Divider(color: Colors.white10, height: 30),
          _buildGuideSection(
              Icons.dashboard_customize,
              "Ana Ekrana Emtia Ekleme/Çıkarma",
              "Ana ekrandaki boş '+' kutucuklarına tıklayarak favori emtialarınızı hızlı erişime ekleyebilirsiniz. Eklediğiniz emtiaları kaldırmak için ise, o emtiaya basılı tutunca sağ üst köşesinde beliren 'x' ikonuna tıklamanız yeterlidir."),
          _buildGuideSection(
              Icons.show_chart_rounded,
              "Emtia Grafik ve Canlı Fiyat Takibi",
              "Ana ekrandan veya Tüm Piyasa listesinden herhangi bir emtiaya tıklayarak detay ekranını açabilirsiniz. Bu ekranda alış ve satış fiyatları canlı olarak güncellenir. 1G (günlük), 1A (aylık) ve 1Y (yıllık) periyotlar arasında geçiş yaparak fiyat grafiğini inceleyebilirsiniz. Grafik üzerinde parmağınızı gezdirerek geçmiş fiyatları görebilirsiniz."),
          _buildGuideSection(
              Icons.history_rounded,
              "Geçmiş Verileri Görüntüleme",
              "Emtia detay ekranında 'GEÇMİŞ' butonuna tıklayarak seçili dönemdeki tüm fiyat geçmişini liste halinde görüntüleyebilirsiniz. Ana ekrandaki Kasa, Alacak ve Borç tutarlarına tıklayarak da finansal geçmişinizi grafik ve liste olarak takip edebilirsiniz."),
          _buildGuideSection(Icons.swap_vert, "Piyasa Sıralamasını Değiştirme",
              "'Tüm Piyasa' ekranında, her emtianın sağ tarafında bulunan altı noktalı ikona (sürükle bırak) basılı tutarak listeyi kendi zevkinize göre sıralayabilirsiniz."),
          _buildGuideSection(
              Icons.touch_app_rounded,
              "Kayıtları Silme",
              "Borçlar ve Alacaklar listelerinde bir kişiyi silmek için basılı tutun, beliren silme ikonuna dokunun. Alacak/Borç detay ekranlarında ise varlıkları hem basılı tutarak hem de sağa kaydırarak (swipe) silebilirsiniz. Kasa ekranındaki varlıkları silmek için basılı tutmanız yeterlidir."),
          _buildGuideSection(
              Icons.visibility_outlined,
              "Bakiye Gizleme",
              "Ana ekrandaki göz ikonuna tıklayarak finansal verilerinizi gizleyebilir veya tekrar gösterebilirsiniz. Böylece başkalarının yanında ekranınız güvenle açık kalabilir."),
          _buildGuideSection(Icons.lock_outline, "Güvenlik ve Kilit",
              "Uygulama öncelikle cihazınızın Biyometrik (Parmak İzi / Yüz Tanıma) sistemini kullanır. Sağ üst köşedeki kilit ikonuyla uygulamayı kilitleyebilir, verilerinizi meraklı gözlerden koruyabilirsiniz."),
          const SizedBox(height: 15),
          const Text("Geliştirici Bildirimi",
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white)),
          const SizedBox(height: 10),
          const Text(
              "Bu uygulama %100 'Offline-First' (Çevrimdışı Öncelikli) mimarisi ile Drksistem tarafından geliştirilmiştir. Cihazınıza girdiğiniz hiçbir finansal veri, kasa tutarı veya portföy bilgisi internet ortamına, bulut sunuculara veya üçüncü şahıslara aktarılmaz. Bütün veriler doğrudan telefonunuzun yerel hafızasında şifrelenerek tutulur. Bu sayede maksimum veri gizliliği ve güvenlik sağlanır.",
              style:
                  TextStyle(color: Colors.white54, height: 1.5, fontSize: 13)),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

class FullDisclaimerPage extends StatelessWidget {
  const FullDisclaimerPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Yasal Uyarı")),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: const [
          Icon(Icons.gavel_rounded, size: 80, color: AppTheme.goldMain),
          SizedBox(height: 30),
          Text("KULLANIM SÖZLEŞMESİ VE GİZLİLİK POLİTİKASI",
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AppTheme.goldMain,
                  fontSize: 20,
                  fontWeight: FontWeight.bold)),
          SizedBox(height: 30),
          Text("1. Sorumluluk Reddi ve Yatırım Danışmanlığı Kapsamı",
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16)),
          SizedBox(height: 8),
          Text(
              "Altın Asistanım (bundan böyle 'Uygulama' olarak anılacaktır) bünyesinde sunulan tüm fiyat, oran, grafik, haber ve simülasyon verileri tamamen kişisel portföy takibini kolaylaştırma ve genel bilgilendirme amacı taşımaktadır. Uygulama içerisindeki hiçbir veri, grafik veya araç; 6362 sayılı Sermaye Piyasası Kanunu ve ilgili SPK tebliğleri kapsamında 'Yatırım Danışmanlığı' veya 'Alım-Satım Tavsiyesi' niteliği taşımamaktadır.",
              style: TextStyle(color: Colors.white70, height: 1.5)),
          SizedBox(height: 20),
          Text("2. Veri Doğruluğu, Kesintiler ve Sistemsel Gecikmeler",
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16)),
          SizedBox(height: 8),
          Text(
              "Uygulama; serbest piyasa, döviz büroları, kripto para borsaları ve TCMB verilerini anlık/gecikmeli API entegrasyonları ile derlemektedir. İnternet bağlantısı sorunları, API sağlayıcı kaynaklı yavaşlamalar veya piyasadaki ani volatilite (dalgalanma) nedeniyle ekranda görüntülenen fiyatlar ile piyasada (kuyumcu, banka, borsa vb.) gerçekleşen reel fiyatlar arasında farklılıklar oluşabilir.",
              style: TextStyle(color: Colors.white70, height: 1.5)),
          SizedBox(height: 20),
          Text("3. Kişisel Verilerin Korunması (KVKK)",
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16)),
          SizedBox(height: 8),
          Text(
              "Uygulama, veri güvenliğinizi en üst düzeyde tutmak amacıyla %100 Çevrimdışı (Offline-First) mimari ile tasarlanmıştır. Uygulama içerisine kaydettiğiniz kasa, portföy, alacak ve borç bilgileri yalnızca cihazınızın yerel (lokal) hafızasında şifrelenerek saklanır. Harici sunucular bu verilere erişemez.",
              style: TextStyle(color: Colors.white70, height: 1.5)),
          SizedBox(height: 20),
          Text("4. Veri Kaybı Sorumluluğu",
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16)),
          SizedBox(height: 8),
          Text(
              "Verilerinizin sunuculara aktarılmamasının bir sonucu olarak; uygulamanın cihazdan silinmesi, cihazın sıfırlanması veya arızalanması durumunda tüm portföy verileriniz kalıcı olarak silinecektir. Yedekleme ve güvenlik sorumluluğu tamamen kullanıcıya aittir.",
              style: TextStyle(color: Colors.white70, height: 1.5)),
        ],
      ),
    );
  }
}

class DisclaimerScreen extends StatefulWidget {
  final VoidCallback onAccepted;
  const DisclaimerScreen({super.key, required this.onAccepted});
  @override
  State<DisclaimerScreen> createState() => _DisclaimerScreenState();
}

class _DisclaimerScreenState extends State<DisclaimerScreen> {
  bool _isChecked = false;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            children: [
              const SizedBox(height: 20),
              const Icon(Icons.account_balance_rounded,
                  size: 60, color: AppTheme.goldMain),
              const SizedBox(height: 15),
              const Text("KULLANIM SÖZLEŞMESİ\nVE GİZLİLİK POLİTİKASI",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: AppTheme.goldMain,
                      fontSize: 18,
                      fontWeight: FontWeight.w900)),
              const SizedBox(height: 20),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                      color: AppTheme.card,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white10)),
                  child: const SingleChildScrollView(
                    physics: BouncingScrollPhysics(),
                    child: Text(
                      "ALTIN ASİSTANIM KULLANIM SÖZLEŞMESİ\n\n"
                      "Lütfen uygulamayı kullanmaya başlamadan önce aşağıdaki koşulları dikkatlice okuyunuz. Uygulamayı kullanmanız, bu şartları tamamen kabul ettiğiniz anlamına gelir.\n\n"
                      "1. Sorumluluk Reddi ve Yatırım Danışmanlığı Kapsamı\n"
                      "Altın Asistanım (bundan böyle 'Uygulama' olarak anılacaktır) bünyesinde sunulan tüm fiyat, oran, grafik, haber ve simülasyon verileri tamamen kişisel portföy takibini kolaylaştırma ve genel bilgilendirme amacı taşımaktadır. Uygulama içerisindeki hiçbir veri, grafik veya araç; 6362 sayılı Sermaye Piyasası Kanunu ve ilgili SPK tebliğleri kapsamında 'Yatırım Danışmanlığı' veya 'Alım-Satım Tavsiyesi' niteliği taşımamaktadır. Alacağınız finansal kararlar tamamen kendi inisiyatifinizdedir.\n\n"
                      "2. Veri Doğruluğu, Kesintiler ve Sistemsel Gecikmeler\n"
                      "Uygulama; serbest piyasa, döviz büroları, kripto para borsaları ve TCMB verilerini anlık/gecikmeli API entegrasyonları ile derlemektedir. İnternet bağlantısı sorunları, API sağlayıcı kaynaklı yavaşlamalar veya piyasadaki ani volatilite (dalgalanma) nedeniyle ekranda görüntülenen fiyatlar ile piyasada (kuyumcu, banka, borsa vb.) gerçekleşen reel fiyatlar arasında farklılıklar oluşabilir. Uygulama verilerine dayanılarak yapılacak ticari işlemlerden doğabilecek doğrudan veya dolaylı maddi/manevi zararlardan geliştirici sorumlu tutulamaz.\n\n"
                      "3. Kişisel Verilerin Korunması (KVKK) ve Veri Güvenliği\n"
                      "Uygulama, veri güvenliğinizi en üst düzeyde tutmak amacıyla %100 Çevrimdışı (Offline-First) mimari ile tasarlanmıştır. Uygulama içerisine kaydettiğiniz kasa, portföy, alacak ve borç bilgileri yalnızca cihazınızın yerel (lokal) hafızasında şifrelenerek saklanır. Geliştirici ekip, Drksistem, üçüncü şahıslar veya harici sunucular bu verilere kesinlikle erişemez, toplayamaz, kopyalayamaz ve analiz edemez.\n\n"
                      "4. Veri Kaybı ve Yedekleme Sorumluluğu\n"
                      "Verilerinizin sunuculara aktarılmamasının bir sonucu olarak; uygulamanın cihazdan silinmesi, cihazın sıfırlanması, kaybolması veya arızalanması durumunda tüm portföy verileriniz kalıcı olarak silinecektir. Verilerin güvenliği sorumluluğu tamamen kullanıcıya aittir.\n\n"
                      "5. Biyometrik Kilit ve Uygulama Şifresi\n"
                      "Uygulama içi Biyometrik Kilit (Face ID / Parmak İzi) özelliği, cihazınızın kendi güvenli işletim sistemi ortamında doğrulanır. Biyometrik verileriniz uygulamaya aktarılmaz. Uygulama giriş şifrenizi (PIN) unutmanız durumunda, güvenlik gereği şifre sıfırlama işlemi yapılamaz ve uygulamayı silip yeniden yüklemeniz gerekir (Bu durum veri kaybına yol açar).\n\n"
                      "6. Fikri Mülkiyet Hakları\n"
                      "Uygulamanın tasarımı, kod yapısı, logoları ve tüm arayüz bileşenlerinin fikri mülkiyet hakları Drksistem'e aittir. İzinsiz kopyalanamaz veya çoğaltılamaz.\n",
                      style: TextStyle(
                          color: Colors.white70, fontSize: 13, height: 1.6),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 15),
              GestureDetector(
                onTap: () {
                  setState(() {
                    _isChecked = !_isChecked;
                  });
                  HapticFeedback.lightImpact();
                },
                child: Row(children: [
                  Checkbox(
                      value: _isChecked,
                      activeColor: AppTheme.goldMain,
                      checkColor: Colors.black,
                      side:
                          const BorderSide(color: AppTheme.goldMain, width: 2),
                      onChanged: (bool? value) {
                        setState(() {
                          _isChecked = value ?? false;
                        });
                      }),
                  const Expanded(
                      child: Text(
                          "Kullanım sözleşmesini ve gizlilik politikasını okudum, anladım ve tüm maddeleri kendi özgür irademle kabul ediyorum.",
                          style: TextStyle(color: Colors.white, fontSize: 12))),
                ]),
              ),
              const SizedBox(height: 15),
              SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: _isChecked
                              ? AppTheme.goldMain
                              : Colors.grey.withOpacity(0.3),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12))),
                      onPressed: _isChecked
                          ? () async {
                              final prefs =
                                  await SharedPreferences.getInstance();
                              await prefs.setBool('has_accepted_terms', true);
                              widget.onAccepted();
                            }
                          : null,
                      child: Text("KABUL EDİYORUM",
                          style: TextStyle(
                              color: _isChecked ? Colors.black : Colors.white54,
                              fontWeight: FontWeight.bold,
                              fontSize: 14)))),
            ],
          ),
        ),
      ),
    );
  }
}
