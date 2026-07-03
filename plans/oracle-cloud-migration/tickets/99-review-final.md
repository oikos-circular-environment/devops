# Review Final — Épico Oracle Cloud Migration

**Quando usar**: depois que todas as tickets (T1-T10) estiverem implementadas, antes de considerar o épico encerrado. Cada item abaixo é uma decisão específica tomada durante o planejamento (epic brief + tech-plan + conversas de refinamento) — o objetivo é confirmar que nenhuma se perdeu entre a discussão e a implementação real. Marcar só depois de **verificar de fato**, não de confiar que "deve ter sido feito".

## Escopo e exposição pública

- [ ] `oikos.company` serve a página inicial de exemplo do Next.js (T3, T6, T10)
- [ ] `api.oikos.company` serve a API (T6, T10)
- [ ] Nenhum Cloudflare Tunnel rodando em produção — só DNS proxied + nginx + Origin CA (T5, T6)
- [ ] Security List da OCI libera 443 só pros ranges de IP do Cloudflare (T4)
- [ ] `grafana.oikos.company` exposto e protegido pelo login próprio do Grafana, com senha forte (T5, T7)
- [ ] `minio.oikos.company` (console, porta 9001) exposto e protegido pelo login próprio do MinIO, com senha forte (T5, T6)
- [ ] API S3 do MinIO (porta 9000) **não** é alcançável pela internet — só via rede interna do Docker (T6)
- [ ] Túnel Cloudflare manual antigo desativado na máquina de desenvolvimento (T10)

## Infraestrutura como código

- [ ] Nenhuma VM foi criada manualmente — as duas vieram 100% de `terraform apply`, sem import (T4)
- [ ] State do Terraform vive no Terraform Cloud (remoto, persistente, VCS-driven) (T4)
- [ ] Um segundo `terraform apply` sem mudança no código não recria/duplica nada (T4)
- [ ] Rede privada (VCN) conecta as duas VMs — `E2.1.Micro` não tem nenhuma porta pública (T4, T7)
- [ ] Storage dividido dentro dos 200GB compartilhados: ~150GB `A1.Flex` / ~50GB `E2.1.Micro` incl. swap de 8-10GB (T4)

## Deploy e versionamento

- [ ] `api`, `mobile`, `web` cada um com seu próprio `ci.yml` (format/lint/test + SemVer automático) (T1, T2, T3)
- [ ] `api` e `web` disparam `repository_dispatch` (`event_type: api-production` / `web-production`) pro `devops` (T1, T3)
- [ ] `mobile` **não** dispara nada pro `devops` (T2)
- [ ] Migration do Prisma roda como passo separado no deploy, antes de trocar o container — não mais dentro do `CMD` do Dockerfile (T6, T9)
- [ ] Deploy é sempre targeted por serviço (`pull <serviço> && up -d <serviço>`), nunca a stack inteira (T9)
- [ ] Imagem no GHCR é **privada**, dentro do GitHub Packages, com PAT fine-grained (T9)
- [ ] Nomenclatura consistente `api-production`/`web-production` em event_type, nome do job e nome do Environment (T9)

## Secrets

- [ ] Secrets organizados em GitHub Environments (`api-production`, `web-production`) + secrets de nível repo pro que é compartilhado (T9)
- [ ] `api` e `web` têm PATs fine-grained **separados** (não o mesmo valor) pro dispatch (T1, T3)
- [ ] Nenhum valor real de secret foi digitado/manipulado pelo assistente em nenhum momento da implementação — só estrutura
- [ ] HashiCorp Vault não foi adotado (avaliado e descartado por não ter opção grátis viável)

## Observabilidade

- [ ] Stack completa mantida na `E2.1.Micro` (Prometheus + Loki + Tempo + Grafana + Alertmanager), não a versão enxuta (T7)
- [ ] Limites de memória re-tunados somam ~875MB dentro de 1GB (T7)
- [ ] cAdvisor + node-exporter + Alloy rodando na `A1.Flex`, alimentando a stack da `E2.1.Micro` via IP privado (T7)
- [ ] Dashboards "Infra Overview" e "Container Detail" (de `docs/infra-monitoring-producao.md`) adaptados e funcionando (T7)
- [ ] Container `web` com `NODE_OPTIONS="--max-old-space-size=384"` e restart noturno agendado (mitigação do memory leak do Next.js) (T6)

## Backup

- [ ] Postgres + Redis com backup diário, retenção de 7 dias, indo pro Oracle Object Storage (T8)
- [ ] Lifecycle Policy nativa da OCI cuidando da expiração — não script customizado de rotação (T8)
- [ ] MinIO **fora** do backup recorrente neste MVP — confirmado como decisão consciente, não esquecimento (T8)
- [ ] Restore testado de ponta a ponta pelo menos uma vez, não só a geração do backup (T8)

## Documentação viva

- [ ] `docs/infrastructure.md` reflete os valores/custos reais implementados (não só os planejados)
- [ ] `docs/architecture-diagrams.md` com os 3 diagramas C4 — re-renderizar e confirmar que ainda batem com a infra final
- [ ] Custo mensal real conferido contra a tabela de `docs/infrastructure.md` (deveria continuar em $0)

## Migração e cutover

- [ ] Dados de Postgres e MinIO migrados da máquina antiga pra VM Oracle sem perda (T10)
- [ ] App mobile em produção apontando 100% pra infraestrutura nova, sem depender mais da máquina de desenvolvimento (T10)

---

Se algum item aqui não tiver ticket correspondente marcado como pronto, ou a verificação falhar, é sinal de spec drift — voltar no `04-tech-plan.md`/ticket correspondente antes de fechar o épico.
