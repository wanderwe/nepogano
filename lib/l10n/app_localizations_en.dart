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
  String get connectionFailedTitle => 'Couldn\'t connect';

  @override
  String get connectionFailedBody =>
      'Check your internet connection and try again.';

  @override
  String get done => 'Done';

  @override
  String get back => 'Back';

  @override
  String get or => 'or';

  @override
  String get search => 'Search';

  @override
  String get showMore => 'Show more';

  @override
  String get moodNiyak => 'Meh';

  @override
  String get moodNepogano => 'Fine';

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
  String get onboarding1Headline => 'Your day, no dressing it up';

  @override
  String get onboarding1Body =>
      'Not every day has to be amazing, and that\'s fine. Just honestly note how it went.';

  @override
  String get onboarding2Headline => 'Meh. Fine. Awesome.';

  @override
  String get onboarding2Body =>
      'Three plain words: quick and honest, no pressure to dress it up as \"amazing\" when it was really just okay.';

  @override
  String get onboarding4Headline => 'Close ones, close by';

  @override
  String get onboarding4Body =>
      'Just the people you actually know, no endless feed of strangers. Add friends and try to guess how their day went.';

  @override
  String get onboarding5Headline => 'A look back at your month';

  @override
  String get onboarding5Body =>
      'Your entries add up into a quiet retrospective: just a mirror of your month, no scoring.';

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
      'Drag the photo up or down, or pinch to zoom in';

  @override
  String get repositionPhotoTooltip => 'Reposition photo';

  @override
  String get history => 'History';

  @override
  String get scrollToTop => 'Scroll to top';

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
  String get dailyReminderTitle => 'Nepogano';

  @override
  String get dailyReminderBody =>
      'How was your day? Jot it down before you forget.';

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
      'Check your email: we sent a confirmation link';

  @override
  String get somethingWentWrong => 'Something went wrong. Try again.';

  @override
  String get googleSignInFailed => 'Couldn\'t sign in with Google.';

  @override
  String get appleSignInFailed => 'Couldn\'t sign in with Apple.';

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
  String get signInWithApple => 'Sign in with Apple';

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
  String subjectDayInNepogano(String name) {
    return '$name in Nepogano';
  }

  @override
  String get friends => 'Friends';

  @override
  String get profile => 'Profile';

  @override
  String get myFriendCode => 'My code';

  @override
  String get codeCopied => 'Code copied';

  @override
  String get addFriend => 'Add friend';

  @override
  String get couldNotLoadFriends => 'Couldn\'t load friends.';

  @override
  String get couldNotAcceptInvite => 'Couldn\'t accept the invite.';

  @override
  String get invitations => 'Invitations';

  @override
  String get sharedDiaries => 'Open for viewing';

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
  String friendInviteShareText(String name, String code, String encodedName) {
    return '$name wants to add you as a friend on Nepogano!\n\nhttps://nepogano.app/join/$code?name=$encodedName';
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
  String get couldNotSaveAvatar => 'Couldn\'t save your avatar.';

  @override
  String get notCheckedInToday => 'No news in a while';

  @override
  String get guessedRight => 'Guessed';

  @override
  String get guessedWrong => 'Missed';

  @override
  String get howAreTheyToday => 'How do you think they\'re doing?';

  @override
  String get couldNotSaveGuess => 'Couldn\'t save the guess.';

  @override
  String guessStats(int correct, int total, int percent) {
    return 'Friends guessed your mood $correct out of $total ($percent%)';
  }

  @override
  String friendGuessStats(int correct, int total, int percent) {
    return 'Guesses you: $correct out of $total ($percent%)';
  }

  @override
  String get friendNeverGuessed => 'Hasn\'t guessed yet';

  @override
  String get commentHint => 'Write a comment...';

  @override
  String get addComment => 'Add a comment';

  @override
  String get commentsLabel => 'Comments';

  @override
  String commentsCount(int count) {
    return 'Comments ($count)';
  }

  @override
  String get postComment => 'Send';

  @override
  String get reply => 'Reply';

  @override
  String replyingTo(String name) {
    return 'Replying to $name';
  }

  @override
  String get editedLabel => '(edited)';

  @override
  String get commentDeleted => 'Comment deleted';

  @override
  String get deleteCommentConfirmTitle => 'Delete this comment?';

  @override
  String get deleteCommentConfirmBody => 'This can\'t be undone.';

  @override
  String get couldNotLoadComments => 'Couldn\'t load comments.';

  @override
  String get couldNotPostComment => 'Couldn\'t post the comment.';

  @override
  String get couldNotEditComment => 'Couldn\'t save the changes.';

  @override
  String get couldNotDeleteComment => 'Couldn\'t delete the comment.';

  @override
  String get commentActivityEmpty => 'Nothing here yet';

  @override
  String commentActivityNewComment(String name) {
    return 'New comment from $name';
  }

  @override
  String commentActivityReply(String name) {
    return 'Reply from $name';
  }

  @override
  String get allFriends => 'All';

  @override
  String get newFolder => 'New circle';

  @override
  String get folderNameHint => 'e.g. Family';

  @override
  String get create => 'Create';

  @override
  String get couldNotCreateFolder => 'Couldn\'t create the circle.';

  @override
  String get addToFolder => 'Add to circle';

  @override
  String get renameFolder => 'Rename circle';

  @override
  String get couldNotRenameFolder => 'Couldn\'t rename the circle.';

  @override
  String get noFoldersYet => 'No circles yet.';

  @override
  String removeFolderConfirmTitle(String name) {
    return 'Delete the \"$name\" circle?';
  }

  @override
  String get couldNotRemoveFolder => 'Couldn\'t delete the circle.';

  @override
  String get me => 'Me';

  @override
  String get newSubject => 'New diary';

  @override
  String get subjectNameHint => 'Name (e.g. Emma)';

  @override
  String get subjectKindChild => 'Child';

  @override
  String get subjectKindPet => 'Pet';

  @override
  String get subjectKindPartner => 'Partner';

  @override
  String get subjectKindOther => 'Other';

  @override
  String get couldNotCreateSubject => 'Couldn\'t create it.';

  @override
  String removeSubjectConfirmTitle(String name) {
    return 'Delete $name\'s diary?';
  }

  @override
  String get removeSubjectConfirmBody =>
      'All entries will be deleted permanently.';

  @override
  String get couldNotRemoveSubject => 'Couldn\'t delete it.';

  @override
  String get renameDiary => 'Rename';

  @override
  String get couldNotRenameSubject => 'Couldn\'t rename it.';

  @override
  String get shareWithCircle => 'Share with circle';

  @override
  String get deleteDiary => 'Delete diary';

  @override
  String get noFoldersYetForSharing =>
      'Create a circle on the \"Friends\" screen first.';

  @override
  String shareSubjectTitle(String name) {
    return 'Who can see $name\'s diary';
  }

  @override
  String get addCoauthor => 'Add co-author';

  @override
  String get someone => 'someone';

  @override
  String coauthorInfoBody(String name) {
    return 'This diary is kept by $name. You can write and edit entries, and only $name can rename, share, or delete the diary.';
  }

  @override
  String get leaveCoauthoredDiary => 'Remove diary';

  @override
  String leaveCoauthoredDiaryConfirmTitle(String name) {
    return 'Remove $name?';
  }

  @override
  String leaveCoauthoredDiaryConfirmBody(String name) {
    return 'It\'ll disappear from your switcher. $name still keeps it, and if you want back in, you\'ll need to be added again.';
  }

  @override
  String get couldNotLeaveCoauthoredDiary => 'Couldn\'t remove the diary.';

  @override
  String coauthorsTitle(String name) {
    return 'Who else writes $name\'s diary';
  }

  @override
  String get searchFriendHint => 'Search a friend';

  @override
  String get noFriendsToAddAsCoauthor =>
      'Add some friends first to make someone a co-author.';

  @override
  String get noFriendsFoundForSearch => 'No one found.';

  @override
  String authorLabel(String name) {
    return 'By $name';
  }

  @override
  String updatedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count times',
      one: '$count time',
    );
    return 'Updated $_temp0';
  }

  @override
  String get nudgeButtonTooltip => 'Wondering about you';

  @override
  String get nudgeSent => 'Sent, they\'ll see it.';

  @override
  String get couldNotSendNudge => 'Couldn\'t send. Try again.';

  @override
  String get nudgeDialogTitle => 'Wondering about you';

  @override
  String get nudgeDialogBody =>
      'Next time your friend opens the app, they\'ll see a banner with your name: \"is wondering how you\'re doing.\" You can send it once a week.';

  @override
  String get nudgeDialogSend => 'Send';

  @override
  String nudgeAlreadySent(String date) {
    return 'Already sent. You can again on $date.';
  }

  @override
  String nudgeBannerSolo(String name) {
    return '$name is wondering how you\'re doing';
  }

  @override
  String nudgeBannerMultiple(String name, int restCount) {
    String _temp0 = intl.Intl.pluralLogic(
      restCount,
      locale: localeName,
      other: '$restCount other friends',
      one: '$restCount other friend',
    );
    return '$name and $_temp0 are wondering how you\'re doing';
  }

  @override
  String get language => 'Language';

  @override
  String get today => 'today';

  @override
  String get yesterday => 'yesterday';

  @override
  String get thisMonth => 'This month';

  @override
  String get timeCapsulesMenuLabel => 'Time capsules';

  @override
  String get timeCapsulesEmptyTitle => 'A letter that opens later';

  @override
  String get timeCapsulesEmptySubtitle =>
      'Choose when: a month, half a year, or a year from now. Until then it\'s sealed, no peeking.';

  @override
  String get timeCapsulesWriteFirst => 'Write your first letter';

  @override
  String get timeCapsulesWriteNew => 'Write a new letter';

  @override
  String get timeCapsulesComposeHint => 'Write your letter...';

  @override
  String get timeCapsulesDelayMonth => 'In a month';

  @override
  String get timeCapsulesDelayHalfYear => 'In half a year';

  @override
  String get timeCapsulesDelayYear => 'In a year';

  @override
  String get timeCapsulesSeal => 'Seal it';

  @override
  String get timeCapsuleToSelfLabel => 'Letter to yourself';

  @override
  String timeCapsuleToFriendLabel(String name) {
    return 'Letter for $name';
  }

  @override
  String timeCapsuleFromFriendLabel(String name) {
    return 'Letter from $name';
  }

  @override
  String get timeCapsulesRecipientLabel => 'To';

  @override
  String timeCapsulesLockedUntil(String date) {
    return 'unlocks $date';
  }

  @override
  String timeCapsulesOpenedOn(String date) {
    return 'opened $date';
  }

  @override
  String timeCapsulesStillLocked(String date) {
    return 'Still sealed, opens $date';
  }

  @override
  String get timeCapsulesDeleteConfirmTitle => 'Delete letter?';

  @override
  String get timeCapsulesDeleteConfirmBody =>
      'An unsealed letter can be deleted for good.';

  @override
  String get timeCapsulesSealedConfirmation => 'Letter sealed';

  @override
  String get timeCapsulesBannerReady => 'You have a letter that\'s unlocked';
}
