# shared/fixtures — the cross-language parity contract

The Sharp Edge runs the same kitchen arithmetic in three languages: Python on the
server, Swift on the iPad, TypeScript on the web. These JSON files are how those three
are held to the same answers.

**Do not edit these files by hand.** They are generated:

```bash
python api/scripts/dump_fixtures.py            # rewrite
python api/scripts/dump_fixtures.py --check    # fail if stale (CI does this)
```

Inputs are curated by hand in `dump_fixtures.py`; **expectations are generated from the
live Python.** That asymmetry is deliberate. Hand-typed expectations only pin what
somebody remembered to type, and only on the day they typed it.

## Why this exists

CLAUDE.md §8 said "the server is canonical" and the client "mirrors" it. That is a
comment, and comments do not fail builds. By the time this harness was written:

- `SampleDataSource.glutenWatch` carried **14** terms against the server's **23** —
  missing `curry powder, spice blend, seasoning, gravy, sausage, bacon, imitation crab,
  surimi, oats`. GF is load-bearing (§1); a missing term there is a bad week.
- `AISLE_ORDER` existed in **four** hand-copied places.

Local notebook mode raises the stakes: with no server in the loop, the Swift answer is
the one a cook acts on. "Canonical" needs teeth.

## The rule

**Any change to `scaling.py`, `shopping.py`, `aisles.py` or `ingredients.py` must add or
change a fixture case.** Regenerate, and every port that has not followed goes red on
the exact input that moved.

## Format

```json
{
  "version": 1,
  "function": "classify_aisle",
  "note": "why these cases matter",
  "tolerance": 0.001,
  "cases": [
    { "id": "beef-chuck", "args": { "name": "beef chuck, cut into 1-inch cubes" },
      "expect": "Meat & fish" }
  ]
}
```

`tolerance` is optional and applies to numeric comparison only — merging genuinely
produces `953.5920000000001`. **Rendered display strings always compare exactly**,
because they are what a cook reads.

`id` is a sentence, not an index, so a failure names the input that broke.

## Consumers

| Suite | Loader | Role |
|---|---|---|
| `api/tests/test_parity_fixtures.py` | `api/tests/fixtures.py` | regression net — these were generated from this code |
| `ios/TheSharpEdgeTests/*ParityTests.swift` | `SharedFixtures.swift` | **specification** for the Swift port |

Each suite also asserts that no fixture file is orphaned. A fixture nothing reads is
worse than no fixture: it looks like coverage.

The Swift loader reads this directory from the source tree via `#filePath`, so those
tests run on a **simulator or Mac, not a physical device**. Everything covered is a pure
function, and the alternative — copying the JSON into the test bundle — would
reintroduce the stale-duplicate problem these files exist to kill.
