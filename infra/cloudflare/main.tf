# Discover all accessible zones
data "cloudflare_zones" "all" {}

# For each zone, fetch all DNS records (no filter -> all records)
data "cloudflare_dns_records" "all" {
  for_each = { for z in data.cloudflare_zones.all.zones : z.id => z }

  zone_id = each.key
}


