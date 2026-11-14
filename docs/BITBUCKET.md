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

Bitbucket Data Center is not detected. Its hosts are the company's own, so the host alone says
nothing, and no repository of one was available to measure.

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

The Keychain item is keyed by host alone, not by configuration directory, so two profiles cannot
hold two different Bitbucket Cloud sign-ins by pointing `BKT_CONFIG_DIR` at two directories the
way `GH_CONFIG_DIR` does for `gh`. Sign-in per profile has to carry the token itself, through
`BKT_TOKEN`, from the profile's own Keychain item. That is the next piece of work, not this one.

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
| `author.nickname` | author |
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
and the Bamboo builds. So the checks tab shows a pipeline as one check named by run and branch.
The names of the steps inside it, which #534 asks for, come from
`/pipelines/{build number}/steps/`, which answered without a credential (`Build and deploy`,
`COMPLETED`, `FAILED`, with start and end) while the same path with the run's UUID answered
`Bad request` until the braces were encoded. Reading the steps is not done yet.

## Merging, opening, and the rest

An open Bitbucket pull request shows its state and its builds, and its merge button stays
disabled with "Unified Dev cannot merge a Bitbucket pull request yet. Merge it on Bitbucket.",
because every merge the app asks of an agent is written for `gh`. A draft offers no "Mark ready"
for the same reason. Still to do, each against a real repository:

- merging from the bar, with instructions written for `bkt pr merge <id> --strategy`
  (`merge_commit`, `squash`, `fast_forward`) and `--close-source=false`;
- opening a pull request with `bkt pr create --source --target --title --description`;
- starting a workspace from a pull request with `bkt pr checkout <id>`, which adds a remote for a
  fork on its own;
- a failed build's log for Ask to fix, from `bkt pipeline logs` for Pipelines only;
- sign-in per profile in Profile Settings, as above;
- the starting points suggested below the new workspace composer, which offer recent branches
  alone on Bitbucket, with no pull request waiting on the owner and no issue assigned to them;
- the readers that still ask `gh` whatever the host: the workspace list and merge tools of the
  bridge, the pull request auto fix, and the check failure request. They find nothing on a
  Bitbucket workspace, as they did before Bitbucket was read at all.
