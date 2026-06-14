# chardetz WASM ABI

`chardetz.wasm` (target `wasm32-freestanding`, built via `nix build .#wasm` or
`./build_all`) exposes a tiny, robust one-shot charset-detection ABI over WASM
linear memory. No libc, no WASI — it instantiates with an empty import object.

## Exported functions

| Export | Signature (WASM) | Purpose |
| --- | --- | --- |
| `memory` | (the module's linear memory) | Shared byte buffer between host and module |
| `chardetz_alloc(len: i32) -> i32` | returns a pointer (byte offset) into `memory`, or `0` on failure | Reserve `len` bytes for the host to write input into |
| `chardetz_detect(ptr: i32, len: i32) -> i32` | returns a pointer to a NUL-terminated charset name in `memory` | Detect the charset of the `len` bytes at `ptr` |
| `chardetz_free(ptr: i32, len: i32)` | — | Return memory obtained from `chardetz_alloc` (pass back the same `len`) |

The full uchardet streaming ABI (`uchardet_new`, `uchardet_handle_data`, …) is
also exported on the WASM build, but the **one-shot** `chardetz_detect` path is
the recommended host interface — it needs no handle lifecycle.

### Return value of `chardetz_detect`

A pointer into `memory` to a **NUL-terminated** ASCII charset name, e.g.
`UTF-8`, `WINDOWS-1251`, `SHIFT_JIS`, or the empty string `""` (just a NUL) when
the input is undetermined. The pointer is valid until the next
`chardetz_detect` call (it points at a single reused static buffer in the
module). Copy the string out before calling `chardetz_detect` again.

## Host recipe (JavaScript)

```js
const fs = require("fs");
const bytes = fs.readFileSync("chardetz.wasm");
const { instance } = await WebAssembly.instantiate(bytes, {});
const ex = instance.exports;

function detect(uint8) {
  const len = uint8.length;
  const ptr = ex.chardetz_alloc(len);          // reserve room in wasm memory
  if (ptr === 0) throw new Error("chardetz_alloc failed");
  new Uint8Array(ex.memory.buffer).set(uint8, ptr); // copy input bytes in
  const outPtr = ex.chardetz_detect(ptr, len);  // detect
  // Read the NUL-terminated name out of wasm memory:
  const mem = new Uint8Array(ex.memory.buffer); // re-read: memory may have grown
  let end = outPtr;
  while (mem[end] !== 0) end++;
  const charset = Buffer.from(mem.subarray(outPtr, end)).toString("utf8");
  ex.chardetz_free(ptr, len);                   // return the input buffer
  return charset;                               // e.g. "UTF-8" or "" if unknown
}

// PDF with an undeclared/lying encoding: feed the raw bytes, get a real charset.
console.log(detect(new Uint8Array([0xEF, 0xBB, 0xBF, 0x68, 0x69]))); // "UTF-8"
```

Notes:
- Always re-read `ex.memory.buffer` after calls that may allocate
  (`chardetz_alloc`, `chardetz_detect`) — WASM memory growth detaches old
  `ArrayBuffer` views.
- The module is single-threaded and the detect-result buffer is a single static
  slot, so treat detection as a synchronous, serial operation.

## Validation

`./build_all` (or `nix build .#wasm`) produces
`result-wasm/bin/chardetz.wasm`. The artifact is validated by instantiating it
in Node (available in the dev shell) and asserting the exports exist and that a
few corpus-shaped inputs detect correctly — see the manual check in the M5/M6
report and the snippet above. (`wasm2wat` / `wasm-objdump` are not in the dev
shell; Node's `WebAssembly` API is the validation harness.)
