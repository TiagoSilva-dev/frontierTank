# Forja Celeste

Implementação local: `/home/tiago/Frontier Tank` (WSL). Sem publicação na VM.

## Fortalecimento

- Uma tentativa usa **uma pedra do nível de destino** e a taxa de ouro já existente. Exemplo: +8 → +9 exige uma pedra nível 9.
- A falha consome a pedra e a taxa; conserva o item, seus bônus e o nível atual.
- Chance de sucesso, custo, estoque e atributos antes/depois aparecem antes da tentativa.
- A operação é executada pelo perfil autorizado: offline no jogo, online no servidor. O cliente não escolhe o resultado.
- O botão fica bloqueado durante a operação e a animação para impedir cliques repetidos.
- Armas, roupas e chapéus continuam compatíveis. Transferência e Moedas foram preservadas.
- As quatro IDs antigas de pedra representam os níveis 1–4, conservando as quantidades nos saves. Os oito níveis seguintes usam novas IDs. Fortalecimentos existentes permanecem intactos.

| Nível de destino | Sucesso | Nível mínimo do mapa para a pedra |
|---|---:|---:|
| +1 | 100% | 1 / entrada livre |
| +2 | 95% | 1 / entrada livre |
| +3 | 90% | 2 |
| +4 | 85% | 3 |
| +5 | 80% | 4 |
| +6 | 75% | 5 |
| +7 | 65% | 7 |
| +8 | 55% | 8 |
| +9 | 45% | 10 |
| +10 | 35% | 12 |
| +11 | 25% | 14 |
| +12 | 20% | 16 |

São valores iniciais de balanceamento, centralizados em `shared/balance/items.json` → `strengthen`.

## Drops de monstros

- Sorteio pessoal: 30% de chance base para quem deu o golpe final.
- Sorteio do grupo: 12% de chance base; **cada participante recebe uma cópia completa** do mesmo item.
- Cada sorteio bem-sucedido escolhe pedra (75%), moeda de crafting (20%) ou arma (5%).
- Guardiões multiplicam as chances por 2; elites por 1,5; quantidade do mapa também aumenta as chances, limitadas a 100%.
- Chefes garantem uma pedra no sorteio do grupo, além da possibilidade de drop pessoal e das recompensas existentes da fase/baú.
- Pedras avançadas têm pesos menores; o nível do mapa libera novos níveis de pedra e a raridade aumenta o peso relativo das melhores.
- O dono de veneno/queimadura recebe o crédito quando o efeito mata. Mortes por queda usam o último atacante válido.
- Monstros invocados não dão drops. Uma morte só é registrada uma vez, mesmo com múltiplos projéteis ou verificações de fim da fase.
- Integrantes desconectados continuam recebendo; quem desistiu não recebe novos drops. O que já foi recebido permanece na mochila mesmo após derrota.
- O RNG de loot é separado da simulação da batalha. Online, apenas o servidor entrega e salva recompensas; a mensagem `mob_loot` atualiza o perfil e os avisos do cliente.
- A mochila recebe os itens imediatamente. A batalha mostra até três avisos por vez e enfileira o restante. O resultado inclui os drops de monstros; o texto de recompensas tem a lista completa no tooltip.
- Pedras não são vendidas na loja nem sorteadas nas cartas de PvP. As cartas de instância respeitam o nível mínimo da pedra.

## Arte e som

- PixelLab Pro: cenário original da forja e 12 pedras com silhuetas distintas. IDs das gerações em `assets/ui/forge/provenance.json`; sprites em `assets/items/forge/`.
- `ForgeStage`: arma flutuante, anéis de energia e brasas sobre a fornalha.
- `ForgeOutcome`: concentração de energia, impacto, arma atualizada, raios, partículas e anúncio de sucesso/falha.
- Áudio original em `assets/audio/sfx/forge_*.ogg` e `ui_loot.ogg`; respeita o controle de efeitos do jogo. Recriar com `python tools/make_forge_audio.py` (numpy e soundfile).
- Interfaces e textos em português e inglês. As abas Transferência e Moedas usam a mesma moldura de bronze e painéis escuros.

## Validação e visualização local

```text
godot --headless --path . --script tests/forge_tests.gd
godot --headless --path . --script tests/ui_tests.gd
godot --headless --path . --script tests/net_e2e_tests.gd
godot --path . --script tests/forge_visual_check.gd -- smith
```

A captura usa um perfil descartável em memória. Modos: `smith`, `success`, `failure`, `transfer`, `currencies`, `empty`, `max`. Imagens em `docs/screens/forge_*.png`.

Para jogar a nova versão no editor já aberto: F8 e F5. O cupom de teste `PEDRAS` continua entregando pedras de todos os níveis no modo offline (uso único por perfil); `TESTARTUDO` é reutilizável e entrega 200 pedras de cada nível, 200 de cada uma das sete moedas especiais, 99.999 moedas e 80 mapas (cinco instâncias, níveis 1 a 16), além dos equipamentos e cosméticos. Nenhum save pessoal é alterado pelos testes novos.

### Resultado desta validação

697 verificações passaram nas suítes de forja (19), interface (79), rede ponta a ponta (154), rede/lockstep (58), instâncias (112), armas (58), crafting (64), status (47), idiomas (25), combate (54) e mochila (27). Sete estados da interface foram capturados e inspecionados. `git diff --check`, a conferência das traduções e a sintaxe JavaScript da wiki passaram.

O processo do teste de rede ponta a ponta emitiu avisos de 39 objetos e 7 recursos ainda referenciados ao encerrar, apesar das 154 verificações aprovadas. Não houve erro de script durante o teste. Esse aviso de encerramento permanece registrado para investigação; as suítes de interface e mochila encerraram normalmente.
