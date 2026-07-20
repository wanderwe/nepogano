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
  String get onboarding3Headline => 'Без стріків і тиску';

  @override
  String get onboarding3Body =>
      'Заходь, коли хочеш. Це не про дисципліну — це про чесність із собою.';

  @override
  String get onboarding4Headline => 'Кола близьких';

  @override
  String get onboarding4Body =>
      'Створи коло з друзями чи родиною, побач їхній настрій і спробуй вгадати, як минув їхній день.';

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
  String get circle => 'Коло';

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
      'Це видалить твій акаунт і всі записи назавжди. Скасувати неможливо.';

  @override
  String get howAreThingsToday => 'Як справи сьогодні?';

  @override
  String alreadySavedToday(String time) {
    return 'Вже зберіг сьогодні о $time';
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
  String get couldNotLoadCircles => 'Не вдалось завантажити кола.';

  @override
  String get couldNotAcceptInvite => 'Не вдалось прийняти запрошення.';

  @override
  String get newCircle => 'Нове коло';

  @override
  String get circleNameHint => 'Наприклад, Родина';

  @override
  String get create => 'Створити';

  @override
  String get couldNotCreateCircle => 'Не вдалось створити коло.';

  @override
  String get invitations => 'Запрошення';

  @override
  String get accept => 'Прийняти';

  @override
  String get myCircles => 'Мої кола';

  @override
  String get noCirclesYet =>
      'Ще немає жодного кола. Створи своє кнопкою \"+\" зверху.';

  @override
  String get pending => 'Очікують';

  @override
  String get notJoinedYet => 'ще не приєднався(лась)';

  @override
  String get cancelInviteTooltip => 'Скасувати запрошення';

  @override
  String get nobodyHereYet =>
      'Тут поки нікого немає.\nЗапроси когось у це коло.';

  @override
  String get invite => 'Запросити';

  @override
  String get inviteToCircle => 'Запросити в коло';

  @override
  String get personEmailHint => 'Email людини';

  @override
  String get inviteAdded =>
      'Додано. Людина побачить запрошення, коли відкриє \"Коло\" в застосунку.';

  @override
  String get couldNotInvite => 'Не вдалось запросити. Можливо, вже запрошений.';

  @override
  String get couldNotCancelInvite => 'Не вдалось скасувати запрошення.';

  @override
  String get shareInviteLink => 'Поділитися запрошенням';

  @override
  String inviteShareText(String circleName, String code) {
    return 'Приєднайся до мого кола \"$circleName\" у Nepogano!\n\nВстанови застосунок і введи код запрошення: $code';
  }

  @override
  String get joinCircle => 'Приєднатися до кола';

  @override
  String get joinCircleHint => 'Код запрошення';

  @override
  String get join => 'Приєднатися';

  @override
  String get invalidInviteCode => 'Невірний код запрошення.';

  @override
  String get joinedCircleSuccess => 'Готово! Ти приєднався(лась) до кола.';

  @override
  String get haveInviteCode => 'Маю код запрошення';

  @override
  String get inviteByEmail => 'Запросити по email';

  @override
  String get notCheckedInToday => 'Давно не було новин';

  @override
  String get guessedRight => 'вгадав(ла)';

  @override
  String get guessedWrong => 'не вгадав(ла)';

  @override
  String get showDetails => 'Показати деталі';

  @override
  String get hideDetails => 'Сховати деталі';

  @override
  String get howAreTheyToday => 'Як думаєш, як у них?';

  @override
  String get couldNotSaveGuess => 'Не вдалось зберегти здогадку.';

  @override
  String get language => 'Мова';

  @override
  String get recentActivity => 'Нещодавно';

  @override
  String get today => 'сьогодні';

  @override
  String get yesterday => 'вчора';

  @override
  String get thisMonth => 'Цей місяць';
}
