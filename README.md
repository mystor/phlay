# Phlay your commits for phabricator

At Mozilla we often want to use commit series, but 'Arcanist', the default
phabricator command line tool, does not support this use case nicely. Phlay is
a hacky tool for people using git for their Mozilla development, which rewrites
git history, and pushes individual commits as revisions, with the correct bug
number, reviewers, and dependencies.

This tool depends on:

  - The `git-cinnabar` version of `arc` (https://github.com/mozilla-conduit/arcanist) being on the path,
  - Git >= 2.11 as 'git', and
  - Python >= 3.6 as 'python3'.

NOTE: This is a hacky tool made for my own use, probably don't depend on it
unless you're OK with it breaking.

NOTE: There's a chance that your git version isn't quite recent enough, in which
case you'll need to use the `noarc` branch, or get an updated git on the path.

## WIP `noarc` branch

**NOTE** This version of the tool depends on the default phabricator command
line tool `arc`. The [`noarc`](https://github.com/mystor/phlay/tree/noarc)
branch contains a WIP alternate implementation which instead directly talks to
conduit endpoints.

Please let me know about problems you run into when using `noarc`!
