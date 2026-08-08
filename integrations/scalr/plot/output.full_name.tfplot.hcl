turf {
  intent = "The assembled name: pet plus suffix. Read it back from the Scalr workspace via the Scalr MCP server after apply."
}

output "full_name" {
  value = "${random_pet.name.id}-${random_string.suffix.result}"
}
