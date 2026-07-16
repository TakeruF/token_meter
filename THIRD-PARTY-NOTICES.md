# Third-Party Notices

Token Meter redistributes the third-party components listed below in its binary
builds. Each component remains under its own license, reproduced here to satisfy
the attribution requirements of those licenses.

Build- and test-only dependencies (XcodeGen, xunit, Microsoft.NET.Test.Sdk) are
not redistributed and are therefore not listed.

---

## macOS

### Sparkle 2.9.4

<https://github.com/sparkle-project/Sparkle> — MIT License.
Embedded as `Sparkle.framework` inside `TokenMeter.app` and used for
in-app updates. Not present in Mac App Store builds (none are shipped).

```
Copyright (c) 2006-2013 Andy Matuschak.
Copyright (c) 2009-2013 Elgato Systems GmbH.
Copyright (c) 2011-2014 Kornel Lesiński.
Copyright (c) 2015-2017 Mayur Pawashe.
Copyright (c) 2014 C.W. Betts.
Copyright (c) 2014 Petroules Corporation.
Copyright (c) 2014 Big Nerd Ranch.
All rights reserved.

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```

Sparkle itself bundles the following components, whose notices it carries in its
own `LICENSE` file:

- **bsdiff 4.3** (`bspatch.c`, `bsdiff.c`) — Copyright 2003-2005 Colin Percival — BSD-2-Clause
- **sais-lite** (`sais.c`, `sais.h`) — Copyright (c) 2008-2010 Yuta Mori — MIT
- **Ed25519 portable C implementation** — Copyright (c) 2015 Orson Peters — zlib
- **SUSignatureVerifier.m** — Copyright (c) 2011 Mark Hamlin — BSD-2-Clause

The Ed25519 implementation's license additionally requires that altered source
versions be plainly marked as such and that its notice not be removed. Token
Meter does not alter it.

---

## Windows

### Microsoft.WindowsAppSDK 2.2.0

<https://github.com/microsoft/WindowsAppSDK> — Microsoft Software License Terms
(redistributable). Provides WinUI 3 and the Windows App SDK runtime.

### Microsoft.Data.Sqlite.Core 10.0.10

<https://github.com/dotnet/efcore> — MIT License. Copyright (c) .NET Foundation
and Contributors.

### SQLitePCLRaw.bundle_e_sqlite3 3.0.2

<https://github.com/ericsink/SQLitePCL.raw> — Apache License 2.0.
Copyright (c) Eric Sink.

Bundles the **SQLite** library itself, which is in the public domain
(<https://www.sqlite.org/copyright.html>).

---

## Not bundled

Token Meter reads log files written by Claude Code, Codex, and Copilot CLI, and
optionally queries Anthropic's usage endpoint. It does not redistribute any code
from those products, and is not affiliated with or endorsed by Anthropic,
OpenAI, GitHub, or Microsoft. Product names are the trademarks of their
respective owners.
