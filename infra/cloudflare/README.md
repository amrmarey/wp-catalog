# Cloudflare DNS Records Export (Terraform)

This configuration discovers all accessible Cloudflare zones and collects all DNS records for each zone using the official Cloudflare Terraform provider.

## Prerequisites

- Terraform >= 1.3
- Cloudflare API Token exported as an environment variable with at least:
  - Zone:Read
  - DNS:Read

```bash
# PowerShell
$env:CLOUDFLARE_API_TOKEN = "<your_token_here>"

# Bash
export CLOUDFLARE_API_TOKEN="<your_token_here>"
```

## Usage

```bash
cd infra/cloudflare
terraform init
terraform plan
terraform apply -auto-approve

# View outputs (human-readable)
terraform output dns_records_by_zone

# View outputs as JSON (good for piping to tools)
terraform output -json dns_records_by_zone > dns_records.json
```

Outputs:
- `zones`: Basic list of discovered zone IDs and names
- `dns_records_by_zone`: Map of `zone_id` to the list of DNS `records`

Notes:
- The provider will automatically use the `CLOUDFLARE_API_TOKEN` environment variable.
- To restrict zones, edit `data "cloudflare_zones" "all" { ... }` with a filter per the provider docs.

