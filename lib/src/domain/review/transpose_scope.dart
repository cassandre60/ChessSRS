// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

/// Move transposition matching scope options.
library;

/// How far transposed-move acceptance reaches (INV-065).
enum TransposeScope { off, withinStudy, inScope }
