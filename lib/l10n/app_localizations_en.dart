// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get cancel => 'Cancel';

  @override
  String get delete => 'Delete';

  @override
  String get save => 'Save';

  @override
  String get update => 'Update';

  @override
  String get edit => 'Edit';

  @override
  String get retry => 'Try again';

  @override
  String get done => 'Done';

  @override
  String get back => 'Back';

  @override
  String get or => 'or';

  @override
  String get moodNiyak => 'Meh';

  @override
  String get moodNepogano => 'Not bad';

  @override
  String get moodZbs => 'Awesome';

  @override
  String get todayWasPrefix => 'Today was';

  @override
  String get skip => 'Skip';

  @override
  String get next => 'Next';

  @override
  String get getStarted => 'Get started';

  @override
  String get onboarding1Headline => 'Not every day is amazing';

  @override
  String get onboarding1Body =>
      'And that\'s fine. No need to dress it up here — just honestly note how the day went.';

  @override
  String get onboarding2Headline => 'Meh. Not bad. Awesome.';

  @override
  String get onboarding2Body =>
      'Three plain ratings, no hype. No pressure to say \"amazing\" when it was really just okay.';

  @override
  String get onboarding4Headline => 'Close ones, close by';

  @override
  String get onboarding4Body =>
      'Add friends, see how they\'re doing, and try to guess how their day went.';

  @override
  String get onboarding5Headline => 'A look back at your month';

  @override
  String get onboarding5Body =>
      'Your entries add up into a quiet retrospective — no scoring, just a mirror of your month.';

  @override
  String get addPhoto => 'Add photo';

  @override
  String get takePhoto => 'Take photo';

  @override
  String get chooseFromGallery => 'Choose from gallery';

  @override
  String get removePhotoTooltip => 'Remove photo';

  @override
  String get repositionPhoto => 'Reposition photo';

  @override
  String get repositionPhotoHint =>
      'Drag the photo up or down to show the right part';

  @override
  String get repositionPhotoTooltip => 'Reposition photo';

  @override
  String get history => 'History';

  @override
  String get moreTooltip => 'More';

  @override
  String get signOut => 'Sign out';

  @override
  String get deleteAccount => 'Delete account';

  @override
  String get deleteAccountConfirmTitle => 'Delete account?';

  @override
  String get deleteAccountConfirmBody =>
      'This will permanently delete your account and all entries. This cannot be undone.';

  @override
  String get deleteAccountFinalConfirmTitle => 'Are you absolutely sure?';

  @override
  String get no => 'No';

  @override
  String get yesDelete => 'Yes, delete';

  @override
  String get howAreThingsToday => 'How\'s it going today?';

  @override
  String alreadySavedToday(String time) {
    return 'Already saved at $time';
  }

  @override
  String get notePlaceholder => 'A few words about your day (optional)';

  @override
  String get dayCard => 'Day card';

  @override
  String savedSnackbar(String mood) {
    return 'Saved: $mood';
  }

  @override
  String get saveFailedSnackbar => 'Couldn\'t save. Try again.';

  @override
  String get deleteAccountFailedSnackbar =>
      'Couldn\'t delete account. Try again.';

  @override
  String get lastWeek => 'Last week';

  @override
  String get thisWeek => 'This week';

  @override
  String get previousWeek => 'Previous week';

  @override
  String get checkEmailToConfirm =>
      'Check your email — we sent a confirmation link';

  @override
  String get somethingWentWrong => 'Something went wrong. Try again.';

  @override
  String get googleSignInFailed => 'Couldn\'t sign in with Google.';

  @override
  String get createAccount => 'Create an account';

  @override
  String get signInToAccount => 'Sign in to your account';

  @override
  String get emailHint => 'Email';

  @override
  String get passwordHint => 'Password';

  @override
  String get signUp => 'Sign up';

  @override
  String get signIn => 'Sign in';

  @override
  String get alreadyHaveAccount => 'Already have an account? Sign in';

  @override
  String get noAccountYet => 'No account yet? Sign up';

  @override
  String get continueWithGoogle => 'Continue with Google';

  @override
  String get couldNotLoadHistory => 'Couldn\'t load history.';

  @override
  String get couldNotLoadTodayEntry =>
      'Couldn\'t check today\'s entry. Try again to avoid creating a duplicate.';

  @override
  String get noEntriesThisMonth => 'No entries yet this month.';

  @override
  String get shareFailed => 'Couldn\'t share. Try again.';

  @override
  String get prepareCardFailed => 'Couldn\'t prepare the card. Try again.';

  @override
  String get share => 'Share';

  @override
  String get shareOnSocial => 'Share on social media';

  @override
  String get shareEverywhereHint =>
      'Tap an app, then come back and tap the next one.';

  @override
  String get other => 'Other';

  @override
  String notInstalled(String app) {
    return '$app isn\'t installed on this device.';
  }

  @override
  String get myDayInNepogano => 'My day with Nepogano';

  @override
  String get friends => 'Friends';

  @override
  String get addFriend => 'Add friend';

  @override
  String get couldNotLoadFriends => 'Couldn\'t load friends.';

  @override
  String get couldNotAcceptInvite => 'Couldn\'t accept the invite.';

  @override
  String get invitations => 'Invitations';

  @override
  String get accept => 'Accept';

  @override
  String get noFriendsYet =>
      'No friends yet. Add someone with the button above.';

  @override
  String get removeFriend => 'Remove friend';

  @override
  String get removeFriendConfirmTitle => 'Remove this friend?';

  @override
  String get removeFriendConfirmBody =>
      'You\'ll no longer see each other\'s check-ins.';

  @override
  String get couldNotRemoveFriend => 'Couldn\'t remove the friend.';

  @override
  String get invite => 'Invite';

  @override
  String get personEmailHint => 'Person\'s email';

  @override
  String get inviteFriendByEmail => 'Invite a friend by email';

  @override
  String get friendInviteSent =>
      'Sent. They\'ll see the invite when they open \"Friends\" in the app.';

  @override
  String get couldNotInviteFriend =>
      'Couldn\'t invite. They may already be invited.';

  @override
  String get shareMyLink => 'Share my link';

  @override
  String friendInviteShareText(String name, String code) {
    return '$name wants to add you as a friend on Nepogano!\n\nInstall the app and enter this code: $code';
  }

  @override
  String get haveCode => 'I have a code';

  @override
  String get enterFriendCode => 'Enter a friend\'s code';

  @override
  String get friendCodeHint => 'Friend code';

  @override
  String get join => 'Add';

  @override
  String get invalidInviteCode => 'Invalid invite code.';

  @override
  String get friendRequestTitle => 'Someone wants to add you as a friend';

  @override
  String friendRequestTitleNamed(String name) {
    return '$name wants to add you as a friend';
  }

  @override
  String get friendAdded => 'Done! You\'re friends now.';

  @override
  String get editDisplayName => 'Your name';

  @override
  String get displayNameHint => 'How friends will see you';

  @override
  String get setDisplayName => 'Add your name';

  @override
  String get couldNotSaveDisplayName => 'Couldn\'t save your name.';

  @override
  String get notCheckedInToday => 'No news in a while';

  @override
  String get guessedRight => 'you got it';

  @override
  String get guessedWrong => 'not quite';

  @override
  String get howAreTheyToday => 'How do you think they\'re doing?';

  @override
  String get couldNotSaveGuess => 'Couldn\'t save the guess.';

  @override
  String get allFriends => 'All';

  @override
  String get newFolder => 'New folder';

  @override
  String get folderNameHint => 'e.g. Family';

  @override
  String get create => 'Create';

  @override
  String get couldNotCreateFolder => 'Couldn\'t create the folder.';

  @override
  String get addToFolder => 'Add to folder';

  @override
  String get noFoldersYet => 'No folders yet.';

  @override
  String get language => 'Language';

  @override
  String get today => 'today';

  @override
  String get yesterday => 'yesterday';

  @override
  String get thisMonth => 'This month';
}
