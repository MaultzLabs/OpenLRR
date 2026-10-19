# OpenLRR Wine host filesystem isolation audit

The TEST app is kept separate from the user's normal Rock Raiders install.
That **does not** prove its Windows DLLs are confined to a secure Mac
sandbox. Wine commonly provides Windows drives mapped to macOS paths,
including `Z:` mapped to the host root. An untrusted AI-generated DLL could
potentially reach files outside the TEST app if the Wine configuration
exposes them.

`scripts/macos/wine-isolation-audit.py` is a **read-only diagnostic** for
these obvious filesystem escape paths. It checks:

- the fixed TEST app, Wine prefix, C: drive, game and DLL paths
- C: and other `dosdevices` drive mappings, especially host-root mappings
- symlinks in the Wine C: drive that resolve beyond the contained prefix
- the maximum allowed number of scanned paths; incomplete audits fail closed

Run the default report without modifying files or launching Wine:

```bash
python3 "$HOME/OpenLRR-Agent/scripts/macos/wine-isolation-audit.py"
```

Use `--require-safe-mappings` to fail if the audit detects a host-visible
mapping. Importantly, even with no unsafe mappings observed, the output
**always** records:

- `host_filesystem_isolation_verified: false`
- `unreviewed_candidate_autorun_allowed: false`

The `--require-automatic-execution-isolation` flag **always refuses** to
grant permission from a folder/symlink audit alone. This is intentional:
Windows DLL code running through Wine is still untrusted native code, and
filesystem links alone are not a security boundary.

The next true unattended execution solution needs a separately verified
VM/OS-level sandbox with bounded accessible files/network/process rights,
rollback snapshots, test data only, and approval/provenance checks. That
sandbox cannot be truthfully attested from this cloud GitHub session.

Existing explicitly supervised game tests are left unchanged. The audit
does not create executable approvals, run DLLs, install Wine, touch the
working game or upload local path information.
