# Working in swift-insteon

Read [CONVENTIONS.md](CONVENTIONS.md) first. It sets the names, spelling and style that
`Scripts/check-terms.py` and the other `Scripts/check-*.py` checks hold the repository to.

## What the packages know

- **The catalog describes the protocol; the code reads it.** What a device is and does comes from
  the Insteon device catalog (`InsteonDeviceCatalog`): its ALL-Link record data, operating flags,
  commands, linking changes and how a relay holds a state. InsteonCore, the `insteon` command, the
  in-memory modem and their tests name no real product or operating flag. A test builds its own
  catalog with invented names. If a behavior can't be expressed from the catalog, the catalog's
  schema grows a field in protocol terms; the code doesn't learn the device.
- **The command stays thin.** `insteon` depends only on InsteonCore and InsteonCLISupport.
- **Facts come from hardware observations or public documents cited by exact title.** A value
  nobody has checked is marked unverified.

## How a change goes

1. Specify the behavior as Given/When/Then and agree it before writing code.
2. Write the failing tests first, from the outside in: the command or public API, then the
   internals. Tests state behavior and never wait on time.
3. Make them pass, then refactor with the tests green.
4. One logical change per commit. The author is the person who owns the work; commit messages
   carry no attribution lines.
5. Open a draft pull request. CI runs four jobs: Terms, macOS, Linux and iOS. All must pass on the
   head commit.
6. A change that can alter what a device does needs a hardware test on the pull request's head
   before it is marked ready (see the pull request template).

## Before pushing

- `swift build -Xswiftc -warnings-as-errors` and `swift test` in the packages you touched.
- Every `python3 Scripts/check-*.py`, and `python3 -m unittest discover -s Scripts/tests`.
- `python3 Scripts/check-public-api.py --update` when InsteonCore's public API changes.
- An allow-list file only shrinks; CI fails a pull request that adds a line.
- No em dash or en dash anywhere, in code, comments, docs, commit messages or pull request text.
- Check `git log -1 --format=%ae` against the identity the repository is configured with before
  every push.

## Catalog updates

The package bundles a copy of the catalog as a fallback and downloads newer catalogs of the same
MAJOR.MINOR at run time. Refresh the bundled copy with `Scripts/update-device-catalog.sh`. A new
MAJOR.MINOR needs a package change that reads it.
