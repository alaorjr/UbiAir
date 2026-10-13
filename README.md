# LGThinQ para macOS

Aplicativo nativo SwiftUI para controlar ar-condicionado LG ThinQ pela barra de menus.
Inspirado na experiência do [TCLimate](https://github.com/umarz317/TCLimate), com cliente
Swift original para a API oficial ThinQ Connect, sem executar Python.

## Executar

Requisitos: macOS 14 ou posterior, Xcode/Command Line Tools com Swift 6 ou posterior.

```sh
swift test
bash Scripts/build-app.sh
open build/LGThinQ.app
```

O ícone de floco de neve aparece na barra de menus. Abra o painel, informe seu
Personal Access Token do portal LG e o país da conta (Brasil: `BR`). O token pode
ser salvo no Chaves do macOS. “Desconectar e remover token” remove a credencial salva.
Os aparelhos precisam estar previamente cadastrados na sua conta do app LG ThinQ.
Conectar e atualizar fazem apenas leitura; comandos são enviados ao clicar nos controles.

Para experimentar sem token e sem conexão com aparelhos reais:

```sh
open build/LGThinQ.app --args --demo --preview
```

`--demo` usa dois aparelhos fictícios; `--preview` abre uma janela com o mesmo painel
para facilitar a avaliação. Ambos permanecem separados dos aparelhos reais.
Se o app já estiver em execução, encerre-o antes de abrir com argumentos diferentes.

## Recursos da versão inicial

- Seleção de ar-condicionado, estado de energia e temperatura ambiente/alvo.
- Ligar/desligar, ajustar temperatura, modo, ventilação e oscilação, quando o perfil permitir.
- Respeito aos enums, intervalos, passos e valores excluídos do perfil do aparelho.
- Verificação do comando por leitura posterior do estado da nuvem; o sucesso do POST sozinho
  não é anunciado como confirmação.
- Atualização ao abrir e a cada 30 segundos com o painel visível, sem polling de aparelhos
  quando todos os painéis estão fechados.
- PAT no Chaves, Client ID persistente e opção de abrir ao iniciar sessão.
- Demonstração offline, sem chamadas LG.

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
Sources/LGThinQMenuBar   SwiftUI, coordenação de sessão, Chaves, preferências e Login Items
Tests/ThinQCoreTests    Testes offline com transporte simulado
Scripts                Empacotamento e atualização do progresso
Docs                   Pesquisa, decisões e continuidade
Progress               Painel local e histórico das etapas
```

## Compatibilidade e distribuição

O protocolo segue o [SDK oficial pythinqconnect](https://github.com/thinq-connect/pythinqconnect).
Veja [Docs/API-RESEARCH.md](Docs/API-RESEARCH.md) para fontes e limitações. Os testes offline
validam o protocolo modelado; a validação com os modelos reais do usuário ainda é necessária.
Energia, MQTT e funções extras ficam para depois dessa validação. Dados ausentes não são
apresentados como zero, e o modo de demonstração é identificado na interface.

O build padrão usa assinatura ad hoc para teste local, sem notarização. Para manter uma
identidade estável no Chaves e preparar distribuição com certificado:

```sh
LGTHINQ_CODESIGN_IDENTITY='Nome do certificado' bash Scripts/build-app.sh
```

Alterar a identidade/assinatura de builds pode impedir o acesso ao token salvo anteriormente.
Para início automático, mova o aplicativo para seu local definitivo em Aplicativos antes de
habilitar a opção. Assinatura Developer ID e notarização são etapas posteriores de distribuição.

LGThinQ é um projeto independente, sem vínculo ou endosso da LG Electronics.
