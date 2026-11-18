# Pipeline de instalação e configuração do Claude Code

## Objetivo

Implementar no bucket Scoop pessoal um pipeline reproduzível para
preparar o Claude Code no Windows, separando:

1.  Instalação de dependências e ferramentas CLI.
2.  Registro e instalação de plugins do Claude Code.
3.  Configuração de integrações (MCPs e hooks).
4.  Validação e relatório de estado.

O pipeline deve ser idempotente: executá-lo mais de uma vez não deve
criar registros duplicados, sobrescrever configurações do usuário nem
causar falhas desnecessárias.

## Contexto do ambiente

-   Windows e PowerShell.
-   Scoop com bucket pessoal.
-   Claude Code CLI disponível no `PATH`.
-   Ferramentas Python instaladas preferencialmente com `uv tool`.
-   Integrações e plugins no escopo do usuário (`user`), para
    funcionarem em diferentes projetos.

## Ferramentas contempladas

  ---------------------------------------------------------------------------------------------------------------------------------------------
  Ferramenta              Instalação                                           Configuração
  ----------------------- ---------------------------------------------------- ----------------------------------------------------------------
  RTK                     Manifesto Scoop, preferencialmente                   `rtk init -g`

  Graphify                `uv tool install graphifyy`                          `graphify install`

  Headroom                `uv tool install --python 3.13 "headroom-ai[mcp]"`   `headroom mcp install`

  Ponytail                Marketplace Claude Code                              `claude plugin install ponytail@ponytail --scope user`

  Context Mode            Marketplace Claude Code                              `claude plugin install context-mode@context-mode --scope user`
  ---------------------------------------------------------------------------------------------------------------------------------------------

### Dependências

Verificar Claude Code CLI, Scoop, `uv` e Python 3.13. Verificar Node.js
quando exigido pelo ambiente/plugin. Não reinstalar dependências já
disponíveis. Se alguma estiver ausente, informar se o script pode
instalá-la ou se depende do bootstrap do ambiente.

## Marketplaces do Claude Code

Marketplaces:

-   Ponytail: `DietrichGebert/ponytail`
-   Context Mode: `mksglu/context-mode`

Comandos de referência:

``` powershell
claude plugin marketplace add DietrichGebert/ponytail
claude plugin marketplace add mksglu/context-mode
```

Instalação:

``` powershell
claude plugin install ponytail@ponytail --scope user
claude plugin install context-mode@context-mode --scope user
```

Antes de implementar, confirmar a sintaxe suportada pela versão
instalada do Claude Code com `claude --help` ou documentação/CLI
disponível. Não assumir que comandos ou argumentos existem sem validar.

## Instalação e configuração das ferramentas

### RTK

Preferir manifesto Scoop no bucket pessoal, se compatível e disponível.
Evitar instalar o mesmo executável simultaneamente por Scoop e Winget.

Comando alternativo de referência:

``` powershell
winget install rtk-ai.rtk
```

Configurar e validar:

``` powershell
rtk init -g
rtk --version
```

### Graphify

``` powershell
uv tool install graphifyy
graphify install
graphify --version
```

O comando `/graphify .` é uma ação de uso dentro de um projeto; não deve
ser executado automaticamente durante a configuração global. A
geração/atualização do grafo fica sob demanda.

### Headroom

``` powershell
uv tool install --python 3.13 "headroom-ai[mcp]"
headroom mcp install
headroom mcp status
```

**MCP e Proxy são componentes separados.** O pipeline deve configurar
somente o servidor MCP. Não deve:

-   iniciar `headroom proxy`;
-   configurar ou alterar `ANTHROPIC_BASE_URL`;
-   criar tarefas agendadas para manter o proxy ativo;
-   abrir portas ou iniciar serviços em segundo plano.

O proxy `http://127.0.0.1:8787` é opcional e deve ser ativado
manualmente pelo usuário. A ausência do proxy não deve ser classificada
como falha se o MCP estiver configurado e conectado.

`headroom mcp status` verifica a configuração, mas não comprova
necessariamente que o servidor esteja conectado na sessão atual.
Confirmar a conexão dentro do Claude Code com `/mcp`.

### Ponytail

``` powershell
claude plugin marketplace add DietrichGebert/ponytail
claude plugin install ponytail@ponytail --scope user
```

Validar com `claude plugin list`.

### Context Mode

``` powershell
claude plugin marketplace add mksglu/context-mode
claude plugin install context-mode@context-mode --scope user
```

