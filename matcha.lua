-- Muscle Legends for Matcha. Based on AkiraDev's Muscle Legends Hub v1.0.3.
-- UI: your REM v6.1 library. Right Shift shows/hides; End unloads.
-- Emergency stop: _G.MuscleLegendsMatcha.Stop()
-- Saved hub settings restore on reload. Hybrid Mode is required for game remotes.
-- No Instance construction, GC writes, or unsupported Humanoid writes in this port.
-- Machine training, rebirths and Ultimate purchases were verified in the live game.

local previous = _G.MuscleLegendsMatcha
if previous and type(previous.Stop) == "function" then previous.Stop() end
if game.PlaceId ~= 3623096087 then
    print("[ML Matcha] Join Muscle Legends (place 3623096087), then run this script.")
    return
end
if not Drawing or type(Drawing.new) ~= "function" then
    error("Matcha Drawing API is required")
end

local Players = game:GetService("Players")
local Input = game:GetService("UserInputService")
local player = Players.LocalPlayer
if not player then error("LocalPlayer is not ready; run again after loading") end

local app = { running = true }
_G.MuscleLegendsMatcha = app
local options = {
    train = true, exercise = 1, rate = 1, fastPunch = false,
    rebirth = true, ultimates = true, equipBest = true, small = true, punch = false, combat = 1,
    target = 0, camp = false, noclip = false, chests = false,
    location = 1,
}
local exercises = { "Direct reps", "Weight", "Pushups", "Handstands", "Situps", "Cycle exercises", "Best strength source" }
local BEST_STRENGTH = 7
local exerciseNames = { "Weight", "Pushups", "Handstands", "Situps" }
local cooldownNames = { Weight = "repTime", Pushups = "pushupTime", Handstands = "handstandTime", Situps = "situpTime" }
local rates = { 5, 10, 20 }
local combatModes = { "Off", "All except whitelist", "Selected player" }
local locations = {
    { "Starter Island", 226.25, 13.15, 219.37 },
    { "Tiny Island", -31.86, 11.06, 2087.89 },
    { "Beach", -365.80, 49.51, -501.62 },
    { "Jungle Gym", -8137, 33, 2820 },
    { "Jungle Bench", -8629.88, 69.88, 1855.03 },
    { "Jungle Bar Lift", -8678.06, 19.50, 2089.26 },
    { "Jungle Squat", -8374.26, 39.59, 2932.45 },
    { "Frost Gym", -2933.48, 34.64, -579.95 },
    { "Mythical Gym", 2659.51, 26.61, 934.69 },
    { "Eternal Gym", -7176.19, 50.39, -1106.31 },
    { "Legend Gym", 4446.92, 1009.47, -3983.76 },
    { "Muscle King", -8626, 20, -5730 },
    { "Brawl Arena 1", 985.91, 168.80, -7037.81 },
    { "Brawl Arena 2", 4466.75, 339.97, -8425.75 },
    { "Brawl Arena 3", -1901.88, 256.90, -5899.65 },
}
local partClasses = { Part = true, MeshPart = true, UnionOperation = true, TrussPart = true,
    WedgePart = true, CornerWedgePart = true, Seat = true, VehicleSeat = true, SpawnLocation = true }
local changedValues, collisions, whitelist, deadlines = {}, {}, {}, {}
local actors, targets, characterParts, chestParts, visits = {}, {}, {}, {}, {}
local pendingChest, campAddress, cycle = nil, nil, 0
local inputConnection
local dirty = true
local UI, destroyUI, syncControls
local message = "Ready. Saved settings restored; Hybrid Mode required."
local started = tick()
local sessionBaseline, sessionText = {}, "Waiting for game stats"
local counters = { requests = 0, moves = 0 }
local rebirthState = { status = "Off", nextAttempt = 0, failures = 0, inFlight = false }
local ultimateState = { status = "Off", nextAttempt = 0, inFlight = false }
local petState = { force = true, nextCheck = 0 }
local ULTIMATE_RESERVE = 100
local ultimateAttributes = {
    ["+1 Daily Spin"] = "UltimateDailySpin", ["+1 Pet Slot"] = "UltimatePetSlot",
    ["+10 Item Capacity"] = "UltimateItemCapacity", ["+5% Rep Speed"] = "UltimateRepSpeed",
    ["Demon Damage"] = "UltimateDemonDamage", ["Galaxy Gains"] = "UltimateGalaxyGains",
    ["Golden Rebirth"] = "UltimateGoldenRebirth", ["Infernal Health"] = "UltimateInfernalHealth",
    ["Jungle Swift"] = "UltimateJungleSwift", ["Muscle Mind"] = "UltimateMuscleMind",
    ["x2 Chest Rewards"] = "UltimateChestRewards", ["x2 Quest Rewards"] = "UltimateQuestRewards",
}
local currentRoot, currentHumanoid, currentCharacter, rightHand, leftHand
local releaseTraining
local training = { sources = {}, denied = {}, scanAt = 0, selectAt = 0, pauseUntil = 0,
    releaseAt = 0, busy = false, status = "Off" }

