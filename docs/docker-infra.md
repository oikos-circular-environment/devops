# Docker & Deploy — Decisões de Arquitetura

Racional de arquitetura, achados de produção e orçamento de capacidade da stack Docker/deploy do épico [`oracle-cloud-migration`](../plans/oracle-cloud-migration/00-epic-brief.md). Referências `(ver ticket NN)` apontam pro histórico de implementação em `plans/oracle-cloud-migration/tickets/`. Atualizar sempre que uma decisão documentada aqui mudar.

## 1. Pipeline CI/CD (`deploy-api.yml` / `deploy-web.yml` / `deploy-stack.yml`)

- **Um entrypoint por gatilho** `(ver ticket 04, plano infra-cicd-v2)`: `deploy-api.yml` (`repository_dispatch[api-production]` + `workflow_dispatch`), `deploy-web.yml` (`repository_dispatch[web-production]` + `workflow_dispatch`) e `deploy-stack.yml` (`push[production]` + `workflow_dispatch`). O roteamento que antes era feito por `if:` nos jobs (comparando `github.event.action`/`inputs.service`) agora é o próprio `on:` de cada arquivo — não existe mais `if:` de gatilho em job nenhum, nem input `service` (choice) no `workflow_dispatch` — cada arquivo tem o seu próprio, já implícito no serviço.
- **Trigger de `push` em `deploy-stack.yml`**: qualquer merge em `production` reconcilia a stack inteira (job `stack-production`). `paths-ignore` exclui `docs/`, `plans/`, `**/*.md` e `infra/terraform/**` — esses não afetam a stack, e o Terraform é aplicado separadamente no Terraform Cloud, com aprovação manual depois do merge (rodar a stack no push reconvergeria contra a infra antiga; pra reconvergir pós-apply, usar `workflow_dispatch` em `deploy-stack.yml`).
- **Build fica inline em cada entrypoint, sem `workflow_call`**: chegou a existir um `_build-push-image.yml` reusável, descartado. `environment:` não é keyword suportado num job caller que só tem `uses:` (doc oficial, "Supported keywords for jobs that call a reusable workflow"), então o caller não conseguiria ler `vars`/`secrets` do Environment `web-production` pra montar os `build-args` de `NEXT_PUBLIC_*`. Declarar `environment: ${{ inputs.environment }}` dentro do reusable resolveria isso, mas forçaria o arquivo genérico a conhecer nomes de build-arg específicos do `web`. Com o `web` inline, sobrava um único chamador (`api`) — reusable com um consumidor é indireção sem dedup. A deduplicação real mora nas composite actions de `.github/actions/`, que o `ssh-setup` sozinho já paga (7 usos).
- **`concurrency: group: deploy-vm`**: único grupo, repetido nos 3 entrypoints (escopo é o repositório, não o arquivo) — as pipelines api/web/stack mexem nos mesmos arquivos/containers na mesma VM, então precisam ser serializadas entre si, não só contra reexecuções de si mesmas.
- **Estrutura dos jobs api/web**: `api` é `build → sync → migrate → deploy-container`; `web` é `build → sync → deploy-container` (sem migrate — não existe migration do Prisma pro web).
- **Runner arm64 nativo** (`ubuntu-24.04-arm`): build cross-arch via QEMU (`docker/setup-qemu-action`) travava com `qemu: uncaught target signal 4 (Illegal instruction)` durante o `npm ci`, sem reportar falha (ficava preso indefinidamente). A A1.Flex também é arm64 (Ampere), então a imagem buildada aqui roda nativa lá, sem tradução nenhuma.
- **Resolução de versão/SHA** `(ver ticket 12)`: vem do `repository_dispatch` (sempre preenchidos) ou do `workflow_dispatch` (opcionais) — quando vazios, resolve a última tag SemVer do repo via API (`sort -V`, não a ordem da API, que não é garantida) e o commit dela. Tag anotada aponta pra um objeto tag, não pro commit — por isso a dereferência condicional (`TYPE == "tag"`).
- **`sort -V` + gate `api_changed`** (job `stack-production`): mesmo motivo do `sort -V` acima; `api_changed` decide se a migration roda (só quando a versão do api realmente avança — mesma proteção do fluxo de release normal).
- **Bump de versão via `sed`**: tanto em `web-sync` quanto em `stack-production`, só a linha de versão é tocada, nunca um secret — o valor é sempre uma tag SemVer de formato controlado, seguro pra `sed` sem risco de caractere especial.

## 2. Secrets & Environment

