# T4 — `devops`: Terraform — VMs + Rede

**Status**: **Pronta.** Infra recriada do zero (`destroy` + `apply` completo) depois dos fixes de IPv6 e NAT Gateway, pra validar o pipeline inteiro sem depender de `moved` blocks (removido — nesse estágio inicial, sem dado real, não fazia sentido preservar identidade de recurso). SSH e Docker confirmados nas duas VMs pós-recriação. Processo completo de credenciais e dos 3 bugs encontrados (chave OCI criptografada, IPv6 na Security List, subnet sem rota de internet) está documentado em [`docs/terraform-cloud-credentials-setup.md`](../../../docs/terraform-cloud-credentials-setup.md). Descoberta durante o planejamento: falta liberar portas internas de observabilidade na Security List (movido pra T7, ver checklist lá) — a OCI não libera tráfego intra-subnet automaticamente.

**Bug de rede encontrado ao testar SSH na `E2.1.Micro`**: `cloud-init` falhou ao instalar o Docker (`apt` com timeout) porque a subnet compartilhada só tinha rota via Internet Gateway — e um Internet Gateway na OCI só roteia tráfego de instância **com IP público**. A `E2.1.Micro` (sem IP público, por design) não tinha rota nenhuma pra internet. Correção: VCN passou a ter 2 subnets — pública (`A1.Flex`, rota → Internet Gateway) e privada (`E2.1.Micro`, rota → **NAT Gateway**, novo recurso).
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

- [x] `infra/terraform/backend.tf` — workspace remoto no Terraform Cloud, VCS-driven (conectado direto no repo `devops`)
- [x] Credenciais OCI cadastradas como workspace variables sensitive no Terraform Cloud (usuário cadastra)
- [x] `infra/terraform/network/` — VCN + subnet privada compartilhada pelas 2 VMs
- [x] `infra/terraform/network/` — internet gateway + route table
- [x] `infra/terraform/network/` — Security List: porta 443 liberada só pros ranges de IP do Cloudflare
- [x] `infra/terraform/network/` — nenhuma porta pública liberada pra subnet/VM da observabilidade
- [x] `infra/terraform/compute/` — `oci_core_instance` da VM `A1.Flex` (2 OCPU / 12GB), boot volume ~150GB
- [x] `infra/terraform/compute/` — `oci_core_instance` da VM `E2.1.Micro` (1GB), boot volume ~50GB
- [x] cloud-init (ambas as VMs): instala Docker, cria usuário `deploy` (grupo `docker`, chave SSH própria), hardening básico de SSH
- [x] cloud-init (só `E2.1.Micro`): cria e ativa swap file de 8-10GB
- [x] Confirmar que cloud-init **não** inclui secrets nem compose files (isso é do deploy, T9)
- [x] `terraform plan` revisado (7 recursos a criar, 0 erros, warning cosmético de variável não usada já corrigido)
- [x] `apply` rodado com sucesso — precisou de 1 correção no meio do caminho (regras IPv6 na Security List eram inválidas pra uma VCN sem IPv6 habilitado; removidas). VCN, internet gateway e route table sobreviveram ao primeiro apply parcial; security list, subnet e as 2 instâncias entraram no apply seguinte
- [x] IPs públicos das duas VMs anotados (necessários pra T5) — ver tabela abaixo
- [x] SSH manual de teste com o usuário `deploy` funcionando nas duas VMs — confirmado nas duas, com Docker instalado e funcional (`docker --version` OK); swap de 9GB ativo na `E2.1.Micro`

**IPs (saída do `terraform apply` do zero, pós-destroy)**:

| VM | IP público | IP privado |
|---|---|---|
| `oikos-app` (A1.Flex) | `134.65.229.35` | `10.0.1.196` |
| `oikos-observability` (E2.1.Micro) | — (sem IP público, por design) | `10.0.2.37` |

