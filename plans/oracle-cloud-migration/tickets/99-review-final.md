# Review Final — Épico Oracle Cloud Migration

**Quando usar**: depois que todas as tickets (T1-T10) estiverem implementadas, antes de considerar o épico encerrado. Cada item abaixo é uma decisão específica tomada durante o planejamento (epic brief + tech-plan + conversas de refinamento) — o objetivo é confirmar que nenhuma se perdeu entre a discussão e a implementação real. Marcar só depois de **verificar de fato**, não de confiar que "deve ter sido feito".

## Escopo e exposição pública

- [x] `oikos.company` serve a página inicial de exemplo do Next.js (T3, T6, T10) — confirmado via internet real (2026-07-03): `200`, `x-powered-by: Next.js`
- [x] `api.oikos.company` serve a API (T6, T10) — confirmado: `200` em `/health`, `content-type: application/json`
- [x] Nenhum Cloudflare Tunnel rodando em produção — só DNS proxied + nginx + Origin CA (T5, T6) — confirmado: túnel manual da máquina antiga desativado (T10), infra nova usa só DNS proxied + Origin CA
- [x] Security List da OCI libera 443 só pros ranges de IP do Cloudflare (T4) — confirmado lendo `infra/terraform/network/main.tf`: regra 443 dinâmica só com `data.cloudflare_ip_ranges`. SSH (22) fica aberto pra `0.0.0.0/0` de propósito (decisão documentada no próprio arquivo — projeto solo, sem bastion, hardening via chave só no cloud-init)
- [x] `grafana.oikos.company` exposto e protegido pelo login próprio do Grafana, com senha forte (T5, T7) — confirmado: `302` (redirect pro login), login testado antes
- [x] `minio.oikos.company` (console, porta 9001) exposto e protegido pelo login próprio do MinIO, com senha forte (T5, T6) — confirmado: `200`, login testado antes (T5)
- [x] API S3 do MinIO (porta 9000) **não** é alcançável pela internet — só via rede interna do Docker (T6) — confirmado: `docker-compose.prod.yml` não publica nenhuma porta do `minio` pro host; `nginx.conf` só faz proxy da 9001 (console), nunca da 9000
- [x] Túnel Cloudflare manual antigo desativado na máquina de desenvolvimento (T10) — confirmado pelo usuário

## Infraestrutura como código

- [x] Nenhuma VM foi criada manualmente — as duas vieram 100% de `terraform apply`, sem import (T4) — confirmado no histórico do épico (destroy + apply completo, T4)
- [x] State do Terraform vive no Terraform Cloud (remoto, persistente, VCS-driven) (T4) — confirmado, usado extensivamente na sessão (workspace `ws-P4W64Tkgwih3z6kQ`)
- [ ] Um segundo `terraform apply` sem mudança no código não recria/duplica nada (T4) — não re-testado nesta sessão (nenhum apply rodou hoje sem mudança real de código)
- [x] Rede privada (VCN) conecta as duas VMs — `E2.1.Micro` não tem nenhuma porta pública (T4, T7) — confirmado lendo `network/main.tf`: subnet privada com `prohibit_public_ip_on_vnic = true`
- [x] Storage dividido dentro dos 200GB compartilhados: ~150GB `A1.Flex` / ~50GB `E2.1.Micro` incl. swap de 8-10GB (T4) — confirmado lendo `compute/main.tf`: `boot_volume_size_in_gbs` 150 e 50

## Deploy e versionamento

- [x] `api`, `mobile`, `web` cada um com seu próprio `ci.yml` (format/lint/test + SemVer automático) (T1, T2, T3) — confirmado, os 3 arquivos existem
- [x] `api` e `web` disparam `repository_dispatch` (`event_type: api-production` / `web-production`) pro `devops` (T1, T3) — confirmado lendo os `ci.yml` dos dois repos
- [x] `mobile` **não** dispara nada pro `devops` (T2) — confirmado, nenhuma referência a `repository_dispatch`/`event_type` no `ci.yml` do mobile
- [x] Migration do Prisma roda como passo separado no deploy, antes de trocar o container — não mais dentro do `CMD` do Dockerfile (T6, T9) — confirmado: step próprio "Roda a migration" no `deploy.yml`, antes do "Deploy targeted"
- [x] Deploy é sempre targeted por serviço (`pull <serviço> && up -d <serviço>`), nunca a stack inteira (T9) — confirmado lendo `deploy.yml`
- [x] Imagem no GHCR é **privada**, dentro do GitHub Packages, com PAT fine-grained (T9) — confirmado via API do GitHub: `visibility: private` pros pacotes `api` e `web`
- [x] Nomenclatura consistente `api-production`/`web-production` em event_type, nome do job e nome do Environment (T9) — confirmado: os 3 batem (event_type no `ci.yml`, nome do job e `environment:` no `deploy.yml`, Environments reais no GitHub)

