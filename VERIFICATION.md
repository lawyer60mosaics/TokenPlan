# Verification — 2026-08-28

Reference: cc-switch commit `3217f72596f2d1c0f879f0a05f83803825d9809f`. The local reference checkout's Token Plan service/catalog match the fetched upstream commit.

- `cargo fmt --check`: passed.
- `cargo test --lib`: 56 passed. Includes upstream parsing, local HTTP error/transport tests, Zhipu team request headers, Kimi and ZenMux fixtures, provider routing, legacy profile migration and DPAPI roundtrip. These do not call paid model inference APIs.
- `npm test`: 7 passed. Credentials, partial/dynamic windows, clamping, concurrent profile isolation, duplicate request suppression, obsolete responses, stale-cache retention and paused profiles.
- `npx tauri build --debug`: passed, embedded production frontend; GUI subsystem retained.
- Browser UI (fictional credentials, in-memory persistence): all 7 providers switch; two/three-window layouts; ZenMux USD amounts; team org/project fields; region controls; add/save/cancel/pause/delete; English settings; no browser error logs. Simulation is not evidence of real remote API availability.
- Real desktop app: existing Volcengine encrypted credentials loaded without re-entry; live three-window query succeeded.
- Native drag regression on a separate test instance: text `(104,104) → (164,140)`, progress `(164,140) → (224,176)`, blank `(224,176) → (284,212)`; each moved `60 × 36` pixels. Settings control remained `(284,212)`. The independent test instance was closed; the user's main instance was left running.

New providers still need the user's own active plan credentials for real-account verification. ZenMux requires an explicit official HTTPS usage endpoint; OpenCode Go's route is undocumented and may change. Other cc-switch features (generic balance scripts, custom scripts, official OAuth subscriptions) are outside the Token Plan tab scope. DeepSeek balance is a separate integration added below.

## DeepSeek balance addition — 2026-08-28

- Official contract: https://api-docs.deepseek.com/api/get-user-balance/ (`GET /user/balance`). Independently implemented; not treated as a Token Plan percentage.
- `cargo fmt --check`: passed. `cargo test --lib`: **63 passed**, including seven new DeepSeek parsing, transport, serialization and routing tests. HTTP tests use a local loopback server with fictional credentials.
- `npm test`: **14 passed**. Additional balance cases cover exact decimal strings, multiple currencies, missing fields, depleted balances, stale-cache timestamps, edited-profile responses and quota/balance isolation.
- `npm run build` and `npx tauri build --debug`: passed; rebuilt desktop executable with production Vue assets.
- Isolated browser UI: Chinese and English balance labels; three amounts without progress bars; official-key settings hint; depleted balance shown as unavailable, not a failed query; CNY/USD displayed separately with vertical scrolling and no horizontal overflow; failed refresh preserves successful data/timestamp; switching back to Volcengine restores three quota bars.
- Fixture URLs: `tests/preview.html?balance=depleted`, `?balance=multi`, `?balance=stale`. Fictional data only; fixture code is excluded from the production build.
- DeepSeek live-account verification is **not performed**: no user DeepSeek key was provided or imported. Existing encrypted profiles were not edited for testing.

## In-app acknowledgments — 2026-08-28

- Settings includes an always-visible `致谢与许可 / Acknowledgments & licenses` action. The full `THIRD_PARTY_NOTICES.md` is imported at build time, without network access or a Markdown runtime dependency.
- `npm test`: 14 passed. `npm run build`: passed.
- Browser fixture verified Chinese and English entry points, DeveloperLz credit/disclaimer, cc-switch source/reference commit and the full MIT license through its final paragraph. The 340×330 panel scrolls vertically with no horizontal overflow and permits text selection.
- Opening and returning preserves an edited, unsaved profile name. Returning restores focus to the notice button. No provider queries or credential persistence changes were introduced.