**Acesso SSH na `E2.1.Micro`**: sem IP público, então SSH só via bastion pela `A1.Flex`. `ssh -J` não propaga a identidade explícita (`-i`) pro salto — usar `ProxyCommand` explícito:
```bash
ssh -i <chave> -o ProxyCommand="ssh -i <chave> -W %h:%p deploy@134.65.229.35" deploy@10.0.2.37
```

**Nota sobre `apply` via CLI local**: `terraform apply` direto do terminal (mesmo autenticado via `terraform login`) **não funciona** nesse workspace — Terraform Cloud recusa (`Apply not allowed for workspaces with a VCS connection`) porque o workspace é VCS-driven, então só aceita `apply` disparado pelo próprio pipeline (push + aprovação na UI, ou via API reaproveitando uma configuration version já ingerida). `terraform plan` local funciona, mas só gera um plano especulativo, não aplicável.

## Definição de Pronto

As duas VMs existem, respondem por SSH com o usuário `deploy`, têm Docker instalado e funcional, e o state do Terraform está persistido no Terraform Cloud (um segundo `terraform apply` sem mudanças no código não recria nada).

## Guia: credenciais necessárias antes de rodar esta ticket

São **3 coisas separadas** que depois convergem como variáveis do workspace no Terraform Cloud.

### a) Chave de API da OCI (autentica o provider Terraform com a Oracle)

1. Console da Oracle Cloud → ícone de perfil → **User settings** → **Tokens and keys**
2. **API keys** → **Add API key** → **Generate API key pair** → **Download private key**
3. A própria tela mostra um snippet com `tenancy` (OCID), `user` (OCID), `fingerprint` e `region` — guardar esses 4 valores + o arquivo da chave privada

**Alternativa via CLI** (evita passar pelo console): `openssl genrsa -out chave.pem 2048` + `openssl rsa -pubout -in chave.pem -out chave_public.pem`, depois `oci iam user api-key upload --user-id <ocid> --key-file chave_public.pem` (retorna o fingerprint). **Não usar `oci setup keys --passphrase "N/A"`** — essa flag não reconhece o sentinela "N/A" como "sem senha" (só funciona digitando interativamente), então gera uma chave `ENCRYPTED PRIVATE KEY` que o provider Terraform não consegue ler (erro `did not find a proper configuration for private key`). Detalhes em [`docs/terraform-cloud-credentials-setup.md`](../../../docs/terraform-cloud-credentials-setup.md).

### b) Token de API do Cloudflare (autentica o provider Terraform com o Cloudflare)

1. Dashboard do Cloudflare → **My Profile** → **API Tokens** → **Create Token**
2. Custom token, com permissões: **Zone → DNS → Edit** (escopado só na zona `oikos.company`) + **Account → Access: Apps and Policies → Edit**
3. Copiar o token gerado

### c) Terraform Cloud (onde as credenciais viram config)

1. Criar conta em app.terraform.io (se ainda não tiver)
2. Criar uma organização e um workspace, conectado via VCS ao repo `devops`, apontando pra pasta `infra/terraform/`
3. No workspace → **Variables** → adicionar como *Terraform variables* (marcadas **sensitive**): as 4 credenciais OCI + o token Cloudflare

**Cuidado ao colar a chave privada (valor multi-linha) na UI**: colar um PEM multi-linha no campo de valor às vezes achata tudo numa linha só, quebrando o parse (mesmo erro `did not find a proper configuration for private key` acima). Se acontecer, é mais confiável atualizar a variável via API lendo o arquivo direto do disco (`PATCH /vars/{id}` com o conteúdo de `open(caminho).read()`) do que via copiar/colar no navegador — exemplo documentado em [`docs/terraform-cloud-credentials-setup.md`](../../../docs/terraform-cloud-credentials-setup.md).

Assim que isso estiver feito, o restante da ticket (escrever os `.tf` e rodar `apply`) pode prosseguir.
