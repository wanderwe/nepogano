// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Ukrainian (`uk`).
class AppLocalizationsUk extends AppLocalizations {
  AppLocalizationsUk([String locale = 'uk']) : super(locale);

  @override
  String get cancel => 'Скасувати';

  @override
  String get delete => 'Видалити';

  @override
  String get save => 'Зберегти';

  @override
  String get update => 'Оновити';

  @override
  String get edit => 'Редагувати';

  @override
  String get retry => 'Спробувати ще раз';

  @override
  String get done => 'Готово';

  @override
  String get back => 'Назад';

  @override
  String get or => 'або';

  @override
  String get moodNiyak => 'Ніяк';

  @override
  String get moodNepogano => 'Непогано';

  @override
  String get moodZbs => 'Збс';

  @override
  String get todayWasPrefix => 'Сьогодні було';

  @override
  String get skip => 'Пропустити';

  @override
  String get next => 'Далі';

  @override
  String get getStarted => 'Почати';

  @override
  String get onboarding1Headline => 'Не кожен день неймовірний';

  @override
  String get onboarding1Body =>
      'І це нормально. Тут не треба прикрашати — просто чесно зафіксуй, як минув день.';

  @override
  String get onboarding2Headline => 'Ніяк. Непогано. Збс.';

  @override
  String get onboarding2Body =>
      'Три прості оцінки без пафосу. Жодного тиску відповідати \"чудово\", коли насправді \"так собі\".';

  @override
  String get onboarding4Headline => 'Близькі поруч';

  @override
  String get onboarding4Body =>
      'Додай друзів, побач їхній настрій і спробуй вгадати, як минув їхній день.';

  @override
  String get onboarding5Headline => 'Погляд на місяць';

  @override
  String get onboarding5Body =>
      'Записи складаються в спокійну ретроспективу — без оцінок, просто дзеркало твого місяця.';

  @override
  String get addPhoto => 'Додати фото';

  @override
  String get takePhoto => 'Зробити фото';

  @override
  String get chooseFromGallery => 'Обрати з галереї';

  @override
  String get removePhotoTooltip => 'Прибрати фото';

  @override
  String get repositionPhoto => 'Розташування фото';

  @override
  String get repositionPhotoHint =>
      'Перетягни фото вгору чи вниз, щоб показати потрібну частину';

  @override
  String get repositionPhotoTooltip => 'Змінити розташування фото';

  @override
  String get history => 'Історія';

  @override
  String get moreTooltip => 'Ще';

  @override
  String get signOut => 'Вийти';

  @override
  String get deleteAccount => 'Видалити акаунт';

  @override
  String get deleteAccountConfirmTitle => 'Видалити акаунт?';

  @override
  String get deleteAccountConfirmBody =>
      'Це видалить твій акаунт і всі записи назавжди. Відновити буде неможливо.';

  @override
  String get deleteAccountFinalConfirmTitle => 'Ти точно впевнений?';

  @override
  String get no => 'Ні';

  @override
  String get yesDelete => 'Так, видалити';

  @override
  String get howAreThingsToday => 'Як справи сьогодні?';

  @override
  String alreadySavedToday(String time) {
    return 'Вже збережено о $time';
  }

  @override
  String get notePlaceholder => 'Пару слів про день (необов\'язково)';

  @override
  String get dayCard => 'Картка дня';

  @override
  String savedSnackbar(String mood) {
    return 'Збережено: $mood';
  }

  @override
  String get saveFailedSnackbar => 'Не вдалось зберегти. Спробуй ще раз.';

  @override
  String get deleteAccountFailedSnackbar =>
      'Не вдалось видалити акаунт. Спробуй ще раз.';

  @override
  String get lastWeek => 'Останній тиждень';

  @override
  String get thisWeek => 'Цей тиждень';

  @override
  String get previousWeek => 'Минулий тиждень';

  @override
  String get checkEmailToConfirm =>
      'Перевір пошту — надіслали лист для підтвердження';

  @override
  String get somethingWentWrong => 'Щось пішло не так. Спробуй ще раз.';

  @override
  String get googleSignInFailed => 'Не вдалось увійти через Google.';

  @override
  String get createAccount => 'Створи акаунт';

  @override
  String get signInToAccount => 'Увійди в акаунт';

  @override
  String get emailHint => 'Email';

  @override
  String get passwordHint => 'Пароль';

  @override
  String get signUp => 'Зареєструватись';

  @override
  String get signIn => 'Увійти';

  @override
  String get alreadyHaveAccount => 'Вже є акаунт? Увійти';

  @override
  String get noAccountYet => 'Немає акаунту? Зареєструватись';

  @override
  String get continueWithGoogle => 'Продовжити з Google';

  @override
  String get couldNotLoadHistory => 'Не вдалось завантажити історію.';

  @override
  String get couldNotLoadTodayEntry =>
      'Не вдалось перевірити сьогоднішній запис. Спробуй ще раз, щоб не створити дублікат.';

  @override
  String get noEntriesThisMonth => 'У цьому місяці ще немає записів.';

  @override
  String get shareFailed => 'Не вдалось поділитись. Спробуй ще раз.';

  @override
  String get prepareCardFailed =>
      'Не вдалось підготувати картку. Спробуй ще раз.';

  @override
  String get share => 'Поділитись';

  @override
  String get shareOnSocial => 'Поділитись у соцмережах';

