import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:provider/provider.dart';
import 'l10n/app_localizations.dart';
import 'screens/family_setup_screen.dart';
import 'screens/home_screen.dart';
import 'screens/intro_slides_screen.dart';
import 'screens/update_required_screen.dart';
import 'services/database_service.dart';
import 'services/locale_provider.dart';
import 'services/push_notification_service.dart';
import 'services/theme_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Capturar errores no manejados de sockets asíncronos cuando Android suspende la app en segundo plano
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint("[GLOBAL DISPATCHER LOG] Excepción asíncrona interceptada y amortiguada: $error");
    return true; // Retorna true para evitar pausas en el depurador o cierres inesperados
  };

  if (!kIsWeb) {
    await MobileAds.instance.initialize();
    await PushNotificationService.initialize();
  }
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LocaleProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => DatabaseService()),
      ],
      child: const ShoppingListApp(),
    ),
  );
}

class ShoppingListApp extends StatefulWidget {
  const ShoppingListApp({super.key});

  @override
  State<ShoppingListApp> createState() => _ShoppingListAppState();
}

class _ShoppingListAppState extends State<ShoppingListApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint("[APP_LIFECYCLE] App reanudada (resumed). Disparando sincronización en segundo plano...");
      final db = Provider.of<DatabaseService>(context, listen: false);
      db.onAppResume();
    }
  }

  @override
  Widget build(BuildContext context) {
    final localeProvider = context.watch<LocaleProvider>();
    final themeProvider = context.watch<ThemeProvider>();

    return MaterialApp(
      navigatorKey: PushNotificationService.navigatorKey,
      title: 'Lista lista',
      debugShowCheckedModeBanner: false,
      locale: localeProvider.effectiveLocale,
      localeResolutionCallback: (deviceLocale, supportedLocales) {
        if (localeProvider.locale != null) {
          return localeProvider.locale;
        }
        if (deviceLocale != null) {
          if (deviceLocale.languageCode.toLowerCase() == 'en') {
            return const Locale('en');
          }
        }
        return const Locale('es');
      },
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('es'), // Español
        Locale('en'), // Inglés
      ],
      themeMode: themeProvider.themeMode,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.light,
          primary: Colors.deepPurple,
          secondary: Colors.teal,
        ),
        scaffoldBackgroundColor: const Color(0xFFF8F9FE),
        appBarTheme: const AppBarTheme(
          elevation: 0,
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          centerTitle: true,
          titleTextStyle: TextStyle(
            color: Colors.black87,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFEFD5FF),
          primaryContainer: Color(0xFF381E72),
          onPrimaryContainer: Color(0xFFF2E7FF),
          secondary: Colors.tealAccent,
          surface: Color(0xFF1E1E2C),
          onSurface: Colors.white,
        ),
        scaffoldBackgroundColor: const Color(0xFF12121E),
        cardColor: const Color(0xFF1E1E2C),
        dialogTheme: const DialogThemeData(backgroundColor: Color(0xFF1E1E2C)),
        appBarTheme: const AppBarTheme(
          elevation: 0,
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          centerTitle: true,
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      home: const RootSessionDecider(),
    );
  }
}

class RootSessionDecider extends StatelessWidget {
  const RootSessionDecider({super.key});

  @override
  Widget build(BuildContext context) {
    final db = context.watch<DatabaseService>();

    // Esperar a que cargue la preferencia de sesión guardada
    if (!db.isInitialized) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: Colors.deepPurple),
        ),
      );
    }

    if (db.isUpdateRequired) {
      return UpdateRequiredScreen(remoteVersion: db.remoteAppVersion);
    }

    if (db.currentUser != null) {
      if (db.currentUser!.idFamilia != null) {
        return const HomeScreen();
      }
      return const FamilySetupScreen();
    }

    return const IntroSlidesScreen();
  }
}
