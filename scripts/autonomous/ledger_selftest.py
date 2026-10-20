#!/usr/bin/env python3
"""Thin wrapper that runs the ledger's built-in self-check."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ledger  # noqa: E402

sys.exit(ledger.run_selftest())
