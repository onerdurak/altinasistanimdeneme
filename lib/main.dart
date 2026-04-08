import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:local_auth/local_auth.dart';
import 'package:url_launcher/url_launcher.dart';

// --- SENİN KLASÖR YAPINA GÖRE DÜZELTİLMİŞ YOLLAR ---
import 'modeller.dart';
import 'piyasa_motoru.dart';
import 'sayfalar/ana_ekran.dart';
import 'sayfalar/detay_sayfalari.dart';
import 'sayfalar/guvenlik_sayfalari.dart';
import 'sayfalar/piyasa_sayfalari.dart';
import 'sayfalar/portfoy_sayfalari.dart';
import 'sayfalar/destek_sayfasi.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('tr_TR', null);
  runApp(const GoldGuardApp());
}

class GoldGuardApp extends StatelessWidget {
  const GoldGuardApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ALTIN ASİSTANIM',
      theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: AppTheme.bg,
          useMaterial3: true,
          fontFamily: 'Roboto',
          appBarTheme: const AppBarTheme(
              backgroundColor: Colors.transparent,
              elevation: 0,
              centerTitle: true,
              iconTheme: IconThemeData(color: AppTheme.goldMain),
              titleTextStyle: TextStyle(
                  color: AppTheme.goldMain,
                  fontSize: 22,
                  fontWeight: FontWeight.w900))),
      home: const StartupCheck(),
    );
  }
}

class StartupCheck extends StatefulWidget {
  const StartupCheck({super.key});
  @override
  State<StartupCheck> createState() => _StartupCheckState();
}

class _StartupCheckState extends State<StartupCheck> {
  bool? _hasAcceptedTerms;

  @override
  void initState() {
    super.initState();
    _checkTerms();
  }

