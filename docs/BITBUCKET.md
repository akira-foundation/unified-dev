# Bitbucket

How Unified Dev reads a pull request that lives on Bitbucket Cloud, which command line tool it
drives to do it, and what was measured to choose it. Measured on 2026-11-13 against public
repositories in the `atlassian` workspace (`atlassian/aui` above all), with reads only and no
credential of any kind. Anything not written here is unknown rather than assumed.

## Which host a repository is on

`ForgeRepository.parse(remoteURL:)` reads the host, the owner and the name from the remote, in
every form Bitbucket Cloud hands out: `git@bitbucket.org:team/repo.git`,
`https://user@bitbucket.org/team/repo.git`, `ssh://git@bitbucket.org/team/repo.git`, with or
without `.git` and `www.`. `bitbucket.org` is Bitbucket; every other host, and a remote with no
host at all, is GitHub, which is exactly what the app assumed before there was a choice to make.
`Forge.kind(forDirectory:)` asks it of the base remote of a checkout and remembers the answer for
five minutes, so a repository moved to another host is noticed without a remote being read on
every poll. Nothing is typed by hand.

Bitbucket Data Center is not detected, and #633 holds why. Its hosts are the company's own, so
the host alone says nothing: bkt itself treats every host other than `bitbucket.org` as Data Center
(`internal/remote/remote.go`), and on the public `bitbucket.software.geant.org` (Bitbucket 9.4.26)
the clone links are `https://<host>/scm/<project>/<repo>.git` and
`ssh://git@<host>:7999/<project>/<repo>.git`. The source the app could discover is the hosts
`bkt auth status --json` reports with `kind: "dc"`. What stops it is the readers: anonymously that
instance lists repositories and commits, answers every pull request list with an empty page and
refuses build statuses, so no Data Center pull request or build was ever seen.

## The command line tool

| Candidate | What it covers of Bitbucket | Verdict |
| --- | --- | --- |
| `acli` 1.3.39 (Atlassian) | `admin`, `auth`, `confluence`, `guard`, `jira`, `rovodev`; `acli bitbucket` answers `unknown command` | covers none of it |
| `twg` (Atlassian) | announced with a Bitbucket surface; its documentation page answered 404 | could not be measured |
| `bkt` 0.38.1, `bitbucket-cli` in Homebrew core | pull requests, build statuses, Pipelines, raw REST, Cloud and Data Center | **chosen** |

