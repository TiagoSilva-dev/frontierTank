# Painel administrativo (`/admin/`)

Uma página para a equipe operar o jogo sem mexer no banco: números do dia, jogadores, denúncias, pagamentos, leilão, presentes e o registro de tudo o que foi feito. Fica **dentro da API em Go** (`server/api/admin*.go`), com a interface embutida no binário (`server/api/admin_ui/`, HTML, CSS e JavaScript puros, sem build), então sobe junto com a API em qualquer lugar (Docker local, VM, Railway) e não precisa de serviço novo. O nginx do serviço `web` encaminha `/admin/` para a API.

Vem **desligado**: só existe com `ADMIN_ENABLED=1`.

## Ligar

Em `server/.env` (ou nas variáveis do serviço `api` no Railway):

```
ADMIN_ENABLED=1
ADMIN_BOOTSTRAP_USER=dona
ADMIN_BOOTSTRAP_PASSWORD=<12 a 128 caracteres>
```

Ao subir, a API cria o **primeiro dono** com esse par, só se ainda não existir nenhuma conta da equipe (a senha vale uma vez: o primeiro acesso exige trocá-la). Depois do primeiro acesso, **apague as duas variáveis**. `tools/local.sh` (e `local.ps1`) já fazem isso numa instalação nova: usuário `admin`, senha aleatória escrita em `server/.env`, painel em `http://localhost:8000/admin/`.

No primeiro acesso, nesta ordem: o painel mostra a chave do **autenticador** (Google Authenticator, Authy, 1Password...; é a chave digitada, não há QR code), pede o primeiro código de 6 dígitos e depois a troca da senha.

| Variável | Para quê |
|---|---|
| `ADMIN_ENABLED` | `1` liga o painel. |
| `ADMIN_BOOTSTRAP_USER`, `ADMIN_BOOTSTRAP_PASSWORD` | Primeiro dono (só se não houver equipe). |
| `ADMIN_REQUIRE_2FA` | `1` (padrão): toda conta precisa do código do autenticador. `0` só para teste local. |
| `ADMIN_ALLOW_IPS` | Lista de endereços ou redes (`203.0.113.7, 10.0.0.0/8`) que alcançam o painel; fora dela a resposta é 404. Vazio = qualquer endereço. Veja "Endereço do jogador" abaixo. |
| `ADMIN_SECURE_COOKIE` | `1` ou `0` força a marca `Secure` do cookie. Vazio: segue `X-Forwarded-Proto` (o nginx repassa o do proxy de borda). No Railway, ponha `1`. |
| `ADMIN_SESSION_HOURS`, `ADMIN_IDLE_MINUTES` | A sessão acaba depois de 12 h, ou de 120 min sem uso. |
| `ADMIN_AUDIT_DAYS` | Quanto tempo o registro de ações da equipe fica (1826 = 5 anos; `0` = para sempre). |

## O que tem

| Página | Para quê | Papel mínimo |
|---|---|---|
| **Visão geral** | Online agora, contas, novas contas, quem jogou em 24 h/7 d/30 d, receita por moeda (24 h, 7 d, 30 d), reembolsos, fila (denúncias abertas, pagamentos pendentes, anúncios, cartas não recebidas), alertas (partidas fora de sincronia, **pagamentos divergentes**, silenciamentos automáticos) e gráficos de 14 dias. Atualiza a cada 30 s; dias no horário de Brasília. | visualizador |
| **Jogadores** | Busca por usuário, personagem, ID, SteamID ou IP. A **ficha**: conta, save (campos e JSON completo), presença, acessos com IP, **outras contas no mesmo IP** (indício de várias contas de uma pessoa, ou rede compartilhada), pedidos, correio, leilão, denúncias, anotações, ações da equipe sobre a conta e a atividade recente do jogo. | suporte |
| Ações na ficha | **Anotar**, **Presentear** (moedas e pedras pelo Correio), **Banir** (motivo e prazo; desconecta em até 10 s) e **Desbanir**, **Encerrar sessões**, **Senha temporária** (para quem perdeu a senha; o jogo não tem e-mail), **Exportar dados** e **Excluir conta** (LGPD, só dono). | suporte (anotar, presentear); administrador (banir, sessões, senha); dono (exportar, excluir) |
| **Denúncias** | Fila do chat com a mensagem, a conversa em volta, o histórico do denunciado e o silenciamento automático; descartar, avisar ou banir. Substitui `tools/moderate.py` (que continua funcionando). | suporte (banir: administrador) |
| **Economia** | Moedas e pedras em circulação, **quem mais tem** de cada uma (onde olhar quando uma moeda infla), volume e comissões do leilão, ofertas do Câmbio. | visualizador |
| **Pagamentos** | Pedidos da Steam e do Stripe com busca e filtros, link para o pagamento no Stripe, mais vendidos em 30 dias. Reembolsos são feitos no Stripe e chegam sozinhos. | suporte |
| **Leilão** | Anúncios com o preço comparado à **mediana de 30 dias** do mesmo item (destaca preço fora do mercado) e **cancelar** (o item volta ao Correio do vendedor). | suporte (cancelar: administrador) |
| **Enviar presentes** | Envio em massa (todos, ativos em 30/7 dias, novos em 7 dias; só quem tem personagem e não está banido). Mostra quantos vão receber e **só envia se o número confirmado ainda for o mesmo**. | administrador |
| **Registro do jogo** | O `audit_log` com filtros (tipo, prefixo `op.*`, conta, texto, datas) e CSV. | suporte (CSV: administrador) |
| **Servidores** | Servidores de jogo (online, capacidade, tempo desde o último aviso), tamanho do banco. | visualizador |
| **Ações da equipe** | O registro do próprio painel: quem fez o quê, em quem, por quê e de que IP. | administrador |
| **Equipe** | Criar contas, mudar papel, desativar, reiniciar o 2FA, senha temporária. | dono |
| **Sistema** | Só leitura: o que está configurado (Stripe, Steam, retenção, Termos) sem mostrar segredos, migrações, maiores tabelas. | dono |
| **Minha conta** | Trocar a senha. | todos |

