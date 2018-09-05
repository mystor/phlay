# Phlay your commits for phabricator

At Mozilla we often want to use commit series, but 'Arcanist', the default
phabricator command line tool, does not support this use case nicely. Phlay is
a hacky tool for people using git for their Mozilla development, which rewrites
git history, and pushes individual commits as revisions, with the correct bug
number, reviewers, and dependencies.

## Install

To install, symlink `phlay` from this directory onto your `$PATH`.

```
$ ln -s $PWD/phlay $HOME/.local/bin/phlay
```

## Dependencies

This program depends on a few programs being installed:
 - `ruby` is used for the core of the script
 - `git-cinnabar` is required for cinnabar-based repositories
 - `bundler` is used to install other dependencies from `Gemfile`
