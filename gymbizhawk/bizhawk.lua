---------------------------
-- common functions
---------------------------
local function eval(code)
    local chunk, err = load(code)
    if chunk then
        local success, result = pcall(chunk)
        if success then
            return result
        else
            return nil, "Runtime error: " .. result
        end
    else
        return nil, "Compilation error: " .. err
    end
end

local function split(str, ts)
    if ts == nil then return {} end

    local t = {};
    local i = 1
    for s in string.gmatch(str, "([^" .. ts .. "]+)") do
        t[i] = s
        i = i + 1
    end

    return t
end

local function startswith(str, start)
    return string.sub(str, 1, string.len(start)) == start
end

local function getenv_safe(envVarName, default)
    default = default or ""  -- default args

    local success, value = pcall(os.getenv, envVarName)
    if success then
        return value
    else
        return default
    end
end


---------------------------
-- GymEnv
---------------------------
local GymEnv = {}
GymEnv.new = function(log_path)
    local this = {}
    this.log_path = log_path or "gymenv.log"
    this.processor = nil
    this.mode = ""
    this.emu_speed = 100
    this.is_reset = false
    this.observation_type = ""
    this.backup_data = {}
    this.wkdir_with_slash = ""
    this.frameskip = 0
    this.prev_send_state = ""

    if this.log_path ~= "" then
        local f = io.open(this.log_path, "w")
        if f ~= nil then
            f:close()
        end
    end

    this.close = function(self)
        self:send("close")
    end

    this.run = function(self, processor)
        local success, result = pcall(self.run_sub, self, processor)
        if not success then
            self:log_info("[Error]" .. result)
            comm.socketServerSend("error")
        end
    end

    this.run_sub = function(self, processor)
        -- bizhawk外から実行した場合は何もしない
        if emu == nil then
            self:log_info("Run it from BizHawk.")
            self:close()
            return
        end

        ---- processor
        if processor == nil then
            self:log_info("processor is not found.")
            self:close()
            return
        end
        self.processor = processor

        ---- open rom
        if self.processor.ROM == nil then
            self:log_info("ROM not found." .. self.processor.ROM)
            self:close()
            return
        end
        client.openrom(self.processor.ROM)
        if gameinfo.getromname() == "Null" then
            self:log_info("ROM could not be opened. " .. self.processor.ROM)
            self:close()
            return
        end
        self.platform = emu.getsystemid()
        client.pause()
        client.SetSoundOn(false)
        client.speedmode(100)
        self.emu_speed = 100

        ---- 1st recv
        local recv = self:recv_wait()
        if recv == nil then
            self:log_info("1st recv fail.")
            self:close()
            return
        end
        self:log_info("1st recv: " .. recv)

        -- ある文字列から必要な部分一気にまとめて取り出す
        local setup_str
        local mode
        local silent
        mode, self.observation_type, self.frameskip, silent,self.wkdir_with_slash, setup_str = string.match(recv, "a|(.-)|(.-)|(.-)|(.-)|(.-)|(.+)")
        if self.wkdir_with_slash == "_" then
            self.wkdir_with_slash = ""
        end
        if setup_str == "_" then
            setup_str = ""
        end
        self.frameskip = tonumber(self.frameskip)
        self:log_info("mode            :" .. mode)
        self:log_info("observation_type:" .. self.observation_type)
        self:log_info("frameskip       :" .. self.frameskip)
        self:log_info("silent          :" .. silent)
        self:log_info("wkdir           :" .. self.wkdir_with_slash)
        self:log_info("setup_str       :" .. setup_str)
        if silent == "0" then
            client.SetSoundOn(true)
        end

        ------ setup processor
        self.processor:setup(self, setup_str)
        self.ACTION_SPACE = self.processor.ACTION_SPACE
        if self.ACTION_SPACE == nil then
            self:log_info("ACTION_SPACE is not defined.")
            self:close()
            return
        end
        self.OBSERVATION_SPACE = self.processor.OBSERVATION_SPACE
        if self.OBSERVATION_SPACE == nil then
            self:log_info("OBSERVATION_SPACE is not defined.")
            self:close()
            return
        end

        self:log_info("Verstion :" .. client.getversion())
        self:log_info("Game     :" .. gameinfo.getromname())
        self:log_info("ROM      :" .. self.processor.ROM)
        local gamehash = gameinfo.getromhash()
        self:log_info("Hash     :" ..
            gamehash .. ((gamehash == self.processor.HASH) and " match" or (", not match " .. self.processor.HASH)))
        self:log_info("Platform :" .. self.platform)
        self:log_info("Processor:" .. self.processor.NAME)
        local s = "" .. #self.ACTION_SPACE .. " "
        for i = 1, #self.ACTION_SPACE do
            s = s .. self.ACTION_SPACE[i] .. ","
        end
        self:log_info("action   :" .. s)
        self:log_info("log      :" .. self.log_path)

        ---- emu setting
        self:log_debug("[reset]")
        self:setMode(mode)
        if self.mode == "FAST_RUN" then
            client.unpause()
        elseif mode == "RECORD" then
            self:log_info("[RECORD] Reset wait. Run with frameadvance.")
        elseif mode == "DEBUG" then
            self:log_info("[DEBUG] Paused. Run with frameadvance.")
        else  -- RUN
            client.unpause()
        end
        self:setResetSpeed()
        self.processor:reset()
        self.is_reset = true

        ---- 1st send
        local s = ""
        -- [0] platform
        s = s .. self.platform .. "|"
        -- [1] action_space
        for i = 1, #self.ACTION_SPACE do
            s = s .. self.ACTION_SPACE[i] .. ","
        end
        if self.observation_type == "VALUE" or self.observation_type == "BOTH" then
            -- [2][3] obs_size, obs_space
            if self.processor["getObservation"] == nil then
                self:log_info("'getObservation' is not defined for processor. observation_type='value' cannot be used.")
                self:close()
                return
            end
            local d = self.processor:getObservation()
            local obs_size = #d
            self:log_info("obs size   : " .. obs_size)

            local obs_s = ""
            for i = 1, #self.OBSERVATION_SPACE do
                obs_s = obs_s .. self.OBSERVATION_SPACE[i] .. ","
            end
            self:log_info("observation: " .. #self.OBSERVATION_SPACE .. " " .. obs_s)
            s = s .. "|" .. obs_size .. "|" .. obs_s
        end
        self:send(s)

        ---- main loop
        while true do
            -- 基本接続チェックはpython側で実施

            -- connection check
            --if not comm.socketServerSuccessful() then
            --    log_info("connection refused.")
            --    break
            --end

            -- 動作不明
            --if not comm.socketServerIsConnected() then
            --    log_info("connection refused2.")
            --    break
            --end

            -- recv
            if self:_waitAction() == false then
                self:log_info("loop end.")
                break
            end
        end
        
        --- close
        self:close()
        print("speed 100, paused.")
        self:log_debug("speed 100, paused")
        self.emu_speed = 100
        client.speedmode(100)
        client.pause()
    end

    this.setMode = function(self, mode)
        if self.mode == mode then
            return
        end
        if self.mode == "DEBUG" then
            self:log_info("mode no change(debug mode)")
            return
        end
        self.mode = mode
        if self.mode == "FAST_RUN" then
            self:log_info("set mode FAST_RUN: speed 800, unpaused.")
        elseif self.mode == "DEBUG" then
            self:log_info("set mode DEBUG: Paused. Run with frameadvance.")
        elseif self.mode == "RECORD" then
            self:log_info("set mode RECORD: speed 800, unpaused.")
        else -- RUN
            self:log_info("set mode RUN: speed 100, unpaused.")
        end
    end

    this.setResetSpeed = function(self)
        if self.mode == "FAST_RUN" then
            if self.emu_speed == 100 then
                self:log_debug("speed 800")
                self.emu_speed = 800
                client.speedmode(800)
            end
        elseif self.mode == "RUN" then
            if self.emu_speed == 800 then
                self:log_debug("speed 100")
                self.emu_speed = 100
                client.speedmode(100)
            end
        elseif self.mode == "RECORD" then
            if self.emu_speed == 100 then
                self:log_debug("speed 800")
                self.emu_speed = 800
                client.speedmode(800)
            end
        elseif self.mode == "DEBUG" then
            if self.emu_speed == 800 then
                self:log_debug("speed 100")
                self.emu_speed = 100
                client.speedmode(100)
            end
        end
    end

    this.setStepSpeed = function(self)
        if self.mode == "FAST_RUN" then
            if self.emu_speed == 100 then
                self:log_debug("speed 800")
                self.emu_speed = 800
                client.speedmode(800)
            end
        elseif self.mode == "RUN" then
            if self.emu_speed == 800 then
                self:log_debug("speed 100")
                self.emu_speed = 100
                client.speedmode(100)
            end
        elseif self.mode == "RECORD" then
            if self.emu_speed == 100 then
                self:log_debug("speed 800")
                self.emu_speed = 800
                client.speedmode(800)
            end
        elseif self.mode == "DEBUG" then
            if self.emu_speed == 800 then
                self:log_debug("speed 100")
                self.emu_speed = 100
                client.speedmode(100)
            end
        end
    end

    -----------------------------------
    -- send recv
    -----------------------------------
    this.recv_wait = function(self)
        self:log_debug("wait recv")
        local d = comm.socketServerResponse()
        if d == "" then
            return nil
        end
        self:log_debug("recv: " .. d)
        return d
    end

    this.send = function(self, d)
        -- empty is not send
        if d == "" then
            return
        end
        d = d .. " "
        self:log_debug("send: " .. d)
        comm.socketServerSend(d)
    end

    this.sendScreenShot = function(self)
        self:log_debug("send ScreenShot")
        comm.socketServerScreenShot()
    end

    this._sendExtendObservtion = function(self, s)
        if self.observation_type == "VALUE" or self.observation_type == "BOTH" then
            s = s .. self:_encodeObservation()
        end
        self.prev_send_state = s
        self:send(s)
    end

    -----------------------------------
    -- action
    -----------------------------------
    this._waitAction = function(self)
        ---- recv
        local data = self:recv_wait()
        if data == nil then
            self:log_debug("recv data is nil")
            return true -- skip
        elseif data == "close" then
            self:log_info("recv close")
            return false
        end

        ---- reset
        -- recv: "r"
        -- send: invalid_actions "|" observation
        if data == "reset" then
            if self.is_reset then
                self:log_debug("[reset] skip")
            else
                self:log_debug("[reset]")
                self:setResetSpeed()
                self.processor:reset()
                self.is_reset = true
            end

            local s = self:_encodeInvalidActions() .. "|"
            self:_sendExtendObservtion(s)
            return true
        end

        ---- step
        if startswith(data, "step") then
            self:log_debug("[step] " .. tostring(data))
            ---- 1. recv: "step act1 act2 act3" スペース区切り
            local act_str = string.sub(data, 6)
            if act_str == nil then
                self:log_info("action nil")
                return false
            end
            local acts = split(act_str, " ")

            for i = 1, #self.ACTION_SPACE do
                if startswith(self.ACTION_SPACE[i], "bool") then
                    acts[i] = (acts[i] == "1" and true or false)
                elseif startswith(self.ACTION_SPACE[i], "int") then
                    acts[i] = tonumber(acts[i])
                elseif startswith(self.ACTION_SPACE[i], "float") then
                    acts[i] = tonumber(acts[i])
                end
            end

            ---- 2. step
            local prev_frame = emu.framecount()
            self:setStepSpeed()
            local reward = 0
            local r, terminated, truncated, done
            for i=1, self.frameskip+1 do
                r, terminated, truncated = self.processor:step(acts)
                reward = reward + r
                done = terminated or truncated
                if done then
                    break
                end
            end
            self.is_reset = false
            self:log_debug("[step] reward: " .. tostring(reward) .. ", terminated: " .. tostring(terminated) .. ", truncated: " .. tostring(truncated))
            -- step内でframeが進んでいない場合進める
            if not done then
                local target_frame = prev_frame+self.frameskip
                while emu.framecount() < target_frame do
                    emu.frameadvance()
                    self:log_debug("[step] frameadvance " .. target_frame .. ">" .. emu.framecount())
                end
            end

            ---- 3. send: invalid_actions "|" reward "|" terminated "|" truncated "|" observation
            -- reward     : float
            -- terminated : "0" or "1"
            -- truncated  : "0" or "1"
            local s = self:_encodeInvalidActions()
            s = s .. "|" .. reward
            s = s .. "|" .. (terminated and "1" or "0")
            s = s .. "|" .. (truncated and "1" or "0")
            s = s .. "|"
            self:_sendExtendObservtion(s)

            return true
        end

        ---- functions
        if data == "frameadvance_loop" then
            self:log_info("[frameadvance_loop] Paused. Run with frameadvance.")
            client.pause()
            while true do
                emu.frameadvance()
            end
            return true
        elseif data == "frameadvance" then
            self:log_debug("[frameadvance]")
            client.pause()
            emu.frameadvance()
            return true
        elseif data == "screenshot" then
            self:log_debug("[image] send screenshot")
            self:sendScreenShot()
            return true
        elseif startswith(data, "mode") then
            local mode = string.match(data, "mode (.+)")
            self:log_debug("[mode] set " .. mode)
            self:setMode(mode)
            return true
        elseif startswith(data, "save") then
            self:log_debug("[save] " .. data)
            local name = string.match(data, "save (.+)")
            if self.processor.backup ~= nil then
                self.backup_data[name] = self.processor:backup()
            end
            savestate.save(self.wkdir_with_slash .. name)
            return true
        elseif startswith(data, "load") then
            self:log_debug("[load] " .. data)
            local name = string.match(data, "load (.+)")
            savestate.load(self.wkdir_with_slash .. name)
            if self.processor.restore ~= nil then
                self.processor:restore(self.backup_data[name])
            end
            return true
        elseif data == "resend" then
            self:log_debug("[resend]")
            self:send(self.prev_send_state)
            return true
        end

        ---- eval function
        if startswith(data, "function") then
            self:log_info("[function] " .. data)
            local func_str = string.match(data, "f (.+)")
            if func_str == nil then
                self:log_info("func_str nil")
                return false
            end
            local r = eval(func_str)
            self:send("" .. r)
            return true
        end

        return true
    end


    this._encodeObservation = function(self)
        -- "s1 s2 s3 s4" スペース区切り
        local d = self.processor:getObservation()
        local s = ""
        for i = 1, #d do
            if i == 1 then
                s = s .. d[i]
            else
                s = s .. " " .. d[i]
            end
        end
        return s
    end

    this._encodeInvalidActions = function(self)
        -- アクションセット毎の配列（なので2次元配列）
        -- 区切りは"_"と","、最後に_が入る
        -- float: 未定義
        -- ex. ["bool", "int", "float"]
        -- inv_acts = [[false, 0, not support], [true, 1, not support], ...]
        -- str_acts = "0,0,_1,1,_"
        if self.processor.getInvalidActions == nil then
            return ""
        end
        local s = ""
        local inv_act = self.processor:getInvalidActions()
        for i = 1, #inv_act do
            for j = 1, #self.ACTION_SPACE do
                if startswith(self.ACTION_SPACE[j], "bool") then
                    s = s .. (inv_act[i][j] and "1" or "0") .. ","
                elseif startswith(self.ACTION_SPACE[j], "int") then
                    s = s .. inv_act[i][j] .. ","
                elseif startswith(self.ACTION_SPACE[j], "float") then
                    s = s .. "," -- not support
                end
            end
            s = s .. "_"
        end
        return s
    end

    -----------------------------------
    -- utility
    -----------------------------------
    this.getKeys = function(self)
        local jkeys = joypad.get()
        for k, val in pairs(jkeys) do jkeys[k] = false end
        return jkeys
    end

    this.setKey = function(self, key)
        local jkeys = joypad.get()
        for k, val in pairs(jkeys) do jkeys[k] = false end
        if key ~= "" then
            jkeys[key] = true
        end
        joypad.set(jkeys)
    end

    this.setKeys = function(self, keys)
        local jkeys = joypad.get()
        for k, val in pairs(jkeys) do jkeys[k] = false end
        for i = 1, #keys do
            if keys[i] ~= "" then
                jkeys[keys[i]] = true
            end
        end
        joypad.set(jkeys)
    end

    ----------------------------------------
    -- log
    ----------------------------------------
    this.log = function(self, str, is_print)
        if is_print then
            print(str)
        end
        if self.log_path == "" then
            return
        end
        local s = ""
        s = s .. os.date("%Y/%m/%d %H:%M:%S")
        s = s .. ": " .. str

        -- write
        local f = io.open(self.log_path, "a")
        if f then
            f:write(s .. "\n")
            f:close()
        else
            print("[Error] Failed to open log file: " .. self.log_path)
        end
    end
    this.log_info = function(self, str)
        self:log(str, true)
    end
    this.log_debug = function(self, str)
        if self.mode == "FAST_RUN" then
            return
        end
        if self.mode == "DEBUG" then
            self:log(str, true)
        else
            self:log(str, false)
        end
    end
    this.log_info(this, "start")

    return this
end

local luaRunCount = 0
local function run(processor, log_path)
    -- 直接実行した場合や2回目以降は直接envを実行する
    luaRunCount = luaRunCount + 1
    if getenv_safe("GYMBIZHAWK") ~= "1" then
        luaRunCount = 999
    end

    print("luaRunCount: " .. luaRunCount)
    local env = GymEnv.new(log_path)
    if luaRunCount == 1 then
        env:run(processor)
    else
        env:setMode("DEBUG")
        processor:setup(env, "")
        print("reset start")
        processor:reset()
        print("reset end")
        emu.frameadvance()
        while true do
            processor:step(nil)
        end
    end

    return env
end


return {
    GymEnv = GymEnv,
    run = run,
    eval = eval,
    split = split,
    startswith = startswith,
    getenv_safe = getenv_safe,
}
