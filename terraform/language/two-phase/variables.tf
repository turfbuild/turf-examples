variable "device_id" {
  description = "Identifier of the device/target whose config is staged then committed"
  type        = string
  default     = "edge-router-1"
}

variable "candidate_config" {
  description = "The candidate configuration to stage (a real provider would push this to the device)"
  type        = string
  default     = "interface eth0 { mtu = 9000 }"
}
