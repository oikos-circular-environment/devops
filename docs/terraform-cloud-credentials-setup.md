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

```bash
mkdir -p ~/.oci/terraform-api-key
oci setup keys --key-name terraform-oikos --output-dir ~/.oci/terraform-api-key --passphrase "N/A"
```

> Nota: a flag `--no-passphrase` **não existe** nessa versão da CLI (3.89.0), apesar de aparecer em exemplos antigos por aí. O jeito certo de gerar sem senha é `--passphrase "N/A"` (literal, é o que o prompt interativo pede).

Isso gera:
- `~/.oci/terraform-api-key/terraform-oikos.pem` — chave privada, fica só local
- `~/.oci/terraform-api-key/terraform-oikos_public.pem` — chave pública

A pública foi registrada na conta OCI (retorna o fingerprint):

```bash
oci iam user api-key upload \
  --user-id <user_ocid> \
  --key-file ~/.oci/terraform-api-key/terraform-oikos_public.pem \
  --auth security_token
```

## 4. Cloudflare — Account API Token

Diferente da OCI, o token da Cloudflare **não dá pra gerar via CLI/API do zero** (precisaria já ter um token com permissão de criar tokens). Gerado manualmente pelo dashboard:

- **Account API Tokens** (não "My Profile → API Tokens" — Cloudflare recomenda token de conta, não atrelado a usuário, pra automação/CI)
- Custom token com duas policies:
  - **Account → Entire Account → Access: Apps and Policies → Edit** (aparece na UI só como "Access", dentro da categoria "Cloudflare One / Zero Trust" — é o nome curto do mesmo grupo de permissão)
  - **Zone → (domínio do projeto) → DNS → Edit** (não confundir com "Zone DNS Settings", que é outra permissão — essa aqui é a que permite criar/editar registros, incluindo subdomínios, já que um subdomínio é só um registro dentro da mesma zona)

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

Todas criadas manualmente pela UI (colar direto, sem passar o valor pelo terminal/clipboard persistente) — decisão tomada porque escrever segredos via script/API é uma ação sensível o suficiente pra preferir o caminho manual.

### Conexão VCS

- Provider: GitHub App (não OAuth clássico)
- Repositório: `oikos-circular-environment/devops`
- Terraform working directory: `infra/terraform/`
- Trigger: **path-based**, pattern `infra/terraform/**` (só dispara run quando algo dentro dessa pasta muda — decisão consciente porque o repo `devops` é monorepo e tem outras pastas, como `docker/`, que são deploy de aplicação via GitHub Actions/SSH, um pipeline totalmente separado do Terraform — ver ticket `09-deploy-pipeline.md`)

**Problema conhecido**: a instalação do GitHub App pode falhar com `Failed to install GitHub App / Please disable pop-up blocker` em navegadores com bloqueio agressivo de popup (ex: Brave Shields). Resolvido desabilitando o Shields/pop-up blocker pro domínio `app.terraform.io` durante o fluxo.

## Referências

- [Install Terraform / OCI CLI (tutorial HashiCorp)](https://developer.hashicorp.com/terraform/tutorials/oci-get-started/install-cli)
- [OCI CLI — instalação (docs Oracle)](https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm)
- [Terraform Cloud — organizações](https://app.terraform.io/app/organizations)
- [Terraform — documentação geral](https://developer.hashicorp.com/terraform)
