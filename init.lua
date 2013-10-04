-- returns whether the pickup failed or not.
function pickup(player,inv,object)
    if inv and inv:room_for_item("main", ItemStack(object:get_luaentity().itemstring)) then
        inv:add_item("main", ItemStack(object:get_luaentity().itemstring))
        if object:get_luaentity().itemstring ~= "" then
            minetest.sound_play("item_drop_pickup", {
                to_player = player:get_player_name(),
                gain = 0.4,
            })
        end
        object:get_luaentity().itemstring = ""
        object:remove()
        return false;
    else
        return true;
    end
end

function isGood(object)
    if not object:is_player() and object:get_luaentity() and object:get_luaentity().name == "__builtin:item" then
        return true
    else
        return false
    end
end

function pickupOrStop(object,inv,player)
    local lua = object:get_luaentity()
    if object == nil or lua == nil or lua.itemstring == nil then
        return
    end
    if pickup(object,inv,player) then
        -- no pickup, even though it's close, so
        -- stop moving towards the player
        object:setvelocity({x=0,y=0,z=0})
        -- also we can walk on it and it can push pressure plates
        object:get_luaentity().physical_state = true
        object:get_luaentity().object:set_properties({
            physical = true
        })
    end
end

function moveTowards(object,inv,pos1)
    -- move it towards the player, then pick it up after a delay!
    pos1.y = pos1.y+0.2 -- head towards player's belt
    local pos2 = object:getpos()
    local vec = {x=pos1.x-pos2.x, y=pos1.y-pos2.y, z=pos1.z-pos2.z}
    vec.x = vec.x*3
    vec.y = vec.y*3
    vec.z = vec.z*3
    object:setvelocity(vec)
    -- make sure object doesn't push the player around!
    object:get_luaentity().physical_state = false
    object:get_luaentity().object:set_properties({
        physical = false
    })

    minetest.after(1, function(args)
        pickupOrStop(object,inv,player);
    end, {player, inv, object})
end

if minetest.setting_get("enable_item_pickup") then
    minetest.register_globalstep(function(dtime)
        for _,player in ipairs(minetest.get_connected_players()) do
            if player:get_hp() > 0 or not minetest.setting_getbool("enable_damage") then
                local playerPosition = player:getpos()
                playerPosition.y = playerPosition.y+0.5
                local inv = player:get_inventory()

                for _,object in ipairs(minetest.env:get_objects_inside_radius(playerPosition, 1)) do
                    if isGood(object) then
                        pickup(player,inv,object)
                    end
                end

                for _,object in ipairs(minetest.env:get_objects_inside_radius(playerPosition, 2)) do
                    if isGood(object) and
                        object:get_luaentity().collect and
                        inv and
                        inv:room_for_item("main", ItemStack(object:get_luaentity().itemstring))
                        then
                          moveTowards(object,inv,playerPosition);
                    end
                end
            end
        end
    end)
end

function expireLater(expiration,obj)
    minetest.after(expiration,function(obj)
        obj:remove()
    end, obj)
end

function minetest.handle_node_drops(pos, drops, digger)
    local inv
    if minetest.setting_getbool("creative_mode") and digger and digger:is_player() then
        inv = digger:get_inventory()
    end
    for _,item in ipairs(drops) do
        local count, name
        if type(item) == "string" then
            count = 1
            name = item
        else
            count = item:get_count()
            name = item:get_name()
        end
        -- Only drop the item if not in creative, or if the item is not in creative inventory
        if not inv or not inv:contains_item("main", ItemStack(name)) then
            for i=1,count do
                local obj = minetest.env:add_item(pos, name)
                if obj ~= nil then
                    -- Set this to make the item move towards the player later
                    local lua = obj:get_luaentity()
                    lua.collect = true
                    local x = math.random(1, 5)
                    if math.random(1,2) == 1 then
                        x = -x
                    end
                    local z = math.random(1, 5)
                    if math.random(1,2) == 1 then
                        z = -z
                    end
                    -- hurl it out into space at a random velocity
                    -- (still falling though)
                    obj:setvelocity({x=1/x, y=obj:getvelocity().y, z=1/z})

                    if minetest.setting_get("remove_items") and tonumber(minetest.setting_get("remove_items")) then
                        -- we will hold the age as a property of the lua object
                        -- but that won't last a server restart, or an object unloading.
                        --
                        -- By returning the age from get_staticdata, it gets serialized
                        -- along with the object on disk. The staticdata is provided again
                        -- during the 'on_activate' event, whether the server restarts
                        -- or the object unloads.
                        --
                        -- In this way we should be able to preserve an object's age
                        -- so it can expire as soon as it loads, if it's really old.

                        local expiration = tonumber(minetest.setting_get("remove_items"))

                        lua.age = minetest.get_gametime()

                        -- if on_activate gets called when the object is first
                        -- spawned, then expireLater would get called twice, if
                        -- we didn't set an alreadyActivated flag.

                        obj.on_activate = function(obj, staticdata)
                            local lua = obj:get_luaentity()
                            if lua.alreadyActivated then return end
                            lua.alreadyActivated = true;
                            local now = minetest.get_gametime();
                            local age = tonumber(staticdata);
                            if now - age > expiration then
                                obj:remove()
                            else
                                obj:get_luaentity().age = tonumber(staticdata);
                                -- wait the rest of the time left, then expire
                                expireLater(obj,expiration-(now-age));
                            end
                        end
                        obj.get_staticdata = function(obj)
                            return obj:get_luaentity().age
                        end
                        lua.alreadyActivated = true;
                        expireLater(obj,expiration);
                    end
                end
            end
        end
    end
end

if minetest.setting_get("log_mods") then
    minetest.log("action", "item_drop loaded")
end