Validar com `claude plugin list`. O comando `/ctx-doctor` pode ser
executado dentro de uma sessão do Claude Code para diagnóstico; não é
necessário executá-lo automaticamente no script.

## Estrutura sugerida

Adaptar à organização existente do bucket. Não reorganizar ou renomear
arquivos sem necessidade.

``` text
bucket/
  rtk.json
  ...

scripts/
  setup-claude.ps1
```

Responsabilidades:

-   **Manifestos Scoop:** instalar e atualizar executáveis.
-   **`setup-claude.ps1`:** verificar dependências, instalar ferramentas
    não gerenciadas pelo Scoop, registrar integrações, configurar
    plugins e validar.
-   **Comando/grupo do bucket:** chamar o script depois que os
    pré-requisitos estiverem instalados.

Não duplicar a instalação de um pacote em mais de um lugar. Se Graphify
e Headroom forem instalados por `uv tool`, não criar manifestos Scoop
concorrentes para os mesmos executáveis, salvo se houver uma estratégia
explícita de dependência e atualização.

## Comportamento de `setup-claude.ps1`

Criar um script independente, com funções pequenas e responsabilidades
claras.

### Fluxo

1.  Exibir resumo do que será configurado.
2.  Verificar Windows, PowerShell, Scoop e Claude Code.
3.  Verificar `uv` e Python 3.13.
4.  Garantir que RTK esteja instalado, preferencialmente via Scoop.
5.  Instalar Graphify e Headroom caso estejam ausentes.
6.  Executar `rtk init -g`.
7.  Executar `graphify install`.
8.  Executar `headroom mcp install`.
9.  Registrar os marketplaces necessários, evitando duplicatas.
10. Instalar/garantir Ponytail e Context Mode no escopo `user`.
11. Validar versões, plugins e configuração do Headroom.
12. Exibir relatório final por componente.

### Idempotência e segurança

-   Detectar instalações existentes antes de instalar.
-   Detectar marketplaces já registrados antes de adicioná-los.
-   Detectar plugins já instalados/habilitados antes de tentar
    instalá-los novamente.
-   Reexecutar comandos de configuração somente quando forem seguros e
    idempotentes; se não houver garantia, verificar o estado antes.
-   Não sobrescrever arquivos de configuração do Claude Code.
-   Não remover plugins, MCPs, marketplaces ou configurações que não
    pertençam ao pipeline.
-   Não modificar configurações não relacionadas.
-   Não alterar `ANTHROPIC_BASE_URL`.
-   Não iniciar o proxy do Headroom.
-   Não exigir privilégios administrativos sem necessidade.
-   Não usar `Invoke-Expression` para executar conteúdo remoto.
-   Tratar falhas por etapa, mostrando comando, motivo e possível ação
    corretiva.
-   Continuar etapas independentes quando for seguro, mas finalizar com
    estado geral parcial/falha se alguma etapa falhar.
-   Não imprimir tokens, credenciais ou conteúdo sensível.

### Parâmetros desejáveis

Se compatível com os padrões do repositório, implementar:

``` powershell
.\scripts\setup-claude.ps1
.\scripts\setup-claude.ps1 -Update
.\scripts\setup-claude.ps1 -Check
```

-   Sem parâmetros: instalar/configurar o que estiver faltando e
    validar.
-   `-Update`: atualizar ferramentas e plugins gerenciados pelo
    pipeline, sem alterar configurações alheias.
-   `-Check`: somente verificar e gerar relatório; não instalar nem
    modificar nada.

Se a atualização de plugins não tiver comando seguro e suportado na
versão instalada, não improvisar. Informar que a atualização precisa ser
manual.

## Validação

Executar verificações de CLI:

``` powershell
rtk --version
graphify --version
headroom mcp status
claude plugin list
```

Distinguir claramente:

-   ferramenta CLI instalada;
-   integração/configuração registrada;
-   plugin instalado e habilitado;
-   servidor MCP configurado;
-   servidor MCP efetivamente conectado na sessão.

A conexão ativa do Headroom deve ser confirmada dentro do Claude Code
com `/mcp`.

O diagnóstico do Context Mode pode ser feito dentro do Claude Code com
`/ctx-doctor`.

Não declarar o MCP conectado apenas porque `headroom mcp status` informa
que a configuração existe.

## Relatório final

Exibir uma tabela ou resumo semelhante a:

``` text
Claude Code Setup

[OK] RTK CLI
[OK] RTK global integration
[OK] Graphify CLI
[OK] Graphify integration
[OK] Headroom CLI
[OK] Headroom MCP configuration
[OK] Ponytail plugin
[OK] Context Mode plugin

MCP live connection: verify inside Claude Code with /mcp
Headroom proxy: not started (optional, by design)

Result: SUCCESS / PARTIAL / FAILED
```

