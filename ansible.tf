resource "local_file" "ansible_inventory" {
  depends_on = [
    azurerm_linux_virtual_machine.master,
    azurerm_linux_virtual_machine.worker,
    aws_instance.k8s_worker,
  ]

  content  = "[master]\n${azurerm_public_ip.master_ip.ip_address}\n\n[worker]\n${join("\n", azurerm_public_ip.worker_ip[*].ip_address)}\n${aws_instance.k8s_worker.public_ip}"
  filename = "inventory"
}

output "master_ip" {
  value = azurerm_public_ip.master_ip.ip_address
}

output "azure_worker_ips" {
  value = join(", ", azurerm_public_ip.worker_ip[*].ip_address)
}

output "aws_worker_ip" {
  value = aws_instance.k8s_worker.public_ip
}
