# Avaliação adiada — Nomad + Consul

**Status**: **não iniciada.** Analisar **depois** de concluídos os tickets de [`00-tech-plan.md`](./00-tech-plan.md), com a infra já reconstruída e o CI/CD já desacoplado.

## Por que ficou registrado

Durante a discussão da devops#77 a pergunta original era sobre Kubernetes: se um orquestrador resolveria o problema de containers gerenciados "na mão" (nada se reergue sozinho, nada reescala, atualização é `docker compose up -d` imperativo via SSH).

A análise concluiu que **Kubernetes não resolveria nenhum dos incidentes reais** e que o overhead de cluster (kubelet, CNI, CSI, ingress controller, controlador de GitOps) é caro demais para 2 OCPU de Always Free. Kubernetes foi descartado nesta fase.

**Nomad + Consul** apareceu como alternativa de peso intermediário e ficou sem avaliação — não porque seja pior, mas porque avaliar naquele momento misturaria duas discussões. Este documento existe para que a pergunta não se perca.

## O que avaliar quando chegar a hora

- **Custo real de operação numa VM de 2 OCPU / 12GB**: footprint de `nomad agent` (server + client no mesmo nó) e de `consul agent`, medido, não estimado. Comparar com o que os 9 containers consomem hoje (1.3GB de 12GB).
- **O que muda de fato no dia a dia**: rolling update com health gate (hoje `docker compose up -d api` troca o container independente do healthcheck passar), reagendamento, e deploy declarativo em vez de SSH imperativo.
- **Se Consul é necessário** ou se Nomad sozinho já resolve. Com um único nó e uma rede Docker, service discovery pode ser complexidade sem contrapartida.
- **Migração dos serviços com estado** (`postgresql_data`, `redis_data`, `minio_data`): host volumes do Nomad versus volumes Docker de hoje. Ver se ganha algo real ou se só troca a forma de escrever a mesma coisa.
- **Impacto no CI/CD já refatorado**: os pipelines passariam a submeter jobspec em vez de rodar `docker compose` por SSH. Medir se simplifica ou se só desloca a complexidade.
- **Comparação honesta com a linha de base**: depois dos tickets 01-08, boa parte da dor original (provisionamento manual, env acoplada, pipeline monolítico) já terá sido resolvida sem orquestrador. A pergunta certa passa a ser "o que ainda dói?", não "qual orquestrador usar".

## Critério de decisão

Só adotar se a resposta a **"o que ainda dói depois dos tickets 01-08?"** apontar especificamente para algo que um orquestrador resolve — rollout com health gate, reagendamento automático, ou escala. Se a dor remanescente for outra, a resposta é outra ferramenta.

## Referências

- [`00-tech-plan.md`](./00-tech-plan.md) — análise crítica que descartou Kubernetes nesta fase
- devops#77 — discussão original
- `docs/docker-infra.md` — decisões e gotchas do runtime atual
