// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get appTitle => 'Lista lista';

  @override
  String get introSlide1Title => 'Organiza tus Compras';

  @override
  String get introSlide1Desc =>
      'Gestiona fácilmente las listas de compras de tu hogar en tiempo real.';

  @override
  String get introSlide2Title => 'Catálogo Fast-Select';

  @override
  String get introSlide2Desc =>
      'Añade artículos frecuentes a tus listas con un solo toque.';

  @override
  String get introSlide3Title => 'Colaboración Familiar';

  @override
  String get introSlide3Desc =>
      'Crea o únete a una familia compartida para comprar en equipo.';

  @override
  String get btnStart => 'Comenzar';

  @override
  String get loginTitle => 'Iniciar Sesión';

  @override
  String get loginSubtitle => 'Bienvenido de nuevo a tu Lista lista';

  @override
  String get emailOrUsername => 'Correo electrónico o Usuario';

  @override
  String get password => 'Contraseña';

  @override
  String get btnLogin => 'Iniciar Sesión';

  @override
  String get noAccount => '¿No tienes cuenta?';

  @override
  String get registerHere => 'Regístrate aquí';

  @override
  String get registerTitle => 'Crear Cuenta';

  @override
  String get registerSubtitle => 'Únete para administrar tus compras';

  @override
  String get fullName => 'Nombre';

  @override
  String get usernameOptional => 'Nombre de Usuario (Opcional)';

  @override
  String get email => 'Correo Electrónico';

  @override
  String get confirmPassword => 'Confirmar Contraseña';

  @override
  String get btnRegister => 'Registrarse';

  @override
  String get alreadyHaveAccount => '¿Ya tienes una cuenta?';

  @override
  String get loginHere => 'Inicia sesión aquí';

  @override
  String get passwordSecurityTitle => 'Seguridad de la contraseña';

  @override
  String get passRuleMinChars => 'Al menos 8 caracteres';

  @override
  String get passRuleUppercase => 'Al menos una letra mayúscula';

  @override
  String get passRuleNumber => 'Al menos un número';

  @override
  String get passRuleSpecial => 'Al menos un carácter especial (@#\$%^&*)';

  @override
  String get passwordsMismatch => 'Las contraseñas no coinciden';

  @override
  String get weakPassword =>
      'La contraseña debe cumplir con los requisitos de seguridad.';

  @override
  String get familySetupTitle => 'Bienvenido a la App';

  @override
  String get familySetupSubtitle =>
      'Para comenzar, crea una nueva familia o únete a una existente con su código.';

  @override
  String get btnCreateFamily => 'Crear Familia';

  @override
  String get btnCreateFamilyDesc =>
      'Crea un grupo familiar e invita a tus miembros.';

  @override
  String get btnJoinFamily => 'Unirse a Familia';

  @override
  String get btnJoinFamilyDesc =>
      'Ingresa un código de 6 caracteres suministrado por tu familia.';

  @override
  String get createFamilyTitle => 'Crear Nueva Familia';

  @override
  String get familyNameLabel => 'Nombre de la Familia';

  @override
  String get familyNameHint => 'Ejemplo: Familia Pérez';

  @override
  String get familyDescLabel => 'Descripción / Propósito (Opcional)';

  @override
  String get familyDescHint => 'Ejemplo: Compras semanales de la casa';

  @override
  String get btnSaveFamily => 'Guardar Familia';

  @override
  String get joinFamilyTitle => 'Unirse a una Familia';

  @override
  String get familyCodeLabel => 'Código de Familia (cl_familia)';

  @override
  String get familyCodeHint => 'Ej. FAM-8X92K';

  @override
  String get btnJoin => 'Unirse';

  @override
  String get invalidFamilyCode =>
      'El código de familia no es válido o no existe.';

  @override
  String get homeTitle => 'Listas de Compras';

  @override
  String get newListTitle => 'Nueva Lista de Compras';

  @override
  String get listNameLabel => 'Nombre de la Lista';

  @override
  String get listNameHint => 'Ej. Carnicería, Ferretería...';

  @override
  String get btnCreateList => 'Crear Lista';

  @override
  String get defaultListName => 'Super';

  @override
  String get swipeToDeleteHint => 'Desliza a la derecha para eliminar';

  @override
  String get confirmDeleteTitle => 'Confirmar Eliminación';

  @override
  String get confirmDeleteMsg =>
      'La lista de compras que desea eliminar tiene artículos sin comprar, ¿Desea continuar?';

  @override
  String get btnCancel => 'Cancelar';

  @override
  String get btnDelete => 'Eliminar';

  @override
  String get listAlreadyExistsErr => 'Esta lista de compras ya existe.';

  @override
  String get syncTooltip => 'Sincronizar';

  @override
  String get defaultUser => 'Usuario';

  @override
  String get defaultFamily => 'Familia';

  @override
  String get primaryFixedListTag => 'Lista Principal Fija';

  @override
  String get deleteListAction => 'Eliminar Lista';

  @override
  String get listDetailTitle => 'Detalle de Lista';

  @override
  String get pendingItemsHeader => 'Artículos por comprar';

  @override
  String get fastSelectHeader => 'Lista de artículos';

  @override
  String get completedItemsHeader => 'Artículos ya comprados';

  @override
  String get addCustomItemTitle => 'Agregar Artículo Nuevo';

  @override
  String get itemNameLabel => 'Nombre del Artículo';

  @override
  String get btnAdd => 'Agregar';

  @override
  String get finishListTooltip => 'Marcar toda la lista como hecha';

  @override
  String get cannotFinishPendingItemsErr =>
      'No se puede finalizar la lista si aún tiene artículos por comprar.';

  @override
  String get listFinishedSuccess => '¡Lista completada exitosamente!';

  @override
  String get confirmFinishListTitle => 'Finalizar Lista';

  @override
  String get confirmFinishListMsg => '¿Desea finalizar toda la lista?';

  @override
  String get btnFinish => 'Finalizar';

  @override
  String get noPendingItemsMsg =>
      'No hay artículos pendientes. Escribe o selecciona abajo para agregar.';

  @override
  String get statusPurchased => 'Comprado';

  @override
  String get actionDelete => 'Eliminar';

  @override
  String get searchOrTypeItemHint => 'Buscar o escribir artículo...';

  @override
  String addQueryToListOption(String query) {
    return 'Agregar \'$query\' a la lista';
  }

  @override
  String get addQueryToListSubtitle =>
      'Se agregará a tu lista y al catálogo de tu familia';

  @override
  String get noCatalogItemsFound =>
      'No se encontraron artículos en el catálogo.';

  @override
  String get addDetailHint => 'Agregar detalle (ej. Marca, cantidad...)';

  @override
  String get tapToAddDetail => 'Toca para agregar detalle...';

  @override
  String get menuAbout => 'Acerca de';

  @override
  String get menuFamilyMembers => 'Miembros de la Familia';

  @override
  String get menuLanguage => 'Idioma / Language';

  @override
  String get menuLogout => 'Cerrar Sesión';

  @override
  String get privacyPolicyTitle => 'Aviso de Privacidad';

  @override
  String get privacyPolicyContent =>
      'Los datos recopilados (Nombre, Correo Electrónico y Contraseña encriptada) se utilizan única y exclusivamente para la autenticación en la aplicación y la sincronización de las listas de compras de su grupo familiar. No compartimos ni comercializamos su información con terceros.';

  @override
  String get familyCodeBadge => 'Código de Familia:';

  @override
  String get copiedCode => '¡Código copiado al portapapeles!';

  @override
  String get membersTitle => 'Integrantes de la Familia';

  @override
  String get creatorTag => 'Creador';

  @override
  String get removeMember => 'Eliminar Miembro';

  @override
  String get confirmRemoveMember =>
      '¿Seguro que deseas eliminar a este miembro de la familia?';

  @override
  String get spanish => 'Español';

  @override
  String get english => 'Inglés';

  @override
  String get systemDefault => 'Predeterminado del Sistema';

  @override
  String get selectFamily => 'Seleccionar Familia';

  @override
  String get leaveFamily => 'Salir de esta familia';

  @override
  String get confirmLeaveFamilyTitle => 'Abandonar Familia';

  @override
  String get confirmLeaveFamilyMsg =>
      '¿Estás seguro de que deseas salir de esta familia? Perderás el acceso a sus listas de compra compartidas.';

  @override
  String get addOrJoinFamily => '+ Crear o Unirse a otra familia';

  @override
  String get noFamiliesYet => 'Sin familia asignada';

  @override
  String get leftFamilySuccess => 'Has salido de la familia correctamente.';

  @override
  String get invalidCredentialsErr =>
      'Credenciales incorrectas. Verifique e intente nuevamente.';

  @override
  String addedBy(String name) {
    return 'Agregado por: $name';
  }

  @override
  String itemAlreadyInList(String name) {
    return '\'$name\' ya está en la lista.';
  }

  @override
  String get forgotPasswordLink => '¿Olvidaste tu contraseña?';

  @override
  String get forgotPasswordTitle => 'Recuperar Contraseña';

  @override
  String get enterEmailMsg =>
      'Ingresa tu correo o usuario registrado para recibir un código de verificación de 6 dígitos.';

  @override
  String get sendCodeBtn => 'Enviar Código';

  @override
  String enterPinMsg(String email) {
    return 'Hemos enviado un código de 6 dígitos a $email.';
  }

  @override
  String get pinLabel => 'Código de Verificación (6 dígitos)';

  @override
  String get verifyCodeBtn => 'Verificar Código';

  @override
  String get newPasswordLabel => 'Nueva Contraseña';

  @override
  String get confirmNewPasswordLabel => 'Confirmar Nueva Contraseña';

  @override
  String get saveNewPasswordBtn => 'Guardar Nueva Contraseña';

  @override
  String get passwordResetSuccessMsg =>
      'Tu contraseña ha sido actualizada con éxito.';

  @override
  String get invalidOrExpiredPin =>
      'El código de verificación es incorrecto o ha expirado.';

  @override
  String get userNotFoundErr =>
      'No se encontró ninguna cuenta registrada con esa información.';

  @override
  String get resetEmailSentMsg =>
      'Si la información ingresada está registrada, hemos enviado un código de recuperación de 6 dígitos a su correo.';

  @override
  String expiresIn(String time) {
    return 'Expira en: $time';
  }

  @override
  String get statusSecure => 'Segura ✓';

  @override
  String get statusIncomplete => 'Incompleta';

  @override
  String createdFamiliesCount(int current, int max, int remaining) {
    return 'Familias creadas: $current de $max ($remaining disponibles)';
  }

  @override
  String get maxFamiliesReachedErr =>
      'Has alcanzado el límite máximo de 5 familias creadas. Puedes eliminar una de tus familias para liberar espacio o unirte a otras familias de forma ilimitada.';

  @override
  String get unlimitedJoinInfo =>
      'Puedes unirte a cuantas familias desees de forma ilimitada.';

  @override
  String get deleteFamilyTitle => 'Eliminar Familia';

  @override
  String deleteFamilyConfirmTitle(String name) {
    return '¿Eliminar la familia \'$name\'?';
  }

  @override
  String get deleteFamilyWarning =>
      'Esta acción es irreversible y eliminará físicamente:\n\n• La familia y su código de acceso.\n• La relación de todos los integrantes con esta familia.\n• Todas las listas de compras creadas en esta familia.\n• Todos los productos y detalles dentro de esas listas.\n• El catálogo de productos personalizado de esta familia.\n\nℹ️ Los usuarios integrantes NO serán eliminados del sistema, únicamente su vínculo con esta familia.';

  @override
  String get myFamiliesHeader => 'Mis Familias';

  @override
  String get creatorBadge => 'Creador';

  @override
  String get memberBadge => 'Miembro';

  @override
  String get alreadyFamilyCreatorMsg => 'Tú eres el creador de esta familia.';

  @override
  String get alreadyFamilyMemberMsg => 'Ya perteneces a esta familia.';

  @override
  String get pushNotificationTitle => 'Lista de Compras';

  @override
  String pushNotificationBody(String userName, String listName) {
    return '$userName ha agregado productos a la lista \"$listName\"';
  }
}