- **`api-sync` precisa do Environment `api-production`**: é o único job que renderiza o `.env.prod` com os secrets de app (Postgres/Redis/MinIO/JWT/Admin) — build/backup/migrate/deploy-container só usam o secret de repositório (`SSH_DEPLOY_KEY`), não precisam do Environment.
- **`.env.prod` renderizado localmente, não via `sed` remoto**: evita qualquer problema de escaping de caractere especial em senha/segredo dentro de um comando SSH remoto. O arquivo só existe no runner efêmero e no destino final (VM), nunca commitado.
- **`web-production` Environment mantido mesmo sem secrets**: hoje só o `api` tem secrets de app; o Environment é mantido no job que efetivamente troca o container do web só pelo tracking de deployment que o GitHub associa a um Environment (visível na aba "Environments" do repo).
- **`CLIENT_API_KEY` (consumida pelo `web`) mora no Environment `api-production`**: como `api-sync` é o único job que renderiza o `.env.prod` inteiro, qualquer secret que precise chegar no arquivo — mesmo que só o `web` a consuma — tem que estar nesse Environment. `docker-compose.prod.yml` interpola `${CLIENT_API_KEY}` no serviço `web` a partir desse mesmo `.env.prod`.
- **`TURNSTILE_SITE_KEY` é `vars`, `TURNSTILE_SECRET_KEY` é `secrets`** (ambos no Environment `api-production`, pelo mesmo motivo da `CLIENT_API_KEY` acima — só o `web` as consome): a site key é pública por natureza (vai renderizada no HTML do formulário de Suporte), então fica como variável para poder ser lida de volta pelo `gh variable list`; só a secret key, usada no `siteverify` server-side, precisa de mascaramento.
- **`WEB_VERSION` preexistente sobrevive ao render**: o render do `.env.prod` (job `api-sync`) só sabe a versão da api — antes de mandar o arquivo novo, preserva o valor atual do `WEB_VERSION` do arquivo remoto.
- **Placeholder do nginx via `sed`, não `envsubst`**: o IP privado da E2.1.Micro é substituído no `nginx.conf` via `sed`, não `envsubst` do próprio nginx — de propósito, pra não colidir com as variáveis nativas do nginx (`$host`, `$remote_addr` etc.) que também usam a sintaxe `$NOME`.

## 3. Job de Reconciliação da Stack `(ver ticket 12)`

Evolução do `infra-production` `(ver ticket 11)`: reconciliação **completa** da stack a partir do próprio `devops`, sem depender do `repository_dispatch`. Qualquer merge em `production` (fora docs/planos/terraform) sincroniza os arquivos de deploy e converge **todos** os containers, inclusive api/web pra última tag SemVer publicada nos repos deles (resolvida via API — a última release real que passou pelo CI, nunca a tag móvel `:latest`, proibida por decisão `(ver ticket 09)`/`(ver ticket 11)`). Cobre inclusive dispatch perdido: se o `repository_dispatch` de uma release falhar, o próximo merge do `devops` converge a stack do mesmo jeito.

Não builda imagem nenhuma — só `pull` do que já existe no GHCR. Por isso não usa nenhum secret de Environment (`SSH_DEPLOY_KEY`/`SOURCE_REPO_PAT`/`VM_HOST` são de repositório — ver `docs/terraform-cloud-credentials-setup.md` seção 9.1). Edge case aceito (decisão 2026-07-03): bootstrap do zero, sem imagem api/web publicada ainda, falha no step de pull — esperado.

- **`pull` e `up` são passos separados**: se a imagem não existir no GHCR (bootstrap do zero), a falha fica isolada e visível aqui, sem mascarar o resto da reconciliação.
- **`up -d` simples (sem `--force-recreate`) resolve mudança de config** `(ver ticket 10)`: o Compose detecta sozinho mudança de `cpus`/`environment`/etc. definidos direto no `docker-compose.prod.yml` (foi o caso do fix de throttle do Postgres — só pegou depois de um `--force-recreate` manual, porque nenhum job recriava esse serviço). Se nada relevante mudou, `up -d` é no-op.

## 4. Observability & Logging

