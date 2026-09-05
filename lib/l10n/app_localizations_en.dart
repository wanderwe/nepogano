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
  String get discardLetterConfirmTitle => 'Discard this letter?';

  @override
  String get discardLetterConfirmBody => 'The text you wrote will be lost.';

  @override
  String get keepWriting => 'Keep writing';

  @override
  String get discardLetter => 'Discard';

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
  String get updateRequiredTitle => 'Update required';

  @override
  String get updateRequiredBody =>
      'This version of Nepogano is out of date. Update the app to keep using it.';

  @override
  String get updateRequiredButton => 'Update the app';

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
  String get showOlder => 'Show older';

  @override
  String get moodNiyak => 'Meh';

  @override
  String get moodNepogano => 'Fine';

  @override
  String get moodZbs => 'Awesome';

  @override
  String get todayWasPrefix => 'Today was';

  @override
  String get yesterdayWasPrefix => 'Yesterday was';

  @override
  String get skip => 'Skip';

  @override
  String get next => 'Next';

  @override
  String get getStarted => 'Get started';

  @override
  String get onboarding1Headline => 'Unfiltered day';

  @override
  String get onboarding1Body =>
      'Not every day has to look amazing, and that\'s fine. Just note it honestly, exactly as it happened.';

  @override
  String get onboarding4Headline => 'Close ones nearby';

  @override
  String get onboarding4Body =>
      'Only the people you actually know, no endless feed of strangers. Add friends and try to guess their mood.';

  @override
  String get onboarding5Headline => 'Monthly recap';

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
      'Drag or zoom the photo to adjust the frame for your post';

  @override
  String get repositionPhotoHintAvatar =>
      'Drag or zoom the photo to adjust the frame for your avatar';

  @override
  String get repositionPhotoTooltip => 'Reposition photo';

  @override
  String get changePhotoTooltip => 'Change photo';

  @override
  String get repositionPhotoDayCardPreview => 'Day card preview';

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
  String get howAreThingsYesterday => 'How was yesterday?';

  @override
  String get yesterdayIntroTitle => 'Yesterday\'s entry';

  @override
  String get yesterdayIntroBody =>
      'Missed yesterday? You can still create or fix yesterday\'s entry until noon. Tap today\'s dot to go back.';

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
  String get notePlaceholder => 'About your day (optional)';

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
  String get accountAlreadyRegistered =>
      'This account already exists and is confirmed. Try signing in instead.';

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
  String signUpCooldown(int seconds) {
    return 'Sign up (${seconds}s)';
  }

  @override
  String get signIn => 'Sign in';

  @override
  String get alreadyHaveAccountQuestion => 'Already have an account?';

  @override
  String get noAccountYetQuestion => 'No account yet?';

  @override
  String get unnamedFriend => 'Friend';

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
  String get noEntryForDay => 'There\'s no entry for this day.';

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
  String get myConstellationInNepogano => 'My constellation with Nepogano';

  @override
  String subjectConstellationInNepogano(String name) {
    return '$name\'s constellation with Nepogano';
  }

  @override
  String get friends => 'Friends';

  @override
  String get profile => 'Profile';

  @override
  String get myFriendCode => 'Your friend-code';

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
  String get editDisplayName => 'Name or nickname';

  @override
  String get displayNameHint => 'How friends will see you';

  @override
  String get setDisplayName => 'Add name or nickname';

  @override
  String get couldNotSaveDisplayName => 'Couldn\'t save your name.';

  @override
  String get couldNotSaveAvatar => 'Couldn\'t save your avatar.';

  @override
  String get removeAvatar => 'Remove photo';

  @override
  String get removeAvatarConfirmTitle => 'Remove photo?';

  @override
  String get removeAvatarConfirmBody =>
      'The first letter of your name will show instead.';

  @override
  String get couldNotRemoveAvatar => 'Couldn\'t remove the photo.';

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
  String friendGuessStats(String correct, String total, int percent) {
    return 'Guesses you: $correct/$total ($percent%)';
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
  String get commentActivityMarkAllRead => 'Mark all as read';

  @override
  String get commentActivityMarkedAllRead => 'All comments marked as read';

  @override
  String get commentActivityMarkAllReadConfirmTitle => 'Mark all as read?';

  @override
  String get commentActivityMarkAllReadConfirmBody =>
      'All unread comments will be marked as read, this can\'t be undone.';

  @override
  String get commentActivityMarkAllReadConfirmYes => 'Yes, mark them';

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
  String get subjectIntroTitle => 'About extra diaries';

  @override
  String get subjectIntroBody =>
      'All your friends can see your personal diary. A new diary is only visible to you by default. If you want to share it, open it up for a friend circle to view, or add co-authors who can edit it.';

  @override
  String get gotIt => 'Got it';

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
  String get nudgeListTitle => 'Who\'s curious';

  @override
  String get nudgeBanner => 'Curious about you';

  @override
  String get language => 'Language';

  @override
  String get today => 'today';

  @override
  String get yesterday => 'yesterday';

  @override
  String get thisMonth => 'This month';

  @override
  String get exportMonth => 'Export month';

  @override
  String get calendarView => 'Calendar';

  @override
  String get constellationView => 'Constellation';

  @override
  String get viewEntry => 'View';

  @override
  String get constellationIntroTitle => 'About Constellation';

  @override
  String get constellationIntroBody =>
      'Each day becomes a star, and every month\'s constellation is unique. A longer note or photo makes the star brighter.';

  @override
  String get exportMonthDisabledHint =>
      'No entries this month yet to report on.';

  @override
  String get reportMoodDistribution => 'Mood distribution';

  @override
  String reportDaysFilled(int filled, int total, int missed) {
    return '$filled of $total days logged ($missed missed)';
  }

  @override
  String reportWeekdayInsight(String weekday) {
    return 'Mood tends to dip on $weekday';
  }

  @override
  String get reportNotesSection => 'Month\'s notes';

  @override
  String get reportConstellationSection => 'Month\'s constellation';

  @override
  String get reportNoNote => 'No note';

  @override
  String get reportFooterBrand => 'nepogano.app';

  @override
  String get timeCapsulesMenuLabel => 'Time capsules';

  @override
  String get timeCapsulesRecipientSelf => 'Myself';

  @override
  String get timeCapsulesEmptyTitle => 'A letter into the future';

  @override
  String get timeCapsulesEmptySubtitle =>
      'Pick when: a month, six months, or a year. It\'s sealed until then, keeping today exactly as it really was.';

  @override
  String get timeCapsulesWriteFirst => 'Write your first letter';

  @override
  String get timeCapsulesWriteNew => 'Write a new letter';

  @override
  String get timeCapsulesComposeHint => 'Write your letter...';

  @override
  String get timeCapsulesDelayMonth => '1 month';

  @override
  String get timeCapsulesDelayHalfYear => '6 months';

  @override
  String get timeCapsulesDelayYear => '1 year';

  @override
  String get timeCapsulesSeal => 'Seal it';

  @override
  String get timeCapsuleToSelfLabel => 'Letter to yourself';

  @override
  String get timeCapsuleRecipientDeletedLabel =>
      'To a friend (account deleted)';

  @override
  String timeCapsuleToFriendLabel(String name) {
    return 'Letter for $name';
  }

  @override
  String timeCapsuleFromFriendLabel(String name) {
    return 'Letter from $name';
  }

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
      'The letter will be deleted for good.';

  @override
  String get timeCapsulesSealedConfirmation => 'Letter sealed';

  @override
  String get timeCapsulesBannerReady => 'There\'s news in your time capsules';
}
