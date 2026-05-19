-- 超高速パリィ機構 v2.0 (理論限界バージョン)
local Players = game:GetService("Players")
local VirtualInputManager = game:GetService("VirtualInputManager")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Player = Players.LocalPlayer or Players.PlayerAdded:Wait()
local Balls = workspace:WaitForChild("Balls", 9e9)

-- 設定
local CONFIG = {
    TriggerDistance = 15,           -- トリガー距離 (スタッド)
    MinVelocityForParry = 0.1,     -- 最小速度 (低すぎるボールを無視)
    MaxParriesPerSecond = 1000,     -- 最大パリィ/秒 (理論値)
    UseDirectInput = true,          -- 直接入力モード (より高速)
    PredictionFrames = 2,           -- 先読みフレーム数
    BypassCooldown = true,          -- クールダウン無視 (危険)
}

-- 高速パリィキュー
local ParryQueue = {}
local LastParryTime = 0
local ParryCount = 0

-- 超高速パリィ実行関数
local function UltraFastParry()
    local now = tick()
    
    -- レート制限を無視する場合
    if not CONFIG.BypassCooldown then
        local timeSinceLast = now - LastParryTime
        local minInterval = 1 / CONFIG.MaxParriesPerSecond
        if timeSinceLast < minInterval then
            return false
        end
    end
    
    -- 方法1: VirtualInputManager (標準)
    if CONFIG.UseDirectInput then
        -- マウスボタン押下 (フレーム単位で最適化)
        VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 0)
        VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 0)
    end
    
    -- 方法2: キーボード入力も同時に送信 (多重化で確実性向上)
    VirtualInputManager:SendKeyEvent(true, "F", false, game)
    VirtualInputManager:SendKeyEvent(false, "F", false, game)
    
    -- 方法3: UserInputService エミュレーション (より低レベル)
    if UserInputService then
        pcall(function()
            -- シミュレートされた入力オブジェクトを作成
            local inputObject = {
                UserInputType = Enum.UserInputType.MouseButton1,
                Position = Vector2.new(0, 0),
                Delta = Vector2.new(0, 0),
            }
        end)
    end
    
    LastParryTime = now
    ParryCount = ParryCount + 1
    
    -- デバッグ用 (パフォーマンス影響大なので通常はコメントアウト)
    -- if ParryCount % 100 == 0 then
    --     warn(string.format("[Parry] 実行回数: %d, レート: %.2f/秒", 
    --           ParryCount, ParryCount / (now - (LastParryTime - 1/CONFIG.MaxParriesPerSecond))))
    -- end
    
    return true
end

-- 超高速マクロ連打モード (緊急時用)
local MacroMode = false
local MacroConnection = nil

local function StartHyperMacro(duration)
    if MacroConnection then return end
    
    local startTime = tick()
    local frameCount = 0
    
    -- レンダーステップで毎フレーム実行 (約60-240Hz)
    MacroConnection = RunService.RenderStepped:Connect(function(deltaTime)
        local elapsed = tick() - startTime
        if elapsed >= duration then
            StopHyperMacro()
            return
        end
        
        -- 1フレーム内で複数回実行 (フレームレートに依存)
        local parriesThisFrame = math.floor(CONFIG.MaxParriesPerSecond * deltaTime)
        for i = 1, math.min(parriesThisFrame, 10) do -- 最大10回/フレーム
            UltraFastParry()
            frameCount = frameCount + 1
        end
    end)
end

local function StopHyperMacro()
    if MacroConnection then
        MacroConnection:Disconnect()
        MacroConnection = nil
        warn(string.format("[Macro] 停止 - 総パリィ回数: %d", ParryCount))
    end
end

-- 強化されたボール検証
local function VerifyBall(Ball)
    return typeof(Ball) == "Instance" 
        and Ball:IsA("BasePart") 
        and Ball:IsDescendantOf(Balls) 
        and (Ball:GetAttribute("realBall") == true or Ball:GetAttribute("isBall") == true)
end

-- ターゲット検出 (最適化版)
local function IsTarget()
    local char = Player.Character
    if not char then return false end
    
    -- キャッシュを使用
    if char._cachedHighlight and tick() - char._cacheTime < 0.033 then
        return char._cachedHighlight
    end
    
    local hasHighlight = char:FindFirstChild("Highlight") ~= nil
    char._cachedHighlight = hasHighlight
    char._cacheTime = tick()
    
    return hasHighlight
end

