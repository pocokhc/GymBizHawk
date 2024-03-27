package.path = package.path .. ";gymbizhawk/bizhawk.lua"
local drmario = require('examples.NES_DrMario.drmario')

local function test_PriorityQueue()
    local pq = drmario.PriorityQueue:new()

    -- プッシュとポップの基本的なテスト
    pq:push("Task 1", 3)
    pq:push("Task 2", 1)
    pq:push("Task 3", 2)
    assert(pq:pop() == "Task 2", "Test failed: Basic push and pop")
    assert(pq:pop() == "Task 3", "Test failed: Basic push and pop")
    assert(pq:pop() == "Task 1", "Test failed: Basic push and pop")

    -- 空のPriorityQueueからのポップのテスト
    assert(pq:pop() == nil, "Test failed: Pop from empty PriorityQueue")

    -- 途中で優先度を変更してみるテスト
    pq:push("Task 4", 5)
    pq:push("Task 5", 4)
    pq:push("Task 6", 6)
    pq:push("Task 7", 7)
    pq.heap[2].priority = 3  -- Task 5の優先度を変更
    assert(pq:pop() == "Task 5", "Test failed: Changing priority")

    print("All tests passed successfully!")
        
end
test_PriorityQueue()