- **Log de query do Postgres**: nativo do Postgres avaliado e descartado (2026-07-03) — decisão consciente de usar `PRISMA_QUERY_LOG=true` no `api` em vez disso, que já correlaciona com `traceId`/`spanId` da requisição via OTLP (ver `api/src/lib/prisma.ts` e `logger.ts`).
- **Alloy substitui o `otelcol`/`promtail` em produção**: roda na A1.Flex, envia tudo (traces/métricas/logs) pra Prometheus/Loki/Tempo na E2.1.Micro via IP privado da VCN. Variáveis de ambiente necessárias: `PROMETHEUS_REMOTE_WRITE_URL`, `LOKI_URL`, `TEMPO_ENDPOINT`.
- **`web` ganhou instrumentacao OTel propria (ticket observabilidade Next.js)**: antes so o `api` exportava pro Alloy; o `web` nao tinha nenhuma telemetria de dentro do processo Node, so as metricas de cgroup do cAdvisor (sintoma, nunca causa). Mesmo padrao do `api` (`NodeSDK` + `instrumentation-runtime-node`), registrado via hook `instrumentation.ts` do Next (codigo do SDK isolado em `lib/otel-node.ts` e carregado via `import()` dinamico so no runtime nodejs — o Next tambem builda `instrumentation.ts` pro Edge Runtime, que nao tem `process.on`).
- **Logs 100% via OTLP** (`pino-opentelemetry-transport` no api), sem arquivo/tail — trade-off consciente: se o Alloy cair, logs gerados nessa janela se perdem (sem buffer em disco). Aceito por ora; revisitar só se causar problema real em produção.
- **Grafana `anonymous-auth` desabilitado em produção** `(ver ticket 05)`: o arquivo base (`docker-compose.observability.yml`) habilita `GF_AUTH_ANONYMOUS_ENABLED=true` com role Admin, conveniência pro dev local — em produção isso daria acesso admin total sem login pra qualquer um que chegasse em `grafana.oikos.company`. Como o Grafana é protegido só pelo login próprio (sem Cloudflare Access), essa senha forte precisa ser a única barreira de verdade.
- **Porta OTLP gRPC do Tempo exposta pro host** (só em produção): é como o Alloy da A1.Flex (VM diferente) alcança o Tempo via IP privado. Em dev local não precisa disso (o `otelcol` fala com o Tempo dentro da rede Docker interna).

## 5. Orçamento de Capacidade

### VM de produção — A1.Flex (2 OCPU / 12GB)

Migrado de `oikos/api/docker-compose.prod.yml` `(ver ticket 01)`, ganhou `web`, `nginx` e a camada de observabilidade (Alloy/cAdvisor/node-exporter). Certificado Cloudflare Origin CA (`certs/cloudflare-origin.pem/.key`) materializado pelo deploy `(ver ticket 09)`, nunca commitado. Só `api` e `web` são buildados a partir de contexto local (checkout dos repos irmãos); em produção real, `image:` (GHCR) é o que efetivamente roda — `build:` é só pra `docker compose build` local antes do primeiro deploy `(ver ticket 06)`.

| Serviço | Memória |
|---|---|
| postgresql | 512 MB |
| redis | 128 MB |
| minio | 256 MB |
| api | 512 MB |
| web | 512 MB |
| nginx | 64 MB |
| cadvisor | 128 MB |
| node-exporter | 64 MB |
| alloy | 128 MB |
| **Total** | **~2.3GB de 12GB disponíveis** |

CPU do Postgres bumpado de `1.0` pra `1.5` — achado em produção (2026-07-03): o container ficava throttled quase o tempo todo no limite de `1.0`; os outros serviços (exceto cadvisor) usam bem menos que o próprio limite, então há folga real na VM (2 OCPU) pra dar mais CPU ao Postgres.

### VM de observabilidade — E2.1.Micro (1GB), produção

Override aplicado só na E2.1.Micro, nunca em dev local `(ver ticket 07)`/`(ver ticket 09)`. Reconciliado automaticamente pelo job `stack-production` do `deploy.yml` a cada push em `production` `(ver #6)` — o comando abaixo é só referência/uso manual:

```
docker compose \
  -f docker-compose.observability.yml \
  -f docker-compose.observability.prod.yml \
  up -d --no-deps prometheus loki tempo grafana alertmanager
```

