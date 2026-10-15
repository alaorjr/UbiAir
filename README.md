# UbiAir para macOS

UbiAir é um aplicativo nativo SwiftUI para controlar ar-condicionado LG pela barra de menus.
Inspirado na experiência do [TCLimate](https://github.com/umarz317/TCLimate), usa cliente
Swift original para o serviço LG ThinQ Connect, sem executar Python. Versão 0.1.7 (build 8).

## Preparação para a Mac App Store

Há um target macOS em `UbiAir.xcodeproj`, com sandbox, rede de saída, ícone provisório,
manifesto e build universal. A preparação e os itens que dependem da conta Apple ativa
estão em [Docs/APP-STORE.md](Docs/APP-STORE.md).

```sh
bash Scripts/build-sandbox-app.sh
python3 Scripts/verify-distribution.py
open build/XcodeSandbox/Build/Products/Release/UbiAir.app
```

A assinatura desse script é ad hoc local, sem envio à loja. O sandbox usa seu próprio
container de preferências; país/PAT podem precisar ser configurados novamente na primeira
execução. Não executa a importação do domínio anterior. Chaves e início automático com a
assinatura final ainda precisam ser validados. Política e material de loja são rascunhos.

## Executar

Requisitos: macOS 14 ou posterior, Xcode/Command Line Tools com Swift 6 ou posterior.

```sh
swift test
bash Scripts/build-app.sh
open build/UbiAir.app
```

O ícone de floco de neve aparece na barra de menus. Abra o painel, informe seu
Personal Access Token (PAT) e o país da conta (Brasil: `BR`). Para obter o PAT, abra o
[portal LG](https://connect-pat.lgthinq.com/login), entre com sua conta LG ThinQ,
crie um PAT e cole-o no campo do UbiAir. Se ainda não tiver conta, o portal orienta criar
uma pelo app LG ThinQ. O token pode ser salvo no Chaves do macOS.
“Desconectar e remover token” remove a credencial salva.
Os aparelhos precisam estar previamente cadastrados na sua conta do app LG ThinQ.
Conectar e atualizar fazem apenas leitura; comandos são enviados ao clicar nos controles.

Para experimentar sem token e sem conexão com aparelhos reais:

```sh
open build/UbiAir.app --args --demo
```

`--demo` usa dois aparelhos fictícios; abra o painel pelo ícone da barra de menus. Para
avaliação visual automatizada, `--show-panel` abre esse mesmo popover após a inicialização.
`--ui-smoke-test` exige `--demo`, verifica abertura, fechamento e reabertura do popover e
encerra o app; opcionalmente, `UBIAIR_UI_PREVIEW_PATH=/caminho/arquivo.png` salva uma captura
somente da view do painel. Exemplo: `open build/UbiAir.app --args --demo --ui-smoke-test`.
Cenários locais de erro também exigem `--demo`, por exemplo:
`open build/UbiAir.app --args --demo --demo-error offline --show-panel`.
Valores: `offline`, `internet`, `timeout`, `authentication`, `limit`, `service`, `empty`.
Esses cenários usam dados fictícios, não leem PAT e não chamam a LG.
Não há janela de prévia separada. Encerre o app antes de iniciar com argumentos diferentes.

O painel é um popover nativo ancorado ao ícone de floco de neve e não pode ser destacado.
Ele fecha ao clicar fora ou mudar de aplicação, inclusive após usar o menu da engrenagem.
[Veja a prévia com aparelhos fictícios](Docs/Images/menu-panel-demo.png).
O visual compacto traz seletor horizontal de aparelhos, temperatura alvo e ambiente,
controles de temperatura e cartões de modo/ventilação. Oscilação aparece quando suportada;
os controles são determinados pelas capabilities de cada aparelho. Sleep e energia não são
expostos sem suporte confirmado pela API.

## Recursos da versão 0.1.7

- Seleção de ar-condicionado, estado de energia e temperatura ambiente/alvo.
- Mensagens e recuperação para aparelho offline, internet/timeout, PAT inválido, permissões
  e indisponibilidade da LG; contas sem ar-condicionados mostram o suporte do UbiAir.
- Controles bloqueados após falha de leitura/verificação até atualizar o estado; comandos
  nunca são reenviados automaticamente. PAT inválido e limite pausam atualização automática.
- Painel ampliado para caber confirmação de comandos e direção do ar expandida, sem barra de rolagem.
- Círculos de energia independentes da seleção: verde ligado, vermelho desligado e cinza
  quando o estado está desconhecido ou a leitura falhou. O destaque do botão indica a seleção.
- Ligar/desligar, ajustar temperatura, modo, ventilação e oscilação, quando o perfil permitir.
- Respeito aos enums, intervalos, passos e valores excluídos do perfil do aparelho.
- Verificação do comando por leitura posterior do estado da nuvem; o sucesso do POST sozinho
  não é anunciado como confirmação.
- Atualização ao abrir e a cada 30 segundos com o painel visível, sem polling de aparelhos
  quando todos os painéis estão fechados.
- PAT no Chaves, Client ID persistente e opção de abrir ao iniciar sessão.
- Demonstração offline, sem chamadas LG.
- Ilustração original do ar-condicionado em SwiftUI, com animação de fluxo de ar que respeita
  a preferência de acessibilidade para reduzir movimento.

## Acompanhar e retomar

Abra [Progress/index.html](Progress/index.html) no navegador. O arquivo funciona sem servidor
e recarrega a cada 15 segundos. Para acompanhamento durante o desenvolvimento:

```sh
python3 -m http.server 8765 --bind 127.0.0.1
```

Abra `http://127.0.0.1:8765/Progress/`; o painel lê o progresso atualizado a cada 3 segundos.
O servidor é somente local. Use `Ctrl+C` para encerrá-lo.

O coordenador registra cada início e conclusão com:

```sh
python3 Scripts/progress.py start F03 --note 'Escopo do trabalho'
python3 Scripts/progress.py done F03 --note 'Resultado e verificações'
```

A fonte de verdade é `Progress/progress.json`. Leia [Docs/CONTINUITY.md](Docs/CONTINUITY.md)
para retomar em outra sessão, e [Docs/DECISIONS.md](Docs/DECISIONS.md) para as decisões.
O repositório Git é local, branch `main`; não existe remoto configurado.

## Arquitetura

```text
Sources/ThinQCore        Cliente REST, JSON flexível, capacidades, comandos e demonstração
Sources/UbiAirMenuBar    SwiftUI, coordenação de sessão, Chaves, preferências e Login Items
Tests/ThinQCoreTests    Testes offline com transporte simulado
Tests/UbiAirTests       Preferências, indicadores e recuperação de falhas com serviços fictícios
Scripts                Empacotamento e atualização do progresso
Docs                   Pesquisa, decisões e continuidade
Progress               Painel local e histórico das etapas
```

## Quando algo falhar

Offline significa que a LG informou que o aparelho não está conectado ao ThinQ. Uma falha
de internet ou timeout aparece como problema de conexão, sem marcar o aparelho como
desligado. O círculo fica cinza quando não há leitura confiável; seu texto acessível e
a dica do seletor explicam a falha. O cartão do aparelho oferece atualização manual.

PAT inválido oferece “Conectar novamente” para informar um novo token. Essa ação preserva
o registro do Chaves; “Desconectar e remover token” continua sendo a ação de remoção.
Ao atingir o limite de chamadas, o app pausa leituras automáticas e orienta aguardar antes
de tentar novamente. A API não fornece aqui um prazo de espera confirmado.

Após falha no envio ou na confirmação de um comando, atualize o estado antes de repetir.
O aplicativo não anuncia sucesso nem reenvia a ação automaticamente. Respostas técnicas
da API não são exibidas nas mensagens ao usuário.

## Compatibilidade e distribuição

O nome do aplicativo é **UbiAir** e seu Bundle Identifier é **`ai.ubiquu.UbiAir`**.
Na versão Swift Package de desenvolvimento, país e Client ID válidos da versão anterior do UbiAir são importados
quando esses campos ainda não existem na configuração nova. Escolhas atuais têm prioridade.
O domínio anterior é consultado apenas para essas preferências; o identificador pessoal
da versão inicial foi retirado do código.
O serviço do Chaves também usa `ai.ubiquu.UbiAir`. A credencial da versão anterior não é importada;
informe e salve novamente seu PAT na interface do UbiAir. O registro antigo fica no Chaves,
mas não é consultado por este aplicativo. A nova assinatura pode exigir autorização do Chaves
pelo usuário. Login Items não é ativado automaticamente pela migração; confira essa opção
após instalar UbiAir no local definitivo.

O protocolo segue o [SDK oficial pythinqconnect](https://github.com/thinq-connect/pythinqconnect).
Veja [Docs/API-RESEARCH.md](Docs/API-RESEARCH.md) para fontes e limitações. Os testes offline
validam o protocolo modelado. O usuário também confirmou testes em três aparelhos reais,
com tudo funcionando; a validação básica F08 está concluída. Energia, MQTT e funções
extras permanecem como evoluções futuras. Dados ausentes não são apresentados como
zero, e o modo de demonstração é identificado na interface. Nenhum PAT, identificador real
de aparelho ou dado real de aparelho é armazenado na documentação do projeto.

O build padrão usa assinatura ad hoc para teste local, sem notarização. Para manter uma
identidade estável no Chaves e preparar distribuição com certificado:

```sh
UBIAIR_CODESIGN_IDENTITY='Nome do certificado' bash Scripts/build-app.sh
```

Alterar a identidade/assinatura de builds pode impedir o acesso ao token salvo anteriormente.
Para início automático, mova o aplicativo para seu local definitivo em Aplicativos antes de
habilitar a opção. Assinatura Developer ID e notarização são etapas posteriores de distribuição.

UbiAir é um projeto independente, sem vínculo ou endosso da LG Electronics.
