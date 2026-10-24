# Server Performance Stats

Goal of this project is to write a script to analyse server performance stats.

`server-stats.sh` is a single, dependency-light Bash script that prints a readable
report of the essential health metrics of any Linux server.

## Requirements covered

- Total CPU usage
- Total memory usage (used vs free, including percentage)
- Total disk usage (used vs free, including percentage)
- Top 5 processes by CPU usage
- Top 5 processes by memory usage
- Stretch goals: OS version, kernel/architecture, uptime, load average, CPU core
  count, process count, swap usage, all mounted filesystems, logged in users and
  failed login attempts

## Usage

Copy the script to the server, make it executable and run it:

```bash
scp server-stats.sh user@server:/tmp/
ssh user@server 'chmod +x /tmp/server-stats.sh && /tmp/server-stats.sh'
```

Or locally:

```bash
chmod +x server-stats.sh
./server-stats.sh
```

### Options

| Option        | Description                                  |
| ------------- | -------------------------------------------- |
| `--top N`     | Show `N` processes per list (default: `5`)   |
| `--no-color`  | Disable ANSI colors (useful for logs)        |
| `-h`, `--help`| Show usage                                   |

`CPU_SAMPLE` (default `1`) controls how many seconds CPU usage is sampled for:

```bash
CPU_SAMPLE=3 ./server-stats.sh
```

## Sample output

```
=============== SERVER PERFORMANCE STATS ===============

SYSTEM
------------------------------------------------------------
  Hostname           web-01
  OS                 Ubuntu 24.04.1 LTS
  Kernel             6.8.0-45-generic (x86_64)
  Uptime             up 12 days, 4 hours, 8 minutes
  Load average       0.42, 0.31, 0.28
  CPU cores          4
  Processes          187
  Current time       2026-10-24 13:30:02 UTC

CPU USAGE
------------------------------------------------------------
  Total      [####--------------------------]    12.4%   (sampled over 1s)
  Cores              4
  Load average       0.42 0.31 0.28  (1, 5, 15 min)

MEMORY USAGE
------------------------------------------------------------
  Memory      2.1 GiB / 7.7 GiB   [########----------------------]    27.1%  free: 5.6 GiB
  Swap       12.0 MiB / 2.0 GiB   [------------------------------]     0.6%  free: 2.0 GiB

DISK USAGE (/)
------------------------------------------------------------
  Root (/)   23.5 GiB / 78.2 GiB  [#########---------------------]    30.0%  free: 54.7 GiB
  Filesystem         /dev/sda1 -> /
  Available          54.7 GiB

MOUNTED FILESYSTEMS
------------------------------------------------------------
  FILESYSTEM               SIZE     USED     AVAIL    USE%   MOUNTED ON
  /dev/sda1                78G      24G      55G      30%    /
  /dev/sdb1                500G     120G     380G     24%    /data
...
```

## What the script reads

| Stat              | Source                                                        |
| ----------------- | ------------------------------------------------------------- |
| CPU usage         | Two samples of `/proc/stat`, computing idle vs total deltas   |
| Memory            | `/proc/meminfo` (`MemTotal` vs `MemAvailable`)                |
| Disk              | `df -P /` (plus `df -Ph` for the mounted-filesystem table)    |
| Processes         | `ps -eo ... --sort=-pcpu` / `-pmem` (with a `ps aux` fallback)|
| Load / uptime     | `/proc/loadavg`, `uptime`, `/proc/uptime`                     |
| Users             | `who`                                                         |
| Failed logins     | `/var/log/auth.log`, `/var/log/secure`, `journalctl`, `lastb` |

## Notes

- **Linux only.** The script requires `/proc/stat` and `/proc/meminfo`; it exits
  with a clear message on macOS/BSD.
- **No root required** for CPU, memory, disk, process and OS stats. Failed-login
  counts may show "unavailable" unless run as root (or the user can read the auth
  log / journal).
- **Dependencies:** `bash`, `coreutils`, `procps` / `ps`, `awk`, `df`. These ship
  with every mainstream Linux distribution.
- Colors are enabled only when stdout is a terminal, so redirecting to a file
  produces clean text.

## Exit codes

| Code | Meaning                              |
| ---- | ------------------------------------ |
| 0    | Report generated                     |
| 1    | Not Linux / `/proc` not available    |
| 2    | Invalid command-line argument        |
# Server-Performance-Stats