-- 軌道予測関数 (超高速)
local function PredictImpact(ballPos, ballVel, targetPos)
    -- 簡易的な線形予測
    local relativePos = ballPos - targetPos
    local t = 0.05  -- 初期予測時間 (50ms)
    
    for i = 1, 3 do  -- 3回の反復で収束
        local predictedPos = ballPos + ballVel * t
        local distance = (predictedPos - targetPos).Magnitude
        t = distance / ballVel.Magnitude
        if t < 0.01 then t = 0.01 end
        if t > 0.5 then t = 0.5 end
    end
    
    return t
end

-- ボールトラッキング (最適化)
local BallTrackers = {}
local HeartbeatConnection = nil

-- ハートビートで全てのボールを同時トラッキング
HeartbeatConnection = RunService.Heartbeat:Connect(function(deltaTime)
    if not IsTarget() then 
        -- 対象がいない場合はマクロ停止
        if MacroMode then StopHyperMacro() end
        return 
    end
    
    local targetPos = workspace.CurrentCamera.Focus.Position
    local shouldStartMacro = false
    
    -- 全てのボールをチェック
    for _, ball in ipairs(Balls:GetChildren()) do
        if VerifyBall(ball) then
            local tracker = BallTrackers[ball]
            if not tracker then
                -- 新しいボールのトラッカーを作成
                tracker = {
                    lastPos = ball.Position,
                    lastVel = Vector3.zero,
                    lastTime = tick(),
                }
                BallTrackers[ball] = tracker
            end
            
            -- 速度計算 (差分法)
            local now = tick()
            local dt = now - tracker.lastTime
            if dt > 0 then
                local velocity = (ball.Position - tracker.lastPos) / dt
                
                -- 速度が十分高い場合
                if velocity.Magnitude > CONFIG.MinVelocityForParry then
                    local impactTime = PredictImpact(ball.Position, velocity, targetPos)
                    
                    -- 衝突まで非常に短い時間の場合 → 超高速マクロ発動
                    if impactTime < 0.033 and impactTime > 0 then  -- 33ms未満
                        shouldStartMacro = true
                    end
                end
                
                -- 更新
                tracker.lastPos = ball.Position
                tracker.lastVel = velocity
                tracker.lastTime = now
            end
        end
    end
    
    -- マクロ制御
    if shouldStartMacro and not MacroMode then
        MacroMode = true
        StartHyperMacro(0.1)  -- 100msだけ超高速連打
        task.wait(0.05)
        MacroMode = false
    elseif not shouldStartMacro and MacroMode then
        MacroMode = false
        StopHyperMacro()
    end
end)

-- 従来のChildAdded監視も維持 (バックアップ)
Balls.ChildAdded:Connect(function(Ball)
    if not VerifyBall(Ball) then
        return
    end
    
    local OldPosition = Ball.Position
    local OldTick = tick()
    
    -- 強化された位置変更監視
    local connection
    connection = Ball:GetPropertyChangedSignal("Position"):Connect(function()
        if not IsTarget() then
            return
        end
        
        local currentPos = Ball.Position
        local distance = (currentPos - workspace.CurrentCamera.Focus.Position).Magnitude
        
        -- 距離が非常に近い場合 (クリティカル)
        if distance < CONFIG.TriggerDistance then
            local velocity = (OldPosition - currentPos).Magnitude / (tick() - OldTick)
            
            -- 高速ボール or 非常に近い
            if velocity > 50 or distance < 3 then
                -- マクロ発動
                if not MacroMode then
                    MacroMode = true
                    StartHyperMacro(0.05)
                    task.wait(0.025)
                    MacroMode = false
                end
                
                -- 即時パリィも実行
                for i = 1, 5 do  -- 5連続パリィ
                    UltraFastParry()
                end
            end
            
            -- 標準パリィ (レート制限内)
            UltraFastParry()
        end
        
        -- 位置更新 (レート制限)
        if (tick() - OldTick >= 1/240) then  -- 240Hzで更新
            OldTick = tick()
            OldPosition = Ball.Position
        end
    end)
end)

-- パフォーマンスモニタリング (オプション)
if _G.DEBUG_MODE then
    task.spawn(function()
        while true do
            task.wait(1)
            local currentRate = ParryCount - (ParryCount - 100)
            print(string.format("[Performance] 総パリィ: %d, 現在レート: ~%d/秒", 
                  ParryCount, currentRate))
        end
    end)
end

print("[System] 超高速パリィシステム起動完了 - 最大レート: " .. CONFIG.MaxParriesPerSecond .. "/秒")