### Papéis

`visualizador` (só números), `suporte` (jogadores, denúncias, presentes pequenos), `administrador` (banir, presentes grandes, envio em massa, cancelar anúncios, CSV) e `dono` (equipe, exclusão e exportação de contas, sistema). Cada rota confere o papel no servidor; esconder um botão na página é só conforto.

Limites de um presente: suporte até 5.000 moedas e 50 de cada moeda ou pedra; administrador até 1.000.000 e 10.000; envio em massa até 100.000 e 1.000 por jogador.

## Segurança

- **Contas próprias**, separadas das dos jogadores: senha com PBKDF2 (como a dos jogadores) de 12 a 128 caracteres, mais **TOTP** (RFC 6238); o segredo fica cifrado no banco (AES-GCM, chave derivada de `INTERNAL_KEY`) e o mesmo código não vale duas vezes.
- Sessão em cookie `HttpOnly`, `SameSite=Strict`, restrito a `/admin`, e **token CSRF** em toda mudança, mais conferência de `Origin` e de `Content-Type: application/json`. Só o hash do token fica no banco.
- Login limitado por endereço (10 por minuto) e **5 erros seguidos bloqueiam a conta por 15 minutos**. Isso também permite que alguém, sabendo o usuário, bloqueie a conta de propósito; é a troca que o projeto aceita. Quem tem acesso ao banco desbloqueia: `UPDATE admin_users SET locked_until = NULL`.
- Cabeçalhos: `Content-Security-Policy` sem JavaScript embutido, `X-Frame-Options: DENY`, `no-store` na API, `noindex`. Todo texto vindo do jogo entra na página como texto, nunca como HTML.
- **Toda mudança exige motivo** e vai para `admin_audit` na **mesma transação** do efeito: não há ação sem registro nem registro sem ação. Presentes e envios em massa levam um identificador do navegador que os faz valer uma vez só (clique duplo, repetição).
- O painel **não edita o save** de ninguém: o servidor de jogo guarda uma cópia do perfil de quem está online e gravaria por cima. Compensações vão pelo Correio, que o jogador recebe pelo jogo, na transação que grava o perfil.
- Exportar e excluir dados de uma conta (LGPD) pedem papel de dono, motivo e, na exclusão, digitar o usuário; a exclusão exige o jogador **offline**. O registro de ações guarda o `account_id` mesmo depois da exclusão (prestação de contas); as anotações somem com a conta.

### Endereço do jogador (leia antes de abrir ao público)

