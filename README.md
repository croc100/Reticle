# Centree

> The open-source, redaction-first screenshot tool for macOS. Inspired by ShareX.

**한국어** | [English](#english)

---

## 한국어

### Centree란?

Centree는 macOS용 오픈소스 스크린샷 도구입니다. 기존 도구들과 달리 **라이브 마스킹**을 핵심으로 설계했습니다. 반복적으로 같은 화면을 캡쳐하는 개발자, 튜토리얼 제작자, 영업 데모 담당자를 위해 만들었습니다.

### 왜 Centree인가?

| 기능 | Centree | CleanShot X | Shottr | Flameshot |
|---|:---:|:---:|:---:|:---:|
| 영역/창/전체 화면 캡쳐 | ✅ | ✅ | ✅ | ✅ |
| 캡쳐 후 마크업 | ✅ | ✅ | ✅ | ✅ |
| **라이브 마스킹 (캡쳐 전 영역 지정)** | ✅ | ❌ | ❌ | ❌ |
| **앱별 마스크 프로파일** | ✅ | ❌ | ❌ | ❌ |
| **자동 PII 감지 (Vision)** | ✅ | ❌ | ❌ | ❌ |
| 오픈소스 (MIT) | ✅ | ❌ | ❌ | ✅ |
| 무료 | ✅ | ❌ | ✅ | ✅ |

### 스크린샷

> 📸 스크린샷 준비 중 — v0.1 베타 출시 후 추가 예정

### 시스템 요구사항

- macOS 13 Ventura 이상
- Apple Silicon 또는 Intel Mac

### 설치

#### Homebrew (권장, v0.1 출시 후)

```bash
brew install --cask centree
```

#### 직접 다운로드

[GitHub Releases](https://github.com/centree/centree/releases) 페이지에서 최신 `.dmg`를 다운로드하세요.

### 주요 기능

- **영역 / 창 / 전체 화면 캡쳐** — 글로벌 핫키로 즉시 실행
- **라이브 마스킹** — 캡쳐 전에 민감 영역을 미리 지정, 매번 자동 적용
- **라이브 드로잉** — 화살표, 박스, 펜, 텍스트, 하이라이트
- **캡쳐 후 에디터** — 마스크·도형 추가/제거/조정
- **클립보드 + 로컬 저장** — 파일명 토큰 패턴 지원

### 빌드 방법

[CONTRIBUTING.md](CONTRIBUTING.md)를 참고하세요.

---

## English

### What is Centree?

Centree is an open-source macOS screenshot tool built around **live masking** as a first-class feature. Unlike other tools that require you to blur sensitive areas after every capture, Centree lets you define mask boxes ahead of time — they apply automatically on every screenshot.

Built for developers, tutorial creators, and sales demo folks who take the same screenshot over and over.

### Why Centree?

| Feature | Centree | CleanShot X | Shottr | Flameshot |
|---|:---:|:---:|:---:|:---:|
| Region / window / full-screen capture | ✅ | ✅ | ✅ | ✅ |
| Post-capture annotation | ✅ | ✅ | ✅ | ✅ |
| **Live masking (pre-capture region lock)** | ✅ | ❌ | ❌ | ❌ |
| **Per-app mask profiles** | ✅ | ❌ | ❌ | ❌ |
| **Auto PII detection (Vision framework)** | ✅ | ❌ | ❌ | ❌ |
| Open source (MIT) | ✅ | ❌ | ❌ | ✅ |
| Free | ✅ | ❌ | ✅ | ✅ |

### Screenshots

> 📸 Screenshots coming with v0.1 beta

### Requirements

- macOS 13 Ventura or later
- Apple Silicon or Intel Mac

### Installation

#### Homebrew (recommended, after v0.1 release)

```bash
brew install --cask centree
```

#### Direct download

Download the latest `.dmg` from the [GitHub Releases](https://github.com/centree/centree/releases) page.

### Features

- **Region / window / full-screen capture** — global hotkeys, works instantly
- **Live masking** — pre-define sensitive areas once, applied automatically every time
- **Live drawing** — arrows, boxes, pen, text, highlight
- **Post-capture editor** — add/remove/adjust masks and annotations
- **Clipboard + local save** — filename token patterns (`%date%_%app%_%counter%.png`)

### Building from source

See [CONTRIBUTING.md](CONTRIBUTING.md).

---

## Architecture

Centree is structured as a set of Swift library modules managed by Swift Package Manager, with the macOS app target in an Xcode project. See [`Package.swift`](Package.swift) for the module dependency graph.

```
Capture → Pipeline → Effects → Output
              ↑
          WorkflowProfile (hotkey config)
```

## Roadmap

| Version | Features |
|---|---|
| v0.1 | Region/window/full capture, live masking, live drawing, clipboard/save |
| v1.0 | Per-app mask profiles, Smart Mask (Vision PII), scroll capture, uploaders (Imgur/S3) |
| v2.0 | AI redaction, team profile sharing, plugin SDK |

## Contributing

Pull requests are welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) first.

## License

[MIT](LICENSE) © Centree Contributors