`bkt` is [avivsinai/bitbucket-cli](https://github.com/avivsinai/bitbucket-cli), MIT, released
from a signed tag with checksums and an SBOM per archive, and installed with
`brew install bitbucket-cli`. Its shape is the shape of `gh`: `bkt pr list`, `pr view`,
`pr checks`, `pr create`, `pr merge`, `pr checkout`, `pipeline list|view|logs`, `--json` and
`--jq` on every command, and `bkt api <path>` for anything without a command of its own, sent
with the stored credentials. It is detected like the agent CLIs, by `Shell.which("bkt")`.

The release archive was checked against `checksums.txt` and unpacked into a scratch directory with
its own `BKT_CONFIG_DIR`. Nothing was installed on the machine.

## Signing in, and where each secret lives

`bkt auth login https://bitbucket.org --kind cloud` with one of:

| Method | Flag | Secret |
| --- | --- | --- |
| OAuth in the browser | `--web` | short lived access token, refreshed by bkt |
| Atlassian API token, which replaced app passwords | `--web-token`, or `--username <email> --with-token` on stdin | the token |
| Repository or workspace access token | `BKT_TOKEN` with `BKT_AUTH_METHOD=bearer` | the token, in the environment |

Every stored secret goes to the macOS Keychain under the service `bkt`, keyed by host
(`api.bitbucket.org` for Cloud). `config.yml` under `BKT_CONFIG_DIR` holds the hosts and contexts
and never a token. `bkt auth status --json` lists the hosts with their kind, user name, method,
token source and expiry, and no secret, which is why it is the only thing the app reads to decide
whether somebody is signed in.

The Keychain item is keyed by host alone, not by configuration directory: the service is `bkt`
and the account `host/api.bitbucket.org/token`, read from bkt's `internal/secret/store.go` at the
0.38.1 tag. So two profiles cannot hold two Bitbucket Cloud sign-ins by pointing `BKT_CONFIG_DIR`
at two directories the way `GH_CONFIG_DIR` does for `gh`.

### Sign-in per profile

bkt's secret store is 99designs/keyring, and it reads four variables of its own that no help page
lists: `KEYRING_BACKEND` chooses the backend, `BKT_ALLOW_INSECURE_STORE=1` admits the encrypted
file one, `KEYRING_FILE_DIR` names its folder and `BKT_KEYRING_PASSPHRASE` its key. A profile whose
GitHub login is its own gets a Bitbucket sign-in of its own the same way, under
`<Application Support>/BitbucketLogins/<profile>/`, beside `GitHubLogins/`:

| Variable | Value |
| --- | --- |
| `BKT_CONFIG_DIR` | the profile's folder, so its hosts and contexts are its own |
| `KEYRING_BACKEND` | `file` |
| `BKT_ALLOW_INSECURE_STORE` | `1` |
| `KEYRING_FILE_DIR` | `secrets/` inside the profile's folder |
| `BKT_KEYRING_PASSPHRASE` | the contents of `passphrase` in the profile's folder |
| `BKT_TOKEN`, `BKT_HOST`, `BKT_USERNAME`, `BKT_AUTH_METHOD`, `BKT_WORKSPACE` | emptied, so a token in the owner's shell never reaches the profile |
| `KEYRING_FILE_PASSWORD`, `KEYRING_PASSWORD` | emptied, because bkt falls back to them for the file store's key |

The folder and its `secrets/` are `0700`, set again on every sign-in, and the passphrase, 32 random bytes written the first time the profile signs
in, is `0600`. The token is encrypted at rest with it. That keeps it out of plain sight and out of a
backup read on its own, and it does not keep it from a process running as the owner, which is the
same standing `gh auth login --insecure-storage` has in the profile's `GH_CONFIG_DIR`. An agent of the
profile is started with the passphrase in its environment, because its own `bkt pr merge` has to
open the store; anything that agent runs can read it, as it could read a `gh` token from that folder. The
initial profile, and every profile whose GitHub login is Unified's, keep this Mac's own bkt
configuration and Keychain, and the app adds nothing to their environment.

`BitbucketLogin` in `Sources/Core/Forge/` holds this; `GitHubLogin.everySignIn(appliedTo:)` is what
every agent runner and `GitHubLogin.everyVariable` what a workspace's setup is started with, so an
agent's `bkt pr merge` runs as the profile. Every `bkt` the app runs itself goes through
`Bitbucket.run`, which resolves the directory's profile exactly as `gh` does.

Profile Settings shows a Bitbucket section under the GitHub one. It reads `bkt auth status --json`
under the profile's variables and shows the user and the method bkt reports (`oauth` is the browser
sign-in, `basic` an API token, `bearer` an access token). Every profile offers two methods, each run
in a terminal inside the sheet: `bkt auth login https://bitbucket.org --kind cloud --web` for OAuth
in the browser, and the same with `--web-token` for an Atlassian API token, where bkt itself asks
for the email and the token. A profile with its own sign-in adds `--allow-insecure-store` and its
variables; one using this Mac's signs this Mac in, into the Keychain. Unified Dev never has a field
for either. App passwords are not offered: Atlassian stopped issuing them in favour of API tokens,
and bkt asks for an API token where an app password once went. Repository and workspace access
tokens are read by bkt only from `BKT_TOKEN`, so offering one would mean the app holding the token
itself; that is left out, and #634 holds what was measured, starting with `bkt auth status --json`
listing no host at all under `BKT_TOKEN`.

The welcome window's setup check lists the Bitbucket CLI after the GitHub CLI, for everybody and as
optional: missing or signed out, it offers `brew install bitbucket-cli` and then
`bkt auth login https://bitbucket.org --kind cloud --web`. Without it nothing is blocked: the window
reads ready to go, and the sentence under the headline does not name it. Signed in means `bkt auth status --json` lists a Cloud host, the same reading the bar
makes.

