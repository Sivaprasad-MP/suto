# Suto fixes and usage

The corrected local script is `suto.sh`; the original is saved as `suto.sh.bak`.
This directory is a checkout of `Sivaprasad-MP/suto`. The original GitHub script
matched the saved local backup byte for byte. Local backup files are excluded
from Git.

Run from this directory:

```bash
bash suto.sh example.com --ports 80,443,8080,8443 --threads 10
```

Replace `example.com` with an authorized target. Select ports permitted by the
program. The default probes only 80 and 443. The port list probes HTTP and HTTPS;
it does not discover arbitrary TCP services or scan every possible port.

A hostname can exist without a website. A missing HTTP response can mean a
non-web service, a different port, filtering, a timeout, or a DNS problem. It does
not establish a dangling domain or a takeover. Check A, AAAA and CNAME records
separately, then inspect authorized ports if the program allows port scanning.
An HTTP 404/403 is still an HTTP response and is retained.

Outputs:

- `alive_urls.txt`: responding HTTP(S) URLs, preserving explicit ports.
- `alive_subdomains.txt`: unique responding hostnames.
- `dead_subdomains.txt`: historical filename; means no HTTP response on the
  selected ports, not proven nonexistent DNS.
- `cname_records.txt`: CNAME answers from every discovered hostname, including
  hosts with no HTTP response.
- `takeover_candidates.txt`: recognized provider references; not proof of takeover.
- `confirmed_takeovers.txt`: historical filename; contains unverified scanner
  findings. Reports now describe them as unverified.
- `errors.log`: diagnostics from enumeration and optional tools. Review it before
  interpreting empty results. Optional tool failures do not stop the whole run.

Normal scans do not require sudo. `sudo bash suto.sh --install` installs system
packages and Go binaries into `/usr/local/bin`. Add `--full` for optional tools.
Installation/update needs network access and compatible upstream tool versions.
These operations were not run as part of the local verification.

Every run gets its own default output directory. Explicit output directories must
be empty to prevent mixing old and new findings.

Offline verification:

```bash
bash -n suto.sh
python3 -m unittest discover -s tests -v
```

The regression tests mock external tools and network responses. They cover
alternate ports, hostname deduplication, CNAME names containing hyphens, scope
filtering, HTML escaping, empty discovery, output reuse, missing optional tools,
HTTP tool failure, and invalid arguments. They do not validate the live behavior
of every upstream tool or guarantee that every vulnerability will be detected.
