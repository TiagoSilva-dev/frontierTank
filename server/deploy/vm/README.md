# Implantação do Gustfire na VM

Configurações e scripts usados na VM `136.248.73.212`, com o projeto em
`/home/ubuntu/frontierTank`. O estado da implantação e os comandos de operação
estão em [docs/DEPLOY-VM.md](../../../docs/DEPLOY-VM.md).

Estes arquivos pressupõem o frontend já iniciado e o proxy nginx existente,
conectados à rede Docker `frontier-web-proxy`. Os caminhos dos scripts são
específicos dessa VM.

## Preparar os arquivos

No checkout da VM, copie as configurações para o diretório operacional:

```bash
mkdir -p .deploy
cp server/deploy/vm/*.sh server/deploy/vm/*.py server/deploy/vm/*.conf \
   server/deploy/vm/compose.api.yaml .deploy/
```

Essa cópia não inicia serviços. `gustfire-http.nginx.conf` serve para a primeira
emissão do certificado; `gustfire-https.nginx.conf` é a configuração final.
O proxy ativo fica em
`/home/ubuntu/alocativateam/al-infra/nginx/conf.d/zz-gustfire.conf`.

## API e banco

`provision-gustfire-db.py` recebe por stdin um objeto JSON com `host`, `port`,
`user` e `password` do administrador Railway. Cria o banco `gustfire` e o usuário
restrito `gustfire_app`, com senha aleatória. Não coloque credenciais em arquivos
versionados ou na linha de comando. Use uma ferramenta de segredos ou uma entrada
interativa protegida para fornecer esse JSON.

O script grava apenas as credenciais da aplicação e sua chave interna em
`.deploy/api.env`, com permissão `600`. Esse arquivo e o diretório `.deploy/`
são ignorados pelo Git. A senha administrativa não é gravada.

```bash
docker build -t frontier-tank-api:11f3e92 server/api
bash .deploy/start-gustfire-api.sh
python3 .deploy/verify-gustfire-db.py
```

Para publicar outro commit, atualize a tag da imagem em `compose.api.yaml` e
compile com a mesma tag. A API executa as migrações ao iniciar.

`start-gustfire-api.sh` verifica a saúde da API e as migrações antes de ativar
a rota `/v1/` no proxy. Não inicia o servidor multiplayer.

## HTTPS

`ativar-gustfire-https.sh` usa o Certbot já instalado e configurado na VM,
emite o certificado para `gustfire.online` e `www.gustfire.online` e instala
`gustfire-renew-hook.sh` para recarregar o nginx após a renovação.
Requer DNS apontando para a VM e a rota ACME HTTP previamente configurada.

`AbrirFrontend.ps1` abre um túnel SSH opcional no Windows; o site público
funciona diretamente em `https://gustfire.online/`.
