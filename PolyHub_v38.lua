--[[
    POLY HUB v38 MODULAR | Interface Roblox (Luau)
    Nova aba: Auto Farm Castelo (combate experimental).
    Mantem Auto Farm geral (opcoes visuais), Auto Farm Doces, Player e Config.
    Uso: LocalScript em StarterPlayer > StarterPlayerScripts, na sua experiencia.

    CASTELO: procura alvos em Workspace.Animal_Live.Aggressors; le os atributos
    @Tier, @Animal, @Health, @DungeonRun e @DungeonRoom; por padrao
    movimenta no chao ate Approach Distance e entao ajusta a altura.
    Opcao separada: subir IMEDIATAMENTE ao selecionar Count Dracula,
    sem precisar habilitar o ajuste de altura por aproximacao.
    Se altura negativa: Noclip temporario + retorno a posicao segura
    ao afastar/terminar. Noclip manual do Player continua independente.
    Ataca com a primeira ferramenta de combate disponivel na barra/mochila
    (a ordem real do slot nao e exposta de forma confiavel por APIs normais).
    Universal Debug mostra @Health/@Animal como prefixo visual; os atributos
    REAIS do Roblox sao Health/Animal/AttackType/Tier (SEM arroba).
    PRIMEIRA FASE: Count Dracula NAO MORRE; ele foge quando sua vida
    chega aproximadamente a 50%, quebrando a janela. O farm monitora
    Health/MaxHealth, ARMA a transicao perto de 55% e confirma a fuga
    (modelo removido da arena apos dano ou cutscene nova); so entao
    aguarda cerca de 5 segundos e procura caminho ate o checkpoint.
    GraveGolem ja visivel nao serve como prova de fuga.
    Detecta Dracula via HealthChanged e signal de atributo Health.
    Ao detectar fuga do Dracula perto de 50%, aguarda a cutscene e caminha
    ao gatilho final, antes de buscar GraveGolem. Nas DUAS transicoes usa
    velocidade temporaria (configuravel) e MoveTo sem microparadas.
    Durante combate envia a tecla Q no maximo uma vez a cada 15 segundos,
    quando ha um metodo de simulacao de teclado disponivel no runtime.
    Telas finais: "Corra novamente" (vitoria) e "Tente novamente"
    (derrota do personagem) sao tratadas separadamente, com clique
    somente se botoes de GUI visiveis forem encontrados.
    A verificacao de fim da cutscene e heuristica; confira o diagnostico no jogo.
    Nao valida regras exclusivas do servidor.
    v23: base v20 mantida no combate, Q, altura, MoveTo e velocidade.
    Corrige APENAS o ciclo de vida: troca de personagem/Humanoid e retomada
    das fases apos Derrotado / Corra novamente, com logs de diagnostico.
    Sem segundo Q, sem novos impulsos/saltos e sem aumento no raio de busca.
    v29: preserva fase GraveGolem apos respawn; busca 250 studs e mantem
    altura positiva durante pequenas variacoes de distancia.
    v31: corrige saida X=6502.43 e subida do GraveGolem medida pela
    superficie, com decolagem antecipada e sustentacao sem perder alvo.
    v32: adiciona modos de transicao WALK (padrao) e TELEPORT (opcional)
    para o checkpoint do GraveGolem e a saida final. Teleporte so inicia
    depois das confirmacoes de fuga ou derrota e nao substitui combate.
    Se a posicao e corrigida pelo servidor, tenta novamente COM INTERVALOS
    CRESCENTES, sem teleporte continuo em cada frame. Apos detectar a
    nova cutscene, boss final ou telas de recompensa, retoma fluxo normal.
    Servidores podem bloquear teleporte ou expulsar o cliente: WALK e
    o modo recomendado quando o jogo nao aceita o deslocamento.
    Mantem a saida fixa, sem campos de coordenadas editaveis.
    v27: altura positiva do GraveGolem usa como piso de referencia
    a altura de chegada do PERSONAGEM, e nao apenas a MeshPart do boss.
    Evita recalcular MoveTo(root.Position) repetidamente em combate perto.
    Adiciona diagnostico Y atual / Y desejado no Output.
    v26: interface reabre pelo botao flutuante ou RightShift; evita
    ficar bloqueado esperando nascimento do personagem. Nao altera combate.
    v25: corrige gatilho final que exigia chegar a apenas 3 studs;
    apos confirmar fuga do Dracula, reconhece GraveGolem perto do checkpoint.
    Usa distancia maior para concluir a rota sem atravessar paredes;
    registra diagnosticos do boss se nenhum alvo for escolhido.
    v24: adiciona Auto Maca opcional e limite de vida em %. Equipa uma Tool
    reconhecida como maca/apple, usa Tool:Activate e restaura a arma anterior.
    Tem intervalo minimo entre tentativas e nao altera MoveTo, rotas ou Q.
    A confirmacao de cura depende de medir HP depois do uso, nao so do clique.
    Use em sua propria experiencia; comportamento depende das regras do servidor.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")

local localPlayer = Players.LocalPlayer
if not localPlayer then return end
local playerGui = localPlayer:WaitForChild("PlayerGui")

local previous = playerGui:FindFirstChild("PolyHubUI")
if previous then previous:Destroy() end

local COLORS = {
    bg = Color3.fromRGB(13, 10, 28),
    panel = Color3.fromRGB(22, 16, 42),
    card = Color3.fromRGB(30, 22, 54),
    line = Color3.fromRGB(74, 52, 117),
    purple = Color3.fromRGB(153, 92, 255),
    purpleDark = Color3.fromRGB(102, 56, 185),
    white = Color3.fromRGB(244, 239, 255),
    muted = Color3.fromRGB(166, 149, 193),
    success = Color3.fromRGB(54, 224, 143),
}

-- Usa a velocidade da experiencia; nenhum numero fixo e aplicado no reset.
-- A interface nao deve aguardar indefinidamente um Character/respawn.
local startingCharacter = localPlayer.Character
local startingHumanoid = startingCharacter and startingCharacter:FindFirstChildOfClass("Humanoid")
local experienceSpeed = startingHumanoid and startingHumanoid.WalkSpeed or 16
local speedWasCustomized = false

local state = {
    dungeon = "Masmorra de Halloween 2026",
    autoFarm = false,
    autoReplay = false,
    bossPriority = false,
    antiAFK = false,
    noclip = false,
    speedEnabled = false,
    infiniteJump = false,
    candyFarm = false,
    candyPriority = "Raridade",
    speedValue = experienceSpeed,
    castleFarm = false,
    castleHeightEnabled = false,
    castleHeightDirectDracula = false,
    castleCombatTeleportDracula = false, -- opcional: TP de ataque no Dracula
    castleCombatTeleportGolem = false,   -- opcional: TP de ataque no GraveGolem
    castleDraculaCombatTeleportRange = 30, -- distancia maxima XZ antes do TP de combate (Dracula)
    castleDraculaDetectionRange = 250, -- detecta Dracula distante do altar apos respawn
    castleApproach = 8,
    castleHeight = 0,
    castleDraculaDefeated = false,
    castleAutoReplay = true,
    castleAutoQ = true,
    castleQInterval = 15, -- segundos entre tentativas; configuravel na aba Castelo
    castleQRange = 18, -- distancia XZ para usar o Q sem exigir alcance da espada
    castleAutoApple = false, -- desligado por padrao, ativacao opcional
    castleAutoLoot = false, -- coleta opcional de drops do GraveGolem, sem alterar a rota normal
    castleAppleThreshold = 50, -- usa maca quando HP <= este percentual
    castleAppleName = "", -- opcional: parte do nome exato da Tool
    castleRouteBoost = true,
    castleRouteSpeed = 24,
    castleTransitionMode = "Walk", -- "Walk" original ou "Teleport" opcional
}

-- Referencias de cards e controles agrupadas num unico campo, para nao
-- exceder o limite do compilador de variaveis locais do arquivo principal.
state._uiRefs = {}

-- Conecte a lógica do seu próprio jogo neste callback.
local function onSettingChanged(key, value)
    print(string.format("[Poly Hub] %s = %s", tostring(key), tostring(value)))
    -- Exemplo: se key == "autoFarm" then iniciarOuPararMotor(value) end
end

local function create(className, props, parent)
    local inst = Instance.new(className)
    for k, v in pairs(props or {}) do inst[k] = v end
    inst.Parent = parent
    return inst
end

local function round(object, radius)
    return create("UICorner", { CornerRadius = UDim.new(0, radius or 12) }, object)
end

local function outline(object, color, thickness, transparency)
    return create("UIStroke", {
        Color = color or COLORS.line,
        Thickness = thickness or 1,
        Transparency = transparency or 0,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, object)
end

local function txt(parent, value, size, color, bold, props)
    props = props or {}
    props.BackgroundTransparency = 1
    props.Text = value
    props.TextColor3 = color or COLORS.white
    props.Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham
    props.TextSize = size or 13
    props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
    props.TextYAlignment = props.TextYAlignment or Enum.TextYAlignment.Center
    return create("TextLabel", props, parent)
end

local function button(parent, value, props)
    props = props or {}
    props.Text = value
    props.TextColor3 = props.TextColor3 or COLORS.white
    props.Font = Enum.Font.GothamBold
    props.TextSize = props.TextSize or 12
    props.AutoButtonColor = false
    props.BorderSizePixel = 0
    return create("TextButton", props, parent)
end

local screenGui = create("ScreenGui", {
    Name = "PolyHubUI", ResetOnSpawn = false, IgnoreGuiInset = true,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 900,
}, playerGui)

local window = create("Frame", {
    Name = "Window", AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(790, 535),
    BackgroundColor3 = COLORS.bg, BorderSizePixel = 0,
}, screenGui)
round(window, 17)
outline(window, COLORS.purpleDark, 1.6)

-- Os controles de visibilidade sao registrados antes do restante da UI.
-- Usamos um atalho registrado aqui e um botao nomeado, sem aumentar
-- a quantidade de variaveis locais do arquivo principal (limite Lua).
button(screenGui, "POLY HUB", {
    Name = "ReabrirPolyHub",
    AnchorPoint = Vector2.new(1, 0.5),
    Position = UDim2.new(1, -20, 0.32, 0),
    Size = UDim2.fromOffset(130, 43),
    BackgroundColor3 = COLORS.purpleDark,
    TextColor3 = COLORS.white,
    TextSize = 13,
    Visible = false,
    ZIndex = 50,
})
round(screenGui.ReabrirPolyHub, 12)
outline(screenGui.ReabrirPolyHub, COLORS.purple, 1.5)
screenGui.ReabrirPolyHub.MouseButton1Click:Connect(function()
    screenGui.Enabled = true
    window.Visible = true
    screenGui.ReabrirPolyHub.Visible = false
    print("[Poly Hub v26][UI] ABERTO pelo botao")
end)
state._uiHotkeyConnection = UserInputService.InputBegan:Connect(function(input)
    if input.KeyCode ~= Enum.KeyCode.RightShift then return end
    if UserInputService:GetFocusedTextBox() then return end
    screenGui.Enabled = true
    window.Visible = not window.Visible
    screenGui.ReabrirPolyHub.Visible = not window.Visible
    print("[Poly Hub v26][UI] " .. (window.Visible and "ABERTO" or "MINIMIZADO"))
end)
print("[Poly Hub v26][UI] GUI criada; RightShift e botao de reabrir disponiveis")

local scale = create("UIScale", { Scale = 1 }, window)
local function adjustScale()
    local camera = workspace.CurrentCamera
    if not camera then return end
    local screen = camera.ViewportSize
    scale.Scale = math.clamp(math.min((screen.X - 26) / 790, (screen.Y - 26) / 535), 0.48, 1)
end
adjustScale()
local cameraConnection
local function watchCamera()
    if cameraConnection then cameraConnection:Disconnect() end
    local camera = workspace.CurrentCamera
    if camera then cameraConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(adjustScale) end
    adjustScale()
end
watchCamera()
local changeCameraConnection = workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)

-- Top bar
local header = create("Frame", {
    Name = "Header", Size = UDim2.new(1, 0, 0, 64),
    BackgroundColor3 = COLORS.panel, BorderSizePixel = 0,
}, window)
round(header, 16)
create("Frame", {
    Position = UDim2.new(0, 0, 1, -1), Size = UDim2.new(1, 0, 0, 1),
    BackgroundColor3 = COLORS.line, BorderSizePixel = 0,
}, header)
txt(header, "✦", 28, COLORS.purple, true, {
    Position = UDim2.fromOffset(20, 9), Size = UDim2.fromOffset(33, 44),
    TextXAlignment = Enum.TextXAlignment.Center,
})
txt(header, "POLY HUB", 20, COLORS.white, true, {
    Position = UDim2.fromOffset(62, 9), Size = UDim2.fromOffset(225, 27),
})
txt(header, "CENTRAL DE UTILIDADES", 10, COLORS.muted, false, {
    Position = UDim2.fromOffset(63, 35), Size = UDim2.fromOffset(300, 17),
})

local minimize = button(header, "—", {
    Size = UDim2.fromOffset(35, 32), Position = UDim2.new(1, -87, 0, 16),
    BackgroundTransparency = 1, TextSize = 20,
})
local close = button(header, "×", {
    Size = UDim2.fromOffset(35, 32), Position = UDim2.new(1, -45, 0, 16),
    BackgroundTransparency = 1, TextSize = 24,
})

local sidebar = create("Frame", {
    Name = "Sidebar", Position = UDim2.fromOffset(0, 65),
    Size = UDim2.new(0, 205, 1, -65),
    BackgroundColor3 = COLORS.panel, BorderSizePixel = 0,
}, window)
create("Frame", {Position = UDim2.new(1, -1, 0, 0), Size = UDim2.new(0, 1, 1, 0), BackgroundColor3 = COLORS.line, BorderSizePixel = 0}, sidebar)

local content = create("Frame", {
    Name = "Content", Position = UDim2.fromOffset(220, 78),
    Size = UDim2.new(1, -234, 1, -92),
    BackgroundTransparency = 1,
}, window)

local pageTitle = txt(content, "Auto Farm", 23, COLORS.white, true, {
    Size = UDim2.new(1, 0, 0, 33),
})
local pageSubtitle = txt(content, "Configure a masmorra e acompanhe o estado do sistema.", 11, COLORS.muted, false, {
    Position = UDim2.fromOffset(0, 31), Size = UDim2.new(1, 0, 0, 22),
})
local pageArea = create("Frame", {
    Position = UDim2.fromOffset(0, 64),
    Size = UDim2.new(1, 0, 1, -64), BackgroundTransparency = 1,
}, content)

local statusText
local function updateStatus(message)
    if statusText then statusText.Text = message end
end

local pages = {}
local navButtons = {}

local function navItem(id, icon, caption, index)
    local navHeight = index <= 5 and 46 or 38
    local navY = index <= 5 and (20 + (index - 1) * 58) or (300 + (index - 6) * 42)
    local nav = button(sidebar, "", {
        Position = UDim2.fromOffset(12, navY),
        Size = UDim2.new(1, -24, 0, navHeight),
        BackgroundColor3 = COLORS.card, BackgroundTransparency = 1,
    })
    round(nav, 10)
    local strip = create("Frame", {
        Visible = false, Position = UDim2.fromOffset(0, 4),
        Size = UDim2.fromOffset(3, navHeight - 8), BorderSizePixel = 0,
        BackgroundColor3 = COLORS.purple,
    }, nav)
    round(strip, 3)
    local iconLabel = txt(nav, icon, 22, COLORS.muted, true, {
        Position = UDim2.fromOffset(12, 0), Size = UDim2.fromOffset(34, navHeight),
        TextXAlignment = Enum.TextXAlignment.Center,
    })
    local title = txt(nav, caption, 14, COLORS.muted, true, {
        Position = UDim2.fromOffset(55, 0), Size = UDim2.new(1, -62, 1, 0),
    })
    navButtons[id] = {frame = nav, strip = strip, icon = iconLabel, label = title}
    return nav
end

local function scrollPage(key)
    local page = create("ScrollingFrame", {
        Name = key, Size = UDim2.fromScale(1, 1),
        ScrollBarThickness = 3, ScrollBarImageColor3 = COLORS.purple,
        BackgroundTransparency = 1, Visible = false,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        CanvasSize = UDim2.fromOffset(0, 0), BorderSizePixel = 0,
    }, pageArea)
    create("UIListLayout", {
        Padding = UDim.new(0, 11), SortOrder = Enum.SortOrder.LayoutOrder,
    }, page)
    create("UIPadding", {
        PaddingLeft = UDim.new(0, 2), PaddingRight = UDim.new(0, 8),
        PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 10),
    }, page)
    pages[key] = page
    return page
end

local autoPage = scrollPage("auto")
local castlePage = scrollPage("castle")
local candyPage = scrollPage("candy")
local playerPage = scrollPage("player")
local settingsPage = scrollPage("settings")

local pageMeta = {
    auto = {"Auto Farm", "Configure opções da masmorra e acompanhe seu estado."},
    castle = {"Auto Farm Castelo", "Ajuste altura por proximidade ou subida direta contra Dracula."},
    candy = {"Auto Farm Doces", "Capture ghosts com a rede e acompanhe a caça."},
    player = {"Player", "Noclip, Speed e Infinite Jump para sua experiência Roblox."},
    settings = {"Configurações", "Atalhos e informações do hub."},
}
local selectedTab = "auto"
local function selectTab(key)
    selectedTab = key
    for id, page in pairs(pages) do page.Visible = (id == key) end
    for id, elements in pairs(navButtons) do
        local active = id == key
        elements.frame.BackgroundTransparency = active and 0.1 or 1
        elements.frame.BackgroundColor3 = active and COLORS.card or COLORS.panel
        elements.strip.Visible = active
        elements.label.TextColor3 = active and COLORS.white or COLORS.muted
        elements.icon.TextColor3 = active and COLORS.purple or COLORS.muted
    end
    pageTitle.Text = pageMeta[key][1]
    pageSubtitle.Text = pageMeta[key][2]
end

navItem("auto", "⚔", "Auto Farm", 1).MouseButton1Click:Connect(function() selectTab("auto") end)
navItem("castle", "♛", "Auto Farm Castelo", 2).MouseButton1Click:Connect(function() selectTab("castle") end)
navItem("candy", "◈", "Auto Farm Doces", 3).MouseButton1Click:Connect(function() selectTab("candy") end)
navItem("player", "♙", "Player", 4).MouseButton1Click:Connect(function() selectTab("player") end)
navItem("settings", "⚙", "Config.", 5).MouseButton1Click:Connect(function() selectTab("settings") end)
navButtons.castle.label.TextSize = 11.5

local function cardBase(parent, title, detail, symbol, height)
    local h = height or 80
    local box = create("Frame", {
        BackgroundColor3 = COLORS.card, BorderSizePixel = 0,
        Size = UDim2.new(1, -2, 0, h),
    }, parent)
    round(box, 12)
    outline(box, COLORS.line, 1, 0.25)
    txt(box, symbol, 21, COLORS.purple, true, {
        Position = UDim2.fromOffset(15, 15), Size = UDim2.fromOffset(32, 33),
        TextXAlignment = Enum.TextXAlignment.Center,
    })
    txt(box, title, 14, COLORS.white, true, {
        Position = UDim2.fromOffset(58, 14), Size = UDim2.new(1, -145, 0, 24),
    })
    txt(box, detail, 10, COLORS.muted, false, {
        Position = UDim2.fromOffset(58, 39), Size = UDim2.new(1, -134, 0, 27),
        TextWrapped = true,
    })
    return box
end

-- Callbacks de recursos Player; definidos antes da configuração dos controles.
local playerEffects = {}
local toggles = {}
local function addToggle(parent, key, title, detail, symbol)
    local box = cardBase(parent, title, detail, symbol, 83)
    local hit = button(box, "", {
        Position = UDim2.new(1, -75, 0.5, -17),
        Size = UDim2.fromOffset(54, 34),
        BackgroundColor3 = COLORS.panel,
    })
    round(hit, 17)
    outline(hit, COLORS.line, 1)
    local knob = create("Frame", {
        Position = UDim2.fromOffset(5, 5), Size = UDim2.fromOffset(24, 24),
        BackgroundColor3 = COLORS.muted, BorderSizePixel = 0,
    }, hit)
    round(knob, 13)
    local backgroundTween
    local knobTween
    -- Os interruptores animam ao serem ativados/desativados.
    local function draw(active, instant)
        if backgroundTween then backgroundTween:Cancel() end
        if knobTween then knobTween:Cancel() end
        local backgroundColor = active and COLORS.purpleDark or COLORS.panel
        local knobPosition = active and UDim2.fromOffset(25, 5) or UDim2.fromOffset(5, 5)
        local knobColor = active and COLORS.white or COLORS.muted
        if instant then
            hit.BackgroundColor3 = backgroundColor
            knob.Position = knobPosition
            knob.BackgroundColor3 = knobColor
        else
            backgroundTween = TweenService:Create(hit, TweenInfo.new(0.16), {
                BackgroundColor3 = backgroundColor,
            })
            knobTween = TweenService:Create(knob, TweenInfo.new(0.16), {
                Position = knobPosition,
                BackgroundColor3 = knobColor,
            })
            backgroundTween:Play()
            knobTween:Play()
        end
        screenGui:SetAttribute(key, active)
    end
    hit.MouseButton1Click:Connect(function()
        state[key] = not state[key]
        draw(state[key])
        onSettingChanged(key, state[key])
        local handler = playerEffects[key]
        if handler then handler(state[key]) end
        if handler then
            updateStatus(title .. ": " .. (state[key] and "ativado" or "desativado"))
        else
            updateStatus(title .. ": " .. (state[key] and "ativado (interface)" or "desativado"))
        end
    end)
    toggles[key] = draw
    draw(state[key], true)
end

-- Seleção de masmorra: por ora há só a opção da masmorra conhecida.
state._uiRefs.dungeonCard = cardBase(autoPage, "Selecionar masmorra", "Escolha o cenário monitorado.", "◈", 102)
state._uiRefs.dungeonButton = button(state._uiRefs.dungeonCard, state.dungeon .. "   ▾", {
    Position = UDim2.fromOffset(58, 61), Size = UDim2.new(1, -74, 0, 29),
    BackgroundColor3 = COLORS.panel, TextSize = 11,
    TextXAlignment = Enum.TextXAlignment.Left,
})
round(state._uiRefs.dungeonButton, 7)
outline(state._uiRefs.dungeonButton, COLORS.line, 1, 0.35)
create("UIPadding", {PaddingLeft = UDim.new(0, 12)}, state._uiRefs.dungeonButton)
state._uiRefs.dungeonButton.MouseButton1Click:Connect(function()
    updateStatus("Masmorra selecionada: " .. state.dungeon)
    onSettingChanged("dungeon", state.dungeon)
end)

addToggle(autoPage, "autoFarm", "Auto Farm", "Ativa a opção visual; conecte ao motor para executar ações.", "▷")
addToggle(autoPage, "autoReplay", "Auto Replay", "Permitir nova partida após conclusão, quando integrado.", "↻")
addToggle(autoPage, "bossPriority", "Prioridade Boss", "Preferir bosses quando o motor de combate estiver integrado.", "♛")
addToggle(autoPage, "antiAFK", "Anti-AFK", "Opção preparada para lógica autorizada do projeto.", "◇")

state._uiRefs.statusCard = cardBase(autoPage, "Status do sistema", "As preferências são salvas nesta sessão do hub.", "▥", 82)
statusText = txt(state._uiRefs.statusCard, "Pronto · Somente interface", 11, COLORS.success, true, {
    Position = UDim2.new(1, -215, 0, 21), Size = UDim2.fromOffset(200, 34),
    TextXAlignment = Enum.TextXAlignment.Right, TextWrapped = true,
})

-- AUTO FARM DOCES: somente a LOGICA do script compartilhado. A UI original
-- do Ghost Net Farm NAO e criada; usamos cards e toggles deste proprio hub.
-- Ajuste estes nomes para os objetos reais da sua experiencia.
local GHOST_CONFIG = {
    folder = "Halloween_Ghosts", -- "" procura filhos diretos de Workspace
    tool = "GhostNet",
    candyNames = {"CandyCorn", "Candy Corn", "Candy_Corn"},
    approachDistance = 10, -- Valor calibrado pelo usuario na experiencia
    catchDistance = 12,
    swingInterval = 0.8,
    moveInterval = 0.35,
    refreshInterval = 0.5,
    -- Tempo da tentativa aumentado para tolerar animação/latência do servidor.
    captureTimeout = 5.0,
    failedTargetCooldown = 14,
    successfulTargetCooldown = 5,
    minProgressStuds = 2.5,
    stuckSeconds = 3.5,
    pathReplanInterval = 3.0,
    waypointReachDistance = 3.2,
    maxPathFailures = 3,
}
local TIER_ORDER = {Gold = 1, Blue = 2, White = 3}
local TIER_TEXT = {Gold = "Ouro", Blue = "Azul", White = "Branco"}
local priorityOptions = {"Raridade", "Mais próximo", "Somente Ouro", "Somente Azul", "Somente Branco"}

local ghostCurrentTarget = nil
local ghostSkipUntil = setmetatable({}, {__mode = "k"})
local ghostTaskVersion = 0
local ghostCaptureCount = 0
local ghostLikelyCount = 0
local ghostFailureCount = 0
local ghostPathCount = 0
local ghostNetActivations = 0
local ghostEquippedToolByFarm = false
local ghostLastHumanoid = nil
local ghostStatusText
local ghostTargetText
local ghostCandyText
local ghostCapturedText
local ghostExtraText

local function showGhostStatus(value)
    if ghostStatusText and ghostStatusText.Parent then
        ghostStatusText.Text = "Estado: " .. value
    end
end

local function ghostGetCharacter()
    local character = localPlayer.Character
    if not character then return nil, nil, nil end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart")
    if not humanoid or not root or humanoid.Health <= 0 then return nil, nil, nil end
    return character, humanoid, root
end

local function ghostFolder()
    if GHOST_CONFIG.folder == "" then return workspace end
    return workspace:FindFirstChild(GHOST_CONFIG.folder)
end

local function ghostPosition(ghost)
    if not ghost or not ghost.Parent then return nil end
    if ghost:IsA("BasePart") then return ghost.Position end
    if ghost:IsA("Model") then
        local part = ghost.PrimaryPart
            or ghost:FindFirstChild("HumanoidRootPart", true)
            or ghost:FindFirstChildWhichIsA("BasePart", true)
        return part and part.Position or nil
    end
    return nil
end

local function ghostTier(ghost)
    -- O diagnostico confirmou que os ghosts reais usam "Rarity", nao "Tier".
    local attribute = ghost:GetAttribute("Rarity") or ghost:GetAttribute("Tier")
    if typeof(attribute) == "string" then
        local normalized = string.lower(attribute)
        if normalized == "gold" then return "Gold" end
        if normalized == "blue" then return "Blue" end
        if normalized == "white" then return "White" end
    end
    local name = string.lower(ghost.Name)
    if name:find("gold", 1, true) then return "Gold" end
    if name:find("blue", 1, true) then return "Blue" end
    return "White"
end

local function ghostValid(ghost)
    local folder = ghostFolder()
    if not folder or not ghost or ghost.Parent ~= folder then return false end
    if not (ghost:IsA("Model") or ghost:IsA("BasePart")) then return false end
    if ghost:GetAttribute("Caught") == true or ghost:GetAttribute("Collected") == true then
        return false
    end
    return ghostPosition(ghost) ~= nil
end

local function ghostAllowed(tier)
    if state.candyPriority == "Somente Ouro" then return tier == "Gold" end
    if state.candyPriority == "Somente Azul" then return tier == "Blue" end
    if state.candyPriority == "Somente Branco" then return tier == "White" end
    return true
end

local function ghostFindBest(rootPosition)
    local folder = ghostFolder()
    if not folder then return nil end
    local best = nil
    local bestPriority = math.huge
    local bestDistance = math.huge
    local now = os.clock()
    for _, ghost in ipairs(folder:GetChildren()) do
        local untilTime = ghostSkipUntil[ghost]
        if untilTime and untilTime <= now then
            ghostSkipUntil[ghost] = nil
            untilTime = nil
        end
        if not untilTime and ghostValid(ghost) then
            local tier = ghostTier(ghost)
            if ghostAllowed(tier) then
                local position = ghostPosition(ghost)
                if position then
                    local distance = (rootPosition - position).Magnitude
                    local rank = state.candyPriority == "Raridade"
                        and (TIER_ORDER[tier] or 3) or 1
                    if rank < bestPriority or (rank == bestPriority and distance < bestDistance) then
                        best, bestPriority, bestDistance = ghost, rank, distance
                    end
                end
            end
        end
    end
    return best
end

local function ghostEquippedNet()
    local character = localPlayer.Character
    local tool = character and character:FindFirstChild(GHOST_CONFIG.tool)
    return tool and tool:IsA("Tool") and tool or nil
end

local function ghostEquipNet(humanoid)
    if ghostEquippedNet() then return true end
    local backpack = localPlayer:FindFirstChildOfClass("Backpack")
    local tool = backpack and backpack:FindFirstChild(GHOST_CONFIG.tool)
    if tool and tool:IsA("Tool") then
        local ok = pcall(function() humanoid:EquipTool(tool) end)
        if ok then
            ghostEquippedToolByFarm = true
            print("[Poly Hub Doces] GhostNet equipada automaticamente")
        end
    end
    -- A replicacao do equipamento pode precisar de mais um frame.
    return ghostEquippedNet() ~= nil
end

local function ghostCandyValue()
    local sources = {localPlayer:FindFirstChild("leaderstats"), localPlayer}
    for _, source in ipairs(sources) do
        if source then
            for _, name in ipairs(GHOST_CONFIG.candyNames) do
                local child = source:FindFirstChild(name)
                if child and (child:IsA("IntValue") or child:IsA("NumberValue") or child:IsA("StringValue")) then
                    return tostring(child.Value)
                end
            end
        end
    end
    for _, name in ipairs(GHOST_CONFIG.candyNames) do
        local attribute = localPlayer:GetAttribute(name)
        if attribute ~= nil then return tostring(attribute) end
    end
    return nil
end

local function ghostUpdateCandyCounter()
    if ghostCandyText and ghostCandyText.Parent then
        ghostCandyText.Text = "Doces: " .. (ghostCandyValue() or "N/D")
    end
    if ghostCapturedText and ghostCapturedText.Parent then
        ghostCapturedText.Text = "Confirmadas: " .. tostring(ghostCaptureCount)
            .. "  |  Prováveis: " .. tostring(ghostLikelyCount)
    end
    if ghostExtraText and ghostExtraText.Parent then
        ghostExtraText.Text = "Falhas: " .. tostring(ghostFailureCount)
            .. "  |  Rotas: " .. tostring(ghostPathCount)
            .. "  |  Usos da rede: " .. tostring(ghostNetActivations)
    end
end

local function ghostStopMovement()
    -- MoveTo na posicao atual cancela o comando pendente, sem teleportar.
    local character, humanoid, root = ghostGetCharacter()
    local owner = humanoid or ghostLastHumanoid
    if owner and owner.Parent then
        pcall(function()
            if owner == humanoid and root then
                owner:MoveTo(root.Position)
            end
        end)
        if ghostEquippedToolByFarm and ghostEquippedNet() and owner == humanoid then
            pcall(function() owner:UnequipTools() end)
        end
    end
    ghostEquippedToolByFarm = false
    ghostLastHumanoid = nil
end

-- Um alvo fica bloqueado até capturar, desaparecer ou expirar por falha.
-- Evita trocar de fantasma a cada atualização de 0.5s.
local function ghostFarmLoop(version)
    local function active()
        return state.candyFarm and ghostTaskVersion == version and screenGui.Parent ~= nil
    end

    local lastMove = 0
    local lastSwing = 0
    local lastCandyUi = 0
    local activeTarget = nil
    local attemptStart = nil
    local candyBaseline = nil
    local didSwingForTarget = false

    local pathWaypoints = nil
    local pathIndex = 0
    local pathDestination = nil
    local lastPathCompute = -math.huge
    local pathFailures = 0
    local stuckCycles = 0
    local progressPosition = nil
    local progressTime = 0
    local wasInRange = false

    local function resetNavigation(position, now)
        pathWaypoints = nil
        pathIndex = 0
        pathDestination = nil
        lastPathCompute = -math.huge
        pathFailures = 0
        stuckCycles = 0
        progressPosition = position
        progressTime = now
        lastMove = 0
        wasInRange = false
    end

    local function forgetTarget(message, cooldown, countFailure)
        if activeTarget and cooldown and cooldown > 0 and ghostValid(activeTarget) then
            ghostSkipUntil[activeTarget] = os.clock() + cooldown
        end
        if countFailure then ghostFailureCount += 1 end
        if message then
            showGhostStatus(message)
            print("[Poly Hub Doces] " .. message)
        end
        ghostCurrentTarget = nil
        activeTarget = nil
        attemptStart = nil
        candyBaseline = nil
        didSwingForTarget = false
        resetNavigation(nil, os.clock())
        ghostUpdateCandyCounter()
    end

    ghostCurrentTarget = nil
    while active() do
        local now = os.clock()
        if now - lastCandyUi >= 0.5 then
            ghostUpdateCandyCounter()
            lastCandyUi = now
        end

        local _, humanoid, root = ghostGetCharacter()
        if not humanoid then
            ghostCurrentTarget = nil
            activeTarget = nil
            attemptStart = nil
            candyBaseline = nil
            didSwingForTarget = false
            resetNavigation(nil, now)
            showGhostStatus("Aguardando personagem/respawn")
            task.wait(0.3)
            continue
        end

        ghostLastHumanoid = humanoid
        if not ghostEquipNet(humanoid) then
            showGhostStatus("Procurando ferramenta " .. GHOST_CONFIG.tool)
            task.wait(0.35)
            continue
        end

        if ghostCurrentTarget and not ghostValid(ghostCurrentTarget) then
            -- Ghost desaparecido NÃO comprova que doces foram concedidos.
            local actualCount = tonumber(ghostCandyValue())
            if candyBaseline and actualCount and actualCount > candyBaseline then
                ghostCaptureCount += 1
                forgetTarget("Captura confirmada pelo contador", 0, false)
            elseif didSwingForTarget then
                ghostLikelyCount += 1
                forgetTarget("Ghost sumiu após usar rede (não confirmado)", 0, false)
            else
                forgetTarget("Ghost desapareceu antes da captura", 0, false)
            end
        end

        -- Procura novo alvo SOMENTE quando o anterior terminou ou falhou.
        if not ghostCurrentTarget then
            ghostCurrentTarget = ghostFindBest(root.Position)
        end
        if ghostCurrentTarget ~= activeTarget then
            activeTarget = ghostCurrentTarget
            attemptStart = nil
            candyBaseline = nil
            didSwingForTarget = false
            resetNavigation(root.Position, now)
            if activeTarget then
                print("[Poly Hub Doces] Fixado alvo: " .. activeTarget.Name
                    .. " | prioridade=" .. state.candyPriority)
            end
        end

        if not activeTarget then
            if ghostTargetText then ghostTargetText.Text = "Alvo: nenhum" end
            if not ghostFolder() then
                showGhostStatus("Pasta ausente: " .. GHOST_CONFIG.folder)
            else
                showGhostStatus("Aguardando ghost elegível")
            end
            task.wait(0.4)
            continue
        end

        local targetPosition = ghostPosition(activeTarget)
        if not targetPosition then
            forgetTarget("Alvo sem posição", 0, false)
            task.wait(0.12)
            continue
        end

        local tier = ghostTier(activeTarget)
        if ghostTargetText and ghostTargetText.Parent then
            ghostTargetText.Text = "Alvo: " .. (TIER_TEXT[tier] or tier)
                .. " · " .. activeTarget.Name
        end

        local distance = (root.Position - targetPosition).Magnitude
        if distance > GHOST_CONFIG.approachDistance then
            wasInRange = false
            attemptStart = nil
            candyBaseline = nil
            didSwingForTarget = false

            if not progressPosition or (root.Position - progressPosition).Magnitude >= GHOST_CONFIG.minProgressStuds then
                progressPosition = root.Position
                progressTime = now
                stuckCycles = 0
            end

            -- Se o trajeto ficar obstruído, calcula uma rota normal pelo mapa.
            -- Não teleporta, não atravessa paredes nem altera colisão.
            local isStuck = now - progressTime >= GHOST_CONFIG.stuckSeconds
            local canRepath = now - lastPathCompute >= GHOST_CONFIG.pathReplanInterval
            if isStuck and canRepath then
                stuckCycles += 1
                if stuckCycles > GHOST_CONFIG.maxPathFailures then
                    forgetTarget("Sem progresso ao caminhar; próximo ghost", GHOST_CONFIG.failedTargetCooldown, true)
                    task.wait(0.1)
                    continue
                end
                lastPathCompute = now
                local from = root.Position
                local goal = targetPosition
                showGhostStatus("Obstáculo encontrado; buscando rota")
                local pathOk, waypointsOrError = pcall(function()
                    local path = PathfindingService:CreatePath({
                        AgentRadius = 2, AgentHeight = 5,
                        AgentCanJump = true, WaypointSpacing = 5,
                    })
                    path:ComputeAsync(from, goal)
                    if path.Status ~= Enum.PathStatus.Success then
                        return nil
                    end
                    return path:GetWaypoints()
                end)
                if not active() then break end
                if pathOk and waypointsOrError and #waypointsOrError >= 2 then
                    pathWaypoints = waypointsOrError
                    pathIndex = 2
                    pathDestination = goal
                    pathFailures = 0
                    ghostPathCount += 1
                    progressPosition = root.Position
                    progressTime = os.clock()
                    print("[Poly Hub Doces] Rota calculada: " .. #waypointsOrError .. " pontos")
                else
                    pathFailures += 1
                    progressTime = os.clock()
                    print("[Poly Hub Doces] Caminho bloqueado (" .. pathFailures .. ")")
                    if pathFailures >= GHOST_CONFIG.maxPathFailures then
                        forgetTarget("Ghost inacessível; próximo alvo", GHOST_CONFIG.failedTargetCooldown, true)
                        task.wait(0.1)
                        continue
                    end
                end
            end

            local movePosition = targetPosition
            if pathWaypoints and pathIndex >= 2 then
                if pathDestination and (targetPosition - pathDestination).Magnitude > 13 then
                    pathWaypoints = nil -- Ghost se moveu; retoma perseguição direta.
                    pathIndex = 0
                else
                    while pathWaypoints and pathIndex <= #pathWaypoints do
                        local waypoint = pathWaypoints[pathIndex]
                        if (root.Position - waypoint.Position).Magnitude > GHOST_CONFIG.waypointReachDistance then
                            movePosition = waypoint.Position
                            if waypoint.Action == Enum.PathWaypointAction.Jump then
                                humanoid.Jump = true
                            end
                            break
                        end
                        pathIndex += 1
                    end
                    if pathWaypoints and pathIndex > #pathWaypoints then
                        pathWaypoints = nil
                        pathIndex = 0
                    end
                end
            end

            showGhostStatus(string.format("Perseguindo ghost (%.0f studs)%s", distance,
                pathWaypoints and " · rota alternativa" or ""))
            if now - lastMove >= GHOST_CONFIG.moveInterval then
                lastMove = now
                if active() then pcall(function() humanoid:MoveTo(movePosition) end) end
            end
            task.wait(0.1)
        else
            -- Só tenta capturar quando estiver realmente próximo.
            -- Não interrompe a caminhada prematuramente (sem MoveTo(root.Position)).
            if not wasInRange then
                wasInRange = true
            end
            pathWaypoints = nil
            pathIndex = 0
            local count = tonumber(ghostCandyValue())
            if not attemptStart then
                attemptStart = now
                candyBaseline = count
                didSwingForTarget = false
            elseif candyBaseline and count and count > candyBaseline then
                ghostCaptureCount += 1
                forgetTarget("Doce confirmado (+" .. tostring(count - candyBaseline) .. ")", GHOST_CONFIG.successfulTargetCooldown, false)
                task.wait(0.1)
                continue
            end

            showGhostStatus("Capturando ghost (em alcance)")
            local net = ghostEquippedNet()
            if net and now - lastSwing >= GHOST_CONFIG.swingInterval then
                -- Reconfirma posição do ghost no instante do ataque.
                -- Se ele se moveu, a perseguição continua sem gastar a paulada.
                local positionNow = ghostPosition(activeTarget)
                if positionNow and active() then
                    local distanceNow = (root.Position - positionNow).Magnitude
                    if distanceNow <= GHOST_CONFIG.approachDistance then
                        lastSwing = now
                        local ok = pcall(function() net:Activate() end)
                        if ok then
                            didSwingForTarget = true
                            ghostNetActivations += 1
                        else
                            showGhostStatus("Falha ao ativar a rede")
                        end
                    else
                        wasInRange = false
                        if now - lastMove >= GHOST_CONFIG.moveInterval then
                            lastMove = now
                            pcall(function() humanoid:MoveTo(positionNow) end)
                        end
                        showGhostStatus(string.format(
                            "Ghost se afastou (%.1f studs); perseguindo", distanceNow
                        ))
                    end
                end
            end

            if attemptStart and now - attemptStart >= GHOST_CONFIG.captureTimeout then
                forgetTarget("Tempo de captura esgotado; trocando alvo", GHOST_CONFIG.failedTargetCooldown, true)
            end
            task.wait(0.12)
        end
    end
end

local function setGhostFarm(active)
    -- Aumentar a versao interrompe loops antigos, inclusive se o usuario
    -- desligar e religar imediatamente.
    ghostTaskVersion += 1
    local version = ghostTaskVersion
    if active then
        if state._uiRefs.stopExternalAutomation then pcall(state._uiRefs.stopExternalAutomation, "PolyHub Doces") end
        print("[Poly Hub Doces] Auto Farm Doces ON | Prioridade: " .. state.candyPriority)
        ghostCaptureCount = 0
        ghostLikelyCount = 0
        ghostFailureCount = 0
        ghostPathCount = 0
        ghostNetActivations = 0
        ghostCurrentTarget = nil
        ghostSkipUntil = setmetatable({}, {__mode = "k"})
        showGhostStatus("Iniciando")
        ghostUpdateCandyCounter()
        task.spawn(function()
            local ok, err = xpcall(function() ghostFarmLoop(version) end, function(message)
                return tostring(message)
            end)
            if not ok then
                warn("[Poly Hub Doces] Erro no farm: " .. tostring(err))
                -- Quando ocorre erro, desarma o toggle real e visual.
                if ghostTaskVersion == version and screenGui.Parent then
                    state.candyFarm = false
                    local draw = toggles.candyFarm
                    if draw then draw(false) end
                    showGhostStatus("Erro; veja o Output do Studio")
                    ghostStopMovement()
                end
            end
        end)
    else
        print("[Poly Hub Doces] Auto Farm Doces OFF")
        ghostCurrentTarget = nil
        showGhostStatus("Desativado")
        if ghostTargetText then ghostTargetText.Text = "Alvo: nenhum" end
        ghostStopMovement()
    end
end

playerEffects.candyFarm = setGhostFarm

-- Controles proprios do Poly Hub (a interface do script de origem nao foi usada).
addToggle(candyPage, "candyFarm", "Caçar ghosts", "Equipa GhostNet, mantém o alvo e usa rota alternativa se necessário.", "◈")
state._uiRefs.priorityCard = cardBase(candyPage, "Prioridade dos alvos", "Filtre a raridade ou capture o mais proximo.", "♢", 104)
state._uiRefs.priorityButton = button(state._uiRefs.priorityCard, state.candyPriority .. "   ▾", {
    Position = UDim2.fromOffset(58, 63), Size = UDim2.new(1, -74, 0, 29),
    BackgroundColor3 = COLORS.panel, TextSize = 11,
})
round(state._uiRefs.priorityButton, 7)
outline(state._uiRefs.priorityButton, COLORS.line, 1, 0.3)
state._uiRefs.priorityButton.MouseButton1Click:Connect(function()
    local current = table.find(priorityOptions, state.candyPriority) or 0
    state.candyPriority = priorityOptions[(current % #priorityOptions) + 1]
    state._uiRefs.priorityButton.Text = state.candyPriority .. "   ▾"
    ghostCurrentTarget = nil
    onSettingChanged("candyPriority", state.candyPriority)
end)

state._uiRefs.candyStatusCard = cardBase(candyPage, "Status da caca", "Atividade da rede e recompensas da sessao.", "▥", 122)
ghostStatusText = txt(state._uiRefs.candyStatusCard, "Estado: desativado", 11, COLORS.success, true, {
    Position = UDim2.fromOffset(58, 67), Size = UDim2.new(1, -74, 0, 17),
    TextTruncate = Enum.TextTruncate.AtEnd,
})
ghostTargetText = txt(state._uiRefs.candyStatusCard, "Alvo: nenhum", 10, COLORS.white, false, {
    Position = UDim2.fromOffset(58, 91), Size = UDim2.new(1, -74, 0, 17),
    TextTruncate = Enum.TextTruncate.AtEnd,
})
state._uiRefs.candyCounterCard = cardBase(candyPage, "Coleta de doces", "Só confirma capturas com aumento numérico dos doces.", "✦", 140)
ghostCandyText = txt(state._uiRefs.candyCounterCard, "Doces: N/D", 11, COLORS.success, true, {
    Position = UDim2.fromOffset(58, 66), Size = UDim2.fromOffset(170, 18),
})
ghostCapturedText = txt(state._uiRefs.candyCounterCard, "Confirmadas: 0 | Prováveis: 0", 10, COLORS.muted, false, {
    Position = UDim2.fromOffset(58, 89), Size = UDim2.new(1, -74, 0, 18),
})
ghostExtraText = txt(state._uiRefs.candyCounterCard, "Falhas: 0 | Rotas: 0 | Usos da rede: 0", 10, COLORS.muted, false, {
    Position = UDim2.fromOffset(58, 112), Size = UDim2.new(1, -74, 0, 18),
})
ghostUpdateCandyCounter()


-- ================================================================
-- AUTO FARM CASTELO | motor local experimental (independente do farm de doces)
-- ================================================================
-- Os modelos reais foram observados em Workspace.Animal_Live.Aggressors.
-- Aproxima no chao usando MoveTo. O ajuste Y so e aplicado DEPOIS de
-- entrar na distancia de aproximacao (medida no plano X/Z).
local CASTLE_CONFIG = {
    rootFolder = "Animal_Live",
    aggressorsFolder = "Aggressors",
    attackInterval = 0.28,
    moveInterval = 0.28,
    updateInterval = 0.11,
    maxAcquireDistance = 95,     -- outros inimigos; Dracula usa state.castleDraculaDetectionRange
    disengagePadding = 4,       -- distancia extra para retornar ao chao
    maxHeight = 20,
    maxVerticalAcceleration = 80,
    directChaseMaxSpeed = 24, -- quando flutuando, segue o Dracula sem teleportar
    directChaseGain = 2.0,
    directChaseVelocityGain = 3.5,
    directChaseMaxAcceleration = 45,
    verticalStiffness = 15,
    verticalDamping = 7,
    -- Assistencia curta apenas quando preso em superficie com altura negativa.
    verticalAssistInterval = 0.20,
    verticalAssistStep = 0.9,
    verticalAssistStuckSeconds = 0.22,

    -- Ponto selecionado no Universal Debug apos a fuga do Dracula.
    -- A movimentacao usa MoveTo + caminho pelo chao, sem teleportar.
    golemTriggerPosition = Vector3.new(6328.90, 273.93, -6003.89),
    finalExitPosition = Vector3.new(6502.43, 258.94, -6000.00), -- saida fixa fornecida pelo usuario
    golemTriggerRadius = 3.5, -- manter alcance do gatilho se boss AINDA nao apareceu
    golemTriggerYTolerance = 15.0,
    golemEngageRadius = 24.0, -- com fuga confirmada e boss visivel nesta area, ja atacar
    golemEngageYTolerance = 18.0,
    -- Dracula escapa com APROXIMADAMENTE metade da vida; 55% apenas
    -- ARMA a verificacao. Nao iniciar caminho enquanto estiver atacando.
    draculaRetreatArmFraction = 0.55,
    draculaRetreatGoneSeconds = 0.9,
    draculaRetreatCutsceneSeconds = 0.8,
    draculaObserveRadius = 120,
    golemRecoveryDistance = 250, -- permite reencontrar Golem longe apos respawn
    golemHeightHoldPadding = 90, -- manter sustentacao na arena mesmo quando boss recua bastante
    golemHeightEngageDistance = 20, -- decolar perto da SUPERFICIE do Golem, antes dos golpes
    golemHeightTakeoffRetrySeconds = 2.6, -- evitar spam de Jump e kick
    golemHeightTakeoffMaxTries = 3, -- primeira decolagem + ate duas tentativas suaves
    cutsceneWaitSeconds = 5.0, -- Dracula FOGE: espera a janela quebrar.
    cutsceneMaxSeconds = 7.5, -- Evita travar se CameraType continuar Scriptable apos a cena.
    routeRecalculateInterval = 2.8,
    routeStuckSeconds = 2.5,
    routeWaypointRadius = 3.5,
    routeMoveRefreshSeconds = 1.4, -- nao reiniciar MoveTo a cada frame
    routeDirectLineMaxDistance = 35,
    teleportArrivalRadius = 7.0,
    teleportArrivalYTolerance = 16.0,
    teleportInitialRetrySeconds = 3.0, -- nao repetir em cada frame
    teleportMaxRetrySeconds = 14.0, -- backoff progressivo se o servidor devolver
    teleportSceneExitGraceSeconds = 0.5,
    combatTeleportInterval = 1.8, -- deslocamento com pausa, sem TP por frame
    combatTeleportBounceCheck = 0.85,
    combatTeleportMaxFailures = 3, -- se servidor bloquear, usa WALK ate novo alvo/respawn
    combatTeleportOffset = 3.0, -- distancia para fora da MeshPart do boss
    combatTeleportHeightTolerance = 3,
    combatTeleportFollowRange = 5.0, -- so reposicionar se saiu do lado do boss
    -- O gate de proximidade do Dracula e independente do alcance de detecao
    -- e da distancia de ataque. O usuario ajusta no painel do Castelo.
    -- O timer do Q agora usa state.castleQInterval; por seguranca,
    -- uma unica tentativa por intervalo (sem retry duplo da v22).
    qRetryAfterFailure = 5.0,
    appleMinInterval = 6.0, -- anti-desperdicio: uma tentativa por 6s
    appleNotFoundInterval = 5.0,
    uiCheckInterval = 0.55,
    uiClickRetrySeconds = 2.5,
    defeatRetrySeconds = 2.5,
    replayResetWaitSeconds = 4.0,
    replayMaxWaitSeconds = 16.0,
}

local castleVersion = 0
local castleTarget = nil
local castleAttackCount = 0
local castleDraculaSeen = false
local castleDraculaTookDamage = false
local castleDraculaLastHealth = nil
local castleDraculaPositiveModel = nil -- mesmo model observado com HP > 55%
local castleDraculaMissingSince = nil
local castleDraculaLastPosition = nil
local castleDraculaAttacks = 0
local castleDraculaObservations = 0
local castleRunId = nil
-- Estados da sequencia: dracula -> cutscene -> trigger -> golem -> concluido.
local castlePhase = "dracula"
local castlePhaseStartedAt = 0
local castleRouteWaypoints = nil
local castleRouteIndex = 1
local castleRouteCalculatedAt = 0
local castleRouteLastProgressAt = 0
local castleRouteLastPos = nil
local castleLastRouteMoveAt = 0
local castleCutsceneReason = ""
local castleVerticalAttachment = nil
local castleVerticalForce = nil
local castleVerticalConnection = nil
local castleVerticalRoot = nil
local castleHeightGoal = nil
local castleDirectChasePosition = nil
local castleTempNoclip = false
local castleSafeRootCFrame = nil
local castleSafeRoot = nil
local castleHeightProgressY = nil
local castleHeightProgressAt = 0
local castleLastVerticalAssistAt = 0
local castleVerticalAssistCount = 0
local castleRuntime = {
    castleDraculaMaxHealth = nil,
    castleDraculaRetreatModel = nil,
    castleDraculaRetreatArmedAt = 0,
    castleDraculaRetreatLastRatio = nil,
    castleDraculaRetreatGoneSince = nil,
    castleDraculaRetreatCameraSince = nil,
    castleDraculaCameraWasScriptableOnArm = false,
    castleDirectTakeoffAt = 0,
    castleFinalPosition = CASTLE_CONFIG.finalExitPosition, -- destino fixo da saida
    castleFinishConfirmedAt = 0,
    castleGolemSeen = false,
    castleGolemTookDamage = false,
    castleGolemLastHealth = nil,
    castleGolemMissingSince = nil,
    castleGolemAttacks = 0,
    castleGolemLastDiagnosticAt = -math.huge,
    castleGolemRouteRecoveryCount = 0,
    -- Altura do corpo do Golem pode ficar ABAIXO do chao da arena.
    -- Guardar Y de entrada em combate para nao mandar subir ate um Y
    -- que na pratica ainda e altura do proprio chao.
    castleGolemHeightAnchorY = nil,
    castleGolemHeightDiagnosticAt = -math.huge,
    castleGolemNearStopIssued = false,
    castleGolemLiftAttempted = false,
    castleGolemLiftTries = 0,
    castleGolemLiftLastAt = 0,
    castleGolemLiftStartingY = nil,
    castleGolemRecoverAfterRespawn = false,
    castleGolemResumeAt = 0,
    castleLastBossSignature = nil,
    castleLastScannedUI = 0,
    castleUI = {loot = false, replay = false, starting = false,
        defeated = false, retry = false,
        lootPoint = nil, replayPoint = nil, retryPoint = nil},
    castleDefeatObserved = false,
    castleDefeatObservedAt = 0,
    castleDefeatCharacter = nil,
    castleLastDefeatDiagnostic = 0,
    castleLastUITap = 0,
    castleLastUIError = nil,
    castleReplayRequestedAt = 0,
    castleReplaySawStarting = false,
    castleReplayScreenWasVisible = false,
    castleCameraEverNonScriptable = false,
    castleCutsceneCameraSince = 0,
    castleDraculaHealthConnection = nil,
    castleDraculaHumanoidConnection = nil,
    castleDraculaWatchedModel = nil,
    castleLastEvidenceLog = 0,
    castleRouteHumanoid = nil,
    castleRouteOriginalSpeed = nil,
    castleRouteAppliedSpeed = nil,
    castleRouteMoveTarget = nil,
    castleRouteFailures = 0,
    castleRouteStuckRecoveries = 0,
    castleTeleportContext = nil, -- TP para checkpoint/saida (nao alterar)
    castleCombatTeleportContext = nil, -- separado: TP de combate, alvo, char e Y base
    -- Sinais de uma nova vida. O combate v20 nao e modificado:
    -- apenas invalidamos o estado da fase/arena antiga apos o respawn.
    castleBoundCharacter = nil,
    castleBoundHumanoid = nil,
    castlePendingRespawnCharacter = nil,
    castlePendingRespawnHumanoid = nil,
    castlePendingRespawnAt = 0,
    castleRespawnResetCount = 0,
    castleLastLifecycleLog = 0,
    castleLastQCastAt = -math.huge,
    castleLastQAttemptAt = -math.huge,
    castleLastQMethod = 'nenhum',
    castleQFailures = 0,
    castleQLastObservation = 'aguardando',
    castleQStatusUpdatedAt = 0,
    castleQToolRef = nil,
    castleQToolReadyAt = 0,
    castleAppleUsing = false,
    castleAppleNextAt = 0,
    castleAppleLastAttemptAt = -math.huge,
    castleAppleAttempts = 0,
    castleAppleLastMissingLogAt = -math.huge,
    castleAppleLastMessage = "aguardando",
}
-- Ligacoes definidas na aba Player mais abaixo; ambas as fontes de Noclip
-- (manual/combate) usam EXATAMENTE a mesma tabela de colisoes originais.
local castleNoclipApply = function() end
local castleNoclipRestore = function() end
local castleStatusText = nil
local castleTargetText = nil
local castlePhaseText = nil
local castleAttackText = nil
local castleNoclipText = nil
local castleAppleStatusText = nil
local castleApproachInput
local castleHeightInput

local function castleStatus(message)
    if castleStatusText and castleStatusText.Parent then
        castleStatusText.Text = "Estado: " .. tostring(message)
    end
end

local function castleUpdateDetails()
    if castlePhaseText and castlePhaseText.Parent then
        local phaseLabels = {
            dracula = "Etapa: 1/3 - Dracula (ate a fuga ~50%)",
            cutscene = "Etapa: 2/3 - Dracula fugiu / janela quebrando",
            trigger = "Etapa: 2/3 - Indo ativar boss final",
            golem = "Etapa: 3/3 - GraveGolem",
            finish_route = "Etapa: 4/5 - Saindo da sala final",
            loot = "Etapa: 4/5 - Confirmar recompensa",
            replay = "Etapa: 5/5 - Correr novamente",
            restart_wait = "Etapa: 5/5 - Nova corrida iniciando",
            concluido = "Etapa: Finalizado",
        }
        castlePhaseText.Text = phaseLabels[castlePhase] or "Etapa: verificando"
    end
    if castleAttackText and castleAttackText.Parent then
        castleAttackText.Text = string.format("Ataques enviados: %d  |  Altura: %s%g", castleAttackCount,
            state.castleHeight >= 0 and "+" or "", state.castleHeight)
    end
    if castleNoclipText and castleNoclipText.Parent then
        local currentHeight = ""
        if castleHeightGoal ~= nil and castleVerticalRoot and castleVerticalRoot.Parent then
            local measuredOffset = castleVerticalRoot.Position.Y - (castleHeightGoal - state.castleHeight)
            currentHeight = string.format(" | Y real: %+.1f", measuredOffset)
        end
        castleNoclipText.Text = (castleTempNoclip
            and "Noclip de combate: ATIVO" or "Noclip de combate: OFF") .. currentHeight
        castleNoclipText.TextColor3 = castleTempNoclip and COLORS.success or COLORS.muted
    end
end

-- Atualiza o status da maca sem sobrescrever o status do combate.
local function castleRefreshAppleStatus(message)
    if message then castleRuntime.castleAppleLastMessage = message end
    if castleAppleStatusText and castleAppleStatusText.Parent then
        castleAppleStatusText.Text = string.format(
            "Auto Maca: %s | HP <= %d%% | %s",
            state.castleAutoApple and "ON" or "OFF",
            state.castleAppleThreshold,
            castleRuntime.castleAppleLastMessage or "aguardando"
        )
    end
end

local function castleEnemyFolder()
    local animalLive = workspace:FindFirstChild(CASTLE_CONFIG.rootFolder)
    return animalLive and animalLive:FindFirstChild(CASTLE_CONFIG.aggressorsFolder) or nil
end

local function castleEnemyPosition(model)
    if not model or not model.Parent then return nil end
    if model:IsA("BasePart") then return model.Position end
    if model:IsA("Model") then
        -- No Universal Debug, GraveGolem e uma MeshPart FILHA de um Model
        -- com nome hexadecimal. A posicao do Model/PrimaryPart pode estar
        -- afastada da MeshPart real: usar a geometria do boss para mirar.
        local golemPart = model:FindFirstChild("GraveGolem", true)
        if golemPart and golemPart:IsA("BasePart") then
            return golemPart.Position
        end
        -- HumanoidRootPart representa a posicao real do alvo humanoide;
        -- PrimaryPart do modelo pode apontar para uma peca decorativa.
        local part = model:FindFirstChild("HumanoidRootPart", true)
            or model.PrimaryPart
            or model:FindFirstChildWhichIsA("BasePart", true)
        return part and part.Position or nil
    end
    return nil
end

local function castleEnemyHealth(model)
    if not model then return nil end
    local attribute = model:GetAttribute("Health")
    if typeof(attribute) == "number" then return attribute end
    local humanoid = model:FindFirstChildOfClass("Humanoid")
    if humanoid then return humanoid.Health end
    return nil
end

function castleRuntime.castleEnemyMaxHealth(model)
    if not model then return nil end
    local attribute = model:GetAttribute("MaxHealth")
    if typeof(attribute) == "number" and attribute > 0 then return attribute end
    local humanoid = model:FindFirstChildOfClass("Humanoid")
    if humanoid and humanoid.MaxHealth > 0 then return humanoid.MaxHealth end
    return nil -- nao inventar HP maximo: diagnosticar no Output
end

local function castleEnemyType(model)
    local value = model:GetAttribute("Animal")
    return typeof(value) == "string" and value or model.Name
end

-- Identifica o boss final confirmado pelo usuario. O jogo pode salvar
-- @Animal como "GraveGolem" ou com espaco/separador; o modelo pode ter ID
-- aleatorio, entao @Animal e prioritario, com Nome como fallback.
local function castleIsDracula(model)
    if not model then return false end
    local function matches(value)
        if typeof(value) ~= "string" then return false end
        local normalized = value:lower():gsub("[^%w]", "")
        return normalized == "countdracula" or normalized == "dracula"
    end
    return matches(model:GetAttribute("Animal"))
        or matches(model:GetAttribute("AttackType"))
        or matches(model.Name)
end

local function castleIsGraveGolem(model)
    if not model then return false end
    local function matchesName(value)
        return typeof(value) == "string"
            and value:lower():gsub("[^%w]", "") == "gravegolem"
    end
    -- Prioriza @Animal; @AttackType e Name sao alternativas se o modelo
    -- expuser o identificador do boss final em outro campo.
    if matchesName(model:GetAttribute("Animal"))
        or matchesName(model:GetAttribute("AttackType"))
        or matchesName(model.Name) then
        return true
    end
    -- No diagnostico do usuario, a MeshPart do boss final se chama
    -- "GraveGolem" mesmo quando o modelo externo tem nome hexadecimal.
    -- Fallback limitado a esse componente, sem confundir com PumpkinGolem.
    if model:IsA("Model") and model:FindFirstChild("GraveGolem", true) ~= nil then return true end
    -- Algumas interfaces localizam o nome do boss em portugues.
    local name = tostring(model:GetAttribute("Animal") or model:GetAttribute("AttackType") or model.Name)
        :lower():gsub("[^%w]", "")
    return name == "golemdotumulo" or name == "tombgolem" or name == "gravegolem"
end

local function castleIsBoss(model)
    local tier = model:GetAttribute("Tier")
    if typeof(tier) == "string" and tier:lower() == "boss" then return true end
    return castleIsDracula(model) or castleIsGraveGolem(model)
end

local function castleHorizontalDistance(a, b)
    local dx, dz = a.X - b.X, a.Z - b.Z
    return math.sqrt(dx * dx + dz * dz)
end

-- A MeshPart GraveGolem pode ter 10-30 studs de largura. O Humanoid pode
-- estar encostado no boss sem nunca chegar a 8 studs de seu CENTRO.
-- Mede o afastamento ate a superficie horizontal (caixa orientada), com
-- dimensoes limitadas para nao considerar o boss proximo do outro lado do mapa.
-- Para Dracula e outros inimigos a regra anterior permanece identica.
function castleRuntime.castleDistanceToCombatTarget(rootPosition, enemy, center)
    local raw = castleHorizontalDistance(rootPosition, center)
    if not enemy or not castleIsGraveGolem(enemy) then return raw end
    local part = enemy:IsA("BasePart") and enemy
        or (enemy:IsA("Model") and enemy:FindFirstChild("GraveGolem", true))
    if not part or not part:IsA("BasePart") then return raw end
    local relative = part.CFrame:PointToObjectSpace(rootPosition)
    local halfX = math.min(part.Size.X * 0.5, 24)
    local halfZ = math.min(part.Size.Z * 0.5, 24)
    local dx = math.max(math.abs(relative.X) - halfX, 0)
    local dz = math.max(math.abs(relative.Z) - halfZ, 0)
    return math.min(raw, math.sqrt(dx * dx + dz * dz))
end

-- Ativa Noclip SOMENTE se o combate ja entrou na fase de aproximacao
-- e Attack Height e negativo. O modo manual do Player nunca e alterado.
local function castleSetTemporaryNoclip(enabled, root)
    if enabled then
        if castleTempNoclip or not root or not root.Parent then return end
        castleSafeRootCFrame = root.CFrame -- posicao conhecida antes de atravessar o solo
        castleSafeRoot = root
        castleTempNoclip = true
        castleHeightProgressY = root.Position.Y
        castleHeightProgressAt = os.clock()
        castleLastVerticalAssistAt = 0
        castleNoclipApply()
        -- Entrar em queda livre ajuda a sair do estado de corrida apoiado
        -- no solo. O servidor ainda pode bloquear o movimento subterraneo.
        pcall(function()
            local humanoid = root.Parent:FindFirstChildOfClass("Humanoid")
            if humanoid then humanoid:ChangeState(Enum.HumanoidStateType.Freefall) end
            local velocity = root.AssemblyLinearVelocity
            root.AssemblyLinearVelocity = Vector3.new(velocity.X, math.min(velocity.Y, -10), velocity.Z)
        end)
        print("[Poly Hub Castelo] Noclip temporario ATIVO: tentando descer no combate")
    else
        if not castleTempNoclip then return end
        castleTempNoclip = false
        -- Sem noclip manual, nao reabilite colisoes com o jogador enterrado.
        -- Retorna ao local seguro salvo imediatamente ANTES do combate.
        if not state.noclip then
            local character = localPlayer.Character
            local currentRoot = character and character:FindFirstChild("HumanoidRootPart")
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")
            if currentRoot and currentRoot == castleSafeRoot and currentRoot.Parent
                and humanoid and humanoid.Health > 0
                and castleSafeRootCFrame
                and currentRoot.Position.Y < castleSafeRootCFrame.Position.Y - 1 then
                local ok, err = pcall(function()
                    currentRoot.AssemblyLinearVelocity = Vector3.zero
                    currentRoot.AssemblyAngularVelocity = Vector3.zero
                    currentRoot.CFrame = castleSafeRootCFrame
                end)
                if ok then
                    print("[Poly Hub Castelo] Retorno para posicao segura antes de restaurar colisoes")
                else
                    warn("[Poly Hub Castelo] Retorno seguro falhou: " .. tostring(err))
                end
            end
            castleNoclipRestore()
        end
        castleSafeRootCFrame = nil
        castleSafeRoot = nil
        castleHeightProgressY = nil
        castleUpdateDetails()
        print("[Poly Hub Castelo] Noclip temporario OFF")
    end
    castleUpdateDetails()
end

local function castleClearVertical()
    castleHeightGoal = nil
    castleDirectChasePosition = nil
    castleRuntime.castleGolemHeightAnchorY = nil
    castleRuntime.castleGolemNearStopIssued = false
    castleRuntime.castleGolemLiftAttempted = false
    castleRuntime.castleGolemLiftTries = 0
    castleRuntime.castleGolemLiftLastAt = 0
    castleRuntime.castleGolemLiftStartingY = nil
    castleRuntime.castleDirectTakeoffAt = 0
    if castleVerticalConnection then
        castleVerticalConnection:Disconnect()
        castleVerticalConnection = nil
    end
    if castleVerticalForce then
        castleVerticalForce:Destroy()
        castleVerticalForce = nil
    end
    if castleVerticalAttachment then
        castleVerticalAttachment:Destroy()
        castleVerticalAttachment = nil
    end
    castleVerticalRoot = nil
    castleSetTemporaryNoclip(false)
end

local function castleEnsureVertical(root)
    if castleVerticalRoot == root and castleVerticalConnection then return end
    castleClearVertical()
    local attachment = create("Attachment", {Name = "PolyCastleVerticalAttachment"}, root)
    local force = create("VectorForce", {
        Name = "PolyCastleVerticalForce",
        Attachment0 = attachment,
        RelativeTo = Enum.ActuatorRelativeTo.World,
        ApplyAtCenterOfMass = true,
        Force = Vector3.zero,
    }, root)
    castleVerticalAttachment = attachment
    castleVerticalForce = force
    castleVerticalRoot = root
    -- A forca atua SOMENTE no eixo Y. Nao prende o X/Z durante combate.
    castleVerticalConnection = RunService.Heartbeat:Connect(function()
        if not state.castleFarm
            or not (state.castleHeightEnabled or state.castleHeightDirectDracula
                or state.castleCombatTeleportDracula or state.castleCombatTeleportGolem)
            or castleHeightGoal == nil or not root.Parent or root ~= castleVerticalRoot then
            force.Force = Vector3.zero
            return
        end
        local deltaY = castleHeightGoal - root.Position.Y
        local vy = root.AssemblyLinearVelocity.Y
        local correction = math.clamp(
            deltaY * CASTLE_CONFIG.verticalStiffness - vy * CASTLE_CONFIG.verticalDamping,
            -CASTLE_CONFIG.maxVerticalAcceleration,
            CASTLE_CONFIG.maxVerticalAcceleration
        )
        local mass = root.AssemblyMass
        if mass > 0 then
            -- A altura imediata aplica deslocamento horizontal suave enquanto
            -- o Dracula ainda estiver longe. MoveTo sozinho pode nao
            -- locomover um Humanoid suspenso no ar por VectorForce.
            -- A forca e limitada e so atua durante a perseguicao direta.
            local horizontalForce = Vector3.zero
            if castleDirectChasePosition
                and state.castleHeight > 0
                and ((castlePhase == "dracula" and state.castleHeightDirectDracula)
                    or (castlePhase == "golem" and state.castleHeightEnabled)) then
                local diff = Vector3.new(
                    castleDirectChasePosition.X - root.Position.X,
                    0,
                    castleDirectChasePosition.Z - root.Position.Z
                )
                local planar = Vector3.new(
                    root.AssemblyLinearVelocity.X, 0,
                    root.AssemblyLinearVelocity.Z
                )
                local desiredVelocity = Vector3.zero
                if diff.Magnitude > state.castleApproach then
                    desiredVelocity = diff.Unit * math.min(
                        CASTLE_CONFIG.directChaseMaxSpeed,
                        diff.Magnitude * CASTLE_CONFIG.directChaseGain
                    )
                end
                local accel = (desiredVelocity - planar) * CASTLE_CONFIG.directChaseVelocityGain
                if accel.Magnitude > CASTLE_CONFIG.directChaseMaxAcceleration then
                    accel = accel.Unit * CASTLE_CONFIG.directChaseMaxAcceleration
                end
                horizontalForce = accel * mass
            end
            force.Force = Vector3.new(
                horizontalForce.X,
                mass * (workspace.Gravity + correction),
                horizontalForce.Z
            )
        end

        -- Assistencia vertical pequena e limitada quando o Humanoid continua
        -- preso a superficie mesmo sem colisao. So na altura NEGATIVA e
        -- SOMENTE enquanto o boss permanece dentro da distancia de aproximacao.
        if castleTempNoclip and state.castleHeight < 0 and deltaY < -1.25 then
            local now = os.clock()
            if castleHeightProgressY == nil or math.abs(root.Position.Y - castleHeightProgressY) > 0.25 then
                castleHeightProgressY = root.Position.Y
                castleHeightProgressAt = now
            elseif now - castleHeightProgressAt >= CASTLE_CONFIG.verticalAssistStuckSeconds
                and now - castleLastVerticalAssistAt >= CASTLE_CONFIG.verticalAssistInterval then
                local enemyPosition = castleTarget and castleEnemyPosition(castleTarget)
                if enemyPosition and castleHorizontalDistance(root.Position, enemyPosition) <= state.castleApproach then
                    local step = math.min(CASTLE_CONFIG.verticalAssistStep, -deltaY)
                    -- Limita o passo: nao teleporta do outro lado do mapa.
                    -- Terreno/replicacao podem vetar movimento subterraneo.
                    -- Tentativa limitada local; nao afirma sucesso sem medir Y real.
                    pcall(function()
                        root.AssemblyLinearVelocity = Vector3.new(
                            root.AssemblyLinearVelocity.X,
                            math.min(root.AssemblyLinearVelocity.Y, -8),
                            root.AssemblyLinearVelocity.Z
                        )
                        root.CFrame = root.CFrame + Vector3.new(0, -step, 0)
                    end)
                    castleVerticalAssistCount += 1
                    castleLastVerticalAssistAt = now
                    castleHeightProgressAt = now
                    castleHeightProgressY = root.Position.Y
                    if castleVerticalAssistCount <= 3 or castleVerticalAssistCount % 10 == 0 then
                        print("[Poly Hub Castelo] Auxilio vertical -" .. tostring(step)
                            .. " studs (tentativa " .. castleVerticalAssistCount .. ")")
                    end
                end
            end
        end
    end)
end

-- A ordem visual dos slots nao e fornecida por uma API publica de Tool.
-- Preferir reconhecimento pelo nome real da ferramenta (slot 2 na imagem).
local function castleIsAppleTool(tool)
    if not tool or not tool:IsA("Tool") then return false end
    local name = string.lower(tool.Name)
    local configuredName = string.lower(state.castleAppleName or "")
    if configuredName ~= "" then
        return string.find(name, configuredName, 1, true) ~= nil
    end
    return string.find(name, "apple", 1, true) ~= nil
        or string.find(name, "maç", 1, true) ~= nil
        or string.find(name, "maca", 1, true) ~= nil
end

local function castleFindAppleTool(character)
    local backpack = localPlayer:FindFirstChildOfClass("Backpack")
    local best, bestRank = nil, -1
    for _, container in ipairs({character, backpack}) do
        if container then
            for _, obj in ipairs(container:GetChildren()) do
                if castleIsAppleTool(obj) then
                    local lower = string.lower(obj.Name)
                    local rank = (lower:find("gold", 1, true)
                        or lower:find("dourad", 1, true)) and 2 or 1
                    if rank > bestRank then
                        best, bestRank = obj, rank
                    end
                end
            end
        end
    end
    return best
end

-- TELEPORTE DE COMBATE v35 (independente do TP entre fases).
-- Usa sempre a posicao ATUAL do boss (nao checkpoints estaticos).
-- Como a experiencia pode corrigir CFrame, a confirmacao usa posicao X/Z
-- de fato alcancada, sem contar a demora para subir como rejeicao do TP.
function castleRuntime.castleCombatDistance(point, target, center)
    if not castleIsGraveGolem(target) then
        return castleHorizontalDistance(point, center)
    end
    local part = target:IsA("BasePart") and target
        or (target:IsA("Model") and target:FindFirstChild("GraveGolem", true))
    if not part or not part:IsA("BasePart") then
        return castleRuntime.castleDistanceToCombatTarget(point, target, center)
    end
    -- Para TP de combate nao limitar artificialmente a caixa a 24 studs:
    -- o Golem pode ser maior, e o TP posiciona na SUPERFICIE real dele.
    local rel = part.CFrame:PointToObjectSpace(point)
    local dx = math.max(math.abs(rel.X) - part.Size.X * 0.5, 0)
    local dz = math.max(math.abs(rel.Z) - part.Size.Z * 0.5, 0)
    return math.sqrt(dx * dx + dz * dz)
end

function castleRuntime.castleTryCombatTeleport(now, humanoid, root, target, ignoredCenter)
    local golem = castlePhase == "golem" and castleIsGraveGolem(target)
    local dracula = castlePhase == "dracula" and castleIsDracula(target)
    if not ((golem and state.castleCombatTeleportGolem)
        or (dracula and state.castleCombatTeleportDracula)) then
        return false
    end
    if not target or not target.Parent or not root or not root.Parent
        or not humanoid or humanoid.Health <= 0 then return false end

    -- A cada atualizacao pega o boss pela peca REAL observada no Debug.
    local center = castleEnemyPosition(target)
    if not center then
        castleStatus("[TP COMBATE] Boss sem posicao disponivel")
        return false
    end
    local ctx = castleRuntime.castleCombatTeleportContext
    if not ctx or ctx.target ~= target or ctx.character ~= root.Parent
        or ctx.phase ~= castlePhase then
        ctx = {
            target = target, character = root.Parent, phase = castlePhase,
            anchorY = root.Position.Y, lastAt = -math.huge, failures = 0,
            lastDest = nil, awaitingCheck = false, disabled = false,
            reportedAt = 0, heightIssueAt = nil, insideGate = false,
        }
        castleRuntime.castleCombatTeleportContext = ctx
        print(string.format('[Poly Hub Castelo][TP COMBATE] Novo alvo %s, posicao (%.1f, %.1f, %.1f)',
            dracula and 'Dracula' or 'GraveGolem', center.X, center.Y, center.Z))
    end
    if ctx.disabled then
        -- Se o servidor ja recusou o TP, manter o Dracula em WALK nesta luta.
        if dracula then
            castleRuntime.castleCombatTeleportWalkToDracula = true
        end
        return false
    end

    -- SOMENTE DRACULA: enquanto estiver fora da distancia configurada,
    -- segue pelo chao. Nao tenta TP nem aplica a sustentacao vertical.
    -- Mede apenas o plano XZ para nao bloquear por diferenca de altura.
    -- GraveGolem preserva integralmente o TP de combate da v35.
    if dracula then
        local planarRange = castleHorizontalDistance(root.Position, center)
        local maxRange = state.castleDraculaCombatTeleportRange
        if planarRange > maxRange then
            castleRuntime.castleCombatTeleportWalkToDracula = true
            if ctx.insideGate then
                print(string.format(
                    '[Poly Hub Castelo][TP DRACULA][WALK] Dracula afastou: %.1f > %d studs; seguindo pelo chao',
                    planarRange, maxRange))
            end
            ctx.insideGate = false
            -- Apos sair do raio nao tratar uma checagem antiga como TP
            -- devolvido. Conserva cooldown/falhas para evitar spam.
            ctx.awaitingCheck = false
            if castleHeightGoal ~= nil or castleVerticalConnection ~= nil then
                castleClearVertical()
            end
            return false
        end
        if not ctx.insideGate then
            ctx.insideGate = true
            print(string.format(
                '[Poly Hub Castelo][TP DRACULA][ALCANCE] %.1f <= %d studs: liberando TP de combate',
                planarRange, maxRange))
        end
    end

    local destinationXZ = nil
    if golem then
        local part = target:IsA("BasePart") and target
            or (target:IsA("Model") and target:FindFirstChild("GraveGolem", true))
        if part and part:IsA("BasePart") then
            -- Encontrar o ponto mais proximo da SUPERFICIE horizontal do
            -- monstro. Sem cortar o tamanho real da MeshPart a 24 studs.
            local relative = part.CFrame:PointToObjectSpace(root.Position)
            local hx, hz = part.Size.X * 0.5, part.Size.Z * 0.5
            local x, z = math.clamp(relative.X, -hx, hx), math.clamp(relative.Z, -hz, hz)
            local dx, dz = relative.X - x, relative.Z - z
            local nx, nz = 0, 0
            if dx * dx + dz * dz > 0.001 then
                local length = math.sqrt(dx * dx + dz * dz)
                nx, nz = dx / length, dz / length
            elseif hx - math.abs(relative.X) < hz - math.abs(relative.Z) then
                nx = relative.X >= 0 and 1 or -1
                x = nx * hx
            else
                nz = relative.Z >= 0 and 1 or -1
                z = nz * hz
            end
            local p = part.CFrame:PointToWorldSpace(Vector3.new(
                x + nx * CASTLE_CONFIG.combatTeleportOffset,
                0,
                z + nz * CASTLE_CONFIG.combatTeleportOffset
            ))
            destinationXZ = Vector3.new(p.X, 0, p.Z)
        end
    end
    if not destinationXZ then
        local diff = Vector3.new(root.Position.X - center.X, 0,
            root.Position.Z - center.Z)
        local direction = diff.Magnitude > 0.01 and diff.Unit or Vector3.new(1, 0, 0)
        local spacing = math.clamp(state.castleApproach * 0.6, 2.5, 5.5)
        destinationXZ = Vector3.new(center.X, 0, center.Z) + direction * spacing
    end
    local desiredY = math.max(center.Y, ctx.anchorY) + state.castleHeight
    local destination = Vector3.new(destinationXZ.X, desiredY, destinationXZ.Z)

    if ctx.awaitingCheck and now - ctx.lastAt >= CASTLE_CONFIG.combatTeleportBounceCheck then
        ctx.awaitingCheck = false
        local planarError = castleHorizontalDistance(root.Position, ctx.lastDest)
        local yError = math.abs(root.Position.Y - ctx.lastDest.Y)
        -- IMPORTANTE: a v33 contava Y diferente de +8 como TP rejeitado.
        -- Mas o personagem pode demorar a subir ou cair durante a animação;
        -- isso nao prova que o servidor devolveu o teleporte X/Z.
        if planarError > math.max(state.castleApproach + 3, 11) then
            ctx.failures += 1
            warn(string.format('[Poly Hub Castelo][TP COMBATE] Alvo %s: posicao XZ devolvida (%.1f studs), %d/%d',
                castlePhase, planarError, ctx.failures, CASTLE_CONFIG.combatTeleportMaxFailures))
            if ctx.failures >= CASTLE_CONFIG.combatTeleportMaxFailures then
                ctx.disabled = true
                castleClearVertical()
                castleStatus('TP de combate rejeitado: voltando ao WALK nesta luta')
                return false
            end
        else
            ctx.failures = 0
            if yError > CASTLE_CONFIG.combatTeleportHeightTolerance then
                if not ctx.heightIssueAt then ctx.heightIssueAt = now end
                if now - ctx.reportedAt > 3 then
                    ctx.reportedAt = now
                    print(string.format('[Poly Hub Castelo][TP COMBATE][HEIGHT] Posicao XZ OK, mas Y atual %.1f / alvo %.1f',
                        root.Position.Y, destination.Y))
                end
            else
                ctx.heightIssueAt = nil
            end
        end
    end

    -- Preserva o controlador de altura que ja funciona no hub original.
    if not castleVerticalConnection or castleVerticalRoot ~= root then
        castleEnsureVertical(root)
    end
    castleHeightGoal = desiredY
    castleDirectChasePosition = nil
    castleSetTemporaryNoclip(state.castleHeight < 0, root)

    local planarToDest = castleHorizontalDistance(root.Position, destination)
    local verticalToDest = math.abs(root.Position.Y - desiredY)
    -- No primeiro encontro, tentar TP imediatamente, mesmo que ja esteja
    -- dentro da distancia de ataque: o usuario selecionou TP, nao WALK.
    local firstAttempt = ctx.lastAt == -math.huge
    local needsReposition = firstAttempt
        or planarToDest > CASTLE_CONFIG.combatTeleportFollowRange
        or verticalToDest > CASTLE_CONFIG.combatTeleportHeightTolerance
    if needsReposition and now - ctx.lastAt >= CASTLE_CONFIG.combatTeleportInterval then
        ctx.lastAt = now
        ctx.lastDest = destination
        ctx.awaitingCheck = true
        local success, errorMessage = pcall(function()
            local look = Vector3.new(center.X, destination.Y, center.Z)
            -- Mesmo mecanismo basico de root.CFrame usado no TP entre fases
            -- da v32 (que o usuario confirmou funcionar no jogo).
            root.CFrame = (look - destination).Magnitude > 0.5
                and CFrame.lookAt(destination, look) or CFrame.new(destination)
            -- Nao zerar AssemblyLinearVelocity: isso nao existia no TP v32.
        end)
        if success then
            local reached = root.Position
            print(string.format(
                '[Poly Hub Castelo][TP COMBATE] %s | boss=(%.1f,%.1f,%.1f) | destino=(%.1f,%.1f,%.1f) | atual=(%.1f,%.1f,%.1f) | Height=%+g',
                castlePhase, center.X, center.Y, center.Z,
                destination.X, destination.Y, destination.Z,
                reached.X, reached.Y, reached.Z, state.castleHeight))
        else
            ctx.awaitingCheck = false
            warn('[Poly Hub Castelo][TP COMBATE] Erro ao definir CFrame: ' .. tostring(errorMessage))
        end
    end
    return true
end

local function castleCombatTool(humanoid)
    -- O Roblox nao expõe a ordem visual da hotbar de modo publico e confiavel.
    -- Preferimos a primeira Tool nao-GhostNet ja equipada; depois a primeira
    -- Tool nao-GhostNet disponivel na Backpack (slot 1 presumido).
    local character = localPlayer.Character
    if not character then return nil end
    for _, object in ipairs(character:GetChildren()) do
        if object:IsA("Tool") and object.Name ~= GHOST_CONFIG.tool
            and not castleIsAppleTool(object) then
            return object
        end
    end
    local backpack = localPlayer:FindFirstChildOfClass("Backpack")
    if not backpack then return nil end
    local candidate
    for _, object in ipairs(backpack:GetChildren()) do
        if object:IsA("Tool") and object.Name ~= GHOST_CONFIG.tool
            and not castleIsAppleTool(object) then
            candidate = object
            break
        end
    end
    if not candidate then return nil end
    local ok = pcall(function() humanoid:EquipTool(candidate) end)
    if not ok then return nil end
    return candidate.Parent == character and candidate or nil
end

-- O Auto Maca usa APENAS as APIs de Tool padrao (equipar + ativar).
-- Nao simula cliques do mouse do Windows e nao altera a logica do Q.
-- Retorna true quando ocupou este ciclo com uma tentativa de uso.
local function castleTryAutoApple(now, humanoid)
    if not state.castleAutoApple or not state.castleFarm then return false end
    if castlePhase ~= "dracula" and castlePhase ~= "golem" then return false end
    if castleRuntime.castleAppleUsing or now < castleRuntime.castleAppleNextAt then return false end
    if not humanoid or humanoid.Health <= 0 or humanoid.MaxHealth <= 0 then return false end
    local percent = humanoid.Health / humanoid.MaxHealth * 100
    if percent > state.castleAppleThreshold then return false end

    local character = localPlayer.Character
    if not character or humanoid.Parent ~= character then return false end
    local apple = castleFindAppleTool(character)
    if not apple then
        castleRuntime.castleAppleNextAt = now + CASTLE_CONFIG.appleNotFoundInterval
        castleRefreshAppleStatus("maca nao encontrada na mochila")
        if now - castleRuntime.castleAppleLastMissingLogAt > 15 then
            castleRuntime.castleAppleLastMissingLogAt = now
            warn("[Poly Hub Castelo][MACA] Nenhuma Tool de maca/apple detectada no Character/Backpack. "
                .. "Se ela estiver no slot 2 mas tiver outro nome, configure Nome da Maca na aba Castelo.")
        end
        return false
    end
    if not apple.Enabled then
        castleRuntime.castleAppleNextAt = now + 2
        castleRefreshAppleStatus("Tool desabilitada, aguardando")
        return false
    end

    castleRuntime.castleAppleUsing = true
    castleRuntime.castleAppleNextAt = now + CASTLE_CONFIG.appleMinInterval
    castleRuntime.castleAppleLastAttemptAt = now
    castleRuntime.castleAppleAttempts += 1
    local beforeHealth = humanoid.Health
    local previouslyEquipped = character:FindFirstChildOfClass("Tool")
    if previouslyEquipped and castleIsAppleTool(previouslyEquipped) then
        previouslyEquipped = nil
    end

    -- Selecionar/equipar a maca. Se o jogo nao a expor como Tool,
    -- nao pressionar o slot 2 cegamente nem usar controles extras.
    local equipped = false
    local okEquip, equipErr = pcall(function()
        humanoid:EquipTool(apple)
        equipped = apple.Parent == character
    end)
    if not okEquip or not equipped then
        castleRuntime.castleAppleUsing = false
        castleRefreshAppleStatus("falha ao equipar")
        warn("[Poly Hub Castelo][MACA] Falha ao equipar: " .. tostring(equipErr))
        return false
    end

    -- Um pequeno tempo para a ferramenta equipar antes de ser ativada.
    task.wait(0.15)
    local eligible = state.castleFarm and state.castleAutoApple
        and localPlayer.Character == character
        and humanoid.Parent == character and humanoid.Health > 0
        and apple.Parent == character
    local okUse, useErr = false, "personagem/Tool mudou durante o uso"
    if eligible and apple.Enabled then
        okUse, useErr = pcall(function() apple:Activate() end)
    end
    if okUse then
        print(string.format(
            "[Poly Hub Castelo][MACA] Tool:Activate enviada: %s | HP %.1f%% <= limite %d%% | tentativa %d",
            apple.Name, percent, state.castleAppleThreshold, castleRuntime.castleAppleAttempts))
        castleRefreshAppleStatus("uso enviado; conferindo HP")
    else
        castleRefreshAppleStatus("nao foi possivel ativar")
        warn("[Poly Hub Castelo][MACA] Ativacao nao executada: " .. tostring(useErr))
    end
    -- Evitar que o ataque volte a equipar a espada ANTES da ativacao.
    task.wait(0.22)
    if state.castleFarm and localPlayer.Character == character
        and humanoid.Parent == character and humanoid.Health > 0 then
        if previouslyEquipped and previouslyEquipped.Parent then
            pcall(function() humanoid:EquipTool(previouslyEquipped) end)
        else
            -- Sem arma anterior equipada: deixa o combate v20 escolher a espada.
            castleCombatTool(humanoid)
        end
    end
    castleRuntime.castleAppleUsing = false

    if okUse then
        local thisAttempt = castleRuntime.castleAppleLastAttemptAt
        task.delay(0.55, function()
            if castleRuntime.castleAppleLastAttemptAt ~= thisAttempt
                or localPlayer.Character ~= character or humanoid.Parent ~= character then return end
            if humanoid.Health > beforeHealth then
                castleRefreshAppleStatus("HP subiu apos o uso")
                print(string.format("[Poly Hub Castelo][MACA] HP mudou: %.0f -> %.0f",
                    beforeHealth, humanoid.Health))
            else
                castleRefreshAppleStatus("uso enviado; cura nao confirmada")
                print("[Poly Hub Castelo][MACA] HP ainda nao subiu. Tool ativada nao comprova consumo no servidor.")
            end
        end)
    end
    return true
end

local function castleCandidate(rootPos)
    local folder = castleEnemyFolder()
    if not folder then return nil end
    local best, bestRank, bestDistance = nil, math.huge, math.huge
    for _, model in ipairs(folder:GetChildren()) do
        if (model:IsA("Model") or model:IsA("BasePart")) and model.Parent == folder then
            local pos = castleEnemyPosition(model)
            local hp = castleEnemyHealth(model)
            local run = model:GetAttribute("DungeonRun")
            -- Nao fixe a partida usando um mob comum: isso excluia boss da
            -- varredura quando seu @DungeonRun nao era o mesmo.
            local sameRun = castleRunId == nil or run == nil
                or tostring(run) == castleRunId or castleIsBoss(model)
            if pos and sameRun and (hp == nil or hp > 0) then
                local dist = castleHorizontalDistance(rootPos, pos)
                -- Dracula costuma ficar longe do altar apos o respawn.
                -- O alcance proprio e editavel no Hub (padrao: 250).
                -- Nao altera a distancia de ataque nem a busca do GraveGolem.
                local detectionRange = CASTLE_CONFIG.maxAcquireDistance
                if castlePhase == "dracula" and castleIsDracula(model) then
                    detectionRange = state.castleDraculaDetectionRange
                elseif castlePhase == "golem" and castleIsGraveGolem(model) then
                    detectionRange = CASTLE_CONFIG.golemRecoveryDistance
                end
                if dist <= detectionRange then
                    local animal = castleEnemyType(model)
                    local boss = castleIsBoss(model)
                    local rank
                    if castlePhase == "golem" then
                        -- Boss final confirmado: @Animal = GraveGolem.
                        rank = castleIsGraveGolem(model) and 0 or nil
                    elseif castlePhase == "dracula" then
                        if castleIsGraveGolem(model) then
                            rank = nil -- Nunca perseguir boss final antes do Dracula.
                        elseif castleIsDracula(model) then
                            rank = 0
                        elseif boss then
                            rank = 2
                        else
                            rank = 1
                        end
                    end
                    if rank and (rank < bestRank or (rank == bestRank and dist < bestDistance)) then
                        best, bestRank, bestDistance = model, rank, dist
                    end
                end
            end
        end
    end
    return best
end

-- O boost so atua DURANTE os deslocamentos de transicao. Ao concluir,
-- morrer ou desligar, restaura a velocidade que havia no inicio da rota.
-- Se outra configuracao alterou WalkSpeed durante o caminho, nao sobrescreve.
function castleRuntime.castleRestoreRouteSpeed()
    local humanoid = castleRuntime.castleRouteHumanoid
    local original = castleRuntime.castleRouteOriginalSpeed
    local applied = castleRuntime.castleRouteAppliedSpeed
    if humanoid and humanoid.Parent and original and applied then
        local current = humanoid.WalkSpeed
        if math.abs(current - applied) <= 0.15 then
            humanoid.WalkSpeed = state.speedEnabled and state.speedValue
                or (original > 0 and original or experienceSpeed)
            print(string.format('[Poly Hub Castelo][ROTA] Velocidade restaurada: %.1f', humanoid.WalkSpeed))
        end
    end
    castleRuntime.castleRouteHumanoid = nil
    castleRuntime.castleRouteOriginalSpeed = nil
    castleRuntime.castleRouteAppliedSpeed = nil
end

function castleRuntime.castleApplyRouteSpeed(humanoid)
    if not humanoid or not humanoid.Parent or not state.castleRouteBoost then return end
    if castleRuntime.castleRouteHumanoid ~= humanoid then
        castleRuntime.castleRestoreRouteSpeed()
        castleRuntime.castleRouteHumanoid = humanoid
        castleRuntime.castleRouteOriginalSpeed = humanoid.WalkSpeed
    end
    local desired = state.castleRouteSpeed
    if humanoid.WalkSpeed < desired then
        local ok = pcall(function() humanoid.WalkSpeed = desired end)
        if ok then
            castleRuntime.castleRouteAppliedSpeed = desired
        end
    end
end

-- O estado da rota e efemero e nunca reaproveitado apos uma nova partida.
local function castleResetRoute()
    castleRuntime.castleRestoreRouteSpeed()
    castleRouteWaypoints = nil
    castleRouteIndex = 1
    castleRouteCalculatedAt = 0
    castleRouteLastProgressAt = 0
    castleRouteLastPos = nil
    castleLastRouteMoveAt = 0
    castleRuntime.castleRouteMoveTarget = nil
    castleRuntime.castleRouteFailures = 0
    castleRuntime.castleRouteStuckRecoveries = 0
end

function castleRuntime.castleDisconnectDraculaHealth()
    if castleRuntime.castleDraculaHealthConnection then
        castleRuntime.castleDraculaHealthConnection:Disconnect()
        castleRuntime.castleDraculaHealthConnection = nil
    end
    if castleRuntime.castleDraculaHumanoidConnection then
        castleRuntime.castleDraculaHumanoidConnection:Disconnect()
        castleRuntime.castleDraculaHumanoidConnection = nil
    end
    castleRuntime.castleDraculaWatchedModel = nil
end

local function castleResetBossStage()
    castleRuntime.castleAppleUsing = false
    castleRuntime.castleAppleNextAt = 0
    castleRuntime.castleAppleLastMessage = "aguardando"
    castleRefreshAppleStatus()
    castleRuntime.castleDisconnectDraculaHealth()
    state.castleDraculaDefeated = false
    castleDraculaSeen = false
    castleDraculaTookDamage = false
    castleDraculaLastHealth = nil
    castleDraculaPositiveModel = nil
    castleRuntime.castleDraculaMaxHealth = nil
    castleRuntime.castleDraculaRetreatModel = nil
    castleRuntime.castleDraculaRetreatArmedAt = 0
    castleRuntime.castleDraculaRetreatLastRatio = nil
    castleRuntime.castleDraculaRetreatGoneSince = nil
    castleRuntime.castleDraculaRetreatCameraSince = nil
    castleRuntime.castleDraculaCameraWasScriptableOnArm = false
    castleDraculaMissingSince = nil
    castleDraculaLastPosition = nil
    castleDraculaAttacks = 0
    castleDraculaObservations = 0
    castleRuntime.castleGolemSeen = false
    castleRuntime.castleGolemTookDamage = false
    castleRuntime.castleGolemLastHealth = nil
    castleRuntime.castleGolemMissingSince = nil
    castleRuntime.castleGolemAttacks = 0
    castleRuntime.castleGolemLastDiagnosticAt = -math.huge
    castleRuntime.castleGolemRouteRecoveryCount = 0
    castleRuntime.castleGolemRecoverAfterRespawn = false
    castleRuntime.castleGolemResumeAt = 0
    castleRuntime.castleLastBossSignature = nil
    castleRuntime.castleLastScannedUI = 0
    castleRuntime.castleUI = {loot = false, replay = false, starting = false,
        defeated = false, retry = false, lootPoint = nil, replayPoint = nil, retryPoint = nil}
    castleRuntime.castleDefeatObserved = false
    castleRuntime.castleDefeatObservedAt = 0
    castleRuntime.castleDefeatCharacter = nil
    castleRuntime.castleLastDefeatDiagnostic = 0
    castleRuntime.castleLastUITap = 0
    castleRuntime.castleLastUIError = nil
    castleRuntime.castleReplayRequestedAt = 0
    castleRuntime.castleReplaySawStarting = false
    castleRuntime.castleReplayScreenWasVisible = false
    castleRuntime.castleCameraEverNonScriptable = false
    castleRuntime.castleCutsceneCameraSince = 0
    castleRuntime.castleFinishConfirmedAt = 0
    castleRunId = nil
    castlePhase = "dracula"
    castlePhaseStartedAt = os.clock()
    castleCutsceneReason = ""
    castleRuntime.castleTeleportContext = nil
    castleRuntime.castleCombatTeleportContext = nil
    castleResetRoute()
    castleTarget = nil
    castleClearVertical()
    castleUpdateDetails()
end

-- v23: retoma apenas os ESTADOS apos uma vida nova. Nao muda velocidades,
-- gravidade, rota, WalkSpeed, movimentacao nem o mecanismo da tecla Q.
-- Importante: aguardamos o novo Humanoid estar vivo e a tela Derrotado
-- desaparecer; CharacterAdded sozinho NAO significa nova corrida pronta.
local function castleResetForNewLife(character, humanoid, reason)
    if not state.castleFarm or not character or localPlayer.Character ~= character
        or not humanoid or not humanoid.Parent or humanoid.Health <= 0 then
        return false
    end
    -- MORTE DO JOGADOR NA FASE 3 NAO MATA NEM REINICIA O BOSS.
    -- Na v28 castleResetBossStage() SEMPRE voltava a 'dracula', mesmo
    -- com GraveGolem vivo. Na mesma corrida, conservar a fase atual.
    local wasGolem = castlePhase == "golem"
    if wasGolem then
        castleRuntime.castleTeleportContext = nil
        castleRuntime.castleCombatTeleportContext = nil
        castleTarget = nil
        castleClearVertical() -- remove attachments e forcas do Character antigo
        castleResetRoute() -- restaura velocidade do movimento anterior
        castleRuntime.castleAppleUsing = false
        castleRuntime.castleAppleNextAt = 0
        castleRuntime.castleGolemLastHealth = nil
        castleRuntime.castleGolemMissingSince = nil
        castleRuntime.castleGolemTookDamage = false
        castleRuntime.castleGolemAttacks = 0
        castleRuntime.castleGolemSeen = false -- nova evidencia da fase atual
        castleRuntime.castleGolemRecoverAfterRespawn = true
        castleRuntime.castleGolemResumeAt = os.clock()
        castleRuntime.castleGolemLastDiagnosticAt = -math.huge
        castleRuntime.castleDefeatObserved = false
        castleRuntime.castleDefeatObservedAt = 0
        castleRuntime.castleDefeatCharacter = nil
        castleRuntime.castleLastUITap = 0
        castleRuntime.castleLastUIError = nil
        castleRuntime.castleUI = {loot = false, replay = false, starting = false,
            defeated = false, retry = false, lootPoint = nil, replayPoint = nil, retryPoint = nil}
        castlePhaseStartedAt = os.clock()
        castleUpdateDetails()
    else
        castleResetBossStage() -- nova vida na fase do Dracula: comportamento v28
    end
    -- Um Humanoid novo precisa reequipar a espada antes de usar Q.
    -- Nao dispara tecla imediatamente ao respawn nem duplica comando.
    castleRuntime.castleQToolRef = nil
    castleRuntime.castleQToolReadyAt = 0
    castleRuntime.castleQLastObservation = 'nova vida: aguardando espada/alcance'
    castleRuntime.castleBoundCharacter = character
    castleRuntime.castleBoundHumanoid = humanoid
    castleRuntime.castlePendingRespawnCharacter = nil
    castleRuntime.castlePendingRespawnHumanoid = nil
    castleRuntime.castlePendingRespawnAt = 0
    castleRuntime.castleRespawnResetCount += 1
    print(string.format(
        '[Poly Hub Castelo][CICLO] Respawn: %s | fase=%s | resets=%d | personagem=%s',
        tostring(reason), castlePhase, castleRuntime.castleRespawnResetCount, tostring(character.Name)))
    if castlePhase == "golem" then
        castleStatus('Nova vida: mantendo 3/3 e procurando GraveGolem')
        print('[Poly Hub Castelo][GOLEM][RESPAWN] Fase 3 preservada; procurando boss sem voltar ao Dracula')
    else
        castleStatus('Nova vida detectada: buscando Dracula sem desligar a caca')
    end
    return true
end

-- Guarda a porcentagem de vida do MESMO Count Dracula. O limiar (~55%)
-- nao e derrota, mas um aviso para observar sua fuga e a quebra da janela.
-- Dois sinais juntos: HP de boss observado cair de >55% para <=55%
-- MAIS a saida do modelo da arena OU a cutscene iniciada depois da queda.
function castleRuntime.castleTrackDraculaHP(dracula, reason)
    if not state.castleFarm or castlePhase ~= "dracula"
        or not dracula or not castleIsDracula(dracula) then return end
    local hp = castleEnemyHealth(dracula)
    local maxHp = castleRuntime.castleEnemyMaxHealth(dracula)
    if hp == nil or maxHp == nil then
        if os.clock() - castleRuntime.castleLastEvidenceLog >= 6 then
            castleRuntime.castleLastEvidenceLog = os.clock()
            warn("[Poly Hub Castelo][FUGA] Atributos Health/MaxHealth ausentes no Dracula; "
                .. "nao vou supor que ele fugiu")
        end
        return
    end
    local fraction = math.clamp(hp / maxHp, 0, 1)
    local old = castleDraculaLastHealth
    castleDraculaLastHealth = hp
    castleRuntime.castleDraculaMaxHealth = maxHp
    castleRuntime.castleDraculaRetreatLastRatio = fraction
    if old and hp < old then castleDraculaTookDamage = true end
    local threshold = CASTLE_CONFIG.draculaRetreatArmFraction
    if fraction > threshold then
        -- So usar baseline real do mesmo modelo. Nao armar com HP de
        -- um Dracula de outra instancia/partida que apareceu com 0.
        castleDraculaPositiveModel = dracula
    end
    if castleDraculaPositiveModel == dracula
        and castleRuntime.castleDraculaRetreatModel == nil
        and fraction <= threshold and castleDraculaTookDamage then
        castleRuntime.castleDraculaRetreatModel = dracula
        castleRuntime.castleDraculaRetreatArmedAt = os.clock()
        castleRuntime.castleDraculaRetreatGoneSince = nil
        castleRuntime.castleDraculaRetreatCameraSince = nil
        local cam = workspace.CurrentCamera
        castleRuntime.castleDraculaCameraWasScriptableOnArm = cam ~= nil
            and cam.CameraType == Enum.CameraType.Scriptable
        print(string.format("[Poly Hub Castelo][FUGA ARMADA] HP Dracula %.0f/%.0f (%.1f%%) | %s",
            hp, maxHp, fraction * 100, tostring(reason)))
        castleStatus(string.format("Dracula HP %.1f%%: esperando fuga e vidro quebrar", fraction * 100))
    end
end

-- So executado DEPOIS de a fuga estar armada. Nunca avanca por mero
-- HP=55%%, camera Scriptable anterior, ausencia de boss sem dano,
-- ou GraveGolem que ja estivesse visivel em outro ponto da arena.
local function castleBeginDraculaTransition(reason)
    if castlePhase ~= "dracula" or not state.castleFarm then return false end
    if not castleRuntime.castleDraculaRetreatModel or castleRuntime.castleDraculaRetreatArmedAt <= 0 then return false end
    local playerCharacter = localPlayer.Character
    local root = playerCharacter and playerCharacter:FindFirstChild("HumanoidRootPart")
    if not root then return false end
    local folder = castleEnemyFolder()
    -- Exigir que o Drácula monitorado NAO continue lutando na arena.
    -- No caso da camera iniciar a cutscene, o boss pode ainda constar
    -- em Aggressors por poucos frames, mas a camera deve TER MUDADO
    -- depois de o HP cruzar o limiar.
    local noLongerInArena = not folder
        or castleRuntime.castleDraculaRetreatModel.Parent ~= folder
    local cam = workspace.CurrentCamera
    local newCutscene = castleRuntime.castleDraculaRetreatCameraSince ~= nil
        and os.clock() - castleRuntime.castleDraculaRetreatCameraSince >= CASTLE_CONFIG.draculaRetreatCutsceneSeconds
    if not noLongerInArena and not newCutscene then return false end
    local dist = castleDraculaLastPosition
        and castleHorizontalDistance(root.Position, castleDraculaLastPosition) or math.huge
    -- Validar que a transicao se refere ao boss nesta area, nao a um
    -- modelo distante replicado por engano.
    if dist > CASTLE_CONFIG.draculaObserveRadius then return false end

    state.castleDraculaDefeated = true -- compatibilidade: agora significa que Dracula fugiu
    castleRuntime.castleDisconnectDraculaHealth()
    castleTarget = nil
    castleClearVertical()
    castlePhase = "cutscene"
    castlePhaseStartedAt = os.clock()
    castleRuntime.castleTeleportContext = nil
    castleCutsceneReason = reason
    castleResetRoute()
    castleUpdateDetails()
    castleStatus("Dracula FUGIU. Aguardando ~5s para vidro quebrar")
    print("[Poly Hub Castelo][FUGA CONFIRMADA] " .. tostring(reason)
        .. " | HP final=" .. tostring(castleDraculaLastHealth)
        .. "/" .. tostring(castleRuntime.castleDraculaMaxHealth)
        .. " | nao confundir com morte")
    return true
end

function castleRuntime.castleWatchDraculaHealth(dracula)
    if not dracula or not castleIsDracula(dracula)
        or castlePhase ~= "dracula" or not state.castleFarm then return end
    local currentRoot = localPlayer.Character
        and localPlayer.Character:FindFirstChild("HumanoidRootPart")
    local pos = castleEnemyPosition(dracula)
    if not currentRoot or not pos or
        castleHorizontalDistance(currentRoot.Position, pos) > CASTLE_CONFIG.draculaObserveRadius then
        return
    end
    if castleRuntime.castleDraculaWatchedModel == dracula then return end
    -- Nao trocar de Dracula e perder a evidencia de fuga ja armada.
    if castleRuntime.castleDraculaRetreatModel and castleRuntime.castleDraculaRetreatArmedAt > 0 then return end
    castleRuntime.castleDisconnectDraculaHealth()
    castleRuntime.castleDraculaWatchedModel = dracula
    castleDraculaSeen = true
    castleDraculaLastHealth = nil
    castleRuntime.castleDraculaMaxHealth = nil
    castleDraculaPositiveModel = nil
    castleDraculaTookDamage = false
    castleRuntime.castleDraculaRetreatModel = nil
    castleRuntime.castleDraculaRetreatArmedAt = 0
    castleRuntime.castleDraculaRetreatGoneSince = nil
    castleRuntime.castleDraculaRetreatCameraSince = nil
    local function onHealthChanged()
        if state.castleFarm and castlePhase == "dracula"
            and castleRuntime.castleDraculaWatchedModel == dracula then
            castleRuntime.castleTrackDraculaHP(dracula, "Health mudou")
        end
    end
    castleRuntime.castleDraculaHealthConnection = dracula:GetAttributeChangedSignal("Health"):Connect(onHealthChanged)
    local humanoid = dracula:FindFirstChildOfClass("Humanoid")
    if humanoid then
        castleRuntime.castleDraculaHumanoidConnection = humanoid.HealthChanged:Connect(onHealthChanged)
    end
    onHealthChanged()
    print("[Poly Hub Castelo][HP] Dracula monitorado: " .. dracula.Name
        .. " | HP inicial=" .. tostring(castleDraculaLastHealth)
        .. "/" .. tostring(castleRuntime.castleDraculaMaxHealth))
end

function castleRuntime.castleCheckDraculaEscape(now, folder, root)
    if castlePhase ~= "dracula"
        or castleRuntime.castleDraculaRetreatArmedAt <= 0
        or not castleRuntime.castleDraculaRetreatModel then return end
    local watched = castleRuntime.castleDraculaRetreatModel
    local stillInArena = folder and watched.Parent == folder
    local hp = castleEnemyHealth(watched)
    local percentage = castleRuntime.castleDraculaRetreatLastRatio
        and castleRuntime.castleDraculaRetreatLastRatio * 100 or -1
    if stillInArena then
        castleRuntime.castleDraculaRetreatGoneSince = nil
    else
        castleRuntime.castleDraculaRetreatGoneSince = castleRuntime.castleDraculaRetreatGoneSince or now
    end

    -- A camera Scriptable so e prova se ERA NORMAL na hora de armar,
    -- e se mudou para Scriptable depois que o HP caiu abaixo do limiar.
    local cam = workspace.CurrentCamera
    local inNewScene = cam and cam.CameraType == Enum.CameraType.Scriptable
        and not castleRuntime.castleDraculaCameraWasScriptableOnArm
    if inNewScene then
        castleRuntime.castleDraculaRetreatCameraSince = castleRuntime.castleDraculaRetreatCameraSince or now
    else
        castleRuntime.castleDraculaRetreatCameraSince = nil
    end

    local goneLongEnough = castleRuntime.castleDraculaRetreatGoneSince ~= nil
        and now - castleRuntime.castleDraculaRetreatGoneSince >= CASTLE_CONFIG.draculaRetreatGoneSeconds
    local newSceneLongEnough = castleRuntime.castleDraculaRetreatCameraSince ~= nil
        and now - castleRuntime.castleDraculaRetreatCameraSince >= CASTLE_CONFIG.draculaRetreatCutsceneSeconds
    if goneLongEnough then
        castleBeginDraculaTransition("Dracula saiu de Aggressors APOS chegar a ~50%")
    elseif newSceneLongEnough then
        castleBeginDraculaTransition("Cutscene nova APOS HP ~50%")
    elseif os.clock() - castleRuntime.castleLastEvidenceLog > 3 then
        castleRuntime.castleLastEvidenceLog = os.clock()
        print(string.format("[Poly Hub Castelo][FUGA ESPERANDO] HP %.1f%% | noMapa=%s | sumiu=%.1fs | cameraNova=%s",
            percentage, tostring(stillInArena),
            castleRuntime.castleDraculaRetreatGoneSince and (now-castleRuntime.castleDraculaRetreatGoneSince) or 0,
            tostring(inNewScene)))
        castleStatus("HP chegou ao limite; esperando Dracula fugir/vidro quebrar")
    end
end

-- Inicia a transicao do boss final mesmo que a Tool tenha atacado outro
-- inimigo no mesmo instante em que o modelo do Golem foi removido.
function castleRuntime.castleBeginGolemTransition(reason)
    if castlePhase ~= "golem" then return end
    castleTarget = nil
    castleClearVertical()
    castleResetRoute()
    castlePhaseStartedAt = os.clock()
    castleRuntime.castleFinishConfirmedAt = castlePhaseStartedAt
    castlePhase = "finish_route"
    castleRuntime.castleTeleportContext = nil
    castleUpdateDetails()
    castleStatus("GraveGolem derrotado: indo a saida fixa")
    print("[Poly Hub Castelo] GRAVEGOLEM DERROTADO: " .. tostring(reason))
end

-- Atualiza do cliente as evidencias das telas finais. Nao le as janelas do
-- Poly Hub, apenas as GUIs do jogo. Nao executa qualquer evento remoto.
function castleRuntime.castleVisibleGUI(obj)
    local current = obj
    while current and current ~= playerGui do
        if current:IsA("GuiObject") and not current.Visible then return false end
        if current:IsA("LayerCollector") and not current.Enabled then return false end
        if current == screenGui then return false end
        current = current.Parent
    end
    return true
end

-- O texto "Corra novamente" normalmente e filho de um botao visual maior.
-- Clicar no centro do TextLabel causava desvios verticais ou alvos errados.
function castleRuntime.castleGetClickableParent(obj)
    local node = obj
    while node and node ~= playerGui do
        if node:IsA("GuiButton") and castleRuntime.castleVisibleGUI(node) then
            return node
        end
        node = node.Parent
    end
    return nil
end

function castleRuntime.castleReadUI(now)
    if now - castleRuntime.castleLastScannedUI < CASTLE_CONFIG.uiCheckInterval then return castleRuntime.castleUI end
    castleRuntime.castleLastScannedUI = now
    local seen = {loot = false, replay = false, starting = false,
        defeated = false, retry = false,
        lootPoint = nil, replayPoint = nil, retryPoint = nil}
    for _, obj in ipairs(playerGui:GetDescendants()) do
        if (obj:IsA("TextLabel") or obj:IsA("TextButton")) and castleRuntime.castleVisibleGUI(obj) then
            local textValue = tostring(obj.Text or ""):lower()
            if textValue:find("novo saque", 1, true)
                or textValue:find("clique em qualquer", 1, true)
                or textValue:find("click anywhere", 1, true) then
                seen.loot = true
                seen.lootPoint = seen.lootPoint or obj
            end
            -- Tela de morte do jogador nao e igual ao fim bem-sucedido.
            -- Nela o jogo mostra "Derrotado" e o botao "Tente novamente".
            if textValue:find("derrotado", 1, true)
                or textValue:find("defeated", 1, true) then
                seen.defeated = true
            end
            if textValue:find("tente novamente", 1, true)
                or textValue:find("try again", 1, true) then
                local clickable = castleRuntime.castleGetClickableParent(obj)
                if clickable or not seen.retryPoint then
                    seen.retry = true
                    seen.retryPoint = clickable or obj
                end
            end
            if textValue:find("corra novamente", 1, true)
                or textValue:find("run again", 1, true) then
                local clickable = castleRuntime.castleGetClickableParent(obj)
                -- Se varios textos combinam, preferir o TextButton ou
                -- ImageButton real, nao uma legenda explicativa solta.
                if clickable or not seen.replayPoint then
                    seen.replay = true
                    seen.replayPoint = clickable or obj
                end
            end
            if textValue:find("próxima corrida", 1, true)
                or textValue:find("proxima corrida", 1, true)
                or textValue:find("começando", 1, true)
                or textValue:find("comecando", 1, true)
                or textValue:find("starting next", 1, true) then
                seen.starting = true
            end
        end
    end
    castleRuntime.castleUI = seen
    if seen.replay then castleRuntime.castleReplayScreenWasVisible = true end
    return seen
end

-- Alguns ambientes Luau nao permitem injetar clique de outro script.
-- Tenta apenas se a API existir; caso nao exista, pede clique manual.
-- Um clique nao prova que a acao foi recebida: verificamos a tela depois.
function castleRuntime.castleClickUI(target)
    -- PROTECAO: se o alvo nao foi encontrado, NAO clique no centro da tela.
    if not target or not target.Parent or not target:IsA("GuiObject")
        or not castleRuntime.castleVisibleGUI(target) then
        return false, "Botao nao localizado/visivel (sem clique cego)"
    end
    if target.AbsoluteSize.X < 8 or target.AbsoluteSize.Y < 8 then
        return false, "Area do botao muito pequena"
    end
    local center = target.AbsolutePosition + target.AbsoluteSize * 0.5
    -- AbsolutePosition esta no espaco de GUI. A entrada de mouse usa
    -- coordenadas fisicas de tela; sem inset o clique pode ficar ACIMA.
    local inset = game:GetService("GuiService"):GetGuiInset()
    local screenPoint = Vector2.new(math.floor(center.X + inset.X + 0.5),
        math.floor(center.Y + inset.Y + 0.5))
    local camera = workspace.CurrentCamera
    if camera then
        local view = camera.ViewportSize
        if screenPoint.X < 0 or screenPoint.Y < 0
            or screenPoint.X > view.X or screenPoint.Y > view.Y then
            return false, "Centro do botao fora da tela apos GuiInset"
        end
    end
    local ok, err = pcall(function()
        local service = game:GetService("VirtualInputManager")
        service:SendMouseMoveEvent(screenPoint.X, screenPoint.Y, game)
        service:SendMouseButtonEvent(screenPoint.X, screenPoint.Y, 0, true, game, 0)
        task.wait(0.07) -- clique completo: press/release dentro do botao
        service:SendMouseButtonEvent(screenPoint.X, screenPoint.Y, 0, false, game, 0)
    end)
    if ok then
        print(string.format("[Poly Hub Castelo][UI] Clique em %s | GUI=(%d,%d), inset=(%d,%d), tela=(%d,%d)",
            target:GetFullName(), math.floor(center.X), math.floor(center.Y),
            math.floor(inset.X), math.floor(inset.Y), screenPoint.X, screenPoint.Y))
    end
    return ok, ok and nil or tostring(err)
end

function castleRuntime.castleTryUIClick(now, target, kind)
    if now - castleRuntime.castleLastUITap < CASTLE_CONFIG.uiClickRetrySeconds then return end
    castleRuntime.castleLastUITap = now
    local ok, err = castleRuntime.castleClickUI(target)
    if ok then
        print("[Poly Hub Castelo] Clique enviado (aguardando confirmacao da tela): " .. kind)
        if kind == "Corra novamente" then
            castleRuntime.castleReplayRequestedAt = now
        elseif kind == "Tente novamente" then
            castleRuntime.castleDefeatObserved = true
            print("[Poly Hub Castelo][RETRY] Clique enviado em Tente novamente; aguardando tela fechar e respawn")
        end
        castleRuntime.castleLastUIError = nil
    else
        castleRuntime.castleLastUIError = tostring(err)
        castleStatus(kind .. " - clique manual necessario (simulacao bloqueada)")
        if now - castleRuntime.castleLastEvidenceLog > 7 then
            castleRuntime.castleLastEvidenceLog = now
            warn("[Poly Hub Castelo] Entrada de mouse nao disponivel: " .. tostring(err))
        end
    end
end

-- Detecta morte dos dois bosses pela varredura de Aggressors, sem
-- depender de qual alvo esta selecionado ou do @DungeonRun do mob comum.
local function castleObserveBossProgress(now, root)
    if castlePhase ~= "dracula" and castlePhase ~= "trigger"
        and castlePhase ~= "golem" then return end
    local folder = castleEnemyFolder()
    if not folder then
        -- A pasta Aggressors pode sumir por um instante durante a fuga.
        -- Continuar examinando a evidencia do Dracula monitorado.
        if castlePhase == "dracula" then
            castleRuntime.castleCheckDraculaEscape(now, nil, root)
        end
        return
    end
    local dracula, golem = nil, nil
    local draculaDist, golemDist = math.huge, math.huge
    for _, model in ipairs(folder:GetChildren()) do
        if model:IsA("Model") or model:IsA("BasePart") then
            local pos = castleEnemyPosition(model)
            if pos then
                local d = castleHorizontalDistance(root.Position, pos)
                if castleIsDracula(model) and d < draculaDist then
                    dracula, draculaDist = model, d
                elseif castleIsGraveGolem(model) and d < golemDist then
                    golem, golemDist = model, d
                end
            end
        end
    end

    if castlePhase == "dracula" then
        if dracula and draculaDist <= CASTLE_CONFIG.draculaObserveRadius then
            castleRuntime.castleWatchDraculaHealth(dracula)
            castleDraculaSeen = true
            castleDraculaObservations += 1
            castleDraculaMissingSince = nil
            castleDraculaLastPosition = castleEnemyPosition(dracula) or castleDraculaLastPosition
            if castleRuntime.castleDraculaWatchedModel == dracula then
                castleRuntime.castleTrackDraculaHP(dracula, "varredura")
            end
        elseif castleDraculaSeen then
            castleDraculaMissingSince = castleDraculaMissingSince or now
        end
        castleRuntime.castleCheckDraculaEscape(now, folder, root)
    elseif castlePhase == "trigger" then
        -- Apos a FUGA CONFIRMADA (HP ~50% + cena/desaparecimento), se
        -- o GraveGolem ja apareceu e estamos na area do checkpoint,
        -- nao insistir em chegar a um ponto de 3 studs e ficar travado.
        -- Nunca libera o golem enquanto castlePhase == "dracula".
        local checkpointDistance = castleHorizontalDistance(
            root.Position, CASTLE_CONFIG.golemTriggerPosition)
        local checkpointHeight = math.abs(
            root.Position.Y - CASTLE_CONFIG.golemTriggerPosition.Y)
        local golemHealth = golem and castleEnemyHealth(golem) or nil
        if state.castleDraculaDefeated and golem
            and (golemHealth == nil or golemHealth > 0)
            and golemDist <= CASTLE_CONFIG.maxAcquireDistance
            and checkpointDistance <= CASTLE_CONFIG.golemEngageRadius
            and checkpointHeight <= CASTLE_CONFIG.golemEngageYTolerance then
            castleTarget = nil
            castleClearVertical()
            castleResetRoute() -- restaura a velocidade usada na transicao
            castlePhase = "golem"
            castlePhaseStartedAt = now
            castleRuntime.castleGolemSeen = true
            castleRuntime.castleGolemMissingSince = nil
            castleRuntime.castleGolemRouteRecoveryCount += 1
            castleUpdateDetails()
            castleStatus("GraveGolem confirmado perto do checkpoint; iniciando combate")
            print(string.format(
                "[Poly Hub Castelo][GOLEM] Ativado por presenca real na area | dist_checkpoint=%.1f | dist_boss=%.1f",
                checkpointDistance, golemDist))
        elseif now - castleRuntime.castleGolemLastDiagnosticAt >= 6 then
            castleRuntime.castleGolemLastDiagnosticAt = now
            print(string.format(
                "[Poly Hub Castelo][GOLEM][ROTA] boss_presente=%s | dist_checkpoint=%.1f | dist_boss=%.1f | fuga=%s",
                tostring(golem ~= nil), checkpointDistance, golemDist,
                tostring(state.castleDraculaDefeated)))
        end
        return
    elseif castlePhase == "golem" then
        if golem then
            castleRuntime.castleGolemSeen = true
            castleRuntime.castleGolemMissingSince = nil
            castleRuntime.castleGolemRecoverAfterRespawn = false
            local hp = castleEnemyHealth(golem)
            if hp ~= nil then
                if castleRuntime.castleGolemLastHealth ~= nil and hp < castleRuntime.castleGolemLastHealth then
                    castleRuntime.castleGolemTookDamage = true
                end
                castleRuntime.castleGolemLastHealth = hp
                if hp <= 0 then
                    castleRuntime.castleBeginGolemTransition("@Health chegou a zero")
                    return
                end
            end
        elseif castleRuntime.castleGolemSeen then
            castleRuntime.castleGolemMissingSince = castleRuntime.castleGolemMissingSince or now
            local goneTime = now - castleRuntime.castleGolemMissingSince
            if goneTime >= 1.5 and (castleRuntime.castleGolemTookDamage or castleRuntime.castleGolemAttacks > 0) then
                castleRuntime.castleBeginGolemTransition("boss sumiu por " .. string.format("%.1fs", goneTime))
                return
            end
        end
    end
end

-- Envia Q com o mesmo metodo da v36, sem tecla duplicada e sem alterar
-- a movimentacao. O retorno confirma somente envio de input, NAO o
-- consumo da habilidade no jogo (servidor pode rejeitar o comando).
function castleRuntime.castleSendQ()
    local success, reason = pcall(function()
        local vim = game:GetService('VirtualInputManager')
        vim:SendKeyEvent(true, Enum.KeyCode.Q, false, game)
        task.delay(0.09, function()
            pcall(function() vim:SendKeyEvent(false, Enum.KeyCode.Q, false, game) end)
        end)
    end)
    if success then return true, 'VirtualInputManager' end

    local env = nil
    pcall(function()
        if type(getgenv) == 'function' then env = getgenv() end
    end)
    env = type(env) == 'table' and env or _G
    local down = (env and env.keypress) or keypress
    local up = (env and env.keyrelease) or keyrelease
    if type(down) == 'function' and type(up) == 'function' then
        local ok, err = pcall(function()
            down(0x51) -- tecla Q
            task.delay(0.09, function() pcall(up, 0x51) end)
        end)
        if ok then return true, 'keypress/keyrelease' end
        return false, tostring(err)
    end
    return false, 'Entrada de tecla Q indisponivel neste runtime: ' .. tostring(reason)
end

-- Q tem alcance independente da espada. Ao ficar disponivel pelo
-- temporizador, equipa a Tool e envia UMA tecla, sem repeticoes curtas.
-- Um TextBox/chat focado impede o envio, para nao digitar Q em um campo.
-- Este estado NAO e o cooldown real do jogo (ainda nao identificado).
function castleRuntime.castleQCanTry(now)
    if not state.castleFarm or not state.castleAutoQ then return false end
    if castlePhase ~= 'dracula' and castlePhase ~= 'golem' then return false end
    if now - castleRuntime.castleLastQCastAt < state.castleQInterval then return false end
    if now - castleRuntime.castleLastQAttemptAt < CASTLE_CONFIG.qRetryAfterFailure then return false end
    return true
end

function castleRuntime.castleTryQ(now, enemy, humanoid, targetDistance)
    if not castleRuntime.castleQCanTry(now) then return end
    if not enemy or not enemy.Parent or not humanoid or humanoid.Health <= 0 then
        castleRuntime.castleQLastObservation = 'aguardando boss/personagem vivo'
        return
    end
    if not targetDistance or targetDistance > state.castleQRange then
        castleRuntime.castleQLastObservation = 'fora do alcance do Q'
        return
    end
    -- Q era testado apenas a <= Approach Distance (8 studs). Em combate
    -- a distancia pode oscilar e impedir todas as tentativas por minutos.
    local sword = castleCombatTool(humanoid)
    if not sword or sword.Parent ~= localPlayer.Character then
        castleRuntime.castleQLastObservation = 'sem espada equipada'
        return
    end
    if not sword.Enabled then
        castleRuntime.castleQLastObservation = 'Tool desabilitada'
        return
    end
    if UserInputService:GetFocusedTextBox() then
        castleRuntime.castleQLastObservation = 'texto/chat focado, Q adiado'
        return
    end

    -- Apos equipar uma espada nova, aguarda uma fracao de segundo para o
    -- jogo registrar a Tool antes de mandar Q. Nao conta isso como uso.
    if castleRuntime.castleQToolRef ~= sword then
        castleRuntime.castleQToolRef = sword
        castleRuntime.castleQToolReadyAt = now + 0.35
        castleRuntime.castleQLastObservation = 'equipando espada (0.35 s)'
        return
    end
    if now < castleRuntime.castleQToolReadyAt then
        return
    end

    castleRuntime.castleLastQAttemptAt = now
    local ok, method = castleRuntime.castleSendQ()
    if ok then
        castleRuntime.castleLastQCastAt = now
        castleRuntime.castleLastQMethod = method
        castleRuntime.castleQLastObservation = 'tecla Q enviada (' .. tostring(method) .. ')'
        print(string.format('[Poly Hub Castelo][Q] Tecla enviada por %s; timer configurado: %.0fs; XZ=%.1f; espada=%s; ATIVACAO NAO CONFIRMADA',
            tostring(method), state.castleQInterval, targetDistance, sword.Name))
    else
        castleRuntime.castleQFailures += 1
        castleRuntime.castleQLastObservation = 'falha no envio: ' .. tostring(method)
        if castleRuntime.castleQFailures <= 2 or castleRuntime.castleQFailures % 6 == 0 then
            warn('[Poly Hub Castelo][Q] ' .. tostring(method))
        end
    end
end

function castleRuntime.castleUpdateQStatus(now)
    local control = state._uiRefs.castleQStatusText
    if not control or not control.Parent then return end
    if now - castleRuntime.castleQStatusUpdatedAt < 0.40 then return end
    castleRuntime.castleQStatusUpdatedAt = now
    local remaining = math.max(0, state.castleQInterval - (now - castleRuntime.castleLastQCastAt))
    if not state.castleAutoQ then
        control.Text = 'Q: OFF'
    elseif remaining > 0 then
        control.Text = string.format('Q: proxima tentativa em %.1fs | %s',
            remaining, castleRuntime.castleLastQMethod)
    else
        control.Text = 'Q: timer pronto | ' .. tostring(castleRuntime.castleQLastObservation)
    end
end

-- Os dois trajetos (janela apos Dracula e saida apos GraveGolem) usam
-- exatamente o MESMO planejador e as mesmas protecoes antitravamento.
-- MoveTo so e reenviado ao mudar de waypoint ou para evitar timeout.
local function castlePlanTriggerRoute(root, destination)
    local path = PathfindingService:CreatePath({
        AgentRadius = 2,
        AgentHeight = 5,
        AgentCanJump = true,
        AgentCanClimb = true,
        WaypointSpacing = 8, -- menos microparadas do que espacamento 4
    })
    castleRouteCalculatedAt = os.clock()
    local ok, err = pcall(function()
        path:ComputeAsync(root.Position, destination)
    end)
    if ok and path.Status == Enum.PathStatus.Success then
        castleRouteWaypoints = path:GetWaypoints()
        castleRouteIndex = 1
        castleRuntime.castleRouteMoveTarget = nil
        castleRouteLastProgressAt = os.clock()
        castleRouteLastPos = root.Position
        print(string.format('[Poly Hub Castelo][ROTA] Planejado: %d pontos, %.1f studs restantes',
            #castleRouteWaypoints, castleHorizontalDistance(root.Position, destination)))
    else
        castleRouteWaypoints = nil
        castleRouteIndex = 1
        castleRuntime.castleRouteFailures += 1
        if castleRuntime.castleRouteFailures <= 3 or castleRuntime.castleRouteFailures % 5 == 0 then
            warn('[Poly Hub Castelo][ROTA] Sem caminho completo: ' .. tostring(err or path.Status))
        end
    end
end

function castleRuntime.castleRouteHasLineOfSight(root, destination)
    local direction = Vector3.new(destination.X - root.Position.X, 0, destination.Z - root.Position.Z)
    if direction.Magnitude > CASTLE_CONFIG.routeDirectLineMaxDistance or direction.Magnitude < 0.1 then return false end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {root.Parent}
    local origin = root.Position + Vector3.new(0, 2, 0)
    return workspace:Raycast(origin, direction, params) == nil
end

-- Mantem velocidade constante durante ambas as transicoes. Evita enviar
-- MoveTo repetido a cada 0.11/0.28s, que causa microparadas em varios jogos.
local function castleGoToGolemTrigger(now, humanoid, root, version, exitMode)
    local destination = exitMode and CASTLE_CONFIG.finalExitPosition or CASTLE_CONFIG.golemTriggerPosition
    if not state.castleFarm or castleVersion ~= version then return end

    local horizontal = castleHorizontalDistance(root.Position, destination)
    local vertical = math.abs(root.Position.Y - destination.Y)
    if horizontal <= CASTLE_CONFIG.golemTriggerRadius
        and vertical <= CASTLE_CONFIG.golemTriggerYTolerance then
        pcall(function() humanoid:MoveTo(root.Position) end)
        castleResetRoute()
        castlePhase = exitMode and 'loot' or 'golem'
        castlePhaseStartedAt = now
        castleUpdateDetails()
        castleStatus(exitMode and 'Saida final alcancada; aguardando recompensa'
            or 'Checkpoint alcancado; aguardando GraveGolem')
        print(exitMode and '[Poly Hub Castelo][ROTA] Saida final alcancada'
            or '[Poly Hub Castelo][ROTA] Checkpoint GraveGolem alcancado')
        return
    end

    castleRuntime.castleApplyRouteSpeed(humanoid)
    if castleRouteLastPos == nil or castleHorizontalDistance(root.Position, castleRouteLastPos) >= 1.5 then
        castleRouteLastPos = root.Position
        castleRouteLastProgressAt = now
    end
    local stuck = castleRouteLastProgressAt > 0
        and now - castleRouteLastProgressAt >= CASTLE_CONFIG.routeStuckSeconds
    if stuck then
        castleRuntime.castleRouteStuckRecoveries += 1
        if castleRuntime.castleRouteStuckRecoveries <= 5
            or castleRuntime.castleRouteStuckRecoveries % 5 == 0 then
            print(string.format('[Poly Hub Castelo][ROTA] Sem progresso %.1fs; replanejando (tentativa %d), resto %.1f, Speed=%.1f, Anchored=%s, State=%s',
                now - castleRouteLastProgressAt, castleRuntime.castleRouteStuckRecoveries,
                horizontal, humanoid.WalkSpeed, tostring(root.Anchored), tostring(humanoid:GetState())))
        end
        -- Em caminhos com degraus a tentativa de pular ajuda a soltar.
        pcall(function() humanoid.Jump = true end)
        castleRouteWaypoints = nil
        castleRouteIndex = 1
        castleRuntime.castleRouteMoveTarget = nil
        castleRouteLastProgressAt = now
    end

    if castleRouteCalculatedAt == 0
        or (not castleRouteWaypoints and now - castleRouteCalculatedAt >= CASTLE_CONFIG.routeRecalculateInterval) then
        castlePlanTriggerRoute(root, destination)
        if not state.castleFarm or castleVersion ~= version or not root.Parent then return end
    end

    -- Quando a janela esta realmente aberta, a aproximacao final pode
    -- usar o destino direto. Antes disso, so usar waypoints navegaveis.
    local directVisible = castleRuntime.castleRouteHasLineOfSight(root, destination)
    local waypoint = nil
    if not directVisible and castleRouteWaypoints then
        while castleRouteIndex <= #castleRouteWaypoints do
            local candidate = castleRouteWaypoints[castleRouteIndex]
            local horizontalToPoint = castleHorizontalDistance(root.Position, candidate.Position)
            if horizontalToPoint > CASTLE_CONFIG.routeWaypointRadius then
                waypoint = candidate
                break
            end
            castleRouteIndex += 1
        end
    end
    local nextPosition = nil
    if directVisible then
        nextPosition = destination
    elseif waypoint then
        nextPosition = waypoint.Position
    elseif castleRouteWaypoints and #castleRouteWaypoints > 0 then
        nextPosition = destination -- ultimo ponto ja passou
    else
        -- Sem caminho e sem linha de visao: nao empurrar contra o vidro.
        castleStatus(string.format('Rota bloqueada; recalculando (%.1f studs)', horizontal))
        return
    end

    local previous = castleRuntime.castleRouteMoveTarget
    local changed = previous == nil or castleHorizontalDistance(previous, nextPosition) > 2.2
    if changed or now - castleLastRouteMoveAt >= CASTLE_CONFIG.routeMoveRefreshSeconds then
        if waypoint and waypoint.Action == Enum.PathWaypointAction.Jump then
            pcall(function() humanoid.Jump = true end)
        end
        castleRuntime.castleRouteMoveTarget = nextPosition
        castleLastRouteMoveAt = os.clock()
        pcall(function() humanoid:MoveTo(nextPosition) end)
    end
    castleStatus(string.format(exitMode
        and 'Saida: %.1f studs | velocidade %.0f | ponto %d'
        or 'Checkpoint: %.1f studs | velocidade %.0f | ponto %d',
        horizontal, humanoid.WalkSpeed, castleRouteIndex))
end

-- TELEPORT opcional nas transicoes do Castelo. Diferente de WALK, aqui
-- a chegada geometrica NAO e confirmacao de ativacao: aguardamos o boss,
-- a cutscene do proximo estagio ou as telas finais antes de avancar.
-- Nao executa teleporte durante ataque, morte do personagem ou cutscene.
function castleRuntime.castleTryTeleportTransition(now, humanoid, root, version, exitMode, ui)
    if not state.castleFarm or castleVersion ~= version
        or state.castleTransitionMode ~= "Teleport"
        or not humanoid or humanoid.Health <= 0 or not root or not root.Parent then return end
    local phase = exitMode and "finish_route" or "trigger"
    if castlePhase ~= phase then return end
    local destination = exitMode and CASTLE_CONFIG.finalExitPosition
        or CASTLE_CONFIG.golemTriggerPosition
    local ctx = castleRuntime.castleTeleportContext
    if not ctx or ctx.phase ~= phase or ctx.root ~= root then
        castleResetRoute() -- restaura velocidade temporaria da caminhada
        ctx = {
            phase = phase, root = root, attempts = 0, lastAttempt = 0,
            nextAttemptAt = 0, bounced = 0, checkedBounce = false,
            sawNormalCamera = false, sceneStartedAt = nil,
        }
        castleRuntime.castleTeleportContext = ctx
        print(string.format('[Poly Hub Castelo][TP] Iniciando %s -> (%.2f, %.2f, %.2f)',
            phase, destination.X, destination.Y, destination.Z))
    end

    -- Se o usuario completou pelo jogo, a fase normal processa a GUI.
    if exitMode and ui and (ui.loot or ui.replay) then return end
    local cam = workspace.CurrentCamera
    local cameraLocked = cam ~= nil and cam.CameraType == Enum.CameraType.Scriptable
    if not cameraLocked then ctx.sawNormalCamera = true end
    -- Aceitar como transicao apenas uma camera que comecou NAO Scriptable
    -- nesta mesma fase e mudou depois de ao menos uma tentativa.
    if cameraLocked and ctx.sawNormalCamera and ctx.lastAttempt > 0
        and not ctx.sceneStartedAt then
        ctx.sceneStartedAt = now
        print('[Poly Hub Castelo][TP] Cutscene detectada; suspendendo teleportes')
    end
    if ctx.sceneStartedAt then
        castleStatus('Cutscene detectada; aguardando voltar ao fluxo normal')
        if not cameraLocked
            and now - ctx.sceneStartedAt >= CASTLE_CONFIG.teleportSceneExitGraceSeconds then
            castlePhase = exitMode and 'loot' or 'golem'
            castlePhaseStartedAt = now
            castleRuntime.castleTeleportContext = nil
            castleResetRoute()
            castleUpdateDetails()
            castleStatus(exitMode and 'Cena final terminou; aguardando recompensas'
                or 'Cena do boss terminou; procurando GraveGolem')
            print(exitMode and '[Poly Hub Castelo][TP] FIM DE CENA: rotina de recompensas'
                or '[Poly Hub Castelo][TP] FIM DE CENA: retomando combate Golem')
        end
        return
    end
    if cameraLocked then
        castleStatus('Camera em cutscene; teleporte suspenso')
        return
    end

    local distance = castleHorizontalDistance(root.Position, destination)
    local yDistance = math.abs(root.Position.Y - destination.Y)
    local inside = distance <= CASTLE_CONFIG.teleportArrivalRadius
        and yDistance <= CASTLE_CONFIG.teleportArrivalYTolerance
    if inside then
        castleStatus(exitMode and 'Na saida final: esperando cena/recompensas'
            or 'No checkpoint: esperando cena/GraveGolem')
        return
    end

    -- Se o cliente conseguiu chegar mas o servidor o devolveu, aguarde
    -- antes da proxima tentativa. Sem martelar CFrame por frame.
    if ctx.lastAttempt > 0 and not ctx.checkedBounce
        and now - ctx.lastAttempt >= 0.85 then
        ctx.checkedBounce = true
        ctx.bounced += 1
        local waitSeconds = math.min(
            CASTLE_CONFIG.teleportMaxRetrySeconds,
            CASTLE_CONFIG.teleportInitialRetrySeconds * (1.6 ^ math.min(ctx.bounced, 4)))
        ctx.nextAttemptAt = math.max(ctx.nextAttemptAt, now + waitSeconds)
        warn(string.format('[Poly Hub Castelo][TP] Posicao nao mantida (%s, tentativa %d):'
            .. ' servidor pode estar devolvendo o personagem; proxima tentativa em %.1fs',
            phase, ctx.attempts, waitSeconds))
    end
    if now < ctx.nextAttemptAt then
        castleStatus(string.format('Teleport: posicao corrigida; aguardando %.1fs para nova tentativa',
            ctx.nextAttemptAt - now))
        return
    end
    ctx.attempts += 1
    ctx.lastAttempt = now
    ctx.checkedBounce = false
    ctx.nextAttemptAt = now + CASTLE_CONFIG.teleportInitialRetrySeconds
    local ok, err = pcall(function()
        -- Offset curto evita colocar o HumanoidRootPart dentro do chao.
        root.CFrame = CFrame.new(destination + Vector3.new(0, 2.5, 0))
    end)
    if ok then
        -- Andar os ultimos studs pode ativar a area de Trigger/Touch.
        pcall(function() humanoid:MoveTo(destination) end)
        print(string.format('[Poly Hub Castelo][TP] %s tentativa %d | restante antes: %.1f studs',
            phase, ctx.attempts, distance))
        castleStatus(string.format('Teleporte %s: tentativa %d; aguardando ativacao',
            exitMode and 'da saida' or 'do boss', ctx.attempts))
    else
        warn('[Poly Hub Castelo][TP] Falha ao definir posicao: ' .. tostring(err))
        ctx.checkedBounce = true
        ctx.nextAttemptAt = now + CASTLE_CONFIG.teleportMaxRetrySeconds
    end
end

local function castleCombatLoop(version)
    local function active()
        return state.castleFarm and castleVersion == version and screenGui.Parent ~= nil
    end
    local lastMove = 0
    local lastAttack = 0
    local lastTarget = nil
    local lastMode = ""
    local function logMode(mode, label)
        if lastMode ~= mode then
            lastMode = mode
            print("[Poly Hub Castelo] " .. label)
        end
    end
    while active() do
        local now = os.clock()
        -- IMPORTANTE: ler a GUI ANTES de ghostGetCharacter(). Quando o
        -- Humanoid morre, ghostGetCharacter retorna nil e a v16 nunca
        -- chegava a processar o botao "Tente novamente".
        local ui = castleRuntime.castleReadUI(now)
        local character = localPlayer.Character
        local rawHumanoid = character and character:FindFirstChildOfClass("Humanoid")
        local playerDead = rawHumanoid ~= nil and rawHumanoid.Health <= 0
        local defeatVisible = ui.defeated or (ui.retry and playerDead)

        -- Alguns respawns fecham "Derrotado" antes que a varredura de UI
        -- registre a morte; nesse caso o novo Character/Humanoid e a prova
        -- de que precisamos invalidar as referencias anteriores.
        local lifeChanged = character ~= nil and (
            character ~= castleRuntime.castleBoundCharacter
            or (rawHumanoid ~= nil and rawHumanoid ~= castleRuntime.castleBoundHumanoid))
        if lifeChanged and (
            castleRuntime.castlePendingRespawnCharacter ~= character
            or castleRuntime.castlePendingRespawnHumanoid ~= rawHumanoid) then
            castleRuntime.castlePendingRespawnCharacter = character
            castleRuntime.castlePendingRespawnHumanoid = rawHumanoid
            castleRuntime.castlePendingRespawnAt = now
            print('[Poly Hub Castelo][CICLO] Troca de Character/Humanoid detectada; aguardando personagem vivo e interface livre')
        end

        if defeatVisible then
            castleClearVertical()
            castleResetRoute()
            castleTarget = nil
            lastTarget = nil
            if not castleRuntime.castleDefeatObserved then
                castleRuntime.castleDefeatObserved = true
                castleRuntime.castleDefeatObservedAt = now
                castleRuntime.castleDefeatCharacter = character
                castleStatus("Derrotado: aguardando botao Tente novamente")
                print("[Poly Hub Castelo][RETRY] Tela Derrotado detectada; "
                    .. "pausando combate e preparando nova tentativa")
            end
            if state.castleAutoReplay and ui.retry and ui.retryPoint then
                castleStatus("Derrotado: tentando clicar Tente novamente")
                castleRuntime.castleTryUIClick(now, ui.retryPoint, "Tente novamente")
            elseif not state.castleAutoReplay then
                castleStatus("Derrotado: Auto Replay OFF; clique manualmente")
            else
                castleStatus("Derrotado: aguardando botao Tente novamente aparecer")
            end
            task.wait(0.22)
            continue
        end

        if castleRuntime.castleDefeatObserved then
            -- A tela pode desaparecer antes do respawn. Nao resetar a
            -- fase com o personagem ainda morto ou um novo jogo ainda
            -- bloqueado em outra tela.
            if rawHumanoid and rawHumanoid.Health > 0
                and not ui.retry and not ui.defeated
                and not ui.starting and not ui.replay and not ui.loot then
                print("[Poly Hub Castelo][RETRY] Personagem vivo; limpando estado da tentativa anterior")
                if castleResetForNewLife(character, rawHumanoid, 'Derrotado terminou') then
                    lastTarget = nil
                    lastMode = ""
                    lastMove = 0
                    lastAttack = 0
                end
            else
                castleClearVertical()
                castleStatus("Aguardando respawn apos Tente novamente")
                if now - castleRuntime.castleLastDefeatDiagnostic >= 6 then
                    castleRuntime.castleLastDefeatDiagnostic = now
                    print("[Poly Hub Castelo][RETRY][DIAG] screen="
                        .. tostring(ui.defeated) .. " botao=" .. tostring(ui.retry)
                        .. " humanoid=" .. tostring(rawHumanoid and rawHumanoid.Health))
                end
                task.wait(0.25)
                continue
            end
        end

        -- Recuperacao extra quando a tela de derrota foi perdida.
        -- Nao altera o movimento: apenas restaura estados e desconecta
        -- o monitor antigo de HP antes do ciclo normal da v20 continuar.
        if castleRuntime.castlePendingRespawnCharacter then
            if character == castleRuntime.castlePendingRespawnCharacter
                and rawHumanoid and rawHumanoid.Health > 0
                and not ui.defeated and not ui.retry
                and not ui.replay and not ui.loot and not ui.starting then
                if castleResetForNewLife(character, rawHumanoid,
                    'novo Character/Humanoid sem depender da tela Derrotado') then
                    lastTarget = nil
                    lastMode = ""
                    lastMove = 0
                    lastAttack = 0
                end
            elseif now - castleRuntime.castleLastLifecycleLog >= 7 then
                castleRuntime.castleLastLifecycleLog = now
                print(string.format(
                    '[Poly Hub Castelo][CICLO][DIAG] pendente=sim HP=%s derrota=%s retry=%s replay=%s iniciando=%s',
                    tostring(rawHumanoid and rawHumanoid.Health), tostring(ui.defeated),
                    tostring(ui.retry), tostring(ui.replay), tostring(ui.starting)))
            end
        end

        local _, humanoid, root = ghostGetCharacter()
        if not humanoid then
            castleClearVertical()
            castleTarget = nil
            lastTarget = nil
            castleStatus(playerDead and "Personagem morreu; aguardando tela Derrotado"
                or "Aguardando personagem")
            task.wait(0.3)
            continue
        end
        -- Cura opcional antes de decidir o ataque (sem alterar rotas nem Q).
        -- Equipa a maca, ativa uma unica vez e restaura a espada.
        if castleTryAutoApple(now, humanoid) then
            task.wait(CASTLE_CONFIG.updateInterval)
            continue
        end
        -- Independente do alvo atual: morte de ambos os bosses.
        castleObserveBossProgress(now, root)
        -- Recupera o inicio de OUTRA partida mesmo quando o jogo desenha a
        -- tela de replay fora do PlayerGui e nossa leitura nao a encontra.
        if castlePhase ~= "dracula" and castlePhase ~= "cutscene" and castlePhase ~= "trigger"
            and castlePhase ~= "golem" then
            local folder = castleEnemyFolder()
            if folder and now - castleRuntime.castleFinishConfirmedAt >= 3
                and castleRuntime.castleFinishConfirmedAt > 0 then
                local newDracula = false
                for _, model in ipairs(folder:GetChildren()) do
                    if castleIsDracula(model) then
                        local hp = castleEnemyHealth(model)
                        local pos = castleEnemyPosition(model)
                        if pos and (hp == nil or hp > 0)
                            and castleHorizontalDistance(root.Position, pos) <= 180 then
                            newDracula = true
                            break
                        end
                    end
                end
                if newDracula and not ui.loot and not ui.replay then
                    print("[Poly Hub Castelo] NOVO DRACULA detectado: resetando fases com Auto Farm ainda ligado")
                    castleResetBossStage()
                    castleRuntime.castleBoundCharacter = character
                    castleRuntime.castleBoundHumanoid = humanoid
                    castleRuntime.castlePendingRespawnCharacter = nil
                    castleRuntime.castlePendingRespawnHumanoid = nil
                    lastTarget = nil
                    lastMode = ""
                    lastMove = 0
                    lastAttack = 0
                    castleStatus("Nova corrida: Dracula ativo, retomando ataques")
                end
            end
        end
        if ui.replay and castlePhase ~= "replay" and castlePhase ~= "restart_wait" then
            castleClearVertical()
            castleResetRoute()
            castleTarget = nil
            castlePhase = "replay"
            castlePhaseStartedAt = now
            castleUpdateDetails()
            print("[Poly Hub Castelo] RECUPERACAO: tela Corra novamente detectada")
        end
        -- Qualquer tela de saque no fim da luta tem prioridade sobre andar:
        -- evita perder os botoes de continuar enquanto o personagem corre.
        if castlePhase == "golem" and ui.loot and castleRuntime.castleGolemSeen then
            castleRuntime.castleBeginGolemTransition("recompensa final ja apareceu")
        end
        -- As fases seguintes dispensam um inimigo visivel. O gatilho da janela
        -- e um ponto no mapa, nao um objeto em Aggressors.
        if castlePhase == "cutscene" then
            castleClearVertical()
            castleRuntime.castleRestoreRouteSpeed()
            local elapsed = now - castlePhaseStartedAt
            local cam = workspace.CurrentCamera
            local cameraLocked = cam and cam.CameraType == Enum.CameraType.Scriptable
            if elapsed >= CASTLE_CONFIG.cutsceneWaitSeconds
                and (not cameraLocked or elapsed >= CASTLE_CONFIG.cutsceneMaxSeconds) then
                castlePhase = "trigger"
                castlePhaseStartedAt = now
                castleResetRoute()
                castleUpdateDetails()
                castleStatus("Fuga confirmada; verificando rota pela janela para GraveGolem")
                print("[Poly Hub Castelo] Indo ao ponto (6328.90, 273.93, -6003.89)")
            else
                local remaining = math.max(0, CASTLE_CONFIG.cutsceneWaitSeconds - elapsed)
                    castleStatus(string.format("Dracula fugiu: aguardando vidro quebrar %.1fs%s", remaining,
                    cameraLocked and " (camera em cena)" or ""))
            end
            task.wait(0.18)
            continue
        elseif castlePhase == "trigger" then
            castleClearVertical()
            local ok, err = pcall(function()
                if state.castleTransitionMode == "Teleport" then
                    castleRuntime.castleTryTeleportTransition(now, humanoid, root, version, false, ui)
                else
                    castleGoToGolemTrigger(now, humanoid, root, version)
                end
            end)
            if not ok then
                warn("[Poly Hub Castelo] Erro no deslocamento ao gatilho: " .. tostring(err))
                castleStatus("Erro no deslocamento ao gatilho; veja Output")
            end
            task.wait(CASTLE_CONFIG.updateInterval)
            continue
        elseif castlePhase == "finish_route" then
            castleClearVertical()
            -- Se a tela final ja abriu, ela prevalece sobre o movimento.
            if ui.loot then
                castlePhase = "loot"
                castlePhaseStartedAt = now
                castleUpdateDetails()
            elseif ui.replay then
                castlePhase = "replay"
                castlePhaseStartedAt = now
                castleUpdateDetails()
            else
                local ok, err = pcall(function()
                    if state.castleTransitionMode == "Teleport" then
                        castleRuntime.castleTryTeleportTransition(now, humanoid, root, version, true, ui)
                    else
                        castleGoToGolemTrigger(now, humanoid, root, version, true)
                    end
                end)
                if not ok then
                    castleStatus("Rota da saida falhou; veja Output")
                    warn("[Poly Hub Castelo] Rota final: " .. tostring(err))
                end
            end
            task.wait(CASTLE_CONFIG.updateInterval)
            continue
        elseif castlePhase == "loot" then
            castleClearVertical()
            if ui.replay then
                castlePhase = "replay"
                castlePhaseStartedAt = now
                castleUpdateDetails()
                castleStatus("Recompensas concluidas, aguardando Corra novamente")
            elseif ui.loot then
                castleStatus("NOVO SAQUE: tentando continuar")
                castleRuntime.castleTryUIClick(now, ui.lootPoint, "Recompensa")
            else
                castleStatus("Aguardando tela de saque / continuar")
            end
            task.wait(0.2)
            continue
        elseif castlePhase == "replay" then
            castleClearVertical()
            if not state.castleAutoReplay then
                castleStatus("Corrida concluida. Auto Replay desligado")
                task.wait(0.5)
                continue
            end
            if ui.replay then
                castleStatus("Corra novamente: tentando clicar")
                castleRuntime.castleTryUIClick(now, ui.replayPoint, "Corra novamente")
            elseif ui.starting then
                castleRuntime.castleReplaySawStarting = true
                castleRuntime.castleReplayRequestedAt = castleRuntime.castleReplayRequestedAt > 0
                    and castleRuntime.castleReplayRequestedAt or now
                castlePhase = "restart_wait"
                castlePhaseStartedAt = now
                castleUpdateDetails()
                castleStatus("Corrida reiniciando: esperando novo Castelo")
            elseif castleRuntime.castleReplayRequestedAt > 0
                or (castleRuntime.castleReplayScreenWasVisible
                    and not ui.loot and now - castlePhaseStartedAt > 0.8) then
                -- Tambem reconhece o clique MANUAL: nao exige que tenha
                -- sido possivel simular o mouse pelo LocalScript.
                castlePhase = "restart_wait"
                castlePhaseStartedAt = now
                castleUpdateDetails()
                castleStatus("Tela de replay fechou: aguardando nova corrida")
            else
                castleStatus("Aguardando botao Corra novamente")
            end
            task.wait(0.2)
            continue
        elseif castlePhase == "restart_wait" then
            castleClearVertical()
            if ui.starting then castleRuntime.castleReplaySawStarting = true end
            local elapsed = now - castlePhaseStartedAt
            local screenClosed = not ui.replay and not ui.loot and not ui.starting
            if screenClosed and elapsed >= CASTLE_CONFIG.replayResetWaitSeconds then
                print("[Poly Hub Castelo] NOVA CORRIDA: resetando etapas e reacendendo combate sem mexer no toggle")
                castleResetBossStage()
                castleRuntime.castleBoundCharacter = character
                castleRuntime.castleBoundHumanoid = humanoid
                castleRuntime.castlePendingRespawnCharacter = nil
                castleRuntime.castlePendingRespawnHumanoid = nil
                lastTarget = nil
                lastMode = ""
                lastMove = 0
                lastAttack = 0
                castleStatus("Nova corrida detectada: procurando Dracula")
            elseif ui.replay and elapsed > 4 then
                castlePhase = "replay"
                castlePhaseStartedAt = now
                castleUpdateDetails()
            else
                castleStatus("Aguardando reinicio da proxima corrida")
            end
            task.wait(0.2)
            continue
        elseif castlePhase == "concluido" then
            castleClearVertical()
            castlePhase = "loot"
            castlePhaseStartedAt = now
            castleUpdateDetails()
            continue
        end

        if not castleEnemyFolder() then
            castleClearVertical()
            castleStatus("Pasta Animal_Live/Aggressors nao encontrada")
            task.wait(0.5)
            continue
        end

        -- Atualiza o alvo. A fase 2 so inicia ao confirmar FUGA perto
        -- de 50% de vida, nunca pela falsa "morte" nem por boss distante.
        if castleTarget and (castleTarget.Parent ~= castleEnemyFolder()
            or (castleEnemyHealth(castleTarget) ~= nil and castleEnemyHealth(castleTarget) <= 0)) then
            local animalGone = castleEnemyType(castleTarget)
            local hpGone = castleEnemyHealth(castleTarget)
            if castleIsDracula(castleTarget) and castlePhase == "dracula" then
                -- Nao iniciar a etapa 2 diretamente por alvo removido.
                -- castleCheckDraculaEscape exige HP ~50% e prova da fuga.
                castleDraculaMissingSince = castleDraculaMissingSince or now
                castleRuntime.castleCheckDraculaEscape(now, castleEnemyFolder(), root)
                if castlePhase == "dracula" then
                    castleStatus("Dracula saiu: aguardando prova da fuga apos 50% HP")
                end
            elseif castleIsGraveGolem(castleTarget) and castlePhase == "golem" then
                if hpGone ~= nil and hpGone <= 0 then
                    castleRuntime.castleBeginGolemTransition("@Health chegou a zero (alvo atual)")
                elseif castleRuntime.castleGolemSeen and castleRuntime.castleGolemAttacks > 0 then
                    castleRuntime.castleGolemMissingSince = castleRuntime.castleGolemMissingSince or now
                end
            end
            castleTarget = nil
            lastTarget = nil
            if castlePhase ~= "dracula" and castlePhase ~= "golem" then
                task.wait(CASTLE_CONFIG.updateInterval)
                continue
            end
        end

        if not castleTarget then
            castleTarget = castleCandidate(root.Position)
        end
        if castleTarget and castlePhase == "golem" then
            castleRuntime.castleGolemRecoverAfterRespawn = false
        end
        if castleTarget ~= lastTarget then
            castleClearVertical()
            castleRuntime.castleCombatTeleportContext = nil
            lastTarget = castleTarget
            lastMode = ""
            if castleTarget then
                print("[Poly Hub Castelo] Novo alvo: " .. castleEnemyType(castleTarget)
                    .. " | DungeonRoom=" .. tostring(castleTarget:GetAttribute("DungeonRoom"))
                    .. " | DungeonRun=" .. tostring(castleTarget:GetAttribute("DungeonRun")))
                if castlePhase == "golem" then
                    print(string.format("[Poly Hub Castelo][GOLEM][COMBATE] alvo=%s HP=%s part=%s",
                        tostring(castleTarget.Name), tostring(castleEnemyHealth(castleTarget)),
                        tostring(castleEnemyPosition(castleTarget))))
                end
            end
        end
        if not castleTarget then
            if castlePhase == "golem"
                and now - castleRuntime.castleGolemLastDiagnosticAt >= 6 then
                castleRuntime.castleGolemLastDiagnosticAt = now
                local folder = castleEnemyFolder()
                local total, matches, eligible, minDist = 0, 0, 0, math.huge
                if folder then
                    for _, model in ipairs(folder:GetChildren()) do
                        if model:IsA("Model") or model:IsA("BasePart") then
                            total += 1
                            if castleIsGraveGolem(model) then
                                matches += 1
                                local pos = castleEnemyPosition(model)
                                local hp = castleEnemyHealth(model)
                                if pos and (hp == nil or hp > 0) then
                                    eligible += 1
                                    minDist = math.min(minDist,
                                        castleHorizontalDistance(root.Position, pos))
                                end
                            end
                        end
                    end
                end
                print(string.format(
                    "[Poly Hub Castelo][GOLEM][ALVO] modelos=%d reconhecidos=%d vivos=%d distancia_min=%.1f limite=%d | fase=%s",
                    total, matches, eligible, minDist,
                    CASTLE_CONFIG.golemRecoveryDistance, castlePhase))
            end
            if castlePhase == "dracula" and now - castleRuntime.castleLastEvidenceLog > 6 then
                castleRuntime.castleLastEvidenceLog = now
                print(string.format("[Poly Hub Castelo][DIAG] fase=dracula alcance=%d viu=%s HP=%s ataques=%d ultimo_modelo_ausente=%s run=%s",
                    state.castleDraculaDetectionRange,
                    tostring(castleDraculaSeen), tostring(castleDraculaLastHealth),
                    castleDraculaAttacks, tostring(castleDraculaMissingSince), tostring(castleRunId)))
            end
            if castleTargetText then castleTargetText.Text = "Alvo: nenhum" end
            -- Depois do respawn na fase 3, o boss pode estar longe demais
            -- para ser replicado. Retornar ao checkpoint pelo sistema de
            -- rota da v28, sem criar comandos de teleport/forca novos.
            if castlePhase == "golem" and castleRuntime.castleGolemRecoverAfterRespawn then
                local d = castleHorizontalDistance(root.Position, CASTLE_CONFIG.golemTriggerPosition)
                if d > CASTLE_CONFIG.golemEngageRadius then
                    castleStatus(string.format("Respawn Golem: retornando a arena (%.1f studs)", d))
                    castleGoToGolemTrigger(now, humanoid, root, version, false)
                else
                    castleRuntime.castleGolemRecoverAfterRespawn = false
                    castleResetRoute()
                    castleStatus("Na arena: aguardando GraveGolem replicar")
                end
            else
                castleStatus(castlePhase == "golem"
                    and "Aguardando GraveGolem surgir em Aggressors"
                    or "Aguardando inimigos / Dracula")
            end
            task.wait(0.33)
            continue
        end

        local position = castleEnemyPosition(castleTarget)
        if not position then
            castleClearVertical()
            castleTarget = nil
            task.wait(0.12)
            continue
        end
        local run = castleTarget:GetAttribute("DungeonRun")
        if castleRunId == nil and run ~= nil and castleIsBoss(castleTarget) then
            castleRunId = tostring(run)
        end
        local animal = castleEnemyType(castleTarget)
        local hp = castleEnemyHealth(castleTarget)
        if castleIsDracula(castleTarget) then
            castleRuntime.castleWatchDraculaHealth(castleTarget)
            if castlePhase ~= "dracula" then
                task.wait(CASTLE_CONFIG.updateInterval)
                continue
            end
            castleDraculaSeen = true
            castleDraculaMissingSince = nil
            castleDraculaLastPosition = position
            -- Toda leitura de HP passa pela MESMA rotina, para nao perder
            -- a transicao se o evento ocorrer entre duas varreduras.
            if castleRuntime.castleDraculaWatchedModel == castleTarget then
                castleRuntime.castleTrackDraculaHP(castleTarget, "combate")
            end
        elseif castleIsGraveGolem(castleTarget) then
            castleRuntime.castleGolemSeen = true
            castleRuntime.castleGolemMissingSince = nil
            if hp ~= nil and castleRuntime.castleGolemLastHealth ~= nil and hp < castleRuntime.castleGolemLastHealth then
                castleRuntime.castleGolemTookDamage = true
            end
            if hp ~= nil then castleRuntime.castleGolemLastHealth = hp end
        end
        if castleTargetText then
            local hpInfo = hp and tostring(math.floor(hp)) or "N/D"
            if castleIsDracula(castleTarget) and hp then
                local maximum = castleRuntime.castleEnemyMaxHealth(castleTarget)
                if maximum and maximum > 0 then
                    hpInfo = string.format("%d/%d (%.1f%%)",
                        math.floor(hp), math.floor(maximum), math.clamp(hp / maximum * 100, 0, 100))
                end
            end
            castleTargetText.Text = string.format("Alvo: %s | HP: %s", animal, hpInfo)
        end
        -- Para GraveGolem a superficie (nao o centro do corpo enorme)
        -- determina a distancia real de aproximacao e alcance dos golpes.
        local distance = castleRuntime.castleDistanceToCombatTarget(
            root.Position, castleTarget, position)
        -- TP durante combate e seletivo por boss; transicoes seguem WALK/TP v32.
        -- A verificacao de posicao e refeita depois do deslocamento, pois a
        -- espada pode atacar imediatamente no mesmo ciclo se ja estiver perto.
        -- Resetar a cada tick: so o TP do Dracula pode marcar espera por
        -- alcance. Se o alvo mudar, o Golem nunca herda esta condicao.
        castleRuntime.castleCombatTeleportWalkToDracula = false
        local combatTeleport = castleRuntime.castleTryCombatTeleport(
            now, humanoid, root, castleTarget, position)
        if combatTeleport then
            local currentCenter = castleEnemyPosition(castleTarget) or position
            distance = castleRuntime.castleCombatDistance(
                root.Position, castleTarget, currentCenter)
        end
        local near = distance <= state.castleApproach
        local tooFar = distance > state.castleApproach + CASTLE_CONFIG.disengagePadding
        -- Q: intervalo e alcance independentes do golpe de espada e da forma
        -- de aproximacao. Assim, continua funcionando enquanto faz WALK/TP
        -- na arena (nunca nas fases de cutscene/saida).
        castleRuntime.castleTryQ(now, castleTarget, humanoid, distance)
        castleRuntime.castleUpdateQStatus(now)
        -- O Golem decola ja ao entrar na regiao proxima a sua SUPERFICIE.
        -- Uma vez decolado, conserva a altura enquanto ele recua; o jogador
        -- nao precisa tocar a MeshPart para iniciar a subida.
        local golemHeightEntry = castlePhase == "golem"
            and state.castleHeightEnabled and state.castleHeight > 0
            and distance <= math.max(state.castleApproach + 6, CASTLE_CONFIG.golemHeightEngageDistance)
        local golemHeightHold = castlePhase == "golem"
            and state.castleHeightEnabled and state.castleHeight > 0
            and castleRuntime.castleGolemHeightAnchorY ~= nil
            and distance <= state.castleApproach + CASTLE_CONFIG.golemHeightHoldPadding
        local golemHeightActive = golemHeightEntry or golemHeightHold

        -- Opcao independente da altura por aproximacao:
        -- SOMENTE Count Dracula, SOMENTE Attack Height POSITIVO.
        -- Comeca a subir assim que o Dracula e escolhido como alvo,
        -- mesmo que ele ainda esteja alem da Approach Distance.
        local directDracula = state.castleHeightDirectDracula
            and state.castleHeight > 0
            and castlePhase == "dracula"
            and castleIsDracula(castleTarget)
            and not castleRuntime.castleCombatTeleportWalkToDracula

        if castleRuntime.castleCombatTeleportWalkToDracula
            or (not combatTeleport and not directDracula and not golemHeightActive
                and (tooFar or (not near and castleHeightGoal == nil))) then
            -- Modo padrao: corre no chao ate chegar perto do inimigo.
            castleClearVertical()
            logMode("ground", "Perseguindo pelo chao, SEM ajuste de altura")
            if castleRuntime.castleCombatTeleportWalkToDracula then
                castleStatus(string.format(
                    "Dracula: WALK %.1f / %d studs ate habilitar TP",
                    distance, state.castleDraculaCombatTeleportRange))
            else
                castleStatus(string.format("Aproximando pelo chao (%.1f studs)", distance))
            end
            if now - lastMove >= CASTLE_CONFIG.moveInterval then
                lastMove = now
                if active() then pcall(function() humanoid:MoveTo(position) end) end
            end
        else
            -- Se altura direta estiver ativa, o Dracula recebe ajuste de Y
            -- desde o inicio; os outros inimigos seguem a regra por proximidade.
            if combatTeleport then
                -- Nao usar MoveTo: o proprio modo TP mantem XZ/Y do alvo.
                logMode("combat_tp", "Teleport de COMBATE: " .. castlePhase
                    .. ", altura " .. tostring(state.castleHeight))
            elseif not near then
                -- Quando o boss sai do raio de ataque, retoma perseguicao.
                castleRuntime.castleGolemNearStopIssued = false
                if now - lastMove >= CASTLE_CONFIG.moveInterval then
                    lastMove = now
                    pcall(function() humanoid:MoveTo(position) end)
                end
            elseif now - lastMove >= CASTLE_CONFIG.moveInterval then
                -- ANTES: MoveTo(root.Position) a cada 0.28s. Repetir ordem
                -- de parar podia interferir na subida fisica do Golem.
                -- Emitir apenas UMA parada quando entra no alcance.
                if not castleRuntime.castleGolemNearStopIssued then
                    castleRuntime.castleGolemNearStopIssued = true
                    lastMove = now
                    pcall(function() humanoid:MoveTo(root.Position) end)
                end
            end

            if combatTeleport then
                -- O controlador vertical e a posicao foram atualizados pelo
                -- castleTryCombatTeleport; nada de Jump ou MoveTo adicionais.
                castleUpdateDetails()
            elseif state.castleHeightEnabled or directDracula then
                if directDracula then
                    logMode("direct_height", "Dracula selecionado: altura +" .. tostring(state.castleHeight)
                        .. " SEM aguardar aproximacao")
                elseif golemHeightActive then
                    logMode("golem_takeoff", "GraveGolem: decolagem proxima a superficie, +"
                        .. tostring(state.castleHeight) .. " studs")
                else
                    logMode("height", "Alvo proximo: altura " .. tostring(state.castleHeight)
                        .. " studs aplicada agora")
                end
                castleEnsureVertical(root)
                castleSetTemporaryNoclip(not directDracula and state.castleHeight < 0, root)
                -- O centro da MeshPart GraveGolem pode estar abaixo da area
                -- caminhavel: usar somente boss.Y+8 faz o destino ser tao
                -- baixo quanto o chao. Ancorar no Y do PERSONAGEM quando
                -- o combate se inicia; nao recalcular a ancora no ar.
                if castlePhase == "golem" and state.castleHeight > 0 then
                    if castleRuntime.castleGolemHeightAnchorY == nil then
                        castleRuntime.castleGolemHeightAnchorY = root.Position.Y
                        print(string.format(
                            "[Poly Hub Castelo][GOLEM][ALTURA] Ancorado: pisoY=%.2f | meshY=%.2f | ajuste=+%.1f",
                            castleRuntime.castleGolemHeightAnchorY, position.Y, state.castleHeight))
                    end
                    castleHeightGoal = math.max(
                        position.Y, castleRuntime.castleGolemHeightAnchorY
                    ) + state.castleHeight
                    -- Nao aguarda tocar no centro do Golem. Solicita o salto
                    -- apenas ao entrar no raio da superficie. Se a fisica do
                    -- Humanoid rejeitar o primeiro salto, ate duas tentativas
                    -- ESPACADAS sao permitidas, nunca em loop agressivo.
                    local belowHeight = castleHeightGoal - root.Position.Y
                    local firstLift = castleRuntime.castleGolemLiftTries == 0
                    local retryLift = castleRuntime.castleGolemLiftTries > 0
                        and castleRuntime.castleGolemLiftTries < CASTLE_CONFIG.golemHeightTakeoffMaxTries
                        and now - castleRuntime.castleGolemLiftLastAt
                            >= CASTLE_CONFIG.golemHeightTakeoffRetrySeconds
                        and belowHeight > 2.5
                        and math.abs(root.AssemblyLinearVelocity.Y) < 1.5
                    if golemHeightEntry and (firstLift or retryLift) then
                        castleRuntime.castleGolemLiftAttempted = true
                        castleRuntime.castleGolemLiftTries += 1
                        castleRuntime.castleGolemLiftLastAt = now
                        if firstLift then
                            castleRuntime.castleGolemLiftStartingY = root.Position.Y
                        end
                        pcall(function()
                            humanoid.Jump = true
                            -- Sem mover CFrame, sem mexer em WalkSpeed e sem
                            -- impulso AssemblyLinearVelocity; o VectorForce
                            -- continua responsavel por manter a altura.
                        end)
                        print(string.format(
                            '[Poly Hub Castelo][GOLEM][ALTURA] Tentativa de decolagem %d/%d | delta=%.2f | XZsuperficie=%.1f',
                            castleRuntime.castleGolemLiftTries,
                            CASTLE_CONFIG.golemHeightTakeoffMaxTries, belowHeight, distance))
                    end
                    if now - castleRuntime.castleGolemHeightDiagnosticAt >= 3 then
                        castleRuntime.castleGolemHeightDiagnosticAt = now
                        print(string.format(
                            "[Poly Hub Castelo][GOLEM][ALTURA] Y_atual=%.2f | Y_alvo=%.2f | delta=%.2f | XZ=%.1f | hold=%s | estado=%s | preso=%s",
                            root.Position.Y, castleHeightGoal,
                            castleHeightGoal - root.Position.Y, distance,
                            tostring(golemHeightHold), tostring(humanoid:GetState()),
                            tostring(root.Anchored)))
                    end
                else
                    castleHeightGoal = position.Y + state.castleHeight
                end
                if directDracula and castleRuntime.castleDirectTakeoffAt == 0 then
                    -- Impulso inicial reduz a chance de Humanoid/MoveTo manter
                    -- os pes colados ao solo com subida imediata.
                    castleRuntime.castleDirectTakeoffAt = now
                    pcall(function()
                        humanoid.Jump = true
                        humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
                        root.AssemblyLinearVelocity = Vector3.new(
                            root.AssemblyLinearVelocity.X,
                            math.max(root.AssemblyLinearVelocity.Y, 17),
                            root.AssemblyLinearVelocity.Z
                        )
                    end)
                    print("[Poly Hub Castelo] Subida imediata Dracula: impulso inicial Y")
                end
                -- Perseguicao plana adicional apenas quando suspenso e longe.
                castleDirectChasePosition = (directDracula or golemHeightActive)
                    and not near and position or nil
                castleUpdateDetails()
            else
                logMode("combat", "Alvo proximo: combate no chao")
                castleClearVertical()
            end

            if near then
                local equipped = castleCombatTool(humanoid)
                if equipped and now - lastAttack >= CASTLE_CONFIG.attackInterval then
                    local currentPosition = castleEnemyPosition(castleTarget)
                    local attackDistance = currentPosition and (combatTeleport
                        and castleRuntime.castleCombatDistance(root.Position, castleTarget, currentPosition)
                        or castleRuntime.castleDistanceToCombatTarget(root.Position, castleTarget, currentPosition))
                    if attackDistance and attackDistance <= state.castleApproach then
                        lastAttack = now
                        local ok = pcall(function() equipped:Activate() end)
                        if ok then
                            castleAttackCount += 1
                            if castleIsDracula(castleTarget) then
                                castleDraculaAttacks += 1
                            elseif castleIsGraveGolem(castleTarget) then
                                castleRuntime.castleGolemAttacks += 1
                            end
                            if castleAttackCount == 1 or castleAttackCount % 10 == 0 then
                                print("[Poly Hub Castelo] Tool:Activate enviado, total " .. castleAttackCount)
                            end
                            castleUpdateDetails()
                        end
                    end
                end
                if castlePhase == "golem" and state.castleHeightEnabled
                    and state.castleHeight > 0 and castleHeightGoal ~= nil
                    and root.Position.Y < castleHeightGoal - 2.0 then
                    castleStatus(string.format(
                        "GraveGolem: elevando Y %.1f / %.1f; espada %s",
                        root.Position.Y, castleHeightGoal,
                        equipped and "equipada" or "nao encontrada"))
                else
                    castleStatus(equipped and (castleTempNoclip
                        and "Atacando de baixo (Noclip AUTO)" or "Atacando alvo proximo")
                        or "Sem Tool de espada acessivel (verifique slot 1)")
                end
            else
                if directDracula then
                    castleStatus(string.format(
                        "Altura DIRETA +%g; perseguindo Dracula (%.1f studs)",
                        state.castleHeight, distance
                    ))
                elseif golemHeightActive and castleHeightGoal ~= nil then
                    castleStatus(string.format(
                        "GraveGolem: subindo para Y %.1f (Y atual %.1f; XZ %.1f)",
                        castleHeightGoal, root.Position.Y, distance))
                else
                    castleStatus("Mantendo combate; alvo se deslocando")
                end
            end
        end
        task.wait(CASTLE_CONFIG.updateInterval)
    end
    castleClearVertical()
    castleRuntime.castleRestoreRouteSpeed()
end

local function setCastleFarm(active)
    castleVersion += 1
    local version = castleVersion
    if active then
        if state._uiRefs.stopExternalAutomation then pcall(state._uiRefs.stopExternalAutomation, "Castelo") end
        print("[Poly Hub Castelo] ON: Deteccao Dracula=" .. tostring(state.castleDraculaDetectionRange)
            .. " / Approach=" .. tostring(state.castleApproach)
            .. " / Height=" .. tostring(state.castleHeight)
            .. " / Ajuste=" .. tostring(state.castleHeightEnabled))
        -- Nao disputamos movimento/Tool entre dois farms simultaneos.
        if state.candyFarm then
            state.candyFarm = false
            if toggles.candyFarm then toggles.candyFarm(false) end
            setGhostFarm(false)
        end
        castleAttackCount = 0
        castleVerticalAssistCount = 0
        castleTarget = nil
        castleRuntime.castleCombatTeleportContext = nil
        castleResetBossStage()
        -- Baseline: nao reconhecer a vida ja existente como respawn.
        castleRuntime.castleBoundCharacter = localPlayer.Character
        castleRuntime.castleBoundHumanoid = castleRuntime.castleBoundCharacter
            and castleRuntime.castleBoundCharacter:FindFirstChildOfClass('Humanoid') or nil
        castleRuntime.castlePendingRespawnCharacter = nil
        castleRuntime.castlePendingRespawnHumanoid = nil
        castleRuntime.castlePendingRespawnAt = 0
        castleStatus("Iniciando Castelo: Dracula foge a ~50% HP, depois GraveGolem")
        task.spawn(function()
            local ok, err = xpcall(function() castleCombatLoop(version) end, debug.traceback)
            if not ok then
                warn("[Poly Hub Castelo] " .. tostring(err))
                if state.castleFarm and castleVersion == version and screenGui.Parent then
                    state.castleFarm = false
                    if toggles.castleFarm then toggles.castleFarm(false) end
                    castleStatus("Erro: veja Output")
                end
                castleClearVertical()
                castleRuntime.castleRestoreRouteSpeed()
            end
        end)
    else
        print("[Poly Hub Castelo] OFF: movimentos e forca vertical encerrados")
        castleTarget = nil
        castleRuntime.castleCombatTeleportContext = nil
        castleRuntime.castlePendingRespawnCharacter = nil
        castleRuntime.castlePendingRespawnHumanoid = nil
        castleRuntime.castleDisconnectDraculaHealth()
        castleClearVertical()
        castleResetRoute()
        castleRuntime.castleTeleportContext = nil
        castlePhase = "dracula"
        castleUpdateDetails()
        local _, humanoid, root = ghostGetCharacter()
        if humanoid and root then
            pcall(function() humanoid:MoveTo(root.Position) end)
        end
        castleStatus("Desativado")
    end
end

playerEffects.castleFarm = setCastleFarm
playerEffects.castleAutoQ = function(enabled)
    castleRuntime.castleQLastObservation = enabled and 'aguardando alcance/espada' or 'desligado'
    castleRuntime.castleQStatusUpdatedAt = -math.huge
    castleRuntime.castleUpdateQStatus(os.clock())
    castleStatus(enabled and ('Poder Q automatico: intervalo ' .. tostring(state.castleQInterval) .. 's')
        or 'Poder Q automatico desligado')
end
playerEffects.castleAutoApple = function(enabled)
    castleRefreshAppleStatus(enabled and "monitorando vida" or "desativado")
    castleStatus(enabled and "Auto Maca ativado: cura quando HP atingir o limite"
        or "Auto Maca desativado")
end
playerEffects.castleRouteBoost = function(enabled)
    if not enabled then castleRuntime.castleRestoreRouteSpeed() end
    castleStatus(enabled and 'Velocidade temporaria nas rotas ativada'
        or 'Velocidade temporaria nas rotas desligada')
end
playerEffects.castleHeightEnabled = function(enabled)
    if not enabled and not state.castleHeightDirectDracula then
        castleClearVertical()
    end
    castleStatus(enabled and "Altura por aproximacao ativa"
        or "Altura por aproximacao OFF")
end
playerEffects.castleCombatTeleportDracula = function(enabled)
    castleRuntime.castleCombatTeleportContext = nil
    castleClearVertical()
    castleStatus(enabled and "TP combate Dracula ON (usa Attack Height)"
        or "TP combate Dracula OFF (WALK preservado)")
end
playerEffects.castleCombatTeleportGolem = function(enabled)
    castleRuntime.castleCombatTeleportContext = nil
    castleClearVertical()
    castleStatus(enabled and "TP combate GraveGolem ON (usa Attack Height)"
        or "TP combate GraveGolem OFF (WALK preservado)")
end
playerEffects.castleHeightDirectDracula = function(enabled)
    -- O modo direto e exclusivo de Dracula e so usa altura positiva.
    -- Desligar agora cancela a sustentacao atual, deixando o proximo
    -- ciclo recalcular o movimento por aproximacao se estiver habilitado.
    if not enabled then
        castleClearVertical()
    end
    if enabled and state.castleHeight <= 0 then
        castleStatus("Modo direto requer Attack Height POSITIVO (+1 a +20)")
    else
        castleStatus(enabled and "Altura direta do Dracula ativada"
            or "Altura direta do Dracula desativada")
    end
end
state._uiRefs.originalCandyEffect = playerEffects.candyFarm
playerEffects.candyFarm = function(active)
    if active and state.castleFarm then
        state.castleFarm = false
        if toggles.castleFarm then toggles.castleFarm(false) end
        setCastleFarm(false)
    end
    state._uiRefs.originalCandyEffect(active)
end

-- Visual integrado no HUB existente: sem nova janela.
addToggle(castlePage, "castleFarm", "Iniciar caça no Castelo",
    "Persegue alvos reais, equipa primeira Tool de combate e envia ataques.", "⚔")
addToggle(castlePage, "castleHeightEnabled", "Ajustar altura ao atacar",
    "Golem: sobe perto da superficie, antes do golpe. Dracula: regra padrao. Negativo: Noclip.", "↕")
addToggle(castlePage, "castleHeightDirectDracula", "Altura imediata no Dracula",
    "Com Attack Height positivo, sobe JA ao mirar Dracula; ignora Approach Distance.", "↑")
addToggle(castlePage, "castleCombatTeleportDracula", "TP para Dracula ao atacar",
    "Opcional. Faz WALK ate o alcance de TP configurado; entao teleporta e ataca.", "⌖")
addToggle(castlePage, "castleCombatTeleportGolem", "TP para GraveGolem ao atacar",
    "Opcional e independente. Teleporta ao lado da superficie do Golem na altura configurada.", "⌖")
addToggle(castlePage, "castleAutoQ", "Usar poder Q automaticamente",
    "Intervalo e alcance configuraveis, sem tentativas duplicadas.", "Q")
addToggle(castlePage, "castleAutoApple", "Comer maca automaticamente",
    "Opcional. Se HP estiver no limite, equipa maca, ativa e volta para espada.", "✿")
addToggle(castlePage, "castleRouteBoost", "Movimento rapido nas transicoes",
    "Usa velocidade minima configurada apenas nas rotas apos Dracula e GraveGolem.", "➜")
addToggle(castlePage, "castleAutoReplay", "Repetir Castelo automaticamente",
    "Depois das recompensas, tenta clicar Corra novamente e reinicia a caça.", "↻")

-- Velocidade especial so se aplica a WALK; o teleporte nao usa WalkSpeed.
state._uiRefs.castleTravelModeCard = cardBase(castlePage, "Transicao: WALK ou TELEPORT",
    "WALK = caminho normal. TELEPORT = opcional, tenta ir ao checkpoint e a saida; se voltar, aguarda e tenta novamente.", "➜", 135)
state._uiRefs.castleWalkButton = button(state._uiRefs.castleTravelModeCard, "WALK", {
    Position = UDim2.new(0, 58, 0, 82), Size = UDim2.fromOffset(110, 34),
    BackgroundColor3 = COLORS.purple,
})
round(state._uiRefs.castleWalkButton, 8)
state._uiRefs.castleTeleportButton = button(state._uiRefs.castleTravelModeCard, "TELEPORT", {
    Position = UDim2.new(0, 175, 0, 82), Size = UDim2.fromOffset(110, 34),
    BackgroundColor3 = COLORS.panel,
})
round(state._uiRefs.castleTeleportButton, 8)
function castleRuntime.castleSetTransitionMode(mode)
    if mode ~= "Walk" and mode ~= "Teleport" then return end
    if state.castleTransitionMode == mode then return end
    state.castleTransitionMode = mode
    castleRuntime.castleTeleportContext = nil
    castleResetRoute() -- limpa rota antiga apenas na troca de modo
    state._uiRefs.castleWalkButton.BackgroundColor3 = mode == "Walk" and COLORS.purple or COLORS.panel
    state._uiRefs.castleTeleportButton.BackgroundColor3 = mode == "Teleport" and COLORS.purple or COLORS.panel
    castleStatus(mode == "Teleport" and 'TELEPORT escolhido: so nas duas transicoes'
        or 'WALK escolhido: rotas por caminho')
    print('[Poly Hub Castelo][MODO] Deslocamento de transicoes = ' .. mode)
end
state._uiRefs.castleWalkButton.MouseButton1Click:Connect(function()
    castleRuntime.castleSetTransitionMode("Walk")
end)
state._uiRefs.castleTeleportButton.MouseButton1Click:Connect(function()
    castleRuntime.castleSetTransitionMode("Teleport")
end)

-- Opcoes independentes: o modo direto prevalece somente no Dracula,
-- sem obrigar a ativacao do ajuste de altura por aproximacao.
-- Este toggle nao inicia um efeito; apenas atualiza a opcao lida pelo motor.
local function castleControl(parent, title, description, icon, field, minValue, maxValue, step, units)
    local box = cardBase(parent, title, description, icon, 113)
    local minus = button(box, "−", {
        Position = UDim2.fromOffset(58, 74), Size = UDim2.fromOffset(38, 29),
        BackgroundColor3 = COLORS.panel, TextSize = 21,
    })
    round(minus, 8)
    local input = create("TextBox", {
        Name = field, Position = UDim2.fromOffset(104, 74),
        Size = UDim2.fromOffset(90, 29), BackgroundColor3 = COLORS.panel,
        Text = tostring(state[field]), TextColor3 = COLORS.white,
        TextSize = 13, Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Center,
        ClearTextOnFocus = false, BorderSizePixel = 0,
    }, box)
    round(input, 8)
    outline(input, COLORS.line, 1, 0.25)
    local plus = button(box, "+", {
        Position = UDim2.fromOffset(202, 74), Size = UDim2.fromOffset(38, 29),
        BackgroundColor3 = COLORS.panel, TextSize = 21,
    })
    round(plus, 8)
    local suffix = txt(box, units or "studs", 11, COLORS.muted, false, {
        Position = UDim2.fromOffset(251, 77), Size = UDim2.fromOffset(100, 26),
    })
    local function repaintNumber(value)
        input.Text = (value > 0 and field == "castleHeight" and "+" or "") .. tostring(value)
        input.TextColor3 = COLORS.purple
        input.TextSize = 16
        TweenService:Create(input, TweenInfo.new(0.22), {
            TextColor3 = COLORS.white, TextSize = 13,
        }):Play()
    end
    local function update(value)
        local n = tonumber(value)
        if n == nil then
            repaintNumber(state[field])
            return
        end
        n = math.clamp((n < 0 and math.ceil(n / step - 0.5) or math.floor(n / step + 0.5)) * step, minValue, maxValue)
        state[field] = n
        repaintNumber(n)
        onSettingChanged(field, n)
        if field == "castleHeight" then castleUpdateDetails() end
        if field == "castleAppleThreshold" then castleRefreshAppleStatus() end
        if field == "castleQInterval" or field == "castleQRange" then
            castleRuntime.castleQStatusUpdatedAt = -math.huge
            castleRuntime.castleUpdateQStatus(os.clock())
        end
    end
    local function clickAnimate(ctrl)
        TweenService:Create(ctrl, TweenInfo.new(0.08), {BackgroundColor3 = COLORS.purpleDark}):Play()
        task.delay(0.09, function()
            if ctrl.Parent then
                TweenService:Create(ctrl, TweenInfo.new(0.18), {BackgroundColor3 = COLORS.panel}):Play()
            end
        end)
    end
    minus.MouseButton1Click:Connect(function()
        clickAnimate(minus)
        update(state[field] - step)
    end)
    plus.MouseButton1Click:Connect(function()
        clickAnimate(plus)
        update(state[field] + step)
    end)
    input.FocusLost:Connect(function() update(input.Text) end)
    repaintNumber(state[field])
    return input
end

castleControl(castlePage, "Alcance de Deteccao do Dracula",
    "Raio para achar Dracula, inclusive apos reaparecer no altar (padrao 250).",
    "⌖", "castleDraculaDetectionRange", 50, 500, 10)
castleControl(castlePage, "Distancia maxima para TP no Dracula",
    "Fora do raio: WALK pelo chao. Dentro do raio: TP na altura configurada. Padrao: 30 studs.",
    "⌖", "castleDraculaCombatTeleportRange", 10, 200, 5)
castleApproachInput = castleControl(castlePage,
    "Approach Distance", "Ate esta distancia corre no chao; so entao comeca o combate.",
    "➤", "castleApproach", 2, 25, 1)
castleHeightInput = castleControl(castlePage,
    "Attack Height", "TP de combate: altura relativa ao boss; no modo WALK, ajuste normal da v32.",
    "↕", "castleHeight", -20, 20, 1)
castleControl(castlePage, "Intervalo automatico do Q",
    "Segundos entre envios da tecla. Ajuste conforme cooldown real; padrao 15 segundos.",
    "Q", "castleQInterval", 5, 40, 1, "segundos")
castleControl(castlePage, "Alcance do poder Q",
    "Pode usar Q antes de entrar no alcance da espada; padrao 18 studs.",
    "Q", "castleQRange", 6, 40, 1, "studs")
state._uiRefs.castleQCard = cardBase(castlePage, "Diagnostico do poder Q",
    "Mostra contador e envio; nao confirma ativacao dentro do jogo.", "Q", 110)
state._uiRefs.castleQStatusText = txt(state._uiRefs.castleQCard,
    "Q: aguardando", 11, COLORS.success, true, {
    Position = UDim2.fromOffset(58, 68),
    Size = UDim2.new(1, -76, 0, 26),
    TextTruncate = Enum.TextTruncate.AtEnd,
})
castleRuntime.castleQStatusUpdatedAt = -math.huge
castleRuntime.castleUpdateQStatus(os.clock())
castleControl(castlePage, "Velocidade na Rota",
    "Minimo temporario apenas no modo WALK. Restaura no fim.",
    "➜", "castleRouteSpeed", 12, 50, 2, "studs/s")
castleControl(castlePage, "Usar maca com HP abaixo de",
    "Percentual de vida para usar a maca, por exemplo 50 ou 70.",
    "✿", "castleAppleThreshold", 5, 95, 5, "% HP")

state._uiRefs.castleAppleNameCard = cardBase(castlePage, "Nome da maca (opcional)",
    "Vazio: procura Apple / Maca / Maçã nas Tools. Para nome diferente, digite-o.", "✿", 112)
state._uiRefs.castleAppleNameBox = create("TextBox", {
    Name = "CastleAppleName", Position = UDim2.fromOffset(58, 73),
    Size = UDim2.new(1, -76, 0, 28), BackgroundColor3 = COLORS.panel,
    Text = state.castleAppleName, PlaceholderText = "Automatico (Apple / Maçã)",
    TextColor3 = COLORS.white, PlaceholderColor3 = COLORS.muted,
    TextSize = 12, Font = Enum.Font.Gotham, ClearTextOnFocus = false,
    TextXAlignment = Enum.TextXAlignment.Left, BorderSizePixel = 0,
}, state._uiRefs.castleAppleNameCard)
round(state._uiRefs.castleAppleNameBox, 8)
outline(state._uiRefs.castleAppleNameBox, COLORS.line, 1, 0.25)
create("UIPadding", {PaddingLeft = UDim.new(0, 10)}, state._uiRefs.castleAppleNameBox)
state._uiRefs.castleAppleNameBox.FocusLost:Connect(function()
    state.castleAppleName = state._uiRefs.castleAppleNameBox.Text:match("^%s*(.-)%s*$") or ""
    castleRuntime.castleAppleNextAt = 0
    onSettingChanged("castleAppleName", state.castleAppleName)
    castleRefreshAppleStatus("nome de ferramenta atualizado")
end)

-- Saida fixa confirmada: sem inputs X/Y/Z, sem captura ou botao de salvar.
-- O Auto Farm usa diretamente CASTLE_CONFIG.finalExitPosition para a rota.
state._uiRefs.castleFinalCard = cardBase(castlePage, "Saida apos GraveGolem",
    "Destino fixo: WALK ou TELEPORT conforme modo escolhido.", "➤", 110)
txt(state._uiRefs.castleFinalCard, "X: 6502.43  |  Y: 258.94  |  Z: -6000.00", 12,
    COLORS.success, true, {
    Position = UDim2.fromOffset(58, 67),
    Size = UDim2.new(1, -80, 0, 25),
})

state._uiRefs.castleProgressCard = cardBase(castlePage, "Etapas do Castelo",
    "Dracula > janela > gatilho > GraveGolem > saida > recompensa > replay.", "♛", 112)
castlePhaseText = txt(state._uiRefs.castleProgressCard, "Etapa: 1/3 - Dracula (fuga em ~50% HP)", 11, COLORS.white, true, {
    Position = UDim2.fromOffset(58, 68), Size = UDim2.new(1, -72, 0, 20),
})

state._uiRefs.castleStatusCard = cardBase(castlePage, "Status do combate",
    "Acompanhamento dos modelos, atributos e tentativas de cura.", "▥", 189)
castleStatusText = txt(state._uiRefs.castleStatusCard, "Estado: desativado", 11, COLORS.success, true, {
    Position = UDim2.fromOffset(58, 66), Size = UDim2.new(1, -74, 0, 19),
    TextTruncate = Enum.TextTruncate.AtEnd,
})
castleTargetText = txt(state._uiRefs.castleStatusCard, "Alvo: nenhum", 10, COLORS.white, false, {
    Position = UDim2.fromOffset(58, 90), Size = UDim2.new(1, -74, 0, 19),
    TextTruncate = Enum.TextTruncate.AtEnd,
})
castleAttackText = txt(state._uiRefs.castleStatusCard, "Ataques enviados: 0 | Altura: +0", 10, COLORS.muted, false, {
    Position = UDim2.fromOffset(58, 112), Size = UDim2.new(1, -74, 0, 19),
})
castleNoclipText = txt(state._uiRefs.castleStatusCard, "Noclip de combate: desligado", 10, COLORS.muted, false, {
    Position = UDim2.fromOffset(58, 136), Size = UDim2.new(1, -74, 0, 19),
})
castleAppleStatusText = txt(state._uiRefs.castleStatusCard, "Auto Maca: OFF | HP <= 50% | aguardando", 10, COLORS.muted, false, {
    Position = UDim2.fromOffset(58, 160), Size = UDim2.new(1, -74, 0, 20),
    TextTruncate = Enum.TextTruncate.AtEnd,
})
castleUpdateDetails()
castleRefreshAppleStatus()

-- Aba Player: apenas os controles Noclip, Speed e Infinite Jump.

-- PLAYER: recursos executados localmente para teste em sua própria experiência.
local originalCollisions = setmetatable({}, {__mode = "k"})
local speedHumanoid = nil
local originalSpeed = nil

local function getHumanoid()
    local character = localPlayer.Character
    if not character then return nil end
    return character:FindFirstChildOfClass("Humanoid")
end

local function restoreCollisions()
    for part, wasCollidable in pairs(originalCollisions) do
        if part and part.Parent then
            part.CanCollide = wasCollidable
        end
        originalCollisions[part] = nil
    end
end

local function applyNoclip()
    local character = localPlayer.Character
    if not character then return end
    for _, descendant in ipairs(character:GetDescendants()) do
        if descendant:IsA("BasePart") then
            if originalCollisions[descendant] == nil then
                originalCollisions[descendant] = descendant.CanCollide
            end
            descendant.CanCollide = false
        end
    end
end

-- Compartilha um unico mecanismo entre Noclip manual e Noclip do Castelo.
castleNoclipApply = applyNoclip
castleNoclipRestore = restoreCollisions

local function restoreSpeed()
    if speedHumanoid and speedHumanoid.Parent and originalSpeed ~= nil then
        speedHumanoid.WalkSpeed = originalSpeed
        experienceSpeed = originalSpeed
    end
    speedHumanoid = nil
    originalSpeed = nil
end

local function applySpeed()
    if not state.speedEnabled then return end
    local humanoid = getHumanoid()
    if not humanoid or humanoid.Health <= 0 then return end
    if speedHumanoid ~= humanoid then
        speedHumanoid = humanoid
        originalSpeed = humanoid.WalkSpeed
        experienceSpeed = originalSpeed
        if not speedWasCustomized then
            state.speedValue = experienceSpeed
        end
    end
    -- A aba Player nao pode anular o boost de rota a cada Heartbeat.
    -- Fora das transicoes, Speed continua usando somente o valor escolhido.
    local duringRoute = state.castleFarm and state.castleRouteBoost
        and state.castleTransitionMode == "Walk"
        and (castlePhase == 'trigger' or castlePhase == 'finish_route')
    humanoid.WalkSpeed = duringRoute and math.max(state.speedValue, state.castleRouteSpeed)
        or state.speedValue
end

playerEffects.noclip = function(active)
    if active then
        applyNoclip()
    elseif not castleTempNoclip then
        -- Se o Castelo ainda precisa atravessar o chao, nao restaure colisao.
        restoreCollisions()
    end
end

playerEffects.speedEnabled = function(active)
    if active then
        applySpeed()
    else
        restoreSpeed()
    end
end

playerEffects.infiniteJump = function(_active)
    -- O evento JumpRequest é ligado uma única vez abaixo.
end

addToggle(playerPage, "noclip", "Noclip", "Atravessa peças com colisão do personagem local.", "◇")
addToggle(playerPage, "speedEnabled", "Speed", "Ativa a velocidade escolhida abaixo.", "➤")

state._uiRefs.speedCard = cardBase(playerPage, "Valor do Speed", "Padrão: velocidade da experiência. Ajuste com + / −.", "▥", 102)
state._uiRefs.speedMinus = button(state._uiRefs.speedCard, "−", {
    Position = UDim2.new(1, -181, 0, 61), Size = UDim2.fromOffset(34, 29),
    BackgroundColor3 = COLORS.panel, TextSize = 20,
})
round(state._uiRefs.speedMinus, 8)
local speedInput = create("TextBox", {
    Name = "SpeedInput", Position = UDim2.new(1, -140, 0, 61),
    Size = UDim2.fromOffset(88, 29), BackgroundColor3 = COLORS.panel,
    Text = tostring(state.speedValue), TextColor3 = COLORS.white,
    TextSize = 13, Font = Enum.Font.GothamBold,
    TextXAlignment = Enum.TextXAlignment.Center,
    ClearTextOnFocus = false, BorderSizePixel = 0,
}, state._uiRefs.speedCard)
round(speedInput, 8)
outline(speedInput, COLORS.line, 1, 0.2)
state._uiRefs.speedPlus = button(state._uiRefs.speedCard, "+", {
    Position = UDim2.new(1, -45, 0, 61), Size = UDim2.fromOffset(34, 29),
    BackgroundColor3 = COLORS.panel, TextSize = 20,
})
round(state._uiRefs.speedPlus, 8)

-- Animação breve em botões. A revisão impede que cliques rápidos
-- deixem escalas ou cores presas em um estado intermediário.
local pressVersions = setmetatable({}, {__mode = "k"})
local function animatePress(control, highlight, normalColor)
    local scaler = control:FindFirstChild("PressScale")
    if not scaler then
        scaler = create("UIScale", {Name = "PressScale", Scale = 1}, control)
    end
    local version = (pressVersions[control] or 0) + 1
    pressVersions[control] = version
    TweenService:Create(scaler, TweenInfo.new(0.085, Enum.EasingStyle.Quad), {Scale = 0.87}):Play()
    TweenService:Create(control, TweenInfo.new(0.085), {BackgroundColor3 = highlight}):Play()
    task.delay(0.09, function()
        if pressVersions[control] ~= version or not control.Parent then return end
        TweenService:Create(scaler, TweenInfo.new(0.23, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1}):Play()
        TweenService:Create(control, TweenInfo.new(0.28), {BackgroundColor3 = normalColor}):Play()
    end)
end

local speedTextVersion = 0
local function animateSpeedValue()
    speedTextVersion += 1
    local version = speedTextVersion
    speedInput.TextColor3 = COLORS.purple
    speedInput.TextSize = 17
    task.delay(0.075, function()
        if version ~= speedTextVersion or not speedInput.Parent then return end
        TweenService:Create(speedInput, TweenInfo.new(0.26, Enum.EasingStyle.Quad), {
            TextColor3 = COLORS.white, TextSize = 13,
        }):Play()
    end)
end

local function setSpeedValue(value, restoreDefault)
    local numberValue = tonumber(value)
    if not numberValue then
        speedInput.Text = tostring(state.speedValue)
        return
    end
    local minAllowed = math.min(16, experienceSpeed)
    local maxAllowed = math.max(100, experienceSpeed)
    if restoreDefault then
        -- Ao restaurar, preserve o valor do proprio jogo, mesmo fora de 16-100.
        state.speedValue = numberValue
    else
        state.speedValue = math.clamp(math.floor(numberValue + 0.5), minAllowed, maxAllowed)
    end
    speedWasCustomized = not restoreDefault
    speedInput.Text = tostring(state.speedValue)
    onSettingChanged("speedValue", state.speedValue)
    if state.speedEnabled then applySpeed() end
    animateSpeedValue()
end

state._uiRefs.speedMinus.MouseButton1Click:Connect(function()
    animatePress(state._uiRefs.speedMinus, COLORS.purpleDark, COLORS.panel)
    setSpeedValue(state.speedValue - 4)
end)
state._uiRefs.speedPlus.MouseButton1Click:Connect(function()
    animatePress(state._uiRefs.speedPlus, COLORS.purpleDark, COLORS.panel)
    setSpeedValue(state.speedValue + 4)
end)
speedInput.FocusLost:Connect(function()
    setSpeedValue(speedInput.Text)
end)

addToggle(playerPage, "infiniteJump", "Infinite Jump", "Permite novos saltos enquanto estiver no ar.", "↑")

-- O Noclip deve ocorrer antes da simulação física de cada frame.
local noclipConnection = RunService.Stepped:Connect(function()
    if state.noclip or castleTempNoclip then
        applyNoclip()
    end
end)

-- O evento JumpRequest é disparado quando o jogador aperta a tecla de pulo.
local jumpConnection = UserInputService.JumpRequest:Connect(function()
    if not state.infiniteJump then return end
    local humanoid = getHumanoid()
    if humanoid and humanoid.Health > 0 then
        humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
    end
end)

-- Preserva recursos ativos depois do respawn.
local characterConnection = localPlayer.CharacterAdded:Connect(function(character)
    -- Marcacao PASSIVA: o loop deve decidir quando o novo corpo esta vivo,
    -- sem acionar MoveTo, saltos, Q ou combate a partir deste evento.
    if state.castleFarm then
        castleRuntime.castlePendingRespawnCharacter = character
        castleRuntime.castlePendingRespawnHumanoid = nil
        castleRuntime.castlePendingRespawnAt = os.clock()
        print('[Poly Hub Castelo][CICLO] CharacterAdded: aguardando liberacao da interface')
    end
    -- Ao renascer, a geometria antiga nao se aplica ao novo corpo.
    castleClearVertical()
    originalCollisions = setmetatable({}, {__mode = "k"})
    speedHumanoid = nil
    originalSpeed = nil
    task.defer(function()
        local humanoid = character:WaitForChild("Humanoid", 8)
        if not humanoid or localPlayer.Character ~= character then return end
        experienceSpeed = humanoid.WalkSpeed
        if not speedWasCustomized then
            state.speedValue = experienceSpeed
            speedInput.Text = tostring(state.speedValue)
        end
        if state.speedEnabled then applySpeed() end
    end)
end)

state._uiRefs.settingsCard = cardBase(settingsPage, "Atalho do hub", "RightShift exibe ou esconde a interface.", "⌨", 87)
state._uiRefs.infoCard = cardBase(settingsPage, "Execução local", "Recursos Player agem no personagem local; jogos com regras no servidor podem substituir essas alterações.", "ⓘ", 95)

-- Mantém o Speed ativo sem exibir cartões de estatísticas pessoais.
local updateAccumulator = 0
local renderConnection = RunService.Heartbeat:Connect(function(dt)
    updateAccumulator += dt
    if updateAccumulator < 0.35 then return end
    updateAccumulator = 0
    if state.speedEnabled then
        applySpeed()
    else
        -- O jogo pode mudar a velocidade por seus proprios scripts.
        -- Enquanto desativado, seguimos o valor real sem sobrescrever.
        local humanoid = getHumanoid()
        if humanoid and humanoid.Health > 0 and humanoid.WalkSpeed ~= experienceSpeed then
            experienceSpeed = humanoid.WalkSpeed
            if not speedWasCustomized and not speedInput:IsFocused() then
                state.speedValue = experienceSpeed
                speedInput.Text = tostring(state.speedValue)
            end
        end
    end
end)

-- Arrastar a janela pelo cabeçalho.
local dragging = false
local dragStart
local startPosition
local currentDragInput
header.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPosition = window.Position
        currentDragInput = input
    end
end)
header.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
        currentDragInput = input
    end
end)
local dragChanged = UserInputService.InputChanged:Connect(function(input)
    if dragging and input == currentDragInput and dragStart and startPosition then
        local delta = input.Position - dragStart
        window.Position = UDim2.new(startPosition.X.Scale, startPosition.X.Offset + delta.X / scale.Scale,
            startPosition.Y.Scale, startPosition.Y.Offset + delta.Y / scale.Scale)
    end
end)
local dragEnded = UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = false
    end
end)

-- Minimiza somente a janela, deixando o botao flutuante operante.
minimize.MouseButton1Click:Connect(function()
    window.Visible = false
    local opener = screenGui:FindFirstChild("ReabrirPolyHub")
    if opener then opener.Visible = true end
    print("[Poly Hub v26][UI] MINIMIZADO pelo botao")
end)

-- Limpa conexões também quando a GUI é substituída por outra execução.
local function cleanup()
    -- Cancela a caçada, o movimento pendente e as propriedades locais.
    state.candyFarm = false
    setGhostFarm(false)
    state.castleFarm = false
    setCastleFarm(false)
    state.noclip = false
    state.speedEnabled = false
    state.infiniteJump = false
    restoreCollisions()
    restoreSpeed()
    if state._uiHotkeyConnection then state._uiHotkeyConnection:Disconnect() end
    dragChanged:Disconnect()
    dragEnded:Disconnect()
    renderConnection:Disconnect()
    noclipConnection:Disconnect()
    jumpConnection:Disconnect()
    characterConnection:Disconnect()
    changeCameraConnection:Disconnect()
    if cameraConnection then cameraConnection:Disconnect() end
end
screenGui.Destroying:Connect(cleanup)
close.MouseButton1Click:Connect(function()
    screenGui:Destroy()
end)

selectTab("auto")
window.Visible = true
print("[Poly Hub v37] Castelo: Dracula > cutscene > gatilho > GraveGolem > saida > recompensas > replay; ativa nova corrida automaticamente. RightShift: UI.")

-- ================================================================
-- POLY HUB v38 MODULAR: independent modules adapted from the supplied Poly Loot source
-- ================================================================
local function installPolyLootModules()
-- POLY LOOT V6.0 | OASISUI | DUNGEON + MAIN WORLD + AUTO SELL
-- Release version: V6.0 | Based on V5.10.6 (no gameplay logic changes)
-- V5.10.4: World Boss UI simplified; boss combat and automation logic unchanged.
-- V5.10.2: Restore classic Single Enemy Farm distances/teleport logic from V5.9.6.
-- No TweenService or teleport/activation diagnostics. Auto Sell separate tab preserved.
-- POLY LOOT V6.0 | OASISUI | 24H KEY
-- ============================================
-- POLY LOOT | DUNGEON SPEEDRUN V5.5 OASISUI + ANTI-AFK

-- ============================================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Integrated Poly Hub build: no external key server or remote UI dependency.
-- The source modules are local components of this single hub.
local accessGranted = true
local accessKey = "integrated"
local accessDeadline = math.huge
local nextServerCheck = math.huge
local accessBusy = false
local consecutiveRecheckFailures = 0
local lastSuccessfulServerCheck = os.clock()


-- ============================================
-- EINSTELLUNGEN

-- ============================================
local CFG = {}
-- Equipped combat tool is detected automatically.
-- Add utility/non-combat Tool names here to avoid using them as weapons.
CFG.NON_WEAPON_TOOLS = {
    ["halloween dungeon 2026"] = true,
    ["ghostnet"] = true,
}
-- Kampf
CFG.ATTACK_DISTANCE = 2
CFG.ATTACK_INTERVAL = 0.65
CFG.ATTACK_STABILIZE = 0.12
CFG.TARGET_SEARCH_RADIUS = 140
CFG.REPOSITION_DISTANCE = 3.5
CFG.REPOSITION_INTERVAL = 0.35
-- Bewegungs-Vorhersage
CFG.PREDICTION_TIME = 0.04
CFG.MAX_PREDICTION = 0.8
-- Anti-Stuck
CFG.NO_DAMAGE_TIMEOUT = 12
CFG.ENEMY_RETRY_DELAY = 5
-- Navigation | V5.3: direct-only crossings, bounded quick retries.
CFG.DOOR_TELEPORT_DISTANCE = 12
-- V5.4: the visible Room notification may arrive after the character crossed.
-- Give the game a chance to report the room before forcing another teleport.
CFG.ROOM_CONFIRM_TIMEOUT = 3.4
CFG.ROOM_RETRY_DELAY = 0.35
CFG.ROOM_TRANSITION_DELAY = 0.4
CFG.ROOM_MAX_CROSS_ATTEMPTS = 3
CFG.ROOM_POSITION_CHECK_DELAY = 0.22
-- V5.5: poll after the initial check so late rollbacks are caught promptly.
CFG.ROOM_POSITION_POLL_INTERVAL = 0.10
CFG.ROOM_ROLLBACK_CONFIRM_SAMPLES = 2
CFG.ROOM_RETRY_AFTER_ROLLBACK = 0.38
CFG.ROOM_POPUP_GRACE_SECONDS = 6.0
CFG.ROOM_CROSSED_SIDE_THRESHOLD = 5.0
CFG.ROOM_CLOSE_TO_TARGET_THRESHOLD = 8.0
CFG.AUTO_ENTER_FIRST_ROOM = true

-- Auto Replay is opt-in because each successful restart costs one
-- Halloween Dungeon 2026 item. Selects available executor APIs automatically.
CFG.AUTO_REPLAY_DEFAULT = false
-- Anti-AFK is enabled by default, but only sends activity while the
-- licensed Speedrun is running. It can be toggled independently in the GUI.
CFG.ANTI_AFK_DEFAULT = true
CFG.REPLAY_CONFIRM_TIMEOUT = 15
CFG.transitionUntil = 0
CFG.DEBUG_MODE = true

-- ============================================
-- AUTOMATISCHE DROP-SAMMLUNG

-- ============================================
CFG.LOOT_SEARCH_RADIUS = 65
CFG.LOOT_TIMEOUT = 8
CFG.LOOT_SETTLE_TIME = 0.6
CFG.LOOT_PICKUP_WAIT = 0.35
CFG.AUTO_LOOT_ENABLED = true -- control independente na aba Auto Loot

-- ============================================
-- STATUS

-- ============================================
-- Main World runs as a separate exclusive automation session.
local MW: any = {
    worldFarmRunning = false,
    worldFarmMode = nil,
    worldFarmSession = 0,
    worldAutoLoot = true,
    worldDefeated = 0,
    worldAttacks = 0,
    selectedEnemyName = nil,
    enemyFarmEnabled = false,
    bossFarmEnabled = false,
    bossActive = false,
    selectedBossName = "__any_boss",
    bossKnownLabels = {},
    bossScanAt = 0,
    cachedBoss = nil,
    bossRetryUntil = 0,
    bossKills = 0,
    lastBossKillAt = 0,
}

local running = false
local sessionId = 0
local currentRoom = 0
local currentWave = 0
local totalWaves = 0
local roomCleared = false
local dungeonComplete = false
local waitingForRestart = false
local completedRuns = 0
local finalLootHandled = false
local restartRoomObserved = false
local autoReplayEnabled = CFG.AUTO_REPLAY_DEFAULT
local antiAfkEnabled = CFG.ANTI_AFK_DEFAULT
local replayAttempted = false
local replayAttemptAt = 0
local attackCount = 0
local defeatedCount = 0
local skippedEnemies = {}
local usedDoors = {}
local currentHighlight = nil
local lastRoomAttempt = 0
-- One loot inspection per room; keep direction stable across failed retries.
local lootCheckedRoom = nil
local approachRoom = nil
local approachDoor = nil
local approachDirection = nil
-- A door can be physically crossed before the game's room notification arrives.
-- Keep a short pending state so we don't teleport backwards on stale popup data.
local pendingDoor = nil
local pendingRoom = nil
local pendingDirection = nil
local pendingCrossedAt = 0
local pendingDoorLogAt = 0

local function clearPendingDoor()
    pendingDoor = nil
    pendingRoom = nil
    pendingDirection = nil
    pendingCrossedAt = 0
    pendingDoorLogAt = 0
end

-- ============================================
-- SPIELOBJEKTE

-- ============================================

local function getEnemies()
    local live = workspace:FindFirstChild("Animal_Live")
    return live and live:FindFirstChild("Aggressors")
end

local function getDungeon()
    return workspace:FindFirstChild(
        "HalloweenDungeon_Chain"
    )
end

local function getCharacter()
    return player.Character
end

local function getRoot()
    local character = getCharacter()
    return character
        and character:FindFirstChild("HumanoidRootPart")
end

local function getHumanoid()
    local character = getCharacter()
    return character
        and character:FindFirstChildOfClass("Humanoid")
end

local function getWeapon()
    local character = getCharacter()
    if not character then
        return nil
    end

    -- Equipped Roblox Tools are parented to the player's Character.
    -- Backpack items are intentionally ignored until equipped.
    local fallback = nil
    for _, tool in ipairs(character:GetChildren()) do
        if tool:IsA("Tool") and not CFG.NON_WEAPON_TOOLS[tool.Name:lower()] then
            -- Prefer items carrying the game's weapon attributes when available.
            if tool:GetAttribute("WeaponId") ~= nil
                or tool:GetAttribute("WeaponRank") ~= nil
                or tool:GetAttribute("_HitboxReach") ~= nil then
                return tool
            end
            fallback = fallback or tool
        end
    end
    return fallback
end

local function validSession(id)
    return running and sessionId == id and accessGranted and os.clock() < accessDeadline
end

local function debugPrint(...)
    if CFG.DEBUG_MODE then
        print("[DUNGEON V5]", ...)
    end
end

local function horizontalDistance(a, b)
    return Vector3.new(
        a.X - b.X,
        0,
        a.Z - b.Z
    ).Magnitude
end

-- ============================================
-- OASIS UI | DUNGEON SELECTION HUB
-- ============================================
-- OasisUI's demo features are NOT loaded. Only the controls below exist.
-- Keep the original 24H Key window as a separate login gate.
local oldGui = screenGui:FindFirstChild("PolyLootModuleRuntime")
if oldGui then oldGui:Destroy() end

-- Runtime folder belongs to the existing Poly Hub ScreenGui; no second window.
local gui = Instance.new("Folder")
gui.Name = "PolyLootModuleRuntime"
gui.Parent = screenGui

-- OasisUI-compatible adapter: creates native controls inside existing Poly Hub pages.
-- The original external loadstring/UI dependency is intentionally not used.
local OasisUI = {}
local moduleUnloadCallbacks = {}
local moduleUnloadRan = false

local function moduleRunUnload()
    if moduleUnloadRan then return end
    moduleUnloadRan = true
    for _, callback in ipairs(moduleUnloadCallbacks) do
        pcall(callback)
    end
end

gui.Destroying:Connect(moduleRunUnload)

local function optionValue(option)
    if type(option) == "table" then
        return option.Value or option.value or option[1] or option.Title
    end
    return option
end

local function optionTitle(option)
    if type(option) == "table" then
        return tostring(option.Title or option.Value or option.value or option[1] or "")
    end
    return tostring(option)
end

local function buildToggleControl(parent, options2, isModule, addRowFn)
    local row
    if addRowFn then
        row = addRowFn(options2.Description and 57 or 43)
    else
        row = create("Frame", {
            Size = UDim2.new(1, -2, 0, options2.Description and 68 or 54),
            BackgroundTransparency = 1,
            ClipsDescendants = false,
        }, parent)
    end
    local tile = create("Frame", {
        Size = UDim2.fromScale(1, 1), BackgroundColor3 = COLORS.card,
        BorderSizePixel = 0, ClipsDescendants = false,
    }, row)
    round(tile, 10)
    outline(tile, COLORS.line, 1, 0.3)
    local title = txt(tile, tostring(options2.Title or "Toggle"), 11, COLORS.white, true, {
        Position = UDim2.fromOffset(10, 5),
        Size = UDim2.new(1, -86, 0, options2.Description and 20 or 32),
    })
    if options2.Description then
        txt(tile, tostring(options2.Description), 9, COLORS.muted, false, {
            Position = UDim2.fromOffset(10, 26),
            Size = UDim2.new(1, -88, 0, 29), TextWrapped = true,
            TextYAlignment = Enum.TextYAlignment.Top,
        })
    end
    local active = options2.Default == true
    local toggleButton = button(tile, active and "ON" or "OFF", {
        Position = UDim2.new(1, -67, 0.5, -15),
        Size = UDim2.fromOffset(56, 30),
        BackgroundColor3 = active and COLORS.purpleDark or COLORS.panel,
        TextSize = 11,
        ZIndex = 5,
    })
    round(toggleButton, 8)
    outline(toggleButton, COLORS.line, 1)
    local control = {active = active, row = row}
    local function draw()
        toggleButton.Text = control.active and "ON" or "OFF"
        toggleButton.BackgroundColor3 = control.active and COLORS.purpleDark or COLORS.panel
    end
    function control:Get() return self.active end
    function control:Set(value, suppressCallback)
        local nextValue = value == true
        local changed = self.active ~= nextValue
        self.active = nextValue
        draw()
        if changed and not suppressCallback and type(options2.Callback) == "function" then
            local ok, err = pcall(options2.Callback, self.active)
            if not ok then warn("[Poly Hub][Module Toggle]", tostring(err)) end
        end
    end
    function control:SetVisible(value)
        self.row.Visible = value == true
    end
    toggleButton.MouseButton1Click:Connect(function()
        control:Set(not control.active, false)
    end)
    return control
end

local function makeModuleSection(tab, options)
    local sectionFrame = create("Frame", {
        Name = "ModuleSection",
        Size = UDim2.new(1, -2, 0, 54),
        BackgroundColor3 = COLORS.card,
        BorderSizePixel = 0,
        ClipsDescendants = false,
    }, tab.page)
    round(sectionFrame, 12)
    outline(sectionFrame, COLORS.line, 1, 0.25)
    txt(sectionFrame, tostring(options.Title or "Section"), 13, COLORS.white, true, {
        Position = UDim2.fromOffset(12, 10),
        Size = UDim2.new(1, -24, 0, 25),
    })
    local section = {frame = sectionFrame, nextY = 43}

    function section:_addRow(height)
        local y = self.nextY
        local row = create("Frame", {
            Position = UDim2.fromOffset(8, y),
            Size = UDim2.new(1, -16, 0, height),
            BackgroundTransparency = 1,
            ClipsDescendants = false,
            ZIndex = 2,
        }, self.frame)
        self.nextY = y + height + 7
        self.frame.Size = UDim2.new(1, -2, 0, self.nextY + 3)
        return row, y
    end

    function section:Paragraph(options2)
        local row = self:_addRow(76)
        local title = txt(row, tostring(options2.Title or "Information"), 12, COLORS.white, true, {
            Position = UDim2.fromOffset(0, 0), Size = UDim2.new(1, 0, 0, 20),
        })
        local body = txt(row, tostring(options2.Content or ""), 10, COLORS.muted, false, {
            Position = UDim2.fromOffset(0, 21), Size = UDim2.new(1, 0, 0, 52),
            TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top,
        })
        return {
            SetContent = function(_, value) body.Text = tostring(value or "") end,
            SetTitle = function(_, value) title.Text = tostring(value or "") end,
        }
    end

    function section:Label(options2)
        local row = self:_addRow(28)
        txt(row, tostring(options2.Text or "Status"), 10, COLORS.muted, false, {
            Position = UDim2.fromOffset(0, 0), Size = UDim2.new(0.48, 0, 1, 0),
        })
        local valueLabel = txt(row, tostring(options2.Value or ""), 10, COLORS.white, true, {
            Position = UDim2.new(0.48, 0, 0, 0), Size = UDim2.new(0.52, 0, 1, 0),
            TextXAlignment = Enum.TextXAlignment.Right,
            TextWrapped = true,
        })
        return {
            SetValue = function(_, value) valueLabel.Text = tostring(value or "") end,
            GetValue = function() return valueLabel.Text end,
        }
    end


    function section:Toggle(options2)
        return buildToggleControl(self.frame, options2, false, function(height)
            return self:_addRow(height)
        end)
    end

    function section:Button(options2)
        local row = self:_addRow(options2.Description and 58 or 43)
        local caption = tostring(options2.Title or "Run")
        if options2.Description then
            txt(row, caption, 10, COLORS.white, true, {
                Position = UDim2.fromOffset(0, 0), Size = UDim2.new(1, 0, 0, 19),
            })
        end
        local action = button(row, caption, {
            Position = UDim2.fromOffset(0, options2.Description and 22 or 2),
            Size = UDim2.new(1, 0, 0, 34),
            BackgroundColor3 = COLORS.panel,
            TextSize = 10,
            ZIndex = 4,
        })
        round(action, 8)
        outline(action, COLORS.line, 1)
        local confirmUntil = 0
        action.MouseButton1Click:Connect(function()
            if caption == "Sell Selected Now" then
                local now = os.clock()
                if now > confirmUntil then
                    confirmUntil = now + 5
                    action.Text = "CONFIRM SALE (click again within 5s)"
                    task.delay(5, function()
                        if action.Parent and os.clock() >= confirmUntil then action.Text = caption end
                    end)
                    return
                end
                confirmUntil = 0
                action.Text = caption
            end
            if type(options2.Callback) == "function" then
                local ok, err = pcall(options2.Callback)
                if not ok then warn("[Poly Hub][Module Button]", tostring(err)) end
            end
        end)
        return {button = action}
    end

    function section:Slider(options2)
        local row = self:_addRow(48)
        txt(row, tostring(options2.Title or "Value"), 10, COLORS.white, true, {
            Position = UDim2.fromOffset(0, 0), Size = UDim2.new(1, -80, 0, 25),
        })
        local valueBox = create("TextBox", {
            Position = UDim2.new(1, -76, 0, 0), Size = UDim2.fromOffset(76, 28),
            BackgroundColor3 = COLORS.panel, BorderSizePixel = 0,
            Text = tostring(options2.Default or options2.Min or 0),
            TextColor3 = COLORS.white, PlaceholderColor3 = COLORS.muted,
            TextSize = 11, Font = Enum.Font.Gotham, ClearTextOnFocus = false,
            ZIndex = 4,
        }, row)
        round(valueBox, 7)
        outline(valueBox, COLORS.line, 1)
        local current = tonumber(options2.Default) or tonumber(options2.Min) or 0
        local control = {}
        function control:Get() return current end
        function control:Set(value, suppressCallback)
            local n = tonumber(value)
            if not n then return end
            local minV, maxV = tonumber(options2.Min) or 0, tonumber(options2.Max) or 100
            local step = tonumber(options2.Step) or 1
            n = math.clamp(n, minV, maxV)
            if step > 0 then n = minV + math.floor((n - minV) / step + 0.5) * step end
            current = n
            valueBox.Text = tostring(n)
            if not suppressCallback and type(options2.Callback) == "function" then options2.Callback(n) end
        end
        valueBox.FocusLost:Connect(function()
            control:Set(valueBox.Text, false)
        end)
        return control
    end

    function section:Dropdown(options2)
        local row, rowY = self:_addRow(49)
        txt(row, tostring(options2.Title or "Choose"), 10, COLORS.white, true, {
            Position = UDim2.fromOffset(0, 0), Size = UDim2.new(1, 0, 0, 17),
        })
        local selectionButton = button(row, tostring(options2.Placeholder or "Choose..."), {
            Position = UDim2.fromOffset(0, 18), Size = UDim2.new(1, 0, 0, 28),
            BackgroundColor3 = COLORS.panel, TextSize = 10,
            TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 5,
        })
        round(selectionButton, 7)
        outline(selectionButton, COLORS.line, 1)
        create("UIPadding", {PaddingLeft = UDim.new(0, 9), PaddingRight = UDim.new(0, 9)}, selectionButton)
        local popup = create("Frame", {
            Position = UDim2.fromOffset(8, rowY + 49),
            Size = UDim2.new(1, -16, 0, 176),
            BackgroundColor3 = COLORS.panel, BorderSizePixel = 0,
            Visible = false, ZIndex = 20, ClipsDescendants = true,
        }, self.frame)
        round(popup, 8)
        outline(popup, COLORS.purple, 1.2)
        local searchBox
        local listTop = 5
        if options2.Search then
            searchBox = create("TextBox", {
                Position = UDim2.fromOffset(5, 5), Size = UDim2.new(1, -10, 0, 27),
                BackgroundColor3 = COLORS.card, BorderSizePixel = 0,
                PlaceholderText = "Search...", Text = "", ClearTextOnFocus = false,
                TextColor3 = COLORS.white, PlaceholderColor3 = COLORS.muted,
                TextSize = 10, Font = Enum.Font.Gotham, ZIndex = 22,
            }, popup)
            round(searchBox, 6)
            listTop = 37
        end
        local list = create("ScrollingFrame", {
            Position = UDim2.fromOffset(5, listTop), Size = UDim2.new(1, -10, 1, -listTop - 5),
            BackgroundTransparency = 1, BorderSizePixel = 0,
            ScrollBarThickness = 3, ScrollBarImageColor3 = COLORS.purple,
            CanvasSize = UDim2.fromOffset(0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
            ZIndex = 21,
        }, popup)
        create("UIListLayout", {Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder}, list)
        local values = options2.Values or {}
        local multi = options2.Multi == true
        local allowNone = options2.AllowNone ~= false
        local selected = multi and {} or optionValue(options2.Default)
        local optionButtons = {}
        local control = {}

        local function selectedSetFrom(value)
            local set = {}
            if type(value) == "string" then
                set[value] = true
            elseif type(value) == "table" then
                if type(value.Value) == "string" then set[value.Value] = true end
                if type(value.value) == "string" then set[value.value] = true end
                for key, item in pairs(value) do
                    if type(item) == "string" then set[item] = true
                    elseif type(key) == "string" and item == true then set[key] = true
                    elseif type(item) == "table" then
                        local v = optionValue(item)
                        if type(v) == "string" then set[v] = true end
                    end
                end
            end
            return set
        end
        local function updateButtonText()
            if multi then
                local count, names = 0, {}
                for _, item in ipairs(values) do
                    local val = optionValue(item)
                    if selected[val] then
                        count += 1
                        if #names < 2 then names[#names + 1] = optionTitle(item) end
                    end
                end
                for val in pairs(selected) do
                    local found = false
                    for _, item in ipairs(values) do if optionValue(item) == val then found = true break end end
                    if selected[val] and not found then count += 1 end
                end
                if count == 0 then selectionButton.Text = tostring(options2.Placeholder or "Choose items...")
                elseif count <= 2 then selectionButton.Text = table.concat(names, ", ")
                else selectionButton.Text = tostring(count) .. " selected" end
            else
                local title = nil
                for _, item in ipairs(values) do
                    if optionValue(item) == selected then title = optionTitle(item) break end
                end
                selectionButton.Text = title or tostring(options2.Placeholder or "Choose...")
            end
        end
        local function renderOptions()
            for _, itemButton in ipairs(optionButtons) do
                if itemButton.Parent then itemButton:Destroy() end
            end
            table.clear(optionButtons)
            local query = searchBox and searchBox.Text:lower() or ""
            for _, item in ipairs(values) do
                local val = optionValue(item)
                local title = optionTitle(item)
                local description = type(item) == "table" and tostring(item.Description or "") or ""
                if val ~= nil and (query == "" or title:lower():find(query, 1, true) or tostring(val):lower():find(query, 1, true) or description:lower():find(query, 1, true)) then
                    local isSelected = multi and selected[val] == true or (not multi and selected == val)
                    local itemButton = button(list, (isSelected and "✓  " or "    ") .. title, {
                        Size = UDim2.new(1, -4, 0, 28), BackgroundColor3 = isSelected and COLORS.purpleDark or COLORS.card,
                        TextSize = 10, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 22,
                    })
                    create("UIPadding", {PaddingLeft = UDim.new(0, 7)}, itemButton)
                    itemButton.MouseButton1Click:Connect(function()
                        if multi then
                            selected[val] = not selected[val]
                        else
                            if allowNone and selected == val then selected = nil else selected = val end
                            popup.Visible = false
                        end
                        updateButtonText()
                        if popup.Visible then renderOptions() end
                        if type(options2.Callback) == "function" then
                            local ok, err = pcall(options2.Callback, control:Get())
                            if not ok then warn("[Poly Hub][Dropdown]", tostring(err)) end
                        end
                    end)
                    optionButtons[#optionButtons + 1] = itemButton
                end
            end
        end
        function control:Get()
            if not multi then return selected end
            local out = {}
            local added = {}
            for _, item in ipairs(values) do
                local val = optionValue(item)
                if selected[val] then out[#out + 1] = val; added[val] = true end
            end
            for val, active in pairs(selected) do
                if active and not added[val] then out[#out + 1] = val end
            end
            return out
        end
        function control:Set(value, suppressCallback)
            if multi then
                selected = selectedSetFrom(value)
            else
                selected = optionValue(value)
            end
            updateButtonText()
            if popup.Visible then renderOptions() end
            if not suppressCallback and type(options2.Callback) == "function" then
                local ok, err = pcall(options2.Callback, control:Get())
                if not ok then warn("[Poly Hub][Dropdown Set]", tostring(err)) end
            end
        end
        function control:Refresh(nextValues, reset)
            values = type(nextValues) == "table" and nextValues or {}
            if reset == true then selected = multi and {} or nil end
            updateButtonText()
            if popup.Visible then renderOptions() end
        end
        selectionButton.MouseButton1Click:Connect(function()
            popup.Visible = not popup.Visible
            if popup.Visible then renderOptions() end
        end)
        if searchBox then searchBox:GetPropertyChangedSignal("Text"):Connect(renderOptions) end
        updateButtonText()
        renderOptions()
        return control
    end

    return section
end

function OasisUI:CreateWindow(options)
    local moduleWindow = {}
    local definitions = {
        ["Dungeon"] = {key="halloween", caption="Halloween", icon="🎃", index=6,
            title="Dungeon Halloween", subtitle="Speedrun, Auto Replay, Anti-AFK e coleta de recompensas."},
        ["Status"] = {key="halloween", caption="Halloween", icon="🎃", index=6,
            title="Dungeon Halloween", subtitle="Speedrun, Auto Replay, Anti-AFK e coleta de recompensas."},
        ["Main World"] = {key="mainworld", caption="Main World", icon="🌐", index=7,
            title="Main World", subtitle="Farm de um inimigo, World Bosses e coleta de drops."},
        ["Auto Loot"] = {key="autoloot", caption="Auto Loot", icon="◇", index=8,
            title="Auto Loot", subtitle="Controles independentes de coleta para cada ambiente."},
        ["Auto Sell"] = {key="autosell", caption="Auto Sell", icon="$", index=9,
            title="Auto Sell", subtitle="Filtros por raridade, proteção de itens e venda configurável."},
    }
    local function ensureTab(definition)
        if not pages[definition.key] then
            pageMeta[definition.key] = {definition.title, definition.subtitle}
            scrollPage(definition.key)
            local nav = navItem(definition.key, definition.icon, definition.caption, definition.index)
            nav.MouseButton1Click:Connect(function() selectTab(definition.key) end)
        end
    end
    function moduleWindow:Tab(options2)
        local definition = definitions[tostring(options2.Title or "Dungeon")] or definitions.Dungeon
        ensureTab(definition)
        return {
            page = pages[definition.key],
            Section = function(tab, sectionOptions) return makeModuleSection(tab, sectionOptions or {}) end,
            Module = function(tab, moduleOptions)
                return buildToggleControl(tab.page, moduleOptions or {}, true, nil)
            end,
        }
    end
    function moduleWindow:SetVisible(value)
        window.Visible = value == true
        if window.Visible then
            local opener = screenGui:FindFirstChild("ReabrirPolyHub")
            if opener then opener.Visible = false end
        end
    end
    function moduleWindow:SetSubtitle(value)
        if pageMeta.halloween then
            pageMeta.halloween[2] = tostring(value or "")
            if selectedTab == "halloween" then pageSubtitle.Text = pageMeta.halloween[2] end
        end
    end
    function moduleWindow:OnUnload(callback)
        if type(callback) == "function" then table.insert(moduleUnloadCallbacks, callback) end
    end
    return moduleWindow
end

function OasisUI:OnUnload(callback)
    if type(callback) == "function" then table.insert(moduleUnloadCallbacks, callback) end
end

local Window = OasisUI:CreateWindow({Title="POLY HUB MODULES"})
-- frame.Visible is mapped to the existing hub window; no second ScreenGui is created.
local frame = setmetatable({}, {
    __index = function(_, key)
        if key == "Visible" then return window.Visible end
    end,
    __newindex = function(_, key, value)
        if key == "Visible" then Window:SetVisible(value == true) end
    end,
})

-- Make Oasis labels respond to the existing statusLabel.Text assignments.
-- This lets the combat/navigation logic stay untouched.
local function textProxy(element)
    local current = ""
    return setmetatable({}, {
        __index = function(_, key)
            if key == "Text" then return current end
        end,
        __newindex = function(_, key, value)
            if key == "Text" then
                current = tostring(value)
                element:SetValue(current:match("^[^:]+:%s*(.*)$") or current)
            end
        end,
    })
end

-- Dungeon hub architecture: selecting a dungeon reveals only its own controls.
-- To add another dungeon later, register it below and implement its engine.
local DUNGEON_ORDER = { "halloween" }
local DUNGEONS = {
    halloween = {
        Title = "Halloween Dungeon",
        Description = "Halloween Dungeon 2026 | 18 rooms and bosses",
        Icon = "skull",
    },
}

-- World controls are wired to the engine near the end of this file.
local selectedDungeonId = nil
local onSpeedrunToggle = nil   -- Implemented after the dungeon loop
local syncingSpeedrun = false

local dungeonTab = Window:Tab({ Title = "Dungeon", Icon = "swords", Columns = 1 })
local statusTab = Window:Tab({ Title = "Status", Icon = "activity", Columns = 1 })
MW.worldTab = Window:Tab({ Title = "Main World", Icon = "globe", Columns = 1 })
local autoLootTab = Window:Tab({ Title = "Auto Loot", Icon = "package", Columns = 1 })
local autoSellTab = Window:Tab({ Title = "Auto Sell", Icon = "shopping-cart", Columns = 1 })

-- ============================================
-- MAIN WORLD | SINGLE TARGET FARM V5.9.0
-- ============================================
-- One connected map, five named areas. Capture areas with existing spawn
-- markers, then lock exactly ONE spawn marker per farm session.
MW.AREAS = {"Beach", "Dark Forest", "Jungle", "Cave", "Grasslands"}
MW.AREA_MAP_FILE = "PolyLoot_AreaSpawns_v1.json"
MW.areaMarks = {}
MW.selectedArea = nil
MW.selectedEnemyName = nil
MW.lockedSpawn = nil
MW.worldGuiSync = false
MW.worldUiRefreshing = false
MW.worldAutoLoot = true
MW.preferredWeaponName = nil
MW.lastBossRangeWarning = 0
MW.lastBossSignature = ""
MW.nextBossStallWarning = 0
MW.bossUiRefreshing = false

local function singleChoice(value)
    if typeof(value)=="string" then return value end
    if type(value)=="table" then return value.Value or value.value or value[1] end
    return nil
end

function MW.validArea(area)
    for _,name in ipairs(MW.AREAS) do
        if name==area then return true end
    end
    return false
end

function MW.markerKey(part)
    local animal=part:GetAttribute("Animal")
    if not part:IsA("BasePart") or type(animal)~="string" then return nil end
    return string.format("%s|%d|%d",animal,math.floor(part.Position.X+0.5),math.floor(part.Position.Z+0.5))
end

function MW.loadAreaMarkers()
    if type(readfile)~="function" then return end
    local ok,data=pcall(function()
        local txt=readfile(MW.AREA_MAP_FILE)
        return game:GetService("HttpService"):JSONDecode(txt)
    end)
    if not ok or type(data)~="table" or type(data.marks)~="table" then return end
    local loaded=0
    for key,mark in pairs(data.marks) do
        if loaded>=1500 then break end
        if type(key)=="string" and type(mark)=="table" and MW.validArea(mark.area)
            and type(mark.animal)=="string" and type(mark.x)=="number" and type(mark.z)=="number" then
            MW.areaMarks[key]=mark
            loaded+=1
        end
    end
    print("[WORLD][SINGLE] Area mapping loaded:",loaded,"spawn markers")
end
MW.loadAreaMarkers()

MW.selectionSection=MW.worldTab:Section({Title="Single Enemy Farm",Icon="target"})
MW.selectionInfo=MW.selectionSection:Paragraph({
    Title="One area. One enemy type. One spawn locked.",
    Content="Choose an Area and Enemy, then stand near the spawn. "..
        "The nearest spawn stays locked, except while a verified World Boss is active.",
    Icon="info"
})
MW.areaDropdown=MW.selectionSection:Dropdown({
    Title="Area",
    Values={
        {Title="Beach",Value="Beach"},
        {Title="Dark Forest",Value="Dark Forest"},
        {Title="Jungle",Value="Jungle"},
        {Title="Cave",Value="Cave"},
        {Title="Grasslands",Value="Grasslands"},
    },
    Multi=false,Search=false,AllowNone=true,
    Placeholder="Select an area...",
    Callback=function(selection)
        if MW.worldUiRefreshing then return end
        local area=singleChoice(selection)
        if not MW.validArea(area) then area=nil end
        if area~=MW.selectedArea then
            if MW.setWorldFarmMode then MW.setWorldFarmMode("enemy",false) end
            MW.selectedArea=area
            MW.selectedEnemyName=nil
            if MW.refreshAreaEnemies then MW.refreshAreaEnemies() end
        end
    end,
})
MW.enemyDropdown=MW.selectionSection:Dropdown({
    Title="Enemy Name", Values={}, Multi=false, Search=true, AllowNone=true,
    Placeholder="Choose an enemy in this area...",
    Callback=function(selection)
        if MW.worldUiRefreshing then return end
        local enemy=singleChoice(selection)
        if enemy~=MW.selectedEnemyName then
            if MW.setWorldFarmMode then MW.setWorldFarmMode("enemy",false) end
            MW.selectedEnemyName=enemy
        end
    end,
})
MW.selectionSection:Button({
    Title="Capture Nearby Spawns for Selected Area",
    Description="Only needed if area mapping is missing. Stand within your area; capture nearby spawn markers.",
    Icon="map-pin",
    Callback=function()
        if MW.captureAreaMarkers then MW.captureAreaMarkers() end
    end,
})
MW.selectionSection:Button({
    Title="Refresh Enemy Names",
    Icon="refresh-cw",
    Callback=function() if MW.refreshAreaEnemies then MW.refreshAreaEnemies() end end,
})
MW.worldEnemiesModule=MW.worldTab:Module({
    Title="Auto Farm Single Enemy",
    Description="Lock one spawn marker, defeat its NPC, collect loot and wait for its respawn.",
    Icon="swords", Default=false, Keybind=false,
    Callback=function(enabled)
        if MW.onWorldFarmToggle then MW.onWorldFarmToggle("enemy",enabled) end
    end,
})
-- World Boss controls. Existing combat scheduling is unchanged.
-- Boss names are dynamically discovered from explicit boss NPC metadata/folders.
MW.bossSection=MW.worldTab:Section({Title="World Boss",Icon="crown"})
MW.bossDropdown=MW.bossSection:Dropdown({
    Title="World Boss",
    Values={{Title="Any detected World Boss",Value="__any_boss"}},
    Default="__any_boss",Multi=false,Search=true,AllowNone=false,
    Placeholder="Choose boss or Any detected Boss",
    Callback=function(selection)
        if MW.bossUiRefreshing then return end
        local name=singleChoice(selection)
        if type(name)=="string" and name~="" then
            MW.selectedBossName=(name=="__any_boss") and name or MW.canonicalBossName(name)
            MW.bossRetryUntil=0
            MW.lastBossSignDisplay=nil
            if MW.showSelectedBossSignTimer then MW.showSelectedBossSignTimer() end
            print("[WORLD][BOSS] Selected",name)
        end
    end,
})
MW.bossModule=MW.worldTab:Module({
    Title="Auto Farm World Boss",
    Description="Watch for the selected World Boss and farm it when available.",
    Icon="crown",Default=false,Keybind=false,
    Callback=function(enabled)
        if MW.setWorldFarmMode then MW.setWorldFarmMode("boss",enabled) end
    end,
})
MW.bossSection:Button({
    Title="Refresh Known Bosses",
    Description="Refresh bosses identified by Tier=Boss or verified boss flags. Choose Any if waiting for respawn.",
    Icon="refresh-cw",
    Callback=function()
        if MW.refreshBossList then MW.refreshBossList(true) end
    end,
})
MW.bossStatusLabel=MW.bossSection:Label({Text="Boss status",Value="Boss farm off"})
MW.bossKillsLabel=MW.bossSection:Label({Text="Bosses defeated",Value="0"})
MW.bossTimerLabel=MW.bossSection:Label({Text="Selected boss respawn (sign)",Value="Select a boss to view its sign timer"})

-- Boss respawn timers are read from in-world signs, not estimated from kill time.
-- Verified structure: Workspace.SkullcrabSign.Sign.Sign.SurfaceGui.BossName/TIMER.
-- Other boss signs are located by their own BossName text; never display one
-- boss's TIMER for a different selected boss. Signs can stream in/out.
MW.bossSignCache = {}        -- normalized BossName -> SurfaceGui
MW.bossSignScanAt = 0
MW.lastBossSignDisplay = nil

-- Boss NPC attributes and physical respawn signs may use different names.
-- Confirmed alias: Animal="TripleCobra" and sign="Triple Head Cobra"
-- denote the same world boss. Canonicalize before listing, selecting or reading signs.
function MW.canonicalBossName(value)
    if type(value) ~= "string" then return nil end
    local trimmed = value:match("^%s*(.-)%s*$")
    if trimmed == "" then return nil end
    local key = trimmed:lower():gsub("[%s%p_]+", "")
    if key == "triplecobra" or key == "tripleheadcobra" then
        return "Triple Head Cobra"
    end
    return trimmed
end

function MW.bossSignKey(value)
    local canonical = MW.canonicalBossName(value)
    if not canonical then return nil end
    local key = canonical:lower():gsub("[%s%p_]+", "")
    if key == "" then return nil end
    return key
end

function MW.signLabelText(instance)
    if not instance or not (instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox")) then
        return nil
    end
    local ok, result = pcall(function() return instance.Text end)
    if not ok or type(result) ~= "string" then return nil end
    return result:match("^%s*(.-)%s*$")
end

function MW.inspectBossSign(surface)
    if not surface or not (surface:IsA("SurfaceGui") or surface:IsA("BillboardGui")) then return nil end
    local name = MW.signLabelText(surface:FindFirstChild("BossName",true))
    local timer = surface:FindFirstChild("TIMER",true)
    if not name or name == "" or not timer or not MW.bossSignKey(name) then return nil end
    local timeText = MW.signLabelText(timer)
    return name,timeText
end

function MW.rememberBossSign(surface)
    local rawName,timer=MW.inspectBossSign(surface)
    local name=MW.canonicalBossName(rawName)
    if not name then return false end
    local key=MW.bossSignKey(name)
    MW.bossSignCache[key]=surface
    -- Prefer the display name from the sign, but keep one canonical boss entry.
    if not MW.bossKnownLabels[name] then
        MW.bossKnownLabels[name]=true
        return true
    end
    return false
end

function MW.discoverBossSigns(force)
    local now=os.clock()
    if not force and now < MW.bossSignScanAt then return end
    MW.bossSignScanAt=now+8
    local newNames=false
    -- Explicit first: all top-level sign objects, including SkullcrabSign and
    -- potential CursedOwlSign / Cursed OwlSign without assuming either exists.
    for _,child in ipairs(workspace:GetChildren()) do
        if child.Name:lower():find("sign",1,true) then
            local panel=child:FindFirstChild("SurfaceGui",true)
            if panel and MW.rememberBossSign(panel) then newNames=true end
        end
    end
    -- Fallback for signs nested within area models. Infrequent (8 seconds)
    -- to avoid repeatedly traversing the entire streamed Workspace.
    for _,obj in ipairs(workspace:GetDescendants()) do
        if (obj:IsA("SurfaceGui") or obj:IsA("BillboardGui")) and
           obj:FindFirstChild("BossName",true) and obj:FindFirstChild("TIMER",true) then
            if MW.rememberBossSign(obj) then newNames=true end
        end
    end
    if newNames and MW.refreshBossList then
        task.defer(function() if gui.Parent then MW.refreshBossList(true) end end)
    end
end

function MW.readSelectedBossSign()
    local selected=MW.selectedBossName
    if type(selected)~="string" or selected=="" or selected=="__any_boss" then
        return nil,"choose a specific boss"
    end
    local key=MW.bossSignKey(selected)
    local surface=key and MW.bossSignCache[key]
    if surface and not surface:IsDescendantOf(workspace) then
        MW.bossSignCache[key]=nil
        surface=nil
    end
    if not surface then
        -- Force a new search on explicit boss changes, otherwise throttled.
        MW.discoverBossSigns(false)
        surface=key and MW.bossSignCache[key]
    end
    if not surface then return nil,"sign not streamed in (approach boss area)" end
    local realName,timer=MW.inspectBossSign(surface)
    if not realName or MW.bossSignKey(realName)~=key then
        MW.bossSignCache[key]=nil
        return nil,"boss name on sign changed"
    end
    if not timer or timer=="" then return nil,"TIMER label empty" end
    return timer,nil
end

function MW.showSelectedBossSignTimer()
    local selected=MW.selectedBossName
    local display
    if type(selected)~="string" or selected=="" or selected=="__any_boss" then
        display="Choose a specific boss to view its respawn timer"
    else
        local timeText,reason=MW.readSelectedBossSign()
        display=timeText and (selected..": "..timeText)
            or (selected..": sign unavailable ("..tostring(reason or "unknown")..")")
    end
    if display~=MW.lastBossSignDisplay then
        MW.lastBossSignDisplay=display
        MW.bossTimerLabel:SetValue(display)
    end
end

local autoLootStatusLabel = nil
local mainWorldLootToggle = nil
local function updateAutoLootStatus(message)
    if autoLootStatusLabel then
        if message then
            autoLootStatusLabel:SetValue(message)
        else
            autoLootStatusLabel:SetValue(string.format("Halloween: %s | Main World: %s | Castelo: %s",
                CFG.AUTO_LOOT_ENABLED and "ON" or "OFF",
                MW.worldAutoLoot and "ON" or "OFF",
                state.castleAutoLoot and "ON" or "OFF"))
        end
    end
end

MW.worldLootToggle=MW.worldTab:Section({Title="Loot",Icon="package"}):Toggle({
    Title="Auto Collect Loot",
    Description="Collect drops from the locked enemy only.",
    Default=true,
    Callback=function(value)
        MW.worldAutoLoot=value==true
        if mainWorldLootToggle then mainWorldLootToggle:Set(value, true) end
        updateAutoLootStatus()
    end,
})

local autoLootSection = autoLootTab:Section({Title="Auto Loot",Icon="package"})
autoLootSection:Paragraph({
    Title="Independent collection controls",
    Content="Each toggle controls only its own environment. Halloween uses room drops, Main World collects drops from the locked enemy/boss, and Castelo only scans near GraveGolem after its defeat. Castle loot is experimental and OFF by default.",
    Icon="info",
})
autoLootSection:Toggle({
    Title="Auto Loot — Dungeon Halloween",
    Description="Collects WorldBits drops while progressing through Halloween rooms. ON by default to preserve the source module behavior.",
    Default=CFG.AUTO_LOOT_ENABLED,
    Callback=function(value)
        CFG.AUTO_LOOT_ENABLED=value==true
        updateAutoLootStatus()
        print("[AUTO LOOT][HALLOWEEN]", CFG.AUTO_LOOT_ENABLED and "ON" or "OFF")
    end,
})
mainWorldLootToggle=autoLootSection:Toggle({
    Title="Auto Loot — Main World",
    Description="Collects drops near the selected enemy or World Boss. Shares state with the Main World tab.",
    Default=MW.worldAutoLoot,
    Callback=function(value)
        MW.worldAutoLoot=value==true
        if MW.worldLootToggle then MW.worldLootToggle:Set(value, true) end
        updateAutoLootStatus()
        print("[AUTO LOOT][MAIN WORLD]", MW.worldAutoLoot and "ON" or "OFF")
    end,
})
autoLootSection:Toggle({
    Title="Auto Loot — Castelo / GraveGolem",
    Description="After the GraveGolem defeat is confirmed, scans nearby verified Pick Up drops. OFF by default; only runs during the transition, not during combat.",
    Default=state.castleAutoLoot,
    Callback=function(value)
        state.castleAutoLoot=value==true
        updateAutoLootStatus()
        print("[AUTO LOOT][CASTELO]", state.castleAutoLoot and "ON" or "OFF")
    end,
})
autoLootStatusLabel=autoLootSection:Label({Text="Status",Value="Halloween: ON | Main World: ON | Castelo: OFF"})
updateAutoLootStatus()

MW.worldStatusSection=MW.worldTab:Section({Title="Single Farm Status",Icon="activity"})
MW.worldStatusLabel=MW.worldStatusSection:Label({Text="Status",Value="Choose area + enemy"})
MW.worldTargetLabel=MW.worldStatusSection:Label({Text="Locked spawn",Value="-"})
MW.worldKillsLabel=MW.worldStatusSection:Label({Text="Defeated",Value="0"})
MW.worldAttackLabel=MW.worldStatusSection:Label({Text="Attacks",Value="0"})


-- ================================================================
-- AUTO SELL V5.9.6 | REGISTRY NAMES, RARITY FILTER, PROTECTED INSTANCE CHECKS
-- ================================================================
-- Preview is default. Real requests require an independent toggle and
-- explicit allowed names. All eligibility is recalculated before sending.
local AS = {
    enabled=false, live=false, threshold=90, selectedNames={},
    keepOne=false, pollSeconds=8, lastRun=0, busy=false, rarityFilter="All",
}
MW.AS=AS
local ReplicatedStorageAS=game:GetService("ReplicatedStorage")
local InventoryEngineAS=ReplicatedStorageAS:FindFirstChild("Inventory_Engine")
local PlayerDataAS=nil
local RegistryAS={}
local SellValueAS=nil
local ReserveAS=nil
local SellRemoteAS=nil
local replicaAS=nil
local depsOk, depsErr = pcall(function()
    if not InventoryEngineAS then error("Inventory_Engine not found") end
    local playerScripts = player:FindFirstChild("PlayerScripts")
    local dataClient = playerScripts and playerScripts:FindFirstChild("Data_Client")
    local playerDataModule = dataClient and dataClient:FindFirstChild("PlayerData")
    if not playerDataModule then error("PlayerData module unavailable") end
    PlayerDataAS = require(playerDataModule)
    local modules = InventoryEngineAS:FindFirstChild("Modules")
    if not modules then error("Inventory_Engine.Modules unavailable") end
    local registryModule = modules:FindFirstChild("ItemRegistry")
    local sellValueModule = modules:FindFirstChild("SellValue")
    if not registryModule or not sellValueModule then error("ItemRegistry/SellValue unavailable") end
    local loadedRegistry = require(registryModule)
    local loadedSellValue = require(sellValueModule)
    if type(loadedRegistry) ~= "table" or type(loadedSellValue) ~= "table" then
        error("ItemRegistry/SellValue did not return tables")
    end
    RegistryAS = loadedRegistry
    SellValueAS = loadedSellValue
    local questEngine = ReplicatedStorageAS:FindFirstChild("Quest_Engine")
    local reserveModule = questEngine and questEngine:FindFirstChild("Reserve")
    if reserveModule then ReserveAS = require(reserveModule) end
    local remotes = InventoryEngineAS:FindFirstChild("Remotes")
    SellRemoteAS = remotes and remotes:FindFirstChild("SellRequest")
end)
if not depsOk then
    warn("[AUTOSELL] Optional dependencies unavailable; Auto Sell remains disabled: " .. tostring(depsErr))
end
local AS_DEPS_AVAILABLE = depsOk and type(PlayerDataAS) == "table" and type(RegistryAS) == "table"
    and type(SellValueAS) == "table" and type(ReserveAS) == "table" and SellRemoteAS ~= nil

local function inventorySnapshot()
    if not replicaAS then
        local ok,result=pcall(function() return PlayerDataAS:WaitFor(nil,10) end)
        if ok and type(result)=="table" then replicaAS=result end
    end
    if type(replicaAS)~="table" or type(replicaAS.Data)~="table" then
        return nil,nil,"PlayerData replica unavailable"
    end
    local data=replicaAS.Data
    if type(data.Inventory)~="table" then return nil,nil,"Inventory unavailable" end
    if type(data.Inventory.Weapons)~="table" or type(data.Inventory.Armors)~="table" then
        return nil,nil,"Weapons/Armors buckets unavailable"
    end
    return data.Inventory,data,nil
end

function AS.parseNames(value)
    local set={}
    if type(value)=="string" then
        for part in value:gmatch("[^,;\r\n]+") do
            local name=part:match("^%s*(.-)%s*$")
            if name~="" then set[name:lower()]=true end
        end
    end
    return set
end

local function capacityAS()
    local inv=playerGui:FindFirstChild("Inventory")
    local space=inv and inv:FindFirstChild("InventorySpace",true)
    if not space then return nil,nil,"InventorySpace not loaded" end
    local nodes={space}
    for _,v in ipairs(space:GetDescendants()) do nodes[#nodes+1]=v end
    for _,obj in ipairs(nodes) do
        if obj:IsA("TextLabel") or obj:IsA("TextButton") then
            local x,y=obj.Text:match("(%d+)%s*/%s*(%d+)")
            x,y=tonumber(x),tonumber(y)
            if x and y and y>0 and x>=0 and x<=y then return x,y,nil end
        end
    end
    return nil,nil,"Capacity indicator unreadable"
end

local function inUseAS(serial,data)
    if type(data.Equipped)~="table" or type(data.Hotbar)~="table" then
        return true,"equipped / hotbar data unknown"
    end
    for _,slot in pairs(data.Equipped) do
        if slot==serial then return true,"equipped" end
    end
    for _,slot in pairs(data.Hotbar) do
        if slot==serial then return true,"hotbar assigned" end
    end
    local char=player.Character
    if char then
        for _,tool in ipairs(char:GetChildren()) do
            if tool:IsA("Tool") and tool:GetAttribute("InventorySerial")==serial then
                return true,"weapon currently drawn"
            end
        end
    end
    return false,nil
end

local function eligibleAS(serial,item,bucket,data)
    if type(serial)~="string" or not serial:match("^s_[%x]+_[%x]+$") then return nil,"serial missing/invalid" end
    if type(item)~="table" or type(item.Id)~="string" or item.Id=="" then return nil,"invalid item" end
    local id=item.Id:lower()
    if not AS.selectedNames[id] then return nil,"item name not selected" end
    if item.Locked~=false or item.Favorited~=false then return nil,"locked/favorite/unknown flag" end
    if item.Protected~=nil and item.Protected~=false and item.Protected~=0 then return nil,"protected item" end
    if item.Equipped==true or item.equipped==true then return nil,"equipped item" end
    if item.Serial~=nil and item.Serial~=serial then return nil,"serial mismatch" end
    if item.Source=="Starter" and bucket=="Weapons" then return nil,"starter weapon" end
    if item.Bound==nil then return nil,"binding status unknown" end
    if data.Quests and data.Quests.Story then
        local okReserve,amount=pcall(function() return ReserveAS.For(data.Quests.Story,item.Id) end)
        if not okReserve or type(amount)~="number" then return nil,"quest reservation unknown" end
        if amount>0 then return nil,"quest reserved item type" end
    end
    local definition=RegistryAS[item.Id]
    if type(definition)~="table" then return nil,"registry entry missing" end
    if bucket=="Weapons" and definition.Kind~="Weapon" then return nil,"weapon kind mismatch" end
    if bucket=="Armors" and definition.Kind~="Armor" then return nil,"armor kind mismatch" end
    if item.Count==nil or type(item.Count)~="number" or item.Count<1 or item.Count%1~=0 then
        return nil,"invalid count"
    end
    local used,reason=inUseAS(serial,data)
    if used then return nil,reason end
    local ok,price=pcall(function() return SellValueAS.For(item) end)
    if not ok or type(price)~="number" or price<=0 then return nil,"no verified sell value" end
    local qty=item.Count
    if not definition.Stackable then
        if item.Count~=1 then return nil,"unexpected unstackable count" end
        qty=1
    end
    if qty<1 then return nil,"keeping last one" end
    return {serial=serial,id=item.Id,bucket=bucket,qty=qty,price=price},nil
end

local function planAS()
    local inv,data,err=inventorySnapshot()
    if not inv then return nil,nil,err end
    local used,cap,cerr=capacityAS()
    if not used then return nil,nil,cerr end
    local candidates,skipped={},{}
    local total=0
    for _,bucket in ipairs({"Weapons","Armors"}) do
        for serial,item in pairs(inv[bucket]) do
            total+=1
            local candidate,reason=eligibleAS(serial,item,bucket,data)
            if candidate then candidates[#candidates+1]=candidate
            else skipped[reason]=(skipped[reason] or 0)+1 end
        end
    end
    table.sort(candidates,function(x,y) return x.id==y.id and x.serial<y.serial or x.id<y.id end)
    return {candidates=candidates,skipped=skipped,used=used,cap=cap,pct=100*used/cap,total=total},data,nil
end

local function statusAS(message)
    if AS.label then AS.label:SetValue(message) end
end

-- forceNow is used only for an explicit OasisUI button press.
-- It bypasses the capacity threshold and the automatic monitor toggle,
-- NEVER the license, allowlist, or item protection checks.
function AS.preview(reason,execute,forceNow)
    if AS.busy then
        statusAS("Sale already running")
        return
    end
    AS.busy=true
    local ok,err=pcall(function()
        local plan,_,problem=planAS()
        if not plan then
            statusAS("Inventory unavailable: "..tostring(problem))
            warn("[AUTOSELL]",problem)
            return
        end
        local above=plan.pct>=AS.threshold
        local mode=forceNow and "SELL NOW" or execute and "AUTO LIVE" or "DRY RUN"
        statusAS(string.format("%d/%d (%.1f%%) | %d eligible | %s",plan.used,plan.cap,plan.pct,#plan.candidates,mode))
        print("[AUTOSELL]",mode,reason,"used",plan.used,"capacity",plan.cap,"pct",plan.pct,"threshold",AS.threshold,"inventory entries",plan.total)
        for _,v in ipairs(plan.candidates) do
            print("[AUTOSELL][ITEM]",v.id,"serial",v.serial,"qty",v.qty,"unit value",v.price)
        end
        for why,n in pairs(plan.skipped) do print("[AUTOSELL][SKIP]",why,n) end
        if not forceNow and not above then
            print("[AUTOSELL] Below threshold: no requests")
            return
        end
        if not execute then
            print("[AUTOSELL] Preview only: zero remotes called")
            return
        end
        if not accessGranted or os.clock()>=accessDeadline then
            warn("[AUTOSELL] Valid license required")
            statusAS("Sale blocked: license invalid")
            return
        end
        if not forceNow and not (AS.live and AS.enabled) then
            warn("[AUTOSELL] Automatic monitor is disabled")
            return
        end
        if #plan.candidates==0 then
            statusAS("No eligible items selected")
            return
        end

        -- Manual: every eligible selected serial (subject to fresh checks).
        -- Automatic: only one per cycle to avoid outdated sale plans.
        local limit=forceNow and #plan.candidates or 1
        local sent=0
        for i=1,limit do
            if not gui.Parent or not accessGranted or os.clock()>=accessDeadline then break end
            if not forceNow and not AS.enabled then break end
            local target=plan.candidates[i]
            local inv2,data2=inventorySnapshot()
            if not inv2 or type(inv2[target.bucket])~="table" then break end
            local item=inv2[target.bucket][target.serial]
            local fresh=eligibleAS(target.serial,item,target.bucket,data2)
            if not fresh or fresh.id~=target.id or fresh.qty~=target.qty then
                warn("[AUTOSELL] Item changed/protected, skipping",target.id,target.serial)
            else
                local permitted=true
                if not forceNow then
                    local nowUsed,nowCap=capacityAS()
                    permitted=nowUsed and nowCap and 100*nowUsed/nowCap>=AS.threshold
                end
                if not permitted then
                    print("[AUTOSELL] Threshold no longer met; stopping")
                    break
                end
                print("[AUTOSELL][LIVE] Selling",fresh.id,fresh.serial,fresh.qty)
                if not SellRemoteAS then error("SellRequest remoto indisponivel; nenhuma venda enviada") end
                SellRemoteAS:FireServer({[fresh.serial]=fresh.qty})
                sent+=1
                AS.lastRun=os.clock()
                if forceNow and i<limit then task.wait(0.3) end
            end
        end
        statusAS(string.format("%s: %d sale request(s) sent",mode,sent))
        print("[AUTOSELL]",mode,"completed; sent",sent,"sale requests; server confirmation not verified")
    end)
    AS.busy=false
    if not ok then warn("[AUTOSELL] Error",tostring(err)) statusAS("Error; see output") end
end

-- Each dropdown value is a normalized item TYPE name, not an instance Serial.
-- A sale plan separately resolves EVERY matching Serial from current PlayerData.
local function dropdownSetAS(value)
    local result={}
    if type(value)=="string" then
        result[value]=true
    elseif type(value)=="table" then
        if type(value.Value)=="string" then result[value.Value]=true end
        if type(value.value)=="string" then result[value.value]=true end
        for key,v in pairs(value) do
            if type(v)=="string" then result[v]=true
            elseif type(key)=="string" and v==true then result[key]=true
            elseif type(v)=="table" then
                local name=v.Value or v.value
                if type(name)=="string" then result[name]=true end
            end
        end
    end
    return result
end

local function selectionCountAS(set)
    local count=0
    for _ in pairs(set) do count+=1 end
    return count
end

AS.section=autoSellTab:Section({Title="Auto Sell",Icon="shield-check"})
AS.section:Paragraph({
    Title="Auto Sell by item name",
    Content="All weapon/armor types are loaded from ItemRegistry, including items not yet owned. "..
        "Favorite, locked, equipped, hotbar, quest-reserved and other protected copies are always excluded. "..
        "Auto Sell is OFF until enabled below.",
    Icon="info"
})

-- Rarity is a registry definition field, NOT an attribute of the player-owned instance.
-- Filtering only changes the dropdown display, never the persisted name selection.
local rarityOrderAS={"All","Common","Rare","Epic","Legendary","Godly","Secret","Unknown"}
local knownRarityAS={}
for _,rarity in ipairs(rarityOrderAS) do knownRarityAS[rarity]=true end
for _,def in pairs(RegistryAS) do
    if type(def)=="table" and (def.Kind=="Weapon" or def.Kind=="Armor") then
        if type(def.Rarity)=="string" and def.Rarity~="" and not knownRarityAS[def.Rarity] then
            knownRarityAS[def.Rarity]=true
            rarityOrderAS[#rarityOrderAS+1]=def.Rarity
        end
    end
end
local rarityOptionsAS={}
for _,r in ipairs(rarityOrderAS) do rarityOptionsAS[#rarityOptionsAS+1]={Title=r,Value=r} end
AS.refreshingDropdowns=false
AS.visibleNames={}

local function refreshRegistryDropdownAS()
    local opts,visible={},{}
    for registryId,definition in pairs(RegistryAS) do
        if type(registryId)=="string" and type(definition)=="table" and
           (definition.Kind=="Weapon" or definition.Kind=="Armor") then
            local rarity=type(definition.Rarity)=="string" and definition.Rarity or "Unknown"
            if AS.rarityFilter=="All" or AS.rarityFilter==rarity then
                local key=registryId:lower()
                visible[key]=true
                opts[#opts+1]={
                    Title=tostring(definition.Display or registryId),
                    Value=key,
                    Description=definition.Kind.." | "..rarity.." | ID: "..registryId,
                }
            end
        end
    end
    table.sort(opts,function(a,b)
        if a.Title:lower()==b.Title:lower() then return a.Value<b.Value end
        return a.Title:lower()<b.Title:lower()
    end)
    AS.visibleNames=visible
    AS.refreshingDropdowns=true
    local ok,err=pcall(function()
        AS.sellDropdown:Refresh(opts,false)
        local checked={}
        for key in pairs(AS.selectedNames) do
            if visible[key] then checked[#checked+1]=key end
        end
        AS.sellDropdown:Set(checked)
    end)
    AS.refreshingDropdowns=false
    if not ok then
        warn("[AUTOSELL][REGISTRY] Dropdown error",tostring(err))
    end
    statusAS("Selected types: "..selectionCountAS(AS.selectedNames).." | Registry items: "..#opts)
end

AS.rarityDropdown=AS.section:Dropdown({
    Title="Filter by rarity",Values=rarityOptionsAS,Multi=false,Search=false,
    AllowNone=false,Default="All",Placeholder="All rarities",
    Callback=function(value)
        local rarity=type(value)=="string" and value or type(value)=="table" and (value.Value or value.value or value[1])
        if type(rarity)~="string" or not knownRarityAS[rarity] then rarity="All" end
        AS.rarityFilter=rarity
        if AS.sellDropdown then refreshRegistryDropdownAS() end
    end,
})
AS.sellDropdown=AS.section:Dropdown({
    Title="Items to auto-sell",Values={},Multi=true,Search=true,AllowNone=true,
    Placeholder="Choose item names (all registry items)...",
    Callback=function(value)
        if AS.refreshingDropdowns then return end
        local nextVisible=dropdownSetAS(value)
        -- Replace choices only in the currently visible rarity; retain selections
        -- from other rarity categories, including item types not currently owned.
        for key in pairs(AS.visibleNames) do AS.selectedNames[key]=nil end
        for key in pairs(nextVisible) do
            if AS.visibleNames[key] then AS.selectedNames[key]=true end
        end
        statusAS("Selected item types: "..selectionCountAS(AS.selectedNames))
    end,
})
AS.section:Slider({Title="Inventory fullness threshold",Min=80,Max=95,Step=1,Default=90,Suffix="%",
    Callback=function(value) AS.threshold=math.clamp(tonumber(value) or 90,80,95) end})
AS.label=AS.section:Label({Text="Auto Sell status",Value="OFF | Select item types"})
AS.enabledToggle=AS.section:Toggle({
    Title="Enable Auto Sell",Default=false,
    Description="Automatically sells eligible copies when inventory reaches the threshold. "..
       "Protected copies are excluded; max one instance per cycle.",
    Callback=function(value)
        if value and not AS_DEPS_AVAILABLE then
            AS.enabled=false
            AS.live=false
            if AS.enabledToggle then AS.enabledToggle:Set(false, true) end
            statusAS("OFF | Inventory modules unavailable")
            warn("[AUTOSELL] Enable refused: inventory dependencies are unavailable")
            return
        end
        AS.enabled=value==true
        AS.live=AS.enabled
        statusAS(AS.enabled and "ON | Monitoring inventory" or "OFF")
    end,
})
-- Manual one-shot action: does not require Auto Sell to be enabled.
-- Intentional click sends actual sell requests for ALL eligible instances
-- of the selected names, even when fullness is below the slider value.
AS.section:Button({
    Title="Sell Selected Now",
    Description="Immediately sell every eligible copy of the selected item types, regardless of inventory fullness. Protected items stay excluded. THIS SELLS FOR REAL.",
    Icon="shopping-cart",
    Callback=function()
        AS.preview("manual Sell Selected Now button",true,true)
    end,
})

-- Populate from all static definitions rather than the player's current inventory.
-- Defer so the dropdown object is ready before Refresh/Set.
task.defer(refreshRegistryDropdownAS)

task.spawn(function()
    while gui.Parent do
        if AS.enabled and accessGranted and os.clock()<accessDeadline then
            if os.clock()-AS.lastRun>=12 then
                AS.preview("automatic capacity check",true)
            end
        end
        task.wait(AS.pollSeconds)
    end
end)

-- Only registered dungeons appear in the selector. No fake or placeholder modes.
local dungeonValues = {}
for _, dungeonId in ipairs(DUNGEON_ORDER) do
    local definition = DUNGEONS[dungeonId]
    table.insert(dungeonValues, {
        Title = definition.Title,
        Value = dungeonId,
        Description = definition.Description,
        Icon = definition.Icon,
    })
end

local selectorSection = dungeonTab:Section({ Title = "Dungeon Selection", Icon = "list" })
local selectorInfo = selectorSection:Paragraph({
    Title = "Select a Dungeon",
    Content = "Choose a dungeon to display its available farming functions.",
    Icon = "info",
})
local onDungeonSelected = nil
local dungeonSelector = selectorSection:Dropdown({
    Title = "Dungeon",
    Values = dungeonValues,
    Default = nil,
    Multi = false,
    AllowNone = true,
    Search = false,
    Placeholder = "Choose a dungeon...",
    Callback = function(value)
        if onDungeonSelected then
            onDungeonSelected(value)
        end
    end,
})

-- Halloween-specific features: displayed only while Halloween is selected.
local speedrunModule = dungeonTab:Module({
    Title = "Dungeon Speedrun",
    Description = "Automatically enter, fight, and clear the 18 Halloween rooms.",
    Icon = "swords",
    Keybind = false,
    Default = false,
    Callback = function(enabled)
        if not syncingSpeedrun and onSpeedrunToggle then
            onSpeedrunToggle(enabled)
        end
    end,
})

local autoReplayModule = dungeonTab:Module({
    Title = "Auto Replay",
    Description = "Attempt to restart after clearing the dungeon. Uses one dungeon item per successful replay.",
    Icon = "rotate-cw",
    Keybind = false,
    Default = CFG.AUTO_REPLAY_DEFAULT,
    Callback = function(enabled)
        autoReplayEnabled = enabled
        debugPrint("Auto Replay:", enabled and "ON" or "OFF")
    end,
})

local antiAfkModule = dungeonTab:Module({
    Title = "Anti-AFK",
    Description = "Attempt to prevent idle disconnects while a licensed farm is active.",
    Icon = "shield-check",
    Keybind = false,
    Default = CFG.ANTI_AFK_DEFAULT,
    Callback = function(enabled)
        antiAfkEnabled = enabled
        debugPrint("Anti-AFK:", enabled and "ON" or "OFF")
    end,
})

-- Future dungeons register their own modules here, without showing
-- irrelevant controls from the Halloween farm.
local dungeonModules = {
    halloween = { speedrunModule, autoReplayModule, antiAfkModule },
}

local function updateDungeonModules()
    for dungeonId, modules in pairs(dungeonModules) do
        local show = (dungeonId == selectedDungeonId)
        for _, module in ipairs(modules) do
            module:SetVisible(show)
        end
    end
end

onDungeonSelected = function(value)
    -- OasisUI single-select returns the configured string Value.
    -- This also handles clearing the selection or a table value defensively.
    if type(value) == "table" then
        value = value.Value or value.value or value[1]
    end
    if type(value) ~= "string" or not DUNGEONS[value] then
        value = nil
    end
    if value == selectedDungeonId then
        return
    end

    -- Switching or clearing a selected dungeon safely stops a running farm.
    if running and onSpeedrunToggle then
        onSpeedrunToggle(false)
    end
    selectedDungeonId = value
    updateDungeonModules()

    if selectedDungeonId == "halloween" then
        selectorInfo:SetContent(
            "Halloween Dungeon 2026 selected. Choose Speedrun, Auto Replay, and Anti-AFK below."
        )
        Window:SetSubtitle("V6.0 | Halloween Dungeon")
        debugPrint("Dungeon selected:", "Halloween Dungeon")
    else
        selectorInfo:SetContent("Choose a dungeon to display its available farming functions.")
        Window:SetSubtitle("V6.0 | Dungeon + Main World + Auto Sell")
        debugPrint("Dungeon selection cleared")
    end
end

-- On first launch, nothing is selected and no farming controls are visible.
updateDungeonModules()
onDungeonSelected(dungeonSelector:Get())

-- Universal status and license page retained independently from the selected dungeon.
local versionSection = statusTab:Section({ Title = "Script Version", Icon = "info" })
versionSection:Label({ Text = "Version", Value = "Poly Loot V6.0" })
local live = statusTab:Section({ Title = "Dungeon Statistics", Icon = "chart-no-axes-column" })
local roomLabel = textProxy(live:Label({ Text = "Room", Value = "Room: - / 18" }))
local waveLabel = textProxy(live:Label({ Text = "Wave", Value = "Wave: -" }))
local targetLabel = textProxy(live:Label({ Text = "Target", Value = "Target: -" }))
local healthLabel = textProxy(live:Label({ Text = "Target HP", Value = "HP: -" }))
local killLabel = textProxy(live:Label({ Text = "Defeated", Value = "Enemies defeated: 0" }))
local attackLabel = textProxy(live:Label({ Text = "Attacks", Value = "Attacks: 0" }))
local statusLabel = textProxy(live:Label({ Text = "Status", Value = "Status: Ready" }))
local licenseArea = statusTab:Section({ Title = "Integrated Modules", Icon = "layers" })
local licenseButton = textProxy(licenseArea:Label({ Text = "Access", Value = "Local module integration" }))

local function setButton(enabled)
    syncingSpeedrun = true
    if speedrunModule:Get() ~= enabled then
        speedrunModule:Set(enabled)
    end
    syncingSpeedrun = false
end

-- Stop all background dungeon tasks if OasisUI is unloaded.
OasisUI:OnUnload(function()
    MW.worldFarmRunning = false
    MW.enemyFarmEnabled = false
    MW.bossFarmEnabled = false
    MW.bossActive = false
    MW.worldFarmSession = MW.worldFarmSession + 1
    running = false
    sessionId = sessionId + 1
    -- Runtime Folder is destroyed with the main Poly Hub ScreenGui.
end)

local function stopMovement()
    local humanoid = getHumanoid()
    local root = getRoot()
    if humanoid and root then
        humanoid:MoveTo(root.Position)
    end
end


-- ============================================
-- KEY GUI / SERVER VERIFICATION
-- ============================================
local HttpService = game:GetService("HttpService")

local previousAccessGui = playerGui:FindFirstChild("PolyLootAccessV4")
if previousAccessGui then
    previousAccessGui:Destroy()
end

-- Integrated build: the external key GUI and network verification are intentionally omitted.
-- Auto Replay and farm controllers remain guarded by local module state and UI toggles.
local accessGui = {Enabled = false}
local accessStatus = {Text = "", TextColor3 = Color3.fromRGB(225, 225, 235)}
local keyInput = {Text = ""}
local verifyButton = {Text = ""}
local getKeyButton = {}
local manualLinkBox = {Visible = false}
accessGranted = true
accessDeadline = math.huge
if licenseButton then licenseButton.Text = "Integrated locally; no external key server" end

-- ============================================
-- UNIVERSAL ANTI-AFK | IDLE EVENT + SAFE FALLBACKS
-- ============================================
-- Fired by Roblox after a period without real player input.
-- No mouse clicks are used: they could accidentally click "Run again".
-- Executor capabilities vary; successful delivery is not a guarantee
-- that Roblox will reset the inactivity timer in every environment.
local antiAfkConnection = nil
local antiAfkWarningShown = false

local function sendAntiAfkActivity()
    -- Most executor environments expose VirtualUser. Prefer its right-click
    -- simulation since it does not require foreground mouse coordinates.
    local virtualUserOk, virtualUser = pcall(function()
        return game:GetService("VirtualUser")
    end)
    if virtualUserOk and virtualUser then
        local ok = pcall(function()
            virtualUser:CaptureController()
            virtualUser:ClickButton2(Vector2.new(0, 0))
        end)
        if ok then
            return true, "VirtualUser"
        end
    end

    -- Some executors expose VirtualInputManager instead.
    -- F15 should not activate normal in-game buttons or cause movement.
    local vimOk, vim = pcall(function()
        return game:GetService("VirtualInputManager")
    end)
    if vimOk and vim then
        local ok = pcall(function()
            vim:SendKeyEvent(true, Enum.KeyCode.F15, false, game)
            task.wait(0.05)
            vim:SendKeyEvent(false, Enum.KeyCode.F15, false, game)
        end)
        if ok then
            return true, "VirtualInputManager"
        end
    end

    -- Final fallback: executor-specific keyboard APIs. Only attempt
    -- when Roblox is focused; never generate a real desktop key into
    -- the browser, another app, or a chat text field.
    if type(keypress) == "function" and type(keyrelease) == "function" then
        local gameIsFocused = true
        if type(isrbxactive) == "function" then
            local ok, active = pcall(isrbxactive)
            gameIsFocused = ok and active == true
        elseif type(isgameactive) == "function" then
            local ok, active = pcall(isgameactive)
            gameIsFocused = ok and active == true
        else
            -- Unknown focus: do not synthesize desktop input.
            gameIsFocused = false
        end

        local textBoxFocused = false
        local inputOk, inputService = pcall(function()
            return game:GetService("UserInputService")
        end)
        if inputOk and inputService then
            local ok, focused = pcall(function()
                return inputService:GetFocusedTextBox()
            end)
            textBoxFocused = not ok or focused ~= nil
        end

        if gameIsFocused and not textBoxFocused then
            local ok = pcall(function()
                keypress(0x7E) -- F15
                task.wait(0.05)
                keyrelease(0x7E)
            end)
            if ok then
                return true, "Executor F15"
            end
            -- Release best-effort even after an unexpected error.
            pcall(keyrelease, 0x7E)
        end
    end

    return false, "No supported Anti-AFK input method"
end

antiAfkConnection = player.Idled:Connect(function()
    -- When a new script execution replaces this GUI, remove this old listener.
    if not gui.Parent then
        if antiAfkConnection then
            antiAfkConnection:Disconnect()
            antiAfkConnection = nil
        end
        return
    end

    if not antiAfkEnabled or not (running or MW.worldFarmRunning)
        or not accessGranted or os.clock() >= accessDeadline then
        return
    end

    local ok, method = sendAntiAfkActivity()
    if ok then
        debugPrint("Anti-AFK activity sent via", method)
        antiAfkWarningShown = false
    elseif not antiAfkWarningShown then
        warn("[DUNGEON V5] Anti-AFK unavailable: " .. tostring(method))
        antiAfkWarningShown = true
    end
end)

local function dismissLootPopup()
    local rewardScreen = playerGui:FindFirstChild(
        "RewardScreen"
    )
    if not rewardScreen then
        return false
    end
    local main = rewardScreen:FindFirstChild("Main")
    local header = main and main:FindFirstChild("Header")
    local title = header and header:FindFirstChild("Title")
    if not main or not title then
        return false
    end
    if not rewardScreen.Enabled
        or not main.Visible
        or title.Text ~= "NEW LOOT!" then
        return false
    end
    debugPrint("NEW LOOT Popup erkannt")
    local ok, err = pcall(function()
        local vim = game:GetService("VirtualInputManager")
        local camera = workspace.CurrentCamera
        if not camera then
            error("Keine Kamera")
        end
        local size = camera.ViewportSize
        local x = math.floor(size.X / 2)
        local y = math.floor(size.Y / 2)
        vim:SendMouseButtonEvent(
            x, y, 0, true, game, 0
        )
        task.wait(0.08)
        vim:SendMouseButtonEvent(
            x, y, 0, false, game, 0
        )
    end)
    if not ok then
        warn(
            "[DUNGEON V4] Loot-Klick fehlgeschlagen:",
            err
        )
        return false
    end
    task.wait(0.2)
    return not rewardScreen.Enabled
        or not main.Visible
end

-- ============================================
-- DUNGEON ABSCHLUSS

-- ============================================

local function isDungeonComplete()
    local hud = playerGui:FindFirstChild("DungeonHud")
    if not hud or not hud:IsA("ScreenGui") then
        return false
    end
    local result = hud:FindFirstChild("Result")
    if not result or not result:IsA("GuiObject") then
        return false
    end
    local header = result:FindFirstChild("Header")
    local resultTitle =
        header and header:FindFirstChild("Title")
    if not resultTitle
        or not resultTitle:IsA("TextLabel") then
        return false
    end
    return hud.Enabled
        and result.Visible
        and resultTitle.Text == "Dungeon Cleared!"
end

-- ============================================
-- HALLOWEEN SCENE REPLAY CONFIRMATION
-- ============================================
-- Scene is SERVER -> CLIENT. It confirms a restart but cannot start one.
-- Observed manual replay sequence: exit {reason="again"}, arrive, gate.
-- No __namecall hooks, no RemoteEvent:FireServer calls.
local SCENE_RESTART_WAIT_SECONDS = 45
local sceneReplay = {
    exit = false,
    arrive = false,
    gate = false,
    otherExit = false,
    exitAt = 0,
    arriveAt = 0,
}

local function clearSceneReplay()
    sceneReplay.exit = false
    sceneReplay.arrive = false
    sceneReplay.gate = false
    sceneReplay.otherExit = false
    sceneReplay.exitAt = 0
    sceneReplay.arriveAt = 0
end

local sceneEventsAvailable = false
local function installSceneReplayListener()
    local replicated = game:GetService("ReplicatedStorage")
    local engine = replicated:FindFirstChild("HalloweenDungeon_Engine")
    local remotes = engine and engine:FindFirstChild("Remotes")
    local scene = remotes and remotes:FindFirstChild("Scene")

    if not scene or not scene:IsA("RemoteEvent") then
        debugPrint("[SCENE] Scene RemoteEvent not available; legacy replay detection")
        return false
    end

    local ok, conn = pcall(function()
        return scene.OnClientEvent:Connect(function(action, data)
            -- Diagnostic only: compare server gate timing with the delayed
            -- room popup. Gate signals alone do NOT prove room entry.
            if CFG.DEBUG_MODE and running and not waitingForRestart
                and action == "gate" and type(data) == "table" then
                debugPrint("[SCENE] In-run gate event:",
                    "room", tostring(data.room),
                    "open", tostring(data.open))
            end
            -- Only interpret replay events for a completed dungeon.
            if not running or not accessGranted or not
                (waitingForRestart or isDungeonComplete()) then
                return
            end
            if type(action) ~= "string" then return end
            if type(data) ~= "table" then data = {} end

            if action == "exit" then
                local reason = tostring(data.reason or "")
                if reason == "again" then
                    if not sceneReplay.exit then
                        sceneReplay.exit = true
                        sceneReplay.exitAt = os.clock()
                        debugPrint("[SCENE] exit(reason=again): restart accepted")
                        statusLabel.Text = "Restart accepted - loading dungeon..."
                    end
                else
                    sceneReplay.otherExit = true
                    debugPrint("[SCENE] exit(reason=" .. reason .. "): not a replay")
                end
            elseif action == "arrive" and sceneReplay.exit then
                local dungeonName = tostring(data.name or "")
                if dungeonName == "" or dungeonName == "Halloween Dungeon 2026" then
                    sceneReplay.arrive = true
                    sceneReplay.arriveAt = os.clock()
                    debugPrint("[SCENE] arrive: new dungeon loaded")
                    statusLabel.Text = "New dungeon loaded - waiting for gate..."
                end
            elseif action == "gate" and sceneReplay.arrive then
                if tonumber(data.room) == 1 and data.open == true then
                    sceneReplay.gate = true
                    debugPrint("[SCENE] gate(room=1, open=true): ready to continue")
                    statusLabel.Text = "Dungeon ready - resuming speedrun"
                end
            end
        end)
    end)

    if not ok or not conn then
        debugPrint("[SCENE] Failed to connect; legacy replay detection")
        return false
    end

    -- Prevent accumulating listeners when the script GUI is destroyed.
    gui.Destroying:Connect(function()
        pcall(function() conn:Disconnect() end)
    end)
    debugPrint("[SCENE] Listener enabled: exit -> arrive -> gate")
    return true
end

sceneEventsAvailable = installSceneReplayListener()

-- ============================================
-- RAUM UND WELLEN

-- ============================================

local function processNotification(text)
    if type(text) ~= "string" then
        return
    end
    local room, _, waves = text:match(
        "Room%s+(%d+)%s*/%s*(%d+)%s*[^%d]+(%d+)%s+waves"
    )
    if room then
        local newRoom = tonumber(room)
        if waitingForRestart and newRoom == 1 then
            restartRoomObserved = true
            debugPrint("Neuer Dungeon: Raum 1 angekuendigt")
        end
        if newRoom ~= currentRoom then
            -- This notification is the *displayed* room progress, not proof
            -- of when the avatar first crossed the gate. Record the delay.
            if pendingRoom and newRoom > pendingRoom then
                debugPrint(
                    "[DOOR] Room popup arrived:", pendingRoom, "->", newRoom,
                    string.format("%.2fs after physical crossing",
                        math.max(0, os.clock() - pendingCrossedAt))
                )
                clearPendingDoor()
            end
            currentRoom = newRoom
            currentWave = 0
            totalWaves = tonumber(waves)
            roomCleared = false
            debugPrint("Neuer Raum:", currentRoom)
        end
        roomLabel.Text =
            "Room: " .. currentRoom .. " / 18"
        waveLabel.Text =
            "Waves: " .. totalWaves
        return
    end
    local wave, maxWave = text:match(
        "Wave%s+(%d+)%s*/%s*(%d+)"
    )
    if wave then
        currentWave = tonumber(wave)
        totalWaves = tonumber(maxWave)
        roomCleared = false
        waveLabel.Text =
            "Wave: " .. currentWave
            .. " / " .. totalWaves
        return
    end
    if text:lower():find("final wave", 1, true) then
        currentWave = totalWaves
        roomCleared = false
        waveLabel.Text = "Final wave"
        return
    end
    if text:lower():find("room cleared", 1, true) then
        roomCleared = true
        statusLabel.Text = "Room cleared"
        debugPrint("Raum abgeschlossen:", currentRoom)
    end
end

-- ============================================
-- DYNAMISCHE UI ERKENNUNG

-- ============================================
local observedLabels = {}

local function isNotificationLabel(obj)
    if not obj:IsA("TextLabel")
        or obj.Name ~= "text" then
        return false
    end
    local parent = obj.Parent
    return parent ~= nil
        and (
            parent.Name == "Blank"
            or parent.Name == "Success"
        )
end

local function observeLabel(label)
    if observedLabels[label] then
        return
    end
    observedLabels[label] = true
    label:GetPropertyChangedSignal("Text"):Connect(
        function()
            if gui.Parent then
                processNotification(label.Text)
            end
        end
    )
    processNotification(label.Text)
end

local function registerNotificationUI()
    local notifi = playerGui:FindFirstChild("NotifiUI")
    local notificationFrame =
        notifi and notifi:FindFirstChild("Frame")
    if not notificationFrame then
        return
    end
    for _, obj in ipairs(notificationFrame:GetDescendants()) do
        if isNotificationLabel(obj) then
            observeLabel(obj)
        end
    end
    notificationFrame.DescendantAdded:Connect(function(obj)
        if isNotificationLabel(obj) then
            observeLabel(obj)
        end
    end)
end
task.spawn(function()
    local notifi = playerGui:WaitForChild(
        "NotifiUI",
        15
    )
    if notifi then
        registerNotificationUI()
    else
        warn("[DUNGEON V4] NotifiUI nicht gefunden")
    end
end)

-- ============================================
-- GEGNER ERKENNEN

-- ============================================

local function enemyAlive(enemy)
    local folder = getEnemies()
    if not folder or not enemy
        or not enemy:IsDescendantOf(folder) then
        return false
    end
    local hp = enemy:GetAttribute("Health")
    return typeof(hp) == "number" and hp > 0
end

local function enemyPosition(enemy)
    if enemy and enemy:IsA("Model") then
        return enemy:GetPivot().Position
    end
    return nil
end

local function getNextEnemy()
    local root = getRoot()
    local folder = getEnemies()
    if not root or not folder then
        return nil
    end
    local nearest = nil
    local bestDistance = CFG.TARGET_SEARCH_RADIUS
    local now = os.clock()
    for _, enemy in ipairs(folder:GetChildren()) do
        if enemy:IsA("Model")
            and enemyAlive(enemy)
            and (skippedEnemies[enemy] or 0) <= now then
            local position = enemyPosition(enemy)
            if position then
                local distance =
                    horizontalDistance(
                        root.Position,
                        position
                    )
                if distance < bestDistance then
                    nearest = enemy
                    bestDistance = distance
                end
            end
        end
    end
    return nearest
end

-- ============================================
-- GEGNER MARKIEREN

-- ============================================

local function clearTarget()
    if currentHighlight then
        currentHighlight:Destroy()
        currentHighlight = nil
    end
    targetLabel.Text = "Target: -"
end

local function markEnemy(enemy)
    clearTarget()
    local highlight = Instance.new("Highlight")
    highlight.Name = "DungeonTarget"
    highlight.Adornee = enemy
    highlight.FillColor = Color3.fromRGB(255, 60, 60)
    highlight.OutlineColor = Color3.fromRGB(255, 0, 0)
    highlight.FillTransparency = 0.65
    highlight.DepthMode =
        Enum.HighlightDepthMode.AlwaysOnTop
    highlight.Parent = gui
    currentHighlight = highlight
    targetLabel.Text =
        "Target: " .. enemy.Name:sub(1, 12)
end


-- DUNGEON SAFETY V5.10.6 | Ground verification + out-of-bounds recovery
-- The bridge and room edges may contain open space beneath a valid X/Z target.
local dungeonSafeCF = nil
local dungeonSafeAt = 0
local dungeonRecoveryAt = -math.huge

local function dungeonGroundAt(position)
    local dungeon = getDungeon()
    if not dungeon then return nil end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local exclude = {}
    local character = getCharacter()
    if character then table.insert(exclude, character) end
    local live = workspace:FindFirstChild("Animal_Live")
    if live then table.insert(exclude, live) end
    params.FilterDescendantsInstances = exclude
    params.IgnoreWater = true
    local result = workspace:Raycast(position + Vector3.new(0, 5, 0), Vector3.new(0, -19, 0), params)
    if not result or not result.Instance or not result.Instance.CanCollide
        or result.Normal.Y < 0.65 or not result.Instance:IsDescendantOf(dungeon) then
        return nil
    end
    -- Do not treat a floor far below the intended Y as the correct bridge deck.
    if math.abs(position.Y - (result.Position.Y + 3)) > 7 then return nil end
    return result
end

local function dungeonSafeDestination(position)
    local hit = dungeonGroundAt(position)
    if not hit then return nil end
    return Vector3.new(position.X, hit.Position.Y + 3.2, position.Z)
end

local function dungeonSafetyWatch()
    if currentRoom <= 0 or dungeonComplete then return false end
    local root, char = getRoot(), getCharacter()
    local humanoid = getHumanoid()
    if not root or not char or not humanoid or humanoid.Health <= 0 then return false end
    local now = os.clock()
    local hit = dungeonGroundAt(root.Position)
    if hit then
        -- Only remember positions with a real dungeon floor directly beneath us.
        if now - dungeonRecoveryAt > 1.5 then
            dungeonSafeCF = root.CFrame
            dungeonSafeAt = now
        end
        return false
    end
    -- An airborne character is normal briefly; rescue only a sustained fall
    -- significantly lower than the last confirmed safe floor.
    if dungeonSafeCF and now - dungeonSafeAt < 45
        and root.Position.Y < dungeonSafeCF.Position.Y - 12
        and now - dungeonRecoveryAt > 2 then
        dungeonRecoveryAt = now
        debugPrint("[DUNGEON][SAFETY] Falling below floor; recovering", currentRoom,
            "drop", math.floor(dungeonSafeCF.Position.Y - root.Position.Y))
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
        char:PivotTo(dungeonSafeCF)
        clearPendingDoor()
        approachRoom, approachDoor, approachDirection = nil, nil, nil
        CFG.transitionUntil = now + 0.7
        statusLabel.Text = "Dungeon: recovered from falling"
        return true
    end
    return false
end

-- ============================================
-- TELEPORT ZUM GEGNER

-- ============================================

local function teleportToEnemy(enemy)
    local character = getCharacter()
    local root = getRoot()
    local position = enemyPosition(enemy)
    if not character or not root or not position then
        return false
    end
    local horizontal = Vector3.new(
        root.Position.X - position.X,
        0,
        root.Position.Z - position.Z
    )
    local direction
    if horizontal.Magnitude > 0.01 then
        direction = horizontal.Unit
    else
        direction = -root.CFrame.LookVector
        direction = Vector3.new(
            direction.X,
            0,
            direction.Z
        )
        if direction.Magnitude < 0.01 then
            direction = Vector3.new(0, 0, 1)
        else
            direction = direction.Unit
        end
    end
    local destination =
        Vector3.new(
            position.X,
            root.Position.Y,
            position.Z
        ) + direction * CFG.ATTACK_DISTANCE
    destination = dungeonSafeDestination(destination)
    if not destination then
        debugPrint("[DUNGEON][SAFETY] Enemy teleport skipped (no safe floor)", enemy.Name)
        return false
    end
    local lookTarget = Vector3.new(
        position.X,
        destination.Y,
        position.Z
    )
    if (lookTarget - destination).Magnitude < 0.01 then
        return false
    end
    character:PivotTo(
        CFrame.lookAt(destination, lookTarget)
    )
    return true
end

-- ============================================
-- AUTOMATISCHER KAMPF

-- ============================================

local function fightEnemy(enemy, id)
    markEnemy(enemy)
    local lastAttack = -math.huge
    local lastTeleport = -math.huge
    local lastDamage = os.clock()
    local oldHealth = enemy:GetAttribute("Health")
    local attackPauseUntil = 0
    debugPrint("Kampf gestartet:", enemy.Name)
-- Einmal zum ersten Ziel teleportieren
    teleportToEnemy(enemy)
    while validSession(id)
        and enemyAlive(enemy)
        and not isDungeonComplete() do
        RunService.Heartbeat:Wait()
        if not validSession(id)
            or not enemyAlive(enemy) then
            break
        end
        local now = os.clock()
        local weapon = getWeapon()
        local root = getRoot()
        local humanoid = getHumanoid()
        if not weapon or not root or not humanoid
            or humanoid.Health <= 0 then
            statusLabel.Text = "Weapon or character missing"
            break
        end
        local hp = enemy:GetAttribute("Health")
        local maxHP = enemy:GetAttribute("MaxHealth")
        if typeof(hp) ~= "number" then
            break
        end
        healthLabel.Text =
            "HP: " .. math.floor(hp)
            .. " / " .. tostring(
                typeof(maxHP) == "number"
                and math.floor(maxHP)
                or "?"
            )
        if oldHealth and hp < oldHealth then
            lastDamage = now
        end
        oldHealth = hp
        local position = enemyPosition(enemy)
        if not position then
            break
        end
        local distance =
            horizontalDistance(root.Position, position)
-- Position nur bei Bedarf korrigieren.-- Keine Korrektur direkt waehrend Angriffspause.
        if now >= attackPauseUntil
            and now - lastTeleport >= CFG.REPOSITION_INTERVAL
            and distance > CFG.REPOSITION_DISTANCE then
            teleportToEnemy(enemy)
            lastTeleport = now
            statusLabel.Text = "Position adjusted"
        end
-- Angriff
        if distance <= CFG.REPOSITION_DISTANCE
            and weapon.Enabled
            and now - lastAttack >= CFG.ATTACK_INTERVAL
            and now >= attackPauseUntil then
-- Position unmittelbar vor Angriff korrigieren,-- aber nicht bei jedem Frame.
            if distance > CFG.ATTACK_DISTANCE + 0.4 then
                teleportToEnemy(enemy)
                task.wait(0.05)
            end
            if not validSession(id)
                or not enemyAlive(enemy) then
                break
            end
            weapon:Activate()
            lastAttack = os.clock()
            attackPauseUntil =
                lastAttack + CFG.ATTACK_STABILIZE
            attackCount = attackCount + 1
            attackLabel.Text =
                "Attacks: " .. attackCount
            statusLabel.Text = "Attacking enemy"
        end
-- Anti-Stuck bei ausbleibendem HP-Verlust
        if now - lastDamage >= CFG.NO_DAMAGE_TIMEOUT then
            skippedEnemies[enemy] =
                now + CFG.ENEMY_RETRY_DELAY
            debugPrint(
                "Kein HP-Fortschritt:",
                enemy.Name
            )
            break
        end
    end
    local ended = not enemyAlive(enemy)
    if validSession(id) then
        clearTarget()
        if ended then
            defeatedCount = defeatedCount + 1
            killLabel.Text =
                "Enemies defeated: " .. defeatedCount
        end
    end
    return ended
end

-- ============================================
-- PASSENDE OFFENE TÜR FINDEN

-- ============================================

local function getOpenDoor()
    local dungeonFolder = getDungeon()
    local root = getRoot()
    if not dungeonFolder or not root
        or currentRoom <= 0
        or currentRoom >= 18 then
        return nil
    end
    local nearestDoor = nil
    local nearestDistance = math.huge
-- Die Raumnummer im Ordner kann abweichen.-- Deshalb mehrere benachbarte Indizes erlauben.
    local minIndex = currentRoom + 1
    local maxIndex = currentRoom + 3
    for _, door in ipairs(dungeonFolder:GetDescendants()) do
        if door:IsA("BasePart")
            and door.Name == "Door"
            and door.CanCollide == false
            and not usedDoors[door] then
            local roomFolder = door.Parent
                and door.Parent.Parent
            local index = roomFolder
                and tonumber(
                    roomFolder.Name:match("^(%d+)_")
                )
            if index
                and index >= minIndex
                and index <= maxIndex then
                local distance = horizontalDistance(
                    root.Position,
                    door.Position
                )
                if distance < nearestDistance then
                    nearestDoor = door
                    nearestDistance = distance
                end
            end
        end
    end
    if nearestDoor then
        debugPrint(
            "Offene Ausgangstuer gefunden:",
            nearestDoor:GetFullName(),
            "Distanz:",
            math.floor(nearestDistance)
        )
    end
    return nearestDoor
end

local function enterFirstRoom(id)
    if not validSession(id) or currentRoom > 0 then
        return false
    end
    local dungeon = getDungeon()
    local character = getCharacter()
    local root = getRoot()
    if not dungeon or not character or not root then
        debugPrint("Dungeon oder Charakter fehlt")
        return false
    end
-- Exakte Eingangstuer suchen
    local startRoom = dungeon:FindFirstChild(
        "01_StartingRoom",
        true
    )
    if not startRoom then
        debugPrint("StartingRoom nicht gefunden")
        return false
    end
    local walls = startRoom:FindFirstChild("InvisWalls")
    local door = walls and walls:FindFirstChild("Door")
    if not door or not door:IsA("BasePart") then
        debugPrint("Eingangstuer nicht gefunden")
        return false
    end
    if door.CanCollide then
        debugPrint("Eingangstuer ist geschlossen")
        return false
    end
    local direction = Vector3.new(
        door.Position.X - root.Position.X,
        0,
        door.Position.Z - root.Position.Z
    )
    if direction.Magnitude < 0.1 then
        debugPrint("Richtung nicht bestimmbar")
        return false
    end
    direction = direction.Unit
    local destination = Vector3.new(
        door.Position.X,
        root.Position.Y,
        door.Position.Z
    ) + direction * CFG.DOOR_TELEPORT_DISTANCE
    destination = dungeonSafeDestination(destination)
    if not destination then
        debugPrint("[DUNGEON][SAFETY] First door skipped: unsafe landing")
        return false
    end
    debugPrint(
        "Teleportiere durch Dungeon-Eingang:",
        door:GetFullName()
    )
    character:PivotTo(
        CFrame.lookAt(
            destination,
            destination + direction
        )
    )
    CFG.transitionUntil = os.clock() + CFG.ROOM_TRANSITION_DELAY
-- Auf Raum 1 warten
    local started = os.clock()
    while validSession(id)
        and os.clock() - started < CFG.ROOM_CONFIRM_TIMEOUT do
        if currentRoom >= 1 then
            debugPrint(
                "Dungeon erfolgreich gestartet! Raum:",
                currentRoom
            )
            return true
        end
        task.wait(0.1)
    end
    debugPrint(
        "Eingang betreten, aber Raum 1 nicht bestaetigt"
    )
    return false
end

-- ============================================
-- CROSS OPEN DOOR | V5.5 / CONTINUOUS ROLLBACK MONITOR
-- ============================================
-- The popup is not a reliable real-time position sensor. After crossing,
-- continuously monitor the door side and wait for the popup as long as the
-- character remains in the new room. Retry on confirmed rollback only.
-- Bounded to 3 attempts per transition, with no new remote calls.
local function teleportThroughDoor(id)
    if not validSession(id) or currentRoom <= 0 or currentRoom >= 18 then
        return false
    end

    local door = getOpenDoor()
    if not door or not door:IsA("BasePart") or door.CanCollide then
        return false
    end

    local roomBefore = currentRoom
    local initialRoot = getRoot()
    if not initialRoot then return false end

    if approachRoom ~= roomBefore or approachDoor ~= door
        or not approachDirection then
        local delta = Vector3.new(
            door.Position.X - initialRoot.Position.X,
            0,
            door.Position.Z - initialRoot.Position.Z
        )
        if delta.Magnitude < 0.1 then
            debugPrint("[DOOR] Cannot determine door direction")
            return false
        end
        approachRoom = roomBefore
        approachDoor = door
        approachDirection = delta.Unit
    end

    local direction = approachDirection
    local started = os.clock()
    local attempts = 0
    local lastAttemptAt = 0
    local positionCheckAt = 0
    local lastTarget = nil
    local physicalCrossingSeen = false
    local rollback = false
    local rollbackSamples = 0
    local firstPositionLogged = false

    local function measurePosition()
        local root = getRoot()
        if not root or not door.Parent then return nil, nil end
        local delta = Vector3.new(
            root.Position.X - door.Position.X,
            0,
            root.Position.Z - door.Position.Z
        )
        local side = delta:Dot(direction)
        local targetOffset = lastTarget
            and horizontalDistance(root.Position, lastTarget) or nil
        return side, targetOffset
    end

    local function directAttempt(reason)
        if not validSession(id) or currentRoom ~= roomBefore
            or isDungeonComplete() or not door.Parent or door.CanCollide then
            return false
        end
        local character = getCharacter()
        local root = getRoot()
        if not character or not root then return false end
        local target = Vector3.new(
            door.Position.X, root.Position.Y, door.Position.Z
        ) + direction * CFG.DOOR_TELEPORT_DISTANCE
        target = dungeonSafeDestination(target)
        if not target then
            debugPrint("[DUNGEON][SAFETY] Door teleport skipped: no safe floor", roomBefore)
            return false
        end
        attempts = attempts + 1
        lastAttemptAt = os.clock()
        positionCheckAt = lastAttemptAt + CFG.ROOM_POSITION_CHECK_DELAY
        lastTarget = target
        rollback = false
        rollbackSamples = 0
        firstPositionLogged = false
        CFG.transitionUntil = os.clock() + CFG.ROOM_TRANSITION_DELAY
        statusLabel.Text = "Crossing into room " .. (roomBefore + 1)
        debugPrint(
            "[DOOR] Direct attempt", attempts,
            "room", roomBefore, "->", roomBefore + 1,
            "trigger", reason,
            "doorDistance", string.format("%.1f",
                horizontalDistance(root.Position, door.Position))
        )
        character:PivotTo(CFrame.lookAt(target, target + direction))
        return true
    end

    if not directAttempt("initial") then return false end

    while validSession(id) and os.clock() - started < CFG.ROOM_CONFIRM_TIMEOUT do
        if isDungeonComplete() then return false end

        if currentRoom > roomBefore then
            usedDoors[door] = true
            roomCleared = false
            approachRoom = nil
            approachDoor = nil
            approachDirection = nil
            clearPendingDoor()
            debugPrint(
                "[DOOR] Room transition confirmed:",
                roomBefore, "->", currentRoom,
                string.format("%.2fs", os.clock() - started),
                "attempts", attempts
            )
            return true
        end

        local now = os.clock()
        -- V5.5: continue sampling after the first 0.22-second position check.
        -- In V5.4 we sampled once, so a later server snapback could remain
        -- unnoticed until the full timeout or pending-popup grace handling.
        if positionCheckAt > 0 and now >= positionCheckAt then
            positionCheckAt = now + CFG.ROOM_POSITION_POLL_INTERVAL
            local side, targetOffset = measurePosition()
            if side then
                local wasRollback = rollback
                if side < -3 then
                    rollbackSamples = rollbackSamples + 1
                else
                    rollbackSamples = 0
                end
                rollback = rollbackSamples >= CFG.ROOM_ROLLBACK_CONFIRM_SAMPLES

                if side >= CFG.ROOM_CROSSED_SIDE_THRESHOLD
                    and targetOffset
                    and targetOffset <= CFG.ROOM_CLOSE_TO_TARGET_THRESHOLD then
                    if not physicalCrossingSeen then
                        physicalCrossingSeen = true
                        pendingDoor = door
                        pendingRoom = roomBefore
                        pendingDirection = direction
                        pendingCrossedAt = now
                        pendingDoorLogAt = now
                        debugPrint(
                            "[DOOR] Behind door; monitoring position and popup:",
                            roomBefore, "->", roomBefore + 1
                        )
                    end
                end

                if not firstPositionLogged or (rollback and not wasRollback) then
                    debugPrint(
                        "[DOOR] Position check:",
                        "attempt", attempts,
                        "side", string.format("%.1f", side),
                        "targetOffset", string.format("%.1f", targetOffset or -1),
                        "returnedToStartSide", tostring(rollback),
                        "rollbackSamples", rollbackSamples
                    )
                    firstPositionLogged = true
                end
                if rollback and not wasRollback then
                    debugPrint(
                        "[DOOR] Late rollback detected; retrying without waiting for timeout",
                        "room", roomBefore, "->", roomBefore + 1,
                        "elapsed", string.format("%.2fs", now - started)
                    )
                end
            end
        end

        -- Never repeat an already successful physical crossing simply because
        -- the game's notification is late. Only retry when the avatar is
        -- actually back on the starting side of the selected door.
        if rollback and attempts < CFG.ROOM_MAX_CROSS_ATTEMPTS
            and now - lastAttemptAt >= CFG.ROOM_RETRY_AFTER_ROLLBACK then
            physicalCrossingSeen = false
            clearPendingDoor()
            if not directAttempt("measured rollback") then break end
        end

        task.wait(0.06)
    end

    local side, targetOffset = measurePosition()
    debugPrint(
        "[DOOR] Popup still pending after crossing:", roomBefore,
        "attempts", attempts,
        "side", side and string.format("%.1f", side) or "n/a",
        "targetOffset", targetOffset
            and string.format("%.1f", targetOffset) or "n/a"
    )
    -- The next main-loop iteration observes pendingDoor first. It waits for
    -- the popup, unless the avatar moves back to the original side.
    return false
end

local function waitingForDelayedRoomPopup()
    if not pendingDoor or pendingRoom ~= currentRoom
        or not pendingDirection or not pendingDoor.Parent then
        clearPendingDoor()
        return false
    end

    local root = getRoot()
    if not root then return false end

    local offset = Vector3.new(
        root.Position.X - pendingDoor.Position.X,
        0,
        root.Position.Z - pendingDoor.Position.Z
    )
    local side = offset:Dot(pendingDirection)

    -- We are genuinely back in the previous room: allow recovery crossing.
    if side < -3 then
        debugPrint("[DOOR] Physical rollback confirmed; retry enabled", side)
        clearPendingDoor()
        return false
    end

    -- Pending notifications are given a bounded grace period so the script
    -- cannot get stuck forever waiting for a UI popup that never appears.
    if os.clock() - pendingCrossedAt < CFG.ROOM_POPUP_GRACE_SECONDS then
        if os.clock() - pendingDoorLogAt >= 1.0 then
            debugPrint("[DOOR] Waiting for room popup, still behind door:",
                currentRoom, "side", string.format("%.1f", side))
            pendingDoorLogAt = os.clock()
        end
        return true
    end

    debugPrint("[DOOR] Popup grace expired; allowing one recovery pass:",
        currentRoom, "side", string.format("%.1f", side))
    clearPendingDoor()
    return false
end

-- ============================================
-- HAUPTSCHLEIFE

-- ============================================

local function resetDungeonRun(roomAlreadyDetected)
    completedRuns = completedRuns + 1
-- Raum 1 kann bereits gemeldet worden sein,-- bevor die Result-Anzeige verschwindet.
    currentRoom = roomAlreadyDetected and 1 or 0
    currentWave = 0
    totalWaves = 0
    roomCleared = false
    dungeonComplete = false
    waitingForRestart = false
    finalLootHandled = false
    restartRoomObserved = false
    replayAttempted = false
    replayAttemptAt = 0
    clearSceneReplay()
    skippedEnemies = {}
    usedDoors = {}
    lastRoomAttempt = 0
    lootCheckedRoom = nil
    approachRoom = nil
    approachDoor = nil
    approachDirection = nil
    clearPendingDoor()
    dungeonSafeCF = nil
    dungeonSafeAt = 0
    dungeonRecoveryAt = -math.huge
    CFG.transitionUntil = 0
    attackCount = 0
    defeatedCount = 0
    clearTarget()
    stopMovement()
    roomLabel.Text = roomAlreadyDetected
        and "Room: 1 / 18"
        or "Room: - / 18"
    waveLabel.Text = "Wave: -"
    targetLabel.Text = "Target: -"
    healthLabel.Text = "HP: -"
    killLabel.Text = "Enemies defeated: 0"
    attackLabel.Text = "Attacks: 0"
    statusLabel.Text = "Starting new run"
    debugPrint(
        "Dungeon-Reset abgeschlossen!",
        "Abgeschlossene Runs:",
        completedRuns
    )
end

local function getNearbyDrops(origin)
    local folder = workspace:FindFirstChild("WorldBits")
    local root = getRoot()
    if not folder or not root then
        return {}
    end
    origin = origin or root.Position
    local drops = {}
    for _, model in ipairs(folder:GetChildren()) do
        if model:IsA("Model") then
            local aura = model:FindFirstChild(
                "DropAura",
                true
            )
            local prompt = model:FindFirstChild(
                "ProximityPrompt",
                true
            )
            if aura
                and aura:IsA("BasePart")
                and aura:GetAttribute("DropAura") == true
                and prompt
                and prompt:IsA("ProximityPrompt")
                and prompt.ActionText == "Pick Up"
                and prompt.Enabled then
                local distance = (
                    aura.Position - origin
                ).Magnitude
                if distance <= CFG.LOOT_SEARCH_RADIUS then
                    table.insert(drops, {
                        model = model,
                        aura = aura,
                        prompt = prompt,
                        distance = distance
                    })
                end
            end
        end
    end
    table.sort(drops, function(a, b)
        return a.distance < b.distance
    end)
    return drops
end

local function collectDroppedItems(id)
    if not CFG.AUTO_LOOT_ENABLED or not validSession(id) then
        return false
    end
    statusLabel.Text = "Checking for dropped items"
-- Warten, damit verzoegerte Drops erscheinen
    task.wait(CFG.LOOT_SETTLE_TIME)
    local started = os.clock()
    local attempted = {}
    local collected = 0
    -- Keep the search centered on the original room, even after teleporting.
    local originRoot = getRoot()
    local lootOrigin = originRoot and originRoot.Position or nil
    while validSession(id)
        and os.clock() - started < CFG.LOOT_TIMEOUT do
        local drops = getNearbyDrops(lootOrigin)
        local target = nil
-- Naechsten noch nicht versuchten Drop suchen
        for _, drop in ipairs(drops) do
            if (attempted[drop.model] or 0) < 2 then
                target = drop
                break
            end
        end
        if not target then
            break
        end
        attempted[target.model] = (attempted[target.model] or 0) + 1
        local character = getCharacter()
        local root = getRoot()
        if not character or not root then
            break
        end
        if not target.aura.Parent
            or not target.prompt.Parent then
            continue
        end
        local prompt = target.prompt
        local promptPart = prompt.Parent
        if not promptPart:IsA("BasePart") then
            debugPrint("Prompt ohne BasePart")
            continue
        end
-- Direkt neben den Pickup-Handle teleportieren
        local position = promptPart.Position
        local destination = Vector3.new(
            position.X,
            position.Y + 2,
            position.Z
        )
        debugPrint(
            "Sammle Drop:",
            target.model:GetAttribute("wbId")
                or target.model.Name
        )
        statusLabel.Text = "Collecting item..."
        character:PivotTo(
            CFrame.new(destination)
        )
-- Auf Interaktionsreichweite warten
        local pickupReady = false
        local waitStarted = os.clock()
        while validSession(id)
            and os.clock() - waitStarted < 2 do
            local currentRoot = getRoot()
            if not currentRoot
                or not prompt.Parent
                or not target.model.Parent then
                break
            end
            local distance = (
                currentRoot.Position - promptPart.Position
            ).Magnitude
            if prompt.Enabled
                and distance <= prompt.MaxActivationDistance then
                pickupReady = true
                break
            end
            task.wait(0.1)
        end
        if not validSession(id) then
            break
        end
        if pickupReady then
            local ok, err = pcall(function()
                if type(fireproximityprompt) ~= "function" then
                    error(
                        "fireproximityprompt nicht verfuegbar"
                    )
                end
                fireproximityprompt(prompt)
            end)
            if not ok then
                warn(
                    "[DUNGEON V4] Pickup fehlgeschlagen:",
                    err
                )
            end
-- Auf Verarbeitung des Pickups warten
            task.wait(CFG.LOOT_PICKUP_WAIT)
            if not target.model.Parent then
                collected = collected + 1
                debugPrint(
                    "Drop erfolgreich eingesammelt"
                )
            else
                debugPrint(
                    "Drop noch vorhanden:",
                    target.model.Name
                )
            end
        else
            debugPrint(
                "Pickup nicht bereit:",
                target.model.Name
            )
        end
    end
    debugPrint(
        "Loot-Phase beendet.",
        "Eingesammelt:",
        collected
    )
    statusLabel.Text = "Loot collection complete"
    return true
end

-- ============================================
-- UNIVERSAL AUTO REPLAY | EXECUTOR CAPABILITIES
-- ============================================
-- Detect the executor for diagnostics, but choose APIs by capability.
-- Executor names and APIs change between releases.
local function getExecutorInfo()
    local probes = {}
    if type(identifyexecutor) == "function" then
        table.insert(probes, identifyexecutor)
    end
    if type(getexecutorname) == "function" then
        table.insert(probes, getexecutorname)
    end
    for _, probe in ipairs(probes) do
        local ok, name, version = pcall(probe)
        if ok and type(name) == "string" and #name > 0 then
            return name, type(version) == "string" and version or ""
        end
    end
    return "Unknown", ""
end

local executorName, executorVersion = getExecutorInfo()
local executorNameLower = string.lower(executorName)
local function canUseNativeMouse()
    return type(mousemoveabs) == "function" and (
        type(mouse1click) == "function" or
        (type(mouse1press) == "function" and type(mouse1release) == "function")
    )
end

local function getNativeMouseFocus()
    local focusFn = nil
    if type(isrbxactive) == "function" then
        focusFn = isrbxactive
    elseif type(isgameactive) == "function" then
        focusFn = isgameactive
    elseif type(iswindowactive) == "function" then
        focusFn = iswindowactive
    end
    if focusFn then
        local ok, isActive = pcall(focusFn)
        if ok and isActive == false then
            return false
        end
    end
    return true
end

local function getReplayButton()
    local hud = playerGui:FindFirstChild("DungeonHud")
    local result = hud and hud:FindFirstChild("Result")
    local again = result and result:FindFirstChild("Again")
    if not again or not again:IsA("GuiButton") then
        return nil, "Run again button was not found"
    end
    if not again.Visible or not again.Active or not again.Interactable then
        return nil, "Run again button is not clickable"
    end
    return again, nil
end

-- ============================================
-- PRECISE REPLAY CLICK (Solara/desktop executors)
-- ============================================
-- Roblox AbsolutePosition is relative to CoreUISafeInsets. Native mouse
-- coordinates and UserInputService:GetMouseLocation() use screen pixels.
-- Add the top-left inset exactly once regardless of IgnoreGuiInset.
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local function replayButtonCenter(again)
    local pos = again.AbsolutePosition
    local size = again.AbsoluteSize
    if size.X <= 0 or size.Y <= 0 then
        return nil, nil, "Run again button is not on-screen"
    end
    local center = pos + size * 0.5
    local ok, inset = pcall(function()
        return GuiService:GetGuiInset()
    end)
    if not ok or typeof(inset) ~= "Vector2" then
        inset = Vector2.new(0, 0)
    end
    local x = math.floor(center.X + inset.X + 0.5)
    local y = math.floor(center.Y + inset.Y + 0.5)
    local camera = workspace.CurrentCamera
    if camera then
        local viewport = camera.ViewportSize
        if x < 0 or y < 0 or x >= viewport.X or y >= viewport.Y then
            return nil, nil, "Run again button is outside the viewport"
        end
    end
    return x, y, nil
end

local function readActualMouse()
    local ok, p = pcall(function()
        return UserInputService:GetMouseLocation()
    end)
    if ok and typeof(p) == "Vector2" then
        return p
    end
    return nil
end

-- Move first, measure where the cursor actually landed, then correct any
-- window/inset offset BEFORE pressing. No probing clicks are performed.
local function moveToReplayCenter(x, y, again)
    local target = Vector2.new(x, y)
    local size = again.AbsoluteSize
    local toleranceX = math.max(5, math.min(16, size.X * 0.14))
    local toleranceY = math.max(5, math.min(16, size.Y * 0.14))

    mousemoveabs(x, y)
    task.wait(0.12)

    local last = readActualMouse()
    if not last then
        -- On executors where location cannot be read, preserve the normal
        -- native mouse behavior, but report that alignment was unverified.
        return true, "Mouse position unavailable; alignment unverified"
    end

    for step = 1, 3 do
        local dx = target.X - last.X
        local dy = target.Y - last.Y
        if math.abs(dx) <= toleranceX and math.abs(dy) <= toleranceY then
            return true, string.format(
                "Aligned at (%d,%d), target (%d,%d), correction steps %d",
                math.floor(last.X + 0.5), math.floor(last.Y + 0.5),
                x, y, step - 1
            )
        end

        if step == 3 then break end

        debugPrint(string.format(
            "Replay mouse offset: dx=%.1f dy=%.1f; adjusting",
            dx, dy
        ))
        local moved = pcall(function()
            if type(mousemoverel) == "function" then
                mousemoverel(math.floor(dx + (dx >= 0 and 0.5 or -0.5)),
                             math.floor(dy + (dy >= 0 and 0.5 or -0.5)))
            else
                -- Fallback if the executor only provides absolute movement.
                mousemoveabs(math.floor(x + dx + 0.5),
                             math.floor(y + dy + 0.5))
            end
        end)
        if not moved then
            return false, "Cursor correction API failed"
        end
        task.wait(0.12)
        local updated = readActualMouse()
        if not updated then
            return false, "Cursor location became unavailable"
        end
        last = updated
    end

    return false, string.format(
        "Cursor missed button center: target (%d,%d), actual (%d,%d)",
        x, y, math.floor(last.X + 0.5), math.floor(last.Y + 0.5)
    )
end

-- A single verified native press-and-release. Never spam clicks or retry
-- after input was dispatched, because each successful restart costs an item.
local function tryNativeMouseReplay(id, again)
    if not canUseNativeMouse() then
        return false, "Native mouse API not available"
    end
    if not getNativeMouseFocus() then
        return false, "Roblox is not the focused window"
    end

    local wasVisible = frame.Visible
    local pressed = false
    local inputStarted = false
    local movedDetails = "not attempted"
    local ok, err = pcall(function()
        frame.Visible = false
        task.wait(0.12)
        if not validSession(id) or not isDungeonComplete()
            or not again.Visible or not again.Interactable then
            error("Result screen changed before clicking")
        end

        -- Recalculate AFTER hiding the overlay, in case the GUI moved.
        local x, y, locationError = replayButtonCenter(again)
        if not x then error(locationError) end
        local aligned, details = moveToReplayCenter(x, y, again)
        movedDetails = details
        debugPrint("Replay cursor:", details)
        if not aligned then error(details) end

        if not validSession(id) or not isDungeonComplete()
            or not getNativeMouseFocus() then
            error("Replay stopped: result closed or window lost focus")
        end

        if type(mouse1press) == "function" and
            type(mouse1release) == "function" then
            mouse1press()
            inputStarted = true
            pressed = true
            task.wait(0.11)
            mouse1release()
            pressed = false
        else
            inputStarted = true
            mouse1click()
        end
        task.wait(0.15)
    end)

    if pressed then pcall(mouse1release) end
    frame.Visible = wasVisible and gui.Parent ~= nil

    if not ok then
        if inputStarted then
            return true, "Mouse input possibly sent: " .. tostring(err)
        end
        return false, "Mouse alignment/press failed: " .. tostring(err)
    end
    return true, "Single native click sent; " .. movedDetails
end

-- Direct signal activation for executors supporting firesignal.
-- This does not guarantee that game logic will accept a missing InputObject.
local function chooseReplaySignal(again)
    if type(getconnections) == "function" then
        local okA, activated = pcall(getconnections, again.Activated)
        local okM, clicked = pcall(getconnections, again.MouseButton1Click)
        if okA and type(activated) == "table" and #activated > 0 then
            return again.Activated, "Activated", activated
        end
        if okM and type(clicked) == "table" and #clicked > 0 then
            return again.MouseButton1Click, "MouseButton1Click", clicked
        end
    end
    return again.Activated, "Activated", nil
end

local function tryFireSignalReplay(_, again)
    if type(firesignal) ~= "function" then
        return false, "firesignal API not available"
    end
    local signal, eventName, listeners = chooseReplaySignal(again)
    if type(getconnections) == "function" and listeners == nil then
        -- If introspection works and reports no handlers for either event,
        -- use a real mouse action instead of treating an empty signal as success.
        local aOk, aList = pcall(getconnections, again.Activated)
        local mOk, mList = pcall(getconnections, again.MouseButton1Click)
        if aOk and mOk and type(aList) == "table" and type(mList) == "table"
            and #aList == 0 and #mList == 0 then
            return false, "No accessible replay button listeners"
        end
    end
    local ok, err = pcall(function()
        if eventName == "Activated" then
            firesignal(signal, nil, 0)
        else
            firesignal(signal)
        end
    end)
    if not ok then
        -- It is impossible to know whether any listener ran before the error.
        return true, "Signal dispatch may have partially succeeded: " .. tostring(err)
    end
    return true, "firesignal(" .. eventName .. ") dispatched"
end

-- Some executors have getconnections but no firesignal.
local function tryConnectionsReplay(_, again)
    if type(getconnections) ~= "function" then
        return false, "getconnections API not available"
    end
    local _, eventName, list = chooseReplaySignal(again)
    if type(list) ~= "table" or #list == 0 then
        return false, "No accessible button event connections"
    end
    local count = 0
    for _, conn in ipairs(list) do
        if conn.Enabled ~= false then
            local ok = pcall(function()
                if type(conn.Fire) == "function" then
                    if eventName == "Activated" then
                        conn:Fire(nil, 0)
                    else
                        conn:Fire()
                    end
                elseif type(conn.Function) == "function" then
                    if eventName == "Activated" then
                        conn.Function(nil, 0)
                    else
                        conn.Function()
                    end
                else
                    error("Unusable connection")
                end
            end)
            if ok then count = count + 1 end
        end
    end
    if count == 0 then
        return false, "Button connections could not be executed"
    end
    return true, "Fired " .. count .. " " .. eventName .. " connection(s)"
end

-- Last-resort API for runtimes which expose VirtualInputManager only.
-- This previously failed in some executors, so it is NOT the first choice.
local function tryVirtualInputReplay(id, again)
    local x, y, err = replayButtonCenter(again)
    if not x then return false, err end
    local okService, vim = pcall(function()
        return game:GetService("VirtualInputManager")
    end)
    if not okService or not vim then
        return false, "VirtualInputManager is unavailable"
    end
    local wasVisible = frame.Visible
    local inputStarted = false
    local ok, failure = pcall(function()
        frame.Visible = false
        task.wait(0.1)
        if not validSession(id) or not isDungeonComplete() then
            error("Result screen changed before clicking")
        end
        vim:SendMouseMoveEvent(x, y, game)
        task.wait(0.09)
        inputStarted = true
        vim:SendMouseButtonEvent(x, y, 0, true, game, 0)
        task.wait(0.09)
        vim:SendMouseButtonEvent(x, y, 0, false, game, 0)
        task.wait(0.1)
    end)
    frame.Visible = wasVisible and gui.Parent ~= nil
    if not ok then
        if inputStarted then
            return true, "VirtualInputManager may have sent input: " .. tostring(failure)
        end
        return false, "VirtualInputManager failed: " .. tostring(failure)
    end
    return true, "VirtualInputManager click dispatched"
end

local function replayMethodOrder()
    -- Name-based preference is only a hint; functionality is checked at call.
    -- Solara: native cursor. Potassium: fire signal first, then native cursor.
    -- Unknown executor: detect and use whichever API is available.
    if executorNameLower:find("potassium", 1, true) then
        -- Prefer the previously used Potassium signal API. The generic native
        -- mouse path can report input dispatched even when it missed the GUI.
        return { "signal", "native", "connections", "virtual" }
    elseif executorNameLower:find("solara", 1, true) then
        return { "native", "virtual", "signal", "connections" }
    end
    return { "native", "signal", "connections", "virtual" }
end

local replayMethods = {
    native = tryNativeMouseReplay,
    signal = tryFireSignalReplay,
    connections = tryConnectionsReplay,
    virtual = tryVirtualInputReplay,
}

local function printReplayCapabilities()
    local versionText = executorVersion ~= "" and (" " .. executorVersion) or ""
    debugPrint("Executor detected:", executorName .. versionText)
    debugPrint("Replay API:",
        "nativeMouse=" .. tostring(canUseNativeMouse()),
        "firesignal=" .. tostring(type(firesignal) == "function"),
        "getconnections=" .. tostring(type(getconnections) == "function"))
    debugPrint("Replay preference:", table.concat(replayMethodOrder(), " -> "))
end
printReplayCapabilities()

-- One actual activation attempt per endscreen. If an API call errors BEFORE
-- dispatching input, the next supported method is tried automatically.
-- If input might have been sent, we wait for the game or require manual replay.
local function attemptAutoReplay(id)
    if not validSession(id) or not isDungeonComplete() then
        return false, "Endscreen not ready"
    end
    if accessGui.Enabled then
        return false, "Close the key window before replay"
    end
    local again, buttonError = getReplayButton()
    if not again then
        return false, buttonError
    end
    local failures = {}
    for _, method in ipairs(replayMethodOrder()) do
        if not validSession(id) or not isDungeonComplete() then
            return false, "Endscreen changed while choosing replay method"
        end
        local success, sent, reason = pcall(replayMethods[method], id, again)
        if success and sent then
            debugPrint("Auto Replay input dispatched by:", method, reason,
                "(not yet confirmed by dungeon)")
            return true, method .. ": " .. tostring(reason)
        end
        local failure = tostring(success and reason or sent)
        debugPrint("Auto Replay method skipped/failed:", method, failure)
        table.insert(failures, method .. "=" .. failure)
    end
    return false, "No usable method: " .. table.concat(failures, "; ")
end

local function startSpeedrun(id)
    debugPrint("Dungeon Speedrun started!")
    while validSession(id) do
        if isDungeonComplete() then
            if not waitingForRestart then
                waitingForRestart = true
                restartRoomObserved = false
                stopMovement()
                clearTarget()
                replayAttempted = false
                replayAttemptAt = 0
                -- Scene exit might already have arrived; do not clear it here.
                statusLabel.Text = "Dungeon cleared - waiting for restart"
                debugPrint("Dungeon cleared; waiting for restart")
            end
            -- Collect any final boss drops before requesting another run.
            if not finalLootHandled then
                finalLootHandled = true
                collectDroppedItems(id)
            end
            -- A Scene event confirms a restart. It never triggers one.
            -- Dispatch at most ONE input attempt; manual Run again stays available.
            local endscreenHiddenAt = nil
            local replayReady = false
            while validSession(id) do
                local completeScreenVisible = isDungeonComplete()
                local now = os.clock()

                if sceneEventsAvailable and sceneReplay.otherExit then
                    statusLabel.Text = "Dungeon exited without replay - stopped"
                    debugPrint("[SCENE] Left dungeon without Run again; stopping")
                    running = false
                    sessionId = sessionId + 1
                    setButton(false)
                    break
                end

                if sceneEventsAvailable and sceneReplay.gate
                    and not completeScreenVisible then
                    replayReady = true
                    break
                end

                if not completeScreenVisible then
                    if not sceneEventsAvailable then
                        -- If the Scene listener cannot be installed, retain
                        -- the old endscreen-based fallback as a last resort.
                        task.wait(1)
                        replayReady = not isDungeonComplete()
                        break
                    end
                    endscreenHiddenAt = endscreenHiddenAt or now
                else
                    endscreenHiddenAt = nil
                end

                if completeScreenVisible and autoReplayEnabled
                    and not replayAttempted and not sceneReplay.exit then
                    replayAttempted = true
                    replayAttemptAt = os.clock()
                    local sent, reason = attemptAutoReplay(id)
                    debugPrint("Auto Replay attempt:", sent, reason)
                    if sent then
                        statusLabel.Text = "Replay input sent - awaiting Scene confirmation"
                    else
                        statusLabel.Text = "Auto Replay failed - click Run again"
                    end
                end

                -- Never automatically click again merely because Scene is slow.
                if replayAttempted and replayAttemptAt > 0
                    and not sceneReplay.exit
                    and now - replayAttemptAt >= CFG.REPLAY_CONFIRM_TIMEOUT then
                    statusLabel.Text = "Replay not confirmed - click Run again"
                    replayAttemptAt = 0
                end

                if sceneEventsAvailable and sceneReplay.exit
                    and not sceneReplay.gate
                    and now - sceneReplay.exitAt >= SCENE_RESTART_WAIT_SECONDS then
                    statusLabel.Text = "Restart received but gate not ready - stopped"
                    debugPrint("[SCENE] Timed out waiting for arrive/gate")
                    running = false
                    sessionId = sessionId + 1
                    setButton(false)
                    break
                end

                if sceneEventsAvailable and endscreenHiddenAt
                    and not sceneReplay.gate
                    and now - endscreenHiddenAt >= SCENE_RESTART_WAIT_SECONDS then
                    statusLabel.Text = "Restart unconfirmed by Scene - stopped"
                    debugPrint("[SCENE] Endscreen vanished without confirmed gate")
                    running = false
                    sessionId = sessionId + 1
                    setButton(false)
                    break
                end

                task.wait(0.2)
            end
            if not validSession(id) then break end
            if not replayReady then
                statusLabel.Text = "Replay was not confirmed"
                break
            end

            -- New dungeon confirmed by the server: exit -> arrive -> gate.
            -- Room 1 may already be reported by a notification.
            local roomAlreadyDetected = restartRoomObserved and currentRoom == 1
            resetDungeonRun(roomAlreadyDetected)
            setButton(true)
            debugPrint("[SCENE] New dungeon confirmed; resuming")
            continue
        end
        if dismissLootPopup() then
            debugPrint("NEW LOOT bestaetigt")
        end
        if dungeonSafetyWatch() then
            task.wait(0.2)
            continue
        end
        local weapon = getWeapon()
        local humanoid = getHumanoid()
        if not weapon then
            statusLabel.Text = "Equip a weapon"
            task.wait(0.4)
        elseif not humanoid or humanoid.Health <= 0 then
            statusLabel.Text = "Character not ready"
            task.wait(0.4)
        elseif CFG.AUTO_ENTER_FIRST_ROOM and currentRoom == 0 then
            statusLabel.Text = "Entering dungeon..."
            enterFirstRoom(id)
            task.wait(0.5)
        elseif os.clock() < CFG.transitionUntil then
            statusLabel.Text = "Confirming room transition"
            task.wait(0.1)
        else
            local enemy = getNextEnemy()
            if enemy then
                fightEnemy(enemy, id)
            elseif waitingForDelayedRoomPopup() then
                statusLabel.Text = "Waiting for room confirmation..."
                task.wait(0.12)
            elseif currentRoom > 0 and currentRoom < 18 and getOpenDoor() then
            if os.clock() - lastRoomAttempt
                >= CFG.ROOM_RETRY_DELAY then
                lastRoomAttempt = os.clock()
                local requestedRoom = currentRoom
-- Scan loot once per room, not again after an unconfirmed door.
                if lootCheckedRoom ~= currentRoom then
                    local scannedRoom = currentRoom
                    local scanned = true
                    if CFG.AUTO_LOOT_ENABLED then
                        scanned = collectDroppedItems(id)
                    end
                    if scanned and validSession(id) and currentRoom == scannedRoom then
                        lootCheckedRoom = scannedRoom
                    end
                else
                    debugPrint("Loot already checked for room", currentRoom,
                        "- skipping repeated scan")
                end
-- Then try crossing (never if the room changed while scanning).
                if validSession(id) and currentRoom == requestedRoom then
                    teleportThroughDoor(id)
                end
            end
                task.wait(0.2)
            else
                statusLabel.Text = "Waiting for enemies / door"
                task.wait(0.25)
            end
        end
        task.wait(0.03)
    end
    if sessionId == id then
        clearTarget()
        stopMovement()
        statusLabel.Text = "Speedrun stopped"
    end
    debugPrint("Dungeon Speedrun beendet")
end

-- ============================================
-- MAIN WORLD V5.9.0 | SINGLE NPC / SAME RESPAWN
-- ============================================
-- Deliberately no long-range route, area roaming, boss loop, target switching,
-- multi-spawn farm, global teleport watchdog, or UID-based player selection.
MW.dropOrigins={}
MW.dropAttempts={}
MW.lastWeaponAttempt=-1e12
MW.lockedSpawn=nil
MW.activeNPC=nil
MW.lastApproachedNPC=nil
MW.lastCombatWarning=0
MW.lastCombatLog=0

function MW.worldFarmValid(id)
    return MW.worldFarmRunning and MW.worldFarmSession==id
        and accessGranted and os.clock()<accessDeadline
        and not running and gui.Parent~=nil
end

function MW.captureAreaMarkers()
    if not MW.validArea(MW.selectedArea) then
        warn("[WORLD][SINGLE] Select an area before capturing")
        return
    end
    local folder=workspace:FindFirstChild("Animal_SpawnPoints")
    local root=getRoot()
    if not root or not folder then return end
    local captured=0
    for _,part in ipairs(folder:GetChildren()) do
        local key=MW.markerKey(part)
        if key and horizontalDistance(root.Position,part.Position)<=115
            and math.abs(root.Position.Y-part.Position.Y)<=60 then
            MW.areaMarks[key]={area=MW.selectedArea,
                animal=part:GetAttribute("Animal"),x=part.Position.X,z=part.Position.Z}
            captured+=1
        end
    end
    if type(writefile)=="function" then
        local ok,err=pcall(function()
            writefile(MW.AREA_MAP_FILE,game:GetService("HttpService"):JSONEncode({
                version=1,marks=MW.areaMarks
            }))
        end)
        if not ok then warn("[WORLD][SINGLE] Cannot save map:",err) end
    end
    print("[WORLD][SINGLE] Captured",captured,"spawns for",MW.selectedArea)
    MW.refreshAreaEnemies()
end

function MW.refreshAreaEnemies()
    local names={}
    local folder=workspace:FindFirstChild("Animal_SpawnPoints")
    if folder and MW.validArea(MW.selectedArea) then
        for _,part in ipairs(folder:GetChildren()) do
            local key=MW.markerKey(part)
            local mark=key and MW.areaMarks[key]
            if mark and mark.area==MW.selectedArea then
                local animal=part:GetAttribute("Animal")
                if type(animal)=="string" then names[animal]=true end
            end
        end
    end
    local sorted={}
    for name in pairs(names) do table.insert(sorted,name) end
    table.sort(sorted)
    local options={}
    for _,name in ipairs(sorted) do
        table.insert(options,{Title=name,Value=name})
    end
    MW.worldUiRefreshing=true
    pcall(function() MW.enemyDropdown:Refresh(options,false) end)
    MW.worldUiRefreshing=false
    if #sorted==0 then
        MW.selectionInfo:SetContent("No mapped enemies for "..tostring(MW.selectedArea or "this area")..
            ". Stand there and use Capture Nearby Spawns, then select the enemy.")
    else
        MW.selectionInfo:SetContent("Area "..MW.selectedArea.." has "..#sorted..
            " enemy types. Select one and stand near the particular NPC to lock its spawn.")
    end
    print("[WORLD][SINGLE] Area",tostring(MW.selectedArea),"enemies",table.concat(sorted,", "))
end

function MW.lockNearestSpawn()
    local folder=workspace:FindFirstChild("Animal_SpawnPoints")
    local root=getRoot()
    if not folder or not root then return false end
    local possible={}
    for _,part in ipairs(folder:GetChildren()) do
        local key=MW.markerKey(part)
        local mark=key and MW.areaMarks[key]
        if mark and mark.area==MW.selectedArea
            and part:GetAttribute("Animal")==MW.selectedEnemyName then
            local d=horizontalDistance(root.Position,part.Position)
            if d<=65 then
                table.insert(possible,{part=part,distance=d,
                    marker=tostring(part:GetAttribute("_MarkerId") or "")})
            end
        end
    end
    if #possible==0 then
        MW.worldStatusLabel:SetValue("No mapped spawn within 65 studs: approach enemy / capture area")
        return false
    end
    -- Choose a LIVE matching spawn first, otherwise the nearest fixed spawn.
    local enemies=getEnemies()
    for _,slot in ipairs(possible) do
        slot.occupied=false
        if enemies then
            for _,npc in ipairs(enemies:GetChildren()) do
                if npc:IsA("Model") and npc:GetAttribute("Animal")==MW.selectedEnemyName then
                    local hp=npc:GetAttribute("Health")
                    local npcPos=enemyPosition(npc)
                    local marker=npc:GetAttribute("_SpawnMarkerId") or npc:GetAttribute("SpawnMarkerId")
                    if type(hp)=="number" and hp>0 and npcPos
                        and ((marker~=nil and slot.marker~="" and tostring(marker)==slot.marker)
                            or (horizontalDistance(npcPos,slot.part.Position)<=20
                                and math.abs(npcPos.Y-slot.part.Position.Y)<=18)) then
                        slot.occupied=true
                        break
                    end
                end
            end
        end
    end
    table.sort(possible,function(a,b)
        if a.occupied~=b.occupied then return a.occupied end
        return a.distance<b.distance
    end)
    local chosen=possible[1]
    MW.lockedSpawn={part=chosen.part,pos=chosen.part.Position,
        marker=chosen.marker,animal=MW.selectedEnemyName}
    MW.worldTargetLabel:SetValue(MW.selectedEnemyName.." | one spawn locked")
    print("[WORLD][SINGLE] LOCKED_SPAWN",MW.selectedArea,MW.selectedEnemyName,
        "distance",math.floor(chosen.distance),"alive",chosen.occupied,
        "marker",MW.lockedSpawn.marker)
    return true
end

function MW.isLockedNpc(npc)
    local slot=MW.lockedSpawn
    if not slot or not npc:IsA("Model") or npc:GetAttribute("Animal")~=slot.animal then
        return false
    end
    if not npc.Parent then return false end
    local id=npc:GetAttribute("_SpawnMarkerId") or npc:GetAttribute("SpawnMarkerId")
    if id~=nil and slot.marker~="" then
        return tostring(id)==slot.marker
    end
    local pos=enemyPosition(npc)
    return pos~=nil and horizontalDistance(pos,slot.pos)<=25
        and math.abs(pos.Y-slot.pos.Y)<=20
end

function MW.currentNpc()
    local folder=getEnemies()
    if not folder then return nil end
    -- Keep the live instance until it dies: never switch NPCs mid-combat.
    if MW.activeNPC and MW.isLockedNpc(MW.activeNPC) then
        local hp=MW.activeNPC:GetAttribute("Health")
        if type(hp)=="number" and hp>0 then return MW.activeNPC end
    end
    MW.activeNPC=nil
    for _,npc in ipairs(folder:GetChildren()) do
        if MW.isLockedNpc(npc) then
            local hp=npc:GetAttribute("Health")
            if type(hp)=="number" and hp>0 then
                MW.activeNPC=npc
                return npc
            end
        end
    end
    return nil
end

function MW.equipWeapon()
    local equipped=getWeapon()
    if equipped then
        MW.preferredWeaponName=equipped.Name
        return equipped
    end
    if not MW.preferredWeaponName or os.clock()-MW.lastWeaponAttempt<0.7 then return nil end
    MW.lastWeaponAttempt=os.clock()
    local humanoid=getHumanoid()
    local bag=player:FindFirstChildOfClass("Backpack")
    local tool=bag and bag:FindFirstChild(MW.preferredWeaponName)
    if humanoid and tool and tool:IsA("Tool") then
        pcall(function() humanoid:EquipTool(tool) end)
    end
    return getWeapon()
end

function MW.groundAt(pos,npc)
    local char=getCharacter()
    local params=RaycastParams.new()
    params.FilterType=Enum.RaycastFilterType.Exclude
    local exclusions={}
    if char then table.insert(exclusions,char) end
    if npc then table.insert(exclusions,npc) end
    params.FilterDescendantsInstances=exclusions
    params.IgnoreWater=true
    local hit=workspace:Raycast(pos+Vector3.new(0,24,0),Vector3.new(0,-80,0),params)
    return hit and hit.Position or nil
end

-- This step is never a prerequisite for attempting Tool:Activate().
function MW.shortStep(npc,id)
    local root,hum=getRoot(),getHumanoid()
    local pos=enemyPosition(npc)
    if not root or not hum or not pos then return false end
    local flat=horizontalDistance(root.Position,pos)
    if flat>7 then return false end
    local from=root.Position
    local d=Vector3.new(pos.X-from.X,0,pos.Z-from.Z)
    if d.Magnitude<0.1 then d=Vector3.new(1,0,0) end
    local toward=d.Unit
    local sideways=Vector3.new(-toward.Z,0,toward.X)
    local direction=(flat>3.3) and toward or sideways
    local goal=from+direction*1.1
    local ground1,ground2=MW.groundAt(from,npc),MW.groundAt(goal,npc)
    if not ground1 or not ground2 or math.abs(ground1.Y-ground2.Y)>3.5 then
        return false
    end
    hum:MoveTo(goal)
    local deadline=os.clock()+1.0
    while MW.worldFarmValid(id) and os.clock()<deadline do
        task.wait(0.08)
        local current=getRoot()
        if not current then return false end
        local moved=horizontalDistance(current.Position,from)
        if moved>=0.55 and moved<5.0 then
            hum:MoveTo(current.Position)
            return true
        end
    end
    hum:MoveTo(root.Position)
    return false
end

function MW.approachOnce(npc,id)
    local char,root,hum=getCharacter(),getRoot(),getHumanoid()
    local pos=enemyPosition(npc)
    if not char or not root or not hum or not pos then return false end
    local flat=horizontalDistance(root.Position,pos)
    if MW.lastApproachedNPC==npc then
        -- Never repeat teleports to the SAME living instance after rollback.
        if flat<=7 then MW.shortStep(npc,id) end
        return flat<=7
    end
    MW.lastApproachedNPC=npc
    if flat>35 then
        MW.worldStatusLabel:SetValue("Move closer to locked NPC ("..math.floor(flat).." studs)")
        return false
    end
    if flat>6 then
        -- One bounded teleport on acquisition of THIS respawn, never mid-combat.
        local outward=Vector3.new(root.Position.X-pos.X,0,root.Position.Z-pos.Z)
        if outward.Magnitude<0.1 then outward=Vector3.new(1,0,0) end
        outward=outward.Unit
        local dirs={outward,-outward,Vector3.new(-outward.Z,0,outward.X)}
        local feetGap=3
        local boxOk,boxCF,boxSize=pcall(function() return char:GetBoundingBox() end)
        if boxOk then feetGap=math.clamp(root.Position.Y-(boxCF.Position.Y-boxSize.Y/2),2,5) end
        local landed=false
        for _,dir in ipairs(dirs) do
            local destXZ=pos+dir*3.3
            local ground=MW.groundAt(destXZ,npc)
            if ground and math.abs(ground.Y-pos.Y)<=9 then
                local landing=Vector3.new(destXZ.X,ground.Y+feetGap+0.2,destXZ.Z)
                hum:MoveTo(root.Position)
                char:PivotTo(CFrame.lookAt(landing,Vector3.new(pos.X,landing.Y,pos.Z)))
                task.wait(0.25)
                root=getRoot()
                if root and horizontalDistance(root.Position,landing)<5.5 then
                    landed=true
                    break
                end
            end
        end
        if not landed then
            MW.worldStatusLabel:SetValue("No safe landing; approach enemy manually")
            return false
        end
    end
    -- Prefer genuine movement, but do NOT block the first attack if it is
    -- already within reach or movement cannot be confirmed (V5.7.0 bug).
    MW.shortStep(npc,id)
    return true
end

function MW.addLootOrigin(position)
    if not MW.worldAutoLoot or not position then return end
    table.insert(MW.dropOrigins,{pos=position,expiry=os.clock()+20})
    while #MW.dropOrigins>2 do table.remove(MW.dropOrigins,1) end
end

function MW.findLoot()
    if not MW.worldAutoLoot then return nil end
    local now=os.clock()
    for i=#MW.dropOrigins,1,-1 do
        if MW.dropOrigins[i].expiry<now then table.remove(MW.dropOrigins,i) end
    end
    if #MW.dropOrigins==0 then return nil end
    local folder=workspace:FindFirstChild("WorldBits")
    if not folder then return nil end
    local best,bestDist=nil,math.huge
    local root=getRoot()
    if not root then return nil end
    for _,drop in ipairs(folder:GetChildren()) do
        if (MW.dropAttempts[drop] or 0)<now then
            local prompt=drop:FindFirstChildWhichIsA("ProximityPrompt",true)
            if prompt and prompt.Enabled then
                local parent=prompt.Parent
                local part=parent and parent:FindFirstAncestorWhichIsA("BasePart")
                local pos=parent and ((parent:IsA("Attachment") and parent.WorldPosition)
                    or (parent:IsA("BasePart") and parent.Position)
                    or (part and part.Position))
                if pos then
                    for _,origin in ipairs(MW.dropOrigins) do
                        if (pos-origin.pos).Magnitude<=24 then
                            local dist=(root.Position-pos).Magnitude
                            if dist<bestDist then
                                best,bestDist={obj=drop,prompt=prompt,pos=pos},dist
                            end
                            break
                        end
                    end
                end
            end
        end
    end
    return best
end

function MW.collectLoot(id)
    local drop=MW.findLoot()
    if not drop then return false end
    local root,hum,char=getRoot(),getHumanoid(),getCharacter()
    if not root or not hum or not char then return false end
    local reach=math.max(1,drop.prompt.MaxActivationDistance)
    local dist=(root.Position-drop.pos).Magnitude
    if dist>reach*0.8 then
        if dist>22 then return false end
        -- Only local loot from THIS killed NPC: one bounded pickup movement.
        hum:MoveTo(root.Position)
        char:PivotTo(CFrame.new(drop.pos+Vector3.new(0,2.5,0)))
        task.wait(0.18)
    end
    root=getRoot()
    if not root or not drop.prompt.Parent or not drop.prompt.Enabled
        or (root.Position-drop.pos).Magnitude>reach then
        MW.dropAttempts[drop.obj]=os.clock()+1.1
        return true
    end
    local fired=false
    if type(fireproximityprompt)=="function" then
        fired=pcall(fireproximityprompt,drop.prompt)
    end
    if not fired then
        pcall(function() drop.prompt:InputHoldBegin() end)
        task.wait(math.max(0.08,math.min(1,drop.prompt.HoldDuration+0.10)))
        pcall(function() drop.prompt:InputHoldEnd() end)
    end
    local stop=os.clock()+0.7
    while MW.worldFarmValid(id) and os.clock()<stop do
        if not drop.obj.Parent or not drop.prompt.Parent or not drop.prompt.Enabled then
            debugPrint("[WORLD][SINGLE] LOOT_PICKED")
            MW.dropAttempts[drop.obj]=os.clock()+60
            return true
        end
        task.wait(0.08)
    end
    MW.dropAttempts[drop.obj]=os.clock()+1.0
    debugPrint("[WORLD][SINGLE] Loot attempted; not yet confirmed")
    return true
end

-- Boss drops can appear in staggered batches. Allow several pickup passes,
-- including a short no-drop window, instead of a fixed 2.1-second deadline.
-- This only uses the existing, origin-restricted MW.findLoot/collectLoot logic.
function MW.collectBossLootBurst(id)
    if not MW.worldAutoLoot then return end
    local started=os.clock()
    local maxDuration=15
    local minimumWindow=3.0
    local quietWindow=1.8
    local lastVisible=started
    local attempts=0
    while MW.worldFarmValid(id) and MW.worldAutoLoot and os.clock()-started<maxDuration do
        local drop=MW.findLoot()
        if drop then
            lastVisible=os.clock()
            attempts+=1
            MW.collectLoot(id)
            -- A fresh check is essential because another prompt may spawn
            -- after the previously collected one disappears.
            task.wait(0.10)
        else
            if os.clock()-started>=minimumWindow and
                os.clock()-lastVisible>=quietWindow then
                break
            end
            task.wait(0.12)
        end
    end
    print("[WORLD][BOSS] LOOT_BURST_FINISHED", "attempts",attempts,
        "elapsed",math.floor((os.clock()-started)*10)/10,
        "possibleRemaining",MW.findLoot()~=nil)
end

-- ================================
-- WORLD BOSS | VALIDATED LIVE SPAWN WATCHER
-- ================================
-- Real in-game diagnostics verified: Skullcrab has Animal="Skullcrab",
-- Tier="Boss", IsBoss=nil, and lives under Animal_Live.Aggressors.
-- Tier="Boss" is therefore authoritative even with no IsBoss flag.
-- Do NOT classify Tier="Huge" or other sizes as world bosses.
function MW.bossName(npc)
    local name=npc:GetAttribute("Animal") or npc:GetAttribute("BossName")
        or npc:GetAttribute("DisplayName")
    if type(name)=="string" and name~="" then
        return MW.canonicalBossName(name)
    end
    local raw=npc.Name
    if type(raw)=="string" and not raw:match("^%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x") then
        return MW.canonicalBossName(raw)
    end
    return nil
end

function MW.isVerifiedBoss(npc)
    if not npc or not npc:IsA("Model") then return false end
    -- Verified on a live Skullcrab: Tier="Boss" is the boss flag.
    -- NPCs have generated UIDs as model names, so use attributes.
    local tier = npc:GetAttribute("Tier")
    if type(tier) == "string" and tier:match("^%s*(.-)%s*$"):lower() == "boss" then
        return true
    end
    for _,key in ipairs({"IsBoss","Boss","_IsBoss","IsWorldBoss","WorldBoss"}) do
        local v=npc:GetAttribute(key)
        if v==true or v==1 or (type(v)=="string" and v:lower()=="true") then
            return true
        end
    end
    for _,key in ipairs({"NPCType","EnemyType","Category","Type"}) do
        local v=npc:GetAttribute(key)
        if type(v)=="string" and v:lower():find("boss",1,true) then return true end
    end
    local p=npc.Parent
    while p and p~=workspace do
        local folderName=p.Name:lower()
        if folderName=="bosses" or folderName=="worldbosses"
            or folderName=="world_bosses" or folderName=="boss_live" then
            return true
        end
        if folderName=="halloweendungeon_chain" then return false end
        p=p.Parent
    end
    return false
end

function MW.scanBossNPCs()
    local out,seen={},{}
    local live=workspace:FindFirstChild("Animal_Live")
    local containers={}
    for _,folder in ipairs({"Aggressors","Bosses","WorldBosses"}) do
        local candidate=live and live:FindFirstChild(folder)
        if candidate then table.insert(containers,candidate) end
    end
    for _,folder in ipairs({"Bosses","WorldBosses","World_Bosses"}) do
        local candidate=workspace:FindFirstChild(folder)
        if candidate then table.insert(containers,candidate) end
    end
    for _,container in ipairs(containers) do
        if container then
            for _,inst in ipairs(container:GetDescendants()) do
                if inst:IsA("Model") and not seen[inst] and MW.isVerifiedBoss(inst) then
                    local hp=inst:GetAttribute("Health")
                    if type(hp)=="number" and hp>0 and enemyPosition(inst) then
                        seen[inst]=true
                        table.insert(out,inst)
                    end
                end
            end
            -- GetDescendants excludes the container itself (rare model container).
            if container:IsA("Model") and not seen[container]
                and MW.isVerifiedBoss(container) then
                local hp=container:GetAttribute("Health")
                if type(hp)=="number" and hp>0 and enemyPosition(container) then
                    seen[container]=true
                    table.insert(out,container)
                end
            end
        end
    end
    return out
end

function MW.refreshBossList(force)
    local names={}
    for _,npc in ipairs(MW.scanBossNPCs()) do
        local name=MW.bossName(npc)
        if name then MW.bossKnownLabels[name]=true end
    end
    -- Merge alternate names from NPCs and signs, also if cached earlier.
    local canonicalLabels={}
    for name in pairs(MW.bossKnownLabels) do
        local canonical=MW.canonicalBossName(name)
        if canonical then canonicalLabels[canonical]=true end
    end
    MW.bossKnownLabels=canonicalLabels
    for name in pairs(canonicalLabels) do table.insert(names,name) end
    table.sort(names)
    local signature=table.concat(names,"|")
    if not force and signature==MW.lastBossSignature then return end
    MW.lastBossSignature=signature
    local values={{Title="Any detected World Boss",Value="__any_boss"}}
    for _,name in ipairs(names) do
        table.insert(values,{Title=name,Value=name})
    end
    MW.bossUiRefreshing=true
    pcall(function() MW.bossDropdown:Refresh(values,false) end)
    MW.bossUiRefreshing=false
    print("[WORLD][BOSS] Verified boss names:",#names,
        #names>0 and signature or "none loaded; Any Boss still available")
end

function MW.availableBoss()
    if not MW.bossFarmEnabled or os.clock()<MW.bossRetryUntil then return nil end
    local now=os.clock()
    if now<MW.bossScanAt and MW.cachedBoss and MW.cachedBoss.Parent then
        local hp=MW.cachedBoss:GetAttribute("Health")
        if type(hp)=="number" and hp>0 then return MW.cachedBoss end
    end
    if now<MW.bossScanAt then return nil end
    MW.bossScanAt=now+0.6
    MW.cachedBoss=nil
    local root=getRoot()
    if not root then return nil end
    local best,bestDist=nil,math.huge
    local newName=false
    for _,npc in ipairs(MW.scanBossNPCs()) do
        local name=MW.bossName(npc)
        if name and not MW.bossKnownLabels[name] then
            MW.bossKnownLabels[name]=true
            newName=true
        end
        if (MW.selectedBossName=="__any_boss" or
            name==MW.canonicalBossName(MW.selectedBossName)) then
            local pos=enemyPosition(npc)
            if pos then
                local d=(pos-root.Position).Magnitude
                if d<bestDist then best,bestDist=npc,d end
            end
        end
    end
    if newName then task.defer(function() if gui.Parent then MW.refreshBossList() end end) end
    -- The standalone single-spot build has no proven safe cross-map travel.
    -- Never seize movement control for a faraway boss and deadlock local farming.
    if best and bestDist>38 then
        if now>MW.lastBossRangeWarning+9 then
            MW.lastBossRangeWarning=now
            MW.bossStatusLabel:SetValue("Boss spawned, "..math.floor(bestDist).." studs away (approach area)")
            print("[WORLD][BOSS] SPAWN_OUT_OF_LOCAL_RANGE",MW.bossName(best),math.floor(bestDist))
        end
        return nil
    end
    MW.cachedBoss=best
    return best
end

function MW.bossApproach(npc,id)
    local root,hum,char=getRoot(),getHumanoid(),getCharacter()
    local pos=enemyPosition(npc)
    if not root or not hum or not char or not pos then return false end
    local dist=horizontalDistance(root.Position,pos)
    if dist>38 then return false end
    if dist>6 then
        local away=Vector3.new(root.Position.X-pos.X,0,root.Position.Z-pos.Z)
        if away.Magnitude<0.1 then away=Vector3.new(1,0,0) end
        local dirs={away.Unit,-away.Unit,Vector3.new(-away.Unit.Z,0,away.Unit.X)}
        local boxOk,boxCF,boxSize=pcall(function() return char:GetBoundingBox() end)
        local feetGap=3
        if boxOk then feetGap=math.clamp(root.Position.Y-(boxCF.Position.Y-boxSize.Y/2),2,5) end
        local arrived=false
        for _,dir in ipairs(dirs) do
            local landXZ=pos+dir*3.3
            local ground=MW.groundAt(landXZ,npc)
            if ground and math.abs(ground.Y-pos.Y)<=10 then
                local land=Vector3.new(landXZ.X,ground.Y+feetGap+0.2,landXZ.Z)
                hum:MoveTo(root.Position)
                char:PivotTo(CFrame.lookAt(land,Vector3.new(pos.X,land.Y,pos.Z)))
                task.wait(0.30)
                root=getRoot()
                if root and horizontalDistance(root.Position,pos)<7 then
                    arrived=true
                    break
                end
            end
        end
        if not arrived then return false end
    end
    MW.shortStep(npc,id)
    return true
end

function MW.returnToLockedSpawn()
    local char,root,hum=getCharacter(),getRoot(),getHumanoid()
    local spawn=MW.lockedSpawn
    if not spawn or not root or not char or not hum then return false end
    local distance=horizontalDistance(root.Position,spawn.pos)
    if distance<=8 then return true end
    -- The local boss mode intentionally avoids unverified cross-map travel.
    if distance>38 then
        MW.worldStatusLabel:SetValue("Boss done; move back to locked enemy spawn ("..math.floor(distance).." studs)")
        print("[WORLD][BOSS] RETURN_TOO_FAR",math.floor(distance))
        return false
    end
    local point=spawn.pos+Vector3.new(3.0,0,0)
    local ground=MW.groundAt(point,nil)
    if not ground then return false end
    local ok,cf,size=pcall(function() return char:GetBoundingBox() end)
    local foot=3
    if ok then foot=math.clamp(root.Position.Y-(cf.Position.Y-size.Y/2),2,5) end
    local dest=Vector3.new(point.X,ground.Y+foot+0.2,point.Z)
    hum:MoveTo(root.Position)
    char:PivotTo(CFrame.new(dest))
    task.wait(0.28)
    local newRoot=getRoot()
    local arrived=newRoot and horizontalDistance(newRoot.Position,spawn.pos)<10
    if not arrived then print("[WORLD][BOSS] RETURN_ROLLBACK_OR_BLOCKED") end
    return arrived==true
end

function MW.fightBoss(npc,id)
    if not MW.worldFarmValid(id) or not MW.bossFarmEnabled then return false end
    local name=MW.bossName(npc) or "Boss"
    MW.bossStatusLabel:SetValue("Fighting "..name.." – normal farm paused")
    print("[WORLD][BOSS] PRIORITY_START",name)
    if not MW.bossApproach(npc,id) then
        MW.bossStatusLabel:SetValue("Boss unreachable; retry after cooldown")
        MW.bossRetryUntil=os.clock()+5
        print("[WORLD][BOSS] APPROACH_FAILED",name)
        return false
    end
    local startHp=npc:GetAttribute("Health")
    if type(startHp)~="number" or startHp<=0 then return false end
    local prevHp=startHp
    local lastHit=os.clock()
    local nextAttack=0
    local nextMove=0
    local attacks=0
    local hitCount=0
    local lastPos=enemyPosition(npc)
    -- Knockback recovery is strictly for boss combat; the single enemy farm is unchanged.
    local recoverSince=nil
    local recoverBestDistance=math.huge
    local recoverProgressAt=0
    local recoverLastLog=0
    while MW.worldFarmValid(id) and MW.bossFarmEnabled and MW.bossActive do
        local hp=npc.Parent and npc:GetAttribute("Health") or 0
        if type(hp)~="number" or hp<=0 then
            if attacks>0 or hitCount>0 then
                MW.bossKills+=1
                MW.bossKillsLabel:SetValue(tostring(MW.bossKills))
                local now=os.clock()
                MW.lastBossKillAt=now
                MW.addLootOrigin(lastPos)
                print("[WORLD][BOSS] KILL_CONFIRMED",name,"loot priority")
                MW.bossStatusLabel:SetValue("Boss defeated; collecting boss loot")
                MW.collectBossLootBurst(id)
                MW.bossRetryUntil=os.clock()+1.4
                MW.bossStatusLabel:SetValue("Boss defeated; waiting for next spawn")
                return true
            end
            return false
        end
        if hp<prevHp then
            hitCount+=1
            lastHit=os.clock()
            print("[WORLD][BOSS] TRUE_HIT",name,math.floor(prevHp),math.floor(hp))
        end
        prevHp=hp
        local pos=enemyPosition(npc)
        local root,hum=getRoot(),getHumanoid()
        if not pos or not root or not hum then return false end
        lastPos=pos
        local flat=horizontalDistance(root.Position,pos)
        local vert=math.abs(root.Position.Y-pos.Y)
        if flat>5.5 or vert>8 then
            if flat>17 or vert>17 then
                -- A boss knockback can push the character beyond the old 17-stud
                -- chase range. Reissue MoveTo towards the CURRENT boss position,
                -- not a stale point from before the knockback.
                local now=os.clock()
                if not recoverSince then
                    recoverSince=now
                    recoverProgressAt=now
                    recoverBestDistance=flat
                    MW.bossStatusLabel:SetValue("Recovering from boss knockback ("..math.floor(flat).." studs)")
                    print("[WORLD][BOSS] KNOCKBACK_RECOVER_START",name,math.floor(flat))
                end
                if flat<recoverBestDistance-2 then
                    recoverBestDistance=flat
                    recoverProgressAt=now
                end
                if now>=nextMove then
                    local diff=Vector3.new(root.Position.X-pos.X,0,root.Position.Z-pos.Z)
                    if diff.Magnitude<0.1 then diff=Vector3.new(1,0,0) end
                    local dest=pos+diff.Unit*3
                    hum:MoveTo(Vector3.new(dest.X,root.Position.Y,dest.Z))
                    nextMove=now+0.45
                end
                if now-recoverLastLog>=3 then
                    recoverLastLog=now
                    print("[WORLD][BOSS] KNOCKBACK_RECOVER",name,"distance",math.floor(flat),
                        "best",math.floor(recoverBestDistance),"noProgress",math.floor(now-recoverProgressAt))
                end
                -- Do not hold an encounter indefinitely when the player is
                -- displaced and normal Humanoid movement cannot recover.
                if now-recoverProgressAt>7 or now-recoverSince>18 then
                    hum:MoveTo(root.Position)
                    MW.bossRetryUntil=now+5
                    MW.bossStatusLabel:SetValue("Boss recovery stuck; move closer and retry")
                    warn("[WORLD][BOSS] KNOCKBACK_RECOVER_STUCK",name,"distance",math.floor(flat))
                    return false
                end
            elseif os.clock()>=nextMove then
                if recoverSince then
                    print("[WORLD][BOSS] KNOCKBACK_RECOVER_CLOSE",name,math.floor(flat))
                    recoverSince=nil
                    recoverBestDistance=math.huge
                end
                local diff=Vector3.new(root.Position.X-pos.X,0,root.Position.Z-pos.Z)
                if diff.Magnitude<0.1 then diff=Vector3.new(1,0,0) end
                local dest=pos+diff.Unit*2.4
                hum:MoveTo(Vector3.new(dest.X,root.Position.Y,dest.Z))
                nextMove=os.clock()+0.5
            end
        else
            if recoverSince then
                print("[WORLD][BOSS] KNOCKBACK_RECOVER_DONE",name)
                recoverSince=nil
                recoverBestDistance=math.huge
            end
            if os.clock()>=nextAttack then
                local tool=MW.equipWeapon()
                if tool then
                    local ok,err=pcall(function() tool:Activate() end)
                    MW.worldAttacks+=1
                    MW.worldAttackLabel:SetValue(tostring(MW.worldAttacks))
                    nextAttack=os.clock()+0.65
                    attacks+=1
                    if not ok then warn("[WORLD][BOSS] Attack error",err) end
                end
            end
            if os.clock()-lastHit>2.7 and os.clock()>=nextMove then
                MW.shortStep(npc,id)
                nextMove=os.clock()+1.1
            end
        end
        -- Priority contract: once combat with a spawned boss begins, the
        -- normal farm stays paused until the boss dies/disappears or the
        -- user disables Boss Farm. Never classify missing damage as a kill.
        if os.clock()-lastHit>24 and os.clock()>=MW.nextBossStallWarning then
            MW.nextBossStallWarning=os.clock()+12
            MW.bossStatusLabel:SetValue("Boss active; waiting for registered hits")
            warn("[WORLD][BOSS] NO_HP_CHANGE; boss still has priority",name,
                "distance",math.floor(flat))
        end
        task.wait(0.1)
    end
    return false
end

function MW.fight(npc,id)
    if not MW.worldFarmValid(id) or not npc or not npc.Parent then return end
    -- ONE fixed NPC instance per respawn. No target rotation and no combat re-teleport.
    MW.worldStatusLabel:SetValue("Fighting "..MW.selectedEnemyName.." (one spawn)")
    if not MW.approachOnce(npc,id) then
        task.wait(0.35)
        return
    end
    local hp0=npc:GetAttribute("Health")
    if type(hp0)~="number" or hp0<=0 then return end
    local prevHp=hp0
    local lastHit=os.clock()
    local nextAttack=0
    local nextMove=0
    local hits=0
    local attacks=0
    while MW.worldFarmValid(id) and MW.activeNPC==npc do
        if MW.bossFarmEnabled and MW.availableBoss() then
            MW.bossActive=true
            MW.lastApproachedNPC=nil
            print("[WORLD][BOSS] PREEMPT_SINGLE_ENEMY")
            return
        end
        local hp=npc.Parent and npc:GetAttribute("Health") or 0
        if type(hp)~="number" or hp<=0 then
            if hits>0 or attacks>0 then
                MW.worldDefeated+=1
                MW.worldKillsLabel:SetValue(tostring(MW.worldDefeated))
                MW.addLootOrigin(enemyPosition(npc) or MW.lockedSpawn.pos)
                debugPrint("[WORLD][SINGLE] KILL confirmed; collecting loot before respawn")
                local untilTime=os.clock()+1.5
                while MW.worldFarmValid(id) and os.clock()<untilTime do
                    if not MW.collectLoot(id) then task.wait(0.12) end
                end
            end
            return
        end
        if hp<prevHp then
            hits+=1
            lastHit=os.clock()
            debugPrint("[WORLD][SINGLE] TRUE_HIT",math.floor(prevHp),math.floor(hp))
        end
        prevHp=hp
        local root=getRoot()
        local pos=enemyPosition(npc)
        local hum=getHumanoid()
        if not root or not pos or not hum then return end
        local flat=horizontalDistance(root.Position,pos)
        local vert=math.abs(root.Position.Y-pos.Y)
        if MW.worldAutoLoot and MW.findLoot() then
            MW.collectLoot(id)
            root=getRoot()
            if not root then return end
            flat=horizontalDistance(root.Position,pos)
            vert=math.abs(root.Position.Y-pos.Y)
        end
        -- Never teleport again while fighting this NPC. Recover knockback by walking.
        if (flat>5.5 or vert>8) and os.clock()>=nextMove then
            if flat<=16 and vert<=16 then
                local delta=Vector3.new(root.Position.X-pos.X,0,root.Position.Z-pos.Z)
                if delta.Magnitude<0.1 then delta=Vector3.new(1,0,0) end
                local goal=pos+delta.Unit*2.3
                hum:MoveTo(Vector3.new(goal.X,root.Position.Y,goal.Z))
            else
                MW.worldStatusLabel:SetValue("Locked enemy too far; move closer ("..math.floor(flat)..")")
            end
            nextMove=os.clock()+0.55
        elseif flat<=5.5 and vert<=8 then
            -- Tool activation is never blocked by an unconfirmed 1-stud step.
            if os.clock()>=nextAttack then
                local tool=MW.equipWeapon()
                if tool then
                    local ok,err=pcall(function() tool:Activate() end)
                    attacks+=1
                    MW.worldAttacks+=1
                    MW.worldAttackLabel:SetValue(tostring(MW.worldAttacks))
                    nextAttack=os.clock()+0.65
                    if attacks==1 or (not ok) then
                        debugPrint("[WORLD][SINGLE] ATTACK_REQUESTED",tool.Name,"ok",ok,tostring(err))
                    end
                elseif os.clock()-MW.lastCombatWarning>3 then
                    MW.lastCombatWarning=os.clock()
                    warn("[WORLD][SINGLE] No equipped weapon. Equip weapon manually.")
                end
            end
            -- Only micro-adjust locally; do not abandon or re-teleport this NPC.
            if os.clock()-lastHit>2.5 and os.clock()>=nextMove then
                MW.shortStep(npc,id)
                nextMove=os.clock()+1.5
            end
        end
        if os.clock()-MW.lastCombatLog>5 then
            MW.lastCombatLog=os.clock()
            debugPrint("[WORLD][SINGLE] LOCKED",MW.selectedEnemyName,
                "distance",math.floor(flat*10)/10,"height",math.floor(vert*10)/10,
                "HP",math.floor(hp),"attacks",attacks,"hits",hits)
        end
        task.wait(0.1)
    end
end

function MW.runFarm(id)
    print("[WORLD][CTRL] START", "enemy",MW.enemyFarmEnabled,"boss",MW.bossFarmEnabled)
    while MW.worldFarmValid(id) do
        -- Boss has absolute movement/combat priority. There is only ONE
        -- controller coroutine, so normal and boss movement never overlap.
        local boss=MW.bossFarmEnabled and MW.availableBoss() or nil
        if boss then
            MW.bossActive=true
            MW.worldStatusLabel:SetValue("Paused for World Boss")
            local ok,err=pcall(MW.fightBoss,boss,id)
            if not ok then warn("[WORLD][BOSS] Encounter error",tostring(err)) end
            MW.bossActive=false
            MW.cachedBoss=nil
            MW.bossScanAt=0
            -- Enemy combat must reacquire its prior spawn after a boss fight.
            -- The old 'already approached this NPC' cache would otherwise
            -- prevent restarting after the boss moved the player away.
            MW.lastApproachedNPC=nil
            if MW.enemyFarmEnabled and MW.lockedSpawn then
                MW.returnToLockedSpawn()
                MW.worldStatusLabel:SetValue("Resuming single enemy farm")
            end
            task.wait(0.2)
        elseif MW.enemyFarmEnabled and MW.lockedSpawn then
            local current=MW.currentNpc()
            if MW.worldAutoLoot and MW.findLoot() then
                MW.collectLoot(id)
            elseif current then
                if not MW.equipWeapon() then
                    MW.worldStatusLabel:SetValue("Equip combat weapon manually")
                    task.wait(0.35)
                else
                    local ok,err=pcall(MW.fight,current,id)
                    if not ok then warn("[WORLD][SINGLE] Fight exception",tostring(err)) end
                    task.wait(0.10)
                end
            else
                MW.worldStatusLabel:SetValue("Waiting for respawn at locked spawn")
                task.wait(0.25)
            end
        else
            task.wait(0.4)
        end
        -- The separate read-only sign watcher below provides the countdown.
        -- Live NPCs, not the sign text, continue to drive boss engagement.
    end
    print("[WORLD][CTRL] STOP")
end

function MW.stopWorldFarm()
    MW.enemyFarmEnabled=false
    MW.bossFarmEnabled=false
    MW.bossActive=false
    MW.worldFarmRunning=false
    MW.worldFarmMode=nil
    MW.worldFarmSession+=1
    MW.activeNPC=nil
    MW.lastApproachedNPC=nil
    MW.lockedSpawn=nil
    MW.cachedBoss=nil
    MW.dropOrigins={}
    if not MW.worldGuiSync then
        MW.worldGuiSync=true
        if MW.worldEnemiesModule:Get() then MW.worldEnemiesModule:Set(false) end
        if MW.bossModule:Get() then MW.bossModule:Set(false) end
        MW.worldGuiSync=false
    end
    MW.worldStatusLabel:SetValue("Stopped")
    MW.bossStatusLabel:SetValue("Boss farm off")
end

function MW.setWorldFarmMode(mode,enabled)
    if MW.worldGuiSync then return end
    if mode~="enemy" and mode~="boss" then return end
    local module=(mode=="enemy") and MW.worldEnemiesModule or MW.bossModule
    local function reject(message)
        if message then MW.worldStatusLabel:SetValue(message) end
        MW.worldGuiSync=true
        if module:Get() then module:Set(false) end
        MW.worldGuiSync=false
    end
    if enabled then
        if not accessGranted or os.clock()>=accessDeadline then
            reject("Valid license required")
            accessGui.Enabled=true
            return
        end
        if mode=="enemy" then
            if not MW.validArea(MW.selectedArea) or not MW.selectedEnemyName then
                reject("Select Area and Enemy first")
                return
            end
            if not MW.lockedSpawn then
                if not MW.lockNearestSpawn() then
                    reject("No matching spawn nearby; approach/capture area")
                    return
                end
            end
            if state._uiRefs.stopPolyHubAutomation then pcall(state._uiRefs.stopPolyHubAutomation, "Main World") end
            if running and onSpeedrunToggle then onSpeedrunToggle(false) end
            MW.enemyFarmEnabled=true
        else
            if state._uiRefs.stopPolyHubAutomation then pcall(state._uiRefs.stopPolyHubAutomation, "Main World") end
            if running and onSpeedrunToggle then onSpeedrunToggle(false) end
            MW.bossFarmEnabled=true
            MW.bossRetryUntil=0
            MW.bossScanAt=0
            MW.bossStatusLabel:SetValue("Watching boss spawns; normal farm continues")
            MW.refreshBossList(false)
        end
    else
        if mode=="enemy" then
            MW.enemyFarmEnabled=false
            MW.activeNPC=nil
            MW.lastApproachedNPC=nil
            MW.lockedSpawn=nil
        else
            MW.bossFarmEnabled=false
            MW.bossActive=false
            MW.cachedBoss=nil
            MW.bossStatusLabel:SetValue("Boss farm off")
        end
    end
    if not MW.enemyFarmEnabled and not MW.bossFarmEnabled then
        MW.stopWorldFarm()
        return
    end
    if not MW.worldFarmRunning then
        MW.dropOrigins={}
        MW.dropAttempts={}
        MW.worldFarmSession+=1
        MW.worldFarmRunning=true
        local weapon=getWeapon()
        MW.preferredWeaponName=weapon and weapon.Name or MW.preferredWeaponName
        local id=MW.worldFarmSession
        task.spawn(function()
            local ok,err=pcall(MW.runFarm,id)
            if not ok then
                warn("[WORLD][CTRL] FARM_ERROR",tostring(err))
                if MW.worldFarmSession==id then MW.stopWorldFarm() end
            end
        end)
    end
end
MW.onWorldFarmToggle=function(mode,enabled)
    MW.setWorldFarmMode(mode,enabled)
end


task.spawn(function()
    task.wait(1)
    if gui.Parent then
        MW.refreshAreaEnemies()
        MW.discoverBossSigns(true)
        MW.refreshBossList(true)
        MW.showSelectedBossSignTimer()
    end
end)

-- Passive, read-only in-world respawn display. No travel, no attack, no event hooks.
task.spawn(function()
    while gui.Parent do
        local ok,err=pcall(function()
            MW.discoverBossSigns(false)
            MW.showSelectedBossSignTimer()
        end)
        if not ok then
            -- Keep the controller alive even if a streamed GUI element disappears.
            if CFG.DEBUG_MODE then warn("[WORLD][BOSS][SIGN] Read error:",tostring(err)) end
        end
        task.wait(1.0)
    end
end)

-- AN / AUS BUTTON

-- ============================================
onSpeedrunToggle = function(enabled)
    if enabled and selectedDungeonId ~= "halloween" then
        setButton(false)
        statusLabel.Text = "Select Halloween Dungeon before starting"
        return
    end
    if enabled and (not accessGranted or os.clock() >= accessDeadline) then
        setButton(false)
        accessGui.Enabled = true
        accessStatus.Text = "Please verify a valid key."
        return
    end
    if enabled and MW.worldFarmRunning and MW.stopWorldFarm then
        MW.stopWorldFarm()
    end
    if enabled and state._uiRefs.stopPolyHubAutomation then
        pcall(state._uiRefs.stopPolyHubAutomation, "Dungeon Halloween")
    end
    if running == enabled then return end
    running = enabled
    sessionId = sessionId + 1
    if running then
        dungeonComplete = false
        waitingForRestart = false
        replayAttempted = false
        replayAttemptAt = 0
        clearSceneReplay()
        skippedEnemies = {}
        usedDoors = {}
        lastRoomAttempt = 0
        lootCheckedRoom = nil
        approachRoom = nil
        approachDoor = nil
        approachDirection = nil
        clearPendingDoor()
        setButton(true)
        statusLabel.Text = "Speedrun started"
        local id = sessionId
        task.spawn(startSpeedrun, id)
    else
        clearPendingDoor()
        setButton(false)
        statusLabel.Text = "Speedrun stopped"
        stopMovement()
        clearTarget()
    end
end


-- Castle loot is an opt-in hook. It runs only after the existing Castle controller
-- confirms the GraveGolem transition, and only scans verified WorldBits Pick Up drops
-- near the last known Golem position. The original route/combat code remains unchanged.
local lastCastleGolemPosition = nil
local castleLootBusy = false

local function collectCastleDropsAt(origin)
    if not state.castleAutoLoot or typeof(origin) ~= "Vector3" or castleLootBusy then return 0 end
    castleLootBusy = true
    local started = os.clock()
    local lastVisible = started
    local attempted = {}
    local collected = 0
    local maxDuration = 5.0
    print("[AUTO LOOT][CASTELO] Busca iniciada perto do GraveGolem")
    if autoLootStatusLabel then autoLootStatusLabel:SetValue("Castelo: procurando drops perto do GraveGolem...") end
    while gui.Parent and state.castleAutoLoot and os.clock() - started < maxDuration do
        local drops = getNearbyDrops(origin)
        local target = nil
        for _, drop in ipairs(drops) do
            if drop.distance <= 24 and not attempted[drop.model] then
                target = drop
                break
            end
        end
        if target then
            attempted[target.model] = true
            lastVisible = os.clock()
            local character = getCharacter()
            local prompt = target.prompt
            local promptPart = prompt and prompt.Parent
            if character and prompt and promptPart and promptPart:IsA("BasePart")
                and prompt.Enabled and target.model.Parent then
                local destination = promptPart.Position + Vector3.new(0, 2, 0)
                pcall(function() character:PivotTo(CFrame.new(destination)) end)
                task.wait(0.15)
                local root = getRoot()
                local ready = root and prompt.Parent and prompt.Enabled
                    and (root.Position - promptPart.Position).Magnitude <= math.max(2, prompt.MaxActivationDistance)
                if ready then
                    local dispatched = false
                    if type(fireproximityprompt) == "function" then
                        local ok = pcall(fireproximityprompt, prompt)
                        dispatched = ok
                    end
                    if not dispatched then
                        pcall(function() prompt:InputHoldBegin() end)
                        task.wait(math.clamp((tonumber(prompt.HoldDuration) or 0) + 0.1, 0.1, 1.0))
                        pcall(function() prompt:InputHoldEnd() end)
                    end
                    task.wait(CFG.LOOT_PICKUP_WAIT)
                    if not target.model.Parent or not prompt.Parent or not prompt.Enabled then
                        collected += 1
                    end
                end
            end
        else
            if os.clock() - lastVisible >= 1.2 then break end
            task.wait(0.12)
        end
    end
    castleLootBusy = false
    local result = string.format("Castelo: %d drop(s) confirmados", collected)
    if autoLootStatusLabel then autoLootStatusLabel:SetValue(result) end
    print("[AUTO LOOT][CASTELO]", result)
    return collected
end

task.spawn(function()
    while gui.Parent do
        if castlePhase == "dracula" then
            lastCastleGolemPosition = nil
        elseif castlePhase == "golem" and castleTarget and castleIsGraveGolem(castleTarget) then
            local position = castleEnemyPosition(castleTarget)
            if position then lastCastleGolemPosition = position end
        end
        task.wait(0.15)
    end
end)

local originalCastleGolemTransition = castleRuntime.castleBeginGolemTransition
castleRuntime.castleBeginGolemTransition = function(reason)
    local wasGolemPhase = castlePhase == "golem"
    local origin = nil
    if castleTarget and castleIsGraveGolem(castleTarget) then
        origin = castleEnemyPosition(castleTarget)
    end
    origin = origin or lastCastleGolemPosition
    originalCastleGolemTransition(reason)
    if wasGolemPhase and state.castleAutoLoot and origin then
        -- The Castle controller is in its transition state and waits here;
        -- this prevents the loot movement from racing the fixed exit route.
        local ok, err = pcall(collectCastleDropsAt, origin)
        if not ok then
            castleLootBusy = false
            warn("[AUTO LOOT][CASTELO] Coleta interrompida sem bloquear a rota: " .. tostring(err))
            if autoLootStatusLabel then autoLootStatusLabel:SetValue("Castelo: erro de coleta; rota preservada") end
        end
    end
end

-- Movement modules are mutually exclusive; loot and Auto Sell keep their own toggles.
state._uiRefs.stopExternalAutomation = function(_reason)
    if running and onSpeedrunToggle then pcall(onSpeedrunToggle, false) end
    if MW.worldFarmRunning and MW.stopWorldFarm then pcall(MW.stopWorldFarm) end
end
state._uiRefs.stopPolyHubAutomation = function(_reason)
    if state.castleFarm then
        state.castleFarm = false
        if toggles.castleFarm then toggles.castleFarm(false) end
        pcall(setCastleFarm, false)
    end
    if state.candyFarm then
        state.candyFarm = false
        if toggles.candyFarm then toggles.candyFarm(false) end
        pcall(setGhostFarm, false)
    end
end

print("Poly Hub v38 Modular | Castelo + Dungeon Halloween + Main World + Auto Loot + Auto Sell carregados")
end

installPolyLootModules()