  @override
  String get shareEverywhereHint =>
      'Тапни застосунок — після повернення тапни наступний.';

  @override
  String get other => 'Інше';

  @override
  String notInstalled(String app) {
    return '$app не встановлено на пристрої.';
  }

  @override
  String get myDayInNepogano => 'Мій день з Nepogano';

  @override
  String get friends => 'Друзі';

  @override
  String get addFriend => 'Додати друга';

  @override
  String get couldNotLoadFriends => 'Не вдалось завантажити друзів.';

  @override
  String get couldNotAcceptInvite => 'Не вдалось прийняти запрошення.';

  @override
  String get invitations => 'Запрошення';

  @override
  String get sharedDiaries => 'Спільні щоденники';

  @override
  String get accept => 'Прийняти';

  @override
  String get noFriendsYet => 'Ще немає друзів. Додай когось кнопкою вгорі.';

  @override
  String get removeFriend => 'Видалити з друзів';

  @override
  String get removeFriendConfirmTitle => 'Видалити з друзів?';

  @override
  String get removeFriendConfirmBody =>
      'Ви більше не будете бачити чек-іни одне одного.';

  @override
  String get couldNotRemoveFriend => 'Не вдалось видалити з друзів.';

  @override
  String get invite => 'Запросити';

  @override
  String get personEmailHint => 'Email людини';

  @override
  String get inviteFriendByEmail => 'Запросити друга по email';

  @override
  String get friendInviteSent =>
      'Запрошення надіслано. Людина побачить його, коли відкриє \"Друзі\" в застосунку.';

  @override
  String get couldNotInviteFriend =>
      'Не вдалось запросити. Можливо, вже запрошений.';

  @override
  String get shareMyLink => 'Поділитися посиланням';

  @override
  String friendInviteShareText(String name, String code) {
    return '$name хоче додати тебе другом у Nepogano!\n\nhttps://nepogano.app/join/$code';
  }

  @override
  String get haveCode => 'Маю код';

  @override
  String get enterFriendCode => 'Ввести код друга';

  @override
  String get friendCodeHint => 'Код друга';

  @override
  String get join => 'Додати';

  @override
  String get invalidInviteCode => 'Невірний код запрошення.';

  @override
  String get friendRequestTitle => 'Хтось хоче додати тебе другом';

  @override
  String friendRequestTitleNamed(String name) {
    return '$name хоче додати тебе другом';
  }

  @override
  String get friendAdded => 'Готово! Тепер ви друзі.';

  @override
  String get editDisplayName => 'Твоє ім\'я';

  @override
  String get displayNameHint => 'Як тебе підписати для друзів';

  @override
  String get setDisplayName => 'Додати своє ім\'я';

  @override
  String get couldNotSaveDisplayName => 'Не вдалось зберегти ім\'я.';

  @override
  String get notCheckedInToday => 'Давно не було новин';

  @override
  String get guessedRight => 'вгадав(ла)';

  @override
  String get guessedWrong => 'не вгадав(ла)';

  @override
  String get howAreTheyToday => 'Як думаєш, як у них?';

  @override
  String get couldNotSaveGuess => 'Не вдалось зберегти здогадку.';

  @override
  String guessStats(int correct, int total, int percent) {
    return 'Друзі вгадали твій настрій $correct із $total ($percent%)';
  }

  @override
  String get allFriends => 'Усі';

  @override
  String get newFolder => 'Нове коло';

  @override
  String get folderNameHint => 'Наприклад, Родина';

  @override
  String get create => 'Створити';

  @override
  String get couldNotCreateFolder => 'Не вдалось створити коло.';

  @override
  String get addToFolder => 'Додати в коло';

  @override
  String get noFoldersYet => 'Ще немає кіл.';

  @override
  String removeFolderConfirmTitle(String name) {
    return 'Видалити коло $name?';
  }

  @override
  String get couldNotRemoveFolder => 'Не вдалось видалити коло.';

  @override
  String get me => 'Я';

  @override
  String get newSubject => 'Новий щоденник';

  @override
  String get subjectNameHint => 'Ім\'я (наприклад, Тьома)';

  @override
  String get subjectKindChild => 'Дитина';

  @override
  String get subjectKindPet => 'Улюбленець';

  @override
  String get subjectKindOther => 'Інше';

  @override
  String get couldNotCreateSubject => 'Не вдалось створити.';

  @override
  String removeSubjectConfirmTitle(String name) {
    return 'Видалити щоденник $name?';
  }

  @override
  String get removeSubjectConfirmBody => 'Усі записи буде видалено назавжди.';

  @override
  String get couldNotRemoveSubject => 'Не вдалось видалити.';

  @override
  String get shareWithCircle => 'Поділитись з колом';

  @override
  String get deleteDiary => 'Видалити щоденник';

  @override
  String get noFoldersYetForSharing =>
      'Спершу створи коло на екрані \"Друзі\".';

  @override
  String shareSubjectTitle(String name) {
    return 'Кому видно щоденник $name';
  }

  @override
  String updatedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count разів',
      many: '$count разів',
      few: '$count рази',
      one: '$count раз',
    );
    return 'Оновлено $_temp0';
  }

  @override
  String get language => 'Мова';

  @override
  String get today => 'сьогодні';

  @override
  String get yesterday => 'вчора';

  @override
  String get thisMonth => 'Цей місяць';
}