  Future<void> _checkTerms() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _hasAcceptedTerms = prefs.getBool('has_accepted_terms') ?? false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_hasAcceptedTerms == null) {
      return const Scaffold(
          backgroundColor: AppTheme.bg,
          body: Center(
              child: CircularProgressIndicator(color: AppTheme.goldMain)));
    }
    if (!_hasAcceptedTerms!) {
      return DisclaimerScreen(
          onAccepted: () => setState(() => _hasAcceptedTerms = true));
    }
    return const MainLayout();
  }
}

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});
  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int _navIndex = 0;
  final PageController _pageController = PageController();

  late PiyasaMotoru _motor;
  final LocalAuthentication _localAuth = LocalAuthentication();
  bool _isAppLocked = false;
  String _appPin = "0000";
  bool _isPageAnimating = false;

  bool _updateScheduled = false;

  @override
  void initState() {
    super.initState();
    _loadAuthData();

    _motor = PiyasaMotoru(onUpdate: () {
      if (mounted && !_isPageAnimating && !_updateScheduled) {
        _updateScheduled = true;
        Future.microtask(() {
          if (mounted) setState(() {});
          _updateScheduled = false;
        });
      }
    });
    _motor.baslat();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pageController.addListener(_onPageScroll);
    });
  }

  void _onPageScroll() {
    if (!_pageController.hasClients) return;
    double page = _pageController.page ?? 0;
    _isPageAnimating = (page - page.roundToDouble()).abs() > 0.01;
  }

  @override
  void dispose() {
    _pageController.removeListener(_onPageScroll);
    _motor.kapat();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadAuthData() async {
    final prefs = await SharedPreferences.getInstance();
    _appPin = prefs.getString('app_pin') ?? "0000";
    _isAppLocked = prefs.getBool('is_app_locked') ?? false;
    if (mounted) setState(() {});
  }

  Future<bool> _showPinDialog() async {
    bool? success = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
            fullscreenDialog: true,
            builder: (c) => PinEntryScreen(
                currentPin: _appPin,
                onPinChanged: (newPin) async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString('app_pin', newPin);
                  setState(() => _appPin = newPin);
                })));
    return success ?? false;
  }

  Future<void> _toggleLock() async {
    final prefs = await SharedPreferences.getInstance();
    if (_isAppLocked) {
      bool authenticated = false;
      try {
        authenticated = await _localAuth.authenticate(
            localizedReason: 'Finansal verilerinizi görmek için kilidi açın');
      } catch (e) {
        authenticated = false;
      }
      if (!authenticated) authenticated = await _showPinDialog();
      if (authenticated) {
        await prefs.setBool('is_app_locked', false);
        setState(() => _isAppLocked = false);
      }
    } else {
      await prefs.setBool('is_app_locked', true);
      setState(() => _isAppLocked = true);
    }
  }

  void _showAssetDetail(BuildContext context, AssetType asset) {
    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (c) => FullScreenAssetPage(
            asset: asset,
            history: _motor.assetHistory,
            intraDayHistory: _motor.intraDayHistory,
            motor: _motor));
  }

  void _openCreator(bool isCredit) {
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (c) => PortfolioCreator(
                isCredit: isCredit,
                market: _motor.market,
                onSave: (item) {
                  isCredit
                      ? _motor.credits.add(item)
                      : _motor.debts.add(item);
                  _motor.saveAllUserData();
                  _motor.recalcLiveValues(notify: true);
                })));
  }

  void _openDetail(PortfolioItem item) {
    Navigator.push(
            context,
            MaterialPageRoute(
                builder: (c) => PortfolioDetail(
                    item: item,
                    market: _motor.market,
                    isWallet: item.id == "me",
                    onUpdate: () {
                      _motor.saveAllUserData();
                      _motor.recalcLiveValues(notify: true);
                    },
                    onRefresh: () async =>
                        await _motor.fetchLiveData(silent: false),
                    onAssetTap: (asset) => _showAssetDetail(context, asset))))
        .then((_) {
      _motor.recalcLiveValues(notify: true);
    });
  }

  void _openFullMarket() {
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (c) => FullMarketPage(
                market: _motor.market,
                onAssetTap: (a) => _showAssetDetail(context, a),
                onReorder: (oldIndex, newIndex) {
                  setState(() {
                    if (newIndex > oldIndex) newIndex -= 1;
                    final item = _motor.market.removeAt(oldIndex);
                    _motor.market.insert(newIndex, item);
                  });
                  _motor.saveMarketOrder();
                })));
  }

  void _deletePortfolioItem(PortfolioItem item, bool isCredit) {
    if (isCredit) {
      _motor.credits.remove(item);
    } else {
      _motor.debts.remove(item);
    }
    _motor.saveAllUserData();
    _motor.recalcLiveValues(notify: true);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Kayıt silindi"), duration: Duration(seconds: 1)));
  }

  Widget _buildRightMenu(BuildContext context) {
    return Drawer(
      backgroundColor: AppTheme.bg,
      child: Column(
        children: [
          DrawerHeader(
              decoration: const BoxDecoration(color: Colors.black26),
              child: Center(
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                    Container(
                        width: 65,
                        height: 65,
                        decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border:
                                Border.all(color: AppTheme.goldMain, width: 3)),
                        child: const Center(
                            child: Text("< | >",
                                style: TextStyle(
                                    color: AppTheme.goldMain,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w900)))),
                    const SizedBox(height: 10),
                    const Text("ALTIN ASİSTANIM",
                        style: TextStyle(
                            color: AppTheme.goldMain,
                            fontSize: 18,
                            fontWeight: FontWeight.bold)),
                    Text(
                        _motor.sheetVersion.isNotEmpty
                            ? "Sürüm: ${_motor.sheetVersion}"
                            : "Sürüm: 1.0.20",
                        style: const TextStyle(
                            color: Color(0x80FFFFFF), fontSize: 12))
                  ]))),
          ListTile(
              leading:
                  const Icon(Icons.menu_book_rounded, color: AppTheme.goldMain),
              title: const Text("Hakkında & Kılavuz"),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context,
                    MaterialPageRoute(builder: (c) => AboutPage(
                        version: _motor.sheetVersion.isNotEmpty
                            ? _motor.sheetVersion
                            : '1.0.20')));
              }),
          ListTile(
              leading: const Icon(Icons.chat_bubble_outline,
                  color: AppTheme.goldMain),
              title: const Text("WhatsApp Destek"),
              onTap: () async {
                Navigator.pop(context);
                await launchUrl(Uri.parse("https://wa.me/905064971970"),
                    mode: LaunchMode.externalApplication);
              }),
          ListTile(
              leading: const Icon(Icons.mail_outline, color: AppTheme.goldMain),
              title: const Text("E-Posta Gönder"),
              onTap: () async {
                Navigator.pop(context);
                await launchUrl(Uri(
                    scheme: 'mailto',
                    path: 'destek@drksistem.com',
                    query: 'subject=Altın Asistanım Öneri ve Destek'));
              }),
          ListTile(
              leading:
                  const Icon(Icons.gavel_rounded, color: AppTheme.goldMain),
              title: const Text("Yasal Uyarı"),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (c) => const FullDisclaimerPage()));
              }),
          const Spacer(),
          const Divider(color: Colors.white10),
          ListTile(
              leading:
                  const Icon(Icons.favorite_rounded, color: AppTheme.goldMain),
              title: const Text("Geliştiriciye Destek Ol"),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (c) => const SupportDeveloperPage()));
              }),
          const Padding(
              padding: EdgeInsets.only(bottom: 25.0, top: 10.0),
              child: Text("powered by Drksistem",
                  style: TextStyle(
                      color: Colors.white24,
                      fontSize: 10,
                      letterSpacing: 1.2))),
        ],
      ),
    );
  }

  Widget _buildSecuredPage(int index, Widget page) {
    if (_isAppLocked && index != 0) {
      return ClipRect(
        child: Stack(children: [
          page,
          Container(color: AppTheme.bg),
          Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
                iconSize: 80,
                icon: const Icon(Icons.lock, color: AppTheme.goldMain),
                onPressed: _toggleLock),
            const SizedBox(height: 15),
            const Text("KİLİTLİ",
                style: TextStyle(
                    color: AppTheme.goldMain,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2)),
            const SizedBox(height: 5),
            const Text("İçeriği görmek için dokunun",
                style: TextStyle(color: Colors.white70))
          ])),
        ]),
      );
    }
    return page;
  }

  @override
  Widget build(BuildContext context) {
    final rawPages = [
      DashboardPage(
          netWorth: _motor.liveNetWorth,
          market: _motor.market,
          wallet: _motor.liveWalletVal,
          credit: _motor.liveCreditVal,
          debt: _motor.liveDebtVal,
          isAppLocked: _isAppLocked,
          onToggleLock: _toggleLock,
          onMoreTap: _openFullMarket,
          onAssetTap: (a) => _showAssetDetail(context, a),
          onStatTap: (title, dataKey, color) {
            Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (c) => HistoryChartPage(
                        title: title,
                        dataKey: dataKey,
                        historyData: _motor.historyData,
                        color: color)));
          },
          isPrimaryEngineActive: _motor.isPrimaryEngineActive,
          isConnected: _motor.isLiveConnection,
          onRefresh: () async => await _motor.fetchLiveData(silent: false)),
      ListingPage(
          items: _motor.debts,
          market: _motor.market,
          isCredit: false,
          onTap: _openDetail,
          onDelete: (i) => _deletePortfolioItem(i, false),
          onRefresh: () async => await _motor.fetchLiveData(silent: false)),
      ListingPage(
          items: _motor.credits,
          market: _motor.market,
          isCredit: true,
          onTap: _openDetail,
          onDelete: (i) => _deletePortfolioItem(i, true),
          onRefresh: () async => await _motor.fetchLiveData(silent: false)),
      PortfolioDetail(
          item: _motor.wallet,
          market: _motor.market,
          isWallet: true,
          onUpdate: () {
            _motor.saveAllUserData();
            _motor.recalcLiveValues(notify: true);
          },
          onRefresh: () async => await _motor.fetchLiveData(silent: false),
          onAssetTap: (asset) => _showAssetDetail(context, asset))
    ];

    final securedPages = rawPages
        .asMap()
        .entries
        .map((e) => KeepAlivePage(
            child: _buildSecuredPage(e.key, e.value)))
        .toList();

    return Scaffold(
        endDrawer: _buildRightMenu(context),
        appBar: AppBar(
            title: Text(
                ["ALTIN ASİSTANIM", "BORÇLAR", "ALACAKLAR", "KASA"][_navIndex]),
            actions: [
              if (_motor.isLoading)
                const Padding(
                    padding: EdgeInsets.all(15),
                    child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppTheme.goldMain))),
              Builder(
                  builder: (context) => IconButton(
                      icon: const Icon(Icons.menu_rounded, size: 28),
                      onPressed: () => Scaffold.of(context).openEndDrawer())),
              const SizedBox(width: 5),
            ]),
        body: PageView(
                physics: const BouncingScrollPhysics(),
                controller: _pageController,
                onPageChanged: (i) {
                  _isPageAnimating = false;
                  setState(() => _navIndex = i);
                },
                children: securedPages),
        floatingActionButton:
            (_navIndex == 1 || _navIndex == 2) && !_isAppLocked
                ? FloatingActionButton.extended(
                    onPressed: () => _openCreator(_navIndex == 2),
                    backgroundColor: AppTheme.goldMain,
                    icon: const Icon(Icons.add_circle, color: Colors.black),
                    label: Text(_navIndex == 2 ? "ALACAK EKLE" : "BORÇ EKLE",
                        style: const TextStyle(
                            color: Colors.black, fontWeight: FontWeight.bold)))
                : null,
        bottomNavigationBar: NavigationBar(
            selectedIndex: _navIndex,
            onDestinationSelected: (i) {
              setState(() => _navIndex = i);
              _pageController.jumpToPage(i);
            },
            backgroundColor: Colors.black,
            indicatorColor: AppTheme.goldMain.withAlpha(51),
            destinations: const [
              NavigationDestination(
                  icon: Icon(Icons.dashboard_outlined),
                  selectedIcon: Icon(Icons.dashboard, color: AppTheme.goldMain),
                  label: "Özet"),
              NavigationDestination(
                  icon: Icon(Icons.arrow_circle_down_outlined),
                  selectedIcon:
                      Icon(Icons.arrow_circle_down, color: AppTheme.neonRed),
                  label: "Borç"),
              NavigationDestination(
                  icon: Icon(Icons.arrow_circle_up_outlined),
                  selectedIcon:
                      Icon(Icons.arrow_circle_up, color: AppTheme.neonGreen),
                  label: "Alacak"),
              NavigationDestination(
                  icon: Icon(Icons.wallet_outlined),
                  selectedIcon: Icon(Icons.wallet, color: AppTheme.goldMain),
                  label: "Kasa"),
            ]));
  }
}

// --- SAYFALARI HAFIZADA TUTARAK KASMAYI ÖNLEYEN SINIF ---
class KeepAlivePage extends StatefulWidget {
  final Widget child;
  const KeepAlivePage({super.key, required this.child});

  @override
  State<KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<KeepAlivePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
