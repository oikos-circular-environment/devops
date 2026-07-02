# T4 — `devops`: Terraform — VMs + Rede

**Status**: Não iniciado
**Repositório**: `oikos-circular-environment/devops`

## Escopo

Provisionamento do zero (sem import) das duas VMs Always Free e da rede que as conecta. Base de toda a infraestrutura — quase todas as outras tickets do `devops` dependem desta.

## Fora de escopo

DNS/Cloudflare (T5), qualquer container/aplicação rodando nas VMs (T6, T7), backup (T8).

## Referências de spec

- `00-epic-brief.md` §Decisão de Arquitetura, §Restrições Confirmadas do Always Free Tier
- `04-tech-plan.md` §Abordagem Arquitetural
- `docs/infrastructure.md` (limites Always Free e Terraform Cloud)

## Dependências

Nenhuma.

## Checklist

- [ ] `infra/terraform/backend.tf` — workspace remoto no Terraform Cloud, VCS-driven (conectado direto no repo `devops`)
- [ ] Credenciais OCI cadastradas como workspace variables sensitive no Terraform Cloud (usuário cadastra)
- [ ] `infra/terraform/network/` — VCN + subnet privada compartilhada pelas 2 VMs
- [ ] `infra/terraform/network/` — internet gateway + route table
- [ ] `infra/terraform/network/` — Security List: porta 443 liberada só pros ranges de IP do Cloudflare
- [ ] `infra/terraform/network/` — nenhuma porta pública liberada pra subnet/VM da observabilidade
- [ ] `infra/terraform/compute/` — `oci_core_instance` da VM `A1.Flex` (2 OCPU / 12GB), boot volume ~150GB
- [ ] `infra/terraform/compute/` — `oci_core_instance` da VM `E2.1.Micro` (1GB), boot volume ~50GB
- [ ] cloud-init (ambas as VMs): instala Docker, cria usuário `deploy` (grupo `docker`, chave SSH própria), hardening básico de SSH
- [ ] cloud-init (só `E2.1.Micro`): cria e ativa swap file de 8-10GB
- [ ] Confirmar que cloud-init **não** inclui secrets nem compose files (isso é do deploy, T9)
- [ ] `terraform plan` revisado e `apply` rodado com sucesso
- [ ] IPs públicos das duas VMs anotados (necessários pra T5)
- [ ] SSH manual de teste com o usuário `deploy` funcionando nas duas VMs

## Definição de Pronto

As duas VMs existem, respondem por SSH com o usuário `deploy`, têm Docker instalado e funcional, e o state do Terraform está persistido no Terraform Cloud (um segundo `terraform apply` sem mudanças no código não recria nada).
