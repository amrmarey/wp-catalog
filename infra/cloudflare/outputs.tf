output "dns_records_by_zone" {
  description = "Map of zone_id to list of DNS records"
  value       = { for zone_id, ds in data.cloudflare_dns_records.all : zone_id => ds.records }
}

output "zones" {
  description = "List of discovered zones with names and ids"
  value = [
    for z in data.cloudflare_zones.all.zones : {
      id   = z.id
      name = z.name
    }
  ]
}


