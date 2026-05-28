# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.12.2](https://github.com/akira-foundation/unified-dev/compare/v0.12.1...v0.12.2) (2026-05-28)

### Bug Fixes

- **ci:** Push landing changelog after committing ([0496883](https://github.com/akira-foundation/unified-dev/commit/04968830e659e5977053ba7644fc6db8a41262c7))
- **macos:** Bundle entitlements so the keychain entry persists ([1f06972](https://github.com/akira-foundation/unified-dev/commit/1f069726734e8b5ab472572f28c61fcccd652b09))

## [0.12.1](https://github.com/akira-foundation/unified-dev/compare/v0.12.0...v0.12.1) (2026-05-28)

### Bug Fixes

- **panic:** Persist panic info to disk before aborting ([04ba4db](https://github.com/akira-foundation/unified-dev/commit/04ba4db932b62f80a7053a52f8922cb05a62fbef))
- **license:** Tolerate cipher decrypt failure during setup ([fbcc80e](https://github.com/akira-foundation/unified-dev/commit/fbcc80e8e31e2991e8e18927d739c964305b299e))
- **providers:** Drop duplicate Details card on provider detail page ([78b9a6c](https://github.com/akira-foundation/unified-dev/commit/78b9a6c8a25031b4517bc1e9d536d0e8262201fd))
- **providers:** Strip the redundant icon + kind + connected row from the header ([ce376c1](https://github.com/akira-foundation/unified-dev/commit/ce376c1443001550d9f61b0715991da0886c1033))
- **providers:** Restore Details card and surface provider name in the breadcrumb ([296ce62](https://github.com/akira-foundation/unified-dev/commit/296ce627291a40fcdd933c47f0f6b5b106c634c1))


### Features

- **updater:** Backup database before installing update ([f55e1b8](https://github.com/akira-foundation/unified-dev/commit/f55e1b80957c1bdc5c9e25e2ea588fef57eb5ecf))
- **updater:** Restore database from a previous backup ([1d85d22](https://github.com/akira-foundation/unified-dev/commit/1d85d22d5df68f637219156cff6d63e16855a217))
- **license:** Add payment status banner skeleton ([8d2882a](https://github.com/akira-foundation/unified-dev/commit/8d2882a9050da1d8e9af327303baf97fece16e7f))
- **license:** Wire payment status banner to the live license payload ([a08bd6c](https://github.com/akira-foundation/unified-dev/commit/a08bd6c50b7521844f26fbb61ac6634b4247dbd5))

## [0.12.0](https://github.com/akira-foundation/unified-dev/compare/v0.11.5...v0.12.0) (2026-05-28)

### Bug Fixes

- **ci:** Parse latest changelog block and attribute landing commit to author ([0908aac](https://github.com/akira-foundation/unified-dev/commit/0908aac3b0838361bd7f607ab9c4cc94cce4d50d))
- **github:** Retry graphql on transient empty response ([9f00143](https://github.com/akira-foundation/unified-dev/commit/9f00143d45cf2ad1af1eadb9e488bd3132d30a80))
- **tracker:** Linear as a row inside Integrations section ([ece0a3f](https://github.com/akira-foundation/unified-dev/commit/ece0a3f80922725ac7ef35f8617fc4a48f5179ec))
- **tracker:** Integrations tab shows only Linear ([9ed43e1](https://github.com/akira-foundation/unified-dev/commit/9ed43e11054c35e3d58e60b319497f001035cdab))
- **tracker:** Match existing modal pattern for Linear connect ([496a36d](https://github.com/akira-foundation/unified-dev/commit/496a36dddde03bad7900019d26ad8ba89d725d2d))
- **ui:** Restore visible dialog border in dark mode ([b0e8f34](https://github.com/akira-foundation/unified-dev/commit/b0e8f340e1d9e20b190a2e6d688538142beb272a))
- **tracker:** Polish Linear connect modal, errors, and sync feedback ([f0d2568](https://github.com/akira-foundation/unified-dev/commit/f0d25685d9b7611c216f3f062226b05cc8d6218f))
- **ui:** Autopilot dialog uses modal backdrop for consistency ([86f70d0](https://github.com/akira-foundation/unified-dev/commit/86f70d08b295ec0382bce196ee6ff59d8197ad67))
- **issues:** Sticky group headers and right-aligned chevron ([3485490](https://github.com/akira-foundation/unified-dev/commit/3485490169556d98dcdb235867ed23c6c4d9e4ce))
- **prs:** Sticky headers, right chevron, non-uppercase labels, cache like issues ([c32690c](https://github.com/akira-foundation/unified-dev/commit/c32690c8322c3764d1c2e59b98cc95fc48f75188))
- **projects:** Project-detail breadcrumb via global header ([f063ab9](https://github.com/akira-foundation/unified-dev/commit/f063ab9989434374b92df0a4e69ce143441301fc))
- **projects:** Searchable scrollable repo picker in add-repo ([000cd2b](https://github.com/akira-foundation/unified-dev/commit/000cd2b9e0d2227f1c78a38c959504d60919a79d))
- **projects:** Clean source labels and aligned repo rows ([cb22c17](https://github.com/akira-foundation/unified-dev/commit/cb22c17bd1f440a07e6d3a3e89b0545bb40cbe80))
- **issues:** Never render raw tracker UUIDs ([9972e60](https://github.com/akira-foundation/unified-dev/commit/9972e607b2fed844a319738938fad9a7eb6f8509))
- **projects:** Source chip shows provider/scope, not repo name ([6c7afde](https://github.com/akira-foundation/unified-dev/commit/6c7afde233fb92c93f4f87f2bda475c5f12b30e4))
- **projects:** Single-line repo rows, issues-provider terminology, no duplicate provider badge ([3b54bc3](https://github.com/akira-foundation/unified-dev/commit/3b54bc3970f59a99bffe9d57b268abd88133efdb))
- **sync:** Master switch gates all auto-sync ([39a257f](https://github.com/akira-foundation/unified-dev/commit/39a257fe0413b1f72127c866259116e0ed0f8b5c))
- **issues:** Searchable repo picker in assign dialog ([fcdb59f](https://github.com/akira-foundation/unified-dev/commit/fcdb59f7b78b95d964a1770f7c0ee24238abb0d0))
- **import:** Sync imported scopes and surface empty projects in filter ([dcca1be](https://github.com/akira-foundation/unified-dev/commit/dcca1be89a8cf8d240ae5f890a9c5aa5736daefe))
- **import:** Full provider sync on import so all selected project issues land ([037bfb4](https://github.com/akira-foundation/unified-dev/commit/037bfb48937f40bb25ff7d04e978a2ca046ecc26))
- **tracker:** Use loopback redirect for Jira OAuth, not a deep link ([0bff973](https://github.com/akira-foundation/unified-dev/commit/0bff973c0564fec5630b66c1570b9c59dd79a8c1))
- **tracker:** Silence dead-code warnings and align provider-detail with app pattern ([ae8af09](https://github.com/akira-foundation/unified-dev/commit/ae8af099222e69e2b0429409b5abd943b7180f95))
- **issues:** Restore sticky group headers in virtualized issue and PR lists ([c27c43f](https://github.com/akira-foundation/unified-dev/commit/c27c43f4e810f56cea06866117e3d8533c33c7a6))
- **sync:** Default auto-sync off in debug builds to match the UI ([70567f2](https://github.com/akira-foundation/unified-dev/commit/70567f2d26ad7f205ccf7dd99c92939b279bf71c))
- **license:** Derive status from payload in store_verified ([f42666c](https://github.com/akira-foundation/unified-dev/commit/f42666c36dbc30d8a78253ad95289a5e98dfacd9))
- **license:** Delegate grace and expiry to lifecycle, keep envelope on revoke ([c0fd5d0](https://github.com/akira-foundation/unified-dev/commit/c0fd5d0ceaad0a2136dbff3141af1a2177d49d8f))
- **commands:** Expose lifecycle-aware status to the frontend ([9207c79](https://github.com/akira-foundation/unified-dev/commit/9207c797e01c2e2a83707145a6b8606d23dea5a1))
- **license:** Enforce free limits when envelope is absent or expired ([4c91df3](https://github.com/akira-foundation/unified-dev/commit/4c91df35d9ab1450f0a09879acefc8cf915ca5c8))
- **license:** Gate paid features on lifecycle state, not stored plan ([f119336](https://github.com/akira-foundation/unified-dev/commit/f119336d1adab2dcd41256ca5f29c14674ed761b))
- **projects:** Auto-sync tracker issues after add_source ([fb50d5b](https://github.com/akira-foundation/unified-dev/commit/fb50d5bf0e0e1e1bd783f7940eaa5c0b04557edd))
- **projects:** Scope auto-sync to the chosen project or team ([5b45372](https://github.com/akira-foundation/unified-dev/commit/5b45372e56be7c83069735f93d5b46e2129134a8))
- **projects:** Scope manual sync menu to each source, not the whole provider ([ce4908a](https://github.com/akira-foundation/unified-dev/commit/ce4908afbb3b303af1928f9d0eabd09e7589680b))
- **issues:** Make filter selection visible ([4fbd8c8](https://github.com/akira-foundation/unified-dev/commit/4fbd8c8e356fadd04e8a7a405dd2822b9e2e2674))
- **issues:** Stop reordering filter rows when selected ([3d4df77](https://github.com/akira-foundation/unified-dev/commit/3d4df772ca1b154520a4ba7f605f04e89b71a711))
- **subscription:** Surface the real backend error when the portal call fails ([f78b873](https://github.com/akira-foundation/unified-dev/commit/f78b8733d0c14480100726999dec731ab3196ce8))


### Code Refactoring

- **nav:** Reorganize sidebar into Work / Structure / Explore ([9b7e601](https://github.com/akira-foundation/unified-dev/commit/9b7e601926a48c7ea7900e55c821c30b9ffd48ea))
- **license:** Adopt billing-sdk v1.1.0 PublicKeyStore for baked keys ([66c6120](https://github.com/akira-foundation/unified-dev/commit/66c61202357d9e3d0366bb33a1797226a48e3892))
- **license:** Use derived device fingerprint, drop random machine_id ([372f350](https://github.com/akira-foundation/unified-dev/commit/372f350b9d1f5a3a4d54521afc632598fc3b1cb2))
- **security:** Drop hand-rolled TokenCipher for the SDK version ([8ce846a](https://github.com/akira-foundation/unified-dev/commit/8ce846a4160efafeb681f0747bd0287adf4e427f))
- **security:** Use SDK keystore instead of manual onyx::keyring ([5297792](https://github.com/akira-foundation/unified-dev/commit/529779226bdf6b6b39dfeeea1c5bd351f8019cae))
- **license:** Drop Keyring wrapper, call SDK verify_license directly ([5b3e362](https://github.com/akira-foundation/unified-dev/commit/5b3e362430c089ceba0d4936285b24cc100ee1b4))
- **license:** Route feature gates through SDK Gate + DenyReason ([95a743b](https://github.com/akira-foundation/unified-dev/commit/95a743b49eeb64ec18dce3d96e76acccffa2d06c))
- **tracker:** Consume omnitrack instead of issue-provider-* trio (#95) ([ac2df48](https://github.com/akira-foundation/unified-dev/commit/ac2df48834ec82a5acc1e738b336f93c4e253952))


### Features

- **tracker:** Provider-neutral issue-tracker seam (P1) ([5d01e10](https://github.com/akira-foundation/unified-dev/commit/5d01e10f32cd5df9b23f61122469da06b4b39264))
- **tracker:** Persistence and Tauri commands (P2) ([8948b4f](https://github.com/akira-foundation/unified-dev/commit/8948b4f1ddfca77decb33ce61b2b614fbf074824))
- **tracker:** Issue mutation commands (P3) ([a3ca36c](https://github.com/akira-foundation/unified-dev/commit/a3ca36ca72b3ff0698312597f83f0e0ca17d787d))
- **tracker:** Integrations connect form + tracker service (P4) ([6157be9](https://github.com/akira-foundation/unified-dev/commit/6157be9202862ba7b313278edff8652533f1e6ab))
- **tracker:** API key modal for Linear connect ([5d23b2f](https://github.com/akira-foundation/unified-dev/commit/5d23b2f1875b4af4130c734675283ec18a1734fb))
- **tracker:** Provider-agnostic integration, name resolution, projects grouping v1 ([242bf3f](https://github.com/akira-foundation/unified-dev/commit/242bf3f12b635d9b98483cc8fd1bc3dcb37e8172))
- **projects:** Org > project > repo > source model (phase 1) ([6d79e7c](https://github.com/akira-foundation/unified-dev/commit/6d79e7cf6da26cb7594d105c7aac3fdd049579f6))
- **projects:** List/detail navigation matching app pattern ([e7cde47](https://github.com/akira-foundation/unified-dev/commit/e7cde474bcd0b083261aa037bf0fe3aab5917551))
- **projects:** Add-repo modes + lowercase breadcrumb ([9aa78fa](https://github.com/akira-foundation/unified-dev/commit/9aa78fa1a318e23201ca1ddf08c3c2c4d858bf94))
- **projects:** Multi-select existing repos + local folder browse ([1341f42](https://github.com/akira-foundation/unified-dev/commit/1341f42b6e7816d3e70c25433fca02f4f4428c75))
- **projects:** View-issues action + cache sidebar counts longer ([f2713be](https://github.com/akira-foundation/unified-dev/commit/f2713be042651591ef703da18a7798488cc4344c))
- **issues:** Add Repos filter facet ([d6b0e20](https://github.com/akira-foundation/unified-dev/commit/d6b0e2046f9309d09a834addf8d86e81fd76b730))
- **projects:** Open repo page from project repo row ([dd45895](https://github.com/akira-foundation/unified-dev/commit/dd4589547439a6b1bebaf999dcd00a68632b779b))
- **filters:** Active-filter badges, selected-first ordering, searchable source picker ([860e429](https://github.com/akira-foundation/unified-dev/commit/860e429520044d34d65beaeca8ddcdce5714092b))
- **nav:** Show project count badge in sidebar ([cd08cea](https://github.com/akira-foundation/unified-dev/commit/cd08cea50b78d254a316353e67024422c1199f0a))
- **projects:** Remove issues provider from repo kebab ([c384e73](https://github.com/akira-foundation/unified-dev/commit/c384e7373200303ad3b6943aff97ae9223ce168e))
- **issues:** Resolve repo container for issues, group Repos facet by it ([f34d32b](https://github.com/akira-foundation/unified-dev/commit/f34d32b63e28d6847c53e7a37ad097ed5442e876))
- **prs:** Add Failed column to PR kanban, de-uppercase state labels ([5a1cf8f](https://github.com/akira-foundation/unified-dev/commit/5a1cf8f26710437eda51b3e3b6659b60f7add42f))
- **issues:** Assign unmapped issue to a project repo from the kebab ([b15eaf3](https://github.com/akira-foundation/unified-dev/commit/b15eaf31ed73b976f01ec4f4712c33d1fdb6abca))
- **projects:** Batch import tracker projects as repos ([d4e69ae](https://github.com/akira-foundation/unified-dev/commit/d4e69ae6f0496b29c314e140e5ddd018361644be))
- **tracker:** Add Jira provider driver and connect UI ([7c4b98d](https://github.com/akira-foundation/unified-dev/commit/7c4b98d1cb5cc2f84f7a42303ba9261c5d9810cb))
- **tracker:** Connect Jira via OAuth instead of a manual token ([b60b8e5](https://github.com/akira-foundation/unified-dev/commit/b60b8e585a95b4bb11638f5c43e120dcf30dd976))
- **projects:** Link repos, import dedup, per-provider sync, provider icons ([c7786c3](https://github.com/akira-foundation/unified-dev/commit/c7786c358cc39baf8534c826577089fd1e9f5161))
- **gating:** Enforce free-plan repo and org limits from license snapshot ([0503082](https://github.com/akira-foundation/unified-dev/commit/05030821fcb357352d116279e3a827eaeeb79cfb))
- **prs:** Inline-editable PR description with flat-row checks and diff UI ([2ece48f](https://github.com/akira-foundation/unified-dev/commit/2ece48f33073606ff0c612ff530a5f2818fabb4e))
- **license:** Add lifecycle module wrapping SDK compute_state ([1da229b](https://github.com/akira-foundation/unified-dev/commit/1da229b89c1d5387b83c00faaf181462bccb3268))
- **license:** Build SDK Gate and expose it on AppState ([ddb20ef](https://github.com/akira-foundation/unified-dev/commit/ddb20efea74c464e385a832350588176379e3bfb))
- **license:** Teach the frontend the full lifecycle state set ([9e2c944](https://github.com/akira-foundation/unified-dev/commit/9e2c9446e27519b570a848c3119ffd79ba9234e3))
- **license:** Grace banner and expired blocking screen ([67c5e10](https://github.com/akira-foundation/unified-dev/commit/67c5e109ef99109170089b0706c74fac02eaa9ad))
- **license:** Bootstrap free envelope via SDK public_free_snapshot ([f075ecc](https://github.com/akira-foundation/unified-dev/commit/f075ecc0db586efe3b25d7e33a1c89ec39c5f3bc))


### Performance Improvements

- **cache:** Long-cache issue/PR lists, refresh on sync events ([0fd1be9](https://github.com/akira-foundation/unified-dev/commit/0fd1be9191e92faac1d817ef7ee040a00082841b))
- **issues:** Virtualize issue list with @tanstack/react-virtual ([f1992f9](https://github.com/akira-foundation/unified-dev/commit/f1992f9c4e3d91560a2e84b905bbd9490bdf22b6))
- **prs:** Virtualize PR list with @tanstack/react-virtual ([dc6d4c0](https://github.com/akira-foundation/unified-dev/commit/dc6d4c0a067d874210832b1706ec156f6c1f8b1c))
- **lists:** Internal scroll virtualizer + progressive load ([ea2074e](https://github.com/akira-foundation/unified-dev/commit/ea2074e73a960dd7e4a3ccd294ede6829d7e67f0))
- **prs:** Drop network sync from PR list read + content-visibility kanban cards ([6761a07](https://github.com/akira-foundation/unified-dev/commit/6761a070f4c68ac3b336f5c2b05baf29bd8e0c15))
- **kanban:** Virtualize issue and PR kanban columns ([f4ae94e](https://github.com/akira-foundation/unified-dev/commit/f4ae94eeb7a6ff8e71b4b98fa79df852cd2ea07a))

## [0.11.5](https://github.com/akira-foundation/unified-dev/compare/v0.11.4...v0.11.5) (2026-05-24)

### Bug Fixes

- **dashboard:** Remove dark hover from stat cards ([ef4ee9e](https://github.com/akira-foundation/unified-dev/commit/ef4ee9e9d267ac0c58aec3e118ba0a6afba9806b))
- **open-source:** Remove dark hover from stat cards ([4c9f419](https://github.com/akira-foundation/unified-dev/commit/4c9f419cae114f9ca2011b6842d9f5e1f63ad044))
- **ui:** Always show pointer cursor on stat cards ([d7bc03d](https://github.com/akira-foundation/unified-dev/commit/d7bc03d12e644d391a6469ee341473a6667ac3ae))
- **repos:** Stop menu clicks from navigating to repo detail ([5a202fa](https://github.com/akira-foundation/unified-dev/commit/5a202fab07eb5da2fb95114900bcfaa3cb190146))
- **ui:** Stop dropdown menu clicks from bubbling to ancestors ([45e9c66](https://github.com/akira-foundation/unified-dev/commit/45e9c66c7e83911a51ff4b7edb1de7661bda6d70))
- **issues:** Open the thread chat after Resolve with AI ([109e9ff](https://github.com/akira-foundation/unified-dev/commit/109e9ff27da4ba5a81574e16af1f33bb168863dd))
- **issues:** Activate thread chat on delegate via authoritative reload ([424a738](https://github.com/akira-foundation/unified-dev/commit/424a7385dadc31fb03a0338709dcb046abef33a4))
- **agents:** Resolve gh binary path for PR detection and CI ([d1aebf2](https://github.com/akira-foundation/unified-dev/commit/d1aebf2891ef32e1311749dfe3e3ac1cc120a4a4))
- **providers:** Cache github installation tokens to stop billing 429 ([a06b05a](https://github.com/akira-foundation/unified-dev/commit/a06b05a66f8ffaa7bf5083433019a09f6324d047))
- **providers:** Https billing url fallback, bump SDK 0.4.0, back off on 429 ([ff2dfc8](https://github.com/akira-foundation/unified-dev/commit/ff2dfc8330f021afe3de049112658d8ec83861c8))
- **notifications:** Correct tab counts and open without vanishing ([b9bbe92](https://github.com/akira-foundation/unified-dev/commit/b9bbe921cd77959d168b920f3352c1dbda5b256f))


### Code Refactoring

- **issues:** Use local kanban override for delegate status ([c8a7a4a](https://github.com/akira-foundation/unified-dev/commit/c8a7a4a838113c93f1329a8b8d1b11f0f7e5b314))


### Features

- **issues:** Move issue to in progress when delegated to AI ([d4d0f1b](https://github.com/akira-foundation/unified-dev/commit/d4d0f1bf25930a34d7ffd6b018118133831f0243))
- **pr:** Close linked issues on merge ([f2c8e77](https://github.com/akira-foundation/unified-dev/commit/f2c8e77e74c6b60a20a192fc5d4d1c445f907cef))
- **threads:** Name thread branches after issue slug instead of UUID ([ab4b979](https://github.com/akira-foundation/unified-dev/commit/ab4b979e97a2e30dae88be7d2c8f08043d8ff3a6))
- **agents:** Dockable CI panel, action loading feedback, CLI tool-call streaming ([dc932ee](https://github.com/akira-foundation/unified-dev/commit/dc932ee358cce32ba405e3023dfe9515151f25ac))


### Other

- **notifications:** Restore card hover background ([a24f856](https://github.com/akira-foundation/unified-dev/commit/a24f85635419c87ededc669b276a5f264ebe6e38))

## [0.11.4](https://github.com/akira-foundation/unified-dev/compare/v0.11.3...v0.11.4) (2026-05-23)

### Bug Fixes

- **sync:** Use OAuth token for GitHub GraphQL, not the installation token ([24d0a83](https://github.com/akira-foundation/unified-dev/commit/24d0a832abc568cbee1540843f3f57a85200457d))
- **notifications:** Remove hover background from notification cards ([c665e7e](https://github.com/akira-foundation/unified-dev/commit/c665e7e3a23e70fef3573cc0123711a15a25723e))
- **github:** Make write_token crate-visible for graphql client ([1335c19](https://github.com/akira-foundation/unified-dev/commit/1335c192258a2f0cb6c73b4770097379d6cc62ae))

## [0.11.3](https://github.com/akira-foundation/unified-dev/compare/v0.11.0...v0.11.3) (2026-05-23)

### Bug Fixes

- **org:** Correct GitHub token type for API authentication ([6eeb7cd](https://github.com/akira-foundation/unified-dev/commit/6eeb7cd57092500bdcaa517c520c5a1bbb0d48e8))
- **org:** Correct GitHub API response struct for user installations ([abf1f5f](https://github.com/akira-foundation/unified-dev/commit/abf1f5f7f77923f97c3d61cc49ee54d5c94ed8f7))
- **sync:** Mint a fresh installation token per repo owner ([0dc93a9](https://github.com/akira-foundation/unified-dev/commit/0dc93a974465e7b8617bcb6fc3f1c91e6b070066))

## [0.10.1](https://github.com/akira-foundation/unified-dev/compare/v0.10.0...v0.10.1) (2026-05-20)

### Bug Fixes

- **issues:** Kanban drag-drop — drop preview, visible overlay, grab cursor ([879d9b5](https://github.com/akira-foundation/unified-dev/commit/879d9b507a7f2cf3c74acbd13c951ee3b039d454))
- **license:** Preserve account email on verify, top-align identity card ([f35cec9](https://github.com/akira-foundation/unified-dev/commit/f35cec9c792829585e49a13bc91cf30e63178987))
- **license:** Route downgrade through billing SDK instead of dead worker ([3a4ea25](https://github.com/akira-foundation/unified-dev/commit/3a4ea255828ea529146c53d06aa04766538355e3))
- **license:** Route manage subscription through SDK billing_portal ([4e43305](https://github.com/akira-foundation/unified-dev/commit/4e4330536b31cfd4a1f44a1e6f5ce4c2b299bfcb))
- Bypass billing API rate limits with direct GitHub API calls and caching ([763099d](https://github.com/akira-foundation/unified-dev/commit/763099dfcda7ac14aedf347757001ec1ba8e74aa))


### Code Refactoring

- **ui:** Breadcrumb app header, PRs sidebar page, drop page-header band ([699e3e8](https://github.com/akira-foundation/unified-dev/commit/699e3e8edc72eb47838e696ecfbdbe97620c6f5b))
- **ui:** Clean Linear-style tabs and smart default PR tab ([3192fa7](https://github.com/akira-foundation/unified-dev/commit/3192fa7f987f17ab1ba3d83b20b9bdfedd4cee5d))
- **repos:** Linear list pattern and push filter panels in repo views ([b43f2c1](https://github.com/akira-foundation/unified-dev/commit/b43f2c1f74771de0c56a5b895dd52b462d51756e))
- **org:** Linear org pages, compact forms, responsive appbar ([687681a](https://github.com/akira-foundation/unified-dev/commit/687681a8c7048305a46bbaf02c7e28650099dbb9))


### Features

- **ui:** Centered appbar search overlay, flat command items, compact empty state ([5332165](https://github.com/akira-foundation/unified-dev/commit/5332165d819df7ce24ca1d4b1a5df758b04dd199))
- **issues:** Linear-style list + detail page, comments, user-authored writes ([8e1b9e2](https://github.com/akira-foundation/unified-dev/commit/8e1b9e251e178c1c27d699fcea363f4267602e59))
- **issues:** Linear-style kanban, board filter, hidden columns, Cmd+N shortcuts ([396cfe4](https://github.com/akira-foundation/unified-dev/commit/396cfe414ec85fc2e49465ecab2c9d1eb423e6a4))
- **prs:** Replicate Linear UI on PRs + appbar action consistency ([de2d561](https://github.com/akira-foundation/unified-dev/commit/de2d56197da2b299cac2b6676c18a669db5b0f8c))
- **prs:** Redesign diff viewer with flat blocks and word-level highlight ([85503de](https://github.com/akira-foundation/unified-dev/commit/85503defaf01e3652421721c15447bd340851455))
- **repos:** Per-tab search in repo detail and theme-aware command palette ([c473f08](https://github.com/akira-foundation/unified-dev/commit/c473f0880efc39f85697e0b436e889ccd374d5e5))
- **prs:** Unify PR into single detail page (overview, files, checks) ([74d838d](https://github.com/akira-foundation/unified-dev/commit/74d838d9a85c8ccfabd5b52417f8cb7c14bf29c7))
- **agents:** Docked workspace island + chat changes summary ([bf4fff7](https://github.com/akira-foundation/unified-dev/commit/bf4fff7b81d0a35077f99b494ed41593aaa78d8d))
- **skills:** Sync button, frontmatter scalar fix, app-pattern detail/notifications ([7b56d53](https://github.com/akira-foundation/unified-dev/commit/7b56d538467f82f64b1422d868728a029f70731c))
- **license:** Migrate billing flow to SDK, web checkout + invoices, drop worker ([afc52ef](https://github.com/akira-foundation/unified-dev/commit/afc52ef65f2cd8fb24c6b9f92b8070fd152dc454))
- **license:** Runtime public-key fetch/cache + app-wide validation triggers ([08c1569](https://github.com/akira-foundation/unified-dev/commit/08c156957c4e2f0103c096ebbb3edfef9a076164))
- **license:** Add subscription resume and downgrade/resume toasts ([2f81819](https://github.com/akira-foundation/unified-dev/commit/2f81819d842400d0dda132b6547572c1e8185c48))

## [0.10.0](https://github.com/akira-foundation/unified-dev/compare/v0.9.0...v0.10.0) (2026-05-20)

### Bug Fixes

- **providers:** Keep organizations when deleting VCS provider ([62d2a00](https://github.com/akira-foundation/unified-dev/commit/62d2a00ace3fd10323399ba75b8d79904372e8b1))
- **orgs:** Align free-tier counter with provider join ([ad33324](https://github.com/akira-foundation/unified-dev/commit/ad33324e1f98e45539203594ce123caf03e22187))
- **license:** Treat empty plan as free in get_plan ([b4ec67d](https://github.com/akira-foundation/unified-dev/commit/b4ec67d51a05a630bf851640594c2e661e178d0b))
- **license:** Persist store, load on mount, clear-first on logout ([d9cf24d](https://github.com/akira-foundation/unified-dev/commit/d9cf24dd61fb4917b532800ed2c519fa0ad81c65))


### Code Refactoring

- **autopilot:** Feature gate via akira-billing SDK ([814628a](https://github.com/akira-foundation/unified-dev/commit/814628a0d6a0af4e95c01f50d284ee677654727c))
- **github:** Migrate provider flows to billing sdk ([4511abc](https://github.com/akira-foundation/unified-dev/commit/4511abcc5d1f7d35446bdd4119c3b9b56fa6ad43))
- **license:** Delegate Ed25519 verification to akira-billing 0.2.0 ([154d99f](https://github.com/akira-foundation/unified-dev/commit/154d99f3f7e2973828ab08f0a8ed2f0e8763957c))


### Features

- **autopilot:** Finish job with an auto-created pull request ([11f377d](https://github.com/akira-foundation/unified-dev/commit/11f377d65cc9727cfc500db33660c09890c98704))
- **billing:** Wire akira-billing SDK and skeleton client ([4726c87](https://github.com/akira-foundation/unified-dev/commit/4726c87d7e3819dafac3b6e56e031fd0d74caf68))
- **billing:** Swap OTP login onto akira-billing SDK ([ed0722d](https://github.com/akira-foundation/unified-dev/commit/ed0722d9377b7515180c7b89bc3299cd95e10277))
- **billing:** Activate license via SDK with ed25519 verification ([2248ecc](https://github.com/akira-foundation/unified-dev/commit/2248ecc95dfbfb6e241b6f3b411d216cd29abdc2))
- **client:** Server-driven usage limits, history, ui polish ([9c025ba](https://github.com/akira-foundation/unified-dev/commit/9c025ba2ec44a575cb2c69a76a133a396c732d90))
- **auth:** Customer oauth login with lazy auth wall and logout ([56d8aaf](https://github.com/akira-foundation/unified-dev/commit/56d8aaf67a096f1957e18a29d661516b5845552c))
- **notifications:** In-app inbox, system notifications, dock badge ([de69fea](https://github.com/akira-foundation/unified-dev/commit/de69fea958883078d35b5894e89e22cd94b9588b))
- **plans:** Drive subscription plans from billing sdk ([9b5075e](https://github.com/akira-foundation/unified-dev/commit/9b5075ee2a9e33d62b616fedbc5dbbc02f5aa3bd))
- **auth:** Dynamic oauth providers + polished onboarding flow ([0be1d67](https://github.com/akira-foundation/unified-dev/commit/0be1d6715ba7da81b3dc08c0cdddae60020dc6d4))
- **notifications:** Action handlers + clickable rows ([f05577f](https://github.com/akira-foundation/unified-dev/commit/f05577fa8f644cdac560fb1603f4418a57ce3c7e))
- **github:** Store OAuth user token on connect for OSS contribution sync ([8737543](https://github.com/akira-foundation/unified-dev/commit/873754376d741601987d12c3414c8ac40ae54261))
- **ui:** User menu in sidebar footer ([9a59944](https://github.com/akira-foundation/unified-dev/commit/9a599442e6252adc7ab0f6f3041e25c2f7245554))
- **autostart:** Launch at login backed by tauri-plugin-autostart ([68e0f92](https://github.com/akira-foundation/unified-dev/commit/68e0f92fd7c0b11ad3488fe61f815da3ac54c24a))
- **open-source:** Toast immediately when sync starts ([ae1085b](https://github.com/akira-foundation/unified-dev/commit/ae1085bc58c2d07478d2feb64405b3859485cf3c))


### Other

- **tauri:** Bump tauri to 2.11.1 (GHSA-7gmj-67g7-phm9) ([a823be8](https://github.com/akira-foundation/unified-dev/commit/a823be8ad536a9b6f39b0425b36637028ed4e565))

## [0.9.0](https://github.com/akira-foundation/unified-dev/compare/v0.8.0...v0.9.0) (2026-05-11)

### Code Refactoring

- **sidebar:** Extract BaseSidebar with shared header and footer ([899d460](https://github.com/akira-foundation/unified-dev/commit/899d4602156c22f19fb10e2eabfb86c15197d1b5))
- **graphql:** Remove unused fields and methods from client and graphql modules ([ddca5fa](https://github.com/akira-foundation/unified-dev/commit/ddca5fa47bc43a9e5fd2cee0a23d9d224cb8d07d))


### Features

- **open-source:** Add Open Source Contributions module ([cf2fac8](https://github.com/akira-foundation/unified-dev/commit/cf2fac82f76e0186c244a05950883d0d9abadcd0))
- **open-source:** Real GitHub GraphQL sync ([e141af3](https://github.com/akira-foundation/unified-dev/commit/e141af3a06b6c55748d75a3098a6e3f87f40e005))
- **open-source:** UI refactor with contribution panel ([20538c2](https://github.com/akira-foundation/unified-dev/commit/20538c2211a85e62f16561849bbd2f1c9eb949dd))
- **window:** Integrate native macOS title bar into sidebar island ([67eb44b](https://github.com/akira-foundation/unified-dev/commit/67eb44b3897163c6b09226f47486a1204de473fc))
- **sidebar:** Redesign sidebars in floating Tahoe-island style ([a23aa1e](https://github.com/akira-foundation/unified-dev/commit/a23aa1ec37d7bd88bd755046a139758bcd920d3a))
- **pr:** Add AI task resolution and new task dialog for pull requests ([9927d82](https://github.com/akira-foundation/unified-dev/commit/9927d82a66d827e7b32f309592b239d4c1c89e6b))


### Other

- Extend OSS contribution schema ([247beed](https://github.com/akira-foundation/unified-dev/commit/247beed7e2531f12d63baec6e7f4968dd51d1018))

## [0.8.0](https://github.com/akira-foundation/unified-dev/compare/v0.7.0...v0.8.0) (2026-05-04)

### Bug Fixes

- **deps:** Upgrade rand to 0.9 to resolve unsoundness with custom logger using rand-rng ([aca2dfa](https://github.com/akira-foundation/unified-dev/commit/aca2dfa4ac96ce4ff8305b0504f7205f6281b6c0))
- **pr-review:** Default to checks tab and auto-expand targeted/single check ([0f49fe8](https://github.com/akira-foundation/unified-dev/commit/0f49fe8b143962410420074c205f4f20fe4238f4))
- **pr-detail-sheet:** Expand comments section by default when present ([ee68463](https://github.com/akira-foundation/unified-dev/commit/ee68463fc90d21ef309c69dc5c89f127e8189952))


### Features

- **repository:** Enhance pull request synchronization and query invalidation ([9416048](https://github.com/akira-foundation/unified-dev/commit/9416048cef430b947d2e47a3ddbbb15f42d25585))
- **provider:** Include upstream status in provider resolution and improve error handling ([df26d7b](https://github.com/akira-foundation/unified-dev/commit/df26d7b0d1ab2eae4bd0eef4aa762db1c0bb70cd))
- **pr-detail:** Improve merge handling with loading state and toast notifications ([618cf69](https://github.com/akira-foundation/unified-dev/commit/618cf69452d245f807446766519874a138430692))
- **merge:** Update merge function to use effective repo name and log merge timestamps ([0e9a239](https://github.com/akira-foundation/unified-dev/commit/0e9a2397de8546a38633da474e318f154a47f646))
- **autopilot:** Implement feature check for autopilot and update free run limits ([818aa97](https://github.com/akira-foundation/unified-dev/commit/818aa9774f84bc0bd27c3902b0bd1ee41e5289d1))
- **profile:** Add get and set functions for user profile management ([3cff3b8](https://github.com/akira-foundation/unified-dev/commit/3cff3b8f77f2467de7eb27465ae57c89084cf816))
- **oauth:** Implement PKCE support with code verifier and challenge in OAuth flow ([99f0aaa](https://github.com/akira-foundation/unified-dev/commit/99f0aaab72bdbc08b58a1fcf3c0c265b31eecba1))
- **pr-ci:** Add CI checks integration with PR status display and polling ([f856cb1](https://github.com/akira-foundation/unified-dev/commit/f856cb16b0f11bbbc2259f16be22b43a5c834807))
- **pr-merged-banner:** Add banner for merged PRs with removal option ([27a0b19](https://github.com/akira-foundation/unified-dev/commit/27a0b1907ae3c35b081243262aa8e79d558d22e0))
- **headers:** Improve layout and styling of agent and app headers ([3d502ab](https://github.com/akira-foundation/unified-dev/commit/3d502abf46f51ea6cbd2bdf0310e92930067692b))
- **prompt:** Tighten turn scope and issue status transition rules ([068fe5a](https://github.com/akira-foundation/unified-dev/commit/068fe5a2d0df76dc0b07a52299412f4c50d70fbb))
- **delegate:** Prefix thread title with issue identifier ([94a1dd9](https://github.com/akira-foundation/unified-dev/commit/94a1dd94a35de1974bb64475add0fec87a88726c))
- **pr-review:** Add backend cmd to resolve thread PR review context ([65d1f63](https://github.com/akira-foundation/unified-dev/commit/65d1f63a7baee42ef7284ee116c31973c421a84c))
- **agent-header:** Add PR sheet, merge button, in-app CI navigation ([dbe7d49](https://github.com/akira-foundation/unified-dev/commit/dbe7d49976f7dc1b5ff2fa636a55387ab9974528))

## [0.7.0](https://github.com/akira-foundation/unified-dev/compare/v0.6.0...v0.7.0) (2026-04-21)

### Bug Fixes

- **repos:** Use LEFT JOIN so repos without a provider appear in global list ([227b28d](https://github.com/akira-foundation/unified-dev/commit/227b28df6b9d503882f876c24527545211bd3543))
- Resolve private repo clone auth, dropdown closing, and git PATH issues ([943bb03](https://github.com/akira-foundation/unified-dev/commit/943bb03db1066e9c3c8fe2e2f9868f576bd09494))
- **model-picker:** Use Popover + Command for proper scroll with available height ([8819e02](https://github.com/akira-foundation/unified-dev/commit/8819e0293fac4fc33e05ef1bd896b2d98d263555))


### Code Refactoring

- Simplify code by using `strip_prefix` and `then_some` for better readability ([8994176](https://github.com/akira-foundation/unified-dev/commit/8994176c9af268b31a639a348d8d833f1ef75100))


### Features

- **settings:** Add "Coming Soon" indicator for various settings items ([230c007](https://github.com/akira-foundation/unified-dev/commit/230c007ed649224ed46a941b2546318a8817308f))
- **providers:** Expose auth_type in ProviderSummary and add reconnect GitHub ([2c3785f](https://github.com/akira-foundation/unified-dev/commit/2c3785f291b8ef4b6bfae79313f052d2e23907dd))
- **repos:** Add create and delete GitHub repository ([294409b](https://github.com/akira-foundation/unified-dev/commit/294409b453e6186907145c49e88ac58ec2b79a0d))
- **i18n:** Add EN/PT translations for create repo, delete remote, and reconnect GitHub ([9646eee](https://github.com/akira-foundation/unified-dev/commit/9646eee35943f1005fc8f5499edb8f6b14f00eae))
- **autopilot:** Persist jobs and align management flows ([e939ead](https://github.com/akira-foundation/unified-dev/commit/e939ead99211ea1741ef6d64a8c47267ed372887))
- **autopilot:** Enhance thread management with removal functionality and status updates ([65ddf87](https://github.com/akira-foundation/unified-dev/commit/65ddf87ec32548c9235c9b7c12efdc7f5e5f011f))
- **graphql:** Improve error handling for GitHub GraphQL responses ([e56b396](https://github.com/akira-foundation/unified-dev/commit/e56b3965ae136e0c6e6ec4ba0fa4e7c72e92cc2f))

## [0.6.0](https://github.com/akira-foundation/unified-dev/compare/v0.5.0...v0.6.0) (2026-04-17)

### Code Refactoring

- **types:** Remove unused RegisterLicenseRequest struct ([aa2210b](https://github.com/akira-foundation/unified-dev/commit/aa2210bdca60dcf9943f943bb88676a31e725b68))


### Features

- **checkout:** Update checkout process to return CheckoutDto and implement polling for session activation ([dc65b39](https://github.com/akira-foundation/unified-dev/commit/dc65b3928833db183e815592a8f8089394b10e20))
- **subscription:** Implement subscription management and billing portal integration ([9462ed3](https://github.com/akira-foundation/unified-dev/commit/9462ed37dfaf28f0343b0703dfeda5db25b2d064))
- **profile:** Add user profile management with email verification and license claiming ([cfed98f](https://github.com/akira-foundation/unified-dev/commit/cfed98ff20a539e294dd20b1861fb6e531c94e5d))
- **billing:** Implement plan downgrade with Stripe schedule and local persistence ([0d00d4a](https://github.com/akira-foundation/unified-dev/commit/0d00d4afdc355b6e20e696f6bec1c9ca8c77f6d0))
- **gemini:** Add Gemini CLI integration and update notification handling ([3a9b928](https://github.com/akira-foundation/unified-dev/commit/3a9b92868d580bb34b70be2dde071e1f240a2f96))
- **billing:** Add invoice listing functionality and update related components ([fd8b224](https://github.com/akira-foundation/unified-dev/commit/fd8b224d2f784895ea1955caef3e1111fba09525))
- **subscription:** Enhance subscription tab with upcoming plan button and update license verification logic ([5a6279e](https://github.com/akira-foundation/unified-dev/commit/5a6279eeae6c4dcc97e65bad919e4285f855055c))

## [0.5.0](https://github.com/akira-foundation/unified-dev/compare/v0.4.3...v0.5.0) (2026-04-10)

### Bug Fixes

- **settings:** Update upgrade plan prices for pro and ultimate tiers ([d01fa57](https://github.com/akira-foundation/unified-dev/commit/d01fa57ac844440cd9da1c24c364abd8580173eb))
- **terminal:** Improve terminal resizing and add environment variables for color support ([7477985](https://github.com/akira-foundation/unified-dev/commit/7477985a62a1ec5c759ca705ca8c99bc3dad9fe7))
- **security:** Patch 50 dependabot CVEs across npm and Rust dependencies ([3bdaad2](https://github.com/akira-foundation/unified-dev/commit/3bdaad2187e1270493f3986fd31af413b26073f1))


### Code Refactoring

- **settings:** Extract SettingsSection and SettingsItem components for reuse ([e3e7e51](https://github.com/akira-foundation/unified-dev/commit/e3e7e51a277579876e4ea8eba7cec71dec21db05))
- **agents-sidebar:** Remove unused navigation functions and update dependencies ([b34f0bd](https://github.com/akira-foundation/unified-dev/commit/b34f0bdb04bb2d7f82f8d3c35a7ea39d8eaa40e4))


### Features

- **license:** Implement HMAC signature verification for license activation ([9dacc68](https://github.com/akira-foundation/unified-dev/commit/9dacc68c05dc5bf19dac17ef2cc2d04bc51310d2))
- **settings:** Add remote settings tab navigation and state management ([3e89481](https://github.com/akira-foundation/unified-dev/commit/3e89481f0920dc4f4cd68e27ed430f193ef92ebe))
- **issues:** Add search functionality to issue table ([55e224a](https://github.com/akira-foundation/unified-dev/commit/55e224a9ac487f4e8bd99dd1ace1b2a19bfeee1a))
- **agenda:** Enhance agenda view with organization sync history and weekly summary ([073aaab](https://github.com/akira-foundation/unified-dev/commit/073aaab4aeef42ce0038c8c8ba705132ef90e247))
- **organizations:** Add manual sync functionality and update sync settings ([3e33c5c](https://github.com/akira-foundation/unified-dev/commit/3e33c5c08df12879174b2703767855387e6e1d08))
- **sync:** Enhance sync functions to update organization settings after sync ([3510d97](https://github.com/akira-foundation/unified-dev/commit/3510d97b098a5d972c236b5e967168b65c9ee068))
- **agents:** Add search functionality to agents sidebar with clear filters option ([6eed33e](https://github.com/akira-foundation/unified-dev/commit/6eed33ebb0339283c4cbb5c1641735359da06309))
- **skills:** Update skill directory handling and enhance filtering logic ([d1c09e4](https://github.com/akira-foundation/unified-dev/commit/d1c09e435566885e554d9f6baf0add22ab24e92c))
- **skill-source:** Add skill source page and integrate remote skill fetching ([e90f0a4](https://github.com/akira-foundation/unified-dev/commit/e90f0a4536b48ad7049b29b0249423e555a6549b))
- **onboarding:** Add onboarding overlay and dependency check functionality ([61576c6](https://github.com/akira-foundation/unified-dev/commit/61576c63cb6fcad8950ee7d9d2498f5ee2555b86))
- **plans:** Sync plan features with landing page (kanban, PR review, support tiers) ([0799283](https://github.com/akira-foundation/unified-dev/commit/079928364b24f8a51183bf9f63237a4527e9f496))
- **plans:** Add repos (3) and org (1) limits to free tier plan display ([8ff0cda](https://github.com/akira-foundation/unified-dev/commit/8ff0cda70a0f20a4fb3194d747a4de1e5abd8ec5))
- **billing:** Add free tier enforcement and usage tracking ([e2f3947](https://github.com/akira-foundation/unified-dev/commit/e2f3947d89fda6b3bd2aa122cd9dae6510eb1f7e))

## [0.4.3](https://github.com/akira-foundation/unified-dev/compare/v0.4.2...v0.4.3) (2026-04-07)

### Bug Fixes

- **ci:** Update build workflow to trigger on main branch and improve error handling for macOS tarballs ([644f5a3](https://github.com/akira-foundation/unified-dev/commit/644f5a39c869d5420a5a8852d21bd24d8de7ec2a))
- Update bundle targets in tauri configuration ([701e296](https://github.com/akira-foundation/unified-dev/commit/701e296af949ce98fb32155dd18c57d6f6eb9a0c))
- **ci:** Update DMG upload step to trigger on tag references and refactor latest.json generation ([4e6be96](https://github.com/akira-foundation/unified-dev/commit/4e6be96f97deb2011058db16a54c3cea20eb60e6))
- **ci:** Replace Python script with jq for generating latest.json ([93b600d](https://github.com/akira-foundation/unified-dev/commit/93b600d7c05a23fad02ce2c5dadfafea4177c203))
- **config:** Update tauri configuration to remove updater target and enable updater artifacts ([6ff3d1d](https://github.com/akira-foundation/unified-dev/commit/6ff3d1d20a65d6e96fb5b8836d7672b4dd8f3e9e))
- **config:** Update public key in tauri configuration ([513c2ad](https://github.com/akira-foundation/unified-dev/commit/513c2adfa032b36a7bb0ab3365d61c97c01f6c50))

## [0.4.2](https://github.com/akira-foundation/unified-dev/compare/v0.4.1...v0.4.2) (2026-04-07)

### Bug Fixes

- **ci:** Refactor build workflow to separate aarch64 and x86_64 jobs and improve artifact handling ([fd70d85](https://github.com/akira-foundation/unified-dev/commit/fd70d85004002f750bfee92dced4fbdad49a90f1))

## [0.4.1](https://github.com/akira-foundation/unified-dev/compare/v0.4.0...v0.4.1) (2026-04-07)

### Bug Fixes

- **build:** Improve artifact handling by dynamically locating macOS tarballs ([8df6e4e](https://github.com/akira-foundation/unified-dev/commit/8df6e4ee1ee3f3e25c9dccfa4bc712d05d9ad34c))

## [0.4.0](https://github.com/akira-foundation/unified-dev/compare/v0.3.0...v0.4.0) (2026-04-07)

### Bug Fixes

- **copilot:** Resolve 400 and 413 errors on multi-turn conversations ([8d6852b](https://github.com/akira-foundation/unified-dev/commit/8d6852b98c5cf00258b5d7a059e88151a886ee5d))
- **agent:** Prevent proactive MCP tool calls and fix streaming indicator ([05b32f7](https://github.com/akira-foundation/unified-dev/commit/05b32f70387ce93930f9c08405cc001842e63dde))


### Code Refactoring

- **styles:** Remove unused font import and clean up CSS ([c4f5c69](https://github.com/akira-foundation/unified-dev/commit/c4f5c690ef9f8b1b7686f0c405cdd857a7761e7e))


### Features

- **copilot:** Add Claude models and remove cross-provider fallbacks ([5e1d880](https://github.com/akira-foundation/unified-dev/commit/5e1d8806b79ece59135ebdd523eded5b2a711952))
- **chat:** Add image support across all providers and frontend ([b02ca7c](https://github.com/akira-foundation/unified-dev/commit/b02ca7c6c801857afcde2cef2bf1fae28267a57a))
- **repository:** Add repository removal functionality with confirmation dialog ([d6a951b](https://github.com/akira-foundation/unified-dev/commit/d6a951bcab89084cea3e821489ff5ff9cc1a15b7))
- **chat:** Skip history messages with images when current message contains an image ([7b3146f](https://github.com/akira-foundation/unified-dev/commit/7b3146fb413ed25e377807119e6c84b6faba0673))
- **agent:** Display dynamic tool call count in status bar ([580d830](https://github.com/akira-foundation/unified-dev/commit/580d830fb4c6bc0671fbb4c82590f29bdc5e9818))
- **repository:** Add repository settings management with display name and model configuration ([3bf3466](https://github.com/akira-foundation/unified-dev/commit/3bf34667274a244dd3f8fa0338baaea4d1899ac6))
- **repository:** Add default merge action configuration to repository settings ([45f88ab](https://github.com/akira-foundation/unified-dev/commit/45f88ab42ff7fb4aa71dd90d267c6fe6076654b8))
- **build:** Support building for multiple macOS architectures and update artifact handling ([f6d5fda](https://github.com/akira-foundation/unified-dev/commit/f6d5fdaa13f2b7060282fa16fd0e2b6c3a4b6a21))
- **agent:** Enhance message handling with loading states and thread-specific storage ([8af775b](https://github.com/akira-foundation/unified-dev/commit/8af775b1478c2c404dcae156ca30e7357b3f1a00))

## [0.3.0](https://github.com/akira-foundation/unified-dev/compare/v0.2.1...v0.3.0) (2026-04-06)

### Features

- **updater:** Implement auto-update with tauri-plugin-updater and update UI in AppHeader ([822a4cb](https://github.com/akira-foundation/unified-dev/commit/822a4cba108afe1e7d11a45d6e1865ed7dc33ec6))

## [0.2.1](https://github.com/akira-foundation/unified-dev/compare/v0.2.0...v0.2.1) (2026-04-06)

### Bug Fixes

- **ci:** Add contents write permission for GitHub release upload ([004f113](https://github.com/akira-foundation/unified-dev/commit/004f113ae935b95f9327a9d35cab1158530154c3))

## [0.2.0](https://github.com/akira-foundation/unified-dev/compare/v0.1.0...v0.2.0) (2026-04-06)

### Bug Fixes

- **zod:** Resolve version mismatch errors in form resolvers and update zod dependency ([574b19d](https://github.com/akira-foundation/unified-dev/commit/574b19d1630593c6e4d18380ae78d73ceaa3b4e3))
- **ci:** Add APPLE_SIGNING_IDENTITY, comment Linux/Windows in test-build, use pnpm ([751ac9f](https://github.com/akira-foundation/unified-dev/commit/751ac9ff98c1a0144861fb166e67daac7b79af71))
- **ci:** Use pnpm run lint with fallback instead of --if-present flag ([82bf76c](https://github.com/akira-foundation/unified-dev/commit/82bf76c65e5f45a7bebbde153899ae7ce43529df))
- **ci:** Fix codesign keychain search path and suppress Rust dead_code warnings ([e71d493](https://github.com/akira-foundation/unified-dev/commit/e71d4930d85fee1037ee2ddf32e74f94374fc326))
- **rust:** Move debug-only imports under cfg(debug_assertions) in key_store ([2dec1eb](https://github.com/akira-foundation/unified-dev/commit/2dec1eb5c1973f2aa5d69fe1dd17e7f97c1a2c0a))


### Features

- **ci:** Add AKIRA_API_URL and GITHUB_CLIENT_ID to build environment variables ([0e9551b](https://github.com/akira-foundation/unified-dev/commit/0e9551b9a282e9b6663177c3faeae18851fb7abc))

## [0.1.0](https://github.com/akira-foundation/unified-dev/compare/...v0.1.0) (2026-04-06)

### Bug Fixes

- Resolve syntax error with escaped backticks in template strings ([7503796](https://github.com/akira-foundation/unified-dev/commit/750379699812b6dd4f1b5872f86d8cfc762eaa13))
- Change skills description to refer to Unified Dev instead of Codex ([f88738d](https://github.com/akira-foundation/unified-dev/commit/f88738dbec183b7f1d3eb4101d4a7490235fb391))
- **ui:** Wire up dashboard actions, organization navigation, and theme settings ([fb1eec0](https://github.com/akira-foundation/unified-dev/commit/fb1eec004a2f70dc4d80f73b9357d95082677800))
- **ui:** Correct light mode across agent workspace and pages ([5b4ede4](https://github.com/akira-foundation/unified-dev/commit/5b4ede4a6a6afd28bff64cf5483361f14eafd7d4))
- **ui:** Improve PR checks log parsing and review page layout ([501e8ac](https://github.com/akira-foundation/unified-dev/commit/501e8ac121e6b57429448e79eed62e433bcba674))
- **ui:** Persist viewed files state and improve patch viewer styling ([c99fec3](https://github.com/akira-foundation/unified-dev/commit/c99fec3f641048240b8276a711314b037a7431c1))


### Code Refactoring

- Streamline UI by removing icons from settings sections and reorganizing sidebar navigation. ([c12bbbd](https://github.com/akira-foundation/unified-dev/commit/c12bbbd93b6c4d3002e1b09a28ac21c4e22f66c6))
- Wrap agent chat input with Card and CardContent components for improved styling and structure. ([9a7b696](https://github.com/akira-foundation/unified-dev/commit/9a7b696e3b6350df6f3d1a672ac06a5a4d8a72ff))
- Adjust agent chat input padding and positioning, and shift timeline vertical line. ([c619abb](https://github.com/akira-foundation/unified-dev/commit/c619abb137912d59784805babd78d66cfdf3e90b))
- **ui:** Apply global cache configuration and refine table styles ([888edb2](https://github.com/akira-foundation/unified-dev/commit/888edb22e38052c34613b4a8185b50ada498106a))
- Remove outdated comments for clarity and maintainability ([c30efd2](https://github.com/akira-foundation/unified-dev/commit/c30efd2ab493f5a481140155f81d5adce27929a7))
- Remove dead config/ module superseded by db/ and services/ ([82422a1](https://github.com/akira-foundation/unified-dev/commit/82422a18ba8fc0cf4ac0e3bbbe4d9f4fc142135d))
- Remove outdated comments and unused module for improved clarity ([cbb0417](https://github.com/akira-foundation/unified-dev/commit/cbb0417d2af89bf13977b9e0853c9df399eca9b8))
- Update module paths to use shared provider traits and types ([4857302](https://github.com/akira-foundation/unified-dev/commit/4857302d29d7904e4e9827c1864a02ac7e29b4de))
- **workspace:** Migrate repository utilities to workspaces module for better organization ([db7ee2a](https://github.com/akira-foundation/unified-dev/commit/db7ee2ae75b11f1fc59e2ebfe4a2b0b5137fb841))
- **db:** Reorganize database module structure and move input types to a new inputs module ([a405d1e](https://github.com/akira-foundation/unified-dev/commit/a405d1e10cf53a05a31364d627c3a1bd08477aed))
- **db:** Update module paths to reflect new organization and provider structure ([a518351](https://github.com/akira-foundation/unified-dev/commit/a518351d64f8043f46ba211a80ec31e5f8feab85))
- Clean up unused functions and comments, and reorganize thread management logic ([77cac17](https://github.com/akira-foundation/unified-dev/commit/77cac17b0c46e019fa1629a856c09dcb291d96ac))
- Rename repoKey to repoName and update related logic in CreateIssueDialog ([772a85a](https://github.com/akira-foundation/unified-dev/commit/772a85aa15ee1cb7b74f7b62c63493582cb458cb))
- Enhance CreateIssueDialog with labels and assignees management ([e6bed59](https://github.com/akira-foundation/unified-dev/commit/e6bed59c6fdb2ebd6f61e1fefc361e23e89398e8))
- **database:** Rename models module to records and update references ([56c34ba](https://github.com/akira-foundation/unified-dev/commit/56c34ba58cf634f858abf658c120154501061591))
- **database:** Replace repository abstractions with direct SQL queries ([65daa1a](https://github.com/akira-foundation/unified-dev/commit/65daa1aa6d9719853ad302042d817b46cba886fc))


### Features

- Rename project to Unified Dev and implement organization management features ([8d09cd5](https://github.com/akira-foundation/unified-dev/commit/8d09cd53d103b25bbddf2c7c34180c2c22285221))
- Add initial components and types for organization management ([bae1abb](https://github.com/akira-foundation/unified-dev/commit/bae1abb60780da79c38e22ba3a4cf2e08694fee0))
- Integrate internationalization and enhance settings management ([f6dfd20](https://github.com/akira-foundation/unified-dev/commit/f6dfd204a627e81ab7adf885ae8b7d1f8f0367be))
- Enhance layout with header and notification components ([be81900](https://github.com/akira-foundation/unified-dev/commit/be819008c2e82299ca73705b91ff9145219907fa))
- Enhance dashboard layout and improve component styling ([8fd03fd](https://github.com/akira-foundation/unified-dev/commit/8fd03fd8287251d37d338b7475038c9f910f7bef))
- Update dashboard and organization components with improved styling and new button integration ([6dd304a](https://github.com/akira-foundation/unified-dev/commit/6dd304a35f2b066fabdb1d6ff9ee5235ae835921))
- Update upgrade modal and translations for new pricing plans and descriptions ([ffec3cc](https://github.com/akira-foundation/unified-dev/commit/ffec3cc33115ee4520aed30fc2ace2fbab5bcd10))
- Implement GitHub and Bitbucket VCS providers with repository and pull request synchronization ([3a7fc24](https://github.com/akira-foundation/unified-dev/commit/3a7fc240f2816c921d7362c15feca3e1b3351241))
- Refactor organization handling to use provider authentication and update database schema ([8626491](https://github.com/akira-foundation/unified-dev/commit/86264918a20342d1e39ec68c1918ec5552e01f43))
- Add organization repository selection page with repository visibility and selection features ([5929877](https://github.com/akira-foundation/unified-dev/commit/5929877a1ffc85cbe91c2e1001f1c93a9573c8a6))
- Implement provider management with CRUD operations and UI integration ([20d1120](https://github.com/akira-foundation/unified-dev/commit/20d11206b8102889fbcec57f871fc6c9e3c88f85))
- Enhance settings page with improved card structure and descriptions ([504decc](https://github.com/akira-foundation/unified-dev/commit/504decc50244cb07243b7e0a8d05e3911cb96b4f))
- Update dashboard layout with improved card structure and localization support ([a2487ed](https://github.com/akira-foundation/unified-dev/commit/a2487ede5edd1bb90db09a504068989b446531b3))
- Enhance team view with improved card structure, updated member display, and refined styling ([a59f5af](https://github.com/akira-foundation/unified-dev/commit/a59f5af1c137b9137cf84ad1127af2f55307af1c))
- Improve agent workspace UI and refactor provider/organization services ([52b59fa](https://github.com/akira-foundation/unified-dev/commit/52b59fa8cbe4d7e4b32db109a3631a5a13aa2a8a))
- Restructure settings UI and add precise prompt configurations ([7095e2a](https://github.com/akira-foundation/unified-dev/commit/7095e2a7b9c6cfe182da143847e7541b8275fa98))
- Revert settings to standard card UI and integrate developer configurations ([bbb3005](https://github.com/akira-foundation/unified-dev/commit/bbb30057b0f2c8a84cdcd6b3dde0c14aa5c53515))
- Implement sidebar navigation in settings with card UI content ([e80116c](https://github.com/akira-foundation/unified-dev/commit/e80116cf0db8d4874c36647200d22deddbf07382))
- Add a new Radix UI-based Switch component and update settings page tab styling. ([6d706c4](https://github.com/akira-foundation/unified-dev/commit/6d706c4dd9fc1c2b1cc3fed4f0ad0e04d5c930ae))
- Complete settings sidebar and modular card architecture ([412f150](https://github.com/akira-foundation/unified-dev/commit/412f15081fd99caa8840f512d7ffd1514f5fba0a))
- Add missing IDE and terminal options to settings ([55d6ef0](https://github.com/akira-foundation/unified-dev/commit/55d6ef039c02a1ac08af341a89e60afab410d44e))
- Use matching workspace branding header inside agents sidebar ([346df91](https://github.com/akira-foundation/unified-dev/commit/346df9168c49f460e58819274fcc5ee2f4ef3656))
- Use explicit back arrow instead of workspace logo in agents sidebar ([ed9273e](https://github.com/akira-foundation/unified-dev/commit/ed9273e585040a34aa3e9b85693d5b242bae8703))
- Change workspace subtitle to agents in agents sidebar ([c4d5346](https://github.com/akira-foundation/unified-dev/commit/c4d5346472a7f36b13f0ea28fe6303c346a78c1a))
- Implement initial skills page layout matching design ([5852dac](https://github.com/akira-foundation/unified-dev/commit/5852dacce902f8e12efe262d017967338bc9c7a3))
- Make skills switches interactive and use primary color ([83b6dde](https://github.com/akira-foundation/unified-dev/commit/83b6ddea85342da2ab0fb2821088df3743cea96d))
- Integrate the Skills page as a tab within the agent workspace, managed by a new `activeTab` state. ([ca9245f](https://github.com/akira-foundation/unified-dev/commit/ca9245f3c3442ee6b682be90761e07f08f31a8d5))
- Implement create automation page and refine UI for automations, providers, and skills sections. ([5d43d20](https://github.com/akira-foundation/unified-dev/commit/5d43d20e2d806b567f53ba6cdb0aa2743277d02d))
- Introduce skill details page with navigation and standardize UI component rounding. ([ad46922](https://github.com/akira-foundation/unified-dev/commit/ad469227fbd0ff4df2e3ac6458c25724f2f1a226))
- Implement automation configuration flow by introducing `selectedAutomation` state and updating UI elements to pre-fill automation details. ([570ba06](https://github.com/akira-foundation/unified-dev/commit/570ba06884398fe25225191a8de90c297cd459a9))
- Implement AI provider detection, model registry, and selection UI for agent interactions. ([ca655bf](https://github.com/akira-foundation/unified-dev/commit/ca655bfa643580403068a950ebe5df0fc5066f31))
- Add shell configuration file scanning for AI provider API keys and simplify config directory detection logic. ([f97afc9](https://github.com/akira-foundation/unified-dev/commit/f97afc93f122418f92b77cccb4a352edd22d9d80))
- Enhance model selection UI with Popover and Command components and add Copilot AI provider detection. ([89c99ea](https://github.com/akira-foundation/unified-dev/commit/89c99ea9bcf4c49e18257577d6f9981db3d9001c))
- Implement integrated terminal panel with PTY support ([9788620](https://github.com/akira-foundation/unified-dev/commit/9788620e18a08292e7a0a55bf462f2da12fb73aa))
- Implement multi-tab functionality in the terminal panel, allowing users to spawn, close, switch, and rename terminal sessions, and add an `onClose` prop to notify the parent when all terminals are closed. ([3d4487e](https://github.com/akira-foundation/unified-dev/commit/3d4487e39d3fcc7542fc65a5bca46dfd84a965aa))
- Dynamically render and enable selection of actions in the agent header dropdown menu. ([b2c8665](https://github.com/akira-foundation/unified-dev/commit/b2c86656ad7be6bd321f9a3e22f379d9e49753b4))
- Group settings navigation tabs into logical categories for improved organization. ([034ca8a](https://github.com/akira-foundation/unified-dev/commit/034ca8aae1858e2797164cfdfa87d1b80713f969))
- Add icons and refine styling for settings sections ([a5bb26c](https://github.com/akira-foundation/unified-dev/commit/a5bb26c34a42239b26cda9799f5ab7f01e2fd083))
- Standardize card headers with new icon-driven design and updated styling across various pages and components ([bbc1e49](https://github.com/akira-foundation/unified-dev/commit/bbc1e49a9f31cfd48c7192030cdbb6fed0433364))
- Update sidebar button text from 'New thread' to 'Add new repository' and add a tooltip to the 'Add new thread' button. ([9b1ef52](https://github.com/akira-foundation/unified-dev/commit/9b1ef52c4dca4a3d4c2a8c1d7593fb2dfc35c9e1))
- **repos:** Implement add repository dialog with native folder selection ([ed247e0](https://github.com/akira-foundation/unified-dev/commit/ed247e04e461e11c99b8677fc27116c6642b3e81))
- **repos:** Connect sidebar and dialog to tauri backend ([e2f1c1f](https://github.com/akira-foundation/unified-dev/commit/e2f1c1fdab8497988a0d5ed937b9625628d26f7e))
- **repos:** Implement thread management and repository listing ([32c6705](https://github.com/akira-foundation/unified-dev/commit/32c67057f4cdb27641d98e56263be923b661cdd0))
- **agents:** Implement thread removal in agent header ([8610216](https://github.com/akira-foundation/unified-dev/commit/86102165d8ee0d1dfc78a2ee329988c184d7aa30))
- Implement file system browsing and editing within the agent interface by adding Tauri commands for file system interaction and updating the UI to display and edit workspace files. ([089e96d](https://github.com/akira-foundation/unified-dev/commit/089e96d1decb11de88f8cf5e31fb60a3f4322f26))
- **editor:** Integrate syntax highlighter and theme selection ([6f6b6a3](https://github.com/akira-foundation/unified-dev/commit/6f6b6a39dc7eb01d9f12d720a65af6495c867163))
- **agents:** Implement file search and command palette ([8fe36fb](https://github.com/akira-foundation/unified-dev/commit/8fe36fbe82afce9e1d8863c714e65cba917c7b40))
- **agents:** Implement real-time chat with message persistence and markdown support ([920e4e5](https://github.com/akira-foundation/unified-dev/commit/920e4e58684bfbe8995c5e7ded5c57c08ef8e7c4))
- **agents:** Implement slash commands menu in chat input ([5107841](https://github.com/akira-foundation/unified-dev/commit/510784108e169e379c9d2c0b7e2971bed6e7f56c))
- **agents:** Implement agentic tool use and execute local slash commands ([4a13ef7](https://github.com/akira-foundation/unified-dev/commit/4a13ef7acd801358a89a6687217d8df8bf3dd357))
- **agents:** Implement real-time git diff viewer and PR creation ([9fb2332](https://github.com/akira-foundation/unified-dev/commit/9fb2332e77a5f82f23a9343b9a0b6985b4f4ee3d))
- **agents:** Enhance diff viewer and workspace layout ([f01e1ad](https://github.com/akira-foundation/unified-dev/commit/f01e1ad2a1cad3c65a2a196fbeeb107384d94673))
- **agents:** Implement customizable action prompts and file discarding ([c371390](https://github.com/akira-foundation/unified-dev/commit/c37139011f64915fdab0ba8ef0a444ab738fd808))
- **agents:** Use strict system prompt for automated actions ([357cc78](https://github.com/akira-foundation/unified-dev/commit/357cc780ed778474126a50a49ea4faaf35b976ca))
- **db:** Add pr_url to threads table ([cbeaae4](https://github.com/akira-foundation/unified-dev/commit/cbeaae4910a9ce0e72ada2b447ab7fa0e592d27e))
- **skills:** Fetch installed skills dynamically from backend ([980820d](https://github.com/akira-foundation/unified-dev/commit/980820d72d5e42b0fe757907f954939b8d9d089b))
- **skills:** Implement skill installation and icon management ([be9134a](https://github.com/akira-foundation/unified-dev/commit/be9134af83d9e7b57633cc7bb0775d6a0ed68e4b))
- **providers:** Implement GitHub App auth, GitLab, and Bitbucket drivers ([adf2440](https://github.com/akira-foundation/unified-dev/commit/adf2440d597fa035e554c9c641ad2466eb47b552))
- **ui:** Relocate provider management to settings and add provider details page ([5505118](https://github.com/akira-foundation/unified-dev/commit/55051186724d2dfd3601239c4ac5d8f7c7b6bdd1))
- **providers:** Implement GitHub OAuth flow and UI empty states ([6cdb2d4](https://github.com/akira-foundation/unified-dev/commit/6cdb2d4657c271c71beb8b1b6600dbe424cec804))
- **i18n:** Internationalize UI components and pages ([e17e923](https://github.com/akira-foundation/unified-dev/commit/e17e923c6cf8056b617edec0321044b996f4d93c))
- **i18n:** Internationalize agent workspace, skills, and automations ([9820207](https://github.com/akira-foundation/unified-dev/commit/98202075471d275895bd4f4871bdccc886a8096e))
- **terminal:** Add minimize button, persist sessions, and resizable panel ([9b1b5ed](https://github.com/akira-foundation/unified-dev/commit/9b1b5edbe696c5f63d7449f2e7cf4b27e294bc2c))
- **repositories:** Implement adding repositories from remote clone URL ([b8481eb](https://github.com/akira-foundation/unified-dev/commit/b8481eb7bd00cbae6d329e0d18b9a5ca042ca509))
- **repositories:** Display all selected repositories globally on the repositories page ([53e2c66](https://github.com/akira-foundation/unified-dev/commit/53e2c6641f343037f3eda6b9d12af121775ae11a))
- **organizations:** Allow editing organizations and optionally keeping them on provider disconnect ([595a144](https://github.com/akira-foundation/unified-dev/commit/595a144c45303d7ee05ad02ff98275e84643887e))
- **repositories:** Implement PR stats syncing and task creation from repository table ([bc420e5](https://github.com/akira-foundation/unified-dev/commit/bc420e50b0e1396e87fa38fa604d9fce0fac3ace))
- **repositories:** Implement pull requests view for repositories ([3ef900a](https://github.com/akira-foundation/unified-dev/commit/3ef900a1d19c86767d70d38ef7580d7fcc332cf3))
- **repositories:** Implement pull request details, comments, and reviews ([2c76306](https://github.com/akira-foundation/unified-dev/commit/2c76306911de5955dd4e069be9fb96de63a9e6a3))
- **repositories:** Implement full PR review page with diff viewer ([d35c075](https://github.com/akira-foundation/unified-dev/commit/d35c075184771cb6d6324834671108712b6734fe))
- **ui:** Migrate data fetching to React Query and tables to TanStack Table ([ee2883c](https://github.com/akira-foundation/unified-dev/commit/ee2883cce9e9c23236fe684d789b5b11b50867a6))
- **repositories:** Implement PR checks view and CI logs parsing ([d117b94](https://github.com/akira-foundation/unified-dev/commit/d117b947c499c351978995d84a30ce1b590c1619))
- **ui:** Replace heavy diff viewer with lightweight custom patch viewer ([b3eed78](https://github.com/akira-foundation/unified-dev/commit/b3eed78ac8f1e7895db8e331ad521265efa9afa8))
- **ui:** Implement syntax highlighting in diff viewer ([6852646](https://github.com/akira-foundation/unified-dev/commit/6852646c4e5bc065c269496f924dc984d8634d18))
- **ui:** Integrate real data into dashboard stats and PR kanban board ([9d80360](https://github.com/akira-foundation/unified-dev/commit/9d80360245549266d71c88e0c64736d713b466cc))
- **issues:** Implement issue tracking, creation, and kanban board ([ec0cfc3](https://github.com/akira-foundation/unified-dev/commit/ec0cfc3ccefd36a3e19d277f69639dab06c7501c))
- **repositories:** Add repository statistics and manual PR sync to detail page ([7cbc39c](https://github.com/akira-foundation/unified-dev/commit/7cbc39c6825968c73336640a1ae46182655c9a46))
- **repositories:** Implement branch management and issue deletion ([b0b4c09](https://github.com/akira-foundation/unified-dev/commit/b0b4c09f693c4caa62945d44d210ac4e1d50fc6e))
- **ui:** Implement generic Combobox component and issue filtering ([e2b2089](https://github.com/akira-foundation/unified-dev/commit/e2b208990b92677854d8d32bba4e0818541cdffd))
- **ui:** Complete issue filtering UI and separate filter namespaces ([b62bdef](https://github.com/akira-foundation/unified-dev/commit/b62bdefd65c3769241c886009616071b97d0fd66))
- **prs:** Add filtering capabilities to PR list and enhance UI components ([2d04a96](https://github.com/akira-foundation/unified-dev/commit/2d04a966a4d8c623b2a06caa8d9397b2f78a946a))
- **drivers:** Implement GitHub, GitLab, and Bitbucket drivers with API integration ([74be34f](https://github.com/akira-foundation/unified-dev/commit/74be34f53694adac9c4e52503cde74d128ab8c38))
- **ai:** Refactor AI provider registry and implement OpenAI and Copilot providers ([67d676f](https://github.com/akira-foundation/unified-dev/commit/67d676f32fe8ffb99584ea1fa8d024c4cd03e3ef))
- **agents:** Implement AI provider detection and model registry caching ([b4011ca](https://github.com/akira-foundation/unified-dev/commit/b4011ca63b27c7a5a65da38d9a47adbb2a021388))
- **chat:** Refactor message handling and introduce session management ([b08ef10](https://github.com/akira-foundation/unified-dev/commit/b08ef10569c47f974789966f871aba065cc27d38))
- **modules:** Add new modules for OAuth, session management, file handling, and repository management ([8283fca](https://github.com/akira-foundation/unified-dev/commit/8283fca6d7a29a255df305c502b8b585965a44fe))
- **issue:** Add slash command functionality to issue creation with task management ([992bf07](https://github.com/akira-foundation/unified-dev/commit/992bf07b77b27255070a64c42499144ad6a97149))
- **slash-command:** Enhance slash command menu with grouping and shortcuts ([6eb6483](https://github.com/akira-foundation/unified-dev/commit/6eb6483a1f19384109cbeb2e0470f479503bd215))
- **issue:** Add 'Save as draft' and 'Create more' functionality in CreateIssueDialog ([df466e4](https://github.com/akira-foundation/unified-dev/commit/df466e440353068f8de3992dd706ce3aad074616))
- **issue:** Add sync with provider functionality and update translations ([82d0f4f](https://github.com/akira-foundation/unified-dev/commit/82d0f4f0549beef79a8ae8439f57fefef0b220e4))
- **filters:** Implement filter popover with multi-select and toggle options ([c6a5281](https://github.com/akira-foundation/unified-dev/commit/c6a5281c372a48335fb3f36b6ac8ee28fdf85233))
- **modules:** Add new modules for organization management and issue handling ([abf1f5d](https://github.com/akira-foundation/unified-dev/commit/abf1f5d1d54424f91a10863e3cb284c1056f323e))
- **repositories:** Refactor repository functions and add filesystem operations ([6d95855](https://github.com/akira-foundation/unified-dev/commit/6d95855f00fb62c2c58791e6ec8248ca86d35645))
- **mod:** Add new modules for organization and provider management ([f5f0b4b](https://github.com/akira-foundation/unified-dev/commit/f5f0b4b1fd02d6209f6d8ff3b4297931e7ff15bc))
- **issues:** Add sync_with_provider field and update issue handling logic ([fefe00d](https://github.com/akira-foundation/unified-dev/commit/fefe00dff885b36a2db7d7dbf5d5e5662e97e523))
- **sync:** Implement sync settings management and UI components ([ae5a819](https://github.com/akira-foundation/unified-dev/commit/ae5a819f4baf6b0edb672f58c9ddf3947bbaa016))
- **organizations:** Enhance organization data with selected repos count and last synced timestamp ([0db0744](https://github.com/akira-foundation/unified-dev/commit/0db0744e32fc53f4ae314418e33f568aa8f96cfa))
- **agent:** Add abort functionality for running agents and delegate issue handling ([8a6a35f](https://github.com/akira-foundation/unified-dev/commit/8a6a35f37e887db9bd6d28cc72ae1186a93cc174))
- **workspace:** Implement workspace renaming functionality and update related logic ([aedefb9](https://github.com/akira-foundation/unified-dev/commit/aedefb9f8383b142638e1d10dc08e6c10907c4fa))
- **agent:** Add context window and token usage calculation for AI models ([beb2bd3](https://github.com/akira-foundation/unified-dev/commit/beb2bd3803745f5f7880fac2af110e3584331a29))
- **agent:** Add plan mode, thinking budget, and fast mode options for message sending ([46c609e](https://github.com/akira-foundation/unified-dev/commit/46c609e9eca4c96de65ff3ebb36e81f030a5e1a8))
- **repository:** Add remote URL handling for local repositories and implement organization linking ([92d80f0](https://github.com/akira-foundation/unified-dev/commit/92d80f0f19840fa0a6143cc3de0b319a460e281e))
- **agent:** Add repository loading after adding a new thread ([b2050b8](https://github.com/akira-foundation/unified-dev/commit/b2050b8ed36e68dee93d7828de53b6b73ae80de1))
- **visibility:** Add visibility preferences management and update related logic ([b730852](https://github.com/akira-foundation/unified-dev/commit/b730852e630c23514e61eb1bb1de5b1ce01cb65a))
- **issue:** Enhance issue management with assign to me functionality and improved issue retrieval ([8257e12](https://github.com/akira-foundation/unified-dev/commit/8257e12f2aa92e21ed0276f041b22a416bc63a5b))
- **remote:** Implement remote access settings management and add related API endpoints ([c6b6fd3](https://github.com/akira-foundation/unified-dev/commit/c6b6fd36fcf4056cdcd4ccb98697d78e7bf65b71))
- **license:** Implement license management with activation, verification, and storage functionality ([dc29c91](https://github.com/akira-foundation/unified-dev/commit/dc29c91b220cf1303db5b1b4b2dca00d35fb2d9c))
- **deep-link:** Add tauri-plugin-deep-link dependency and update pricing plans ([e6df18f](https://github.com/akira-foundation/unified-dev/commit/e6df18f703fac4660f1481d1365a2d7c9741553f))
- **pr:** Enhance PR navigation by adding owner information and improving collapse logic ([716ed53](https://github.com/akira-foundation/unified-dev/commit/716ed5317117f62473a41f8b479fcf03565ecf38))
- **rate-limit:** Implement GitHub rate limit retrieval and display in VCS providers tab ([5666067](https://github.com/akira-foundation/unified-dev/commit/566606711af4521a511cedab0861500a4b009ea1))
- **pull-requests:** Enhance pull request management with database integration and additional fields ([0c6a9be](https://github.com/akira-foundation/unified-dev/commit/0c6a9bed5b91c1143193a6dfbf3ce4ac8b8f2ba0))
- **github-app:** Implement GitHub App installation and uninstallation features, enhance provider organization management ([a1057b0](https://github.com/akira-foundation/unified-dev/commit/a1057b08446d0578c6bf07f32b59886e606abac5))
- **auth:** Enhance GitHub App authentication with refresh token and expiration handling ([a105b7f](https://github.com/akira-foundation/unified-dev/commit/a105b7f0551e8c3c91dbb8034d3adf11373852b0))
- **provider:** Refactor default branch handling and improve issue actions menu ([7875bf0](https://github.com/akira-foundation/unified-dev/commit/7875bf07f800901cccc9d5d244bc588478ad5625))
- **mcp:** Add MCP server management features and integrate with skills ([51b2501](https://github.com/akira-foundation/unified-dev/commit/51b2501e8c1e7fc50001905ecd25c1e33870710b))
- **mcp:** Enhance MCP tool integration with improved server handling and UI updates ([cdcb3d4](https://github.com/akira-foundation/unified-dev/commit/cdcb3d49ecf188b2c91ce42cceabb4a49f69cd27))
- **agent-timeline:** Enhance rendering of tables and improve UI elements for better readability ([5347475](https://github.com/akira-foundation/unified-dev/commit/534747538f34f98a9c5baddc8ec166048286c196))
- **agent-chat-input:** Integrate skills fetching and update skill display logic ([233d0fe](https://github.com/akira-foundation/unified-dev/commit/233d0fe902794629c04a433c8888588b2c2c6e77))
- **skill-discovery:** Implement recommended skills fetching and enhance skill management UI ([4d91976](https://github.com/akira-foundation/unified-dev/commit/4d919764466d9c60bf3632f6e0d2adb26979caa2))
- **skill-discovery:** Filter out skills with empty descriptions in recommendations ([7816566](https://github.com/akira-foundation/unified-dev/commit/78165663e2a8b76df5f611aa63deeceb5f338060))
- **agent-ui:** Improve textarea height handling and adjust layout spacing ([1954386](https://github.com/akira-foundation/unified-dev/commit/1954386981fc0476d948d10a6e1dfa7b21ba4d34))
- **repository:** Add fork information to organization repositories ([c56a331](https://github.com/akira-foundation/unified-dev/commit/c56a3315cf6d457c329353d7e9c330e37fd604fd))
- **sidebar:** Add settings button to sidebar footer and update layout ([7a011fb](https://github.com/akira-foundation/unified-dev/commit/7a011fbb5f371dbcdc6b4ea18c93d2f69ff3271c))
- **release:** Add build and release workflows with version syncing ([f06469a](https://github.com/akira-foundation/unified-dev/commit/f06469a85ef4fd20549009aa6cd8f7e7014b6de1))

