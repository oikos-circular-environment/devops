# Setup de credenciais — Terraform Cloud, OCI e Cloudflare

Registro do processo usado para levantar as credenciais e a configuração do workspace `oracle-server` (Terraform Cloud), necessárias pela ticket [`04-terraform-vms-rede.md`](../plans/oracle-cloud-migration/tickets/04-terraform-vms-rede.md). Cobre o que foi instalado, os comandos rodados e onde cada dado acabou armazenado — não repete valores sensíveis, só o processo pra reproduzir ou auditar depois.

## Ferramentas usadas

| Ferramenta | Onde | Instalação |
|---|---|---|
| OCI CLI | máquina local | já estava instalado (`oci` v3.89.0) |
| Terraform CLI | máquina local | já estava instalado |
| `terraform login` | máquina local | gera token salvo em `~/.terraform.d/credentials.tfrc.json`, usado pra autenticar chamadas à API do Terraform Cloud |

## 1. Autenticação da OCI CLI (sessão local)

A OCI CLI não vinha configurada (`~/.oci/config` não existia). Login feito via:

```bash
oci session authenticate --profile-name learn-terraform --region <regiao>
```

Isso abre o navegador, autentica na conta OCI e grava um *session token* (TTL curto) em `~/.oci/config`, perfil `DEFAULT`.

**Detalhe importante**: esse config gerado não inclui a chave `authentication_type=security_token`, então todo comando `oci` subsequente precisa da flag explícita:

```bash
oci <comando> --auth security_token
```

Sem essa flag a CLI tenta autenticar como API key estática (erro `user: missing`).

## 2. Dados de infraestrutura obtidos via OCI CLI

Com a sessão autenticada, esses valores foram extraídos direto (sem precisar abrir o console):

| Dado | Comando | Valor |
|---|---|---|
| Tenancy OCID | `oci iam tenancy get --tenancy-id <tenancy> --auth security_token` | `ocid1.tenancy.oc1..aaaaaaaa5ctl5fou3xnmvshsm4nc75yohzkebfqg26aeeslh6ngka4tgaqga` |
| User OCID | `oci iam user list --auth security_token` | `ocid1.user.oc1..aaaaaaaan6um3xtv6dezbwmq7agxgwyh2huqgfzvx3bqe3ndkvei5qh4j7ia` (único usuário: christiancnp@gmail.com) |
| Region | já presente em `~/.oci/config` | `sa-vinhedo-1` |
| Compartment | `oci iam compartment list --compartment-id-in-subtree true --all --auth security_token` | vazio — sem sub-compartments criados, então o compartment a usar é o da **tenancy raiz** (mesmo OCID acima) |
| Availability Domain | `oci iam availability-domain list --auth security_token` | `GlBY:SA-VINHEDO-1-AD-1` |

## 3. API Key estática (autenticação do provider Terraform `oci`)

O *session token* do passo 1 expira em ~1h e não serve para o Terraform Cloud (execução remota, sem interação humana). Foi gerado um **par de chaves de API dedicado**, separado da chave SSH que já existia (`/media/ccrs/development/ccrs/oracle/ssh-key-2026-06-30.key`, usada só pro usuário `deploy` das VMs) — **decisão deliberada**: misturar as duas aumentaria o raio de impacto caso uma delas vazasse (SSH = acesso à VM; API key = poder de criar/destruir toda a infra via Terraform).

**Tentativa inicial (com bug — não usar)**:

```bash
mkdir -p ~/.oci/terraform-api-key
oci setup keys --key-name terraform-oikos --output-dir ~/.oci/terraform-api-key --passphrase "N/A"
```

O prompt interativo do `oci setup keys` diz `("N/A" for no passphrase)`, mas esse sentinela **só é reconhecido quando digitado interativamente**. Passado via flag `--passphrase "N/A"`, a CLI trata "N/A" como senha literal e gera uma chave `-----BEGIN ENCRYPTED PRIVATE KEY-----` de verdade. Isso só foi descoberto depois, no primeiro `terraform plan` real no Terraform Cloud, com o erro:

```
Error: can not create client, bad configuration: did not find a proper configuration for private key
```

(o provider `oci` não tem como decifrar uma chave criptografada sem a senha, e não passamos `private_key_password` nenhuma). Rodar `openssl rsa -check -noout -in arquivo.pem` teria pego isso na hora (mostra `BEGIN ENCRYPTED PRIVATE KEY` no `head -1`).

**Correção — gerar via `openssl` direto, sem depender do sentinela da CLI**:

```bash
openssl genrsa -out terraform-oikos-v2.pem 2048
openssl rsa -pubout -in terraform-oikos-v2.pem -out terraform-oikos-v2_public.pem
openssl rsa -in terraform-oikos-v2.pem -check -noout   # confirma "RSA key ok", sem pedir senha
```

A pública foi registrada na conta OCI (retorna o fingerprint):

