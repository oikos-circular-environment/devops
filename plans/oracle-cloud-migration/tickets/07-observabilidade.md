# T7 — `devops`: Observabilidade Re-tunada

**Status**: **Pronta.** Stack completa rodando de verdade na `E2.1.Micro`, alimentada pelo Alloy da `A1.Flex`. `grafana.oikos.company` responde (302 → login, sem acesso anônimo), métricas/logs/traces confirmados chegando via API do Prometheus/Loki/Tempo, os 6 dashboards (incluindo os 2 novos deste ticket) provisionados e com dados reais.
**Repositório**: `oikos-circular-environment/devops`

## Escopo

Stack completa de observabilidade (Prometheus + Loki + Tempo + Grafana + Alertmanager) rodando na `E2.1.Micro` com limites re-tunados pra 1GB, e a camada de coleta (Alloy + cAdvisor + node-exporter) na `A1.Flex` alimentando essa stack — incluindo monitoramento de host e de container, não só de aplicação.

## Fora de escopo

Dashboards novos além dos 2 especificados em `docs/infra-monitoring-producao.md` (Infra Overview e Container Detail).

## Referências de spec

- `00-epic-brief.md` §Decisão de Arquitetura (Observabilidade)
- `04-tech-plan.md` §Abordagem Arquitetural (orçamento de memória, observabilidade de host+container)
- `docs/infra-monitoring-producao.md` (dashboards e config do Alloy — origem, calibrado pra EC2)

## Dependências

T4 (precisa das duas VMs existindo e se comunicando por IP privado).

## Bugs encontrados e corrigidos no deploy real (2026-07-03)

Nenhum destes aparecia nos testes locais — só surgiram testando contra as duas VMs de verdade:

1. **Senha real commitada em `.env.observability.example`** — `GF_ADMIN_PASSWORD` tinha um valor gerado de verdade (base64 de `openssl rand`) em vez de placeholder, desde o primeiro commit. Confirmado que nunca foi a senha efetivamente usada, mas ainda assim uma senha real não deveria estar em arquivo de exemplo. Corrigido.
2. **`GF_AUTH_ANONYMOUS_ENABLED=true` com role `Admin` vazava pra produção** — o arquivo base (dev local) habilita acesso anônimo administrativo por conveniência; o override de produção não desligava isso. Sem correção, qualquer um que chegasse em `grafana.oikos.company` teria acesso admin completo sem login — anulava a decisão do T5 de proteger o Grafana só pelo login próprio. Corrigido no override de produção.
3. **`docker compose` do deploy da observabilidade também precisava de `--env-file .env.observability`** — mesmo padrão do bug achado no T6. Sem isso, `GF_SECURITY_ADMIN_USER`/`PASSWORD` ficavam em branco e o Grafana caía pro admin/admin padrão. Corrigido no comando de deploy (a automatizar em `deploy.yml`/T9 quando esse ticket ganhar um step de deploy da observabilidade — hoje é só documentado aqui).
4. **`prometheus: depends_on: [otelcol]` no arquivo base forçava o `otelcol` a subir mesmo fora da lista de serviços de produção** — `docker compose up -d prometheus loki tempo grafana alertmanager` sobe o `otelcol` de qualquer forma por causa do `depends_on`, e ele conflita de porta (4317) com o `tempo`. Precisa de `--no-deps` no comando de `up` em produção (documentado; considerar mover para dentro do script de deploy quando esse step existir).
5. **cAdvisor não detectava containers Docker** — versões recentes do cAdvisor (v0.55+) detectam containers via **containerd**, não mais só via `docker.sock`. Sem montar `/run/containerd/containerd.sock`, a "docker container factory" falhava ao registrar, e o cAdvisor só enxergava agregados de cgroup (`systemd`/`raw`) sem nenhum label de container — os dois dashboards dependem de `container_label_com_docker_compose_project="oikos-prod"` pra filtrar, que nunca aparecia. Corrigido montando o socket do containerd no `docker-compose.prod.yml` (T6).

## Checklist

**Rede:**
- [x] `infra/terraform/network/` — regras de ingresso liberando Prometheus (9090), Loki (3100), Tempo (4317), Grafana (3000) só a partir da subnet pública — aplicado de verdade (T5)

**Na `E2.1.Micro`:**
- [x] `prometheus`, `loki`, `tempo`, `grafana`, `alertmanager` — todos `healthy`/`running`, dentro dos limites (prometheus 44MB/200MB, loki 53MB/150MB, tempo 50MB/120MB, grafana 68MB/180MB, alertmanager 16MB/25MB)
- [x] Deploy de produção sobe só os 5 serviços reais (`otelcol`/`promtail` não fazem parte do runtime de produção — precisa de `--no-deps`, ver bug 4 acima)
- [x] Acesso SSH validado via jump host pela `A1.Flex` (`E2.1.Micro` não tem IP público)

**Na `A1.Flex`:**
- [x] `cadvisor`, `node-exporter`, `alloy` — rodando, `alloy` conectado e fazendo `remote_write`/`push` de verdade (confirmado via WAL replay nos logs, sem erros)
- [x] Config `alloy-prod.alloy` validada e funcionando em produção real

**Validação de dados reais (via API do Prometheus/Loki/Tempo/Grafana, sem acesso visual ao browser):**
- [x] Prometheus: métricas de `node-exporter` (`node_load1`, `node_memory_MemAvailable_bytes`, `node_filesystem_avail_bytes`) presentes
- [x] Prometheus: métricas de `cadvisor` com labels corretos pros 9 containers da stack de produção (`container_label_com_docker_compose_project="oikos-prod"`) — confirmado pra todos os panels dos 2 dashboards (CPU, throttling, RAM working set/cache, rede, disco, restart count)
- [x] Loki: logs reais da `api` chegando via OTLP, com labels `service_name`/`deployment_environment_name` corretos
- [x] Tempo: `/ready` retorna 200 (demora ~20s após subir pra ficar pronto — comportamento normal)
- [x] Grafana: autenticação com usuário/senha forte funcionando (senha gerada fresca pra essa VM, nunca reaproveitada do `.env.observability` de dev local); acesso anônimo confirmado desabilitado
- [x] Grafana: os 6 dashboards provisionados automaticamente (`Oikos API — BullMQ Queues`, `HTTP Metrics (OTel)`, `k6 Load Tests`, `Overview`, `Oikos — Container Detail`, `Oikos — Infra Overview`)
- [x] `grafana.oikos.company` via internet real (Cloudflare) — 302 (redireciona pro login), antes retornava 502

**Dashboards** (`observability/grafana/dashboards/`):
- [x] `infra-overview.json` — todas as métricas usadas (host CPU/RAM/disco via node-exporter, CPU/RAM/rede por container via cadvisor) confirmadas com dados reais
- [x] `infra-container.json` — todas as métricas usadas (CPU %, throttling, RAM working set/cache, rede RX/TX, disco leitura/escrita, restart count) confirmadas com dados reais, variável `$service` populada corretamente

## Definição de Pronto

Abrir `grafana.oikos.company` (login com usuário/senha do Grafana) e ver, nos dois dashboards, dados reais de CPU/RAM/disco tanto do host `A1.Flex` quanto de cada container individualmente (api, web, postgresql, redis, minio, nginx). **Validado via API nesta sessão** (Prometheus/Loki/Tempo/Grafana todos confirmados com dados reais e consultas corretas) — confirmação visual no browser fica pra quando o usuário acessar manualmente.
