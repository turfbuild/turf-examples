output "full_name" {
  description = "The assembled pet-suffix name. After apply, read it back from the Scalr workspace via the Scalr MCP server (or the Scalr UI) — that's the round-trip this example proves."
  value       = "${random_pet.name.id}-${random_string.suffix.result}"
}
