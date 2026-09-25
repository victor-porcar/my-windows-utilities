# github-repos-sync.ps1

Clones or updates every repository of a GitHub account into one directory.

```
powershell -ExecutionPolicy Bypass -File github-repos-sync.ps1 "D:\path\to\github"
```

Run `Get-Help .\github-repos-sync.ps1 -Full` for the full parameter reference.

## Requires GitHub CLI

The repository list comes from `gh`, which must be installed and authenticated once:

```
winget install --id GitHub.cli
```

```
gh auth login
```

Choose GitHub.com, HTTPS, and login with a web browser. This also leaves git able to push without
you handling tokens by hand.

Note that `gh` is only added to the `PATH` of consoles opened **after** the install, which is why
the script also looks for it in `C:\Program Files\GitHub CLI` before giving up.

With no `-Account`, it uses whichever account is authenticated, and **private repositories are
included**. Pass `-Account <user-or-org>` for someone else's, where only public ones are visible.

## What it does per repository

- **Folder missing** → `git clone`.
- **Folder present** → `git pull --ff-only`.
- **Uncommitted local changes** → reported and skipped, never touched.

Running it twice in a row therefore clones the first time and pulls the second. It is safe to run
as often as you like: only what is missing gets downloaded.

The pull is fast-forward only on purpose. If a branch has diverged, the script reports a failure
instead of creating a merge commit behind your back. Archived repositories are skipped unless you
pass `-IncludeArchived`.

## Watch out for long paths

Windows limits paths to 260 characters unless told otherwise, and git fails the checkout with
`Filename too long` when a repository holds deeply nested files. The clone itself succeeds, so
you end up with an empty-looking working copy.

If you hit it, enable long path support in git once:

```
git config --global core.longpaths true
```

Choosing a short target directory (`D:\github` rather than something nested ten levels deep) also
buys you a lot of headroom.
