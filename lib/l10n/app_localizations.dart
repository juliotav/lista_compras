import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_es.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('es'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In es, this message translates to:
  /// **'Lista de Compras'**
  String get appTitle;

  /// No description provided for @introSlide1Title.
  ///
  /// In es, this message translates to:
  /// **'Organiza tus Compras'**
  String get introSlide1Title;

  /// No description provided for @introSlide1Desc.
  ///
  /// In es, this message translates to:
  /// **'Gestiona fácilmente las listas de compras de tu hogar en tiempo real.'**
  String get introSlide1Desc;

  /// No description provided for @introSlide2Title.
  ///
  /// In es, this message translates to:
  /// **'Catálogo Fast-Select'**
  String get introSlide2Title;

  /// No description provided for @introSlide2Desc.
  ///
  /// In es, this message translates to:
  /// **'Añade artículos frecuentes a tus listas con un solo toque.'**
  String get introSlide2Desc;

  /// No description provided for @introSlide3Title.
  ///
  /// In es, this message translates to:
  /// **'Colaboración Familiar'**
  String get introSlide3Title;

  /// No description provided for @introSlide3Desc.
  ///
  /// In es, this message translates to:
  /// **'Crea o únete a una familia compartida para comprar en equipo.'**
  String get introSlide3Desc;

  /// No description provided for @btnStart.
  ///
  /// In es, this message translates to:
  /// **'Comenzar'**
  String get btnStart;

  /// No description provided for @loginTitle.
  ///
  /// In es, this message translates to:
  /// **'Iniciar Sesión'**
  String get loginTitle;

  /// No description provided for @loginSubtitle.
  ///
  /// In es, this message translates to:
  /// **'Bienvenido de nuevo a tu Lista de Compras'**
  String get loginSubtitle;

  /// No description provided for @emailOrUsername.
  ///
  /// In es, this message translates to:
  /// **'Correo electrónico o Usuario'**
  String get emailOrUsername;

  /// No description provided for @password.
  ///
  /// In es, this message translates to:
  /// **'Contraseña'**
  String get password;

  /// No description provided for @btnLogin.
  ///
  /// In es, this message translates to:
  /// **'Iniciar Sesión'**
  String get btnLogin;

  /// No description provided for @noAccount.
  ///
  /// In es, this message translates to:
  /// **'¿No tienes cuenta?'**
  String get noAccount;

  /// No description provided for @registerHere.
  ///
  /// In es, this message translates to:
  /// **'Regístrate aquí'**
  String get registerHere;

  /// No description provided for @registerTitle.
  ///
  /// In es, this message translates to:
  /// **'Crear Cuenta'**
  String get registerTitle;

  /// No description provided for @registerSubtitle.
  ///
  /// In es, this message translates to:
  /// **'Únete para administrar tus compras'**
  String get registerSubtitle;

  /// No description provided for @fullName.
  ///
  /// In es, this message translates to:
  /// **'Nombre Completo'**
  String get fullName;

  /// No description provided for @usernameOptional.
  ///
  /// In es, this message translates to:
  /// **'Nombre de Usuario (Opcional)'**
  String get usernameOptional;

  /// No description provided for @email.
  ///
  /// In es, this message translates to:
  /// **'Correo Electrónico'**
  String get email;

  /// No description provided for @confirmPassword.
  ///
  /// In es, this message translates to:
  /// **'Confirmar Contraseña'**
  String get confirmPassword;

  /// No description provided for @btnRegister.
  ///
  /// In es, this message translates to:
  /// **'Registrarse'**
  String get btnRegister;

  /// No description provided for @alreadyHaveAccount.
  ///
  /// In es, this message translates to:
  /// **'¿Ya tienes una cuenta?'**
  String get alreadyHaveAccount;

  /// No description provided for @loginHere.
  ///
  /// In es, this message translates to:
  /// **'Inicia sesión aquí'**
  String get loginHere;

  /// No description provided for @passwordSecurityTitle.
  ///
  /// In es, this message translates to:
  /// **'Seguridad de la contraseña'**
  String get passwordSecurityTitle;

  /// No description provided for @passRuleMinChars.
  ///
  /// In es, this message translates to:
  /// **'Al menos 8 caracteres'**
  String get passRuleMinChars;

  /// No description provided for @passRuleUppercase.
  ///
  /// In es, this message translates to:
  /// **'Al menos una letra mayúscula'**
  String get passRuleUppercase;

  /// No description provided for @passRuleNumber.
  ///
  /// In es, this message translates to:
  /// **'Al menos un número'**
  String get passRuleNumber;

  /// No description provided for @passRuleSpecial.
  ///
  /// In es, this message translates to:
  /// **'Al menos un carácter especial (@#\$%^&*)'**
  String get passRuleSpecial;

  /// No description provided for @passwordsMismatch.
  ///
  /// In es, this message translates to:
  /// **'Las contraseñas no coinciden'**
  String get passwordsMismatch;

  /// No description provided for @weakPassword.
  ///
  /// In es, this message translates to:
  /// **'La contraseña debe cumplir con los requisitos de seguridad.'**
  String get weakPassword;

  /// No description provided for @familySetupTitle.
  ///
  /// In es, this message translates to:
  /// **'Bienvenido a la App'**
  String get familySetupTitle;

  /// No description provided for @familySetupSubtitle.
  ///
  /// In es, this message translates to:
  /// **'Para comenzar, crea una nueva familia o únete a una existente con su código.'**
  String get familySetupSubtitle;

  /// No description provided for @btnCreateFamily.
  ///
  /// In es, this message translates to:
  /// **'Crear Familia'**
  String get btnCreateFamily;

  /// No description provided for @btnCreateFamilyDesc.
  ///
  /// In es, this message translates to:
  /// **'Crea un grupo familiar e invita a tus miembros.'**
  String get btnCreateFamilyDesc;

  /// No description provided for @btnJoinFamily.
  ///
  /// In es, this message translates to:
  /// **'Unirse a Familia'**
  String get btnJoinFamily;

  /// No description provided for @btnJoinFamilyDesc.
  ///
  /// In es, this message translates to:
  /// **'Ingresa un código de 6 caracteres suministrado por tu familia.'**
  String get btnJoinFamilyDesc;

  /// No description provided for @createFamilyTitle.
  ///
  /// In es, this message translates to:
  /// **'Crear Nueva Familia'**
  String get createFamilyTitle;

  /// No description provided for @familyNameLabel.
  ///
  /// In es, this message translates to:
  /// **'Nombre de la Familia'**
  String get familyNameLabel;

  /// No description provided for @familyNameHint.
  ///
  /// In es, this message translates to:
  /// **'Ejemplo: Familia Pérez'**
  String get familyNameHint;

  /// No description provided for @familyDescLabel.
  ///
  /// In es, this message translates to:
  /// **'Descripción / Propósito (Opcional)'**
  String get familyDescLabel;

  /// No description provided for @familyDescHint.
  ///
  /// In es, this message translates to:
  /// **'Ejemplo: Compras semanales de la casa'**
  String get familyDescHint;

  /// No description provided for @btnSaveFamily.
  ///
  /// In es, this message translates to:
  /// **'Guardar Familia'**
  String get btnSaveFamily;

  /// No description provided for @joinFamilyTitle.
  ///
  /// In es, this message translates to:
  /// **'Unirse a una Familia'**
  String get joinFamilyTitle;

  /// No description provided for @familyCodeLabel.
  ///
  /// In es, this message translates to:
  /// **'Código de Familia (cl_familia)'**
  String get familyCodeLabel;

  /// No description provided for @familyCodeHint.
  ///
  /// In es, this message translates to:
  /// **'Ej. FAM-8X92K'**
  String get familyCodeHint;

  /// No description provided for @btnJoin.
  ///
  /// In es, this message translates to:
  /// **'Unirse'**
  String get btnJoin;

  /// No description provided for @invalidFamilyCode.
  ///
  /// In es, this message translates to:
  /// **'El código de familia no es válido o no existe.'**
  String get invalidFamilyCode;

  /// No description provided for @homeTitle.
  ///
  /// In es, this message translates to:
  /// **'Listas de Compras'**
  String get homeTitle;

  /// No description provided for @newListTitle.
  ///
  /// In es, this message translates to:
  /// **'Nueva Lista de Compras'**
  String get newListTitle;

  /// No description provided for @listNameLabel.
  ///
  /// In es, this message translates to:
  /// **'Nombre de la Lista'**
  String get listNameLabel;

  /// No description provided for @listNameHint.
  ///
  /// In es, this message translates to:
  /// **'Ej. Carnicería, Ferretería...'**
  String get listNameHint;

  /// No description provided for @btnCreateList.
  ///
  /// In es, this message translates to:
  /// **'Crear Lista'**
  String get btnCreateList;

  /// No description provided for @defaultListName.
  ///
  /// In es, this message translates to:
  /// **'Super'**
  String get defaultListName;

  /// No description provided for @swipeToDeleteHint.
  ///
  /// In es, this message translates to:
  /// **'Desliza a la derecha para eliminar'**
  String get swipeToDeleteHint;

  /// No description provided for @confirmDeleteTitle.
  ///
  /// In es, this message translates to:
  /// **'Confirmar Eliminación'**
  String get confirmDeleteTitle;

  /// No description provided for @confirmDeleteMsg.
  ///
  /// In es, this message translates to:
  /// **'La lista de compras que desea eliminar tiene artículos sin comprar, ¿Desea continuar?'**
  String get confirmDeleteMsg;

  /// No description provided for @btnCancel.
  ///
  /// In es, this message translates to:
  /// **'Cancelar'**
  String get btnCancel;

  /// No description provided for @btnDelete.
  ///
  /// In es, this message translates to:
  /// **'Eliminar'**
  String get btnDelete;

  /// No description provided for @listAlreadyExistsErr.
  ///
  /// In es, this message translates to:
  /// **'Esta lista de compras ya existe.'**
  String get listAlreadyExistsErr;

  /// No description provided for @listDetailTitle.
  ///
  /// In es, this message translates to:
  /// **'Detalle de Lista'**
  String get listDetailTitle;

  /// No description provided for @pendingItemsHeader.
  ///
  /// In es, this message translates to:
  /// **'Artículos por comprar'**
  String get pendingItemsHeader;

  /// No description provided for @fastSelectHeader.
  ///
  /// In es, this message translates to:
  /// **'Lista de artículos'**
  String get fastSelectHeader;

  /// No description provided for @completedItemsHeader.
  ///
  /// In es, this message translates to:
  /// **'Artículos ya comprados'**
  String get completedItemsHeader;

  /// No description provided for @addCustomItemTitle.
  ///
  /// In es, this message translates to:
  /// **'Agregar Artículo Nuevo'**
  String get addCustomItemTitle;

  /// No description provided for @itemNameLabel.
  ///
  /// In es, this message translates to:
  /// **'Nombre del Artículo'**
  String get itemNameLabel;

  /// No description provided for @btnAdd.
  ///
  /// In es, this message translates to:
  /// **'Agregar'**
  String get btnAdd;

  /// No description provided for @finishListTooltip.
  ///
  /// In es, this message translates to:
  /// **'Marcar toda la lista como hecha'**
  String get finishListTooltip;

  /// No description provided for @cannotFinishPendingItemsErr.
  ///
  /// In es, this message translates to:
  /// **'No se puede finalizar la lista si aún tiene artículos por comprar.'**
  String get cannotFinishPendingItemsErr;

  /// No description provided for @listFinishedSuccess.
  ///
  /// In es, this message translates to:
  /// **'¡Lista completada exitosamente!'**
  String get listFinishedSuccess;

  /// No description provided for @menuAbout.
  ///
  /// In es, this message translates to:
  /// **'Acerca de'**
  String get menuAbout;

  /// No description provided for @menuFamilyMembers.
  ///
  /// In es, this message translates to:
  /// **'Miembros de la Familia'**
  String get menuFamilyMembers;

  /// No description provided for @menuLanguage.
  ///
  /// In es, this message translates to:
  /// **'Idioma / Language'**
  String get menuLanguage;

  /// No description provided for @menuLogout.
  ///
  /// In es, this message translates to:
  /// **'Cerrar Sesión'**
  String get menuLogout;

  /// No description provided for @privacyPolicyTitle.
  ///
  /// In es, this message translates to:
  /// **'Aviso de Privacidad'**
  String get privacyPolicyTitle;

  /// No description provided for @privacyPolicyContent.
  ///
  /// In es, this message translates to:
  /// **'Los datos recopilados (Nombre, Correo Electrónico y Contraseña encriptada) se utilizan única y exclusivamente para la autenticación en la aplicación y la sincronización de las listas de compras de su grupo familiar. No compartimos ni comercializamos su información con terceros.'**
  String get privacyPolicyContent;

  /// No description provided for @familyCodeBadge.
  ///
  /// In es, this message translates to:
  /// **'Código de Familia:'**
  String get familyCodeBadge;

  /// No description provided for @copiedCode.
  ///
  /// In es, this message translates to:
  /// **'¡Código copiado al portapapeles!'**
  String get copiedCode;

  /// No description provided for @membersTitle.
  ///
  /// In es, this message translates to:
  /// **'Integrantes de la Familia'**
  String get membersTitle;

  /// No description provided for @creatorTag.
  ///
  /// In es, this message translates to:
  /// **'Creador'**
  String get creatorTag;

  /// No description provided for @removeMember.
  ///
  /// In es, this message translates to:
  /// **'Eliminar Miembro'**
  String get removeMember;

  /// No description provided for @confirmRemoveMember.
  ///
  /// In es, this message translates to:
  /// **'¿Seguro que deseas eliminar a este miembro de la familia?'**
  String get confirmRemoveMember;

  /// No description provided for @spanish.
  ///
  /// In es, this message translates to:
  /// **'Español'**
  String get spanish;

  /// No description provided for @english.
  ///
  /// In es, this message translates to:
  /// **'Inglés'**
  String get english;

  /// No description provided for @systemDefault.
  ///
  /// In es, this message translates to:
  /// **'Predeterminado del Sistema'**
  String get systemDefault;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'es'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
