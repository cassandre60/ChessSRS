// Copyright (C) 2024 ChessSRS contributors
library chess_srs.domain.review.review_engine;

// SPDX-License-Identifier: GPL-3.0-or-later

/// How far transposed-move acceptance reaches (INV-065).
enum TransposeScope { off, withinStudy, inScope }
