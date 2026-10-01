# Casa de Câmbio — 0.17

Implementação local em `/home/tiago/Frontier Tank`. Nenhuma publicação na VM nesta entrega.

## Referência e adaptação

Referência: [guia de Currency Exchange do PoE 2, Mobalytics](https://mobalytics.gg/poe-2/guides/currency-exchange), consultado em 28/09/2026 (artigo atualizado em 04/01/2025). A referência apresenta seleção de “Tenho”/“Quero”, proporção escolhida pelo jogador, consulta de ofertas disponíveis e concorrentes, taxa em ouro, ordens pendentes e cancelamento com devolução do saldo. É inspiração de funcionamento; os parâmetros abaixo são próprios do Gustfire.

## O que o jogador usa

- A Casa de Câmbio ocupa o lugar de Namoro na cidade. Funciona entre jogadores online; ofertas já criadas permanecem disponíveis quando seu dono sai.
- Aceita Brasa, Coroa, Estrela, Tormenta, Solar, Eclipse, Espelho e as 12 pedras de fortalecimento. Qualquer par diferente é permitido. Armas, mapas, equipamentos e ouro não entram nas trocas.
- “Tenho” e “Quero” definem a proporção de cada lote. Quantidade de lotes define o total. O seletor tem busca, filtros Moedas/Pedras e “Tenho saldo”.
- Até 10 ofertas ativas por conta. Máximo de 1.000.000 unidades de cada lado por oferta.
- Taxa ao criar: **5 + arredondamento para cima(total oferecido / 100)** em ouro. Exemplo: oferecer 200 Brasas custa 7 de ouro. Cancelar não devolve essa taxa. Falhas de validação ou de transação não consomem a taxa.
- O saldo oferecido sai da mochila e fica reservado na mesma transação que cria a oferta.
- O livro mostra até 50 ofertas disponíveis e 50 concorrentes no par escolhido, sem incluir ofertas da própria conta. Atualizar consulta preços e histórico. “Usar cotação” preenche a melhor oferta disponível; não garante disponibilidade até a confirmação.
- O preço da oferta que já estava no mercado determina a execução. Entre preços iguais, vence a oferta mais antiga. Ofertas da mesma conta nunca negociam entre si.
- Execuções podem ser parciais. Não existem frações de moeda ou pedra: razões são simplificadas e a execução usa múltiplos inteiros compatíveis com as duas ofertas. Um saldo pequeno pode aguardar outra oferta mesmo com preço compatível.
- Exemplo: alguém oferece 1 Estrela por 2 Brasas. Você aceita pagar até 3 Brasas por Estrela e pede 2. Reservamos 6 Brasas; a troca consome 4, entrega 2 Estrelas e devolve 2 Brasas.
- O Correio entrega receitas, trocas e economia obtida com preço melhor. Cancelar envia apenas o saldo ainda reservado ao Correio. Os créditos só entram na mochila ao receber, com a proteção existente contra resgate duplicado.
- Sem jogadores oferecendo o par, o livro fica vazio. Não há ofertas artificiais nem conversão por NPC.

## Persistência e concorrência

`server/api/migrations/006_exchange.sql` cria `exchange_orders`. O PostgreSQL mantém quantidades, lotes restantes, taxa e estado. Exclusão de conta remove suas ofertas por FK; exportação de dados inclui seu histórico de câmbio.

O cliente envia a intenção. `GameServer.exchange_request` valida saldo, quantidades inteiras e estado do jogador; bloqueia operações simultâneas da sessão e envia o perfil já debitado. A API grava perfil/versionamento, custódia, execuções, correio e auditoria em uma transação. Uma trava transacional serializa o casamento de ofertas e cancelamentos. IDs de operação reutilizam a proteção contra repetição já usada no Leilão. Em resposta incerta, o servidor repete o mesmo ID; se continuar incerta, descarta sua cópia do perfil e exige reconexão.

Rotas internas autenticadas: `POST /internal/exchange/book`, `/create`, `/cancel`. A versão do jogo é 0.17: publicar cliente e servidor juntos. O modo de API em memória usado em testes LAN não oferece câmbio; o serviço exige PostgreSQL.

## Interface e arte

A interface usa painéis escuros, bordas douradas e os ícones existentes das moedas e pedras, coerentes com o ferreiro. O prédio é próprio (`assets/city/buildings/exchange.png`, 0.18): banco de cúpula verde-cobre com moeda dourada, baús de gemas e pilhas de moedas, gerado no PixelLab e centrado no lote calçado da direita. Antes usava o sprite do Leilão. Capturas com dados ilustrativos: `docs/screens/exchange_market.png` e `exchange_picker.png`.

## Verificação local

- `tests/exchange_tests.gd`: catálogo, limites, saldo, taxa, correio de pedras, reversão e acesso na cidade.
- `server/api/exchange_test.go`: matemática inteira, prioridade por preço/tempo, idempotência, cancelamento, limite, exclusão de conta, conflitos de versão e compradores concorrentes. Executar `go test ./...` com `TEST_DATABASE_URL` apontando **somente para banco descartável**; o harness recria as tabelas.
- `tests/exchange_online_tests.gd`: API PostgreSQL local nas portas 17880/17881, chave de teste `exchange-local-key` e servidor de jogo local 7398. Cria contas descartáveis, negocia pedras, recebe Correio e cancela saldo restante. Nenhuma chamada à produção.
- `tests/exchange_visual_check.gd -- market|picker`: captura com perfil em memória, sem carregar save real.

## Publicação futura

Reconstruir a API para aplicar a migração 006; publicar servidor de jogo e exportação web 0.17 juntos. Preservar `gzip off` no proxy de `/v1/`. Não reutilizar banco de produção para os testes de integração.

### Resultado desta entrega

264 verificações Godot passaram: câmbio 15, integração online com PostgreSQL 25, leilão 62, interface 79, idiomas 25 e rede 58. A suíte completa da API (`go test ./...`) passou com banco descartável, incluindo cinco testes do câmbio. As capturas do mercado e seletor foram revisadas. `tools/i18n.py --check` passou com 1.191 chaves e nenhuma tradução inglesa faltante.

Os testes de interface tiveram suas preparações ajustadas ao TESTARTUDO ampliado: o teste isolado de mapas limpa os mapas recebidos anteriormente e a verificação de Solar usa o saldo real do perfil.
