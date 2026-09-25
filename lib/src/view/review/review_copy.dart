// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

// User-visible copy of the review screen, in one place.
//
// Copy drift is invisible in screenshots and survives `./verify`, so every string the
// design fixes is a named constant here, asserted by test/view/review/review_copy_test.dart
// and referenced by the widgets that render it. Changing a word means changing it here.

/// The idle screen's title when nothing is due. Demo: `idleTitle`.
const kSrsNothingDueTitle = 'Nothing due.';

/// The idle screen's title when the daily limit stopped the session.
///
/// Demo: `setIdleCopy(true)` renders `Daily limit reached.` The build previously said
/// `Daily Goal Reached!`, which is the gamified tone the visual identity removes
/// (design/docs/01-identity.md).
const kSrsDailyLimitReachedTitle = 'Daily limit reached.';

/// The idle screen's link into Settings, shown only with the daily-limit title.
/// Demo: `adjustLimitBtn`.
const kSrsAdjustLimitLabel = 'Adjust limit';

/// The idle screen's footnote. Demo: `.foot`.
const kSrsPracticeFootnote = 'Practice never changes your schedule.';

/// Prefix of the idle screen's next-review sentence. The controller's durations already
/// carry their own `in …` prefix, so this must stay bare or the sentence reads
/// `Next review in in 1 day.`. Demo: `Next review in {duration}.`
const kSrsNextReviewPrefix = 'Next review ';

/// Fallback when the scheduler has no next due time. Demo has no equivalent; the state
/// machine reaches this only when there is nothing scheduled at all.
const kSrsNoNextReview = 'Next review will appear automatically.';

/// The help line under the correct move in the correction view. Demo: `.answer-help`.
///
/// The move itself is already rendered large above this line by `_AnswerSlot`, so this
/// deliberately does not name it again.
const kSrsAnswerHelpText = 'Play this move to continue. The position will come back soon.';

/// Attribution under a study note. Demo: `blockquote small`.
const kSrsNoteAttribution = 'From your study';

/// The error screen's title. Demo: `.view-error h1`.
const kSrsErrorTitle = 'Something went wrong.';

/// The one sentence the review error state shows.
///
/// The demo's error scene is written for a *save* failure ("The last review couldn't be
/// saved. Your place is kept; nothing was lost."). This build has no separate save-failure
/// state, so the sentence describes what actually happened and promises nothing: the
/// technical truth is one tap away under `Copy details`.
const kSrsReviewLoadFailedDetail =
    'Reviews could not be loaded. Try again, or copy the details to report this.';

/// Spoken after a correct answer. Demo prototype `say()`: `Correct. {san}.`
String srsCorrectAnnouncement(String san) => 'Correct. $san.';

/// Spoken after any other move. Demo prototype `say()`:
/// `Not this move. The repertoire move is {san}.`
///
/// design/docs/04 §6 also requires that "legal but not the repertoire move" and
/// "illegal" produce the same feedback, which is why there is no second phrasing.
String srsNotThisMoveAnnouncement(String san) => 'Not this move. The repertoire move is $san.';

/// The first-launch headline. Demo: `.first h1`.
const kSrsBringYourRepertoire = 'Bring your repertoire.';

/// The first-launch lede. Demo: `.first .lede`.
const kSrsFirstLaunchLede =
    'Import a PGN or a Lichess study. Everything stays on this device, and reviews work offline.';

/// The drop target's label. Demo: `.drop p`.
const kSrsDropPgnHere = 'Drop a PGN file here';

/// The `Try again` action on the error screen. Demo: `#errorRetryBtn`.
const kSrsRetryLabel = 'Try again';

/// The `Copy details` action on the error screen. Demo: `#errorCopyBtn`.
const kSrsCopyDetailsLabel = 'Copy details';

/// The library sheet's name, and the back label on the scenes it opens.
///
/// The demo writes it in English in both places (`#sheetLib`'s rows, and the `‹ Library`
/// sub-head on analysis, explorer and board editor) and the sheet has no l10n string of
/// its own, so it is hardcoded here too — consistently, rather than in three files.
const kSrsLibraryLabel = 'Library';

/// The library sheet's first row. Demo: `#sheetLib` group 1.
const kSrsImportLabel = 'Import PGN';

/// The library sheet's analysis row. Demo: `#sheetLib` → Explore.
const kSrsAnalysisBoardLabel = 'Analysis board';

/// The library sheet's explorer row. Demo: `#sheetLib` → Explore.
const kSrsOpeningExplorerLabel = 'Opening explorer';

/// The library sheet's board-editor row. Demo: `#sheetLib` → Explore.
const kSrsBoardEditorLabel = 'Board editor';

/// The library sheet's settings row. Demo: `#sheetLib` group 3.
const kSrsSettingsLabel = 'Settings';

/// The library sheet's about row. Demo: `#sheetLib` group 3.
const kSrsAboutLabel = 'About and licences';
