# 🦊 suto.sh — Subdomain TakeOver Tool

> **Single-file bash automation for subdomain enumeration, CNAME analysis, and subdomain takeover detection.**

`suto.sh` is a powerful, all-in-one bash script that automates the entire subdomain takeover workflow — from passive enumeration to confirmed exploitation candidates. Designed for bug bounty hunters, penetration testers, and security researchers.

---

## ✨ Features

|---------------- Feature --------------------| Default | `--full` |
|-------------------------------------------------|-----|-----|
| 🎯 Multi-source subdomain enumeration           | ✅ | ✅ |
| 📦 Auto-deduplication & merging                 | ✅ | ✅ |
| ✅ Alive/Dead subdomain classification          | ✅ | ✅ |
| 🔗 CNAME record extraction (all subdomains)     | ✅ | ✅ |
| ⚠️ Takeover candidate filtering (30+ services)  | ✅ | ✅ |
| 🧪 Confirmation via Nuclei + Subjack            | ✅ | ✅ |
| 📊 HTML report generation                       | ✅ | ✅ |
| 🔁 Permutation generation (dnsgen)              | ❌ | ✅ |
| 🔍 Wayback Machine URL scraping                 | ❌ | ✅ |
| 📜 JS scraping for leaked bucket origins        | ❌ | ✅ |
| 📸 Screenshots (gowitness)                      | ❌ | ✅ |
| 🧠 Amass passive enumeration                    | ❌ | ✅ |
| 🔄 One-command tool updates                     | ✅ | ✅ |

**Detectable services:** AWS S3, CloudFront, Heroku, GitHub Pages, Azure App Service, Vercel, Netlify, Firebase, Shopify, Fastly, DigitalOcean, Pantheon, WordPress, Zendesk, Unbounce, Surge.sh, Cloudflare Pages, Bitbucket, ReadMe, GitBook, Gumroad, Oh Dear, and more.

---

## 🚀 Quick Start

### 1. Install (run once)

```bash
git clone https://github.com/yourusername/suto.sh.git
cd suto.sh
chmod +x suto.sh
sudo ./suto.sh --install
```

Usage: - 

```bash
USAGE:
  sudo ./suto.sh [OPTIONS] <domain>

OPTIONS:
  --install         Install all required dependencies (run once)
  --full            Enable extended features (amass, permutations, JS scraping, screenshots)
  --output DIR      Custom output directory (default: ./outputs/<domain>_<timestamp>)
  --threads N       Thread count for parallel operations (default: 50)
  --update          Update all installed Go tools to latest versions
  -h, --help        Show help message

EXAMPLES:
  sudo ./suto.sh --install                           # Install everything
  sudo ./suto.sh target.com                          # Quick run (enum + CNAME)
  sudo ./suto.sh target.com --full                   # Full recon
  sudo ./suto.sh target.com --output ~/reports       # Custom output
  sudo ./suto.sh target.com --threads 100            # Faster
  sudo ./suto.sh target.com --update                 # Update tools
