# PaceTurner

RSVP (one-word-at-a-time) speed reading on a Garmin Fenix 8, with a Flutter
companion that converts your books into a timed word stream and streams them to
the watch.

> Status: early development. The full architecture story lands in Epic 5; this is a stub.

## Structure

This is a single public monorepo (MIT). The two apps share no code — the only
shared artifact is the protocol contract.

| Path | What lives here |
|------|-----------------|
| [`watch/`](watch/) | Connect IQ watch app (Monkey C), targets Fenix 8 / CIQ API 6.0 |
| [`companion/`](companion/) | Flutter companion app (Android-first) |
| [`protocol/`](protocol/) | The phone↔watch streaming protocol contract — see [`protocol/SPEC.md`](protocol/SPEC.md) |
| [`docs/`](docs/) | [`setup.md`](docs/setup.md) (toolchain) · [`gates.md`](docs/gates.md) (hardware validation V1–V4) |

## License

[MIT](LICENSE).
