# restate-research

Machine-checked experiments on [Restate](https://github.com/restatedev/restate) (durable
execution): a Lean 4 model of its service-protocol message header, and an end-to-end
reproduction of a runtime crash the model led to.

Part of [research](https://github.com/pedroteixeira/research).

## Finding: invoker panic on a custom or unassigned message type

If a service deployment answers an invocation with a frame whose type is a custom one
(`0xFC00–0xFFFF`) or an unassigned id with a bit of `0xFC00` set (e.g. `0x040F`, `0x8000`),
`restate-server` panics (`Message::Custom(_, _) => unimplemented!()` in the invoker). The
partition processor then restarts in a loop on the same invocation.

| frame type | 1.7.14 | 1.8.1-hotfix.3 | main 1bcb627 | with the fix |
|---|---|---|---|---|
| `0xFC00` (custom range) | panic, crash loop | panic, crash loop | panic, crash loop | RT0012, retried |
| `0x040F` (unassigned command id) | not tested | panic, crash loop | not tested | RT0012, retried |
| `0x8000` (unassigned notification id) | not tested | panic, crash loop | not tested | RT0012, retried |
| `0x0201` (control range) | not tested | no panic, retried | not tested | not tested |

- Issue: _to be opened_
- Fix: [`pedroteixeira/restate@fix/invoker-custom-message-panic`](https://github.com/pedroteixeira/restate/tree/fix/invoker-custom-message-panic), PR _to be opened_

## Lean model (`lean/`)

`Header.lean` models the type table, the custom/unknown classification and the 64-bit header
packing, identical in `sdk-shared-core` (`src/service_protocol/header.rs`) and the runtime
(`crates/service-protocol-v4/src/message_codec`). `bv_decide` proves:

- decoding is total and unambiguous (known / custom / error);
- every id in `0xFC00–0xFFFF` decodes as custom;
- the command and notification ranges are disjoint, and a custom id is neither;
- header encode∘decode and decode∘encode are the identity, and setting `REQUESTED_ACK`
  never changes the type.

`Refute.lean` holds the two properties that fail, both with counterexample `0x7FFF`:

- "decodes as custom ⇒ in `0xFC00–0xFFFF`" (the documented range). 63,456 ids below `0xFC00`
  decode as custom.
- "custom ⇒ not a command" (in `sdk-shared-core`).

Following where `Custom` goes in the runtime led to the panic.

```bash
cd lean
lake build                  # Header: every theorem checks
lake env lean Refute.lean   # prints the counterexamples
```

## Reproduction (`repro/`)

`fake_deployment.py` is a Python-stdlib deployment (HTTP/1.1, request/response mode) that
answers every invocation with one 8-byte frame of the given type. `repro.sh` starts
`restate-server` (docker, host network), registers the fake deployment, sends one invocation
and counts panics, partition-processor restarts and RT0012 errors in the server log.

```bash
repro/repro.sh FC00                     # docker image restatedev/restate:1.8.1-hotfix.3
repro/repro.sh FC00 1.7.14              # another tag
RESTATE_BIN=/path/to/restate-server repro/repro.sh FC00   # a local build, e.g. the fix
```

Needs Docker (or a local `restate-server`), `curl` and Python 3. Uses ports 8080, 9070 and 9080.

## AI use

Claude (Anthropic) wrote most of the Lean model, the fake deployment and the fix. Each result
was checked by a machine (Lean, the repro script, `cargo nextest` / `clippy` on the fix) and by
hand before it was reported upstream.
