

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
