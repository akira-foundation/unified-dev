

## [0.11.1](https://github.com/akira-foundation/unified-dev/compare/v0.11.0...v0.11.1) (2026-05-22)


### Bug Fixes

* **org:** correct GitHub token type for API authentication ([6eeb7cd](https://github.com/akira-foundation/unified-dev/commit/6eeb7cd57092500bdcaa517c520c5a1bbb0d48e8))

# [0.11.0](https://github.com/akira-foundation/unified-dev/compare/v0.10.1...v0.11.0) (2026-05-22)


### Bug Fixes

* **issues:** kanban drag-drop — drop preview, visible overlay, grab cursor ([879d9b5](https://github.com/akira-foundation/unified-dev/commit/879d9b507a7f2cf3c74acbd13c951ee3b039d454))
* **license:** preserve account email on verify, top-align identity card ([f35cec9](https://github.com/akira-foundation/unified-dev/commit/f35cec9c792829585e49a13bc91cf30e63178987))
* **license:** route downgrade through billing SDK instead of dead worker ([3a4ea25](https://github.com/akira-foundation/unified-dev/commit/3a4ea255828ea529146c53d06aa04766538355e3))
* **license:** route manage subscription through SDK billing_portal ([4e43305](https://github.com/akira-foundation/unified-dev/commit/4e4330536b31cfd4a1f44a1e6f5ce4c2b299bfcb))


### Features

* **agents:** docked workspace island + chat changes summary ([bf4fff7](https://github.com/akira-foundation/unified-dev/commit/bf4fff7b81d0a35077f99b494ed41593aaa78d8d))
* **issues:** Linear-style kanban, board filter, hidden columns, Cmd+N shortcuts ([396cfe4](https://github.com/akira-foundation/unified-dev/commit/396cfe414ec85fc2e49465ecab2c9d1eb423e6a4))
* **issues:** Linear-style list + detail page, comments, user-authored writes ([8e1b9e2](https://github.com/akira-foundation/unified-dev/commit/8e1b9e251e178c1c27d699fcea363f4267602e59))
* **license:** add subscription resume and downgrade/resume toasts ([2f81819](https://github.com/akira-foundation/unified-dev/commit/2f81819d842400d0dda132b6547572c1e8185c48))
* **license:** migrate billing flow to SDK, web checkout + invoices, drop worker ([afc52ef](https://github.com/akira-foundation/unified-dev/commit/afc52ef65f2cd8fb24c6b9f92b8070fd152dc454))
* **license:** runtime public-key fetch/cache + app-wide validation triggers ([08c1569](https://github.com/akira-foundation/unified-dev/commit/08c156957c4e2f0103c096ebbb3edfef9a076164))
* **prs:** redesign diff viewer with flat blocks and word-level highlight ([85503de](https://github.com/akira-foundation/unified-dev/commit/85503defaf01e3652421721c15447bd340851455))
* **prs:** replicate Linear UI on PRs + appbar action consistency ([de2d561](https://github.com/akira-foundation/unified-dev/commit/de2d56197da2b299cac2b6676c18a669db5b0f8c))
* **prs:** unify PR into single detail page (overview, files, checks) ([74d838d](https://github.com/akira-foundation/unified-dev/commit/74d838d9a85c8ccfabd5b52417f8cb7c14bf29c7)), closes [#262626](https://github.com/akira-foundation/unified-dev/issues/262626)
* **repos:** per-tab search in repo detail and theme-aware command palette ([c473f08](https://github.com/akira-foundation/unified-dev/commit/c473f0880efc39f85697e0b436e889ccd374d5e5))
* **skills:** sync button, frontmatter scalar fix, app-pattern detail/notifications ([7b56d53](https://github.com/akira-foundation/unified-dev/commit/7b56d538467f82f64b1422d868728a029f70731c))
* **ui:** centered appbar search overlay, flat command items, compact empty state ([5332165](https://github.com/akira-foundation/unified-dev/commit/5332165d819df7ce24ca1d4b1a5df758b04dd199))

# [0.10.0](https://github.com/akira-foundation/unified-dev/compare/v0.9.0...v0.10.0) (2026-05-20)


### Bug Fixes

* **license:** persist store, load on mount, clear-first on logout ([d9cf24d](https://github.com/akira-foundation/unified-dev/commit/d9cf24dd61fb4917b532800ed2c519fa0ad81c65))
* **license:** treat empty plan as free in get_plan ([b4ec67d](https://github.com/akira-foundation/unified-dev/commit/b4ec67d51a05a630bf851640594c2e661e178d0b))
* **orgs:** align free-tier counter with provider join ([ad33324](https://github.com/akira-foundation/unified-dev/commit/ad33324e1f98e45539203594ce123caf03e22187))
* **providers:** keep organizations when deleting VCS provider ([62d2a00](https://github.com/akira-foundation/unified-dev/commit/62d2a00ace3fd10323399ba75b8d79904372e8b1))


### Features

* **auth:** customer oauth login with lazy auth wall and logout ([56d8aaf](https://github.com/akira-foundation/unified-dev/commit/56d8aaf67a096f1957e18a29d661516b5845552c))
* **auth:** dynamic oauth providers + polished onboarding flow ([0be1d67](https://github.com/akira-foundation/unified-dev/commit/0be1d6715ba7da81b3dc08c0cdddae60020dc6d4))
* **autopilot:** finish job with an auto-created pull request ([11f377d](https://github.com/akira-foundation/unified-dev/commit/11f377d65cc9727cfc500db33660c09890c98704))
* **autostart:** launch at login backed by tauri-plugin-autostart ([68e0f92](https://github.com/akira-foundation/unified-dev/commit/68e0f92fd7c0b11ad3488fe61f815da3ac54c24a))
* **billing:** activate license via SDK with ed25519 verification ([2248ecc](https://github.com/akira-foundation/unified-dev/commit/2248ecc95dfbfb6e241b6f3b411d216cd29abdc2))
* **billing:** swap OTP login onto akira-billing SDK ([ed0722d](https://github.com/akira-foundation/unified-dev/commit/ed0722d9377b7515180c7b89bc3299cd95e10277))
* **billing:** wire akira-billing SDK and skeleton client ([4726c87](https://github.com/akira-foundation/unified-dev/commit/4726c87d7e3819dafac3b6e56e031fd0d74caf68))
* **client:** server-driven usage limits, history, ui polish ([9c025ba](https://github.com/akira-foundation/unified-dev/commit/9c025ba2ec44a575cb2c69a76a133a396c732d90))
* **github:** store OAuth user token on connect for OSS contribution sync ([8737543](https://github.com/akira-foundation/unified-dev/commit/873754376d741601987d12c3414c8ac40ae54261))
* **notifications:** action handlers + clickable rows ([f05577f](https://github.com/akira-foundation/unified-dev/commit/f05577fa8f644cdac560fb1603f4418a57ce3c7e))
* **notifications:** in-app inbox, system notifications, dock badge ([de69fea](https://github.com/akira-foundation/unified-dev/commit/de69fea958883078d35b5894e89e22cd94b9588b))
* **open-source:** toast immediately when sync starts ([ae1085b](https://github.com/akira-foundation/unified-dev/commit/ae1085bc58c2d07478d2feb64405b3859485cf3c))
* **plans:** drive subscription plans from billing sdk ([9b5075e](https://github.com/akira-foundation/unified-dev/commit/9b5075ee2a9e33d62b616fedbc5dbbc02f5aa3bd))
* **ui:** user menu in sidebar footer ([9a59944](https://github.com/akira-foundation/unified-dev/commit/9a599442e6252adc7ab0f6f3041e25c2f7245554))

# [0.9.0](https://github.com/akira-foundation/unified-dev/compare/v0.8.0...v0.9.0) (2026-05-11)


### Features

* **open-source:** add Open Source Contributions module ([cf2fac8](https://github.com/akira-foundation/unified-dev/commit/cf2fac82f76e0186c244a05950883d0d9abadcd0))
* **open-source:** real GitHub GraphQL sync ([e141af3](https://github.com/akira-foundation/unified-dev/commit/e141af3a06b6c55748d75a3098a6e3f87f40e005))
* **open-source:** UI refactor with contribution panel ([20538c2](https://github.com/akira-foundation/unified-dev/commit/20538c2211a85e62f16561849bbd2f1c9eb949dd))
* **pr:** add AI task resolution and new task dialog for pull requests ([9927d82](https://github.com/akira-foundation/unified-dev/commit/9927d82a66d827e7b32f309592b239d4c1c89e6b))
* **sidebar:** redesign sidebars in floating Tahoe-island style ([a23aa1e](https://github.com/akira-foundation/unified-dev/commit/a23aa1ec37d7bd88bd755046a139758bcd920d3a))
* **window:** integrate native macOS title bar into sidebar island ([67eb44b](https://github.com/akira-foundation/unified-dev/commit/67eb44b3897163c6b09226f47486a1204de473fc))

# [0.8.0](https://github.com/akira-foundation/unified-dev/compare/v0.7.0...v0.8.0) (2026-05-04)


### Bug Fixes

* **deps:** upgrade rand to 0.9 to resolve unsoundness with custom logger using rand-rng ([aca2dfa](https://github.com/akira-foundation/unified-dev/commit/aca2dfa4ac96ce4ff8305b0504f7205f6281b6c0))
* **pr-detail-sheet:** expand comments section by default when present ([ee68463](https://github.com/akira-foundation/unified-dev/commit/ee68463fc90d21ef309c69dc5c89f127e8189952))
* **pr-review:** default to checks tab and auto-expand targeted/single check ([0f49fe8](https://github.com/akira-foundation/unified-dev/commit/0f49fe8b143962410420074c205f4f20fe4238f4))


### Features

* **agent-header:** add PR sheet, merge button, in-app CI navigation ([dbe7d49](https://github.com/akira-foundation/unified-dev/commit/dbe7d49976f7dc1b5ff2fa636a55387ab9974528))
* **autopilot:** implement feature check for autopilot and update free run limits ([818aa97](https://github.com/akira-foundation/unified-dev/commit/818aa9774f84bc0bd27c3902b0bd1ee41e5289d1))
* **delegate:** prefix thread title with issue identifier ([94a1dd9](https://github.com/akira-foundation/unified-dev/commit/94a1dd94a35de1974bb64475add0fec87a88726c))
* **headers:** improve layout and styling of agent and app headers ([3d502ab](https://github.com/akira-foundation/unified-dev/commit/3d502abf46f51ea6cbd2bdf0310e92930067692b))
* **merge:** update merge function to use effective repo name and log merge timestamps ([0e9a239](https://github.com/akira-foundation/unified-dev/commit/0e9a2397de8546a38633da474e318f154a47f646))
* **oauth:** implement PKCE support with code verifier and challenge in OAuth flow ([99f0aaa](https://github.com/akira-foundation/unified-dev/commit/99f0aaab72bdbc08b58a1fcf3c0c265b31eecba1))
* **pr-ci:** add CI checks integration with PR status display and polling ([f856cb1](https://github.com/akira-foundation/unified-dev/commit/f856cb16b0f11bbbc2259f16be22b43a5c834807))
* **pr-detail:** improve merge handling with loading state and toast notifications ([618cf69](https://github.com/akira-foundation/unified-dev/commit/618cf69452d245f807446766519874a138430692))
* **pr-merged-banner:** add banner for merged PRs with removal option ([27a0b19](https://github.com/akira-foundation/unified-dev/commit/27a0b1907ae3c35b081243262aa8e79d558d22e0))
* **pr-review:** add backend cmd to resolve thread PR review context ([65d1f63](https://github.com/akira-foundation/unified-dev/commit/65d1f63a7baee42ef7284ee116c31973c421a84c))
* **profile:** add get and set functions for user profile management ([3cff3b8](https://github.com/akira-foundation/unified-dev/commit/3cff3b8f77f2467de7eb27465ae57c89084cf816))
* **prompt:** tighten turn scope and issue status transition rules ([068fe5a](https://github.com/akira-foundation/unified-dev/commit/068fe5a2d0df76dc0b07a52299412f4c50d70fbb))
* **provider:** include upstream status in provider resolution and improve error handling ([df26d7b](https://github.com/akira-foundation/unified-dev/commit/df26d7b0d1ab2eae4bd0eef4aa762db1c0bb70cd))
* **repository:** enhance pull request synchronization and query invalidation ([9416048](https://github.com/akira-foundation/unified-dev/commit/9416048cef430b947d2e47a3ddbbb15f42d25585))

# [0.7.0](https://github.com/akira-foundation/unified-dev/compare/v0.6.0...v0.7.0) (2026-04-21)


### Bug Fixes

* **model-picker:** use Popover + Command for proper scroll with available height ([8819e02](https://github.com/akira-foundation/unified-dev/commit/8819e0293fac4fc33e05ef1bd896b2d98d263555))
* **repos:** use LEFT JOIN so repos without a provider appear in global list ([227b28d](https://github.com/akira-foundation/unified-dev/commit/227b28df6b9d503882f876c24527545211bd3543))
* resolve private repo clone auth, dropdown closing, and git PATH issues ([943bb03](https://github.com/akira-foundation/unified-dev/commit/943bb03db1066e9c3c8fe2e2f9868f576bd09494))


### Features

* **autopilot:** enhance thread management with removal functionality and status updates ([65ddf87](https://github.com/akira-foundation/unified-dev/commit/65ddf87ec32548c9235c9b7c12efdc7f5e5f011f))
* **autopilot:** persist jobs and align management flows ([e939ead](https://github.com/akira-foundation/unified-dev/commit/e939ead99211ea1741ef6d64a8c47267ed372887))
* **graphql:** improve error handling for GitHub GraphQL responses ([e56b396](https://github.com/akira-foundation/unified-dev/commit/e56b3965ae136e0c6e6ec4ba0fa4e7c72e92cc2f))
* **i18n:** add EN/PT translations for create repo, delete remote, and reconnect GitHub ([9646eee](https://github.com/akira-foundation/unified-dev/commit/9646eee35943f1005fc8f5499edb8f6b14f00eae))
* **providers:** expose auth_type in ProviderSummary and add reconnect GitHub ([2c3785f](https://github.com/akira-foundation/unified-dev/commit/2c3785f291b8ef4b6bfae79313f052d2e23907dd))
* **repos:** add create and delete GitHub repository ([294409b](https://github.com/akira-foundation/unified-dev/commit/294409b453e6186907145c49e88ac58ec2b79a0d))
* **settings:** add "Coming Soon" indicator for various settings items ([230c007](https://github.com/akira-foundation/unified-dev/commit/230c007ed649224ed46a941b2546318a8817308f))

# [0.6.0](https://github.com/akira-foundation/unified-dev/compare/v0.5.0...v0.6.0) (2026-04-17)


### Features

* **billing:** add invoice listing functionality and update related components ([fd8b224](https://github.com/akira-foundation/unified-dev/commit/fd8b224d2f784895ea1955caef3e1111fba09525))
* **billing:** implement plan downgrade with Stripe schedule and local persistence ([0d00d4a](https://github.com/akira-foundation/unified-dev/commit/0d00d4afdc355b6e20e696f6bec1c9ca8c77f6d0))
* **checkout:** update checkout process to return CheckoutDto and implement polling for session activation ([dc65b39](https://github.com/akira-foundation/unified-dev/commit/dc65b3928833db183e815592a8f8089394b10e20))
* **gemini:** add Gemini CLI integration and update notification handling ([3a9b928](https://github.com/akira-foundation/unified-dev/commit/3a9b92868d580bb34b70be2dde071e1f240a2f96))
* **profile:** add user profile management with email verification and license claiming ([cfed98f](https://github.com/akira-foundation/unified-dev/commit/cfed98ff20a539e294dd20b1861fb6e531c94e5d))
* **subscription:** enhance subscription tab with upcoming plan button and update license verification logic ([5a6279e](https://github.com/akira-foundation/unified-dev/commit/5a6279eeae6c4dcc97e65bad919e4285f855055c))
* **subscription:** implement subscription management and billing portal integration ([9462ed3](https://github.com/akira-foundation/unified-dev/commit/9462ed37dfaf28f0343b0703dfeda5db25b2d064))

# [0.5.0](https://github.com/akira-foundation/unified-dev/compare/v0.4.3...v0.5.0) (2026-04-10)


### Bug Fixes

* **security:** patch 50 dependabot CVEs across npm and Rust dependencies ([3bdaad2](https://github.com/akira-foundation/unified-dev/commit/3bdaad2187e1270493f3986fd31af413b26073f1))
* **settings:** update upgrade plan prices for pro and ultimate tiers ([d01fa57](https://github.com/akira-foundation/unified-dev/commit/d01fa57ac844440cd9da1c24c364abd8580173eb))
* **terminal:** improve terminal resizing and add environment variables for color support ([7477985](https://github.com/akira-foundation/unified-dev/commit/7477985a62a1ec5c759ca705ca8c99bc3dad9fe7))


### Features

* **agenda:** enhance agenda view with organization sync history and weekly summary ([073aaab](https://github.com/akira-foundation/unified-dev/commit/073aaab4aeef42ce0038c8c8ba705132ef90e247))
* **agents:** add search functionality to agents sidebar with clear filters option ([6eed33e](https://github.com/akira-foundation/unified-dev/commit/6eed33ebb0339283c4cbb5c1641735359da06309))
* **billing:** add free tier enforcement and usage tracking ([e2f3947](https://github.com/akira-foundation/unified-dev/commit/e2f3947d89fda6b3bd2aa122cd9dae6510eb1f7e))
* **issues:** add search functionality to issue table ([55e224a](https://github.com/akira-foundation/unified-dev/commit/55e224a9ac487f4e8bd99dd1ace1b2a19bfeee1a))
* **license:** implement HMAC signature verification for license activation ([9dacc68](https://github.com/akira-foundation/unified-dev/commit/9dacc68c05dc5bf19dac17ef2cc2d04bc51310d2))
* **onboarding:** add onboarding overlay and dependency check functionality ([61576c6](https://github.com/akira-foundation/unified-dev/commit/61576c63cb6fcad8950ee7d9d2498f5ee2555b86))
* **organizations:** add manual sync functionality and update sync settings ([3e33c5c](https://github.com/akira-foundation/unified-dev/commit/3e33c5c08df12879174b2703767855387e6e1d08))
* **plans:** add repos (3) and org (1) limits to free tier plan display ([8ff0cda](https://github.com/akira-foundation/unified-dev/commit/8ff0cda70a0f20a4fb3194d747a4de1e5abd8ec5))
* **plans:** sync plan features with landing page (kanban, PR review, support tiers) ([0799283](https://github.com/akira-foundation/unified-dev/commit/079928364b24f8a51183bf9f63237a4527e9f496))
* **settings:** add remote settings tab navigation and state management ([3e89481](https://github.com/akira-foundation/unified-dev/commit/3e89481f0920dc4f4cd68e27ed430f193ef92ebe))
* **skill-source:** add skill source page and integrate remote skill fetching ([e90f0a4](https://github.com/akira-foundation/unified-dev/commit/e90f0a4536b48ad7049b29b0249423e555a6549b))
* **skills:** update skill directory handling and enhance filtering logic ([d1c09e4](https://github.com/akira-foundation/unified-dev/commit/d1c09e435566885e554d9f6baf0add22ab24e92c))
* **sync:** enhance sync functions to update organization settings after sync ([3510d97](https://github.com/akira-foundation/unified-dev/commit/3510d97b098a5d972c236b5e967168b65c9ee068))

## [0.4.3](https://github.com/akira-foundation/unified-dev/compare/v0.4.2...v0.4.3) (2026-04-07)


### Bug Fixes

* **ci:** replace Python script with jq for generating latest.json ([93b600d](https://github.com/akira-foundation/unified-dev/commit/93b600d7c05a23fad02ce2c5dadfafea4177c203))
* **ci:** update build workflow to trigger on main branch and improve error handling for macOS tarballs ([644f5a3](https://github.com/akira-foundation/unified-dev/commit/644f5a39c869d5420a5a8852d21bd24d8de7ec2a))
* **ci:** update DMG upload step to trigger on tag references and refactor latest.json generation ([4e6be96](https://github.com/akira-foundation/unified-dev/commit/4e6be96f97deb2011058db16a54c3cea20eb60e6))
* **config:** update public key in tauri configuration ([513c2ad](https://github.com/akira-foundation/unified-dev/commit/513c2adfa032b36a7bb0ab3365d61c97c01f6c50))
* **config:** update tauri configuration to remove updater target and enable updater artifacts ([6ff3d1d](https://github.com/akira-foundation/unified-dev/commit/6ff3d1d20a65d6e96fb5b8836d7672b4dd8f3e9e))
* update bundle targets in tauri configuration ([701e296](https://github.com/akira-foundation/unified-dev/commit/701e296af949ce98fb32155dd18c57d6f6eb9a0c))

## [0.4.2](https://github.com/akira-foundation/unified-dev/compare/v0.4.1...v0.4.2) (2026-04-07)


### Bug Fixes

* **ci:** refactor build workflow to separate aarch64 and x86_64 jobs and improve artifact handling ([fd70d85](https://github.com/akira-foundation/unified-dev/commit/fd70d85004002f750bfee92dced4fbdad49a90f1))

## [0.4.1](https://github.com/akira-foundation/unified-dev/compare/v0.4.0...v0.4.1) (2026-04-07)


### Bug Fixes

* **build:** improve artifact handling by dynamically locating macOS tarballs ([8df6e4e](https://github.com/akira-foundation/unified-dev/commit/8df6e4ee1ee3f3e25c9dccfa4bc712d05d9ad34c))

# [0.4.0](https://github.com/akira-foundation/unified-dev/compare/v0.3.0...v0.4.0) (2026-04-07)


### Bug Fixes

* **agent:** prevent proactive MCP tool calls and fix streaming indicator ([05b32f7](https://github.com/akira-foundation/unified-dev/commit/05b32f70387ce93930f9c08405cc001842e63dde))
* **copilot:** resolve 400 and 413 errors on multi-turn conversations ([8d6852b](https://github.com/akira-foundation/unified-dev/commit/8d6852b98c5cf00258b5d7a059e88151a886ee5d))


### Features

* **agent:** display dynamic tool call count in status bar ([580d830](https://github.com/akira-foundation/unified-dev/commit/580d830fb4c6bc0671fbb4c82590f29bdc5e9818))
* **agent:** enhance message handling with loading states and thread-specific storage ([8af775b](https://github.com/akira-foundation/unified-dev/commit/8af775b1478c2c404dcae156ca30e7357b3f1a00))
* **build:** support building for multiple macOS architectures and update artifact handling ([f6d5fda](https://github.com/akira-foundation/unified-dev/commit/f6d5fdaa13f2b7060282fa16fd0e2b6c3a4b6a21))
* **chat:** add image support across all providers and frontend ([b02ca7c](https://github.com/akira-foundation/unified-dev/commit/b02ca7c6c801857afcde2cef2bf1fae28267a57a))
* **chat:** skip history messages with images when current message contains an image ([7b3146f](https://github.com/akira-foundation/unified-dev/commit/7b3146fb413ed25e377807119e6c84b6faba0673))
* **copilot:** add Claude models and remove cross-provider fallbacks ([5e1d880](https://github.com/akira-foundation/unified-dev/commit/5e1d8806b79ece59135ebdd523eded5b2a711952))
* **repository:** add default merge action configuration to repository settings ([45f88ab](https://github.com/akira-foundation/unified-dev/commit/45f88ab42ff7fb4aa71dd90d267c6fe6076654b8))
* **repository:** add repository removal functionality with confirmation dialog ([d6a951b](https://github.com/akira-foundation/unified-dev/commit/d6a951bcab89084cea3e821489ff5ff9cc1a15b7))
* **repository:** add repository settings management with display name and model configuration ([3bf3466](https://github.com/akira-foundation/unified-dev/commit/3bf34667274a244dd3f8fa0338baaea4d1899ac6))

# [0.3.0](https://github.com/akira-foundation/unified-dev/compare/v0.2.1...v0.3.0) (2026-04-06)


### Features

* **updater:** implement auto-update with tauri-plugin-updater and update UI in AppHeader ([822a4cb](https://github.com/akira-foundation/unified-dev/commit/822a4cba108afe1e7d11a45d6e1865ed7dc33ec6))

## [0.2.1](https://github.com/akira-foundation/unified-dev/compare/v0.2.0...v0.2.1) (2026-04-06)


### Bug Fixes

* **ci:** add contents write permission for GitHub release upload ([004f113](https://github.com/akira-foundation/unified-dev/commit/004f113ae935b95f9327a9d35cab1158530154c3))

# [0.2.0](https://github.com/akira-foundation/unified-dev/compare/v0.1.0...v0.2.0) (2026-04-06)


### Bug Fixes

* **ci:** add APPLE_SIGNING_IDENTITY, comment Linux/Windows in test-build, use pnpm ([751ac9f](https://github.com/akira-foundation/unified-dev/commit/751ac9ff98c1a0144861fb166e67daac7b79af71))
* **ci:** fix codesign keychain search path and suppress Rust dead_code warnings ([e71d493](https://github.com/akira-foundation/unified-dev/commit/e71d4930d85fee1037ee2ddf32e74f94374fc326))
* **ci:** use pnpm run lint with fallback instead of --if-present flag ([82bf76c](https://github.com/akira-foundation/unified-dev/commit/82bf76c65e5f45a7bebbde153899ae7ce43529df))
* **rust:** move debug-only imports under cfg(debug_assertions) in key_store ([2dec1eb](https://github.com/akira-foundation/unified-dev/commit/2dec1eb5c1973f2aa5d69fe1dd17e7f97c1a2c0a))
* **zod:** resolve version mismatch errors in form resolvers and update zod dependency ([574b19d](https://github.com/akira-foundation/unified-dev/commit/574b19d1630593c6e4d18380ae78d73ceaa3b4e3))


### Features

* **ci:** add AKIRA_API_URL and GITHUB_CLIENT_ID to build environment variables ([0e9551b](https://github.com/akira-foundation/unified-dev/commit/0e9551b9a282e9b6663177c3faeae18851fb7abc))

# 0.1.0 (2026-04-06)


### Bug Fixes

* change skills description to refer to Unified Dev instead of Codex ([f88738d](https://github.com/akira-foundation/unified-dev/commit/f88738dbec183b7f1d3eb4101d4a7490235fb391))
* resolve syntax error with escaped backticks in template strings ([7503796](https://github.com/akira-foundation/unified-dev/commit/750379699812b6dd4f1b5872f86d8cfc762eaa13))
* **ui:** correct light mode across agent workspace and pages ([5b4ede4](https://github.com/akira-foundation/unified-dev/commit/5b4ede4a6a6afd28bff64cf5483361f14eafd7d4))
* **ui:** improve PR checks log parsing and review page layout ([501e8ac](https://github.com/akira-foundation/unified-dev/commit/501e8ac121e6b57429448e79eed62e433bcba674))
* **ui:** persist viewed files state and improve patch viewer styling ([c99fec3](https://github.com/akira-foundation/unified-dev/commit/c99fec3f641048240b8276a711314b037a7431c1))
* **ui:** wire up dashboard actions, organization navigation, and theme settings ([fb1eec0](https://github.com/akira-foundation/unified-dev/commit/fb1eec004a2f70dc4d80f73b9357d95082677800))


### Features

* add a new Radix UI-based Switch component and update settings page tab styling. ([6d706c4](https://github.com/akira-foundation/unified-dev/commit/6d706c4dd9fc1c2b1cc3fed4f0ad0e04d5c930ae))
* add icons and refine styling for settings sections ([a5bb26c](https://github.com/akira-foundation/unified-dev/commit/a5bb26c34a42239b26cda9799f5ab7f01e2fd083))
* add initial components and types for organization management ([bae1abb](https://github.com/akira-foundation/unified-dev/commit/bae1abb60780da79c38e22ba3a4cf2e08694fee0))
* add missing IDE and terminal options to settings ([55d6ef0](https://github.com/akira-foundation/unified-dev/commit/55d6ef039c02a1ac08af341a89e60afab410d44e))
* add organization repository selection page with repository visibility and selection features ([5929877](https://github.com/akira-foundation/unified-dev/commit/5929877a1ffc85cbe91c2e1001f1c93a9573c8a6))
* Add shell configuration file scanning for AI provider API keys and simplify config directory detection logic. ([f97afc9](https://github.com/akira-foundation/unified-dev/commit/f97afc93f122418f92b77cccb4a352edd22d9d80))
* **agent-chat-input:** integrate skills fetching and update skill display logic ([233d0fe](https://github.com/akira-foundation/unified-dev/commit/233d0fe902794629c04a433c8888588b2c2c6e77))
* **agent-timeline:** enhance rendering of tables and improve UI elements for better readability ([5347475](https://github.com/akira-foundation/unified-dev/commit/534747538f34f98a9c5baddc8ec166048286c196))
* **agent-ui:** improve textarea height handling and adjust layout spacing ([1954386](https://github.com/akira-foundation/unified-dev/commit/1954386981fc0476d948d10a6e1dfa7b21ba4d34))
* **agent:** add abort functionality for running agents and delegate issue handling ([8a6a35f](https://github.com/akira-foundation/unified-dev/commit/8a6a35f37e887db9bd6d28cc72ae1186a93cc174))
* **agent:** add context window and token usage calculation for AI models ([beb2bd3](https://github.com/akira-foundation/unified-dev/commit/beb2bd3803745f5f7880fac2af110e3584331a29))
* **agent:** add plan mode, thinking budget, and fast mode options for message sending ([46c609e](https://github.com/akira-foundation/unified-dev/commit/46c609e9eca4c96de65ff3ebb36e81f030a5e1a8))
* **agent:** add repository loading after adding a new thread ([b2050b8](https://github.com/akira-foundation/unified-dev/commit/b2050b8ed36e68dee93d7828de53b6b73ae80de1))
* **agents:** enhance diff viewer and workspace layout ([f01e1ad](https://github.com/akira-foundation/unified-dev/commit/f01e1ad2a1cad3c65a2a196fbeeb107384d94673))
* **agents:** implement agentic tool use and execute local slash commands ([4a13ef7](https://github.com/akira-foundation/unified-dev/commit/4a13ef7acd801358a89a6687217d8df8bf3dd357))
* **agents:** implement AI provider detection and model registry caching ([b4011ca](https://github.com/akira-foundation/unified-dev/commit/b4011ca63b27c7a5a65da38d9a47adbb2a021388))
* **agents:** implement customizable action prompts and file discarding ([c371390](https://github.com/akira-foundation/unified-dev/commit/c37139011f64915fdab0ba8ef0a444ab738fd808))
* **agents:** implement file search and command palette ([8fe36fb](https://github.com/akira-foundation/unified-dev/commit/8fe36fbe82afce9e1d8863c714e65cba917c7b40))
* **agents:** implement real-time chat with message persistence and markdown support ([920e4e5](https://github.com/akira-foundation/unified-dev/commit/920e4e58684bfbe8995c5e7ded5c57c08ef8e7c4))
* **agents:** implement real-time git diff viewer and PR creation ([9fb2332](https://github.com/akira-foundation/unified-dev/commit/9fb2332e77a5f82f23a9343b9a0b6985b4f4ee3d))
* **agents:** implement slash commands menu in chat input ([5107841](https://github.com/akira-foundation/unified-dev/commit/510784108e169e379c9d2c0b7e2971bed6e7f56c))
* **agents:** implement thread removal in agent header ([8610216](https://github.com/akira-foundation/unified-dev/commit/86102165d8ee0d1dfc78a2ee329988c184d7aa30))
* **agents:** use strict system prompt for automated actions ([357cc78](https://github.com/akira-foundation/unified-dev/commit/357cc780ed778474126a50a49ea4faaf35b976ca))
* **ai:** refactor AI provider registry and implement OpenAI and Copilot providers ([67d676f](https://github.com/akira-foundation/unified-dev/commit/67d676f32fe8ffb99584ea1fa8d024c4cd03e3ef))
* **auth:** enhance GitHub App authentication with refresh token and expiration handling ([a105b7f](https://github.com/akira-foundation/unified-dev/commit/a105b7f0551e8c3c91dbb8034d3adf11373852b0))
* change workspace subtitle to agents in agents sidebar ([c4d5346](https://github.com/akira-foundation/unified-dev/commit/c4d5346472a7f36b13f0ea28fe6303c346a78c1a))
* **chat:** refactor message handling and introduce session management ([b08ef10](https://github.com/akira-foundation/unified-dev/commit/b08ef10569c47f974789966f871aba065cc27d38))
* complete settings sidebar and modular card architecture ([412f150](https://github.com/akira-foundation/unified-dev/commit/412f15081fd99caa8840f512d7ffd1514f5fba0a))
* **db:** add pr_url to threads table ([cbeaae4](https://github.com/akira-foundation/unified-dev/commit/cbeaae4910a9ce0e72ada2b447ab7fa0e592d27e))
* **deep-link:** add tauri-plugin-deep-link dependency and update pricing plans ([e6df18f](https://github.com/akira-foundation/unified-dev/commit/e6df18f703fac4660f1481d1365a2d7c9741553f))
* **drivers:** implement GitHub, GitLab, and Bitbucket drivers with API integration ([74be34f](https://github.com/akira-foundation/unified-dev/commit/74be34f53694adac9c4e52503cde74d128ab8c38))
* dynamically render and enable selection of actions in the agent header dropdown menu. ([b2c8665](https://github.com/akira-foundation/unified-dev/commit/b2c86656ad7be6bd321f9a3e22f379d9e49753b4))
* **editor:** integrate syntax highlighter and theme selection ([6f6b6a3](https://github.com/akira-foundation/unified-dev/commit/6f6b6a39dc7eb01d9f12d720a65af6495c867163))
* enhance dashboard layout and improve component styling ([8fd03fd](https://github.com/akira-foundation/unified-dev/commit/8fd03fd8287251d37d338b7475038c9f910f7bef))
* enhance layout with header and notification components ([be81900](https://github.com/akira-foundation/unified-dev/commit/be819008c2e82299ca73705b91ff9145219907fa))
* Enhance model selection UI with Popover and Command components and add Copilot AI provider detection. ([89c99ea](https://github.com/akira-foundation/unified-dev/commit/89c99ea9bcf4c49e18257577d6f9981db3d9001c))
* enhance settings page with improved card structure and descriptions ([504decc](https://github.com/akira-foundation/unified-dev/commit/504decc50244cb07243b7e0a8d05e3911cb96b4f))
* enhance team view with improved card structure, updated member display, and refined styling ([a59f5af](https://github.com/akira-foundation/unified-dev/commit/a59f5af1c137b9137cf84ad1127af2f55307af1c))
* **filters:** implement filter popover with multi-select and toggle options ([c6a5281](https://github.com/akira-foundation/unified-dev/commit/c6a5281c372a48335fb3f36b6ac8ee28fdf85233))
* **github-app:** implement GitHub App installation and uninstallation features, enhance provider organization management ([a1057b0](https://github.com/akira-foundation/unified-dev/commit/a1057b08446d0578c6bf07f32b59886e606abac5))
* Group settings navigation tabs into logical categories for improved organization. ([034ca8a](https://github.com/akira-foundation/unified-dev/commit/034ca8aae1858e2797164cfdfa87d1b80713f969))
* **i18n:** internationalize agent workspace, skills, and automations ([9820207](https://github.com/akira-foundation/unified-dev/commit/98202075471d275895bd4f4871bdccc886a8096e))
* **i18n:** internationalize UI components and pages ([e17e923](https://github.com/akira-foundation/unified-dev/commit/e17e923c6cf8056b617edec0321044b996f4d93c))
* Implement AI provider detection, model registry, and selection UI for agent interactions. ([ca655bf](https://github.com/akira-foundation/unified-dev/commit/ca655bfa643580403068a950ebe5df0fc5066f31))
* Implement automation configuration flow by introducing `selectedAutomation` state and updating UI elements to pre-fill automation details. ([570ba06](https://github.com/akira-foundation/unified-dev/commit/570ba06884398fe25225191a8de90c297cd459a9))
* implement create automation page and refine UI for automations, providers, and skills sections. ([5d43d20](https://github.com/akira-foundation/unified-dev/commit/5d43d20e2d806b567f53ba6cdb0aa2743277d02d))
* Implement file system browsing and editing within the agent interface by adding Tauri commands for file system interaction and updating the UI to display and edit workspace files. ([089e96d](https://github.com/akira-foundation/unified-dev/commit/089e96d1decb11de88f8cf5e31fb60a3f4322f26))
* implement GitHub and Bitbucket VCS providers with repository and pull request synchronization ([3a7fc24](https://github.com/akira-foundation/unified-dev/commit/3a7fc240f2816c921d7362c15feca3e1b3351241))
* implement initial skills page layout matching design ([5852dac](https://github.com/akira-foundation/unified-dev/commit/5852dacce902f8e12efe262d017967338bc9c7a3))
* implement integrated terminal panel with PTY support ([9788620](https://github.com/akira-foundation/unified-dev/commit/9788620e18a08292e7a0a55bf462f2da12fb73aa))
* Implement multi-tab functionality in the terminal panel, allowing users to spawn, close, switch, and rename terminal sessions, and add an `onClose` prop to notify the parent when all terminals are closed. ([3d4487e](https://github.com/akira-foundation/unified-dev/commit/3d4487e39d3fcc7542fc65a5bca46dfd84a965aa))
* implement provider management with CRUD operations and UI integration ([20d1120](https://github.com/akira-foundation/unified-dev/commit/20d11206b8102889fbcec57f871fc6c9e3c88f85))
* implement sidebar navigation in settings with card UI content ([e80116c](https://github.com/akira-foundation/unified-dev/commit/e80116cf0db8d4874c36647200d22deddbf07382))
* improve agent workspace UI and refactor provider/organization services ([52b59fa](https://github.com/akira-foundation/unified-dev/commit/52b59fa8cbe4d7e4b32db109a3631a5a13aa2a8a))
* integrate internationalization and enhance settings management ([f6dfd20](https://github.com/akira-foundation/unified-dev/commit/f6dfd204a627e81ab7adf885ae8b7d1f8f0367be))
* Integrate the Skills page as a tab within the agent workspace, managed by a new `activeTab` state. ([ca9245f](https://github.com/akira-foundation/unified-dev/commit/ca9245f3c3442ee6b682be90761e07f08f31a8d5))
* Introduce skill details page with navigation and standardize UI component rounding. ([ad46922](https://github.com/akira-foundation/unified-dev/commit/ad469227fbd0ff4df2e3ac6458c25724f2f1a226))
* **issue:** add 'Save as draft' and 'Create more' functionality in CreateIssueDialog ([df466e4](https://github.com/akira-foundation/unified-dev/commit/df466e440353068f8de3992dd706ce3aad074616))
* **issue:** add slash command functionality to issue creation with task management ([992bf07](https://github.com/akira-foundation/unified-dev/commit/992bf07b77b27255070a64c42499144ad6a97149))
* **issue:** add sync with provider functionality and update translations ([82d0f4f](https://github.com/akira-foundation/unified-dev/commit/82d0f4f0549beef79a8ae8439f57fefef0b220e4))
* **issue:** enhance issue management with assign to me functionality and improved issue retrieval ([8257e12](https://github.com/akira-foundation/unified-dev/commit/8257e12f2aa92e21ed0276f041b22a416bc63a5b))
* **issues:** add sync_with_provider field and update issue handling logic ([fefe00d](https://github.com/akira-foundation/unified-dev/commit/fefe00dff885b36a2db7d7dbf5d5e5662e97e523))
* **issues:** implement issue tracking, creation, and kanban board ([ec0cfc3](https://github.com/akira-foundation/unified-dev/commit/ec0cfc3ccefd36a3e19d277f69639dab06c7501c))
* **license:** implement license management with activation, verification, and storage functionality ([dc29c91](https://github.com/akira-foundation/unified-dev/commit/dc29c91b220cf1303db5b1b4b2dca00d35fb2d9c))
* make skills switches interactive and use primary color ([83b6dde](https://github.com/akira-foundation/unified-dev/commit/83b6ddea85342da2ab0fb2821088df3743cea96d))
* **mcp:** add MCP server management features and integrate with skills ([51b2501](https://github.com/akira-foundation/unified-dev/commit/51b2501e8c1e7fc50001905ecd25c1e33870710b))
* **mcp:** enhance MCP tool integration with improved server handling and UI updates ([cdcb3d4](https://github.com/akira-foundation/unified-dev/commit/cdcb3d49ecf188b2c91ce42cceabb4a49f69cd27))
* **mod:** add new modules for organization and provider management ([f5f0b4b](https://github.com/akira-foundation/unified-dev/commit/f5f0b4b1fd02d6209f6d8ff3b4297931e7ff15bc))
* **modules:** add new modules for OAuth, session management, file handling, and repository management ([8283fca](https://github.com/akira-foundation/unified-dev/commit/8283fca6d7a29a255df305c502b8b585965a44fe))
* **modules:** add new modules for organization management and issue handling ([abf1f5d](https://github.com/akira-foundation/unified-dev/commit/abf1f5d1d54424f91a10863e3cb284c1056f323e))
* **organizations:** allow editing organizations and optionally keeping them on provider disconnect ([595a144](https://github.com/akira-foundation/unified-dev/commit/595a144c45303d7ee05ad02ff98275e84643887e))
* **organizations:** enhance organization data with selected repos count and last synced timestamp ([0db0744](https://github.com/akira-foundation/unified-dev/commit/0db0744e32fc53f4ae314418e33f568aa8f96cfa))
* **pr:** enhance PR navigation by adding owner information and improving collapse logic ([716ed53](https://github.com/akira-foundation/unified-dev/commit/716ed5317117f62473a41f8b479fcf03565ecf38))
* **provider:** refactor default branch handling and improve issue actions menu ([7875bf0](https://github.com/akira-foundation/unified-dev/commit/7875bf07f800901cccc9d5d244bc588478ad5625))
* **providers:** implement GitHub App auth, GitLab, and Bitbucket drivers ([adf2440](https://github.com/akira-foundation/unified-dev/commit/adf2440d597fa035e554c9c641ad2466eb47b552))
* **providers:** implement GitHub OAuth flow and UI empty states ([6cdb2d4](https://github.com/akira-foundation/unified-dev/commit/6cdb2d4657c271c71beb8b1b6600dbe424cec804))
* **prs:** add filtering capabilities to PR list and enhance UI components ([2d04a96](https://github.com/akira-foundation/unified-dev/commit/2d04a966a4d8c623b2a06caa8d9397b2f78a946a))
* **pull-requests:** enhance pull request management with database integration and additional fields ([0c6a9be](https://github.com/akira-foundation/unified-dev/commit/0c6a9bed5b91c1143193a6dfbf3ce4ac8b8f2ba0))
* **rate-limit:** implement GitHub rate limit retrieval and display in VCS providers tab ([5666067](https://github.com/akira-foundation/unified-dev/commit/566606711af4521a511cedab0861500a4b009ea1))
* refactor organization handling to use provider authentication and update database schema ([8626491](https://github.com/akira-foundation/unified-dev/commit/86264918a20342d1e39ec68c1918ec5552e01f43))
* **release:** add build and release workflows with version syncing ([f06469a](https://github.com/akira-foundation/unified-dev/commit/f06469a85ef4fd20549009aa6cd8f7e7014b6de1))
* **remote:** implement remote access settings management and add related API endpoints ([c6b6fd3](https://github.com/akira-foundation/unified-dev/commit/c6b6fd36fcf4056cdcd4ccb98697d78e7bf65b71))
* rename project to Unified Dev and implement organization management features ([8d09cd5](https://github.com/akira-foundation/unified-dev/commit/8d09cd53d103b25bbddf2c7c34180c2c22285221))
* **repos:** connect sidebar and dialog to tauri backend ([e2f1c1f](https://github.com/akira-foundation/unified-dev/commit/e2f1c1fdab8497988a0d5ed937b9625628d26f7e))
* **repos:** implement add repository dialog with native folder selection ([ed247e0](https://github.com/akira-foundation/unified-dev/commit/ed247e04e461e11c99b8677fc27116c6642b3e81))
* **repos:** implement thread management and repository listing ([32c6705](https://github.com/akira-foundation/unified-dev/commit/32c67057f4cdb27641d98e56263be923b661cdd0))
* **repositories:** add repository statistics and manual PR sync to detail page ([7cbc39c](https://github.com/akira-foundation/unified-dev/commit/7cbc39c6825968c73336640a1ae46182655c9a46))
* **repositories:** display all selected repositories globally on the repositories page ([53e2c66](https://github.com/akira-foundation/unified-dev/commit/53e2c6641f343037f3eda6b9d12af121775ae11a))
* **repositories:** implement adding repositories from remote clone URL ([b8481eb](https://github.com/akira-foundation/unified-dev/commit/b8481eb7bd00cbae6d329e0d18b9a5ca042ca509))
* **repositories:** implement branch management and issue deletion ([b0b4c09](https://github.com/akira-foundation/unified-dev/commit/b0b4c09f693c4caa62945d44d210ac4e1d50fc6e))
* **repositories:** implement full PR review page with diff viewer ([d35c075](https://github.com/akira-foundation/unified-dev/commit/d35c075184771cb6d6324834671108712b6734fe))
* **repositories:** implement PR checks view and CI logs parsing ([d117b94](https://github.com/akira-foundation/unified-dev/commit/d117b947c499c351978995d84a30ce1b590c1619))
* **repositories:** implement PR stats syncing and task creation from repository table ([bc420e5](https://github.com/akira-foundation/unified-dev/commit/bc420e50b0e1396e87fa38fa604d9fce0fac3ace))
* **repositories:** implement pull request details, comments, and reviews ([2c76306](https://github.com/akira-foundation/unified-dev/commit/2c76306911de5955dd4e069be9fb96de63a9e6a3))
* **repositories:** implement pull requests view for repositories ([3ef900a](https://github.com/akira-foundation/unified-dev/commit/3ef900a1d19c86767d70d38ef7580d7fcc332cf3))
* **repositories:** refactor repository functions and add filesystem operations ([6d95855](https://github.com/akira-foundation/unified-dev/commit/6d95855f00fb62c2c58791e6ec8248ca86d35645))
* **repository:** add fork information to organization repositories ([c56a331](https://github.com/akira-foundation/unified-dev/commit/c56a3315cf6d457c329353d7e9c330e37fd604fd))
* **repository:** add remote URL handling for local repositories and implement organization linking ([92d80f0](https://github.com/akira-foundation/unified-dev/commit/92d80f0f19840fa0a6143cc3de0b319a460e281e))
* restructure settings UI and add precise prompt configurations ([7095e2a](https://github.com/akira-foundation/unified-dev/commit/7095e2a7b9c6cfe182da143847e7541b8275fa98))
* revert settings to standard card UI and integrate developer configurations ([bbb3005](https://github.com/akira-foundation/unified-dev/commit/bbb30057b0f2c8a84cdcd6b3dde0c14aa5c53515))
* **sidebar:** add settings button to sidebar footer and update layout ([7a011fb](https://github.com/akira-foundation/unified-dev/commit/7a011fbb5f371dbcdc6b4ea18c93d2f69ff3271c))
* **skill-discovery:** filter out skills with empty descriptions in recommendations ([7816566](https://github.com/akira-foundation/unified-dev/commit/78165663e2a8b76df5f611aa63deeceb5f338060))
* **skill-discovery:** implement recommended skills fetching and enhance skill management UI ([4d91976](https://github.com/akira-foundation/unified-dev/commit/4d919764466d9c60bf3632f6e0d2adb26979caa2))
* **skills:** fetch installed skills dynamically from backend ([980820d](https://github.com/akira-foundation/unified-dev/commit/980820d72d5e42b0fe757907f954939b8d9d089b))
* **skills:** implement skill installation and icon management ([be9134a](https://github.com/akira-foundation/unified-dev/commit/be9134af83d9e7b57633cc7bb0775d6a0ed68e4b))
* **slash-command:** enhance slash command menu with grouping and shortcuts ([6eb6483](https://github.com/akira-foundation/unified-dev/commit/6eb6483a1f19384109cbeb2e0470f479503bd215))
* standardize card headers with new icon-driven design and updated styling across various pages and components ([bbc1e49](https://github.com/akira-foundation/unified-dev/commit/bbc1e49a9f31cfd48c7192030cdbb6fed0433364))
* **sync:** implement sync settings management and UI components ([ae5a819](https://github.com/akira-foundation/unified-dev/commit/ae5a819f4baf6b0edb672f58c9ddf3947bbaa016))
* **terminal:** add minimize button, persist sessions, and resizable panel ([9b1b5ed](https://github.com/akira-foundation/unified-dev/commit/9b1b5edbe696c5f63d7449f2e7cf4b27e294bc2c))
* **ui:** complete issue filtering UI and separate filter namespaces ([b62bdef](https://github.com/akira-foundation/unified-dev/commit/b62bdefd65c3769241c886009616071b97d0fd66))
* **ui:** implement generic Combobox component and issue filtering ([e2b2089](https://github.com/akira-foundation/unified-dev/commit/e2b208990b92677854d8d32bba4e0818541cdffd))
* **ui:** implement syntax highlighting in diff viewer ([6852646](https://github.com/akira-foundation/unified-dev/commit/6852646c4e5bc065c269496f924dc984d8634d18))
* **ui:** integrate real data into dashboard stats and PR kanban board ([9d80360](https://github.com/akira-foundation/unified-dev/commit/9d80360245549266d71c88e0c64736d713b466cc))
* **ui:** migrate data fetching to React Query and tables to TanStack Table ([ee2883c](https://github.com/akira-foundation/unified-dev/commit/ee2883cce9e9c23236fe684d789b5b11b50867a6))
* **ui:** relocate provider management to settings and add provider details page ([5505118](https://github.com/akira-foundation/unified-dev/commit/55051186724d2dfd3601239c4ac5d8f7c7b6bdd1))
* **ui:** replace heavy diff viewer with lightweight custom patch viewer ([b3eed78](https://github.com/akira-foundation/unified-dev/commit/b3eed78ac8f1e7895db8e331ad521265efa9afa8))
* update dashboard and organization components with improved styling and new button integration ([6dd304a](https://github.com/akira-foundation/unified-dev/commit/6dd304a35f2b066fabdb1d6ff9ee5235ae835921))
* update dashboard layout with improved card structure and localization support ([a2487ed](https://github.com/akira-foundation/unified-dev/commit/a2487ede5edd1bb90db09a504068989b446531b3))
* update sidebar button text from 'New thread' to 'Add new repository' and add a tooltip to the 'Add new thread' button. ([9b1ef52](https://github.com/akira-foundation/unified-dev/commit/9b1ef52c4dca4a3d4c2a8c1d7593fb2dfc35c9e1))
* update upgrade modal and translations for new pricing plans and descriptions ([ffec3cc](https://github.com/akira-foundation/unified-dev/commit/ffec3cc33115ee4520aed30fc2ace2fbab5bcd10))
* use explicit back arrow instead of workspace logo in agents sidebar ([ed9273e](https://github.com/akira-foundation/unified-dev/commit/ed9273e585040a34aa3e9b85693d5b242bae8703))
* use matching workspace branding header inside agents sidebar ([346df91](https://github.com/akira-foundation/unified-dev/commit/346df9168c49f460e58819274fcc5ee2f4ef3656))
* **visibility:** add visibility preferences management and update related logic ([b730852](https://github.com/akira-foundation/unified-dev/commit/b730852e630c23514e61eb1bb1de5b1ce01cb65a))
* **workspace:** implement workspace renaming functionality and update related logic ([aedefb9](https://github.com/akira-foundation/unified-dev/commit/aedefb9f8383b142638e1d10dc08e6c10907c4fa))
