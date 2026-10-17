# Coverage ledger — every test file, attributed to its walker

Every file containing declared tests at `a71a19096`, with the extractor's per-file declaration count and the walker that read it test-by-test (grade per row committed in the chapter or in `rest-of-suite-weak-rows.md`). Wave 1 = the four deep chapters committed with this PR's first commit; wave 2 = the six digest walk sessions + the two catch-up walkers + the author's walk of the three last files.

File target: 182 files / 1855 declarations; attributed here: 182 files / 1855 declarations.

| Declarations | File | Walker |
|---:|---|---|
| 22 | `test/app_links_service_test.dart` | w2-domain/rng walk |
| 4 | `test/app_test.dart` | w2-domain/rng walk |
| 1 | `test/db/database_config_test.dart` | w1 (persistence-import.md) |
| 1 | `test/db/openings_database_test.dart` | w2-boost A |
| 2 | `test/db/srs_upgrade_test.dart` | w1 + re-walked (w2.5 domain) |
| 4 | `test/design/board_squares_test.dart` | w2-design/perf walk |
| 10 | `test/design/design_primitives_test.dart` | w2-design/perf walk |
| 4 | `test/design/folio_tokens_test.dart` | w2-design/perf walk |
| 2 | `test/design/one_look_test.dart` | w1 (design-settings.md) + re-walked (w2-design/perf) |
| 5 | `test/design/practice_exit_test.dart` | w2-design/perf walk |
| 2 | `test/design/review_line_reserve_test.dart` | w2-design/perf walk |
| 5 | `test/design/srs_accent_test.dart` | w1 (design-settings.md) + re-walked (w2-design/perf) |
| 2 | `test/design/srs_colors_contrast_test.dart` | w2-design/perf walk |
| 7 | `test/design/srs_dialog_test.dart` | w1 (design-settings.md) + re-walked (w2-design/perf) |
| 4 | `test/design/srs_notation_line_test.dart` | w1 (design-settings.md) + re-walked (w2-design/perf) |
| 2 | `test/design/srs_page_head_test.dart` | w1 (design-settings.md) + re-walked (w2-design/perf) |
| 4 | `test/design/srs_sheet_dismissible_test.dart` | w1 (design-settings.md) + re-walked (w2-design/perf) |
| 2 | `test/design/srs_switch_test.dart` | w1 (design-settings.md) + re-walked (w2-design/perf) |
| 6 | `test/design/srs_toast_test.dart` | w1 (design-settings.md) + re-walked (w2-design/perf) |
| 3 | `test/design/theme_bridge_test.dart` | w2-design/perf walk |
| 9 | `test/design/top_bar_colour_squares_test.dart` | w1 (design-settings.md) + re-walked (w2-design/perf) |
| 3 | `test/design/top_bar_narrow_test.dart` | w2-design/perf walk |
| 16 | `test/domain/chess_fsrs_scheduler_test.dart` | w2-domain/rng walk |
| 9 | `test/domain/due_status_test.dart` | w2-domain/rng walk |
| 23 | `test/domain/entities_test.dart` | w2-domain/rng walk |
| 14 | `test/domain/graph_aware_review_coordinator_test.dart` | w1 (scheduler-review.md) |
| 10 | `test/domain/position_knowledge_state_test.dart` | w2-domain/rng walk |
| 4 | `test/domain/repertoire_progress_test.dart` | w2-domain/rng walk |
| 9 | `test/domain/review_scope_test.dart` | w2-domain/rng walk |
| 26 | `test/domain/scheduler_test.dart` | w1 (scheduler-review.md) |
| 4 | `test/gates/domain_boundary_test.dart` | w2-domain/rng walk |
| 9 | `test/import/chapter_orientation_test.dart` | w2-domain/rng walk |
| 14 | `test/import/lichess_study_importer_test.dart` | w1 (persistence-import.md) |
| 8 | `test/import/opening_name_test.dart` | w2-domain/rng walk |
| 14 | `test/import/pgn_exporter_test.dart` | w1 (persistence-import.md) |
| 76 | `test/import/pgn_importer_test.dart` | w1; re-walked in full by w2.5-domain (76 tests) |
| 3 | `test/import/pgn_offload_test.dart` | w2-boost A |
| 12 | `test/model/account/account_preferences_test.dart` | w2-boost A |
| 1 | `test/model/account/account_repository_test.dart` | w2-boost A |
| 12 | `test/model/analysis/forecast_test.dart` | w2-domain/rng walk |
| 5 | `test/model/analysis/server_analysis_service_test.dart` | w2-boost A |
| 6 | `test/model/auth/auth_controller_test.dart` | w2-boost A |
| 3 | `test/model/auth/auth_identity_fencing_test.dart` | w2-boost A |
| 24 | `test/model/auth/auth_repository_test.dart` | w2-domain/rng walk |
| 5 | `test/model/auth/startup_token_check_test.dart` | w2-boost A |
| 4 | `test/model/board_editor/board_editor_controller_test.dart` | w2-domain/rng walk |
| 13 | `test/model/clock/chess_clock_test.dart` | w2-boost A |
| 9 | `test/model/common/eval_test.dart` | w2-boost A |
| 53 | `test/model/common/node_test.dart` | w2-domain/rng walk |
| 2 | `test/model/common/service/sound_service_test.dart` | w2-domain/rng walk |
| 6 | `test/model/common/time_increment_test.dart` | w2-boost A |
| 10 | `test/model/common/uci_test.dart` | w2-domain/rng walk |
| 2 | `test/model/engine/cloud_eval_http_test.dart` | w2-engine walk |
| 6 | `test/model/engine/engine_availability_test.dart` | w2-engine walk |
| 11 | `test/model/engine/engine_budget_test.dart` | w2-engine walk |
| 10 | `test/model/engine/engine_factory_test.dart` | w2-engine walk |
| 32 | `test/model/engine/engine_opponent_test.dart` | w2-engine walk |
| 4 | `test/model/engine/engine_providers_test.dart` | w2-engine walk |
| 33 | `test/model/engine/engine_test.dart` | w2-engine walk |
| 13 | `test/model/engine/engine_utils_test.dart` | w2-engine walk |
| 2 | `test/model/engine/evaluation_mixin_test.dart` | w2-engine walk |
| 3 | `test/model/engine/likely_nodes_test.dart` | w2-engine walk |
| 4 | `test/model/engine/maia_book_asset_test.dart` | w2-engine walk |
| 24 | `test/model/engine/opening_book_test.dart` | w2-engine walk |
| 64 | `test/model/engine/position_evaluator_test.dart` | w2-engine walk |
| 18 | `test/model/engine/stockfish_nnue_service_test.dart` | w2-engine walk |
| 8 | `test/model/engine/thinking_time_test.dart` | w2-engine walk |
| 14 | `test/model/engine/weights_service_test.dart` | w2-engine walk |
| 3 | `test/model/explorer/opening_explorer_repository_test.dart` | w2-domain/rng walk |
| 2 | `test/model/explorer/tablebase_repository_test.dart` | w2-boost A |
| 1 | `test/model/game/game_history_test.dart` | w2-boost A |
| 6 | `test/model/game/game_repository_test.dart` | w2-domain/rng walk |
| 2 | `test/model/game/game_status_test.dart` | w2-boost A |
| 2 | `test/model/game/game_storage_test.dart` | w2-boost A |
| 13 | `test/model/game/game_test.dart` | w2-boost A |
| 4 | `test/model/game/material_diff_test.dart` | w2-domain/rng walk |
| 3 | `test/model/game/offline_computer_game_test.dart` | w2-domain/rng walk |
| 2 | `test/model/log/http_log_paginator_test.dart` | w2-domain/rng walk |
| 5 | `test/model/log/log_diagnostics_test.dart` | w2-domain/rng walk |
| 8 | `test/model/offline_computer/practice_analyser_test.dart` | w2-engine walk |
| 1 | `test/model/offline_computer/practice_comment_test.dart` | w2-engine walk |
| 15 | `test/model/offline_computer/tablebase_eval_test.dart` | w2-engine walk |
| 5 | `test/model/settings/preferences_storage_test.dart` | w2-domain/rng walk |
| 7 | `test/model/study/study_collaboration_test.dart` | w2-boost A |
| 3 | `test/model/study/study_preferences_test.dart` | w2-boost A |
| 2 | `test/model/study/study_repository_test.dart` | w2-domain/rng walk |
| 7 | `test/model/user/user_repository_test.dart` | w2-domain/rng walk |
| 4 | `test/network/aggregator_test.dart` | w2-boost A |
| 16 | `test/network/connectivity_test.dart` | w2-network/analysis/utils |
| 3 | `test/network/default_client_deadline_test.dart` | w2-boost A |
| 14 | `test/network/http_redaction_test.dart` | w2-network/analysis/utils |
| 25 | `test/network/http_test.dart` | w2-network/analysis/utils |
| 9 | `test/network/server_status_test.dart` | w2-network/analysis/utils |
| 47 | `test/network/socket_test.dart` | w2-network/analysis/utils |
| 1 | `test/perf/driver_overhead_test.dart` | w2-design/perf walk |
| 1 | `test/perf/due_summary_attribution_test.dart` | w2-design/perf walk |
| 1 | `test/perf/real_library_session_cost_test.dart` | w2-design/perf walk |
| 11 | `test/persistence/canonical_rekey_migration_test.dart` | w2-domain/rng walk |
| 5 | `test/persistence/fast_date_parser_test.dart` | w2-domain/rng walk |
| 4 | `test/persistence/json_adapters_test.dart` | w2-domain/rng walk |
| 8 | `test/persistence/opening_name_repair_migration_test.dart` | w2-domain/rng walk |
| 38 | `test/persistence/sqlite_study_repository_test.dart` | w1 (persistence-import.md) |
| 2 | `test/persistence/srs_schema_indexes_test.dart` | w2-boost A |
| 5 | `test/platform/app_store_links_test.dart` | author (this file) |
| 4 | `test/platform/ios_share_extension_test.dart` | w2-design/perf walk |
| 3 | `test/platform/oauth_callback_identity_test.dart` | w2-design/perf walk |
| 3 | `test/platform/verified_link_claims_test.dart` | author (this file) |
| 2 | `test/reachability/enforcement_matrix_test.dart` | w2-domain/rng walk |
| 4 | `test/reachability/reachability_test.dart` | w2-domain/rng walk |
| 1 | `test/review/move_latency_test.dart` | w2-review walk |
| 12 | `test/review/review_continuity_test.dart` | w2-review walk |
| 64 | `test/review/review_controller_test.dart` | w1 (scheduler-review.md) |
| 47 | `test/review/review_engine_test.dart` | w2-review walk |
| 7 | `test/review/review_flip_study_test.dart` | w2-review walk |
| 4 | `test/review/review_order_test.dart` | author (this file) |
| 21 | `test/review/review_service_test.dart` | w2-review walk |
| 6 | `test/review/review_side_scope_test.dart` | w2-review walk |
| 7 | `test/review/review_transposition_test.dart` | w2-review walk |
| 3 | `test/review/session_constructor_cost_test.dart` | w2-review walk |
| 4 | `test/scripts/update_openings_db_test.dart` | w2-boost B |
| 9 | `test/utils/cache_test.dart` | w2-boost B |
| 4 | `test/utils/color_palette_test.dart` | w2-boost B |
| 14 | `test/utils/duration_test.dart` | w2-network/analysis/utils |
| 38 | `test/utils/json_test.dart` | w2-network/analysis/utils |
| 13 | `test/utils/l10n_test.dart` | w2-network/analysis/utils |
| 10 | `test/utils/lru_list_test.dart` | w2-boost B |
| 12 | `test/utils/rate_limit_test.dart` | w2-network/analysis/utils |
| 4 | `test/utils/riverpod_test.dart` | w2-boost B |
| 19 | `test/utils/string_test.dart` | w2-network/analysis/utils |
| 1 | `test/vertical_slice_gate_test.dart` | w2-domain/rng walk |
| 1 | `test/view/analysis/analysis_action_row_test.dart` | w2-boost B |
| 4 | `test/view/analysis/analysis_layout_test.dart` | w2-network/analysis/utils |
| 3 | `test/view/analysis/analysis_opening_test.dart` | w2-network/analysis/utils |
| 58 | `test/view/analysis/analysis_screen_test.dart` | w2-network/analysis/utils |
| 2 | `test/view/analysis/analysis_share_screen_test.dart` | w2-network/analysis/utils |
| 2 | `test/view/analysis/engine_settings_widget_test.dart` | w2-boost B |
| 11 | `test/view/auth/email_login_screen_test.dart` | w2-boost B |
| 7 | `test/view/board_editor/board_editor_palette_layout_test.dart` | w2-widgets/view walk |
| 33 | `test/view/board_editor/board_editor_screen_test.dart` | w2-widgets/view walk |
| 5 | `test/view/engine/engine_button_test.dart` | w2-design/perf walk |
| 3 | `test/view/engine/engine_gauge_test.dart` | w2-boost B |
| 2 | `test/view/engine/engine_line_semantics_test.dart` | w2-boost B |
| 15 | `test/view/explorer/explorer_view_test.dart` | w2-widgets/view walk |
| 4 | `test/view/game/game_list_tile_test.dart` | w2-boost B |
| 8 | `test/view/more/import_pgn_screen_test.dart` | w2-widgets/view walk |
| 85 | `test/view/offline_computer/offline_computer_game_screen_test.dart` | w2-widgets/view walk |
| 7 | `test/view/offline_computer/opponent_picker_test.dart` | w2-boost B |
| 3 | `test/view/review/about_page_test.dart` | w2-boost B |
| 4 | `test/view/review/export_pgn_dialog_test.dart` | w2-boost B |
| 7 | `test/view/review/import_sign_in_test.dart` | w2-boost B |
| 3 | `test/view/review/library_sheet_test.dart` | w2-boost B |
| 2 | `test/view/review/repertoire_import_dialog_test.dart` | w2-review walk |
| 45 | `test/view/review/review_screen_test.dart` | w2-review walk |
| 11 | `test/view/review/scope_split_drawers_test.dart` | w2-boost B |
| 3 | `test/view/review/sheet_dismiss_test.dart` | w2-boost B |
| 11 | `test/view/review/study_actions_sheet_test.dart` | w2-review walk |
| 10 | `test/view/screenshot_capture_test.dart` | w2-boost B (skip-gated review tool; grade 0 by rule) |
| 2 | `test/view/settings/app_log_settings_screen_test.dart` | w2-widgets/view walk |
| 7 | `test/view/settings/board_and_sound_screens_test.dart` | w2-boost B |
| 6 | `test/view/settings/board_thumbnail_test.dart` | w2-boost B |
| 2 | `test/view/settings/http_log_screen_test.dart` | w2-widgets/view walk |
| 2 | `test/view/settings/legacy_settings_screen_test.dart` | w2-design/perf walk |
| 1 | `test/view/settings/log_screens_no_horizontal_scroll_test.dart` | w2-boost B |
| 2 | `test/view/settings/settings_account_entry_test.dart` | w2-boost B |
| 5 | `test/view/settings/srs_settings_screen_test.dart` | w1 (design-settings.md) |
| 8 | `test/view/study/create_study_chapter_bottom_sheet_test.dart` | w2-widgets/view walk |
| 2 | `test/view/study/study_list_screen_test.dart` | w2-boost B |
| 2 | `test/view/study/study_opening_test.dart` | w2-widgets/view walk |
| 14 | `test/view/study/study_screen_test.dart` | w2-widgets/view walk |
| 3 | `test/view/user/perf_stats_screen_test.dart` | w2-boost B |
| 2 | `test/view/user/search_screen_test.dart` | w2-widgets/view walk |
| 2 | `test/view/user/user_screen_test.dart` | w2-widgets/view walk |
| 7 | `test/widgets/adaptive_action_sheet_test.dart` | w2-widgets/view walk |
| 11 | `test/widgets/adaptive_choice_picker_test.dart` | w2-widgets/view walk |
| 11 | `test/widgets/clock_test.dart` | w2-widgets/view walk |
| 7 | `test/widgets/feedback_test.dart` | w2-widgets/view walk |
| 9 | `test/widgets/game_layout_test.dart` | w2-widgets/view walk |
| 4 | `test/widgets/move_times_chart_test.dart` | w2-widgets/view walk |
| 2 | `test/widgets/pgn_shapes_test.dart` | w2-boost B |
| 1 | `test/widgets/platform_context_menu_button_test.dart` | w2-boost B |
| 35 | `test/widgets/rich_link_text_test.dart` | w2-widgets/view walk |
| 2 | `test/widgets/user_test.dart` | w2-widgets/view walk |
