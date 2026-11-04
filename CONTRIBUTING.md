# Contributing to Dustnado

Thanks for helping! Dustnado deletes files, so the rules below keep it **safe, predictable and easy to review**.

## Ground rules
1. **Safe by default.** Only clean things that Windows or the app re-creates automatically (caches, temp files, logs). Never touch personal files (Documents, Downloads, Desktop, Pictures, Videos, Music) or app data that holds logins, settings or user content.
2. **Everything goes through the engine.** Deletions use `Invoke-Wipe` (which uses the native worker, skips locked files, never follows junctions and passes the `Test-SafePath` guard). Do not add raw `Remove-Item -Recurse` calls.
3. **Scan mode must stay honest.** Any new task must also work with `/scan` (measure only, delete nothing).
4. **One file.** The project ships as a single `Dustnado.bat`. Keep it ASCII-only (use `[char]0x...` for symbols) with CRLF line endings.
5. **Windows PowerShell 5.1 compatible.** No PowerShell 7-only syntax.
6. **Mind PowerShell gotchas.** `[math]::Min/Max` with an int and a double silently rounds - cast to `[double]` or use `Clamp01`. Avoid `Select-Object -Unique` on big lists (use a `HashSet`). Avoid `+=` on large arrays.

## Adding a cleanup target
Most additions are one line inside an existing task, for example a new app cache:

```powershell
$script:TaskFreed = Invoke-Wipe -Contents @("$($p.LA)\MyApp\Cache")
```

Or a whole new task: `Add-Task 'Name (max ~32 chars)' <weight> { ...action... } <enabled-flag>`.
Set `$script:TaskNote` for the short note shown in the list, and `Skip-Task 'reason'` if it does not apply.

## Testing
- **Syntax:** the CI workflow parses the embedded PowerShell and checks ASCII/CRLF on every push.
- **Manual:** always run `Dustnado.bat /scan` first, then a real run on a test VM. Include the saved report when you open a PR.
- Please test on at least Windows 10 or 11 and mention which.

## Pull requests
Keep PRs small and focused, explain *why* each new path is safe to delete, and update `CHANGELOG.md`.

## Releasing (maintainer)
1. Bump `$AppVer` in `Dustnado.bat` and add an entry to `CHANGELOG.md`.
2. Commit and push to `main`.
3. Tag and push: `git tag -a v1.2.3 -m "Dustnado v1.2.3"` then `git push origin v1.2.3`.

The **Release** workflow checks that the tag matches `$AppVer`, then publishes the GitHub Release with `Dustnado.bat` and `Dustnado.bat.sha256` attached. The README download buttons use `releases/latest/download/Dustnado.bat`.
