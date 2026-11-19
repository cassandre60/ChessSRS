// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

/// Domain entity occurrence identifier generation (`UUID v4`).
library;

import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Generates a new random RFC 4122 UUID v4 string for a domain entity occurrence.
String newId() => _uuid.v4();