## Contexts

Every `bkt` command that touches a repository needs a context, a named binding of a host to a
workspace; `bkt auth login` creates none, and with no context `bkt pr list` answers
`no active context; run bkt context use <name>`. The app passes `--context` on every call that
reads a repository, naming the active Bitbucket Cloud context, or the first one bound to
`api.bitbucket.org`. When there is
none it creates one called `unifieddev` with `bkt context create unifieddev --host
api.bitbucket.org --workspace <owner>`, once, naming the workspace from the remote: bkt refuses a
Cloud context without `--workspace`, measured on 0.38.1 with `--workspace is required for Bitbucket
Cloud contexts`. bkt makes a new context the active one only when no context is active,
so a terminal already pointed at another context keeps it. The workspace and the repository are not taken from the context: the
app names them in the path it asks for, from the remote.

## What the bar reads

Reads go through `bkt api`, because the REST answers are what could be measured without a
credential and `bkt pr view --json` returns the same field names inside a wrapper. Each refresh,
shared between the pull request bar and the checks tab, runs `bkt auth status --json` and then:

1. `/repositories/{workspace}/{repo}/pullrequests` with
   `q=source.branch.name="<branch>"`, the three states `OPEN`, `MERGED` and `DECLINED`, and
   `sort=-updated_on`, one page of 50, which is the most Bitbucket returns. Bitbucket answers only
   `OPEN` when no state is named, and `bkt api` sends every repeated `--param` and percent-encodes
   them. A branch name is reused: `issue/10.2.x/upmerge` on `atlassian/aui` carried one open pull
   request and nine merged ones, so an open one wins and a closed one counts only if it was last
   updated after the workspace was made. A pull request from a fork whose branch has the same name
   is skipped, unless the fork is one of this checkout's own remotes. With none on the branch and a number recorded on the workspace, the pull request is read
   by number.
2. `/repositories/{workspace}/{repo}/commit/{hash}/statuses` for the source commit, one page of
   100. The 12 character hash a pull request reports is accepted. When Bitbucket refuses the statuses
   (`401 Unauthorized`, `403 Forbidden`, `404 Not Found`, which is how bkt prints them) the pull
   request is still shown, with its checks unreadable; any other failure fails the read.

| Bitbucket | Unified Dev |
| --- | --- |
| `state` `OPEN`, `MERGED` | the same |
| `state` `DECLINED`, `SUPERSEDED` | `CLOSED` |
| `draft` | draft |
| `source.branch.name`, `destination.branch.name` | branch, base branch |
| `source.commit.hash` | head commit, abbreviated |
| `author.uuid`, else `author.account_id` | author, as the account that owns the branch |
| source and destination `full_name` differ | from a fork |
| a participant with `changes_requested`, or else one approved | `CHANGES_REQUESTED`, `APPROVED` |
| `updated_on` of a merged or declined pull request | when it closed; Bitbucket records no `closed_on`, and `updated_on` also moves on a later comment |

Bitbucket returns no mergeability with a pull request (`bkt pr mergeability` is a separate call
and was not measured), so a conflict is not shown.

### Build statuses and Pipelines

A commit status is `INPROGRESS`, `SUCCESSFUL`, `FAILED` or `STOPPED`, with a `key`, a `name`, a
`url` and its timestamps. They become a check running, passed, failed and cancelled, and roll up
exactly as GitHub's do, which counts a cancelled check, and so a stopped build, as failed. Bitbucket has no notion of a required status that the API returns, so
every one counts as required.

**Pipelines needs no second source.** Every Pipelines run writes a commit status of its own: on
`atlassian/aui` the source commit of run 14542 carried `FAILED`, key `-1211181337`,
name `Pipeline #14542 for BESECART-3480_aui`, url
`https://bitbucket.org/atlassian/aui/addon/pipelines/home#!/results/14542`, beside a Snyk status
and the Bamboo builds. The steps inside it come from `/pipelines/{build number}/steps/`, which answered without a
credential (`Build and deploy`, `COMPLETED`, `FAILED`, with `started_on` and `completed_on`) while
the same path with the run's UUID answered `Bad request` until the braces were encoded.