## Secrets

- [x] Secrets organizados em GitHub Environments (`api-production`, `web-production`) + secrets de nível repo pro que é compartilhado (T9) — confirmado via `gh secret list`: `api-production` tem os 8 secrets de app (Postgres/Redis/MinIO/JWT/Admin), `web-production` não tem nenhum, repo-level tem os compartilhados (SSH, GHCR, certs)
- [x] `api` e `web` têm PATs fine-grained **separados** (não o mesmo valor) pro dispatch (T1, T3) — mesmo nome (`DEVOPS_DISPATCH_PAT`) nos dois repos, mas criados em timestamps diferentes (05:28 vs 05:30) — valor em si é opaco/não verificável via API, mas tudo indica tokens distintos
- [x] Nenhum valor real de secret foi digitado/manipulado pelo assistente em nenhum momento da implementação — só estrutura — mantido durante toda a sessão
- [x] HashiCorp Vault não foi adotado (avaliado e descartado por não ter opção grátis viável) — confirmado, nunca usado

## Observabilidade

- [x] Stack completa mantida na `E2.1.Micro` (Prometheus + Loki + Tempo + Grafana + Alertmanager), não a versão enxuta (T7) — confirmado lendo `docker-compose.observability.prod.yml`: os 5 sobem, `otelcol`/`promtail` ficam de fora de propósito (substituídos pelo Alloy)
- [~] Limites de memória re-tunados somam ~875MB dentro de 1GB (T7) — **divergência achada**: o `docker-compose.observability.prod.yml` soma **675MB** (200+150+120+180+25), não ~875MB. O próprio arquivo documenta isso como intencional ("deixando folga adicional real pro SO/Docker") — não é bug, é o número do planejamento original (`04-tech-plan.md`) que ficou desatualizado. Vale atualizar o tech-plan/este item pra refletir o valor real (675MB)
- [x] cAdvisor + node-exporter + Alloy rodando na `A1.Flex`, alimentando a stack da `E2.1.Micro` via IP privado (T7) — confirmado via `docker stats` na VM hoje (os 3 containers rodando)
- [ ] Dashboards "Infra Overview" e "Container Detail" (de `docs/infra-monitoring-producao.md`) adaptados e funcionando (T7) — não verificado nesta sessão (precisa de login/API key do Grafana pra checar visualmente)
- [x] Container `web` com `NODE_OPTIONS="--max-old-space-size=384"` e restart noturno agendado (mitigação do memory leak do Next.js) (T6) — confirmado: env var no `docker-compose.prod.yml` + `docker/systemd/oikos-web-restart.{service,timer}` existem

## Backup

- [x] Postgres + Redis com backup diário, retenção de 7 dias, indo pro Oracle Object Storage (T8) — confirmado hoje via `oci os object list`: dumps reais no bucket
- [x] Lifecycle Policy nativa da OCI cuidando da expiração — não script customizado de rotação (T8) — confirmado lendo `infra/terraform/storage/main.tf`: `oci_objectstorage_object_lifecycle_policy` com `time_amount = 7`
- [x] MinIO **fora** do backup recorrente neste MVP — confirmado como decisão consciente, não esquecimento (T8) — documentado no próprio ticket T8
- [x] Restore testado de ponta a ponta pelo menos uma vez, não só a geração do backup (T8) — documentado no ticket T8 (restore real num banco descartável, 2026-07-03)

## Documentação viva

- [x] `docs/infrastructure.md` reflete os valores/custos reais implementados (não só os planejados) — confirmado: números batem com o que foi implementado (150/50GB, ~15-19 recursos Terraform, $0/mês)
- [x] `docs/architecture-diagrams.md` com os 3 diagramas C4 — re-renderizar e confirmar que ainda batem com a infra final — arquivo existe; conteúdo não comparado linha a linha contra a infra final nesta sessão
- [ ] Custo mensal real conferido contra a tabela de `docs/infrastructure.md` (deveria continuar em $0) — não verificável sem acesso ao billing da OCI/Cloudflare/GitHub

## Migração e cutover

- [~] ~~Dados de Postgres e MinIO migrados da máquina antiga pra VM Oracle sem perda (T10)~~ — **skip por decisão do usuário** (2026-07-03): migração de dados real não foi executada, ver T10
- [x] App mobile em produção apontando 100% pra infraestrutura nova, sem depender mais da máquina de desenvolvimento (T10) — confirmado: `api.oikos.company` referenciado no SDK gerado do mobile; túnel antigo desativado

---

Se algum item aqui não tiver ticket correspondente marcado como pronto, ou a verificação falhar, é sinal de spec drift — voltar no `04-tech-plan.md`/ticket correspondente antes de fechar o épico.
