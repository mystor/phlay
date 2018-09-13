# Phlay your commits for phabricator

At Mozilla we often want to use commit series, but 'Arcanist', the default
phabricator command line tool, does not support this use case nicely. Phlay is
a hacky tool for people using git for their Mozilla development, which rewrites
git history, and pushes individual commits as revisions, with the correct bug
number, reviewers, and dependencies.

This tool is a single-file dependency free python script, which directly talks 
to the Conduit API. It aims to be feature complete, and should send all required
information to the Differential remote. If useful/important information is not
being sent, or a patch is unlandable using `lando`, please 
[file a bug](https://github.com/mystor/phlay/issues)

> **NOTE** This tool depends on `python >= 3.6`

> **NOTE** This is a hacky tool made for my own use, probably don't depend on 
> it unless you're OK with it breaking.

