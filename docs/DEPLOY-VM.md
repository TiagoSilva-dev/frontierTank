# Frontier Tank na VM

## Correcao do acesso online (28/09/2026)

- Web, API e multiplayer publicados no commit `c0e24cd`. Servidor `s1`, **S1 · Ilha Celeste**, em `wss://gustfire.online/ws`; cupons de teste habilitados.
- Corrigido o proxy HTTPS: `gzip off` na rota `/v1/`. O navegador ja descompactava a resposta, mas Godot tentava descompacta-la novamente (`stream_peer_gzip.cpp`), fazendo a tela mostrar apenas o modo offline mesmo com a API funcionando.
- A mesma regra foi adicionada a `server/docker/web.nginx.conf` para os proximos deployments. O proxy externo da VM tambem precisa conservar essa regra.
- Validacao no navegador: `/v1/servers` retorna 200 sem erro de descompactacao; a tela exibe S1 e os campos de login. WebSocket verificado com HTTP 101.
- Banco ativo: `gustfire`, usuario `gustfire_app`, esquema `public` no PostgreSQL Railway. Cinco migracoes aplicadas e 13 tabelas: `access_log`, `accounts`, `auction_listings`, `auction_ops`, `audit_log`, `chat_reports`, `game_servers`, `mail`, `presence`, `profiles`, `schema_migrations`, `sessions`, `store_orders`.
- Operacao: `.deploy/compose.api.yaml` e `.deploy/compose.game.yaml` na VM. Assets do multiplayer importados localmente antes de construir a imagem, devido a memoria limitada da VM. Registro: `.deploy/release-c0e24cd.json`.

## Historico da atualizacao anterior

- Commit ativo no site e jogo: `11f3e92` (`melhorias`). Pull fast-forward aplicado na VM e no checkout local.
- Exportacao web concluida; `tests/launch_tests.gd`: 126 verificacoes, zero falhas.
- Pacote web enviado e conferido por SHA256; container `frontier-tank-web` reiniciado; site e jogo retornam HTTP 200 por HTTPS.
- Backup da exportacao anterior: `/home/ubuntu/frontierTank/.deploy/web-before-11f3e92.tar.gz`.
- API tambem publicada no commit `11f3e92`, com PostgreSQL Railway.

## API com PostgreSQL Railway (ativa)

- Imagem `frontier-tank-api:11f3e92` compilada na VM; container `frontier-tank-api` ativo.
- Endpoint: `https://gustfire.online/v1/health`, resposta 200 com `{"status":"ok"}`.
- Banco exclusivo `gustfire`, usuario exclusivo `gustfire_app`, host `viaduct.proxy.rlwy.net`, porta `44031`. Conexao TLS confirmada; o usuario da aplicacao nao e superusuario e nao cria bancos ou roles.
- Cinco migracoes aplicadas, 13 tabelas. `/v1/servers` retorna lista vazia porque o servidor multiplayer ainda nao foi iniciado.
- Testes de integracao do commit anterior passaram com PostgreSQL 17 descartavel local. Nesta implantacao foram conferidos TLS, permissoes, migracoes, saude com banco real, autenticacao obrigatoria (401) e bloqueio da rota interna no proxy publico (404).
- Compose em `/home/ubuntu/frontierTank/.deploy/compose.api.yaml`, com reinicio automatico, limite de 128 MB e nenhuma porta publicada diretamente.
- Nginx encaminha `/v1/` diretamente a API, preservando o IP real do cliente. Site e jogo continuam acessiveis por HTTPS.
- Credenciais exclusivas em `/home/ubuntu/frontierTank/.deploy/api.env`, permissao 600. `.deploy/` esta excluido do Git via `.git/info/exclude`. Nunca registrar os segredos neste documento ou no Git.
- Para reiniciar: `docker compose -f /home/ubuntu/frontierTank/.deploy/compose.api.yaml restart api`.
- Para verificar banco/migracoes: `python3 /home/ubuntu/frontierTank/.deploy/verify-gustfire-db.py`.

## Dominio gustfire.online (27/09/2026)

