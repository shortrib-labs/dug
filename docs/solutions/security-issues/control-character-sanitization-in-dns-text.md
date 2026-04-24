---
title: "Sanitize all C0 control characters in attacker-controlled DNS text, not just ESC"
category: security-issues
date: 2026-04-23
tags: [security, terminal-injection, control-characters, ede, dns, sanitization, rfc-8914]
related_components: [DNSMessage, ExtendedDNSError, PrettyFormatter]
severity: P2
---

# Sanitize all C0 control characters in attacker-controlled DNS text, not just ESC

## Problem

The existing ESC byte sanitization in `PrettyFormatter.styleLine()` strips `\u{1B}` to prevent ANSI escape injection in terminal output. However, EDE (Extended DNS Error, RFC 8914) extra text introduced a new source of attacker-controlled text that enters the system at parse time, not display time. This text can contain any byte value, and terminal injection is not limited to ESC sequences.

## Root Cause

The C0 control character range (0x00-0x1F) and DEL (0x7F) include multiple characters that can manipulate terminal behavior beyond ANSI escape sequences:

| Character | Hex | Terminal effect |
|-----------|-----|----------------|
| BEL | 0x07 | Audible bell; in some terminals, triggers OSC sequences |
| BS | 0x08 | Backspace — can overwrite displayed characters |
| HT | 0x09 | Tab — layout disruption |
| VT | 0x0B | Vertical tab — cursor movement |
| FF | 0x0C | Form feed — screen clear in some terminals |
| CR | 0x0D | Carriage return — overwrite current line |
| ESC | 0x1B | Escape sequences (ANSI SGR, cursor movement, OSC) |
| DEL | 0x7F | Delete — character removal |

An attacker controlling a DNS resolver (or performing a man-in-the-middle on unencrypted DNS) can set the EDE extra text field to contain arbitrary bytes. If these bytes reach the terminal unsanitized, they can manipulate the display, overwrite output, trigger sounds, or in extreme cases exploit terminal emulator vulnerabilities via crafted OSC sequences.

The existing `PrettyFormatter.styleLine()` ESC stripping only handles display-time sanitization for one byte value. EDE extra text needed parse-time sanitization covering the full dangerous range.

## Solution

Sanitize EDE extra text at parse time in `DNSMessage.parseEDNSOptions()`, filtering to only printable characters (0x20-0x7E plus valid multi-byte UTF-8):

```swift
extraText = String(data: textBytes, encoding: .utf8)?
    .unicodeScalars
    .filter { $0.value >= 0x20 && $0.value != 0x7F }
    .map { Character($0) }
    .reduce(into: "") { $0.append($1) }
```

This approach:
- Strips all C0 control characters (0x00-0x1F), not just ESC
- Strips DEL (0x7F)
- Preserves printable ASCII (0x20-0x7E)
- Preserves valid multi-byte UTF-8 (codepoints above 0x7F that are not DEL)
- Runs at parse time so no downstream consumer can forget to sanitize

## Key Insights

- **Parse-time vs. display-time sanitization.** `PrettyFormatter.styleLine()` sanitizes at display time — it strips ESC from text that has already been stored. For new data paths like EDE, sanitizing at parse time is strictly stronger: the dangerous bytes never enter the data model. Both layers should exist (defense in depth), but parse-time is the primary defense.
- **ESC is not the only dangerous control character.** The initial ESC-stripping pattern was correct for its scope (preventing ANSI sequence injection) but insufficient for arbitrary attacker-controlled text. BEL can trigger terminal alerts, BS/CR can overwrite displayed output, and crafted sequences combining control characters with printable text can create convincing spoofed output.
- **DNS text fields are attacker-controlled.** EDE extra text is set by the responding nameserver. Unlike record data which comes from zone files (controlled by domain owners), EDE comes from the resolver itself — a compromised or malicious resolver can set arbitrary extra text. TXT records, CAA values, HINFO strings, and NAPTR fields have similar risk profiles.
- **Filter to allowlist, not blocklist.** Rather than stripping specific known-bad bytes (ESC, BEL, BS...), filter to the known-good range (printable ASCII + valid UTF-8 above 0x7F). This handles future discoveries of dangerous control characters automatically.

## Prevention Strategies

### Adding new DNS text data paths

- **Sanitize at parse time for new text fields.** When adding parsing for any DNS field that contains human-readable text (TXT, HINFO, CAA, NAPTR, EDE extra text), strip C0 control characters and DEL at the point where bytes become strings.
- **Use allowlist filtering.** `$0.value >= 0x20 && $0.value != 0x7F` is the standard check. Apply via `.unicodeScalars.filter { ... }` for Unicode-aware handling.
- **Keep display-time sanitization as defense in depth.** `PrettyFormatter.styleLine()` ESC stripping remains valuable as a second layer — it catches any path where unsanitized text reaches the terminal.

### Testing sanitization

- Construct test data with embedded control characters (BEL 0x07, ESC 0x1B, CR 0x0D, NUL 0x00)
- Assert the parsed string contains no bytes below 0x20 and no 0x7F
- Assert legitimate text surrounding the control characters is preserved
- Test empty extra text (nil) and extra text that is entirely control characters (becomes empty string or nil)

## Related Documentation

- [ANSI escape injection in DNS rdata](ansi-escape-injection-in-dns-rdata.md) — the display-time ESC stripping pattern this extends
- [OPT pseudo-record parsing](../integration-issues/opt-pseudo-record-parsing-and-ede-extraction.md) — the OPT/EDE parsing that introduced this data path
- [Encrypted DNS transport security fixes](encrypted-dns-transport-security-fixes-2026-04-18.md) — related untrusted input handling in DNS transport layer
- RFC 8914 section 4: "The EXTRA-TEXT field is a UTF-8 string" — no restriction on content beyond UTF-8 encoding