```bash
oci iam user api-key upload \
  --user-id <user_ocid> \
  --key-file ~/.oci/terraform-api-key/terraform-oikos-v2_public.pem \
  --auth security_token
```

A chave antiga (quebrada) ficou registrada na conta OCI, ainda ativa mas sem uso — remover via `oci iam user api-key delete --user-id <user_ocid> --fingerprint <fingerprint-antigo>` quando for conveniente.

## 4. Cloudflare — Account API Token

Diferente da OCI, o token da Cloudflare **não dá pra gerar via CLI/API do zero** (precisaria já ter um token com permissão de criar tokens). Gerado manualmente pelo dashboard:

- **Account API Tokens** (não "My Profile → API Tokens" — Cloudflare recomenda token de conta, não atrelado a usuário, pra automação/CI)
- Custom token com duas policies:
  - **Zone → (domínio do projeto) → DNS → Edit** (não confundir com "Zone DNS Settings", que é outra permissão — essa aqui é a que permite criar/editar registros, incluindo subdomínios, já que um subdomínio é só um registro dentro da mesma zona)
  - **Zone → (domínio do projeto) → SSL and Certificates → Edit** (necessária pro recurso `cloudflare_origin_ca_certificate` — sem essa permissão o `apply` falha com 401 "User is not authorized to perform this action")

Cloudflare Access/Zero Trust foi avaliado e descartado do escopo (T5, decisão de 2026-07-02) — não precisa da policy `Access: Apps and Policies`.

## 5. Terraform Cloud — organização e workspace

- Organização: `oikos-circular-economy`
- Workspace: `oracle-server` (`ws-P4W64Tkgwih3z6kQ`)
- Execution mode: Remote
- Auto-apply: **desligado** (runs exigem aprovação manual antes de aplicar — importante nesse primeiro apply, que cria VMs do zero)

### Workspace Variables (Terraform Cloud → oracle-server → Variables)

Todas categoria `terraform`. As 4 primeiras marcadas **sensitive** (nunca mais aparecem na UI/API depois de criadas):

| Variável | Sensível | Origem |
|---|---|---|
| `tenancy_ocid` | sim | passo 2 |
| `user_ocid` | sim | passo 2 |
| `fingerprint` | sim | retorno do `oci iam user api-key upload` (passo 3) |
| `region` | não | `sa-vinhedo-1` |
| `private_key` | sim | conteúdo de `~/.oci/terraform-api-key/terraform-oikos.pem` (passo 3) |
| `cloudflare_account_id` | sim | dashboard Cloudflare (passo 4) |
| `cloudflare_api_token` | sim | dashboard Cloudflare (passo 4) |

Criadas manualmente pela UI (colar direto, sem passar o valor pelo terminal/clipboard persistente) — decisão tomada porque escrever segredos via script/API é uma ação sensível o suficiente pra preferir o caminho manual.

**Problema encontrada**: colar um valor multi-linha (a `private_key`, especificamente) no campo de texto da UI achatou as quebras de linha, gerando o mesmo erro `did not find a proper configuration for private key` mesmo com uma chave `openssl` válida. O parser de PEM da OCI exige quebras de linha reais separando `-----BEGIN/END-----` do corpo em base64. Corrigido atualizando a variável via API, lendo o arquivo direto do disco (preserva as quebras de linha exatas):

```bash
TOKEN=$(python3 -c "import json; print(json.load(open('~/.terraform.d/credentials.tfrc.json'))['credentials']['app.terraform.io']['token'])")
python3 -c "
import json, urllib.request
private_key = open('~/.oci/terraform-api-key/terraform-oikos-v2.pem').read()
payload = {'data': {'type': 'vars', 'id': '<var-id>', 'attributes': {'value': private_key}}}
req = urllib.request.Request(
    'https://app.terraform.io/api/v2/vars/<var-id>',
    data=json.dumps(payload).encode(),
    headers={'Authorization': 'Bearer $TOKEN', 'Content-Type': 'application/vnd.api+json'},
    method='PATCH')
urllib.request.urlopen(req)
"
```

Lição: pra valores sensíveis multi-linha (chaves privadas, certificados), preferir sempre ler o arquivo direto via API a copiar/colar num campo de UI.

### Conexão VCS

- Provider: GitHub App (não OAuth clássico)
- Repositório: `oikos-circular-environment/devops`
- Terraform working directory: `infra/terraform/`
- Trigger: **path-based**, pattern `infra/terraform/**` (só dispara run quando algo dentro dessa pasta muda — decisão consciente porque o repo `devops` é monorepo e tem outras pastas, como `docker/`, que são deploy de aplicação via GitHub Actions/SSH, um pipeline totalmente separado do Terraform — ver ticket `09-deploy-pipeline.md`)

**Problema conhecido**: a instalação do GitHub App pode falhar com `Failed to install GitHub App / Please disable pop-up blocker` em navegadores com bloqueio agressivo de popup (ex: Brave Shields). Resolvido desabilitando o Shields/pop-up blocker pro domínio `app.terraform.io` durante o fluxo.

