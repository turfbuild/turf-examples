module "greeting" {
  source = "./modules/greeting"

  namespace = var.namespace
  greeting  = var.greeting
}
