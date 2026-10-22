# Contributing

This kit is the one source of truth every Janzeer SDK and app is tested against: `vectors/` (crypto and transaction
preimage vectors) and `e2e/SPEC.md` (the end-to-end flow). It is small on purpose.

## What a change here means

- **Vectors are generated, never hand-edited.** They come from the node's `WalletParityVectorsTest`; `sync.sh --regen`
  regenerates them and copies them into every SDK, `sync.sh --check` fails on drift. A pull request that edits a JSON
  vector by hand is closed with that sentence.
- **The SPEC is prose with numbered steps.** Each SDK's e2e test follows the steps by number; adding or changing a step
  means every SDK's e2e test changes with it. Say so in the pull request and list the SDKs you updated.
- **Scripts are plain bash.** `e2e/node-up.sh` starts the local 4-anchor dev net (it needs the private node repo next to
  this one, so most outside contributors cannot run it — that is expected; the unit-level checks run everywhere).

## Good contributions from outside

- A clearer wording of a SPEC step, with the SDK tests still matching it.
- A vector *category* that the SDKs should also agree on (open an issue first: the generator lives in the node).
- Fixes to `run-all.sh` / `sync.sh` portability (macOS, BusyBox).

## Checks before a pull request

```bash
./sync.sh --check        # every SDK's vendored vectors equal vectors/
bash -n e2e/*.sh sync.sh run-all.sh
```

Commit as yourself; no AI attribution trailers in commit messages, please (the maintainers' rule for this organisation).
