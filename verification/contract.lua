-- Model Matcha's restricted properties, unstable wrappers and yielding scheduler.
local now, nextAddress = 0, 100
local threads, requests, touches, logs, httpUrls = {}, {}, {}, {}, {}
local counts = { scans = 0, positionWrites = 0 }
local originalPrint = print
function print(...) logs[#logs+1] = table.concat({...}, " ") end
function warn(...) print(...) end
function tick() return now end
function getfenv() return _G end

task = {}
local function resume(thread)
    local ok, delay = coroutine.resume(thread.co)
    assert(ok, delay)
    thread.wake = now + (delay or 0.03)
end
function task.spawn(fn)
    local thread = { co = coroutine.create(fn), wake = now }
    threads[#threads+1] = thread
    resume(thread)
    return thread
end
function task.wait(delay) return coroutine.yield(delay or 0.03) end
local function advance(duration)
    local finish = now + duration
    while now < finish do
        local soonest = finish
        for _, thread in ipairs(threads) do
            if coroutine.status(thread.co) ~= "dead" then soonest = math.min(soonest, thread.wake) end
        end
        now = math.max(now, soonest)
        for _, thread in ipairs(threads) do
            if coroutine.status(thread.co) ~= "dead" and thread.wake <= now then resume(thread) end
        end
    end
end
local function activeThreads()
    local n = 0
    for _, thread in ipairs(threads) do if coroutine.status(thread.co) ~= "dead" then n=n+1 end end
    return n
end

Vector3 = { new = function(x,y,z) assert(type(x)=="number" and type(y)=="number" and type(z)=="number") return {X=x,Y=y,Z=z} end }
local frameMethods = {}
function frameMethods:PointToWorldSpace(v) return Vector3.new(self.Position.X+v.X,self.Position.Y+v.Y,self.Position.Z+v.Z) end
function frameMethods:PointToObjectSpace(v) return Vector3.new(v.X-self.Position.X,v.Y-self.Position.Y,v.Z-self.Position.Z) end
CFrame = { new = function(...)
    assert(select("#",...)==3,"CFrame.new requires three numbers")
    return setmetatable({Position=Vector3.new(...)}, {
        __index=frameMethods,
        __mul=function(a,b) local p=a:PointToWorldSpace(b.Position) return CFrame.new(p.X,p.Y,p.Z) end,
    })
end }
Drawing = { new = function() error("Port must delegate drawings to REM") end }

local methods = {}
local wrap
local writable = { Parent=true, CFrame=true, AssemblyLinearVelocity=true, Value=true, CanCollide=true }
wrap = function(data)
    if not data then return nil end
    return setmetatable({}, {
        __index=function(_, key)
            if methods[key] then return function(_, ...) return methods[key](data, ...) end end
            if key=="Parent" then return wrap(data.parent) end
            if data.props[key]~=nil then return data.props[key] end
            for _,child in ipairs(data.children) do if child.props.Name==key then return wrap(child) end end
            return nil -- Unsupported Matcha properties silently return nil.
        end,
        __newindex=function(_, key, value)
            assert(writable[key], "Unsupported write: "..key)
            if key=="Parent" then
                -- Resolve the fresh wrapper by stable address.
                local function find(root, address)
                    if root.props.Address==address then return root end
                    for _,child in ipairs(root.children) do local found=find(child,address) if found then return found end end
                end
                local parent=find(_G.ROOT_DATA,value.Address)
                assert(parent,"Parent missing")
                if data.parent then for i,child in ipairs(data.parent.children) do if child==data then table.remove(data.parent.children,i) break end end end
                data.parent=parent parent.children[#parent.children+1]=data
            else
                data.props[key]=value
                if key=="CFrame" then
                    data.props.Position=value.Position
                    counts.positionWrites=counts.positionWrites+1
                end
            end
        end,
    })
end
local function object(name,class,parent,props)
    nextAddress=nextAddress+1
    local data={props={Name=name,ClassName=class,Address=nextAddress},children={},parent=parent}
    for key,value in pairs(props or {}) do data.props[key]=value end
    if parent then parent.children[#parent.children+1]=data end
    return data
end
function methods.FindFirstChild(data,name)
    for _,child in ipairs(data.children) do if child.props.Name==name then return wrap(child) end end
end
function methods.GetChildren(data)
    local list={} for _,child in ipairs(data.children) do list[#list+1]=wrap(child) end return list
end
function methods.GetDescendants(data)
    if data.props.Name=="Workspace" then counts.scans=counts.scans+1 end
    local list={}
    local function visit(node) for _,child in ipairs(node.children) do list[#list+1]=wrap(child) visit(child) end end
    visit(data) return list
end
function methods.FireServer(data,...)
    assert(data.props.ClassName=="RemoteEvent", "FireServer used on a RemoteFunction")
    requests[#requests+1]={name=data.props.Name,args={...},time=now}
    if data.onFire then data.onFire(...) end
end
function methods.InvokeServer(data,...)
    assert(data.props.ClassName=="RemoteFunction", "InvokeServer used on a RemoteEvent")
    requests[#requests+1]={name=data.props.Name,args={...},time=now}
    if data.onInvoke then return data.onInvoke(...) end
    return data.result~=false
end
function methods.GetPlayers(data) return methods.GetChildren(data) end
function methods.GetAttribute(data,name) return data.attrs and data.attrs[name] end
function firetouchinterest(origin,target,state)
    assert(origin.Address and target.Address)
    touches[#touches+1]={origin=origin.Address,target=target.Address,state=state}
end

ROOT_DATA=object("game","DataModel")
local playersData=object("Players","Players",ROOT_DATA)
local storageData=object("ReplicatedStorage","ReplicatedStorage",ROOT_DATA)
local workspaceData=object("Workspace","Workspace",ROOT_DATA)
local remotesData=object("rEvents","Folder",storageData)
local playerData=object("Me","Player",playersData,{UserId=1})
local enemyData=object("Enemy","Player",playersData,{UserId=2})
local bagData=object("Backpack","Folder",playerData)
local function character(name,owner)
    local char=object(name,"Model",workspaceData)
    local root=object("HumanoidRootPart","Part",char,{CFrame=CFrame.new(0,5,0),Position=Vector3.new(0,5,0),CanCollide=true,Size=Vector3.new(2,2,1)})
    object("Humanoid","Humanoid",char,{Health=100})
    object("RightHand","Part",char,{CanCollide=false})
    object("LeftHand","Part",char,{CanCollide=false})
    owner.props.Character=wrap(char)
    return char,root
end
local charData,rootData=character("MeCharacter",playerData)
local _,enemyRoot=character("EnemyCharacter",enemyData)
local muscleData=object("muscleEvent","RemoteEvent",playerData)
local rebirthData=object("rebirthRemote","RemoteFunction",remotesData)
object("checkChestRemote","RemoteEvent",remotesData)
object("changeSpeedSizeRemote","RemoteEvent",remotesData)
object("showPetsEvent","RemoteEvent",remotesData)
object("tradingEvent","RemoteEvent",remotesData)
object("brawlEvent","RemoteEvent",remotesData)
local punchTool=object("Punch","Tool",bagData)
local attackData=object("attackTime","NumberValue",punchTool,{Value=0.35})
local weightData=object("Weight","Tool",bagData)
local workoutData=object("repTime","NumberValue",weightData,{Value=1})
local chestRoot=object("goldenChest","Model",workspaceData)
local chestSign=object("circleSignPart","Part",chestRoot)
local chestLabel=object("timeLabel","TextLabel",chestSign,{Text="Ready To Collect"})
local chestData=object("circleInner","Part",chestRoot,{CFrame=CFrame.new(10,5,0),Position=Vector3.new(10,5,0),Size=Vector3.new(2,2,2)})
local stats=object("leaderstats","Folder",playerData)
local strengthData=object("Strength","NumberValue",stats,{Value=100})
local rebirthCountData=object("Rebirths","NumberValue",stats,{Value=0})
local equippedPetsData=object("equippedPets","Folder",playerData)
object("Kills","NumberValue",stats,{Value=0})
object("Durability","NumberValue",playerData,{Value=50})
object("Agility","NumberValue",playerData,{Value=20})
playersData.props.LocalPlayer=wrap(playerData)
local inputHandles={}
local input={InputBegan={Connect=function(_, callback)
    local handle={callback=callback,active=true}
    function handle:Disconnect() self.active=false end
    inputHandles[#inputHandles+1]=handle return handle
end}}
workspace=wrap(workspaceData)
game={PlaceId=3623096087,GetService=function(_,name)
    if name=="Players" then return wrap(playersData) end
    if name=="ReplicatedStorage" then return wrap(storageData) end
    if name=="UserInputService" then return input end
    if name=="Workspace" then return workspace end
    error("Unsupported service: "..name)
end,HttpGet=function(_,url) httpUrls[#httpUrls+1]=url return REM_SOURCE end}

local files, encoded = {}, {}
local function copy(value)
    if type(value) ~= "table" then return value end
    local out = {} for key,item in pairs(value) do out[key] = copy(item) end return out
end
local function jsonEncode(value)
    local token = "mock-json:" .. tostring(#encoded+1)
    encoded[#encoded+1] = copy(value)
    return token
end
local function jsonDecode(value)
    local index = tonumber(string.match(value or "", "^mock%-json:(%d+)$"))
    assert(index and encoded[index], "Invalid JSON") return copy(encoded[index])
end
function isfile(name) return files[name] ~= nil end
function readfile(name) assert(files[name], "Missing file") return files[name] end
function writefile(name,value) files[name] = value end
local originalGetService = game.GetService
game.GetService = function(self,name)
    if name == "HttpService" then return { JSONEncode=function(_,value) return jsonEncode(value) end,
        JSONDecode=function(_,value) return jsonDecode(value) end } end
    return originalGetService(self,name)
end
local settingsFile = "muscle-legends-matcha-settings.json"
local function resetSettings()
    files[settingsFile] = jsonEncode({ version=1, options={train=false,exercise=1,rate=2,fastPunch=false,
        rebirth=false,ultimates=false,equipBest=false,small=false,punch=false,combat=1,target=0,
        camp=false,noclip=false,chests=false,location=1} })
end
local controls={}
local function makeREM()
    controls={}
    local ui={Alive=true,Tabs={}}
    function ui:SetTitle(title) self.Title=title end
    function ui:SetSubtitle(title) self.Subtitle=title end
    function ui:Notify(options) self.lastNotice=options.Content end
    function ui:Destroy() self.Alive=false end
    function ui:AddTab(options)
        local tab={}
        for _,kind in ipairs({"Toggle","Dropdown","Button","Label"}) do
            tab["Add"..kind]=function(_,options)
                local control={Value=options.Default,Options=options.Options,Callback=options.Callback,kind=kind}
                function control:SetValue(value,silent)
                    if self.kind=="Dropdown" then
                        local found=false for _,option in ipairs(self.Options) do if option==value then found=true end end
                        assert(found,"Invalid REM dropdown value: "..tostring(value))
                    end
                    local changed=self.Value~=value self.Value=value
                    if changed and not silent and self.Callback then task.spawn(function() self.Callback(value) end) end
                end
                function control:SetDescription(value) self.Description=value end
                function control:SetOptions(values,value) self.Options=values self:SetValue(value,true) end
                function control:Click() task.spawn(function() self.Callback() end) end
                controls[options.Title]=control
                return control
            end
        end
        self.Tabs[#self.Tabs+1]=tab return tab
    end
    ui.Home=ui:AddTab({Title="Home"})
    return ui
end
function loadstring(text)
    if text==REM_PATCHED_SOURCE then return function() Rem=makeREM() end end
    return load(text,"@port.lua","t",_G)
end
local function start(keepSettings)
    if _G.MuscleLegendsMatcha then _G.MuscleLegendsMatcha.Stop() end
    if not keepSettings then resetSettings() end
    assert(loadstring(PORT_SOURCE))()
end
local function set(title,value) assert(controls[title],title):SetValue(value) end
local function click(title) assert(controls[title],title):Click() end
local passed=0
local function check(name,fn) fn() passed=passed+1 originalPrint("PASS "..name) end
local function countRequests(name)
    local n=0 for _,request in ipairs(requests) do if request.name==name then n=n+1 end end return n
end

check("wrong-game guard does not load REM or start a worker",function()
    game.PlaceId=123 start() assert(#httpUrls==0 and activeThreads()==0) game.PlaceId=3623096087
end)
check("REM setup starts one scheduler with all automation off",function()
    start() advance(0.5)
    assert(Rem.Alive and Rem.Title=="Muscle Legends")
    assert(string.find(httpUrls[1],"767973251d7985442642a47757ce3fba0a5736f1",1,true))
    assert(activeThreads()==1 and #requests==0 and counts.positionWrites==0)
end)
check("rapid toggles cannot multiply training workers",function()
    for i=1,8 do set("Auto train",true) set("Auto train",false) end
    set("Auto train",true)
    local before=countRequests("muscleEvent") advance(1.01)
    local sent=countRequests("muscleEvent")-before
    assert(sent>=8 and sent<=11,"Unexpected rep rate: "..sent)
    assert(activeThreads()==1)
end)
check("tool training works with fresh wrappers and restores cooldown",function()
    set("Exercise","Weight") advance(0.2)
    assert(weightData.parent==charData and workoutData.props.Value==0)
    set("Auto train",false)
    assert(workoutData.props.Value==1)
end)
check("remote dispatch uses the real class and handles rejection",function()
    strengthData.props.Value=20000
    click("Rebirth now") assert(countRequests("rebirthRemote")==1)
    rebirthCountData.props.Value=1
    advance(0.3)
    rebirthData.result=false click("Rebirth now")
    assert(string.find(Rem.lastNotice,"rejected",1,true))
    rebirthData.result=true
end)
check("combat disables training and restores its local cooldown",function()
    set("Auto train",true) advance(0.2) assert(workoutData.props.Value==0)
    set("Auto punch (5 pairs/s)",true) advance(0.1)
    assert(not controls["Auto train"].Value and workoutData.props.Value==1)
    set("Auto punch (5 pairs/s)",false)
end)
check("selected target and whitelist use stable UserId",function()
    set("Selected player","Enemy") set("Whitelist selected",true)
    set("Touch targets","Selected player") advance(0.5) assert(#touches==0)
    set("Whitelist selected",false) advance(0.3)
    assert(#touches>=4 and touches[1].state==0 and touches[2].state==1)
    assert(punchTool.parent==charData)
    set("Touch targets","Off")
end)
check("noclip restores original collisions",function()
    set("No clip",true) advance(1.2) assert(rootData.props.CanCollide==false)
    set("No clip",false) assert(rootData.props.CanCollide==true)
end)
check("camp moves once per character rather than every tick",function()
    local before=counts.positionWrites
    set("Distant-location camp",true) advance(2)
    assert(counts.positionWrites==before+1)
    charData,rootData=character("Respawn",playerData)
    -- Roblox gives the respawned character fresh tools; the corpse keeps old ones.
    punchTool=object("Punch","Tool",bagData)
    attackData=object("attackTime","NumberValue",punchTool,{Value=0.35})
    advance(1)
    assert(counts.positionWrites==before+2 and rootData.props.Position.Y==26043)
end)
check("chest cache avoids workspace scans on each iteration",function()
    local before=counts.scans
    set("Auto ready chests",true) advance(2)
    assert(not controls["Distant-location camp"].Value)
    assert(counts.scans==before)
    assert(countRequests("checkChestRemote")==0)
    assert(rootData.props.Position.X==10)
end)
check("manual travel cancels collection and camp",function()
    click("Teleport") advance(0.5)
    assert(not controls["Auto ready chests"].Value and not controls["Distant-location camp"].Value)
    assert(math.abs(rootData.props.Position.X-226.25)<0.01)
end)
check("missing remote disables only the failing feature",function()
    local previousClass=muscleData.props.ClassName muscleData.props.ClassName="Folder"
    set("Auto train",true) advance(0.3)
    assert(not controls["Auto train"].Value and _G.MuscleLegendsMatcha.running)
    muscleData.props.ClassName=previousClass
end)
check("rerunning disposes the old menu and worker",function()
    local oldUI=Rem local oldApp=_G.MuscleLegendsMatcha
    start() advance(0.2)
    assert(not oldUI.Alive and not oldApp.running and activeThreads()==1)
end)
check("REM destruction stops work and restores local values",function()
    set("Fast punch cooldown",true) set("Auto punch (5 pairs/s)",true)
    set("No clip",true) advance(1.2)
    assert(attackData.props.Value==0.065 and rootData.props.CanCollide==false)
    local staleCallback=controls["Auto train"].Callback
    Rem:Destroy()
    assert(not _G.MuscleLegendsMatcha.running and attackData.props.Value==0.35 and rootData.props.CanCollide)
    local count=#requests staleCallback(true) advance(1)
    assert(#requests==count and activeThreads()==0)
end)

local function rebirthFixture(count,strength)
    if _G.MuscleLegendsMatcha then _G.MuscleLegendsMatcha.Stop() end
    rebirthCountData.props.Value=count strengthData.props.Value=strength
    playerData.attrs={} charData.attrs={} equippedPetsData.children={}
    rebirthData.result=true rebirthData.onInvoke=nil
    start() advance(0.1)
end
local function addSally()
    local pet=object("Speedy Sally","Folder",ROOT_DATA)
    local slot=object("pet","ObjectValue",equippedPetsData,{Value=wrap(pet)})
    object("petReference","ObjectValue",slot,{Value=wrap(pet)})
end
check("auto rebirth waits for the exact current strength requirement",function()
    rebirthFixture(10,59999)
    local before=countRequests("rebirthRemote")
    set("Auto rebirth (when ready)",true) advance(1)
    assert(countRequests("rebirthRemote")==before)
    strengthData.props.Value=60000 advance(0.3)
    assert(countRequests("rebirthRemote")==before+1)
    advance(2) assert(countRequests("rebirthRemote")==before+1)
    rebirthCountData.props.Value=11 strengthData.props.Value=0 advance(0.3)
    assert(countRequests("rebirthRemote")==before+1)
end)
check("auto rebirth waits through animation and map transitions",function()
    rebirthFixture(10,1000000)
    local before=countRequests("rebirthRemote")
    charData.attrs.IsRebirthing=true
    set("Auto rebirth (when ready)",true) advance(1)
    assert(countRequests("rebirthRemote")==before)
    charData.attrs.IsRebirthing=nil charData.attrs.LastMapCFrame=CFrame.new(1,2,3) advance(1)
    assert(countRequests("rebirthRemote")==before)
    charData.attrs.LastMapCFrame=nil advance(0.3)
    assert(countRequests("rebirthRemote")==before+1)
end)
check("rebirth requirement includes pet and Golden Rebirth reductions",function()
    rebirthFixture(10,29999)
    for i=1,3 do addSally() end
    playerData.attrs.UltimateGoldenRebirth=2
    local before=countRequests("rebirthRemote")
    set("Auto rebirth (when ready)",true) advance(0.5)
    assert(countRequests("rebirthRemote")==before)
    strengthData.props.Value=30000 advance(0.3)
    assert(countRequests("rebirthRemote")==before+1)
end)
check("rebirth discounts stop at the game's ten-percent floor",function()
    rebirthFixture(10,5999)
    for i=1,12 do addSally() end
    playerData.attrs.UltimateGoldenRebirth=100
    local before=countRequests("rebirthRemote")
    set("Auto rebirth (when ready)",true) advance(0.5)
    assert(countRequests("rebirthRemote")==before)
    strengthData.props.Value=6000 advance(0.3)
    assert(countRequests("rebirthRemote")==before+1)
end)
check("first rebirth honors the onboarding override",function()
    rebirthFixture(0,999)
    playerData.attrs.OnboardingRebirthStrength=1000
    local before=countRequests("rebirthRemote")
    set("Auto rebirth (when ready)",true) advance(0.5)
    assert(countRequests("rebirthRemote")==before)
    strengthData.props.Value=1000 advance(0.3)
    assert(countRequests("rebirthRemote")==before+1)
end)
check("rejected rebirths back off instead of spamming or stopping the hub",function()
    rebirthFixture(10,1000000) rebirthData.result=false
    local before=countRequests("rebirthRemote")
    set("Auto rebirth (when ready)",true) advance(10)
    local attempts=countRequests("rebirthRemote")-before
    assert(attempts==3,"Expected 3 backed-off attempts, got "..attempts)
    assert(_G.MuscleLegendsMatcha.running and controls["Auto rebirth (when ready)"].Value)
end)
check("invalid replicated stats cannot trigger a rebirth",function()
    rebirthFixture(10,0/0)
    local before=countRequests("rebirthRemote")
    set("Auto rebirth (when ready)",true) advance(1)
    assert(countRequests("rebirthRemote")==before)
end)
check("manual and automatic rebirth share one in-flight request",function()
    rebirthFixture(10,1000000)
    rebirthData.onInvoke=function() task.wait(0.5) return true,11 end
    local before=countRequests("rebirthRemote")
    click("Rebirth now") set("Auto rebirth (when ready)",true) advance(0.3)
    assert(countRequests("rebirthRemote")==before+1)
    advance(1) assert(countRequests("rebirthRemote")==before+1)
    _G.MuscleLegendsMatcha.Stop() advance(0.1)
end)
local sharedData=object("shared","Folder",storageData)
local catalogsData=object("catalogs","Folder",sharedData)
local ultimateCatalog=object("gameUltimatesFolder","Folder",catalogsData)
local ultimateRemote=object("ultimatesRemote","RemoteFunction",remotesData)
local demon=object("Demon Damage","Folder",ultimateCatalog)
local demonCost=object("rebirthCost","NumberValue",demon,{Value=10})
object("maxUpgrades","NumberValue",demon,{Value=5})
local galaxy=object("Galaxy Gains","Folder",ultimateCatalog)
object("rebirthCost","NumberValue",galaxy,{Value=10})
object("maxUpgrades","NumberValue",galaxy,{Value=5})
local function ultimateFixture(balance)
    rebirthFixture(balance,0)
    playerData.attrs.UltimateDemonDamage=0 playerData.attrs.UltimateGalaxyGains=0
    ultimateRemote.onInvoke=nil demonCost.props.Value=10
end
check("Ultimate reserve rejects 109 and accepts 110 leaving exactly 100",function()
    ultimateFixture(109)
    local before=countRequests("ultimatesRemote")
    set("Auto Ultimate upgrades (reserve 100)",true) advance(0.5)
    assert(countRequests("ultimatesRemote")==before)
    ultimateRemote.onInvoke=function(action,name)
        assert(action=="upgradeUltimate" and name=="Demon Damage")
        playerData.attrs.UltimateDemonDamage=1 rebirthCountData.props.Value=100 return true
    end
    rebirthCountData.props.Value=110 advance(2)
    assert(countRequests("ultimatesRemote")==before+1 and rebirthCountData.props.Value==100)
end)
check("Ultimate selection skips maxed or unknown levels and uses current cost",function()
    ultimateFixture(115)
    playerData.attrs.UltimateDemonDamage=5 playerData.attrs.UltimateGalaxyGains=nil
    local before=countRequests("ultimatesRemote")
    set("Auto Ultimate upgrades (reserve 100)",true) advance(0.5)
    assert(countRequests("ultimatesRemote")==before)
    playerData.attrs.UltimateGalaxyGains=1 advance(0.5)
    assert(countRequests("ultimatesRemote")==before)
    rebirthCountData.props.Value=120
    ultimateRemote.onInvoke=function(_,name) assert(name=="Galaxy Gains") return true end
    advance(0.5) assert(countRequests("ultimatesRemote")==before+1)
end)
check("Ultimate dispatch rereads the balance immediately before purchase",function()
    ultimateFixture(110)
    local original=methods.GetChildren
    methods.GetChildren=function(data)
        local children=original(data)
        if data==ultimateCatalog then rebirthCountData.props.Value=109 end
        return children
    end
    local before=countRequests("ultimatesRemote")
    set("Auto Ultimate upgrades (reserve 100)",true) advance(0.5)
    methods.GetChildren=original
    assert(countRequests("ultimatesRemote")==before)
end)
check("Ultimate waits for both replicated level and balance and blocks rebirth",function()
    ultimateFixture(200)
    ultimateRemote.onInvoke=function() task.wait(0.5) return true end
    local before=countRequests("ultimatesRemote") local rb=countRequests("rebirthRemote")
    set("Auto Ultimate upgrades (reserve 100)",true) advance(0.3)
    strengthData.props.Value=10000000 click("Rebirth now")
    assert(countRequests("rebirthRemote")==rb)
    advance(1) playerData.attrs.UltimateDemonDamage=1 advance(1)
    assert(countRequests("ultimatesRemote")==before+1)
    rebirthCountData.props.Value=190
    set("Auto Ultimate upgrades (reserve 100)",false) advance(0.5)
    click("Rebirth now") assert(countRequests("rebirthRemote")==rb+1)
end)
check("ambiguous Ultimate responses hold without retry even after retoggling",function()
    ultimateFixture(200)
    ultimateRemote.onInvoke=function() error("network failure") end
    local before=countRequests("ultimatesRemote")
    set("Auto Ultimate upgrades (reserve 100)",true) advance(12)
    set("Auto Ultimate upgrades (reserve 100)",false)
    set("Auto Ultimate upgrades (reserve 100)",true) advance(12)
    assert(countRequests("ultimatesRemote")==before+1)
end)
check("unconfirmed Ultimate acceptance holds after timeout",function()
    ultimateFixture(200) ultimateRemote.onInvoke=function() return true end
    local before=countRequests("ultimatesRemote")
    set("Auto Ultimate upgrades (reserve 100)",true) advance(25)
    assert(countRequests("ultimatesRemote")==before+1)
    assert(string.find(controls["Ultimate upgrades"].Description,"paused",1,true))
end)
check("rejected Ultimates back off and invalid balances fail closed",function()
    ultimateFixture(200) ultimateRemote.onInvoke=function() return false end
    local before=countRequests("ultimatesRemote")
    set("Auto Ultimate upgrades (reserve 100)",true) advance(4)
    assert(countRequests("ultimatesRemote")==before+1)
    rebirthCountData.props.Value=0/0 advance(8)
    assert(countRequests("ultimatesRemote")==before+1)
    _G.MuscleLegendsMatcha.Stop()
end)
local machinesData=object("machinesFolder","Folder",workspaceData)
local machineRemote=object("machineInteractRemote","RemoteFunction",remotesData)
local mountedData=object("machineInUse","ObjectValue",playerData)
local weightGain=object("strengthGain","IntValue",weightData,{Value=10})
local function addMachine(name,gain,duration,required)
    local model=object(name,"Model",machinesData)
    object("strengthGain","IntValue",model,{Value=gain})
    object("repTime","NumberValue",model,{Value=duration})
    local req=object("requirements","Folder",model)
    if required then object("Strength","IntValue",req,{Value=required}) end
    local seat=object("interactSeat","Seat",model,{CFrame=CFrame.new(gain,10,0),Position=Vector3.new(gain,10,0)})
    return model,seat,req
end
local function machineFixture()
    rebirthFixture(100,1000)
    machinesData.children={} mountedData.props.Value=nil
    if weightData.parent then
        for i,child in ipairs(weightData.parent.children) do if child==weightData then table.remove(weightData.parent.children,i) break end end
    end
    weightData.parent=bagData bagData.children[#bagData.children+1]=weightData
    workoutData.props.Value=1
    weightData.children={workoutData,weightGain}
    machineRemote.onInvoke=function(action,seat)
        if action=="useMachine" then mountedData.props.Value=seat return true end
        assert(action=="leaveMachine") mountedData.props.Value=nil return true
    end
    set("Exercise","Best strength source")
end
check("best training ranks gain per rep time and passes the real seat",function()
    machineFixture()
    local _,slow=addMachine("Slow",100,10,0)
    local _,best=addMachine("Fast",60,1,0)
    addMachine("Locked",1000,1,100000)
    local before=countRequests("machineInteractRemote") local moves=counts.positionWrites
    set("Auto train",true) advance(2)
    assert(countRequests("machineInteractRemote")==before+1)
    assert(mountedData.props.Value.Address==best.props.Address)
    assert(counts.positionWrites==moves+1)
    local last=requests[#requests]
    assert(last.name=="muscleEvent" and last.args[2].Address==best.props.Address)
end)
check("best training uses any satisfied requirement and skips occupied machines",function()
    machineFixture()
    local _,seat,req=addMachine("Alternative",60,1,999999)
    object("Rebirths","IntValue",req,{Value=100})
    local occupied=addMachine("Occupied",500,1,0)
    occupied.attrs={InUseUserId=2}
    addMachine("Invalid",0/0,1,0)
    set("Auto train",true) advance(2)
    assert(mountedData.props.Value.Address==seat.props.Address)
end)
check("rejected machine backs off and falls back to the best usable tool",function()
    machineFixture() addMachine("Unavailable",100,1,0)
    machineRemote.onInvoke=function() return false end
    local before=countRequests("machineInteractRemote")
    set("Auto train",true) advance(5)
    assert(countRequests("machineInteractRemote")==before+1)
    assert(controls["Training source"].Description=="Tool: Weight")
    assert(weightData.parent==charData)
end)
check("machine reps wait for replicated mounting and unconfirmed mounts back off",function()
    machineFixture() addMachine("Delayed",100,1,0)
    machineRemote.onInvoke=function() return true end
    local before=countRequests("muscleEvent") local mounts=countRequests("machineInteractRemote")
    set("Auto train",true) advance(2)
    assert(countRequests("muscleEvent")==before)
    advance(4)
    assert(countRequests("machineInteractRemote")==mounts+1)
    assert(controls["Training source"].Description=="Tool: Weight")
end)
check("machine mounting and delayed stop share one request and release afterward",function()
    machineFixture() addMachine("Yielding",100,1,0)
    machineRemote.onInvoke=function(action,seat)
        if action=="useMachine" then task.wait(1) mountedData.props.Value=seat return true end
        mountedData.props.Value=nil return true
    end
    local before=countRequests("machineInteractRemote")
    set("Auto train",true) advance(0.8)
    set("Auto train",false) advance(2)
    assert(countRequests("machineInteractRemote")==before+2 and not mountedData.props.Value)
end)
check("rebirth releases the training machine before sending its request",function()
    machineFixture() addMachine("Fast",60,1,0)
    set("Auto train",true) advance(2)
    strengthData.props.Value=10000000
    local before=#requests click("Rebirth now")
    assert(requests[before+1].name=="machineInteractRemote" and requests[before+1].args[1]=="leaveMachine")
    assert(requests[before+2].name=="rebirthRemote")
    assert(not mountedData.props.Value)
end)
check("no-gain machines fall back without teleporting every rep",function()
    machineFixture() addMachine("No gains",60,1,0)
    local moves=counts.positionWrites
    set("Auto train",true) advance(12)
    assert(controls["Training source"].Description=="Tool: Weight")
    assert(counts.positionWrites==moves+1)
end)
check("switching exercises and unload release only the owned machine",function()
    machineFixture() addMachine("Fast",60,1,0)
    set("Auto train",true) advance(2)
    set("Exercise","Direct reps") advance(1)
    assert(not mountedData.props.Value)
    set("Exercise","Best strength source") advance(2)
    _G.MuscleLegendsMatcha.Stop() advance(0.5)
    assert(not mountedData.props.Value and activeThreads()==0)
end)
check("stale normal bench release keeps training and cannot block rebirth",function()
    machineFixture()
    local _,old=addMachine("Current bench",40,1,0)
    addMachine("Better bench",60,1,0)
    mountedData.props.Value=wrap(old)
    machineRemote.onInvoke=function(action) assert(action=="leaveMachine") return true end
    local before=countRequests("machineInteractRemote") local reps=countRequests("muscleEvent")
    set("Auto train",true) advance(4)
    assert(controls["Auto train"].Value)
    assert(countRequests("machineInteractRemote")==before)
    assert(countRequests("muscleEvent")>reps)
    assert(string.find(controls["Training source"].Description,"Current machine",1,true))
    strengthData.props.Value=10000000
    local rb=countRequests("rebirthRemote") click("Rebirth now")
    assert(countRequests("rebirthRemote")==rb+1)
    _G.MuscleLegendsMatcha.Stop() advance(0.5)
end)
check("manual machine switching tolerates a temporarily missing parent",function()
    machineFixture()
    local _,old=addMachine("Old bench",60,1,0)
    mountedData.props.Value=wrap(old)
    set("Auto train",true) advance(0.5)
    local model,seat=addMachine("Hallowed Bar Lift",600,1.5,0)
    seat.parent=nil mountedData.props.Value=wrap(seat)
    local moves=counts.positionWrites
    advance(1)
    assert(controls["Auto train"].Value and counts.positionWrites==moves)
    seat.parent=model advance(1)
    assert(controls["Auto train"].Value)
    assert(requests[#requests].name=="muscleEvent" and requests[#requests].args[2].Address==seat.props.Address)
    assert(string.find(controls["Training source"].Description,"Hallowed Bar Lift",1,true))
end)
local petRemote=object("equipPetEvent","RemoteEvent",remotesData)
local petsFolder=object("petsFolder","Folder",playerData)
local petRarity=object("Unique","Folder",petsFolder)
local function petFixture()
    rebirthFixture(100,0)
    mountedData.props.Value=nil petRarity.children={} equippedPetsData.children={}
    playerData.attrs.UltimatePetSlot=0 petRemote.onFire=nil
    object("Pet A","StringValue",petRarity)
end
check("auto equip best requests once and ignores unchanged inventory",function()
    petFixture()
    local before=countRequests("equipPetEvent")
    set("Auto equip best pets",true) advance(15)
    assert(countRequests("equipPetEvent")==before+1)
    object("Pet B","StringValue",petRarity) advance(2.5)
    assert(countRequests("equipPetEvent")==before+2)
    set("Auto equip best pets",false) object("Pet C","StringValue",petRarity) advance(5)
    assert(countRequests("equipPetEvent")==before+2)
end)
check("equip best absorbs its own loadout update without repeated requests",function()
    petFixture()
    petRemote.onFire=function(action)
        assert(action=="equipBest")
        equippedPetsData.children={}
        local pet=petRarity.children[1]
        local slot=object("pet1","ObjectValue",equippedPetsData,{Value=wrap(pet)})
        object("petReference","ObjectValue",slot,{Value=wrap(pet)})
    end
    local before=countRequests("equipPetEvent")
    set("Auto equip best pets",true) advance(12)
    assert(countRequests("equipPetEvent")==before+1)
end)
check("pets acquired while equipment is settling still trigger equip best",function()
    petFixture()
    local before=countRequests("equipPetEvent")
    set("Auto equip best pets",true) advance(0.5)
    object("New pet","StringValue",petRarity) advance(5)
    assert(countRequests("equipPetEvent")==before+2)
end)
check("Pet Slot Ultimate refresh waits for both upgrade confirmations",function()
    petFixture()
    local slot=object("+1 Pet Slot","Folder",ultimateCatalog)
    object("rebirthCost","NumberValue",slot,{Value=150}) object("maxUpgrades","NumberValue",slot,{Value=3})
    playerData.attrs.UltimateDemonDamage=5 playerData.attrs.UltimateGalaxyGains=5
    rebirthCountData.props.Value=250
    ultimateRemote.onInvoke=function(action,name) assert(action=="upgradeUltimate" and name=="+1 Pet Slot") return true end
    set("Auto equip best pets",true) advance(5)
    local before=countRequests("equipPetEvent")
    set("Auto Ultimate upgrades (reserve 100)",true) advance(0.5)
    playerData.attrs.UltimatePetSlot=1 advance(3)
    assert(countRequests("equipPetEvent")==before)
    rebirthCountData.props.Value=100 advance(1)
    assert(countRequests("equipPetEvent")==before+1)
end)
check("hub preferences persist across unload without saving teardown values",function()
    start()
    set("Requests / second","20") set("Keep size 2 (every 2s)",true)
    set("Auto equip best pets",true) set("Auto train",true)
    _G.MuscleLegendsMatcha.Stop()
    local saved=jsonDecode(files[settingsFile])
    assert(saved.options.train and saved.options.small and saved.options.equipBest and saved.options.rate==3)
    start(true)
    assert(controls["Auto train"].Value and controls["Keep size 2 (every 2s)"].Value)
    assert(controls["Auto equip best pets"].Value and controls["Requests / second"].Value=="20")
end)
check("fresh and malformed preferences use the user's requested defaults",function()
    _G.MuscleLegendsMatcha.Stop() files[settingsFile]="broken JSON" start(true)
    assert(controls["Auto train"].Value and controls["Auto rebirth (when ready)"].Value)
    assert(controls["Auto Ultimate upgrades (reserve 100)"].Value and controls["Auto equip best pets"].Value)
    assert(controls["Exercise"].Value=="Direct reps" and controls["Requests / second"].Value=="5")
    assert(controls["Keep size 2 (every 2s)"].Value)
    _G.MuscleLegendsMatcha.Stop()
    files[settingsFile]=jsonEncode({version=1,options={train=false,exercise=999,rate=0,small=false}})
    start(true)
    assert(not controls["Auto train"].Value and not controls["Keep size 2 (every 2s)"].Value)
    assert(controls["Exercise"].Value=="Direct reps" and controls["Requests / second"].Value=="5")
    _G.MuscleLegendsMatcha.Stop()
end)
originalPrint(string.format("%d contract checks passed; port and actual REM source compile.",passed))
