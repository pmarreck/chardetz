# Upstream defects found during translation

These are defects in uchardet (as pinned in `PROVENANCE.md`) that the translation exposed. Zig's bounds checks turn each of them into a crash instead of a silent wrong read, so chardetz has to make an explicit, documented choice where C++ has undefined behavior.

## EUC-TW frequency table is shorter than its declared size

- Upstream: `EUCTWFreq.tab` declares `EUCTW_TABLE_SIZE 8102`, but `EUCTWCharToFreqOrder` has 5376 entries. `CharDistributionAnalysis::HandleOneChar` checks an order only against `mTableSize`, so for orders 5376 to 8101 it reads past the end of the array.
- Reachable when: an EUC-TW lead byte of 0xFD or 0xFE produces an order of 5376 or more (`94 * (lead - 0xC4) + trail - 0xA1`).
- Upstream effect: it reads whatever memory follows the array, which is undefined behavior. The value only decides whether that character counts as "frequent".
- chardetz: such orders still count as characters but never as frequent ones (`src/mbcs.zig`, `Distribution.handleOneChar`).

## ISO-2022-JP char-length table is shorter than its class count

- Upstream: `ISO2022JPSMModel` has `classFactor` 10, but `ISO2022JPCharLenTable` has 8 entries. `nsCodingStateMachine::NextState` reads `charLenTable[byteClass]` at the start of each character, so classes 8 and 9 read past the array.
- Upstream effect: it reads undefined memory into `mCurrentCharLen`, which the escape-sequence prober (the only user of this machine) never reads. Detection results are unaffected.
- chardetz: it uses 0 for out-of-range classes (`src/prober.zig`, `CodingStateMachine.nextState`). A test asserts that every multibyte model, where the char length does matter, has an in-range table.
