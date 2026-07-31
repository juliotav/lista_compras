// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Lista lista';

  @override
  String get introSlide1Title => 'Organize Your Purchases';

  @override
  String get introSlide1Desc =>
      'Easily manage your household shopping lists in real-time.';

  @override
  String get introSlide2Title => 'Fast-Select Catalog';

  @override
  String get introSlide2Desc =>
      'Add frequent items to your lists with a single tap.';

  @override
  String get introSlide3Title => 'Family Collaboration';

  @override
  String get introSlide3Desc =>
      'Create or join a shared family group to shop together.';

  @override
  String get btnStart => 'Get Started';

  @override
  String get loginTitle => 'Sign In';

  @override
  String get loginSubtitle => 'Welcome back to your Lista lista app';

  @override
  String get emailOrUsername => 'Email or Username';

  @override
  String get password => 'Password';

  @override
  String get btnLogin => 'Sign In';

  @override
  String get noAccount => 'Don\'t have an account?';

  @override
  String get registerHere => 'Register here';

  @override
  String get registerTitle => 'Create Account';

  @override
  String get registerSubtitle => 'Join to manage your purchases';

  @override
  String get fullName => 'Name';

  @override
  String get usernameOptional => 'Username (Optional)';

  @override
  String get email => 'Email Address';

  @override
  String get confirmPassword => 'Confirm Password';

  @override
  String get btnRegister => 'Register';

  @override
  String get alreadyHaveAccount => 'Already have an account?';

  @override
  String get loginHere => 'Sign in here';

  @override
  String get passwordSecurityTitle => 'Password Security';

  @override
  String get passRuleMinChars => 'At least 8 characters';

  @override
  String get passRuleUppercase => 'At least one uppercase letter';

  @override
  String get passRuleNumber => 'At least one number';

  @override
  String get passRuleSpecial => 'At least one special character (@#\$%^&*)';

  @override
  String get passwordsMismatch => 'Passwords do not match';

  @override
  String get weakPassword => 'Password must meet security standards.';

  @override
  String get familySetupTitle => 'Welcome to the App';

  @override
  String get familySetupSubtitle =>
      'To get started, create a new family or join an existing one using its code.';

  @override
  String get btnCreateFamily => 'Create Family';

  @override
  String get btnCreateFamilyDesc =>
      'Create a family group and invite your members.';

  @override
  String get btnJoinFamily => 'Join Family';

  @override
  String get btnJoinFamilyDesc =>
      'Enter a 6-character code provided by your family.';

  @override
  String get createFamilyTitle => 'Create New Family';

  @override
  String get familyNameLabel => 'Family Name';

  @override
  String get familyNameHint => 'Example: Perez Family';

  @override
  String get familyDescLabel => 'Description / Purpose (Optional)';

  @override
  String get familyDescHint => 'Example: Weekly grocery shopping';

  @override
  String get btnSaveFamily => 'Save Family';

  @override
  String get joinFamilyTitle => 'Join a Family';

  @override
  String get familyCodeLabel => 'Family Code (cl_familia)';

  @override
  String get familyCodeHint => 'E.g. FAM-8X92K';

  @override
  String get btnJoin => 'Join';

  @override
  String get invalidFamilyCode =>
      'The family code is invalid or does not exist.';

  @override
  String get homeTitle => 'Shopping Lists';

  @override
  String get newListTitle => 'New Shopping List';

  @override
  String get listNameLabel => 'List Name';

  @override
  String get listNameHint => 'E.g. Butcher, Hardware store...';

  @override
  String get btnCreateList => 'Create List';

  @override
  String get defaultListName => 'Super';

  @override
  String get swipeToDeleteHint => 'Swipe right to delete';

  @override
  String get confirmDeleteTitle => 'Confirm Deletion';

  @override
  String get confirmDeleteMsg =>
      'The shopping list you want to delete has unpurchased items. Do you wish to continue?';

  @override
  String get btnCancel => 'Cancel';

  @override
  String get btnDelete => 'Delete';

  @override
  String get listAlreadyExistsErr => 'This shopping list already exists.';

  @override
  String get syncTooltip => 'Synchronize';

  @override
  String get defaultUser => 'User';

  @override
  String get defaultFamily => 'Family';

  @override
  String get primaryFixedListTag => 'Fixed Main List';

  @override
  String get deleteListAction => 'Delete List';

  @override
  String get listDetailTitle => 'List Detail';

  @override
  String get pendingItemsHeader => 'Items to buy';

  @override
  String get fastSelectHeader => 'Item catalog';

  @override
  String get completedItemsHeader => 'Purchased items';

  @override
  String get addCustomItemTitle => 'Add New Item';

  @override
  String get itemNameLabel => 'Item Name';

  @override
  String get btnAdd => 'Add';

  @override
  String get finishListTooltip => 'Mark entire list as finished';

  @override
  String get cannotFinishPendingItemsErr =>
      'Cannot finish a list while it still has unpurchased items.';

  @override
  String get listFinishedSuccess => 'List completed successfully!';

  @override
  String get confirmFinishListTitle => 'Finish List';

  @override
  String get confirmFinishListMsg => 'Do you want to finish the entire list?';

  @override
  String get btnFinish => 'Finish';

  @override
  String get noPendingItemsMsg =>
      'No pending items. Type or select below to add.';

  @override
  String get statusPurchased => 'Purchased';

  @override
  String get actionDelete => 'Delete';

  @override
  String get searchOrTypeItemHint => 'Search or type item...';

  @override
  String addQueryToListOption(String query) {
    return 'Add \'$query\' to list';
  }

  @override
  String get addQueryToListSubtitle =>
      'Will be added to your list and family catalog';

  @override
  String get noCatalogItemsFound => 'No catalog items found.';

  @override
  String get addDetailHint => 'Add detail (e.g. Brand, quantity...)';

  @override
  String get tapToAddDetail => 'Tap to add detail...';

  @override
  String get menuAbout => 'About';

  @override
  String get menuFamilyMembers => 'Family Members';

  @override
  String get menuLanguage => 'Language / Idioma';

  @override
  String get menuLogout => 'Sign Out';

  @override
  String get privacyPolicyTitle => 'Privacy Policy';

  @override
  String get privacyPolicyContent =>
      'The collected data (Full Name, Email, and encrypted Password) is used strictly and exclusively for authentication and synchronizing shopping lists within your family group. We do not share or sell your information to third parties.';

  @override
  String get familyCodeBadge => 'Family Code:';

  @override
  String get copiedCode => 'Code copied to clipboard!';

  @override
  String get membersTitle => 'Family Members';

  @override
  String get creatorTag => 'Creator';

  @override
  String get removeMember => 'Remove Member';

  @override
  String get confirmRemoveMember =>
      'Are you sure you want to remove this family member?';

  @override
  String get spanish => 'Spanish';

  @override
  String get english => 'English';

  @override
  String get systemDefault => 'System Default';

  @override
  String get selectFamily => 'Select Family';

  @override
  String get leaveFamily => 'Leave this family';

  @override
  String get confirmLeaveFamilyTitle => 'Leave Family';

  @override
  String get confirmLeaveFamilyMsg =>
      'Are you sure you want to leave this family? You will lose access to its shared shopping lists.';

  @override
  String get addOrJoinFamily => '+ Create or Join another family';

  @override
  String get noFamiliesYet => 'No family assigned';

  @override
  String get leftFamilySuccess => 'You have left the family successfully.';

  @override
  String get invalidCredentialsErr => 'Wrong credentials. Verify them.';

  @override
  String addedBy(String name) {
    return 'Added by: $name';
  }

  @override
  String itemAlreadyInList(String name) {
    return '\'$name\' is already in the list.';
  }
}
