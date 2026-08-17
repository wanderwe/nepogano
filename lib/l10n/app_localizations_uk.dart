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
  String get connectionFailedTitle => 'Не вдалось з\'єднатися';

  @override
  String get connectionFailedBody =>
      'Перевір інтернет-з\'єднання і спробуй ще раз.';

  @override
  String get done => 'Готово';

  @override
  String get back => 'Назад';

  @override
  String get or => 'або';

  @override
  String get search => 'Пошук';

  @override
  String get showMore => 'Показати ще';

  @override
  String get moodNiyak => 'Ніяк';

  @override
  String get moodNepogano => 'Непогано';

  @override
  String get moodZbs => 'Чудово';

  @override
  String get todayWasPrefix => 'Сьогодні було';

  @override
  String get skip => 'Пропустити';

  @override
  String get next => 'Далі';

  @override
  String get getStarted => 'Почати';

  @override
  String get onboarding1Headline => 'День без прикрас';

  @override
  String get onboarding1Body =>
      'Не кожен день має бути неймовірним, і це нормально. Просто зафіксуй чесно, як він минув.';

  @override
  String get onboarding2Headline => 'Ніяк. Непогано. Чудово.';

  @override
  String get onboarding2Body =>
      'Три прості слова: швидко й чесно, без тиску вигадувати щось «грандіозне», коли насправді просто «так собі».';

  @override
  String get onboarding4Headline => 'Близькі поруч';

  @override
  String get onboarding4Body =>
      'Лише ті, кого ти справді знаєш, без стрічки незнайомців. Додай друзів і спробуй вгадати, як минув їхній день.';

  @override
  String get onboarding5Headline => 'Місячний підсумок';

  @override
  String get onboarding5Body =>
      'Записи складаються в спокійну ретроспективу: просто дзеркало твого місяця, без оцінок.';

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
      'Перетягни фото вгору чи вниз або зведи пальці, щоб наблизити';

  @override
  String get repositionPhotoTooltip => 'Змінити розташування фото';

  @override
  String get history => 'Історія';

  @override
  String get scrollToTop => 'Прогорнути нагору';

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
  String get dailyReminderTitle => 'Непогано';

  @override
  String get dailyReminderBody => 'Як пройшов день? Занотуй, поки не забув.';

  @override
  String alreadySavedToday(String time) {
    return 'Вже збережено о $time';
  }

  @override
  String get notePlaceholder => 'Про день (необов\'язково)';

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
      'Перевір пошту: надіслали лист для підтвердження';

  @override
  String get somethingWentWrong => 'Щось пішло не так. Спробуй ще раз.';

  @override
  String get googleSignInFailed => 'Не вдалось увійти через Google.';

  @override
  String get appleSignInFailed => 'Не вдалось увійти через Apple.';

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
  String get alreadyHaveAccountQuestion => 'Вже є акаунт?';

  @override
  String get noAccountYetQuestion => 'Немає акаунту?';

  @override
  String get continueWithGoogle => 'Продовжити з Google';

  @override
  String get signInWithApple => 'Увійти через Apple';

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
      'Тапни застосунок, після повернення тапни наступний.';

  @override
  String get other => 'Інше';

  @override
  String notInstalled(String app) {
    return '$app не встановлено на пристрої.';
  }

  @override
  String get myDayInNepogano => 'Мій день з Nepogano';

  @override
  String subjectDayInNepogano(String name) {
    return '$name у Nepogano';
  }

  @override
  String get friends => 'Друзі';

  @override
  String get profile => 'Профіль';

  @override
  String get myFriendCode => 'Твій код для друзів';

  @override
  String get codeCopied => 'Код скопійовано';

  @override
  String get addFriend => 'Додати друга';

  @override
  String get couldNotLoadFriends => 'Не вдалось завантажити друзів.';

  @override
  String get couldNotAcceptInvite => 'Не вдалось прийняти запрошення.';

  @override
  String get invitations => 'Запрошення';

  @override
  String get sharedDiaries => 'Відкрито для перегляду';

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
  String friendInviteShareText(String name, String code, String encodedName) {
    return '$name хоче додати тебе другом у Nepogano!\n\nhttps://nepogano.app/join/$code?name=$encodedName';
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
  String get editDisplayName => 'Ім\'я або нікнейм';

  @override
  String get displayNameHint => 'Як тебе підписати для друзів';

  @override
  String get setDisplayName => 'Додати ім\'я або нікнейм';

  @override
  String get couldNotSaveDisplayName => 'Не вдалось зберегти ім\'я.';

  @override
  String get couldNotSaveAvatar => 'Не вдалось зберегти аватарку.';

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
  String friendGuessStats(int correct, int total, int percent) {
    return 'Вгадує тебе: $correct із $total ($percent%)';
  }

  @override
  String get friendNeverGuessed => 'Ще не вгадував(ла)';

  @override
  String get commentHint => 'Напиши коментар...';

  @override
  String get addComment => 'Додати коментар';

  @override
  String get commentsLabel => 'Коментарі';

  @override
  String commentsCount(int count) {
    return 'Коментарі ($count)';
  }

  @override
  String get postComment => 'Надіслати';

  @override
  String get reply => 'Відповісти';

  @override
  String replyingTo(String name) {
    return 'Відповідаєш $name';
  }

  @override
  String get editedLabel => '(редаговано)';

  @override
  String get commentDeleted => 'Коментар видалено';

  @override
  String get deleteCommentConfirmTitle => 'Видалити коментар?';

  @override
  String get deleteCommentConfirmBody => 'Цю дію не можна скасувати.';

  @override
  String get couldNotLoadComments => 'Не вдалось завантажити коментарі.';

  @override
  String get couldNotPostComment => 'Не вдалось надіслати коментар.';

  @override
  String get couldNotEditComment => 'Не вдалось зберегти зміни.';

  @override
  String get couldNotDeleteComment => 'Не вдалось видалити коментар.';

  @override
  String get commentActivityEmpty => 'Поки що нічого немає';

  @override
  String get commentActivityMarkAllRead => 'Позначити всі переглянутими';

  @override
  String get commentActivityMarkedAllRead =>
      'Усі коментарі позначено переглянутими';

  @override
  String get commentActivityMarkAllReadConfirmTitle =>
      'Позначити всі переглянутими?';

  @override
  String get commentActivityMarkAllReadConfirmBody =>
      'Усі непрочитані коментарі стануть позначеними переглянутими, це не можна скасувати.';

  @override
  String get commentActivityMarkAllReadConfirmYes => 'Так, позначити';

  @override
  String commentActivityNewComment(String name) {
    return 'Новий коментар від $name';
  }

  @override
  String commentActivityReply(String name) {
    return 'Відповідь від $name';
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
  String get renameFolder => 'Перейменувати коло';

  @override
  String get couldNotRenameFolder => 'Не вдалось перейменувати коло.';

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
  String get subjectIntroTitle => 'Про додаткові щоденники';

  @override
  String get subjectIntroBody =>
      'Твій особистий щоденник бачать усі друзі. Новий щоденник за замовчуванням бачиш лише ти. Якщо захочеш поділитись, відкрий на перегляд колу друзів або додай співавторів для редагування.';

  @override
  String get gotIt => 'Зрозуміло';

  @override
  String get subjectNameHint => 'Ім\'я (наприклад, Тьома)';

  @override
  String get subjectKindChild => 'Дитина';

  @override
  String get subjectKindPet => 'Улюбленець';

  @override
  String get subjectKindPartner => 'Партнер';

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
  String get renameDiary => 'Перейменувати';

  @override
  String get couldNotRenameSubject => 'Не вдалось перейменувати.';

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
  String get addCoauthor => 'Додати співавтора';

  @override
  String get someone => 'хтось';

  @override
  String coauthorInfoBody(String name) {
    return 'Щоденник веде $name. Ти можеш писати й редагувати записи, а перейменувати, поділитись чи видалити щоденник може лише $name.';
  }

  @override
  String get leaveCoauthoredDiary => 'Прибрати щоденник';

  @override
  String leaveCoauthoredDiaryConfirmTitle(String name) {
    return 'Прибрати щоденник $name?';
  }

  @override
  String leaveCoauthoredDiaryConfirmBody(String name) {
    return 'Він зникне з твого перемикача. $name і надалі його веде, а якщо захочеш повернутись, треба буде попросити додати ще раз.';
  }

  @override
  String get couldNotLeaveCoauthoredDiary => 'Не вдалось прибрати щоденник.';

  @override
  String coauthorsTitle(String name) {
    return 'Хто ще веде щоденник $name';
  }

  @override
  String get searchFriendHint => 'Пошук друга';

  @override
  String get noFriendsToAddAsCoauthor =>
      'Спершу додай друзів, щоб зробити когось співавтором.';

  @override
  String get noFriendsFoundForSearch => 'Нікого не знайдено.';

  @override
  String authorLabel(String name) {
    return 'Автор: $name';
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
  String get nudgeButtonTooltip => 'Цікаво, як ти';

  @override
  String get nudgeSent => 'Надіслано, друг побачить.';

  @override
  String get couldNotSendNudge => 'Не вдалось надіслати. Спробуй ще раз.';

  @override
  String get nudgeDialogTitle => 'Цікаво, як ти';

  @override
  String get nudgeDialogBody =>
      'Коли друг відкриє застосунок, побачить банер із твоїм ім\'ям: «цікавиться, як ти». Можна раз на тиждень.';

  @override
  String get nudgeDialogSend => 'Надіслати';

  @override
  String nudgeAlreadySent(String date) {
    return 'Вже надіслано. Зможеш ще раз $date.';
  }

  @override
  String get nudgeListTitle => 'Хто цікавиться';

  @override
  String get nudgeBanner => 'Хтось цікавиться, як ти';

  @override
  String get language => 'Мова';

  @override
  String get today => 'сьогодні';

  @override
  String get yesterday => 'вчора';

  @override
  String get thisMonth => 'Цей місяць';

  @override
  String get timeCapsulesMenuLabel => 'Капсули часу';

  @override
  String get timeCapsulesRecipientSelf => 'Собі';

  @override
  String get timeCapsulesEmptyTitle => 'Лист, який відкриється пізніше';

  @override
  String get timeCapsulesEmptySubtitle =>
      'Обери коли: за місяць, півроку чи рік. До того часу він запечатаний, підглянути не вийде.';

  @override
  String get timeCapsulesWriteFirst => 'Написати перший лист';

  @override
  String get timeCapsulesWriteNew => 'Написати новий лист';

  @override
  String get timeCapsulesComposeHint => 'Напиши свій лист...';

  @override
  String get timeCapsulesDelayMonth => '1 місяць';

  @override
  String get timeCapsulesDelayHalfYear => '6 місяців';

  @override
  String get timeCapsulesDelayYear => '1 рік';

  @override
  String get timeCapsulesSeal => 'Запечатати';

  @override
  String get timeCapsuleToSelfLabel => 'Лист собі';

  @override
  String timeCapsuleToFriendLabel(String name) {
    return 'Лист для $name';
  }

  @override
  String timeCapsuleFromFriendLabel(String name) {
    return 'Лист від $name';
  }

  @override
  String get timeCapsulesRecipientLabel => 'Кому';

  @override
  String timeCapsulesLockedUntil(String date) {
    return 'розкриється $date';
  }

  @override
  String timeCapsulesOpenedOn(String date) {
    return 'відкрито $date';
  }

  @override
  String timeCapsulesStillLocked(String date) {
    return 'Ще запечатано, відкриється $date';
  }

  @override
  String get timeCapsulesDeleteConfirmTitle => 'Видалити лист?';

  @override
  String get timeCapsulesDeleteConfirmBody => 'Лист буде видалено назавжди.';

  @override
  String get timeCapsulesSealedConfirmation => 'Лист запечатано';

  @override
  String get timeCapsulesBannerReady => 'У капсулах часу є новина';
}
