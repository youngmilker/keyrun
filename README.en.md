<p align="right"><a href="./README.md">简体中文</a> | English</p>

# KeyRun Windows tools

The supported entry is the local `keyrun.ps1` file. It reads ordinary resources through
`source-config.json → resource-loader.ps1 → keyrun.ps1` and supports Windows PowerShell 5.1.
The shipped configuration defaults to HTTP. Run -Mode local explicitly to select disk files;
the selection persists in source-config.json until another switch. Local mode needs no HTTP service. Resource reads and path diagnosis
need no administrator rights. Use -Install to run the restored Windows processing flow.
macOS/Linux compatibility is deferred; the shell installer remains disabled.

```powershell
.\switch-source.ps1 -Mode local
powershell.exe -NoProfile -File .\keyrun.ps1
.\keyrun.ps1 -ResourcePath index.html
.\keyrun.ps1 -ResourcePath source-config.json -Format Json
.\keyrun.ps1 -ResourcePath LICENSE -Format Bytes
.\keyrun.ps1 -DiagnoseIdeaPaths
.\keyrun.ps1 -DiagnoseIdeaPaths -PropertiesPath 'C:\path\to\idea.properties'

.\switch-source.ps1 -Mode http -HttpBase 'https://your-host.example/keyrun' -TimeoutSeconds 20
.\keyrun.ps1 -ResourcePath README.md
.\switch-source.ps1 -Mode local
```

Replace the example HTTP root with a resource server you control. Executable tools always
come from the local checkout; downloaded PowerShell script text is never executed.
Relative local roots resolve against the Loader directory, independently of the working directory.
Use `-LocalRoot` to override the root. Text is strict UTF-8, with or without a BOM.
The byte interface preserves binary data. Invalid paths, missing files, invalid configuration,
HTTP error statuses, connection failures and timeouts raise explicit errors.
Redirects are rejected; configure the final HTTP/HTTPS directory URL without credentials, query or fragment.
`-OpenPage` opens the local page or the configured HTTP page. Browser icons still use third-party URLs.

The original `ps1` file is now a standalone server bootstrap;
use `keyrun.ps1` with Windows PowerShell's `-File` option.
The read-only path diagnostic checks every discovered properties file by default.
Use -PropertiesPath to inspect just one file. Results are labeled separately;
a failed file does not prevent the remaining files from being checked.
Execution policy remains under your or your organization's control.

## Restored Windows processing flow

Back up IDE settings and existing license files, close all JetBrains IDEs, then run:

```powershell
.\switch-source.ps1 -Mode local
powershell.exe -NoProfile -File .\keyrun.ps1 -Install
```

Installation requests administrator rights and relaunches the local scripts/install.ps1 file,
preserving the optional -OpenPage parameter. It preloads all 25 resources before any environment,
work-directory or IDE changes. The original flow clears product VM_OPTIONS variables,
deploys Agent files, changes relevant startup options and writes .key resource bytes.
The source root must contain ja-netfilter/ and licenses/. Use a trusted source: Agent JARs will
be loaded by the IDE. No remote PowerShell script is downloaded or executed.
The original name/date prompts do not regenerate the static key resources.
File-write success does not verify the software's licensing outcome; reopen the IDE to check.

scripts/install.ps1 is restored and uses the Loader. The old duplicate test_script.ps1 and
the shell installer remain disabled. tests/test-install-resource-wiring.ps1 verifies the
wiring in temporary directories without invoking Main, UAC, or installed IDE changes.
Original backups must not be executed.

## Standalone Windows server entry

The project maintainer runs switch-source.ps1 -Mode http -HttpBase with the actual server root.
This saves the source config and regenerates ps1 with the root URL and matching SHA-256 values
for the four required code files. Publish the complete project to that root; regenerate before
deploying code updates. The server only needs to serve static files.

End users can invoke the deployed Windows bootstrap without a pre-downloaded local project:

```powershell
irm https://liyangxu1.github.io/keyrun/ps1 | iex
```

The old default URL is an example and returned 404 when checked on 2026-10-14. Replace it with
an actual trusted deployment. The bootstrap prepares an isolated temporary project, verifies
matching code bytes, runs the Windows local installer with HTTP resources, then cleans up.
It does not use source files or configuration from the caller's working directory.
Embedded hashes detect mismatched deployments; the initial bootstrap is still supplied by the
chosen server and must be trusted. Local mode remains selected after -Mode local, until -Mode http
is executed again. End users of the deployed entry need no local switch command.

The macOS/Linux curl examples require the server to provide independently compatible shell code;
this repository's shell entry remains disabled until the deferred compatibility work is completed.
tests/test-server-bootstrap.ps1 uses only a loopback server and harmless fixture code, with no
real installation or IDE changes.

See [the refactor report](./SOURCE-REFACTOR.md) and `tests/test-resource-loader.ps1`.
Source code is licensed under [GNU GPL v3](./LICENSE).
Use [JetBrains' official channels](https://www.jetbrains.com/) for software licensing.
