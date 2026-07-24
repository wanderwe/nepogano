import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_uk.dart';

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

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
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
    Locale('uk'),
  ];

  /// No description provided for @cancel.
  ///
  /// In uk, this message translates to:
  /// **'Скасувати'**
  String get cancel;

  /// No description provided for @delete.
  ///
  /// In uk, this message translates to:
  /// **'Видалити'**
  String get delete;

  /// No description provided for @save.
  ///
  /// In uk, this message translates to:
  /// **'Зберегти'**
  String get save;

  /// No description provided for @update.
  ///
  /// In uk, this message translates to:
  /// **'Оновити'**
  String get update;

  /// No description provided for @edit.
  ///
  /// In uk, this message translates to:
  /// **'Редагувати'**
  String get edit;

  /// No description provided for @retry.
  ///
  /// In uk, this message translates to:
  /// **'Спробувати ще раз'**
  String get retry;

  /// No description provided for @done.
  ///
  /// In uk, this message translates to:
  /// **'Готово'**
  String get done;

  /// No description provided for @back.
  ///
  /// In uk, this message translates to:
  /// **'Назад'**
  String get back;

  /// No description provided for @or.
  ///
  /// In uk, this message translates to:
  /// **'або'**
  String get or;

  /// No description provided for @moodNiyak.
  ///
  /// In uk, this message translates to:
  /// **'Ніяк'**
  String get moodNiyak;

  /// No description provided for @moodNepogano.
  ///
  /// In uk, this message translates to:
  /// **'Непогано'**
  String get moodNepogano;

  /// No description provided for @moodZbs.
  ///
  /// In uk, this message translates to:
  /// **'Збс'**
  String get moodZbs;

  /// No description provided for @todayWasPrefix.
  ///
  /// In uk, this message translates to:
  /// **'Сьогодні було'**
  String get todayWasPrefix;

  /// No description provided for @skip.
  ///
  /// In uk, this message translates to:
  /// **'Пропустити'**
  String get skip;

  /// No description provided for @next.
  ///
  /// In uk, this message translates to:
  /// **'Далі'**
  String get next;

  /// No description provided for @getStarted.
  ///
  /// In uk, this message translates to:
  /// **'Почати'**
  String get getStarted;

  /// No description provided for @onboarding1Headline.
  ///
  /// In uk, this message translates to:
  /// **'Не кожен день неймовірний'**
  String get onboarding1Headline;

  /// No description provided for @onboarding1Body.
  ///
  /// In uk, this message translates to:
  /// **'І це нормально. Тут не треба прикрашати — просто чесно зафіксуй, як минув день.'**
  String get onboarding1Body;

  /// No description provided for @onboarding2Headline.
  ///
  /// In uk, this message translates to:
  /// **'Ніяк. Непогано. Збс.'**
  String get onboarding2Headline;

  /// No description provided for @onboarding2Body.
  ///
  /// In uk, this message translates to:
  /// **'Три прості оцінки без пафосу. Жодного тиску відповідати \"чудово\", коли насправді \"так собі\".'**
  String get onboarding2Body;

  /// No description provided for @onboarding4Headline.
  ///
  /// In uk, this message translates to:
  /// **'Близькі поруч'**
  String get onboarding4Headline;

  /// No description provided for @onboarding4Body.
  ///
  /// In uk, this message translates to:
  /// **'Додай друзів, побач їхній настрій і спробуй вгадати, як минув їхній день.'**
  String get onboarding4Body;

  /// No description provided for @onboarding5Headline.
  ///
  /// In uk, this message translates to:
  /// **'Погляд на місяць'**
  String get onboarding5Headline;

  /// No description provided for @onboarding5Body.
  ///
  /// In uk, this message translates to:
  /// **'Записи складаються в спокійну ретроспективу — без оцінок, просто дзеркало твого місяця.'**
  String get onboarding5Body;

  /// No description provided for @addPhoto.
  ///
  /// In uk, this message translates to:
  /// **'Додати фото'**
  String get addPhoto;

  /// No description provided for @takePhoto.
  ///
  /// In uk, this message translates to:
  /// **'Зробити фото'**
  String get takePhoto;

  /// No description provided for @chooseFromGallery.
  ///
  /// In uk, this message translates to:
  /// **'Обрати з галереї'**
  String get chooseFromGallery;

  /// No description provided for @removePhotoTooltip.
  ///
  /// In uk, this message translates to:
  /// **'Прибрати фото'**
  String get removePhotoTooltip;

  /// No description provided for @repositionPhoto.
  ///
  /// In uk, this message translates to:
  /// **'Розташування фото'**
  String get repositionPhoto;

  /// No description provided for @repositionPhotoHint.
  ///
  /// In uk, this message translates to:
  /// **'Перетягни фото вгору чи вниз, щоб показати потрібну частину'**
  String get repositionPhotoHint;

  /// No description provided for @repositionPhotoTooltip.
  ///
  /// In uk, this message translates to:
  /// **'Змінити розташування фото'**
  String get repositionPhotoTooltip;

  /// No description provided for @history.
  ///
  /// In uk, this message translates to:
  /// **'Історія'**
  String get history;

  /// No description provided for @moreTooltip.
  ///
  /// In uk, this message translates to:
  /// **'Ще'**
  String get moreTooltip;

  /// No description provided for @signOut.
  ///
  /// In uk, this message translates to:
  /// **'Вийти'**
  String get signOut;

  /// No description provided for @deleteAccount.
  ///
  /// In uk, this message translates to:
  /// **'Видалити акаунт'**
  String get deleteAccount;

  /// No description provided for @deleteAccountConfirmTitle.
  ///
  /// In uk, this message translates to:
  /// **'Видалити акаунт?'**
  String get deleteAccountConfirmTitle;

  /// No description provided for @deleteAccountConfirmBody.
  ///
  /// In uk, this message translates to:
  /// **'Це видалить твій акаунт і всі записи назавжди. Відновити буде неможливо.'**
  String get deleteAccountConfirmBody;

  /// No description provided for @deleteAccountFinalConfirmTitle.
  ///
  /// In uk, this message translates to:
  /// **'Ти точно впевнений?'**
  String get deleteAccountFinalConfirmTitle;

  /// No description provided for @no.
  ///
  /// In uk, this message translates to:
  /// **'Ні'**
  String get no;

  /// No description provided for @yesDelete.
  ///
  /// In uk, this message translates to:
  /// **'Так, видалити'**
  String get yesDelete;

  /// No description provided for @howAreThingsToday.
  ///
  /// In uk, this message translates to:
  /// **'Як справи сьогодні?'**
  String get howAreThingsToday;

  /// No description provided for @alreadySavedToday.
  ///
  /// In uk, this message translates to:
  /// **'Вже збережено о {time}'**
  String alreadySavedToday(String time);

  /// No description provided for @notePlaceholder.
  ///
  /// In uk, this message translates to:
  /// **'Пару слів про день (необов\'язково)'**
  String get notePlaceholder;

  /// No description provided for @dayCard.
  ///
  /// In uk, this message translates to:
  /// **'Картка дня'**
  String get dayCard;

  /// No description provided for @savedSnackbar.
  ///
  /// In uk, this message translates to:
  /// **'Збережено: {mood}'**
  String savedSnackbar(String mood);

  /// No description provided for @saveFailedSnackbar.
  ///
  /// In uk, this message translates to:
  /// **'Не вдалось зберегти. Спробуй ще раз.'**
  String get saveFailedSnackbar;

  /// No description provided for @deleteAccountFailedSnackbar.
  ///
  /// In uk, this message translates to:
  /// **'Не вдалось видалити акаунт. Спробуй ще раз.'**
  String get deleteAccountFailedSnackbar;

  /// No description provided for @lastWeek.
  ///
  /// In uk, this message translates to:
  /// **'Останній тиждень'**
  String get lastWeek;

  /// No description provided for @thisWeek.
  ///
  /// In uk, this message translates to:
  /// **'Цей тиждень'**
  String get thisWeek;

  /// No description provided for @previousWeek.
  ///
  /// In uk, this message translates to:
  /// **'Минулий тиждень'**
  String get previousWeek;

  /// No description provided for @checkEmailToConfirm.
  ///
  /// In uk, this message translates to:
  /// **'Перевір пошту — надіслали лист для підтвердження'**
  String get checkEmailToConfirm;

  /// No description provided for @somethingWentWrong.
  ///
  /// In uk, this message translates to:
  /// **'Щось пішло не так. Спробуй ще раз.'**
  String get somethingWentWrong;

  /// No description provided for @googleSignInFailed.
  ///
  /// In uk, this message translates to:
  /// **'Не вдалось увійти через Google.'**
  String get googleSignInFailed;

  /// No description provided for @createAccount.
  ///
  /// In uk, this message translates to:
  /// **'Створи акаунт'**
  String get createAccount;

  /// No description provided for @signInToAccount.
  ///
  /// In uk, this message translates to:
  /// **'Увійди в акаунт'**
  String get signInToAccount;

  /// No description provided for @emailHint.
  ///
  /// In uk, this message translates to:
  /// **'Email'**
  String get emailHint;

  /// No description provided for @passwordHint.
  ///
  /// In uk, this message translates to:
  /// **'Пароль'**
  String get passwordHint;

  /// No description provided for @signUp.
  ///
  /// In uk, this message translates to:
  /// **'Зареєструватись'**
  String get signUp;

  /// No description provided for @signIn.
  ///
  /// In uk, this message translates to:
  /// **'Увійти'**
  String get signIn;

  /// No description provided for @alreadyHaveAccount.
  ///
  /// In uk, this message translates to:
  /// **'Вже є акаунт? Увійти'**
  String get alreadyHaveAccount;

  /// No description provided for @noAccountYet.
  ///
  /// In uk, this message translates to:
  /// **'Немає акаунту? Зареєструватись'**
  String get noAccountYet;

  /// No description provided for @continueWithGoogle.
  ///
  /// In uk, this message translates to:
  /// **'Продовжити з Google'**
  String get continueWithGoogle;

  /// No description provided for @couldNotLoadHistory.
  ///
  /// In uk, this message translates to:
  /// **'Не вдалось завантажити історію.'**
  String get couldNotLoadHistory;

  /// No description provided for @couldNotLoadTodayEntry.
  ///
  /// In uk, this message translates to:
  /// **'Не вдалось перевірити сьогоднішній запис. Спробуй ще раз, щоб не створити дублікат.'**
  String get couldNotLoadTodayEntry;

  /// No description provided for @noEntriesThisMonth.
  ///
  /// In uk, this message translates to:
  /// **'У цьому місяці ще немає записів.'**
  String get noEntriesThisMonth;

  /// No description provided for @shareFailed.
  ///
  /// In uk, this message translates to:
  /// **'Не вдалось поділитись. Спробуй ще раз.'**
  String get shareFailed;

  /// No description provided for @prepareCardFailed.
  ///
  /// In uk, this message translates to:
  /// **'Не вдалось підготувати картку. Спробуй ще раз.'**
  String get prepareCardFailed;

  /// No description provided for @share.
  ///
  /// In uk, this message translates to:
  /// **'Поділитись'**
  String get share;

  /// No description provided for @shareOnSocial.
  ///
  /// In uk, this message translates to:
  /// **'Поділитись у соцмережах'**
  String get shareOnSocial;

  /// No description provided for @shareEverywhereHint.
  ///
  /// In uk, this message translates to:
  /// **'Тапни застосунок — після повернення тапни наступний.'**
  String get shareEverywhereHint;

  /// No description provided for @other.
  ///
  /// In uk, this message translates to:
  /// **'Інше'**
  String get other;

  /// No description provided for @notInstalled.
  ///
  /// In uk, this message translates to:
  /// **'{app} не встановлено на пристрої.'**
  String notInstalled(String app);

  /// No description provided for @myDayInNepogano.
  ///
  /// In uk, this message translates to:
  /// **'Мій день з Nepogano'**
  String get myDayInNepogano;

  /// No description provided for @friends.
  ///
  /// In uk, this message translates to:
  /// **'Друзі'**
  String get friends;

  /// No description provided for @addFriend.
  ///
  /// In uk, this message translates to:
  /// **'Додати друга'**
  String get addFriend;

  /// No description provided for @couldNotLoadFriends.
  ///
  /// In uk, this message translates to:
  /// **'Не вдалось завантажити друзів.'**
  String get couldNotLoadFriends;

  /// No description provided for @couldNotAcceptInvite.
  ///
  /// In uk, this message translates to:
  /// **'Не вдалось прийняти запрошення.'**
  String get couldNotAcceptInvite;

  /// No description provided for @invitations.
  ///
  /// In uk, this message translates to:
  /// **'Запрошення'**
  String get invitations;

  /// No description provided for @accept.
  ///
  /// In uk, this message translates to:
  /// **'Прийняти'**
  String get accept;

  /// No description provided for @noFriendsYet.
  ///
  /// In uk, this message translates to:
  /// **'Ще немає друзів. Додай когось кнопкою вгорі.'**
  String get noFriendsYet;

  /// No description provided for @removeFriend.
  ///
  /// In uk, this message translates to:
  /// **'Видалити з друзів'**
  String get removeFriend;

  /// No description provided for @removeFriendConfirmTitle.
  ///
  /// In uk, this message translates to:
  /// **'Видалити з друзів?'**
  String get removeFriendConfirmTitle;

  /// No description provided for @removeFriendConfirmBody.
  ///
  /// In uk, this message translates to:
  /// **'Ви більше не будете бачити чек-іни одне одного.'**
  String get removeFriendConfirmBody;

  /// No description provided for @couldNotRemoveFriend.
  ///
  /// In uk, this message translates to:
  /// **'Не вдалось видалити з друзів.'**
  String get couldNotRemoveFriend;

  /// No description provided for @invite.
  ///
  /// In uk, this message translates to:
  /// **'Запросити'**
  String get invite;

  /// No description provided for @personEmailHint.
  ///
  /// In uk, this message translates to:
  /// **'Email людини'**
  String get personEmailHint;

  /// No description provided for @inviteFriendByEmail.
  ///
  /// In uk, this message translates to:
  /// **'Запросити друга по email'**
  String get inviteFriendByEmail;

  /// No description provided for @friendInviteSent.
  ///
  /// In uk, this message translates to:
  /// **'Запрошення надіслано. Людина побачить його, коли відкриє \"Друзі\" в застосунку.'**
  String get friendInviteSent;

  /// No description provided for @couldNotInviteFriend.
  ///
  /// In uk, this message translates to:
  /// **'Не вдалось запросити. Можливо, вже запрошений.'**
  String get couldNotInviteFriend;

  /// No description provided for @shareMyLink.
  ///
  /// In uk, this message translates to:
  /// **'Поділитися посиланням'**
  String get shareMyLink;

  /// No description provided for @friendInviteShareText.
  ///
  /// In uk, this message translates to:
  /// **'{name} хоче додати тебе другом у Nepogano!\n\nhttps://nepogano.app/join/{code}'**
  String friendInviteShareText(String name, String code);

  /// No description provided for @haveCode.
  ///
  /// In uk, this message translates to:
  /// **'Маю код'**
  String get haveCode;

  /// No description provided for @enterFriendCode.
  ///
  /// In uk, this message translates to:
  /// **'Ввести код друга'**
  String get enterFriendCode;

  /// No description provided for @friendCodeHint.
  ///
  /// In uk, this message translates to:
  /// **'Код друга'**
  String get friendCodeHint;

  /// No description provided for @join.
  ///
  /// In uk, this message translates to:
  /// **'Додати'**
  String get join;

  /// No description provided for @invalidInviteCode.
  ///
  /// In uk, this message translates to:
  /// **'Невірний код запрошення.'**
  String get invalidInviteCode;

  /// No description provided for @friendRequestTitle.
  ///
  /// In uk, this message translates to:
  /// **'Хтось хоче додати тебе другом'**
  String get friendRequestTitle;

  /// No description provided for @friendRequestTitleNamed.
  ///
  /// In uk, this message translates to:
  /// **'{name} хоче додати тебе другом'**
  String friendRequestTitleNamed(String name);

  /// No description provided for @friendAdded.
  ///
  /// In uk, this message translates to:
  /// **'Готово! Тепер ви друзі.'**
  String get friendAdded;

  /// No description provided for @editDisplayName.
  ///
  /// In uk, this message translates to:
  /// **'Твоє ім\'я'**
  String get editDisplayName;

  /// No description provided for @displayNameHint.
  ///
  /// In uk, this message translates to:
  /// **'Як тебе підписати для друзів'**
  String get displayNameHint;

  /// No description provided for @setDisplayName.
  ///
  /// In uk, this message translates to:
  /// **'Додати своє ім\'я'**
  String get setDisplayName;

  /// No description provided for @couldNotSaveDisplayName.
  ///
  /// In uk, this message translates to:
  /// **'Не вдалось зберегти ім\'я.'**
  String get couldNotSaveDisplayName;

  /// No description provided for @notCheckedInToday.
  ///
  /// In uk, this message translates to:
  /// **'Давно не було новин'**
  String get notCheckedInToday;

  /// No description provided for @guessedRight.
  ///
  /// In uk, this message translates to:
  /// **'вгадав(ла)'**
  String get guessedRight;

  /// No description provided for @guessedWrong.
  ///
  /// In uk, this message translates to:
  /// **'не вгадав(ла)'**
  String get guessedWrong;

  /// No description provided for @howAreTheyToday.
  ///
  /// In uk, this message translates to:
  /// **'Як думаєш, як у них?'**
  String get howAreTheyToday;

  /// No description provided for @couldNotSaveGuess.
  ///
  /// In uk, this message translates to:
  /// **'Не вдалось зберегти здогадку.'**
  String get couldNotSaveGuess;

  /// No description provided for @guessStats.
  ///
  /// In uk, this message translates to:
  /// **'Друзі вгадали твій настрій {correct} із {total} ({percent}%)'**
  String guessStats(int correct, int total, int percent);

  /// No description provided for @allFriends.
  ///
  /// In uk, this message translates to:
  /// **'Усі'**
  String get allFriends;

  /// No description provided for @newFolder.
  ///
  /// In uk, this message translates to:
  /// **'Нове коло'**
  String get newFolder;

  /// No description provided for @folderNameHint.
  ///
  /// In uk, this message translates to:
  /// **'Наприклад, Родина'**
  String get folderNameHint;

  /// No description provided for @create.
  ///
  /// In uk, this message translates to:
  /// **'Створити'**
  String get create;

  /// No description provided for @couldNotCreateFolder.
  ///
  /// In uk, this message translates to:
  /// **'Не вдалось створити коло.'**
  String get couldNotCreateFolder;

  /// No description provided for @addToFolder.
  ///
  /// In uk, this message translates to:
  /// **'Додати в коло'**
  String get addToFolder;

  /// No description provided for @noFoldersYet.
  ///
  /// In uk, this message translates to:
  /// **'Ще немає кіл.'**
  String get noFoldersYet;

  /// No description provided for @removeFolderConfirmTitle.
  ///
  /// In uk, this message translates to:
  /// **'Видалити коло {name}?'**
  String removeFolderConfirmTitle(String name);

  /// No description provided for @couldNotRemoveFolder.
  ///
  /// In uk, this message translates to:
  /// **'Не вдалось видалити коло.'**
  String get couldNotRemoveFolder;

  /// No description provided for @me.
  ///
  /// In uk, this message translates to:
  /// **'Я'**
  String get me;

  /// No description provided for @newSubject.
  ///
  /// In uk, this message translates to:
  /// **'Новий щоденник'**
  String get newSubject;

  /// No description provided for @subjectNameHint.
  ///
  /// In uk, this message translates to:
  /// **'Ім\'я (наприклад, Тьома)'**
  String get subjectNameHint;

  /// No description provided for @subjectKindChild.
  ///
  /// In uk, this message translates to:
  /// **'Дитина'**
  String get subjectKindChild;

  /// No description provided for @subjectKindPet.
  ///
  /// In uk, this message translates to:
  /// **'Улюбленець'**
  String get subjectKindPet;

  /// No description provided for @subjectKindOther.
  ///
  /// In uk, this message translates to:
  /// **'Інше'**
  String get subjectKindOther;

  /// No description provided for @couldNotCreateSubject.
  ///
  /// In uk, this message translates to:
  /// **'Не вдалось створити.'**
  String get couldNotCreateSubject;

  /// No description provided for @removeSubjectConfirmTitle.
  ///
  /// In uk, this message translates to:
  /// **'Видалити щоденник {name}?'**
  String removeSubjectConfirmTitle(String name);

  /// No description provided for @removeSubjectConfirmBody.
  ///
  /// In uk, this message translates to:
  /// **'Усі записи буде видалено назавжди.'**
  String get removeSubjectConfirmBody;

  /// No description provided for @couldNotRemoveSubject.
  ///
  /// In uk, this message translates to:
  /// **'Не вдалось видалити.'**
  String get couldNotRemoveSubject;

  /// No description provided for @updatedCount.
  ///
  /// In uk, this message translates to:
  /// **'Оновлено {count, plural, one{{count} раз} few{{count} рази} many{{count} разів} other{{count} разів}}'**
  String updatedCount(int count);

  /// No description provided for @language.
  ///
  /// In uk, this message translates to:
  /// **'Мова'**
  String get language;

  /// No description provided for @today.
  ///
  /// In uk, this message translates to:
  /// **'сьогодні'**
  String get today;

  /// No description provided for @yesterday.
  ///
  /// In uk, this message translates to:
  /// **'вчора'**
  String get yesterday;

  /// No description provided for @thisMonth.
  ///
  /// In uk, this message translates to:
  /// **'Цей місяць'**
  String get thisMonth;
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
      <String>['en', 'uk'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'uk':
      return AppLocalizationsUk();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
