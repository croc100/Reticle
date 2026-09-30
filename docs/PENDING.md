# Pending work

Written 2026-10-01, picking the project back up after a pause. Everything here was found
by reading the code and running CI; nothing in this list has been verified on a Mac,
because the session that produced it ran on Windows with no Swift toolchain.

**Read this first:** CI (`macos-14`) covers `swift build`, `swift test`, and SwiftLint. It
cannot launch the app, so ScreenCaptureKit, the overlay, permission prompts, and anything
involving a window server are unverified by definition. Every item below is tagged with
which of the two it needs.

---

## 1. Runtime verification owed on PR #1

[PR #1](https://github.com/croc100/Reticle/pull/1) fixes five bugs in the redaction and
filename paths. All 87 tests pass in CI, but the fixes change where pixels land on screen,
and no test can confirm that end to end. **Needs a Mac.**

- [ ] **Static Mask placement.** Settings → draw a mask over a known screen region. Then
  take: a full-screen shot, a region shot, a window shot, and a shot on a secondary
  display. The mask must land on the same content every time. Before the fix it was
  correct only for a full-screen capture of a display sitting at the screen origin — this
  is the bug most likely to still be subtly wrong, because the fix threads
  `sourceRect.origin` through and each capture path supplies that origin separately.
- [ ] **Blur and pixelate content.** Mask a region with recognisable content near the top
  of the screen, using blur, then pixelate. The masked area must be a blurred version of
  *what was under it* — not of the mirrored position lower down. Solid fill was never
  affected, so it is not a useful check here.
- [ ] **Multi-monitor.** Specifically a display with a negative origin (one placed left of
  or above the main display). The offset maths is signed and untested against that.
- [ ] **PII redaction on real text.** Open something with an email address and a phone
  number, capture with `autoRedactPII` on. Confirm both are covered, and — the point of
  the pattern fix — that lines containing only ordinary numbers (a year, a port, a version)
  are now left alone.
- [ ] **Retina vs non-Retina.** `scaleFactor` conversion is unit-tested, but only against
  synthetic values. Worth one capture on a 1× external display.

### What PR #1 changed, for reviewing it

| Bug | Where | Symptom |
|---|---|---|
| Rect used in two opposing origin conventions | `Sources/ReticleEffects/MaskRenderer.swift` | Blur/pixelate sampled the vertically mirrored region and pasted it over the correct spot |
| Static masks ignored the capture origin | `App/CaptureCoordinator.swift` | Masks landed at the wrong offset for region, window, and secondary-display captures |
| Phone pattern matched any 4 digits | `Sources/ReticleVision/PIIDetector.swift` | `2026`, `8080`, `1920`, `1080p`, `9999` all read as phone numbers, and a match hides the whole OCR line |
| Card numbers had no checksum | `Sources/ReticleVision/PIIDetector.swift` | Any 16-digit run starting with `4` read as a Visa |
| Extension and payload decided separately | `Sources/ReticlePipeline/LocalFileOutput.swift` | WebP request on a system with no WebP encoder wrote PNG bytes into a `.webp` file |
| No collision handling | `Sources/ReticlePipeline/LocalFileOutput.swift` | A pattern without `%counter%` silently overwrote the previous capture |
| Filename tokens unsanitised | `Sources/ReticleNaming/NameParser.swift` | A `/` in an app or machine name added a directory level that does not exist, so the write failed |

---

## 2. Bugs found but not yet fixed

Now filed as issues — [#2](https://github.com/croc100/Reticle/issues/2),
[#3](https://github.com/croc100/Reticle/issues/3),
[#4](https://github.com/croc100/Reticle/issues/4). The detail is kept here as well since
this is the document you read first; the issues are where progress gets tracked.

The two `S3Uploader` ones are **CI-verifiable** — SigV4 is pure logic and AWS publishes
test vectors, so they can be fixed and proven without a Mac.

### 2a. SigV4 signature breaks on any key needing percent-encoding — [#2](https://github.com/croc100/Reticle/issues/2)

`Sources/ReticleUploaders/S3Uploader.swift:105` and `:192`

```swift
let canonicalURI = url.path.isEmpty ? "/" : url.path
```

`URL.path` **decodes** percent-encoding. The request line sends the encoded path while the
signature is computed over the decoded one, so they disagree and S3 answers
`SignatureDoesNotMatch`.

The generated object name (`objectFilename()`) only uses safe characters, which is why this
has not been noticed — but `config.keyPrefix` is user-supplied. A prefix containing a space
or any non-ASCII character makes **every upload fail**.

Separately, `.urlPathAllowed` is the wrong character set for SigV4: it leaves `+ , ; = : @ ! $ & ' ( ) *`
unencoded, while AWS requires everything outside `A-Z a-z 0-9 - _ . ~` (and `/`) to be
encoded. Fix both together by encoding the key once with a strict unreserved set and
building the canonical URI from that same string, rather than round-tripping through `URL`.

### 2b. Force unwraps on user-supplied strings can crash the app — [#3](https://github.com/croc100/Reticle/issues/3)

`Sources/ReticleUploaders/S3Uploader.swift:88, 89, 95, 145, 147, 154`

`:154` is the worst:

```swift
return URL(string: config.publicURLTemplate + encodedKey)!
```

`publicURLTemplate` is typed into Settings by hand. A malformed value crashes the app on
the next upload. The bucket and region interpolations above have the same shape.

SwiftLint has `force_unwrapping` enabled as an opt-in rule, so these are already being
reported as warnings — CI does not run `--strict`, so nothing fails on them.

### 2c. `testConnection` duplicates the signing logic — folded into [#2](https://github.com/croc100/Reticle/issues/2)

`Sources/ReticleUploaders/S3Uploader.swift:81–135` repeats about 40 lines of
`buildSignedRequest`. Two copies of a signing routine will drift, and fixing 2a means
fixing it in both places. Worth extracting one `canonicalRequest`/`signature` helper that
both paths call — that refactor is also what makes the SigV4 test vectors easy to assert
against.

### 2d. `ClipboardOutput` does not do what its comment says — [#4](https://github.com/croc100/Reticle/issues/4)

`Sources/ReticlePipeline/ClipboardOutput.swift:7`

```
/// Writes both `TIFF` and `PNG` representations so apps that request either type
```

It writes `NSImage` via `writeObjects`, which offers TIFF and PDF — not PNG. Either the
comment is wrong, or the intent was real and PNG should be added explicitly (some targets
do prefer PNG off the pasteboard). **Deciding this needs a Mac** — paste into Slack and
Figma and see what arrives. The comment should be corrected either way.

---

## 3. Test coverage gaps

87 tests now, up from 13. The gaps left are the parts that need a window server or a
network, plus two that are pure logic and simply untested.

**Reachable from CI — worth doing next:**

- `ReticleUploaders` has **no test target at all**. SigV4 signing, the custom HTTP
  uploader's dot-path response parsing (`CustomHTTPUploader.extractURL`), and the multipart
  body construction are all pure functions. The dot-path parser in particular handles
  array indices and missing keys and has never been exercised.
- `ReticleWorkflow` (48 lines) and `ReticleCore`'s `AfterCaptureOption` / `AppSettings`
  round-tripping are untested.
- `ReticleNaming` counter behaviour under concurrent captures — `NameParser` takes a
  `() -> Int` closure and is marked `@unchecked Sendable`, which is a claim nothing checks.

**Needs a Mac:**

- `ReticleOverlay` (4,132 lines) — entirely untested. The annotation engine is the largest
  untested surface in the project by a wide margin.
- `ReticleCapture` — only the non-SCStream types are tested, as the target's comment says.
- `ReticleRecorder` — MP4/GIF encoding is untested; the 0.1.0 changelog already flags
  multi-monitor region recording as producing unexpected crops.

---

## 4. Structural debt

- `App/SettingsView.swift` — 1,460 lines. Over the SwiftLint `file_length` error threshold
  of 800, but `App/` is not in the lint `included` list so it is never checked.
- `Sources/ReticleOverlay/OverlayView.swift` — 1,443 lines, explicitly excluded in
  `.swiftlint.yml`.
- `Sources/ReticleOverlay/Editor/Annotation.swift` — 928 lines, also excluded.
- **`App/` is absent from `.swiftlint.yml`'s `included` list entirely.** 4,148 lines of the
  app target are unlinted, which is why nothing complained about `SettingsView`. Adding it
  will surface a backlog; worth doing deliberately rather than as a side effect.
- `Sources/ReticleOverlay/OverlayWindow.swift` is a stub whose own comment says it is "kept
  as a placeholder for Phase 3". Either finish it or delete it.

---

## 5. Documentation that no longer matches the code

- **`CHANGELOG.md` stops at 0.1.0.** `App/Info.plist` says `0.5.0` (build 5), and there are
  release commits for 0.2.0 through 0.5.0. Four versions are missing.
- **The 0.1.0 "Known limitations" section is stale** — it says "No auto-update yet (Sparkle
  planned for v1.0)", but Sparkle shipped in 0.5.0.
- **`README.md:155` marks Vision PII auto-detection as 🔜.** It is implemented
  (`Sources/ReticleVision/PIIDetector.swift`), wired up
  (`App/CaptureCoordinator.swift`, via `PIIRedactionTask`), and has a settings UI as of
  commit `c192015`. It ships.
- **README's "Coming Soon" and the feature tables disagree.** Google Drive/Dropbox and the
  URL shortener are marked 🔜 in the Uploads table (correctly — neither exists in
  `Sources/ReticleUploaders`) but are missing from "Coming Soon", which lists only the
  notarized DMG and QR code.
- `docs/` holds only `assets/`; all prose lives in `site/src/pages/docs`. Worth noting so
  nobody looks for docs in the obvious place and concludes there are none.

---

## 6. Roadmap items not started

| Item | Notes |
|---|---|
| **Notarized DMG** | Needs a paid Apple Developer ID. Removes the `xattr -dr com.apple.quarantine` step from every install, which is the single biggest install-friction item. |
| **QR code** | Generate and scan from a captured image. `CIQRCodeGenerator` and `VNDetectBarcodesRequest` cover both; the detection half is CI-testable against a generated image. |
| **Google Drive / Dropbox upload** | Both need OAuth, so a token flow and secure storage — a larger job than the existing uploaders, none of which hold a refresh token. |
| **URL shortener** | Smallest of the four. Slots in behind the existing `Uploader` protocol. |

---

## Suggested order

1. **Merge PR #1** once the runtime checks in §1 pass on a Mac.
2. **Fix [#2](https://github.com/croc100/Reticle/issues/2) and [#3](https://github.com/croc100/Reticle/issues/3)** — real bugs, fully provable in CI, no Mac needed. Add the
   `ReticleUploaders` test target from §3 in the same pass, since 2c's refactor is what
   makes the SigV4 vectors testable.
3. **Fix §5** — documentation only, no risk, and it stops the README from
   under-selling a feature that already ships.
4. **Then decide** between §4 (refactoring) and §6 (features). §4 is the better
   investment if `ReticleOverlay` is going to keep growing; §6 is the better one if the
   next release needs a headline.
