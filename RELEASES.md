# Version 0.2.1

* Phlay should now work in the MozillaBuild shell (https://github.com/mystor/phlay/pull/57)
* Revision subranges can now be updated without breaking dependency relationships (https://github.com/mystor/phlay/pull/62)
* Phlay will no longer drop newlines when rewriting commit messages

# Version 0.2.0

* Fix version comparison bug which was preventing updates to 0.1.10 (https://github.com/mystor/phlay/pull/59)

# Version 0.1.10

* Fix another typo (thanks @djg)

# Version 0.1.9

* Fix a typo causing failures updating revisions.

# Version 0.1.8

* Handle parsing empty files correctly in change parser.
* Uses new Conduit APIs to support mutating revision edges.

# Version 0.1.7

* Correctly set the mode bit on newly created files.

# Version 0.1.6

* Added --reopen flag to re-open changesets which were closed and are being updated.

# Version 0.1.5

* Support for Windows paths from WSL

# Version 0.1.4

* Support pushing patches for private/secure bugs better

# Version 0.1.3

* Send addLines/delLines info for hunks (#39)
* Translate invalid utf-8 characters to replacement when generating diffs

# Version 0.1.2

* Preserve punctuation in commit messages for lando (#37, #38)

# Version 0.1.1

* Added '--version' flag and update checking
* Cleaned up error messages in some situations
* Avoid potentially-unnecessary 'git-cinnabar' handling
* Support non-cinnabar mozilla-central checkouts better

# Version 0.1.0

* Diff parsing support
* Improved binary & image handling
* Accurate commit information
* Fixed a bug preventing lando usage