`--no-deps` é obrigatório aqui: `prometheus` tem `depends_on: otelcol` no arquivo base, e sem `--no-deps` o compose sobe o `otelcol` também mesmo sem estar na lista — que colide na porta `4317` do host com o `tempo` (achado em produção, ver #6).

`otelcol` e `promtail` ficam de fora — substituídos pelo Alloy rodando na A1.Flex (item 4 acima), mesmo estando declarados no arquivo base.

| Serviço | Memória (dev local) | Memória (produção) |
|---|---|---|
| prometheus | 512 MB | 200 MB |
| loki | 256 MB | 150 MB |
| tempo | 256 MB | 256 MB `(ver #6)` |
| grafana | 256 MB | 180 MB |
| alertmanager | 64 MB | 25 MB |
| **Total (produção)** | | **~811MB de 1GB — folga menor, mas real; swap (8-10GB, ver cloud-init) como rede de segurança pra picos** |

### Stack de observabilidade — dev local (~1.7GB)

`otelcol` 512MB (recebe OTLP, fan-out pra Tempo/Prometheus/Loki), `prometheus` 512MB, `loki` 256MB, `tempo` 256MB, `promtail` 64MB (tailing dos logs do Pino), `grafana` 256MB, `alertmanager` 64MB. Não sobe junto com `docker-compose.prod.yml`.

Pré-requisito: `cp observability/.env.observability.example observability/.env.observability` com senha gerada via `openssl rand -base64 32`. Subir com `npm run obs:up`, acessar Grafana em `http://localhost:3000`.

## 6. Gotchas / Achados em Produção

- **`io_method=sync` no Postgres** (2026-07-03): Postgres 18 usa `io_method=worker` por padrão (processos "io worker" dedicados), e o container ficou throttled ~99% dos períodos de CPU (`cpu.stat`/`nr_throttled`) rodando só com `pg_isready` de healthcheck, sem query real ativa. `sync` é o método clássico (pré-PG18), sem os workers extras.
- **cAdvisor precisa do mount de `containerd.sock`** `(ver ticket 07)`: sem isso, a factory de detecção de container Docker do cAdvisor falha (Docker usa containerd por baixo) e ele só enxerga cgroups agregados (systemd/raw), sem nenhuma métrica por container — achado no bootstrap real: `container_memory_usage_bytes` existia, mas sem nenhum label de container (nem `name`, nem `container_label_*`).
- **`127.0.0.1` explícito no healthcheck da `api`, não `localhost`** `(ver ticket 06)`: dentro do container, `localhost` resolve pra `::1` (IPv6) primeiro, e o Fastify só escuta em IPv4 (`0.0.0.0`), causando falso-negativo de "connection refused" no healthcheck.
- **Bind-mount de arquivo único exige `--force-recreate`** `(ver ticket 11)`: `nginx.conf` e `alloy-prod.alloy` são montados como bind mount de arquivo único no `docker-compose.prod.yml`. `sed -i` (usado no `scp` do deploy) reescreve via arquivo temporário + rename, trocando o inode — um bind mount de arquivo único fica preso no inode antigo, então nem `nginx -s reload` nem `docker compose restart` enxergam o conteúdo novo (só recriar o container remonta o bind). Achado em produção: o fix do `www.oikos.company` não pegou mesmo depois do deploy, porque o container do nginx nunca tinha sido recriado desde o bootstrap.
- **Tempo ficou morto 4 dias sem ninguém notar** (2026-07-07): OOM-killed (anon-rss ~110MB contra um teto de 120MB) recebendo trace de só o `api`; `web` passou a mandar trace também e o teto já não tinha folga nenhuma pro pico. Nenhum serviço do `docker-compose.observability.yml` tem `restart` definido no arquivo base (todos `"no"`, apropriado pra dev local efêmero) — o override de produção não corrigia isso pra nenhum dos 5 serviços, então o Tempo simplesmente nunca voltou. Agravante: até então a stack de observabilidade da E2.1.Micro nunca era reconciliada pelo `deploy.yml` — só a config do Alloy (na A1.Flex) ia por CI, o resto era comando manual, então nem uma correção de código chegava lá sozinha. Só foi descoberto quando o Grafana passou a devolver 502 (Cloudflare) ao consultar trace. Fix: `restart: unless-stopped` nos 5 serviços no override de produção + memória do Tempo 120MB → 256MB, e o job `stack-production` do `deploy.yml` ganhou um step que sincroniza `observability/` e roda `docker compose up -d` na E2.1.Micro via bastion pela A1.Flex. Três tentativas até esse step funcionar de ponta a ponta em produção: (1) `ProxyJump` não propaga a identidade `-i` explícita pro salto — "Permission denied (publickey)", trocado por `ProxyCommand` explícito, mesmo achado que já motivava o comando documentado pro operador em `docs/infrastructure.md`; (2) a chave de host da E2.1.Micro nunca tinha sido aceita pelo runner efêmero (só a da A1.Flex passa por `ssh-keyscan`) — "Host key verification failed", resolvido com `StrictHostKeyChecking=accept-new` no destino (aceitável, IP privado da VCN só alcançável via bastion); (3) faltava `--no-deps` no `up -d` — sem ele o compose sobe o `otelcol` também (dependência do `prometheus` no arquivo base), que colide na porta `4317` do host com o `tempo`.

## 7. Provisionamento Declarativo da VM

Regra central do provisionamento `(ver ticket 06, plano infra-cicd-v2)`: **o que não está no Terraform/cloud-init/pipeline não existe**. Nenhum passo manual feito na VM sobrevive a um redeploy (recriação da instância) — foi exatamente isso que derrubou o `oikos-backup.*` e o `oikos-web-restart.timer` sem ninguém notar. Tudo o que a aplicação precisa tem que estar materializado em um dos três lugares; se não está, assuma que não existe.

- **O cloud-init cria `/opt/oikos` e subdiretórios com dono `deploy`**: `/opt` é root-owned e o usuário `deploy` não consegue criar diretório lá (`mkdir: cannot create directory: Permission denied`). O `/opt/oikos` só existia porque alguém rodou `mkdir` com `sudo` no bootstrap — numa VM nova o primeiro deploy morreria no `mkdir -p /opt/oikos/docker/certs`. A árvore inteira (`docker/certs`, `nginx`, `observability`, `scripts`) agora é criada pelo cloud-init com `chown deploy:deploy`, junto com os três fragmentos de env já com permissão `600`.
- **Sem units systemd geridas pelo repo** ([T09](../plans/infra-cicd-v2/tickets/09-revisar-scripts-e-systemd.md), 2026-08-17): existiram duas (`oikos-backup.*`, removida no ticket 02; `oikos-web-restart.*`, removida no T09) e as duas foram desativadas por terem deixado de fazer sentido — não por ter surgido um jeito melhor de instalar unit. `scripts/reconcile-systemd.sh` e `docker/systemd/` foram removidos junto, por não terem mais nenhuma unit pra reconciliar. Se surgir necessidade real de novo, o mecanismo (reconciliação pelo pipeline, não pelo cloud-init — evita duplicar conteúdo entre repo e template Terraform) está descrito no registro de execução do [T06](../plans/infra-cicd-v2/tickets/06-provisionamento-declarativo.md).
- **`swap_size_gb = 0` na A1.Flex é deliberado, não bug**: 12GB de RAM com ~1.3GB em uso — a E2.1.Micro (1GB) é que recebe os 9GB de swap como rede de segurança. Não "corrigir" esse zero por engano.

## 8. Backup & Migração de Dados

O backup automatizado foi **removido do caminho de deploy e do repositório** (2026-08-14, [devops#76](https://github.com/oikos-circular-environment/devops/issues/76)). Não existe mais job de backup no `deploy.yml`, nem `scripts/backup-postgres.sh`/`backup-redis.sh`, nem as units `docker/systemd/oikos-backup.service`/`.timer`. Na VM ele também já não rodava de fato: a OCI CLI (instalada manualmente, uma única vez) e as units systemd nunca voltaram depois que a VM foi recriada num redeploy. O redesenho é a issue [devops#90](https://github.com/oikos-circular-environment/devops/issues/90).

- **Por que saiu do caminho de deploy**: o job `api-backup` bloqueava deploy de código sem nenhuma relação com backup — foi assim que a `api` ficou um mês travada na `v0.1.1`, porque `api-migrate` e `api-deploy-container` dependiam dele via `needs:`. Backup passa a ser assunto próprio, fora do fluxo de release.
- **`infra/terraform/storage/` mantido de propósito**: bucket `oikos-backups` + `oci_identity_dynamic_group` + `oci_identity_policy` + lifecycle continuam no repo — o caro de recriar é o IAM escopado ao OCID da instância, não o bucket (vazio, custa zero); o redesenho (#90) vai reusar.
- **Migração one-time de dados removida** (`scripts/migrate-data.sh`, [T09](../plans/infra-cicd-v2/tickets/09-revisar-scripts-e-systemd.md)): existia só pro cutover Postgres + MinIO da máquina de desenvolvimento pra VM Oracle (ticket 10 do `oracle-cloud-migration`, já concluído). A infra foi reconstruída do zero duas vezes desde então sem precisar dele — código morto. Fica recuperável no histórico do git se outro cutover for necessário no futuro.

Procedimento de restore (não de backup) está em [`docs/backup-restore-runbook.md`](./backup-restore-runbook.md) — continua sendo a referência de restore manual dos objetos do bucket `oikos-backups`, que segue existindo.
