import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:provider/provider.dart';
import 'l10n/app_localizations.dart';
import 'screens/family_setup_screen.dart';
import 'screens/home_screen.dart';
import 'screens/intro_slides_screen.dart';
import 'services/database_service.dart';
import 'services/locale_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb) {
    await MobileAds.instance.initialize();
  }
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LocaleProvider()),
        ChangeNotifierProvider(create: (_) => DatabaseService()),
      ],
      child: const ShoppingListApp(),
    ),
  );
}

class ShoppingListApp extends StatelessWidget {
  const ShoppingListApp({super.key});

  @override
  Widget build(BuildContext context) {
    final localeProvider = context.watch<LocaleProvider>();

    return MaterialApp(
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
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
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

    if (db.currentUser != null) {
      if (db.currentUser!.idFamilia != null) {
        return const HomeScreen();
      }
      return const FamilySetupScreen();
    }

    return const IntroSlidesScreen();
  }
}