- DNS confirmado nos dois servidores autoritativos da GoDaddy: `A @ = 136.248.73.212`, TTL 600; `CNAME www = gustfire.online`.
- O nginx ja reconhece `gustfire.online` e `www.gustfire.online` na porta 80. Site, jogo e rota de validacao ACME testados usando o cabecalho Host.
- HTTPS ativo em `https://gustfire.online/` e `https://gustfire.online/jogar/`. O dominio foi publicado no DNS publico durante a configuracao.
- Certificado Let's Encrypt emitido para os dois nomes, valido ate 26/12/2026, com renovacao automatica. Simulacao de renovacao concluida com sucesso.
- Configuracao HTTPS ativa: `/home/ubuntu/alocativateam/al-infra/nginx/conf.d/zz-gustfire.conf`.
- Copia: `/home/ubuntu/frontierTank/.deploy/gustfire-https.nginx.conf`.

Para reaplicar a configuracao ou testar a renovacao na VM:

```bash
bash /home/ubuntu/frontierTank/.deploy/ativar-gustfire-https.sh
sudo certbot renew --cert-name gustfire.online --dry-run
```

O script verifica o DNS, emite o certificado para os dois nomes, testa e recarrega o nginx, redireciona HTTP e www para `https://gustfire.online`, e instala um hook de recarga para a renovacao automatica pelo timer existente do Certbot. O script ja foi executado com sucesso. Os arquivos locais `gustfire-*.nginx.conf` e `gustfire-renew-hook.sh` sao as copias dessa configuracao.

Destinos ativos: site em `https://gustfire.online/` e jogo em `https://gustfire.online/jogar/`. A configuracao HTTPS habilita o contexto seguro exigido pelo Godot; a API e o banco estao ativos, mas o modo multiplayer ainda depende de iniciar o servidor de jogo.

- VM: `ubuntu@136.248.73.212`
- Repositorio: `/home/ubuntu/frontierTank`
- Container: `frontier-tank-web`, nginx, reinicio automatico `unless-stopped`, limite de RAM 96 MB.
- Porta na VM: `8000`.
- Site publico: `http://136.248.73.212/`.
- Site: `http://localhost:18000/` pelo tunel SSH.
- Jogo: `http://localhost:18000/jogar/` pelo tunel SSH.

## Acesso

Execute `powershell -ExecutionPolicy Bypass -File .\AbrirFrontend.ps1` se o tunel nao estiver ativo. Mantenha a janela aberta. A porta local 18000 precisa estar livre.

O tunel original na porta 18789 atende outro servico. O frontend usa 18000 local -> 8000 na VM.

O acesso publico usa o nginx existente nas portas 80 e 443. Prefira o dominio com HTTPS para abrir o jogo. O acesso pelo IP continua disponivel para o site; o tunel em `localhost` permanece como alternativa de teste.

O acesso direto a `http://136.248.73.212:8000/` nao respondeu no teste externo. O acesso publico na porta 80 e o tunel ja funcionam.

## Escopo

Frontend estatico, exportacao web do Godot e API na VM; banco PostgreSQL na Railway. Servidor multiplayer ainda nao iniciado. Use o modo offline no jogo por enquanto. A VM tem aproximadamente 1 GB de RAM e ja executa outros servicos.

## Operacao na VM

```bash
docker ps --filter name=frontier-tank-web
docker logs --tail 50 frontier-tank-web
docker restart frontier-tank-web
```

O site e servido de `website/` e o jogo de `build/web/`, ambos montados como somente leitura no nginx. Configuracao nginx: `server/docker/web.nginx.conf`.

O proxy publico usa `/home/ubuntu/alocativateam/al-infra/nginx/conf.d/zz-frontier-ip.conf`. Os containers `alocativa-nginx` e `frontier-tank-web` estao conectados a rede Docker `frontier-web-proxy`. Se algum deles for recriado, reconectar essa rede antes de recarregar o nginx. Os dominios existentes continuam com as configuracoes anteriores.

## Atualizar a exportacao

Prefira gerar os arquivos no computador e copiar `frontierTank/build/web/` para `/home/ubuntu/frontierTank/build/web/` via SCP. A primeira importacao na VM foi interrompida devido ao uso intenso de swap. O build local terminou sem erros.

Para exportar na VM caso haja memoria suficiente:

```bash
cd /home/ubuntu/frontierTank
GODOT_BIN=/home/ubuntu/frontierTank/.deploy/Godot_v4.7.2-stable_linux.x86_64 python3 tools/web_build.py export > .deploy/export.log 2>&1
```

O processo pode consumir bastante memoria durante a importacao. Acompanhe `tail -20 .deploy/export.log`. Os arquivos sao servidos diretamente depois da exportacao.
