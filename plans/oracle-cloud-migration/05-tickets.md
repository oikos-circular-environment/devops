# Migração de Produção para Oracle Cloud — Ticket Breakdown

Baseado em `00-epic-brief.md` e `04-tech-plan.md`. Cada ticket vive em [`tickets/`](./tickets/), com checklist própria de implementação. Ao final de todas, rodar [`tickets/99-review-final.md`](./tickets/99-review-final.md) — checklist de verificação cruzada contra tudo que foi decidido no planejamento.

## Dependências

```mermaid
flowchart TD
    T1[T1 · api — CI + SemVer]
    T2[T2 · mobile — CI + SemVer]
    T3[T3 · web — CI + SemVer]
    T4[T4 · devops — Terraform: VMs + rede]
    T5[T5 · devops — Terraform: DNS + Cloudflare Access]
    T6[T6 · devops — Stack de produção]
    T7[T7 · devops — Observabilidade re-tunada]
    T8[T8 · devops — Backup automatizado]
    T9[T9 · devops — Deploy pipeline]
    T10[T10 · devops — Migração de dados + cutover]

    T4 --> T5
    T4 --> T6
    T4 --> T7
    T4 --> T8
    T1 --> T9
    T3 --> T9
    T6 --> T9
    T9 --> T10
    T5 --> T10
    T8 --> T10
```

T2 (mobile) é independente de tudo — pode rodar em paralelo com qualquer outra ticket.

## Tickets

| # | Título | Status | Dependências |
|---|---|---|---|
| [T1](./tickets/01-api-ci-semver.md) | `api` — CI + Versionamento | `ci.yml` escrito, prod artifacts removidos, falta PAT/secret + validar | — |
| [T2](./tickets/02-mobile-ci-semver.md) | `mobile` — CI + Versionamento | `ci.yml` escrito, falta validar | — |
| [T3](./tickets/03-web-ci-semver.md) | `web` — CI + Versionamento | `ci.yml` escrito, falta PAT/secret (test runner adiado) | — |
| [T4](./tickets/04-terraform-vms-rede.md) | `devops` — Terraform: VMs + rede | Bloqueada — aguardando credenciais OCI/Cloudflare/Terraform Cloud (guia na ticket) | — |
| [T5](./tickets/05-terraform-dns-cloudflare.md) | `devops` — Terraform: DNS + Cloudflare Access | Não iniciado | T4 |
| [T6](./tickets/06-stack-producao.md) | `devops` — Stack de produção | Escrito e validado localmente, falta testar na VM real | T4 |
| [T7](./tickets/07-observabilidade.md) | `devops` — Observabilidade re-tunada | Não iniciado | T4 |
| [T8](./tickets/08-backup-automatizado.md) | `devops` — Backup automatizado | Não iniciado | T4 |
| [T9](./tickets/09-deploy-pipeline.md) | `devops` — Deploy pipeline | Não iniciado | T1, T3, T6, T4 |
| [T10](./tickets/10-migracao-dados-cutover.md) | `devops` — Migração de dados + cutover | Não iniciado | T9, T5, T8 |

## Refinamento

Granularidade e agrupamento (por repo/componente) definidos em conjunto com o usuário. Ajustar aqui e nos arquivos individuais se algum ticket precisar ser combinado, dividido ou reordenado.