Usar estados diferentes para `OK`, `SKIPPED`, `WARNING` e `FAILED`.

## Comandos de uso cotidiano (não executar automaticamente)

``` text
/graphify .
/ctx-stats
/ctx-doctor
/mcp
```

-   `/graphify .`: gerar/atualizar o grafo do projeto atual.
-   `/ctx-stats`: consultar estatísticas do Context Mode.
-   `/ctx-doctor`: diagnosticar Context Mode.
-   `/mcp`: verificar servidores MCP conectados.

RTK, Ponytail e Context Mode podem atuar automaticamente por
hooks/instruções quando aplicável. Headroom pode ser chamado sob demanda
pelo Claude; compressão automática de todo o tráfego exige o proxy,
desativado por padrão.

## Critérios de aceite

1.  O script pode ser executado duas vezes sem duplicar registros ou
    causar erros.
2.  Ferramentas CLI instaladas e acessíveis no `PATH`.
3.  Marketplaces e plugins registrados no escopo `user`.
4.  RTK, Graphify e Headroom configurados.
5.  O script distingue configuração de conexão MCP em tempo real.
6.  Proxy Headroom permanece desligado e `ANTHROPIC_BASE_URL`
    inalterado.
7.  `-Check` não modifica o sistema.
8.  Relatório final identifica sucessos, avisos e falhas.
9.  Implementação respeita os padrões e a estrutura existentes no
    bucket.

## Instruções ao agente implementador

Antes de alterar arquivos:

1.  Inspecione a estrutura atual do repositório e os padrões dos
    manifestos.
2.  Verifique a versão instalada do Claude Code e a sintaxe real dos
    comandos de marketplace/plugin.
3.  Verifique os comandos e opções disponíveis nas versões instaladas de
    RTK, Graphify e Headroom.
4.  Identifique como o bucket organiza grupos/categorias e aciona
    scripts.
5.  Apresente um plano curto de implementação.

Depois implemente, teste o que for possível no ambiente atual e informe
quais verificações exigem uma sessão interativa do Claude Code.

Não invente comandos, opções ou estados de sucesso. Se a CLI instalada
divergir dos exemplos deste documento, priorize a sintaxe efetivamente
suportada e registre a diferença.

## Implementação (como ficou no bucket)

-   Grupo `claude-tools` em `groups.json` (incluído em `all`): `main/uv`,
    `main/rtk`, `graphifyy` e `headroom-ai[mcp]` (nova fonte `uv-tool`,
    Python 3.13), `ponytail@ponytail` e `context-mode@context-mode`.
-   Passos de configuração = campo `integration` de cada ferramenta,
    implementados em `scripts/lib/Integrations.ps1` e executados pelo
    `install.ps1` depois de todas as ferramentas.
-   `scripts/setup-claude.ps1` (`-Check`, `-Update`) chama
    `install.ps1 -Group claude-tools` e imprime o relatório no formato
    acima; nada é instalado em dois lugares.

Diferenças em relação aos comandos de referência (verificadas na CLI
instalada em 2026-11-18: Claude Code 2.1.327, rtk 1.2.0, graphify 0.9.x,
headroom-ai 0.44.0):

-   RTK: `rtk init -g --auto-patch --no-trust-filters` — `rtk init -g`
    sozinho pergunta antes de alterar `settings.json`.
-   Headroom: `headroom mcp install --agent claude` — sem `--agent`, ele
    também altera as configs de Codex/OpenCode. Sem `--force`.
    `headroom mcp status` sempre sai com 0, então o estado é lido de
    `~/.claude.json` (`mcpServers.headroom`).
-   Graphify: `graphify install` no Windows usa a plataforma `windows`
    (skill em `~/.claude/skills/graphify`). Se `graphify` já estiver no
    PATH via pip, ele não é reinstalado pelo uv.
-   `uv` do Scoop guarda `UV_TOOL_DIR`/`UV_TOOL_BIN_DIR` no ambiente do
    usuário; os scripts recarregam essas variáveis, senão as ferramentas
    iriam para `~\.local\bin` (fora do PATH).
-   Context Mode roda o MCP com `node`: `main/nodejs-lts` é instalado se
    `node` não existir.
-   Ponytail grava uma linha CSV por turno em
    `~/.config/ponytail/band/` (opção `ledger`, padrão ligado); o webhook
    fica desligado.
