# T4 — `devops`: Terraform — VMs + Rede

**Status**: Bloqueada — aguardando o usuário cadastrar credenciais (ver Guia abaixo). Já existe um par de chaves SSH em `/media/ccrs/development/ccrs/oracle/ssh-key-2026-06-30.key(.pub)` — serve pro usuário `deploy` da VM, mas **não** substitui as credenciais de API abaixo.
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

## Guia: credenciais necessárias antes de rodar esta ticket

São **3 coisas separadas** que depois convergem como variáveis do workspace no Terraform Cloud.

### a) Chave de API da OCI (autentica o provider Terraform com a Oracle)

1. Console da Oracle Cloud → ícone de perfil → **User settings** → **Tokens and keys**
2. **API keys** → **Add API key** → **Generate API key pair** → **Download private key**
3. A própria tela mostra um snippet com `tenancy` (OCID), `user` (OCID), `fingerprint` e `region` — guardar esses 4 valores + o arquivo da chave privada

### b) Token de API do Cloudflare (autentica o provider Terraform com o Cloudflare)

1. Dashboard do Cloudflare → **My Profile** → **API Tokens** → **Create Token**
2. Custom token, com permissões: **Zone → DNS → Edit** (escopado só na zona `oikos.company`) + **Account → Access: Apps and Policies → Edit**
3. Copiar o token gerado

### c) Terraform Cloud (onde as credenciais viram config)

1. Criar conta em app.terraform.io (se ainda não tiver)
2. Criar uma organização e um workspace, conectado via VCS ao repo `devops`, apontando pra pasta `infra/terraform/`
3. No workspace → **Variables** → adicionar como *Terraform variables* (marcadas **sensitive**): as 4 credenciais OCI + o token Cloudflare

Assim que isso estiver feito, o restante da ticket (escrever os `.tf` e rodar `apply`) pode prosseguir.
