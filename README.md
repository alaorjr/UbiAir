# UbiAir

UbiAir é um aplicativo nativo para macOS, feito em Swift e SwiftUI, que coloca os
controles de ar-condicionado LG ThinQ na barra de menus. É desenvolvido com Swift 6
e Xcode 27. Versão atual: **0.1.10 (build 11)**.

**Ambiente testado:** Xcode 27.1 e macOS 27.0.1. O projeto está configurado com
versão mínima de implantação macOS 14, mas versões anteriores ao macOS 27 não
foram testadas. Essa configuração não representa compatibilidade validada com
essas versões. A compilação com versões anteriores do Xcode também não foi validada.

<p align="center">
  <img src="Docs/Images/ubiair-demo.gif" width="360" alt="Demonstração animada do UbiAir">
  <br>
  <sub>Prévia exportada da interface nativa com aparelhos e estados fictícios; nenhum comando é enviado a aparelhos reais.</sub>
</p>

O painel acompanha os recursos informados pelo perfil de cada aparelho. O UbiAir é um
projeto independente, sem vínculo ou endosso da LG Electronics. A integração usa o
serviço LG ThinQ Connect; consulte os termos aplicáveis da LG antes de usar o serviço.

[☕ Buy me a coffee](https://buymeacoffee.com/alaorjr) ·
[♥ GitHub Sponsors](https://github.com/sponsors/alaorjr) · [Licença MIT](LICENSE)

## Recursos

- Seleciona entre aparelhos de ar-condicionado da conta e mostra o estado de energia,
  temperatura atual e temperatura desejada.
- Ajusta energia, temperatura, modo, ventilação e direção do ar quando o perfil do
  aparelho oferece esses controles.
- Respeita limites, passos e opções suportadas por cada aparelho, com prévia da
  temperatura enquanto o controle deslizante é arrastado.
- Confirma comandos por uma leitura posterior do estado. Em caso de falha, informa
  como recuperar e não repete comandos automaticamente.
- Atualiza o painel quando ele é aberto e a cada 30 segundos enquanto permanece visível.
- Oferece abrir ao iniciar sessão, ativado pelo usuário.
- Guarda o PAT no Chaves do macOS, oferece uma demonstração offline e respeita a
  preferência de acessibilidade para reduzir movimento.

## Instalar e executar pelo Xcode

1. Use o Xcode 27 em uma versão do macOS compatível com ele. O ambiente utilizado
   nos testes foi Xcode 27.1 no macOS 27.0.1. Abra o Xcode uma vez para concluir
   a instalação dos componentes e, se solicitado, selecione suas Command Line Tools.
2. Clone este repositório e abra o projeto:

   ```sh
   git clone https://github.com/alaorjr/UbiAir.git
   cd UbiAir
   open UbiAir.xcodeproj
   ```

3. No Xcode, escolha o esquema **UbiAir** e o destino **My Mac**.
4. Pressione `⌘B` para compilar ou `⌘R` para compilar e executar.

O build **Debug** usa assinatura local, sem exigir uma conta Apple Developer ou um
Team configurado. Depois de compilar, o aplicativo fica em
`build/XcodeSandbox/Build/Products/Debug/UbiAir.app`. O floco de neve do UbiAir aparece
na barra de menus; clique nele para abrir o painel.

## Experimentar a demonstração

A demonstração usa dois aparelhos fictícios, não precisa de PAT e não faz chamadas à LG.
Para abrir o painel automaticamente na primeira execução pelo Xcode:

1. Antes de pressionar `⌘R`, abra **Product > Scheme > Edit Scheme…**.
2. Selecione **Run > Arguments** e adicione estes argumentos em **Arguments Passed On Launch**:
   `--demo` e `--show-panel`.
3. Feche a edição do esquema e pressione `⌘R`.

O painel será aberto já no modo de demonstração. Encerre o UbiAir antes de alterar os
argumentos de inicialização. Para voltar à conexão normal, remova os dois argumentos
do esquema e inicie o aplicativo novamente.

## Conectar à conta LG ThinQ

1. No painel do UbiAir, informe o país da conta; para uma conta do Brasil, use `BR`.
2. Abra o [portal de PAT da LG](https://connect-pat.lgthinq.com/login), entre com a
   conta LG ThinQ e crie um Personal Access Token (PAT).
3. Cole o PAT no UbiAir e escolha se deseja salvá-lo no Chaves do macOS.

Os aparelhos precisam estar cadastrados na conta do aplicativo LG ThinQ. A listagem e
a atualização leem os estados; os comandos só são enviados quando você usa os controles.
O PAT é uma credencial pessoal: não o publique em issues, logs, capturas, commits ou
pedidos de contribuição.

## Compilar Release e executar os testes

Para compilar a variante Release universal com assinatura local de desenvolvimento:

```sh
bash Scripts/build-sandbox-app.sh
python3 Scripts/verify-distribution.py
open build/XcodeSandbox/Build/Products/Release/UbiAir.app
```

Para executar os testes offline do pacote:

```sh
swift test
```

O script de Release não envia o aplicativo à loja nem o prepara para distribuição final.
O envio à Mac App Store ainda está em preparação; assinatura e validação finais, além da
validação da integração para distribuição, continuam pendentes.

## Privacidade e contribuições

O aplicativo não usa um servidor próprio. O PAT fica no Chaves do macOS quando você
escolhe salvá-lo; as chamadas de conta e aparelho vão diretamente ao serviço da LG.
Preferências locais, builds e configurações pessoais de desenvolvimento não devem ser
incluídos em commits. O `.gitignore` exclui `Config/Local.xcconfig`; use
`Config/Local.example.xcconfig` como referência para configuração local do Xcode quando
necessário. Esse arquivo de configuração não deve conter PATs. Não envie diagnósticos
que exponham tokens, identificadores ou estados reais de aparelhos.

Contribuições são bem-vindas. Use apenas dados fictícios em exemplos, capturas e
relatórios; nunca inclua PAT nem dados reais de aparelhos.

Para regenerar o GIF, execute `Scripts/capture-readme-demo.sh`; é necessário ter ffmpeg
no `PATH` (ou definir a variável `FFMPEG` com o caminho do executável). O script compila o helper de captura e não exige abrir ou
executar o aplicativo instalado.

## Estrutura do projeto

- `Sources/ThinQCore`: cliente ThinQ, capacidades, estados, comandos e serviço de demonstração.
- `Sources/UbiAirMenuBar`: interface SwiftUI, sessão, preferências, Chaves e Login Items.
- `Tests`: testes offline com serviços e transporte fictícios.
- `Scripts`: compilação, verificação e captura da demonstração.
- `Docs/Images`: capturas de demonstração geradas com dados fictícios.

## Apoie o projeto

Se o UbiAir facilita seu dia, você pode pagar um café e ajudar a manter o
desenvolvimento. O apoio é voluntário e não é necessário para usar o código.

<p>
  <a href="https://buymeacoffee.com/alaorjr">
    <img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy me a coffee" height="60" width="217">
  </a>
  <a href="https://github.com/sponsors/alaorjr">
    <img src="https://img.shields.io/badge/GitHub%20Sponsors-Apoiar-ea4aaa?style=for-the-badge&amp;logo=githubsponsors&amp;logoColor=white" alt="Apoiar pelo GitHub Sponsors" height="32">
  </a>
</p>

## Referências

- [Portal LG ThinQ Connect](https://smartsolution.developer.lge.com/en/apiManage/thinq_connect)
- [SDK oficial LG pythinqconnect](https://github.com/thinq-connect/pythinqconnect)
- [TCLimate](https://github.com/umarz317/TCLimate), referência de inspiração visual.

## Licença

O UbiAir é distribuído sob a [licença MIT](LICENSE).
Copyright © 2026 Alaor Jr. As referências e atribuições de terceiros estão em
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