So the checks tab shows a pipeline as its steps, each a row of its own grouped under the pipeline's
name and linked to `/pipelines/results/<build>/steps/<uuid>`, which is why Ask to fix on a step reads
that step's log and no other. A step's state becomes a check's:

| Step `state.name` | `state.result.name` | Check |
| --- | --- | --- |
| `PENDING`, `READY` | | queued |
| `IN_PROGRESS` | | running |
| `COMPLETED` | `SUCCESSFUL` | passed |
| `COMPLETED` | `FAILED`, `ERROR` | failed |
| `COMPLETED` | `STOPPED` | cancelled |
| `COMPLETED` | `NOT_RUN`, `SKIPPED` | skipped |

Only `COMPLETED` with `FAILED` and `SUCCESSFUL` were seen on `atlassian/aui`; the rest is the
vocabulary Bitbucket documents. A step in any other state, steps bkt cannot read, a list of more
than one page, a pipeline link naming another repository, and a finished pipeline with a step still
waiting, which is what a manual step left untriggered looks like, all keep the pipeline as one row,
as before. A repository renamed on Bitbucket while the remote keeps the old name has its results
links refused the same way, until the remote is updated.

Five pipelines at most are expanded per read, so a read of one workspace costs up to five bkt calls
more than before, and a finished pipeline's steps are kept against the time it finished, so a
refresh asks for them again only while it runs or once it is run again.

A results link is compared with the workspace's repository before anything is read from it: its
first two path segments are the workspace and the repository, and a commit status pointing at
another repository's results is shown and never has its build number read from this one.

### A failed pipeline's log

A Pipelines status links to `.../addon/pipelines/home#!/results/<build number>`, and newer runs to
`.../pipelines/results/<build number>`, sometimes followed by `/steps/<step uuid>`.
`BitbucketPipelineTarget.parse` reads the build number from either, and the step when it is named.
Sending a failed build to the agent, from the checks tab, the bar's Ask to fix or the pull request
auto fix, then reads the steps, keeps the failed ones (`state.result.name` `FAILED` or `ERROR`, or
the one the link names), at most three, and asks for each with
`bkt pipeline logs <build number> --step <uuid> --workspace <owner> --repo <name> --context <name>`.
The log is plain text and goes through the same excerpt and the same attachment as a GitHub
Actions log. A build reported by anything else, Bamboo or Snyk on `atlassian/aui`, has no log bkt
can read, and the agent is told so.

The log itself could not be measured: `/pipelines/{uuid}/steps/{uuid}/log` on the public
`atlassian/aui` run 14542 answered `404` with `The value provided is not a valid uuid.` without a
credential, whatever the braces. bkt sends `Accept: application/octet-stream` to the same path, so
the text is taken as bkt prints it.

## Merging, opening, and the rest

Every action is done by the workspace's agent, in its chat, exactly as on GitHub; the app chooses
the words, by the pull request's host.

- **Merge.** An open pull request offers Merge as on GitHub. The method becomes a strategy:
  merge commit is `merge_commit`, squash is `squash`, rebase is `rebase_fast_forward`, which is
  what a rebase merge does on GitHub. The prompt's `{{method_flag}}` reads
  `--strategy <strategy>`, and the steps under it (`MergeInstructions.bitbucketCanonical` and
  `bitbucketAppOnly`) ask for `bkt pr merge <number> --strategy <strategy> --close-source=false`,
  read a refusal from `bkt pr view <number> --json` and `bkt pr checks <number>`, wait with
  `bkt pr checks <number> --wait`, read a failed Pipelines step with `bkt pipeline logs`, and
  delete the branch with git afterwards, as on GitHub. Bitbucket returns no mergeability, so a
  conflict is found by the agent trying the merge locally. A state Bitbucket has not been seen to
  send still holds the merge.
- **Whose branch it is.** The project's own instructions are attached only when the branch is the
  owner's: the viewer is the `uuid` from `bkt api /user`, compared with the pull request author's.
  A nickname or a display name is never compared, because Bitbucket keeps neither unique and anybody
  can choose one. The head Bitbucket reports in twelve characters matches the full commit it begins
  (`CommitHash.same`).