A API enxerga o endereço que o nginx manda em `X-Forwarded-For`, que é `$remote_addr`. No Docker local e numa VM, é o do jogador. **No Railway, o mais provável é que `$remote_addr` seja o do proxy de borda deles**, não o do jogador (não conferi em produção: veja se `access_log.ip` varia entre contas). Se for isso, hoje o limite de login (por endereço), `ADMIN_ALLOW_IPS`, a coluna "mesmo IP" e os registros de acesso do Marco Civil veem o endereço do proxy. Para o painel, a consequência é que o limite de 10 logins por minuto passa a ser de todos juntos (alguém tentando basta para travar o login da equipe por um minuto) e que `ADMIN_ALLOW_IPS` não serve. A correção é do `server/docker/web.nginx.conf`: pegar o IP do jogador do cabeçalho que o Railway manda (conferir qual, e se dá para confiar nele) com o módulo `realip`. Enquanto isso não for feito, a defesa do painel no Railway é a senha forte, o 2FA e o bloqueio da conta.

## Presentes: o que pode ir

O Correio só entrega o que o jogo conhece; uma carta com um id desconhecido seria "recebida" sem dar nada. Por isso a API só aceita as **moedas e as pedras de fortalecimento** listadas em `server/api/admin_catalog.json`, gerado de `shared/balance/items.json` (os mesmos ids de `CurrencyExchange.valid_asset`):

```
python tools/admin_catalog.py           # regera
python tools/admin_catalog.py --check   # falha se estiver velho (rode depois de mudar items.json)
```

No jogo, a carta aparece como "Presente da equipe: <mensagem>" (`Auction.mail_title`), com a mensagem de até 80 letras que a equipe escreveu.

## Banimentos

`accounts` ganhou `ban_reason`, `ban_until`, `banned_at` e `banned_by`. `banned` continua sendo o que o login e os servidores de jogo leem; um banimento com prazo é desfeito pela rotina da API (a cada minuto) e a remoção fica no registro (`sistema`). Banir apaga as sessões do jogador, e o servidor de jogo desconecta quem está online no próximo `heartbeat` (até 10 s).

## Recuperação

- **Perdeu o autenticador** (outro dono): Equipe → Reiniciar 2FA. Se for o único dono, no banco: `UPDATE admin_users SET totp_secret = '', totp_enabled = false WHERE username = '<nome>'` e entre de novo.
- **Perdeu a senha** (outro dono): Equipe → Nova senha. Se for o único dono, apague a linha (`DELETE FROM admin_users WHERE username = '<nome>'`) e suba a API com `ADMIN_BOOTSTRAP_*` de novo (só cria se a tabela estiver vazia), ou gere outro dono por SQL.
- **Trocou `INTERNAL_KEY`**: os segredos do TOTP deixam de abrir; reinicie o 2FA de todos.

## Para ligar no Railway

1. No serviço `api`: `ADMIN_ENABLED=1`, `ADMIN_BOOTSTRAP_USER`, `ADMIN_BOOTSTRAP_PASSWORD` (forte) e `ADMIN_SECURE_COOKIE=1`.
2. Reimplante o `frontierTank` (o nginx ganhou o bloco `/admin/`) e a `api`. A migração `009_admin.sql` roda sozinha.
3. Abra `https://www.gustfire.online/admin/`, entre, cadastre o autenticador, troque a senha e **apague `ADMIN_BOOTSTRAP_*`**.
4. Leia "Endereço do jogador" acima.

## Testes

`server/api/admin_test.go` (TOTP com o vetor da RFC 6238, login e segundo fator, bloqueio, CSRF, papéis, ações e o registro, presentes e envio em massa, denúncias, leilão, LGPD, lista de endereços, cookie) roda com o resto da API, num banco descartável:

```
cd server/api && TEST_DATABASE_URL=postgres://frontier:frontier@localhost:5433/frontier?sslmode=disable go test ./...
```

A interface foi percorrida num navegador de verdade (Chromium headless): entrada com 2FA, troca da senha, todas as páginas, banir, presentear, senha temporária, envio em massa, criar conta da equipe e a tela de celular. Não há teste automatizado da interface no repositório.

## O que ainda não tem (próximos passos)

Pedem mudança no servidor de jogo (Godot), por isso ficaram de fora:

- **Manutenção e avisos**: avisar todos no chat, contagem regressiva e modo manutenção; o `heartbeat` já é o canal (hoje devolve só a lista de banidos).
- **Expulsar** sem banir.
- **Cupons de promoção** (código, validade, limite de usos) com resgate no jogo.
- **Presentear itens e mascotes** (hoje só moedas e pedras): o jogo precisa recusar o que o perfil não aceita antes de marcar a carta como recebida.
- **Reembolso pelo painel** (hoje no Stripe) e retirar do perfil as peças de um pedido reembolsado.
- Banir por IP ou aparelho, e uma tela de eventos (bônus de EXP e de drop por período).
