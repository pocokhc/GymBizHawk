
---------------------------
-- common functions
---------------------------
local function eval(inStr)
    inStr = "_a = " .. inStr 
    assert(loadstring(inStr))()
    return _a
end

local function split(str, ts)
    if ts == nil then return {} end

    local t = {} ; 
    i=1
    for s in string.gmatch(str, "([^"..ts.."]+)") do
        t[i] = s
        i = i + 1
    end

    return t
end

function startswith(str, start)
    return string.sub(str, 1, string.len(start)) == start
end

---------------------------
-- GymEnv
---------------------------
local GymEnv = {}
GymEnv.new = function(log_path)
    local this = {}
    this.log_path = log_path
    this.processor = nil
    this.mode = ""

    this.close = function(self)
        self:send("close")
    end

    this.run = function(self, processor)
        ---- processor
        if processor == nil then
            self:log_info("processor is not found.")
            self:close()
            return
        end
        self.processor = processor

        ---- open rom
        client.openrom(self.processor.ROM)
        if gameinfo.getromname() == "Null" then
            self:log_info("Open the ROM and then execute.")
            self:close()
            return
        end
        self.platform = emu.getsystemid()
        client.pause()

        savestate.loadslot(2)
        

        ---- 1st recv
        local recv = self:recv_wait()
        if recv == nil then
            self:log_info("1st recv fail.")
            self:close()
            return
        end
        self:log_info("1st recv: " .. recv)
        
        -- ある文字列から必要な部分一気にまとめて取り出す
        self.speed, observation_type, py_init_str, a = string.match(recv, "a (.-) (.-) (.-) (.+)")

        ------ init processor
        self.processor:init(self, py_init_str)
        self.ACTION = self.processor.ACTION
        if self.ACTION == nil then
            self:log_info("Action is not defined: " .. self.platform)
            self:close()
            return
        end

        self:log_info("Verstion  :" .. client.getversion())
        self:log_info("Game      :" .. gameinfo.getromname())
        gamehash = gameinfo.getromhash()
        self:log_info("Hash      :" .. gamehash .. ((gamehash == self.processor.HASH) and " same" or (", miss " .. self.processor.HASH)))
        self:log_info("Platform  :" .. self.platform)
        self:log_info("Processor :" .. self.processor.NAME)
        self:log_info("Speed     :" .. self.speed)
        local s = "" .. #self.ACTION .. " "
        for i=1, #self.ACTION do
            s = s .. self.ACTION[i] .. " "
        end
        self:log_info("action    :" .. s)
        self:log_info("log       :" .. self.log_path)

        ---- 1st send
        local s = ""
        for i=1, #self.ACTION do
            s = s .. self.ACTION[i] .. ","
        end
        if observation_type == "VALUE" or observation_type == "BOTH" then
            local obs_len = 0
            if self.processor.OBSERVATION_LENGTH == nil then
                local d = self.processor:getObservation()
                obs_len = #d
            else
                obs_len = self.processor.OBSERVATION_LENGTH
            end
            local obs_low = (self.processor.OBSERVATION_LOW == nil) and 0 or self.processor.OBSERVATION_LOW
            local obs_high = (self.processor.OBSERVATION_HIGH == nil) and 255 or self.processor.OBSERVATION_HIGH
            self:log_info("obs       :" .. obs_len .. " [" .. obs_low .. "," .. obs_high .. "]")
            s = s .. "|"
            s = s .. obs_len
            s = s .. "," .. obs_low
            s = s .. "," .. obs_high
        end
        self:send(s)
        if observation_type == "IMAGE" or observation_type == "BOTH" then
            self:sendImage()
        end
        
        ---- emu setting
        if self.speed == "FAST" then
            self:log_info("speed 800, unpaused.")
            client.speedmode(800)
            client.unpause()
        elseif self.speed == "DEBUG" then
            client.speedmode(100)
            self:log_info("Run with frameadvance.")
        else  -- test
            self:log_info("speed 100, unpaused.")
            client.speedmode(100)
            client.unpause()
        end
        
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
        
        self:close()
        print("speed 100, paused.")
        client.speedmode(100)
        client.pause()
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

    this.sendImage = function(self)
        self:log_debug("send image")
        comm.socketServerScreenShot()
    end


    -----------------------------------
    -- action
    -----------------------------------
    this._waitAction = function(self)

        if self.speed == "DEBUG" then
            emu.frameadvance()
        end

        ---- recv
        local data = self:recv_wait()
        if data == nil then
            self:log_debug("recv data is nil")
            return true  -- skip
        elseif data == "close" then
            self:log_info("recv close")
            return false
        elseif data == "frameadvance" then
            self:log_info("frameadvance")
            client.pause()
            emu.frameadvance()
            return true
        elseif data == "image" then
            self:sendImage()
            return true
        end

        ---- cmd
        local cmd = string.sub(data, 1, 1)

        ---- reset
        if cmd == "r" then
            self.processor:reset()
            self:log_debug("[reset]")
            
            -- valid_actions TODO
            --local d = self.processor:get_valid_actions()
            --local s = ""
            --for i=1, #d do
            --    s = s .. d[i] .. " "
            --end
            --self:send(s)

            if data == "rv" then
                self:send(self:_createObservation())
            elseif data == "ri" then
                self:sendImage()
            elseif data == "rb" then
                self:send(self:_createObservation())
                self:sendImage()
            end
            return true
        end

        ---- step
        if cmd == "s" then
            ---- recv action
            local obs_type = string.sub(data, 2, 2)
            local act_str = string.sub(data, 4)
            if act_str == nil then
                self:log_info("action nil")
                return false
            end
            local acts = split(act_str, " ")

            for i=1, #self.ACTION do
                if self.ACTION[i] == "bool" then
                    acts[i] = (acts[i] == "1" and true or false)
                elseif startswith(self.ACTION[i], "int") then
                    acts[i] = tonumber(acts[i])
                elseif startswith(self.ACTION[i], "float") then
                    acts[i] = tonumber(acts[i])
                end
            end

            ---- step
            local prev_frame = emu.framecount()
            local reward, done = self.processor:step(acts)
            self:log_debug("[step] reward: " .. tostring(reward) .. ", done: " .. tostring(done))
            if prev_frame == emu.framecount() then
                -- step内でframeが進んでいない場合進める
                emu.frameadvance()
                self:log_debug("frameadvance")
            end
            
            ---- send
            local s = "" .. reward .. "|" .. (done and "1" or "0")
            
            --local d = self.processor:get_valid_actions()
            --for i=1, #d do
            --    s = s .. " " .. d[i]
            --end
            
            if obs_type == "v" or data == "b" then
                s = s .. "|" .. self:_createObservation()
            end
            self:send(s)
            if obs_type == "i" or data == "b" then
                self:sendImage()
            end
            
            return true
        end

        ---- function
        if cmd == "f" then
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


    this._createObservation = function(self)
        local d = self.processor:getObservation()
        local s = ""
        for i=1, #d do
            if i == 1 then
                s = s .. d[i]
            else
                s = s .. " " .. d[i]
            end
        end
        return s
    end

    -----------------------------------
    -- utility
    -----------------------------------
    this.get_buttons = function(self)
        local buttons = joypad.get()
        for k, val in pairs(buttons) do buttons[k] = false end
        return buttons
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
        s = s .. " " .. emu.framecount() .. "frame "
        s = s .. ": " .. str
        f = io.open(self.log_path, "a")
        f:write(s .. "\n")
        f:close()
    end
    this.log_info = function(self, str)
        self:log(str, true)
    end
    this.log_debug = function(self, str)
        if self.speed == "DEBUG" then
            self:log(str, true)
        else
            self:log(str, false)
        end
    end
    this.log_info(this, "start")
    
    return this
end

return GymEnv
