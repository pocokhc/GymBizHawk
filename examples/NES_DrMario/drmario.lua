package.path = package.path .. ';../../gymbizhawk/bizhawk.lua'
local bizhawk = require('bizhawk')


local PriorityQueue = {}
PriorityQueue.new = function()
    local this = {}
    this.heap = {}

    this.push = function(self, value, priority)
        table.insert(self.heap, { value = value, priority = priority })
        self:_upper()
    end

    this.pop = function(self)
        if #self.heap == 0 then
            return nil
        end
        if #self.heap == 1 then
            return table.remove(self.heap, 1).value
        end

        local top = self.heap[1]
        self.heap[1] = table.remove(self.heap, #self.heap)
        self:_down()
        return top.value
    end

    this.top = function(self)
        if #self.heap > 0 then
            return self.heap[1].value
        end
        return nil
    end

    this.isEmpty = function(self)
        return #self.heap == 0
    end

    this._upper = function(self)
        local idx = #self.heap
        while idx > 1 do
            local parentIdx = math.floor(idx / 2)
            if self.heap[idx].priority < self.heap[parentIdx].priority then
                -- swap
                self.heap[idx], self.heap[parentIdx] = self.heap[parentIdx], self.heap[idx]
                idx = parentIdx
            else
                break
            end
        end
    end

    this._down = function(self)
        local idx = 1
        while true do
            local leftChild = idx * 2
            local rightChild = idx * 2 + 1
            local smallest = idx

            if leftChild <= #self.heap and self.heap[leftChild].priority < self.heap[smallest].priority then
                smallest = leftChild
            end

            if rightChild <= #self.heap and self.heap[rightChild].priority < self.heap[smallest].priority then
                smallest = rightChild
            end

            if smallest ~= idx then
                self.heap[idx], self.heap[smallest] = self.heap[smallest], self.heap[idx]
                idx = smallest
            else
                break
            end
        end
    end

    return this
end


local EnvProcessor = {}
EnvProcessor.new = function()
    local this = {}
    this.NAME = "DrMario"
    this.ROM = bizhawk.getenv_safe("DRMARIO_PATH")
    this.HASH = "01DE1E04C396298358E86468BA96148066688194"

    -- x: 3bit, 0-7
    -- y: 4bit, 0-15
    -- r: 1bit, 0: right, 1: up
    -- changeColor: 1bit, 0:False, 1:True
    -- 8*16*2*2 = 9bit = 0x1FF
    this.ACTION = {
        "int 1 8",
        "int 1 16",
        "bool",
        "bool",
    }
    this.OBSERVATION = "int"

    this.MAP_W = 8
    this.MAP_H = 16

    this.setup = function(self, env, setup_str)
        self.env = env
        self.level = tonumber(setup_str)
        self.dummyCell = {
            val = 0,
            x = -1,
            y = -1,
            empty = false,
            color = "",
            virus = false,
            pos = "",
        }
        -- print("level: " .. self.level)
    end

    this.reset = function(self)
        savestate.loadslot(9)
        -- select level
        for i = 1, self.level do
            self.env:setKey("P1 Right")
            emu.frameadvance()
            self.env:setKey("")
            emu.frameadvance()
        end
        -- rand
        --local r = math.random(1, 100)
        --for i = 1, r do
        --    emu.frameadvance()
        --end
        -- start
        self.env:setKey("P1 Start")
        emu.frameadvance()
        for i = 1, 100 do
            emu.frameadvance()
        end

        self:skipToStartScene()
        self:readMap()
        self:_searchValidPos()
        if self.env.mode ~= "TRAIN" then
            gui.clearGraphics()
            -- self:drawBox(1, 1, 0xffffff00, "") -- debug
            self:drawValidPos()
            self:drawMap()
            --local p = self.valid_pos[1]                -- debug
            --self:drawBox(p[1], p[2], 0xffffff00, p[3]) -- debug
        end
    end

    this.step = function(self, action)
        local x = action[1]
        local y = action[2]
        local r = action[3] and "up" or "right"
        local changeColor = action[4]
        local reward = 0
        local done = false

        if self.env.mode ~= "TRAIN" then
            -- target pos
            self:drawBox(x, y, 0xffff0000, r)
        end

        -- 1手進める
        if self:_step(4, 1, "right", x, y, r, changeColor) == false then
            return -10, true
        end
        local result = self:skipToStartScene()
        self:readMap()
        self:_searchValidPos()
        if self.env.mode ~= "TRAIN" then
            gui.clearGraphics()
            self:drawValidPos()
            self:drawMap()
        end

        if result == "clear" then
            reward = 1
            done = true
        elseif result == "gameover" then
            reward = -1
            done = true
        end
        return reward, done
    end

    this._astarCreateNode = function(self, parent, x, y, r, c, cmd1, cmd2, description, startX, startY, goalX, goalY)
        local n = {}
        n["x"] = x
        n["y"] = y
        n["r"] = r
        n["c"] = c
        n["prev"] = parent
        n["next"] = nil
        if parent == nil then
            n["cost"] = 0
            n["score"] = 9999
        else
            n["cost"] = parent.cost + 1
            --n["cost"] = math.abs(startX-x) + math.abs(startY-y)
            n["score"] = n.cost + math.abs(goalX - x) + math.abs(goalY - y)
        end
        n["cmd1"] = cmd1
        n["cmd2"] = cmd2
        n["description"] = description
        --print(string.format("(%d,%d,%d,%s) score:%d", n.x, n.y, n.r, (n.c and "1" or "0"), n.score))
        return n
    end

    this._step = function(self, startX, startY, startR, goalX, goalY, goalR, goalC)
        ---- A*
        local start = self:_astarCreateNode(nil, startX, startY, startR, false, {}, {}, "s", startX, startY, goalX, goalY)
        local queue = PriorityQueue.new()
        local tmp_map = {}
        local count = 0
        local goal = nil
        queue:push(start, start.cost)
        while queue:isEmpty() == false do
            count = count + 1
            if count > 9999 then -- for safety
                print(string.format("over: %d", count))
                break
            end
            local node = queue:pop()
            if node == nil then
                break
            end
            local key = string.format("%d_%d_%s_%s", node.x, node.y, node.r, (node.c and "1" or "0"))
            if tmp_map[key] == nil then -- continueなし
                tmp_map[key] = 1

                -- goal
                if node.x == goalX and node.y == goalY and node.r == goalR and node.c == goalC then
                    goal = node
                    break
                end

                -- debug
                --print(string.format("(%d,%d,%s,%s) score:%d", node.x, node.y, node.r, (node.c and "1" or "0"), node.score))

                -- create node
                local x = node.x
                local y = node.y
                local r = node.r
                local c = node.c
                local cmds = {}
                if r == "right" then
                    -- NONE
                    cmds[#cmds + 1] = { x, y, "right", c, {}, "-" }
                    -- A
                    if self:isMapEmpty(x, y - 1) then
                        cmds[#cmds + 1] = { x, y, "up", c, { "P1 A" }, "-a" }
                    end
                    -- right
                    if self:isMapEmpty(x + 2, y) then
                        cmds[#cmds + 1] = { x + 1, y, "right", c, { "P1 Right" }, "-r" }
                    end
                    -- right+A, 挙動が偶奇で変わる
                    --if self:isMapEmpty(x + 2, y) and self:isMapEmpty(x + 1, y - 1) then
                    --    cmds[#cmds + 1] = { x + 1, y, "up", c, { "P1 Right", "P1 A" }, "-ar" }
                    --end
                    -- left
                    if self:isMapEmpty(x - 1, y) then
                        cmds[#cmds + 1] = { x - 1, y, "right", c, { "P1 Left" }, "-l" }
                    end
                    -- left+A
                    if self:isMapEmpty(x - 1, y) and self:isMapEmpty(x - 1, y - 1) then
                        cmds[#cmds + 1] = { x - 1, y, "up", c, { "P1 Left", "P1 A" }, "-al" }
                    end
                    -- left + AB
                    if self:isMapEmpty(x - 1, y) and self:isMapEmpty(x - 2, y) and self:isMapEmpty(x - 1, y - 1) then
                        cmds[#cmds + 1] = { x - 2, y, "right", c, { "P1 Left", "P1 A", "P1 B" }, "-abl" }
                    end
                elseif r == "up" then
                    -- NONE
                    cmds[#cmds + 1] = { x, y, "up", c, {}, "|" }
                    -- A 壁があると挙動が変わる
                    if self:isMapEmpty(x + 1, y) then
                        cmds[#cmds + 1] = { x, y, "right", not c, { "P1 A" }, "|a" }
                    elseif self:isMapEmpty(x - 1, y) then
                        cmds[#cmds + 1] = { x - 1, y, "right", not c, { "P1 A" }, "|a" }
                    end
                    -- right
                    if self:isMapEmpty(x + 1, y) and self:isMapEmpty(x + 1, y - 1) then
                        cmds[#cmds + 1] = { x + 1, y, "up", c, { "P1 Right" }, "|r" }
                    end
                    -- right+A
                    if self:isMapEmpty(x + 1, y) and self:isMapEmpty(x + 2, y) and self:isMapEmpty(x + 1, y - 1) then
                        cmds[#cmds + 1] = { x + 1, y, "right", not c, { "P1 Right", "P1 A" }, "|ar" }
                    end
                    -- left
                    if self:isMapEmpty(x - 1, y) and self:isMapEmpty(x - 1, y - 1) then
                        cmds[#cmds + 1] = { x - 1, y, "up", c, { "P1 Left" }, "|l" }
                    end
                    -- left+A
                    if self:isMapEmpty(x - 1, y) and self:isMapEmpty(x - 2, y) and self:isMapEmpty(x - 1, y - 1) then
                        cmds[#cmds + 1] = { x - 2, y, "right", not c, { "P1 Left", "P1 A" }, "|al" }
                    end
                    -- left + AB
                    if self:isMapEmpty(x - 1, y) and self:isMapEmpty(x - 2, y) and self:isMapEmpty(x - 1, y - 1) and self:isMapEmpty(x - 2, y - 1) then
                        cmds[#cmds + 1] = { x - 2, y, "up", c, { "P1 Left", "P1 A", "P1 B" }, "|abl" }
                    end
                end
                for i = 1, #cmds do
                    local cmd = cmds[i]
                    -- 下を押さない場合
                    local n = self:_astarCreateNode(node, cmd[1], cmd[2], cmd[3], cmd[4], cmd[5], {}, cmd[6] .. "x",
                        startX, startY, goalX, goalY)
                    queue:push(n, n.score)

                    -- 下を押す場合
                    local x2 = cmd[1]
                    local y2 = cmd[2]
                    local r2 = cmd[3]
                    if r2 == "right" then
                        -- 右向き：下移動できる場合は下を押す
                        if self:isMapEmpty(x2, y2 + 1) and self:isMapEmpty(x2 + 1, y2 + 1) then
                            local n2 = self:_astarCreateNode(node, x2, y2 + 1, r2, cmd[4], cmd[5], { "P1 Down" },
                                cmd[6] .. "d", startX, startY, goalX, goalY)
                            queue:push(n2, n2.score)
                        end
                    elseif r2 == "up" then
                        -- 上向き：下移動できる場合は下を押す
                        if self:isMapEmpty(x2, y2 + 1) then
                            local n2 = self:_astarCreateNode(node, x2, y2 + 1, r2, cmd[4], cmd[5], { "P1 Down" },
                                cmd[6] .. "d", startX, startY, goalX, goalY)
                            queue:push(n2, n2.score)
                        end
                    end
                end
            end
        end
        if self.env.mode == "DEBUG" then
            print(string.format("aster count:%d", count))
        end
        if goal == nil then
            print(string.format("goal is nil(%d,%d,%s)", goalX, goalY, goalR))
            return false
        end

        --- draw
        if self.env.mode ~= "TRAIN" then
            self:drawBox(goal.x, goal.y, 0xffff0000, goal.r)
        end

        -- result
        local n = 0
        local node = goal
        for i = 1, 100 do -- for safety
            if node == nil then
                break
            end
            --print(node)
            if node.prev ~= nil then
                node.prev.next = node
            end
            n = n + 1

            if self.env.mode == "DEBUG" then
                print(string.format("%3d:(%d,%d,%s,%s) %s", n, node.x, node.y, node.r, (node.c and "1" or "0"),
                    node.description))
            end
            node = node.prev
        end

        --------------
        -- 実際に進める
        --------------
        node = start.next -- startはコマンドがないため
        for i = 1, 999 do -- for safety
            if node == nil then
                break
            end
            self.env:setKeys(node.cmd1)
            emu.frameadvance()
            self.env:setKeys(node.cmd2)
            emu.frameadvance()
            node = node.next
        end

        -- 最後の下
        emu.frameadvance()
        self.env:setKey("P1 Down")
        emu.frameadvance()
        return true
    end


    this.getObservation = function(self)
        local d = {}
        d[#d + 1] = self.te_left
        d[#d + 1] = self.te_right
        d[#d + 1] = self.te2_left
        d[#d + 1] = self.te2_right
        for y = 1, self.MAP_H do
            for x = 1, self.MAP_W do
                d[#d + 1] = self.map[y][x]["val"]
            end
        end
        return d
    end

    this.getInvalidActions = function(self)
        local d = {}
        for y = 1, self.MAP_H do
            for x = 1, self.MAP_W do
                -- validか
                if self:isValidActions(x, y, 0) == false then
                    d[#d + 1] = { x, y, false, false }
                    d[#d + 1] = { x, y, false, true }
                end
                if self:isValidActions(x, y, 1) == false then
                    d[#d + 1] = { x, y, true, false }
                    d[#d + 1] = { x, y, true, true }
                end
            end
        end
        return d
    end
    this.isValidActions = function(self, x, y, r)
        for i = 1, #self.valid_pos do
            local v = self.valid_pos[i]
            local vr = 0 -- right
            if v[3] == "up" then
                vr = 1
            end
            if v[1] == x and v[2] == y and vr == r then
                return true
            end
        end
        return false
    end

    this.backup = function(self)
        local d = {}
        d[#d + 1] = self.valid_pos
        return d
    end
    this.restore = function(self, d)
        self.valid_pos = d[1]
        self:readMap()
    end

    -------------------------------------------------
    -- functions
    -------------------------------------------------
    this.skipToStartScene = function(self)
        for i = 1, 999 do -- for safety
            -- start pos
            if mainmemory.readbyte(0x0000) == 207 then
                break
            end
            -- ウイルスが0ならゴール
            if mainmemory.readbyte(0x0324) == 0 then -- virus_count == 0
                return "clear"
            end
            -- GameOver
            if mainmemory.readbyte(0x0046) == 7 then
                return "gameover"
            end
            emu.frameadvance()
        end

        -- frame rule check
        savestate.save("_tmp.state")
        local y_pos = mainmemory.readbyte(0x0306)
        self.env:setKey("P1 Down")
        emu.frameadvance()
        emu.frameadvance()
        if y_pos == mainmemory.readbyte(0x0306) and mainmemory.readbyte(0x0000) == 86 then
            savestate.load("_tmp.state")
        else
            savestate.load("_tmp.state")
            emu.frameadvance()
        end

        return ""
    end

    this.readMap = function(self)
        self.map = {}
        for y = 1, self.MAP_H do
            local d = {}
            for x = 1, self.MAP_W do
                local addr = 0x0400 + (x - 1) + (y - 1) * 8
                local cell = mainmemory.readbyte(addr)

                --- cell情報
                local m = {}
                m["val"] = cell
                m["x"] = x
                m["y"] = y
                if cell == 0xFF then
                    m["empty"] = true
                    m["color"] = ""
                    m["virus"] = false
                    m["pos"] = ""
                else
                    m["empty"] = false

                    --- color
                    if cell & 0x3 == 0 then
                        m["color"] = "yellow"
                    elseif cell & 0x3 == 1 then
                        m["color"] = "red"
                    elseif cell & 0x3 == 2 then
                        m["color"] = "blue"
                    end

                    -- 向き
                    local pos = cell & 0x70
                    if pos == 0x40 then
                        m["pos"] = "down"  -- 下とつながっている
                    elseif pos == 0x50 then
                        m["pos"] = "up"    -- 上とつながっている
                    elseif pos == 0x60 then
                        m["pos"] = "right" -- 右とつながっている
                    elseif pos == 0x70 then
                        m["pos"] = "left"  -- 左とつながっている
                    else
                        m["pos"] = ""
                    end

                    -- virus
                    if cell & 0x80 == 0x80 then
                        m["virus"] = true
                        m["pos"] = ""
                    else
                        m["virus"] = false
                    end
                end
                d[#d + 1] = m
            end
            self.map[#self.map + 1] = d
        end

        -- te
        self.te_count = mainmemory.readbyte(0x0310)
        self.te_left = mainmemory.readbyte(0x0081)
        self.te_right = mainmemory.readbyte(0x0082)
        self.te2_left = mainmemory.readbyte(0x009A)
        self.te2_right = mainmemory.readbyte(0x009B)
        self.virus = mainmemory.readbyte(0x0324)
    end

    this.getMap = function(self, x, y)
        if x < 1 or x > self.MAP_W then
            return self.dummyCell
        end
        if y < 1 or y > self.MAP_H then
            return self.dummyCell
        end
        return self.map[y][x]
    end

    this.isMapEmpty = function(self, x, y)
        if x < 1 or x > self.MAP_W then
            return false
        end
        if y < 1 or y > self.MAP_H then
            return false
        end
        return self.map[y][x]["empty"]
    end

    ----------------------------------
    -- 置ける場所を探す
    ----------------------------------
    this._searchValidPos = function(self)
        self.valid_pos = {}
        self.count = 0
        self._visited = {}
        self:_searchValidPosSub(4, 1)

        if self.env.mode == "DEBUG" then
            print(string.format("count=%d len=%d", self.count, #self.valid_pos))
            for i = 1, #self.valid_pos do
                local pos = self.valid_pos[i]
                print(string.format("(%d, %d, %s)", pos[1], pos[2], pos[3]))
            end
        end
    end
    this._searchValidPosSub = function(self, x, y)
        self.count = self.count + 1
        if self:isMapEmpty(x, y) == false then
            return
        end
        local key = string.format("%d_%d", x, y)
        if self._visited[key] ~= nil then
            return
        end
        self._visited[key] = 1

        -- 1つ下が置ける場合
        if self:isMapEmpty(x, y + 1) == false then
            -- 縦がおけるか
            if self:isMapEmpty(x, y - 1) then
                self.valid_pos[#self.valid_pos + 1] = { x, y, "up" }
            end

            -- 右がおけるか
            if self:isMapEmpty(x + 1, y) then
                self.valid_pos[#self.valid_pos + 1] = { x, y, "right" }
            end
        else
            -- 下が空白でも右下にある場合は横に置く
            if self:isMapEmpty(x + 1, y + 1) == false and self:isMapEmpty(x + 1, y) then
                self.valid_pos[#self.valid_pos + 1] = { x, y, "right" }
            end
        end

        -- 右下がうまってる and 上がふさがってる場合は下に移動できない
        if self:isMapEmpty(x + 1, y + 1) or self:isMapEmpty(x, y - 1) then
            self:_searchValidPosSub(x, y + 1)
        end
        -- 2つ右がうまってる and 上か右上がふさがってる場合は右に移動できない
        if self:isMapEmpty(x + 2, y) then
            self:_searchValidPosSub(x + 1, y)
        elseif self:isMapEmpty(x, y - 1) and self:isMapEmpty(x + 1, y - 1) then
            self:_searchValidPosSub(x + 1, y)
        end

        -- 1つ左が開いてれば移動
        if self:isMapEmpty(x - 1, y) then
            self:_searchValidPosSub(x - 1, y)
        end
    end

    ------------------------------------
    -- map 情報を表示
    ------------------------------------
    this.printMap = function(self)
        for y = 1, #self.map do
            local s = ""
            for x = 1, #self.map[y] do
                s = s .. string.format("%2X", self.map[y][x]["val"])
            end
            print(s)
        end

        -- te
        local s = ""
        s = s .. "step: " .. self.te_count
        s = s .. " next: " .. self.te["left"] .. "," .. self.te["right"]
        s = s .. " virus: " .. self.virus
        print(s)
    end

    ------------------------------------
    -- map 情報を画面に描画する
    ------------------------------------
    this.drawMap = function(self)
        --- continueがないので
        local _func = function(cell)
            if cell["empty"] then
                return
            end

            -- left と up は別で描画するのでskip
            if cell.pos == "left" then
                return
            end
            if cell.pos == "up" then
                return
            end

            --- 色 argb?
            local color = 0xffff0000
            if cell.color == "yellow" then
                color = 0xffffff00
            elseif cell.color == "red" then
                color = 0xffff0000
            elseif cell.color == "blue" then
                color = 0xff0000ff
            end

            self:drawBox(cell.x, cell.y, color, cell.pos)
        end
        for y = 1, #self.map do
            for x = 1, #self.map[y] do
                _func(self.map[y][x])
            end
        end
    end

    ------------------------------------
    -- draw box
    ------------------------------------
    this.drawBox = function(self, x, y, color, connect)
        local base_x = 95
        local base_y = 72
        local w = 8
        local h = 8

        local pos_x = base_x + (x - 1) * w
        local pos_y = base_y + (y - 1) * h

        -- 2マス
        if connect == "right" then
            w = w * 2
        elseif connect == "down" then
            h = h * 2
        elseif connect == "left" then
            pos_x = pos_x - w
            w = w * 2
        elseif connect == "up" then
            pos_y = pos_y - h
            h = h * 2
        end

        gui.drawBox(pos_x, pos_y, pos_x + w, pos_y + h, color, nil)
    end

    ------------------------------------
    -- drawValidPos
    ------------------------------------
    this.drawValidPos = function(self)
        for i = 1, #self.valid_pos do
            local x = self.valid_pos[i][1]
            local y = self.valid_pos[i][2]
            local connect = self.valid_pos[i][3]
            local color = 0x40ff0000 -- argb

            self:drawBox(x, y, color, connect)
        end
    end

    return this
end


---- main
local env = bizhawk.GymEnv.new("_drmario.log")
env:run(EnvProcessor.new())

---- for test
return {
    EnvProcessor = EnvProcessor,
    PriorityQueue = PriorityQueue
}