## 6. Primeiro `plan` validado

Depois de corrigir a chave (passo 3), um `plan` disparado manualmente via API (`POST /runs`, reaproveitando a configuration version já ingerida do push pra `production`) rodou com sucesso: **7 recursos a criar, 0 a mudar, 0 a destruir** (VCN, internet gateway, route table, security list, subnet, e as 2 `oci_core_instance`), sem erros. `apply` fica pendente de aprovação manual (auto-apply desligado de propósito).

Runs podem ser disparados sem novo commit quando só a *configuration* já ingerida importa (ex: reprocessar depois de corrigir uma variável) — usando a mesma `configuration-version` num novo `POST /runs`, em vez de esperar um push novo no VCS.

**Problema recorrente**: em pelo menos 2 ocasiões, um `merge` de PR pra `production` (via botão "Merge pull request" do GitHub, commit de 2 parents) não disparou run automaticamente, mesmo com o branch trigger configurado certinho e o file-trigger batendo. A configuration version *foi* ingerida (confirmado via `GET /configuration-versions`), só não virou run sozinha. Sem acesso aos logs de entrega do webhook do GitHub App (não é um webhook clássico por-repositório, não aparece em `gh api repos/.../hooks`), não foi possível confirmar a causa raiz — suspeita não comprovada é o cálculo de "arquivos alterados" do push se confundir com merge commits de 2 parents. Workaround que funcionou 100% das vezes: disparar o run manualmente via API reaproveitando a `configuration-version` já ingerida (mesmo comando acima).

## 7. Bug de rede: subnet privada sem rota pra internet

No primeiro `apply` completo, o `cloud-init` da `E2.1.Micro` falhou ao instalar o Docker — `apt` dava timeout tentando alcançar os mirrors do Ubuntu. Causa: a subnet original era compartilhada pelas 2 VMs com só um Internet Gateway na route table. Na OCI, **um Internet Gateway só roteia tráfego de/para instâncias com IP público** — a `E2.1.Micro` (sem IP público, por design) simplesmente não tinha como sair pra internet, mesmo com a rota `0.0.0.0/0 → Internet Gateway` presente na route table.

Diagnóstico feito direto na VM via SSH (depois de descobrir que `-J`/ProxyJump não herda `-i` explícito do comando externo — precisa de `-o ProxyCommand="ssh -i <chave> -W %h:%p usuario@bastion"` em vez de `-J` quando a chave não está no `ssh-agent` nem é uma das default (`~/.ssh/id_*`)):

```bash
ssh -i chave.key -o ProxyCommand="ssh -i chave.key -W %h:%p deploy@<ip-publico-bastion>" deploy@<ip-privado-alvo> \
  "sudo cloud-init status --long; sudo tail -60 /var/log/cloud-init-output.log"
```

**Correção**: VCN passou de 1 subnet compartilhada pra 2 subnets — pública (`A1.Flex`, rota → Internet Gateway) e privada (`E2.1.Micro`, rota → **NAT Gateway**, recurso novo, sem custo por hora na OCI). Cada subnet com sua própria route table; a Security List continua compartilhada entre as duas (as regras de 443/22 são inofensivas na subnet privada, já que não há IP público pra alcançar de qualquer forma).

Decisão tomada depois: como ainda era configuração inicial (sem dado real, sem DNS apontado), em vez de usar `moved` blocks pra preservar a subnet/instância antiga durante o refactor, optamos por `destroy` completo + `apply` do zero — validando o pipeline inteiro (incluindo todos os bugs já corrigidos) partindo do nada, sem nenhum artefato histórico (`moved.tf`) sobrando no código.

## 8. `terraform apply` via CLI local não funciona nesse workspace

Mesmo com `terraform login` autenticado e `terraform init` conectando certinho ao backend remoto, `terraform apply` direto do terminal falha com:

```
Error: Apply not allowed for workspaces with a VCS connection
A workspace that is connected to a VCS requires the VCS-driven workflow to
ensure that the VCS remains the single source of truth.
```

`terraform plan` local funciona (gera um plano especulativo, só pra preview — não pode virar `apply`). Pra workspaces VCS-driven, todo `apply` real tem que vir do pipeline: push pra `production` (aprovação manual na UI) ou, quando o auto-trigger falha (ver problema recorrente acima), disparo manual via API reaproveitando uma `configuration-version` já ingerida do branch `production`.

## Referências

- [Install Terraform / OCI CLI (tutorial HashiCorp)](https://developer.hashicorp.com/terraform/tutorials/oci-get-started/install-cli)
- [OCI CLI — instalação (docs Oracle)](https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm)
- [Terraform Cloud — organizações](https://app.terraform.io/app/organizations)
- [Terraform — documentação geral](https://developer.hashicorp.com/terraform)
