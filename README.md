# Phlay your commits for phabricator

Phlay handles pushing commit series to Mozilla's phabricator instance efficiently. Phlay was written before `moz-phab` supported git setups, and was made to enable using an efficient patch-stack based phab workflow.

> **NOTE** This is _not_ an official mozilla project, and is not receiving
> active development or releases. Occasionally the phabricator configuration
> will change, and uploads with `phlay` will fail until it is fixed.
>
> I would generally recommend using the officially maintained
> [`moz-phab`](https://github.com/mozilla-conduit/review) tool, as it is tested
> against our specific phabricator config, has more features, and is updated
> more frequently.

## Features

 * Self-contained Python script, with no `php` or `arc` dependencies
 * Full support for git workflows, both with and without `git cinnabar`
 * Automatically parses and sets revision fields, including bug number and reviewers, from the commit message
   * Reviewers are marked as blocking by default
   * Reviewer teams can be specified with a `#` (e.g. `r?#build`)
 * Never modifies working directory, running fast and, preventing needless rebuilds
 * Automatic patch dependencies within specified commit range
 * `--reopen` flag allows for closed revisions to be re-opened (e.g. due to a backout)
 * Compatible with `lando` for landing patches
 * Shows useful information (including diff summary & bug title) before submitting
 * Pretty colorized command-line output
 * Windows Subsystem for Linux support

This tool is a single-file dependency free python script, which directly talks 
to the Conduit API. It aims to be feature complete, and should send all required
information to the Differential remote. If useful/important information is not
being sent, or a patch is unlandable using `lando`, please 
[file a bug](https://github.com/mystor/phlay/issues)

> **NOTE** This tool depends on `python >= 3.6`

> **NOTE** This tool doesn't currently support mercurial

## Non-Mozilla

This tool is fairly specialized for contributing to mozilla projects, including integration with https://bugzilla.mozilla.org, for example. It may not work well with other environments, but patches are welcome to make it cooperate better in those situations.

## Example Output

```
$ phlay 523ecf1ebe5eb..06f7e159d7117

5193b908775df Bug 1529684 - Part 1: Allow Attaching BrowsingContext from parent to child, r=farre
  Update Revision
    https://phabricator.services.mozilla.com/D21095
  Bug 1529684
    Create BrowsingContext for remote frame in embedder process
  Changes
    M  docshell/base/BrowsingContext.cpp +25, -37
    M  docshell/base/BrowsingContext.h   +3, -3
    M  dom/ipc/ContentChild.cpp          +29, -0
    M  dom/ipc/ContentChild.h            +7, -0
    M  dom/ipc/ContentParent.cpp         +4, -2
    M  dom/ipc/PContent.ipdl             +33, -33
    6 files (+101, -75)

511c24af19bcb Bug 1529684 - Part 2: Create BrowsingContext for remote browsers in parent, r=farre
  Update Revision
    https://phabricator.services.mozilla.com/D21096
  Bug 1529684
    Create BrowsingContext for remote frame in embedder process
  Changes
    M  docshell/base/BrowsingContext.cpp           +4, -0
    M  docshell/base/BrowsingContextGroup.cpp      +23, -0
    M  docshell/base/BrowsingContextGroup.h        +3, -0
    M  docshell/base/CanonicalBrowsingContext.h    +2, -0
    M  dom/ipc/BrowserBridgeParent.cpp             +17, -3
    M  dom/ipc/ContentChild.cpp                    +22, -15
    M  dom/ipc/ContentChild.h                      +4, -1
    M  dom/ipc/ContentParent.cpp                   +39, -14
    M  dom/ipc/ContentParent.h                     +3, -1
    M  dom/ipc/PBrowser.ipdl                       +0, -2
    M  dom/ipc/PContent.ipdl                       +2, -1
    M  dom/ipc/TabChild.cpp                        +7, -11
    M  dom/ipc/TabChild.h                          +4, -1
    M  dom/ipc/TabParent.cpp                       +2, -9
    M  dom/ipc/TabParent.h                         +2, -3
    M  toolkit/components/browser/nsWebBrowser.cpp +5, -16
    M  toolkit/components/browser/nsWebBrowser.h   +1, -1
    M  xpfe/appshell/nsAppShellService.cpp         +8, -3
    18 files (+148, -81)

[snip]

06f7e159d7117 Bug 1532661 - Part 6: Clean up BrowsingContext references more reliably, r=farre
  Update Revision
    https://phabricator.services.mozilla.com/D23048
  Bug 1532661
    Support syncing complete BrowsingContextGroups over IPC
  Changes
    M  docshell/base/BrowsingContext.cpp +22, -13
    M  dom/ipc/TabChild.cpp              +6, -0
    2 files (+28, -13)

Proceed? (y/N) y

Publishing Patch Bug 1529684 - Part 1: Allow Attaching BrowsingContext from parent to child, r=farre
    Diff URI: https://phabricator.services.mozilla.com/differential/diff/74466/
Publishing Patch Bug 1529684 - Part 2: Create BrowsingContext for remote browsers in parent, r=farre
    Diff URI: https://phabricator.services.mozilla.com/differential/diff/74467/

[snip]

Requesting Review Bug 1532661 - Part 6: Clean up BrowsingContext references more reliably, r=farre
    Revision URI: https://phabricator.services.mozilla.com/D23048
```

## Contributing

Please feel free to contribute to this project. I will try to fix feature requests as they are filed, and review any changes or contributions.
