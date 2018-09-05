# Phlay your commits for phabricator

At Mozilla we often want to use commit series, but 'Arcanist', the default
phabricator command line tool, does not support this use case nicely. Phlay is
a hacky tool for people using git for their Mozilla development, which rewrites
git history, and pushes individual commits as revisions, with the correct bug
number, reviewers, and dependencies.

This tool is a single-file ruby script, built on libgit2, which directly talks
to the Conduit API. It aims to be feature complete, and handles complex tasks,
such as diff parsing and metadata collection, locally.

> **NOTE** This tool declares dependencies using `bundler/inline`

> **NOTE** This file used to be a single-file python script, but as complexity
> grew, the need for dependencies became too much. The implementation was
> replaced with a ruby one to take advantage of `Rugged` and `bundler/inline`.
