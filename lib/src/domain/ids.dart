// Copyright (C) 2024 ChessSRS contributors
library chess_srs.domain.ids;

// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Generate a new random UUID v4.
String newId() => _uuid.v4();
