# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`socat-forward` is a single Bash script (`bin/socat-forward`, installed as the `socat-forward` command) that deploys and manages socat-based TCP/UDP port forwarding on a fresh Ubuntu server via systemd. Forwarding rules are supplied on the command line and may bind a specific local IPv4 address (multi-NIC / multi-IP). The repo is packaged like a GitHub project: `README.md`, `LICENSE` (MIT), `CHANGELOG.md`, `Makefile`, `.github/workflows/ci.yml`.

## Commands

```bash
make check                      # bash -n + shellcheck + version consistency (skips shellcheck if absent)
make version                    # print current version
make bump-version VERSION=x.y.z # bump VERSION + README badge (CHANGELOG entry must exist first)
make tag PUSH=1                 # create annotated vX.Y.Z tag (and push it)
make install                    # install bin/socat-forward to /usr/local/bin
sudo make install PREFIX=/usr/local

sudo socat-forward up -t 203.0.113.10 tcp:2222=22 udp:443=443 --dry-run
sudo socat-forward up -t 203.0.113.10 \
  tcp:2222=22 tcp:443=443 udp:443=443 \
  tcp:50530=50530 tcp:50960=50960        # deploy/update (merges with deployed rules)
sudo socat-forward up -r -t 203.0.113.10 tcp:2222=22   # replace the whole rule set (-r)
sudo socat-forward status                # aliases: list, ls
sudo socat-forward down [--purge]        # aliases: remove, uninstall
sudo socat-forward clean [--purge]       # aliases: reset; wipes stale units too
journalctl -u socat-fwd-443-udp -f
```

There is no automated test suite. Validate changes with `make check`, `--dry-run`, `systemd-analyze verify` on generated units, and a real install on a disposable host.

## CLI design

- Primary verbs: `up`, `status`, `down`, `clean`; the earlier names still work as aliases. `up`/`apply`/`install` → `do_install`, `status`/`list`/`ls` → `do_status`, `down`/`remove`/`uninstall` → `do_uninstall`, `clean`/`reset` → `do_clean`.
- Options accept short and long forms: `-t/--target`, `-f/--forward`, `-n/--dry-run`, `-u/--update`, `-r/--replace`, `-F/--force`, `-p/--purge`, `-V/--version`, `-h/--help`. `--target=IP` and `--forward=SPEC` work too.
- A bare argument matching `tcp:*`/`udp:*` is treated as a positional forwarding rule (equivalent to `-f`). This is why the rule grammar is `proto:[listen_ip:]lport=[target_ip:]tport` — an unquoted `->` would be eaten by shell redirection (bash would create a file); quoted `'tcp:2222->22'` is still accepted.
- Running with no arguments prints usage and exits 1.

## Architecture

- `parse_rules` → `parse_forward_spec` fills parallel arrays `RULE_PROTO/LIP/LPORT/TIP/TPORT`; they are the source of truth during install. Duplicate `(proto, listen_ip, port)` triples are rejected; the same port on different listen IPs is allowed and gets separate units.
- Unit naming (`unit_name`): wildcard bind → `socat-fwd-<port>-<proto>.service` (backward compatible); specific IP → `socat-fwd-<port>-<proto>-<ip with dots as dashes>.service`.
- Each unit runs `/usr/bin/socat -d -d` with `TCP4-LISTEN:<port>,bind=<ip>,fork,reuseaddr,backlog=128,keepalive` or `UDP4-LISTEN:<port>,bind=<ip>,fork,reuseaddr` plus `-T $UDP_IDLE_TIMEOUT`. Units use `DynamicUser=yes` and rely on `AmbientCapabilities=CAP_NET_BIND_SERVICE` to bind ports below 1024; preserve that when editing hardening or ExecStart.
- Deployed rules persist to `RULES_FILE` (`/etc/socat-forward/rules.conf`, pipe-delimited `proto|lip|lport|tip|tport`). `status`/`down` read it; `clean` ignores it and removes every `socat-fwd-*` unit from disk.
- `up` is incremental by default: `merge_existing_rules` loads `RULES_FILE` and unions it with the rules from the command line, keyed by `(proto, lip, lport)` — a command-line rule wins over a deployed rule with the same listen endpoint, everything else is preserved. `-r/--replace` skips the merge. Because of this, `reconcile_stale_units` normally has nothing to remove; it only deletes stale units in replace mode (or leftovers from the old naming scheme).
- Preflight in `do_install`: root → systemd → rule validation/duplicates → listen IP exists on a local NIC → loop detection (target equals any local IPv4 or the host's public IPv4) → port occupancy. `-F/--force` bypasses the last three checks.
- Package handling is deliberately light (`ensure_socat`): if `SOCAT_BIN` exists, apt is not touched at all; if missing, only `apt-get update` + `apt-get install socat` run (no `upgrade`); `apt-get update` + `upgrade` + install happen only with `-u/--update`. Do not reintroduce an unconditional upgrade.
- Port conflict checking is bind-address aware (`port_listeners` parses `ss -4 -H -lntp/-lnup "sport = :<port>"`, column 4): a listener on another specific IP is not a conflict; a `0.0.0.0` listener conflicts with both wildcard and specific-IP rules; listeners owned by `socat` are tolerated so reruns pass.
- Dry-run must stay side-effect free: mutations go through `run()`, `ensure_socat`/`write_unit`/`write_state_file`/`remove_state_file` have dry-run branches. Read-only checks (`ss`, `ip`, `curl`, `/dev/tcp`) may run in dry-run.
- The script sources cleanly: `main` is guarded by `[[ ${BASH_SOURCE[0]} == $0 ]]`; tests can `source` it, set `UNIT_DIR`/`RULES_FILE` to temp paths, and call `write_unit`/`reconcile_stale_units` directly.

## Gotchas

- `set -Eeuo pipefail` is active. Do not use `cmd | grep -q` for checks (SIGPIPE under pipefail gives false negatives); capture output into a variable. The ERR trap ignores exit code 141 so piping the script's output into `head` stays quiet.
- `ss -p` needs root to show process names; install/uninstall require root anyway.
- `DynamicUser` and the capability/hardening directives require a recent systemd (Ubuntu 22.04+); verify generated units with `systemd-analyze verify`.
- Aliyun public EIPs are NATed and not on a local NIC, so they cannot be used as listen IPs; only `0.0.0.0` or actual interface addresses pass `check_listen_ips_exist`.
- The loop check uses external IP-echo endpoints and silently skips when unreachable.
- Keep `README.md` and `CHANGELOG.md` in sync when changing CLI behavior. The version lives in `VERSION` at the top of the script; `scripts/version.sh check` (run by `make check` and CI) enforces that it matches the README badge and the newest numeric CHANGELOG heading. Use `make bump-version VERSION=x.y.z` to bump and `make tag PUSH=1` to tag releases — do not hand-edit the version in only one place.