- **Mark ready.** A draft offers Mark ready, sent with a Bitbucket default that asks for
  `bkt pr ready <number>`, unless the owner edited that prompt.
- **Create pull request.** `PullRequestInstructions.bitbucketTurn` asks for
  `bkt pr create --source <branch> --target <base> --title --description`, or attaches
  `.unifieddev/pr-instructions.md` when the project has one and the branch is the owner's.
- **Start a workspace from a pull request.** The new workspace pane lists the open pull requests
  from `/repositories/{workspace}/{repo}/pullrequests?state=OPEN`, and a number, or a link ending in
  `/pull-requests/<id>`, is read by number; a GitHub link in a Bitbucket project, or the reverse, is
  refused even when the slug matches. A source branch git would read as an option is refused
  before bkt runs. The checkout is `bkt pr checkout <id> --branch <local> --workspace --repo --context`
  in a fresh detached worktree; bkt fetches `<source>:<local>` and adds a remote for a fork on its
  own. It sets no upstream, so for a branch of this repository the app sets
  `branch.<local>.remote` to `origin` and `branch.<local>.merge` to the source branch. A pull
  request whose source repository Bitbucket does not name is treated as a fork, and gets none.
  bkt fetches `<source>:<local>` without a `+`, so a local branch of that name already ahead of
  the server would be refused. When that branch exists and the pull request is not from a fork, bkt
  is not run: the app fetches `+refs/heads/<source>:refs/remotes/<remote>/<source>` from the
  checkout's base remote, `origin` unless the repository says otherwise, and compares. A
  local branch at or ahead of the server is checked out as it stands, one behind it is fast
  forwarded with `git merge --ff-only`, and one that has moved apart is refused with nothing
  changed, and the new worktree is removed. Either way the branch tracks that remote. The fetch is
  git's own, so it signs in with the git credentials of this Mac, as bkt's fetch does. A fork's pull request over an existing local branch
  still goes through bkt, and still fails the same way.
- **The checks tab** asks bkt whether it is signed in, not gh, and names Bitbucket and bkt when it
  cannot read. Merge, Mark ready and Create pull request ask bkt the same thing before sending
  anything, and say where to sign in when it is not.
- **The bridge.** `workspace_list` with `include_github` and `workspace_merge` read a Bitbucket
  workspace's pull request through bkt, and a refusal names `bkt` and Bitbucket where it would
  name `gh` and GitHub: missing, signed out, silent, no pull request, a state the host will not
  take, and work the host has not got.
- **Starting points.** Under the new workspace header a Bitbucket project offers the open pull
  requests naming the viewer as a reviewer and as the author, from
  `/pullrequests?q=state="OPEN" AND reviewers.uuid="<uuid>"` and the same with `author.uuid`, ten
  of each. Once `q` is given Bitbucket ignores the `state` parameter and answers declined pull
  requests too (measured on `atlassian/aui`), so the state goes inside the query. The viewer is
  the `uuid` from `/user`, and anything that is not a uuid is never put in a query. A reviewer
  stays named after approving, so a pull request the owner has already reviewed is still offered,
  where GitHub's `review-requested:@me` drops it. Issues assigned
  to the owner are not offered, because Bitbucket's are in Jira (#635).
- **The pull request auto fix** reads the viewer and the commit authors from
  `/pullrequests/{id}/commits`, by account `uuid` and with the newest commit as the head they
  describe. Pages of 100 are followed through `next`, whose `page` is an opaque cursor
  (`page=67Fg` on `atlassian/aui` #5486), taken only from a link to the same pull request's commits
  on `api.bitbucket.org` and passed back with `--param page=<cursor>`. Ten pages at most are read;
  a pull request longer than that is not vouched for, and an unlinked author counts as nobody's.
  The failed builds' logs are read as above, and a step whose log cannot be read is left out
  rather than losing the others, and named under `== Not read ==`.

Still to do:

- Bitbucket Data Center, which bkt covers and nothing here detects (#633);
- repository and workspace access tokens per profile (#634);
- Jira issues assigned to the owner as starting points (#635).