local SETTINGS_FILE = "muscle-legends-matcha-settings.json"
local function loadSettings()
    if type(isfile) ~= "function" or not isfile(SETTINGS_FILE) then return end
    local ok, data = pcall(function()
        return game:GetService("HttpService"):JSONDecode(readfile(SETTINGS_FILE))
    end)
    if not ok or type(data) ~= "table" or data.version ~= 1 or type(data.options) ~= "table" then return end
    local limits = { exercise = #exercises, rate = #rates, combat = #combatModes, location = #locations }
    for key, original in pairs(options) do
        local value = data.options[key]
        if type(original) == "boolean" and type(value) == "boolean" then options[key] = value
        elseif type(value) == "number" and value == value and value < math.huge and value % 1 == 0 then
            if limits[key] and value >= 1 and value <= limits[key] then options[key] = value
            elseif key == "target" and value >= 0 then options[key] = value end
        end
    end
    if options.punch or options.combat > 1 then options.train = false end
    if options.train and options.exercise == BEST_STRENGTH then options.chests, options.camp = false, false end
    if options.chests then options.camp = false end
end
local function saveSettings()
    if type(writefile) ~= "function" then return end
    local ok, err = pcall(function()
        local data = game:GetService("HttpService"):JSONEncode({ version = 1, options = options })
        writefile(SETTINGS_FILE, data)
    end)
    if not ok then print("[ML Matcha] Settings could not be saved: " .. tostring(err)) end
end
loadSettings()

local function say(text)
    message = tostring(text)
    dirty = true
    print("[ML Matcha] " .. message)
    if UI and UI.Alive then
        UI:Notify({ Title = "Muscle Legends", Content = message, Duration = 4 })
    end
end

local function getTool(name)
    local char, bag = player.Character, player:FindFirstChild("Backpack")
    local short = string.gsub(name, "s$", "")
    return (char and (char:FindFirstChild(name) or char:FindFirstChild(short)))
        or (bag and (bag:FindFirstChild(name) or bag:FindFirstChild(short)))
end

local function equip(name)
    local tool = getTool(name)
    local char = player.Character
    if not tool or not char then error(name .. " tool is not available") end
    local parent = tool.Parent
    if not parent or parent.Address ~= char.Address then tool.Parent = char end
    return tool
end

local function changeValue(toolName, fieldName, value)
    local tool = getTool(toolName)
    local field = tool and tool:FindFirstChild(fieldName)
    if not field then return end
    local address = field.Address
    if not changedValues[address] then
        changedValues[address] = { tool = toolName, field = fieldName, value = field.Value }
    end
    if field.Value ~= value then field.Value = value end
end

local function restoreValues(kind)
    for address, record in pairs(changedValues) do
        if (kind ~= "punch" or record.tool == "Punch")
            and (kind ~= "training" or record.tool ~= "Punch") then
            local tool = getTool(record.tool)
            local field = tool and tool:FindFirstChild(record.field)
            if field and field.Address == address then
                pcall(function() field.Value = record.value end)
            end
            changedValues[address] = nil
        end
    end
end

local function restoreCollisions()
    local char = player.Character
    if char then
        for _, part in ipairs(char:GetDescendants()) do
            local original = collisions[part.Address]
            if original ~= nil and partClasses[part.ClassName] then
                pcall(function() part.CanCollide = original end)
            end
        end
    end
    collisions = {}
end

local function remote(name, ...)
    local folder = game:GetService("ReplicatedStorage"):FindFirstChild("rEvents")
    local object = folder and folder:FindFirstChild(name)
    if not object then error("Missing remote: " .. name) end
    local result
    if object.ClassName == "RemoteFunction" then
        result = object:InvokeServer(...)
    elseif object.ClassName == "RemoteEvent" then
        object:FireServer(...)
    else
        error(name .. " is not a remote")
    end
    if result == false then error(name .. " rejected the request") end
    counters.requests = counters.requests + 1
end

local function muscle(...)
    local object = player:FindFirstChild("muscleEvent")
    if not object or object.ClassName ~= "RemoteEvent" then error("muscleEvent is unavailable") end
    object:FireServer(...)
    counters.requests = counters.requests + 1
end

local function living()
    return currentRoot and currentHumanoid and currentHumanoid.Health > 0
end

local function rebirthStatus(text, required)
    if rebirthState.status ~= text or rebirthState.required ~= required then dirty = true end
    rebirthState.status, rebirthState.required = text, required
end

local function rebirthRequirement(count)
    -- Verified in shared.config.GameConfig and GlobalFunctions, 22 Oct 2026.
    local onboarding = player:GetAttribute("OnboardingRebirthStrength")
    if count == 0 and type(onboarding) == "number" then
        if onboarding ~= onboarding or onboarding < 0 or onboarding == math.huge then return nil end
        return onboarding
    end
    local required = 10000 + count * 5000
    local equipped = player:FindFirstChild("equippedPets")
    if equipped then
        local sally = 0
        for _, slot in ipairs(equipped:GetChildren()) do
            if slot.ClassName == "ObjectValue" then
                local pet = slot.Value
                local reference = slot:FindFirstChild("petReference")
                if pet and reference and reference.Value and pet.Name == "Speedy Sally" then sally = sally + 1 end
            end
        end
        local golden = player:GetAttribute("UltimateGoldenRebirth")
        golden = type(golden) == "number" and golden or 0
        if golden ~= golden or golden == math.huge then return nil end
        required = required * math.max(0.1, 1 - (math.min(sally, 9) + math.max(golden, 0)) * 0.1)
    end
    return required
end

local function requestRebirth(manual)
    if ultimateState.inFlight or ultimateState.pending or ultimateState.hold then
        rebirthStatus("Waiting for Ultimate purchase confirmation") return false
    end
    if rebirthState.inFlight then return false end
    if not living() then rebirthStatus("Waiting for a living character") return false end
    local leader = player:FindFirstChild("leaderstats")
    local countValue = leader and leader:FindFirstChild("Rebirths")
    local strengthValue = leader and leader:FindFirstChild("Strength")
    local count, strength = countValue and countValue.Value, strengthValue and strengthValue.Value
    if type(count) ~= "number" or count ~= count or count < 0 or count == math.huge or count % 1 ~= 0
        or type(strength) ~= "number" or strength ~= strength or strength < 0 or strength == math.huge then
        rebirthStatus("Waiting for replicated rebirth and strength data") return false
    end
    local required = rebirthRequirement(count)
    if not required or required ~= required or required == math.huge then
        rebirthStatus("Cannot determine a valid rebirth requirement") return false
    end
    local now = tick()
    if rebirthState.waitingCount ~= nil then
        if count > rebirthState.waitingCount then
            rebirthState.waitingCount, rebirthState.failures = nil, 0
        elseif now - rebirthState.sentAt < 5 then
            rebirthStatus("Waiting for the server's rebirth count update", required) return false
        else
            rebirthState.waitingCount = nil
            rebirthState.failures = math.min(rebirthState.failures + 1, 4)
            rebirthState.nextAttempt = now + math.min(15, 2 ^ rebirthState.failures)
            rebirthStatus("No confirmation yet; backing off before another request", required) return false
        end
    end
    local char = player.Character
    if not char or char:GetAttribute("IsRebirthing") == true then
        rebirthStatus("Waiting for the current rebirth to finish", required) return false
    end
    if char:GetAttribute("LastMapCFrame") ~= nil then
        rebirthStatus("Waiting for the map transition to finish", required) return false
    end
    if now < rebirthState.nextAttempt then return false end
    if strength < required then
        local text = string.format("Need %.0f Strength; have %.0f", required, strength)
        rebirthStatus(text, required)
        if manual then say(text) end
        return false
    end
    training.pauseUntil = now + 1
    if releaseTraining and not releaseTraining() then
        rebirthStatus("Leaving training machine before rebirth", required) return false
    end
    -- Lock before InvokeServer yields: UI and automation share this request path.
    rebirthState.inFlight, rebirthState.waitingCount, rebirthState.sentAt = true, count, now
    rebirthState.nextAttempt = now + 0.25
    local ok, accepted, detail = pcall(function()
        local folder = game:GetService("ReplicatedStorage"):FindFirstChild("rEvents")
        local object = folder and folder:FindFirstChild("rebirthRemote")
        if not object or object.ClassName ~= "RemoteFunction" then error("rebirthRemote is not ready") end
        counters.requests = counters.requests + 1
        return object:InvokeServer("rebirthRequest")
    end)
    rebirthState.inFlight = false
    if not app.running then return false end
    if not ok or accepted ~= true then
        rebirthState.waitingCount = nil
        rebirthState.failures = math.min(rebirthState.failures + 1, 4)
        local delay = math.min(15, 2 ^ rebirthState.failures)
        rebirthState.nextAttempt = tick() + delay
        rebirthStatus("Request rejected or failed; retrying after backoff", required)
        if manual then say("Rebirth rejected or failed: " .. tostring(ok and detail or accepted)) end
        return false
    end
    rebirthStatus("Accepted; waiting for replicated confirmation", required)
    if manual then say("Rebirth accepted by the server") end
    return true
end

local function validInteger(value)
    return type(value) == "number" and value == value and value >= 0
        and value < math.huge and value % 1 == 0
end

local function ultimateStatus(text)
    if ultimateState.status ~= text then dirty = true end
    ultimateState.status = text
end

local function ultimateBalance()
    local stats = player:FindFirstChild("leaderstats")
    local value = stats and stats:FindFirstChild("Rebirths")
    return value and value.Value
end

local function ultimateQuote(entry)
    local attribute = ultimateAttributes[entry.Name]
    local level = attribute and player:GetAttribute(attribute)
    local base, maximum = entry:FindFirstChild("rebirthCost"), entry:FindFirstChild("maxUpgrades")
    base, maximum = base and base.Value, maximum and maximum.Value
    if not validInteger(level) or not validInteger(base) or base == 0
        or not validInteger(maximum) or level >= maximum then return nil end
    local cost = base * (level + 1)
    if not validInteger(cost) then return nil end
    return cost, level, attribute
end

local function runUltimates()
    if ultimateState.inFlight or ultimateState.hold then return end
    local now, balance = tick(), ultimateBalance()
    local pending = ultimateState.pending
    if pending then
        local level = player:GetAttribute(pending.attribute)
        if validInteger(level) and level > pending.level and validInteger(balance)
            and balance <= pending.balance - pending.cost then
            ultimateState.pending = nil
            if pending.name == "+1 Pet Slot" and options.equipBest then
                petState.force, petState.nextCheck, deadlines.pets = true, 0, 0
            end
            ultimateStatus("Confirmed " .. pending.name .. "; reserve 100")
            ultimateState.nextAttempt = now + 1
        elseif now - pending.sentAt >= 10 then
            ultimateState.hold = true
            ultimateStatus("Purchase unconfirmed; paused. Verify game state before reloading hub.")
        end
        return
    end
    if now < ultimateState.nextAttempt or rebirthState.inFlight or rebirthState.waitingCount ~= nil then return end
    local char = player.Character
    if not living() or not char or char:GetAttribute("IsRebirthing") == true
        or char:GetAttribute("LastMapCFrame") ~= nil then return end
    if not validInteger(balance) then ultimateStatus("Waiting for valid rebirth balance") return end
    local storage = game:GetService("ReplicatedStorage")
    local shared = storage:FindFirstChild("shared")
    local catalogs = shared and shared:FindFirstChild("catalogs")
    local catalog = catalogs and catalogs:FindFirstChild("gameUltimatesFolder")
    if not catalog then ultimateStatus("Ultimate catalog unavailable") return end
    local best, cheapest
    for _, entry in ipairs(catalog:GetChildren()) do
        local cost = ultimateQuote(entry)
        if cost and (not cheapest or cost < cheapest or (cost == cheapest and entry.Name < best.Name)) then
            best, cheapest = entry, cost
        end
    end
    if not best then ultimateStatus("No valid unmaxed upgrades") return end
    if balance - cheapest < ULTIMATE_RESERVE then
        ultimateStatus(string.format("Reserve 100 | Next: %s (%d) | Have %d", best.Name, cheapest, balance)) return
    end
    local folder = storage:FindFirstChild("rEvents")
    local object = folder and folder:FindFirstChild("ultimatesRemote")
    if not object or object.ClassName ~= "RemoteFunction" then ultimateStatus("Ultimate remote unavailable") return end
    -- Requote immediately before dispatch; never spend a cached balance.
    local cost, level, attribute = ultimateQuote(best)
    balance = ultimateBalance()
    if not cost or cost ~= cheapest or not validInteger(balance) or balance - cost < ULTIMATE_RESERVE then return end
    ultimateState.inFlight = true
    ultimateState.pending = { name = best.Name, attribute = attribute, level = level,
        balance = balance, cost = cost, sentAt = now }
    counters.requests = counters.requests + 1
    local ok, accepted = pcall(function() return object:InvokeServer("upgradeUltimate", best.Name) end)
    ultimateState.inFlight = false
    if not app.running then return end
    if ok and accepted == false then
        ultimateState.pending = nil
        ultimateState.nextAttempt = tick() + 5
        ultimateStatus("Upgrade rejected; retrying after 5s")
    elseif not ok or accepted ~= true then
        ultimateState.hold = true
        ultimateStatus("Ambiguous purchase response; paused. Verify before reloading hub.")
    else
        ultimateStatus("Accepted " .. best.Name .. "; waiting for level and balance")
    end
end

local function petSnapshot()
    local folder = player:FindFirstChild("petsFolder")
    if not folder then return nil end
    local inventory, equippedIds = { tostring(player:GetAttribute("UltimatePetSlot")) }, {}
    for _, rarity in ipairs(folder:GetChildren()) do
        if rarity.ClassName == "Folder" then
            for _, pet in ipairs(rarity:GetChildren()) do
                if pet.ClassName == "StringValue" then inventory[#inventory+1] = "pet:" .. tostring(pet.Address) end
            end
        end
    end
    local equipped = player:FindFirstChild("equippedPets")
    for _, slot in ipairs(equipped and equipped:GetChildren() or {}) do
        if slot.ClassName == "ObjectValue" then
            local reference = slot:FindFirstChild("petReference")
            local pet = reference and reference.Value or slot.Value
            if pet and pet.ClassName == "StringValue" then equippedIds[#equippedIds+1] = tostring(pet.Address) end
        end
    end
    local passes = player:FindFirstChild("ownedGamepasses")
    for _, pass in ipairs(passes and passes:GetChildren() or {}) do inventory[#inventory+1] = "pass:" .. pass.Name end
    table.sort(inventory) table.sort(equippedIds)
    local signature = table.concat(inventory, "|")
    return signature .. "#" .. table.concat(equippedIds, "|"), signature
end

local function equipBestPets()
    if tick() < petState.nextCheck or rebirthState.inFlight or rebirthState.waitingCount ~= nil
        or ultimateState.inFlight or ultimateState.pending then return end
    local char = player.Character
    if not char or char:GetAttribute("IsRebirthing") == true then return end
    local signature, inventory = petSnapshot()
    if not signature then return end
    if petState.awaiting then
        -- Absorb the game's own equipment update; it must not trigger another request.
        if inventory == petState.inventory then petState.signature = signature end
        petState.awaiting = false
    end
    if not petState.force and signature == petState.signature then return end
    remote("equipPetEvent", "equipBest")
    petState.force, petState.signature, petState.awaiting = false, signature, true
    petState.inventory = inventory
    petState.nextCheck = tick() + 3
end

local function move(frame)
    if not living() then error("Character is not ready") end
    if options.exercise == BEST_STRENGTH then options.train = false end
    training.target = nil
    if releaseTraining and not releaseTraining() then
        training.travel = { frame = frame, root = currentRoot.Address }
        return
    end
    currentRoot.CFrame = frame
    counters.moves = counters.moves + 1
end

local function stopTravel()
    options.chests, options.camp = false, false
    pendingChest, campAddress = nil, nil
end

local function collectActors()
    currentCharacter = player.Character
    currentRoot = currentCharacter and currentCharacter:FindFirstChild("HumanoidRootPart")
    currentHumanoid = currentCharacter and currentCharacter:FindFirstChild("Humanoid")
    rightHand = currentCharacter and (currentCharacter:FindFirstChild("RightHand") or currentCharacter:FindFirstChild("Right Arm"))
    leftHand = currentCharacter and (currentCharacter:FindFirstChild("LeftHand") or currentCharacter:FindFirstChild("Left Arm"))
    actors, targets = {}, {}
    for _, other in ipairs(Players:GetPlayers()) do
        if other.UserId ~= player.UserId then
            actors[#actors + 1] = { id = other.UserId, name = other.Name }
            local char = other.Character
            local root = char and char:FindFirstChild("HumanoidRootPart")
            local hum = char and char:FindFirstChild("Humanoid")
            if root and hum then targets[#targets + 1] = { id = other.UserId, root = root, hum = hum } end
        end
    end
    table.sort(actors, function(a, b) return a.name < b.name end)
    local present = options.target == 0
    for _, actor in ipairs(actors) do if actor.id == options.target then present = true end end
    if not present then options.target = 0 end
    dirty = true
end

local function collectCharacterParts()
    characterParts = currentCharacter and currentCharacter:GetDescendants() or {}
end

local chestPaths = {
    { "goldenChest" }, { "enchantedChest" }, { "magmaChest" }, { "mythicalChest" },
    { "legendsChest" }, { "jungleChest" },
    { "IndustrialMap", "Model", "industrialChest" }, { "OverchargedMap", "overchargedChest" },
}
local function collectChests()
    local out = {}
    for _, path in ipairs(chestPaths) do
        local root = workspace
        for _, name in ipairs(path) do root = root and root:FindFirstChild(name) end
        local trigger = root and root:FindFirstChild("circleInner")
        local sign = root and root:FindFirstChild("circleSignPart")
        if trigger and partClasses[trigger.ClassName] and sign then
            for _, label in ipairs(sign:GetDescendants()) do
                if label.Name == "timeLabel" and label.ClassName == "TextLabel" then
                    out[#out+1] = { part = trigger, label = label }
                    break
                end
            end
        end
    end
    chestParts = out
end

local function runChest()
    if not living() then pendingChest = nil return end
    local now = tick()
    if pendingChest then
        if pendingChest.label.Text ~= "Ready To Collect" or now >= pendingChest.untilTime then
            visits[pendingChest.address] = now
            pendingChest = nil
        end
        return
    end
    local clock = game:GetService("ReplicatedStorage"):FindFirstChild("serverTime")
    local cooldown = player:GetAttribute("ChestRequestCooldownUntil")
    if type(cooldown) == "number" and (not clock or type(clock.Value) ~= "number" or clock.Value < cooldown) then return end
    local best, distance = nil, math.huge
    local p = currentRoot.Position
    for _, record in ipairs(chestParts) do
        local part = record.part
        if part.Parent and record.label.Text == "Ready To Collect"
            and now - (visits[part.Address] or -100) >= 15 then
            local q = part.Position
            if q and math.abs(q.X) < 1000000 and math.abs(q.Y) < 1000000 and math.abs(q.Z) < 1000000 then
                local d = (q.X-p.X)^2 + (q.Y-p.Y)^2 + (q.Z-p.Z)^2
                if d < distance then best, distance = record, d end
            end
        end
    end
    if best then
        -- The game's existing proximity handler owns readiness and the claim RPC.
        move(best.part.CFrame * CFrame.new(0, 2, 0))
        pendingChest = { label = best.label, address = best.part.Address, untilTime = now + 3 }
    end
end

local function trainingStatus(text)
    if training.status ~= text then dirty = true end
    training.status = text
end

local function finitePositive(value)
    return type(value) == "number" and value == value and value > 0 and value < math.huge
end

local function mountedSeat()
    local object = player:FindFirstChild("machineInUse")
    local seat = object and object.Value
    if seat and seat.ClassName == "Seat" then return seat end
end

local function machineName(seat)
    local model = seat and seat.Parent
    return model and model.Name or "machine (switching)"
end

local function machineRequest(action, seat)
    training.busy = true
    local ok, accepted, reason = pcall(function()
        local storage = game:GetService("ReplicatedStorage")
        local folder = storage:FindFirstChild("rEvents")
        local object = folder and folder:FindFirstChild("machineInteractRemote")
        if not object or object.ClassName ~= "RemoteFunction" then error("Machine remote unavailable") end
        counters.requests = counters.requests + 1
        if seat then return object:InvokeServer(action, seat) end
        return object:InvokeServer(action)
    end)
    training.busy = false
    return ok and accepted == true, reason
end

releaseTraining = function(requireClear)
    training.target = nil
    if training.busy then return false end
    local owned = training.owned
    if not owned then return true end
    local seat = mountedSeat()
    if owned.waiting and not seat and tick() < owned.expires then return false end
    if not seat or seat.Address ~= owned.address then
        training.owned = nil
        return true
    end
    if tick() >= training.releaseAt then
        training.releaseAt = tick() + 2
        machineRequest("leaveMachine")
        seat = mountedSeat()
        if not seat or seat.Address ~= owned.address then training.owned = nil return true end
    end
    -- Normal benches can retain machineInUse/SeatWeld after an accepted leave.
    -- Relinquish ownership for stop/rebirth/tool use; switching requires a clear seat.
    local char = player.Character
    if not requireClear and char and char:GetAttribute("MachineStandingMount") ~= true
        and char:GetAttribute("MachineScaleFrozen") ~= true then
        training.owned = nil
        return true
    end
    trainingStatus("Waiting for machine release")
    return false
end

local function meetsMachineRequirements(model)
    local requirements = model:FindFirstChild("requirements")
    if not requirements then return true end
    local list = requirements:GetChildren()
    if #list == 0 or model:GetAttribute("IsOvercharged") == true then return true end
    -- GlobalFunctions accepts ANY satisfied requirement, rather than requiring all.
    local stats = player:FindFirstChild("leaderstats")
    for _, requirement in ipairs(list) do
        local amount = requirement.Value
        local value = (stats and stats:FindFirstChild(requirement.Name)) or player:FindFirstChild(requirement.Name)
        local have = value and value.Value
        if validInteger(amount) and type(have) == "number" and have == have and have < math.huge
            and have >= amount then return true end
    end
    return false
end

local function sourceQuote(source)
    local model = source.model
    if not model.Parent or tick() < (training.denied[source.address] or 0) then return nil end
    if source.kind == "machine" then
        if not source.seat.Parent or not meetsMachineRequirements(model) then return nil end
        local owner = model:GetAttribute("InUseUserId")
        if type(owner) == "number" and owner ~= 0 and owner ~= player.UserId then return nil end
    else
        local amount, kind = model:FindFirstChild("requiredAmount"), model:FindFirstChild("requiredType")
        if amount then
            local statName = kind and kind.Value or "Strength"
            local stats = player:FindFirstChild("leaderstats")
            local stat = (stats and stats:FindFirstChild(statName)) or player:FindFirstChild(statName)
            local have = stat and stat.Value
            if not validInteger(amount.Value) or type(have) ~= "number" or have ~= have
                or have == math.huge or have < amount.Value then return nil end
        end
    end
    local gain, duration = model:FindFirstChild("strengthGain"), model:FindFirstChild("repTime")
    gain, duration = gain and gain.Value, duration and duration.Value
    if not finitePositive(gain) or not finitePositive(duration) then return nil end
    local score = gain / duration
    return finitePositive(score) and score or nil
end

local function chooseStrengthSource()
    local now = tick()
    if now >= training.scanAt then
        training.scanAt = now + 10
        training.sources = {}
        local folder = workspace:FindFirstChild("machinesFolder")
        for _, model in ipairs(folder and folder:GetChildren() or {}) do
            local seat = model:FindFirstChild("interactSeat")
            -- Matcha's PrimaryPart binding can return an invalid reference here.
            if seat and seat.ClassName == "Seat" and model:FindFirstChild("strengthGain") then
                training.sources[#training.sources+1] = { kind = "machine", model = model,
                    seat = seat, address = seat.Address, name = model.Name }
            end
        end
        -- Prune cooldowns for objects no longer present in the cache.
        local live = {}
        for _, source in ipairs(training.sources) do live[source.address] = true end
        for address in pairs(training.denied) do if not live[address] then training.denied[address] = nil end end
    end
    local best, score
    local function consider(source)
        local value = sourceQuote(source)
        if value and (not score or value > score or (value == score and source.address < best.address)) then
            best, score = source, value
        end
    end
    for _, source in ipairs(training.sources) do consider(source) end
    for _, name in ipairs(exerciseNames) do
        local tool = getTool(name)
        if tool then consider({ kind = "tool", model = tool, name = name, address = tool.Address }) end
    end
    return best, score
end

local function bestStrengthTraining()
    local now = tick()
    if training.busy or now < training.pauseUntil then return end
    local seat = mountedSeat()
    if seat and not seat.Parent then
        trainingStatus("Waiting for machine switch")
        return
    end
    local owned = training.owned
    if seat and training.observedSeat ~= seat.Address then
        training.observedSeat = seat.Address
        if not owned or not owned.waiting or owned.address ~= seat.Address then
            training.owned, training.target = nil, nil
            training.switchAt, training.selectAt = now + 30, 0
            owned = nil
        end
    elseif not seat then training.observedSeat = nil end
    if owned and owned.root ~= currentRoot.Address then
        training.owned, training.target = nil, nil
        training.selectAt = 0
        owned = nil
    end
    if owned and owned.waiting then
        if seat and seat.Address == owned.address then
            owned.waiting, owned.checkAt = false, now + 8
            local stats = player:FindFirstChild("leaderstats")
            local strength = stats and stats:FindFirstChild("Strength")
            owned.strength = strength and strength.Value
        elseif now >= owned.expires then
            training.denied[owned.address] = now + 30
            releaseTraining()
            training.selectAt = 0
            trainingStatus("Mount unconfirmed; trying another source")
        end
        return
    end
    if owned and owned.checkAt and seat and seat.Address == owned.address and now >= owned.checkAt then
        local stats = player:FindFirstChild("leaderstats")
        local strength = stats and stats:FindFirstChild("Strength")
        local amount = strength and strength.Value
        if type(amount) == "number" and type(owned.strength) == "number" and amount <= owned.strength then
            training.denied[owned.address] = now + 60
            releaseTraining()
            training.selectAt = 0
            trainingStatus("No strength gain; trying another source")
            return
        end
        owned.strength, owned.checkAt = amount, now + 8
    end
    if seat and now < (training.switchAt or 0) then
        muscle("rep", seat)
        trainingStatus("Current machine: " .. machineName(seat) .. " | waiting to switch")
        return
    end
    if now >= training.selectAt then
        training.best, training.score = chooseStrengthSource()
        training.selectAt = now + 2
    end
    local best = training.best
    if not best or not sourceQuote(best) then
        training.selectAt = 0
        if not releaseTraining() then return end
        if mountedSeat() then trainingStatus("Waiting to leave current machine") return end
        trainingStatus("Waiting for a usable strength source")
        return
    end
    if best.kind == "tool" then
        if not releaseTraining() then return end
        seat = mountedSeat()
        if seat then
            training.owned = { address = seat.Address, root = currentRoot.Address }
            releaseTraining() return
        end
        equip(best.name)
        muscle("rep")
        trainingStatus("Tool: " .. best.name)
        return
    end
    if seat and seat.Address == best.address then
        local stats = player:FindFirstChild("leaderstats")
        local strength = stats and stats:FindFirstChild("Strength")
        if not training.owned or not training.owned.checkAt then
            training.owned = { address = seat.Address, root = currentRoot.Address,
                checkAt = now + 8, strength = strength and strength.Value }
        end
        muscle("rep", seat)
        trainingStatus("Machine: " .. best.name .. " | best estimated strength/sec")
        return
    end
    if training.owned or seat then
        if not training.owned then training.owned = { address = seat.Address, root = currentRoot.Address } end
        if not releaseTraining(true) then
            -- Preserve training when a normal bench will not release via RPC.
            local current = mountedSeat()
            if current and current.Parent then
                training.switchAt = now + 30
                muscle("rep", current)
                trainingStatus("Current machine: " .. machineName(current) .. " | switching unavailable")
            end
            return
        end
    end
    local target = training.target
    if not target or target.address ~= best.address then
        local q = best.seat.Position
        if not q or math.abs(q.X) > 1000000 or math.abs(q.Y) > 1000000 or math.abs(q.Z) > 1000000 then
            training.denied[best.address] = now + 60 training.selectAt = 0 return
        end
        currentRoot.CFrame = best.seat.CFrame * CFrame.new(0, 3, 0)
        counters.moves = counters.moves + 1
        training.target = { address = best.address, at = now + 0.35 }
        trainingStatus("Approaching " .. best.name)
        return
    end
    if now < target.at then return end
    training.owned = { address = best.address, root = currentRoot.Address, waiting = true, expires = now + 3 }
    local accepted = machineRequest("useMachine", best.seat)
    training.target = nil
    if not accepted then
        training.denied[best.address] = tick() + 30
        releaseTraining()
        training.selectAt = 0
        trainingStatus("Machine unavailable; trying another source")
    elseif not app.running or not options.train or options.exercise ~= BEST_STRENGTH then
        releaseTraining()
    else
        trainingStatus("Waiting for " .. best.name .. " mount")
    end
end

local function train()
    if not living() or training.busy or rebirthState.inFlight then return end
    if rebirthState.waitingCount ~= nil then
        local count = ultimateBalance()
        if validInteger(count) and count > rebirthState.waitingCount then
            rebirthState.waitingCount, rebirthState.failures = nil, 0
        else return end
    end
    local char = player.Character
    if not char or char:GetAttribute("IsRebirthing") == true or char:GetAttribute("LastMapCFrame") ~= nil then return end
    local index = options.exercise
    if index == BEST_STRENGTH then bestStrengthTraining() return end
    if not releaseTraining() then return end
    if index > 1 then
        local name = exercises[index]
        if index == 6 then
            cycle = cycle % #exerciseNames + 1
            name = exerciseNames[cycle]
        end
        equip(name)
        changeValue(name, cooldownNames[name], 0)
    end
    muscle("rep")
    trainingStatus("Training: " .. exercises[index])
end

local function punch()
    if not living() or not releaseTraining() then return end
    equip("Punch")
    if options.fastPunch then changeValue("Punch", "attackTime", 0.065) end
    muscle("punch", "rightHand")
    muscle("punch", "leftHand")
end

local function touchTargets()
    if not living() or not releaseTraining() then return end
    if type(firetouchinterest) ~= "function" then error("Update Matcha: firetouchinterest is missing") end
    if not rightHand or not leftHand then error("Character hands are unavailable") end
    equip("Punch")
    for _, target in ipairs(targets) do
        if not whitelist[target.id] and target.hum.Health > 0
            and (options.combat == 2 or target.id == options.target) then
            firetouchinterest(rightHand, target.root, 0)
            firetouchinterest(rightHand, target.root, 1)
            firetouchinterest(leftHand, target.root, 0)
            firetouchinterest(leftHand, target.root, 1)
        end
    end
end

local function safeAction(action)
    if not app.running then return end
    local ok, err = pcall(action)
    if not ok then say("Action failed: " .. tostring(err)) end
    if app.running then saveSettings() end
    dirty = true
end

local function toggle(key)
    options[key] = not options[key]
    message = "Ready. Automation settings are shown below."
    if key == "train" and options.train then
        options.punch, options.combat = false, 1
        if options.exercise == BEST_STRENGTH then stopTravel() end
    end
    if key == "punch" and options.punch then options.train = false restoreValues("training") end
    if key == "train" and not options.train then restoreValues("training") end
    if key == "fastPunch" and not options.fastPunch then restoreValues("punch") end
    if key == "noclip" and not options.noclip then restoreCollisions() end
    if key == "equipBest" and options.equipBest then
        petState.force, petState.nextCheck, deadlines.pets = true, 0, 0
    end
    if key == "rebirth" then
        rebirthStatus(options.rebirth and "Checking eligibility" or "Off")
        deadlines.rebirth = 0
    end
    if (key == "camp" or key == "chests") and options[key] and options.exercise == BEST_STRENGTH then options.train = false end
    if key == "camp" then
        options.chests, pendingChest, campAddress = false, nil, nil
    end
    if key == "chests" then
        options.camp, pendingChest, deadlines.scanChests = false, nil, 0
    end
    dirty = true
end

local function targetName()
    for _, actor in ipairs(actors) do if actor.id == options.target then return actor.name end end
    return "None"
end

local pages = {
    { name = "Ultimates", rows = {
        { "Auto Ultimate upgrades (reserve 100)", "ultimates", "toggle" },
    } },
    { name = "Training", rows = {
        { "Auto train", "train", "toggle" },
        { "Exercise", "exercise", exercises },
        { "Requests / second", "rate", rates },
        { "Fast punch cooldown", "fastPunch", "toggle" },
        { "Auto rebirth (when ready)", "rebirth", "toggle" },
        { "Rebirth now", action = function() requestRebirth(true) end },
        { "Keep size 2 (every 2s)", "small", "toggle" },
    } },
    { name = "Combat", rows = {
        { "Auto punch (5 pairs/s)", "punch", "toggle" },
        { "Touch targets", "combat", combatModes },
        { "Selected player", special = "target" },
        { "Whitelist selected", special = "whitelist" },
        { "Join brawl", action = function() remote("brawlEvent", "joinBrawl") say("Brawl join requested") end },
    } },
    { name = "Travel", rows = {
        { "Destination", "location", locations },
        { "Teleport", action = function()
            local location = locations[options.location]
            stopTravel()
            move(CFrame.new(location[2], location[3], location[4]))
            say("Moved to " .. location[1])
        end },
        { "Auto ready chests", "chests", "toggle" },
        { "Rescan chests", action = function()
            if not options.chests then say("Enable auto chests first") return end
            deadlines.scanChests = 0 say("Chest rescan queued")
        end },
        { "Distant-location camp", "camp", "toggle" },
        { "No clip", "noclip", "toggle" },
    } },
    { name = "Utility", rows = {
        { "Auto equip best pets", "equipBest", "toggle" },
        { "Equip best pets", action = function() remote("equipPetEvent", "equipBest") say("Equip best requested") end },
        { "Hide pets", action = function() remote("showPetsEvent", "hidePets") say("Hide pets requested") end },
        { "Show pets", action = function() remote("showPetsEvent", "showPets") say("Show pets requested") end },
        { "Disable trading", action = function() remote("tradingEvent", "disableTrading") say("Disable trading requested") end },
        { "Enable trading", action = function() remote("tradingEvent", "enableTrading") say("Enable trading requested") end },
        { "Size 1 now", action = function() remote("changeSpeedSizeRemote", "changeSize", 1) say("Size 1 requested") end },
        { "Stop all automation", action = function()
            training.travel = nil
            options.ultimates, options.equipBest = false, false
            options.train, options.punch, options.rebirth, options.small = false, false, false, false
            options.combat, options.fastPunch, options.noclip = 1, false, false
            rebirthStatus("Off")
            stopTravel() restoreValues() restoreCollisions() say("All automation stopped")
        end },
        { "Unload hub", action = function() app.Stop() end },
    } },
}

local statusLabel, statsLabel, totalsLabel, rebirthLabel, ultimateLabel, trainingLabel, targetOptionsSignature


local function setupREM()
    -- Pin the reviewed REM revision so later upstream API changes cannot break this port.
    local url = "https://gitlab.com/astra-group5825243/rem-ui/-/raw/767973251d7985442642a47757ce3fba0a5736f1/rem_v6-matcha.lua"
    local cache = "rem-v6-matcha-7679732.lua"
    local source
    if type(isfile) == "function" and isfile(cache) then source = readfile(cache)
    else
        source = game:HttpGet(url)
        if type(writefile) == "function" then pcall(writefile, cache, source) end
    end
    local loader, compileError = loadstring(source)
    if not loader then error("REM failed to compile: " .. tostring(compileError)) end
    loader()
    UI = getfenv().Rem
    assert(UI and UI.Alive, "REM UI failed to load")
    destroyUI = UI.Destroy
    function UI:Destroy()
        if app.running then app.Stop() end
        return destroyUI(self)
    end
    UI:SetTitle("Muscle Legends")
    UI:SetSubtitle("Matcha edition")
    statusLabel = UI.Home:AddLabel({ Title = "Status", Description = message })
    trainingLabel = UI.Home:AddLabel({ Title = "Training source", Description = training.status })
    statsLabel = UI.Home:AddLabel({ Title = "Session gains", Description = sessionText })
    totalsLabel = UI.Home:AddLabel({ Title = "Activity", Description = "No requests sent" })
    rebirthLabel = UI.Home:AddLabel({ Title = "Rebirth readiness", Description = rebirthState.status })
    ultimateLabel = UI.Home:AddLabel({ Title = "Ultimate upgrades", Description = "Cheapest first. Keep 100 rebirths. Off." })
    UI.Home:AddLabel({ Title = "Controls", Description = "Right Shift: menu. End: unload. Hub settings save automatically." })
    UI.Home:AddLabel({ Title = "Compatibility", Description = "Requires Hybrid Mode. Remote rewards need live verification. Distant-location camp is not invulnerability." })
    UI.Home:AddLabel({ Title = "Not ported", Description = "Walk/jump edits, infinite jump, lock position, anti-fling, water platforms, invisibility, anti-AFK and server hopping require unsupported or unverified APIs." })
    for _, definition in ipairs(pages) do
        local tab = UI:AddTab({ Title = definition.name, Category = "Muscle Legends" })
        for _, row in ipairs(definition.rows) do
            local entry = row
            if entry.action then
                entry.control = tab:AddButton({ Title = entry[1], ButtonText = "Run", Callback = function()
                    safeAction(entry.action)
                end })
            elseif entry.special == "target" then
                entry.control = tab:AddDropdown({ Title = entry[1], Options = { "None" }, Default = "None", Callback = function(name)
                    safeAction(function()
                        options.target = 0
                        for _, actor in ipairs(actors) do if actor.name == name then options.target = actor.id end end
                    end)
                end })
            elseif entry.special == "whitelist" then
                entry.control = tab:AddToggle({ Title = entry[1], Default = false, Callback = function(value)
                    safeAction(function()
                        if options.target == 0 then say("Select a player first") return end
                        whitelist[options.target] = value
                    end)
                end })
            elseif entry[3] == "toggle" then
                entry.control = tab:AddToggle({ Title = entry[1], Default = options[entry[2]], Callback = function(value)
                    safeAction(function()
                        if options[entry[2]] ~= value then toggle(entry[2]) end
                    end)
                end })
            else
                local labels = {}
                for i, value in ipairs(entry[3]) do
                    labels[i] = type(value) == "table" and value[1] or tostring(value)
                end
                entry.labels = labels
                entry.control = tab:AddDropdown({ Title = entry[1], Options = labels, Default = labels[options[entry[2]]], Callback = function(value)
                    safeAction(function()
                        for i, label in ipairs(labels) do if label == value then options[entry[2]] = i end end
                        if entry[2] == "exercise" then
                            training.selectAt, training.target = 0, nil
                            restoreValues("training")
                            if options.exercise == BEST_STRENGTH and options.train then stopTravel() end
                        end
                        if entry[2] == "combat" and options.combat > 1 then
                            options.train = false restoreValues("training")
                        end
                    end)
                end })
            end
        end
    end
    syncControls = function()
        if not UI.Alive then return end
        local names = { "None" }
        for _, actor in ipairs(actors) do names[#names+1] = actor.name end
        local signature = table.concat(names, "|")
        for _, definition in ipairs(pages) do
            for _, row in ipairs(definition.rows) do
                local control = row.control
                if row.special == "target" then
                    if signature ~= targetOptionsSignature then control:SetOptions(names, targetName()) end
                    control:SetValue(targetName(), true)
                elseif row.special == "whitelist" then
                    control:SetValue(options.target ~= 0 and whitelist[options.target] or false, true)
                    control:SetDescription("Selected: " .. targetName())
                elseif row[3] == "toggle" then
                    control:SetValue(options[row[2]], true)
                elseif row.labels then
                    control:SetValue(row.labels[options[row[2]]], true)
                end
            end
        end
        targetOptionsSignature = signature
        statusLabel:SetDescription(message)
        statsLabel:SetDescription(sessionText)
        trainingLabel:SetDescription(options.train and training.status or "Off")
        rebirthLabel:SetDescription(rebirthState.status)
        ultimateLabel:SetDescription((options.ultimates and "Cheapest first | " or "Off | ") .. ultimateState.status)
        totalsLabel:SetDescription(string.format("Session %ds | Requests sent %d | Moves %d", math.floor(tick()-started), counters.requests, counters.moves))
    end
end

local function updateStats()
    local leaderstats = player:FindFirstChild("leaderstats")
    local values = {
        { "STR", leaderstats and leaderstats:FindFirstChild("Strength") },
        { "Kills", leaderstats and leaderstats:FindFirstChild("Kills") },
        { "DUR", player:FindFirstChild("Durability") },
        { "AGI", player:FindFirstChild("Agility") },
    }
    local parts = {}
    for _, record in ipairs(values) do
        local value = record[2] and record[2].Value
        if type(value) == "number" then
            if not sessionBaseline[record[1]] then sessionBaseline[record[1]] = value end
            parts[#parts+1] = string.format("%s %+.3g", record[1], value-sessionBaseline[record[1]])
        end
    end
    sessionText = #parts > 0 and table.concat(parts, " | ") or "Game stats are not available yet"
    dirty = true
end

function app.Stop()
    if not app.running then return end
    saveSettings()
    app.running = false
    for key, value in pairs(options) do if type(value) == "boolean" then options[key] = false end end
    options.combat, pendingChest = 1, nil
    if inputConnection then pcall(function() inputConnection:Disconnect() end) end
    training.travel = nil
    local released, complete = pcall(releaseTraining)
    if released and not complete then
        task.spawn(function()
            local expires = tick() + 5
            repeat
                task.wait(0.25)
                local ok, done = pcall(releaseTraining)
                if not ok or done then return end
            until tick() >= expires
        end)
    end
    restoreValues()
    pcall(restoreCollisions)
    if UI and UI.Alive and destroyUI then pcall(destroyUI, UI) end
    print("[ML Matcha] Unloaded. Local cooldown and collision changes restored where still present.")
end

local function job(name, enabled, interval, action, disable)
    if not app.running or not enabled or tick() < (deadlines[name] or 0) then return end
    deadlines[name] = tick() + interval
    local ok, err = pcall(action)
    if not ok then
        if disable then disable() end
        say(name .. " stopped: " .. tostring(err))
    end
end

local ok, setupError = pcall(function()
    setupREM()
    collectActors()
    inputConnection = Input.InputBegan:Connect(function(event)
        if event.KeyCode == 35 then app.Stop() end
    end)
    syncControls()
    saveSettings()
end)
if not ok then app.Stop() error(setupError) end

task.spawn(function()
    while app.running do
        job("actors", true, 0.4, collectActors, function() app.Stop() end)
        job("parts", options.noclip, 1, collectCharacterParts, function() options.noclip = false end)
        job("releaseMachine", not options.train or options.exercise ~= BEST_STRENGTH, 0.25, function()
            if releaseTraining() and training.travel then
                local travel = training.travel training.travel = nil
                if living() and travel.root == currentRoot.Address then move(travel.frame) end
            end
        end)
        job("train", options.train, 1/rates[options.rate], train, function() options.train = false restoreValues("training") end)
        job("fastPunch", options.fastPunch, 0.5, function() changeValue("Punch", "attackTime", 0.065) end,
            function() options.fastPunch = false restoreValues("punch") end)
        job("punch", options.punch, 0.2, punch, function() options.punch = false end)
        job("combat", options.combat > 1, 0.2, touchTargets, function() options.combat = 1 end)
        job("ultimates", options.ultimates or ultimateState.pending ~= nil, 0.25, runUltimates,
            function() ultimateState.hold = true options.ultimates = false end)
        job("pets", options.equipBest, 2, equipBestPets, function() options.equipBest = false end)
        job("rebirth", options.rebirth, 0.25, function() requestRebirth(false) end,
            function() options.rebirth = false end)
        job("size", options.small and living(), 2, function() remote("changeSpeedSizeRemote", "changeSize", 2) end,
            function() options.small = false end)
        job("scanChests", options.chests, 10, collectChests, function() options.chests = false end)
        job("chests", options.chests, 0.2, runChest, function() options.chests = false pendingChest = nil end)
        job("camp", options.camp and living(), 0.5, function()
            if campAddress ~= currentRoot.Address then
                move(CFrame.new(4011, 26043, -2394))
                currentRoot.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
                campAddress = currentRoot.Address
            end
        end, function() options.camp = false end)
        job("noclip", options.noclip, 0.2, function()
            for _, part in ipairs(characterParts) do
                if partClasses[part.ClassName] and part.CanCollide then
                    collisions[part.Address] = true
                    part.CanCollide = false
                end
            end
        end, function() options.noclip = false pcall(restoreCollisions) end)
        job("stats", true, 1, updateStats)
        if dirty and app.running then
            dirty = false
            local drawn, err = pcall(syncControls)
            if not drawn then say("Overlay failed: " .. tostring(err)) app.Stop() end
        end
        task.wait(0.05)
    end
end)
say("Loaded with REM. Saved settings active. Right Shift: menu; End: unload.")
