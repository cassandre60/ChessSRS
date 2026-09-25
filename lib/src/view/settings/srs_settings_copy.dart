// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

// Labels and help text for the settings screen.
//
// The design fixes this copy: design/docs/03-components.md §11 lists the rows and their
// order, and the demo's `#viewSettings` carries the wording. The build had drifted on two
// rows. Copy drift here is invisible in screenshots, so it is named here and asserted by
// test/view/settings/srs_settings_screen_test.dart.

/// Order and grouping, from design/docs/03-components.md §11:
///
///   Daily limit → Target retention → Show notes after a move → Show arrows and circles
///   → Accent → Theme → Sound → Advanced (Scheduling algorithm, Diagnostics)
///
/// The build also has settings the design does not cover (board, engine, logs, licences).
/// They are kept, because deleting them would strand real features, and the design's own
/// rule for anything outside the prototype is to keep it in the family and ask the owner.
const kSrsSettingDailyLimit = 'Daily limit';
const kSrsSettingDailyLimitHelp = 'Positions reviewed per day.';

const kSrsSettingTargetRetention = 'Target retention';
const kSrsSettingTargetRetentionHelp =
    'Higher means more reviews. 88% suits most players; 95% is for tournament preparation.';

/// The design calls this "Show arrows and circles": the review board draws arrows and
/// highlighted squares from the study. The build said "Show board annotations", which
/// names the mechanism rather than what the user sees.
const kSrsSettingShowAnnotations = 'Show arrows and circles';
const kSrsSettingShowAnnotationsHelp = 'Drawn from your study, only after you answer.';

const kSrsSettingShowNotes = 'Show notes after a move';
const kSrsSettingShowNotesHelp = 'Comments from your study appear once you have answered.';

const kSrsSettingAccent = 'Accent';
const kSrsSettingAccentHelp = 'Used for the move you should play and for selection.';

const kSrsSettingTheme = 'Theme';

const kSrsSettingSound = 'Sound';
const kSrsSettingSoundHelp = 'Soft move and correction sounds.';

const kSrsSettingAdvanced = 'Advanced';

const kSrsSettingScheduler = 'Scheduling algorithm';
const kSrsSettingSchedulerHelp = 'FSRS adapts to how well you remember each position.';

const kSrsSettingDiagnostics = 'Diagnostics';
const kSrsSettingDiagnosticsHelp = 'Show memory metrics during review.';

/// The review screen's notation line. Not in the design's list: the line is core to the
/// review screen, so hiding it has to stay a choice, but the design's own wording is
/// "the line is the headline" and does not offer a switch.
const kSrsSettingShowNotation = 'Show move notation';
const kSrsSettingShowNotationHelp = 'Display preceding moves (e.g. 1. e4 e5) in the review screen.';
