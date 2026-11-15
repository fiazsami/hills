# Hills for macOS

[![tests](https://github.com/fiazsami/hills/actions/workflows/tests.yml/badge.svg)](https://github.com/fiazsami/hills/actions/workflows/tests.yml)

<img src="thumbnail.png" alt="Hills screen saver" width="240" align="right">

Hills is Chris Kent's OpenGL screen saver: a camera flies over a generated landscape of hills under a sky dome. The upstream is maintained on GitHub by Nick Zitzmann. This fork makes it build and run correctly on macOS 26, fixes four bugs in how it behaves inside the macOS screen-saver host, and adds tests and CI.

## What changed in this fork

The work was done between 21 and 23 August 2026: 28 commits, +1,305 / −166 lines, all through 9 pull requests.

| Area | Result |
| --- | --- |
| Platform | [Targets macOS 26 and drops the removed AGL framework](https://github.com/fiazsami/hills/commit/c173a15); the old 10.9 target no longer links |
| Host fixes | Four bugs in how the saver behaves inside the macOS screen-saver host (see below) |
| Tests | 11 test cases for the camera module ([`tests/test_camera.m`](tests/test_camera.m)), run by a single-binary harness; `Camera.m` has a 94% line-coverage gate |
| CI | [GitHub Actions](.github/workflows/tests.yml) runs the tests, builds the screen saver and the standalone app in Release and Debug, and verifies the ad-hoc code signature |

Most of Hills is drawing and host-integration code, which unit tests reach poorly. The host fixes were verified by running the saver on real displays. [`tools/verify_main_display.m`](tools/verify_main_display.m) is one of the checks used for that.

## Defects found and fixed

| Defect | Effect | Fix |
| --- | --- | --- |
| Drew on whichever display had focus, not the main one | Hills rendered nothing at all | [`ebbf600`](https://github.com/fiazsami/hills/commit/ebbf600), [`0b31a1d`](https://github.com/fiazsami/hills/commit/0b31a1d) |
| Ignored the host's resize | The full-screen saver was blank | [`5cb4c9e`](https://github.com/fiazsami/hills/commit/5cb4c9e) |
| Preference writes not flushed | Settings did not survive | [`72f0ca9`](https://github.com/fiazsami/hills/commit/72f0ca9) |
| Animation timer | Ran at 10,000 frames per second, then froze on one frame | [`4325f3c`](https://github.com/fiazsami/hills/commit/4325f3c) |

## Build and test

You need macOS 26 and Xcode, or the Xcode command-line tools for the tests alone.

- **Tests:** compile the sources under `tests` with clang, link with `-framework Foundation -framework OpenGL`, and run the binary. The exact steps are in [`.github/workflows/tests.yml`](.github/workflows/tests.yml).
- **Screen saver and app:**

  ```sh
  xcodebuild -project Hills.xcodeproj -target "Hills Screensaver" -configuration Release build
  xcodebuild -project Hills.xcodeproj -target "Hills Application" -configuration Release build
  ```

## How the work was done

The fixes, tests and reviews were written by coding agents (Claude Code) running inside a harness, under the direction of [Fiaz Sami](https://github.com/fiazsami). The harness provides guard hooks, a coverage ratchet and an independent verifier. Every change reached `master` through a pull request with CI; review findings, and the fixes they prompted, are recorded in pull request comments and commit messages. The harness and dated write-ups of what went wrong are in [fiazsami/screen-savers](https://github.com/fiazsami/screen-savers).

## Credits and licence

- Hills © 2006 Chris Kent.
- Upstream repository maintained by Nick Zitzmann ([nickzman/hills](https://github.com/nickzman/hills)).
- Licensed under the GPL, version 2 or later ([`GNU GPL.txt`](GNU%20GPL.txt)).
