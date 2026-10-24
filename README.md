# suto — Subdomain Takeover Review Tool

Bash automation for subdomain enumeration, HTTP probing, CNAME analysis, and
collecting potential takeover findings for authorized security testing.
Provider references and scanner matches require manual validation; they are not
confirmed takeovers.

## Installation

```bash
git clone https://github.com/Sivaprasad-MP/suto.git
cd suto
sudo bash suto.sh --install
```

For optional full-mode dependencies:

```bash
sudo bash suto.sh --install --full
```

Installation uses apt, Go, and pipx on Linux/WSL. It requires internet access and
compatible upstream tool versions. Standard Go binaries are installed into
`/usr/local/bin`. Normal scans do not require sudo.

## Usage

```bash
bash suto.sh --help
bash suto.sh example.com
bash suto.sh example.com --ports 80,443,8080,8443 --threads 10
bash suto.sh example.com --full --output ./reports/example-run1
bash suto.sh --update
```

Replace `example.com` with an authorized target hostname, without a scheme, path,
or port. Limit testing to hosts and ports permitted by the program.

| Option | Behavior |
| --- | --- |
| `--install` | Install standard dependencies; requires sudo |
| `--full` | Attempt Amass, permutations, historical URLs, crawling, and screenshots when available |
| `--ports LIST` | Comma-separated HTTP(S) ports; default `80,443`; no range syntax |
| `--threads N` | Concurrency for tools accepting this setting; default 50, valid 1–9999; not a global rate limit |
| `--output DIR` | Use an empty or nonexistent output directory |
| `--update` | Update standard Go tools and Nuclei templates |
| `-h`, `--help` | Show help |

Each run otherwise creates a separate output directory under `./outputs/`.
Full mode depends on optional tools; inspect diagnostics for failures.

## Domains without a webpage

DNS existence and HTTP availability are separate. A hostname without a response
on 80/443 may serve HTTP on another authorized port, run a non-web service, be
filtered, or have a DNS problem. Missing HTTP is not proof of a takeover.

```bash
dig example.com A
dig example.com AAAA
dig example.com CNAME
bash suto.sh example.com --ports 80,443,8080,8443
```

The script probes only listed web ports. It does not discover every open TCP
port or identify arbitrary services. CNAME checks include hosts with no HTTP
response. HTTP 403/404 responses are retained.

## Results

| File | Contents |
| --- | --- |
| `summary.txt`, `report.html` | Summary and browser-readable report |
| `all_subdomains.txt` | Discovered/generated hostnames; not necessarily resolved |
| `alive_urls.txt` | Responding URLs with scheme and port preserved |
| `alive_subdomains.txt` | Unique responding hostnames |
| `dead_subdomains.txt` | Legacy filename: no HTTP response on selected ports, not proven dead DNS |
| `cname_records.txt` | CNAME answers across discovered hostnames |
| `takeover_candidates.txt` | Recognized provider references requiring investigation |
| `confirmed_takeovers.txt` | Legacy filename: unverified scanner findings |
| `errors.log` | Tool diagnostics; review before interpreting empty results |
| `raw/` | Individual enumeration outputs |
| `screenshots/` | Full-mode screenshots when available |

## Verification

```bash
bash -n suto.sh
python3 -m unittest discover -s tests -v
```

The offline tests mock external tools. They cover alternate ports, CNAME parsing,
scope filtering, HTML escaping, empty results, output reuse, invalid arguments,
missing optional tools, and HTTP tool failures. Live installation and upstream
integration have not been validated by these tests.
