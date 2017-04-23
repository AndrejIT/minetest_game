local cart_entity = {
	physical = false, -- otherwise going uphill breaks
	collisionbox = {-0.5, -0.5, -0.5, 0.5, 0.5, 0.5},
	visual = "mesh",
	mesh = "carts_cart.b3d",
	visual_size = {x=1, y=1},
	textures = {"carts_cart.png"},

	driver = nil,
	punched = false, -- used to re-send velocity and position
    punch_direction = true,
    control_left = nil,
    control_right = nil,

	attached_items = {},

    old_pos = nil,	--rounded
    next_pos = nil,	--rounded
    old_direction = nil,

    -- sound refresh interval = 1.0sec
    rail_sound = function(self, dtime)
    	if not self.sound_ttl then
    		self.sound_ttl = 1.0
    		return
    	elseif self.sound_ttl > 0 then
    		self.sound_ttl = self.sound_ttl - dtime
    		return
    	end
    	self.sound_ttl = 1.0
    	if self.sound_handle then
    		local handle = self.sound_handle
    		self.sound_handle = nil
    		minetest.after(0.2, minetest.sound_stop, handle)
    	end
    	local vel = self.object:getvelocity()
    	local speed = vector.length(vel)
    	if speed > 3 then
    		self.sound_handle = minetest.sound_play(
    			"carts_cart_moving", {
    			object = self.object,
    			gain = (speed / carts.speed_max) / 2,
    			loop = true,
    		})
    	end
    end,

    --set yaw using vector
    set_yaw = function(self, v)
        if v.x == 0 and v.z == 0 then
            return  --keep old jaw
        end

        local yaw = math.pi
        if v.z < 0 then
            yaw = math.pi - math.atan(v.x/v.z)
        elseif v.z > 0 then
            yaw = -math.atan(v.x/v.z)
        elseif v.x > 0 then
            yaw = -math.pi/2
        elseif v.x < 0 then
            yaw = math.pi/2
        end

        self.object:setyaw(yaw)
    end,

    --get yaw as a vector
    get_yaw = function(self)
        local yaw = self.object:getyaw()

        local v = {x=0, y=0, z=0}

        yaw = yaw + math.pi/2
        v.x = math.cos(yaw)
        v.z = math.sin(yaw)

        v = vector.normalize(v)
        return v
    end,

    --set velocity
    set_velocity = function(self, v)
        if not v then
            v = {x=0, y=0, z=0}
        end
        self.object:setvelocity(v)
    end,

    --align cart position on railroad
    precize_on_rail = function(self, pos)
        local v = self.object:getvelocity()
        local aligned_pos = table.copy(pos)
    	if self.old_direction.x == 0 and math.abs(self.old_pos.x-pos.x)>0.2 then
            aligned_pos.x = self.old_pos.x
    		self.object:setpos(aligned_pos)
    	elseif self.old_direction.z == 0 and math.abs(self.old_pos.z-pos.z)>0.2 then
            aligned_pos.z = self.old_pos.z
    		self.object:setpos(aligned_pos)
    	elseif self.old_direction.y == 0 and math.abs(self.old_pos.y-pos.y)>0.2 then
            aligned_pos.y = self.old_pos.y
    		self.object:setpos(aligned_pos)
    	end
    end,

    --position, relative to
    --x-FRONT/BACK, z-LEFT/RIGHT
    get_pos_relative = function(self, rel_pos, position, direction)
        local pos = position
        if pos == nil then
            pos = self.object:getpos()
        end

        if not rel_pos then
            return pos
        elseif rel_pos.x == 0 and rel_pos.z == 0 then
            return {x=pos.x, y=pos.y+rel_pos.y, z=pos.z}
        end

        local v = direction
        if v == nil then
            local yaw = self.object:getyaw()

            v = {x=0, y=0, z=0}

            yaw = yaw + math.pi/2
            v.x = math.cos(yaw)
            v.z = math.sin(yaw)

            v = vector.normalize(v)
        end

        if --NORD
            v.x > 0 and
            v.z >= -v.x and v.z <= v.x
        then
            return {x=pos.x+rel_pos.x, y=pos.y+rel_pos.y, z=pos.z+rel_pos.z}
        elseif --EAST
            v.z < 0 and
            v.x >= v.z and v.x <= -v.z
        then
            return {x=pos.x-rel_pos.z, y=pos.y+rel_pos.y, z=pos.z-rel_pos.x}
        elseif --WEST
            v.z > 0 and
            v.x >= -v.z and v.x <= v.z
        then
            return {x=pos.x+rel_pos.z, y=pos.y+rel_pos.y, z=pos.z+rel_pos.x}
        elseif --SOUTH
            v.x < 0 and
            v.z >= v.x and v.z <= -v.x
        then
            return {x=pos.x-rel_pos.x, y=pos.y+rel_pos.y, z=pos.z-rel_pos.z}
        end

        minetest.log("warning", "Object direction not set")
        return pos  --should not be reached
    end,

    --calculate next acceptable cart position
    get_next_rail_pos = function(self, pos, dir)
        local n_pos = nil
        if self.control_left then
            if minetest.get_item_group(minetest.get_node(self:get_pos_relative({x=0, y=0, z=1}, pos, dir)).name, "rail") > 0 then
                n_pos = self:get_pos_relative({x=0, y=0, z=1}, pos, dir);    --left
            elseif minetest.get_item_group(minetest.get_node(self:get_pos_relative({x=0, y=-1, z=1}, pos, dir)).name, "rail") > 0 then
                n_pos = self:get_pos_relative({x=0, y=-1, z=1}, pos, dir);    --left down
            elseif minetest.get_item_group(minetest.get_node(self:get_pos_relative({x=0, y=1, z=1}, pos, dir)).name, "rail") > 0 then
                n_pos = self:get_pos_relative({x=0, y=1, z=1}, pos, dir);    --left up
            elseif minetest.get_item_group(minetest.get_node(self:get_pos_relative({x=1, y=0, z=0}, pos, dir)).name, "rail") > 0 then
                n_pos = self:get_pos_relative({x=1, y=0, z=0}, pos, dir);     --front
            elseif minetest.get_item_group(minetest.get_node(self:get_pos_relative({x=1, y=1, z=0}, pos, dir)).name, "rail") > 0 then
                n_pos = self:get_pos_relative({x=1, y=1, z=0}, pos, dir);     --up
            elseif minetest.get_item_group(minetest.get_node(self:get_pos_relative({x=1, y=-1, z=0}, pos, dir)).name, "rail") > 0 then
                n_pos = self:get_pos_relative({x=1, y=-1, z=0}, pos, dir);    --down
            elseif minetest.get_item_group(minetest.get_node(self:get_pos_relative({x=0, y=0, z=-1}, pos, dir)).name, "rail") > 0 then
                n_pos = self:get_pos_relative({x=0, y=0, z=-1}, pos, dir);    --right
            elseif minetest.get_item_group(minetest.get_node(self:get_pos_relative({x=0, y=-1, z=-1}, pos, dir)).name, "rail") > 0 then
                n_pos = self:get_pos_relative({x=0, y=-1, z=-1}, pos, dir);    --right down
            elseif minetest.get_item_group(minetest.get_node(self:get_pos_relative({x=0, y=1, z=-1}, pos, dir)).name, "rail") > 0 then
                n_pos = self:get_pos_relative({x=0, y=1, z=-1}, pos, dir);    --right up
            else
                n_pos = nil
            end
        elseif self.control_right then
            if minetest.get_item_group(minetest.get_node(self:get_pos_relative({x=0, y=0, z=-1}, pos, dir)).name, "rail") > 0 then
                n_pos = self:get_pos_relative({x=0, y=0, z=-1}, pos, dir);    --right
            elseif minetest.get_item_group(minetest.get_node(self:get_pos_relative({x=0, y=-1, z=-1}, pos, dir)).name, "rail") > 0 then
                n_pos = self:get_pos_relative({x=0, y=-1, z=-1}, pos, dir);    --right down
            elseif minetest.get_item_group(minetest.get_node(self:get_pos_relative({x=0, y=1, z=-1}, pos, dir)).name, "rail") > 0 then
                n_pos = self:get_pos_relative({x=0, y=1, z=-1}, pos, dir);    --right up
            elseif minetest.get_item_group(minetest.get_node(self:get_pos_relative({x=1, y=0, z=0}, pos, dir)).name, "rail") > 0 then
                n_pos = self:get_pos_relative({x=1, y=0, z=0}, pos, dir);     --front
            elseif minetest.get_item_group(minetest.get_node(self:get_pos_relative({x=1, y=1, z=0}, pos, dir)).name, "rail") > 0 then
                n_pos = self:get_pos_relative({x=1, y=1, z=0}, pos, dir);     --up
            elseif minetest.get_item_group(minetest.get_node(self:get_pos_relative({x=1, y=-1, z=0}, pos, dir)).name, "rail") > 0 then
                n_pos = self:get_pos_relative({x=1, y=-1, z=0}, pos, dir);    --down
            elseif minetest.get_item_group(minetest.get_node(self:get_pos_relative({x=0, y=0, z=1}, pos, dir)).name, "rail") > 0 then
                n_pos = self:get_pos_relative({x=0, y=0, z=1}, pos, dir);    --left
            elseif minetest.get_item_group(minetest.get_node(self:get_pos_relative({x=0, y=-1, z=1}, pos, dir)).name, "rail") > 0 then
                n_pos = self:get_pos_relative({x=0, y=-1, z=1}, pos, dir);    --left down
            elseif minetest.get_item_group(minetest.get_node(self:get_pos_relative({x=0, y=1, z=1}, pos, dir)).name, "rail") > 0 then
                n_pos = self:get_pos_relative({x=0, y=1, z=1}, pos, dir);    --left up
            else
                n_pos = nil
            end
        else
            if minetest.get_item_group(minetest.get_node(self:get_pos_relative({x=1, y=0, z=0}, pos, dir)).name, "rail") > 0 then
                n_pos = self:get_pos_relative({x=1, y=0, z=0}, pos, dir);     --front
            elseif minetest.get_item_group(minetest.get_node(self:get_pos_relative({x=1, y=1, z=0}, pos, dir)).name, "rail") > 0 then
                n_pos = self:get_pos_relative({x=1, y=1, z=0}, pos, dir);     --up
            elseif minetest.get_item_group(minetest.get_node(self:get_pos_relative({x=1, y=-1, z=0}, pos, dir)).name, "rail") > 0 then
                n_pos = self:get_pos_relative({x=1, y=-1, z=0}, pos, dir);    --down
            elseif minetest.get_item_group(minetest.get_node(self:get_pos_relative({x=0, y=0, z=1}, pos, dir)).name, "rail") > 0 then
                n_pos = self:get_pos_relative({x=0, y=0, z=1}, pos, dir);    --left
            elseif minetest.get_item_group(minetest.get_node(self:get_pos_relative({x=0, y=0, z=-1}, pos, dir)).name, "rail") > 0 then
                n_pos = self:get_pos_relative({x=0, y=0, z=-1}, pos, dir);    --right
            elseif minetest.get_item_group(minetest.get_node(self:get_pos_relative({x=0, y=-1, z=1}, pos, dir)).name, "rail") > 0 then
                n_pos = self:get_pos_relative({x=0, y=-1, z=1}, pos, dir);    --left down
            elseif minetest.get_item_group(minetest.get_node(self:get_pos_relative({x=0, y=-1, z=-1}, pos, dir)).name, "rail") > 0 then
                n_pos = self:get_pos_relative({x=0, y=-1, z=-1}, pos, dir);    --right down
            elseif minetest.get_item_group(minetest.get_node(self:get_pos_relative({x=0, y=1, z=1}, pos, dir)).name, "rail") > 0 then
                n_pos = self:get_pos_relative({x=0, y=1, z=1}, pos, dir);    --left up
            elseif minetest.get_item_group(minetest.get_node(self:get_pos_relative({x=0, y=1, z=-1}, pos, dir)).name, "rail") > 0 then
                n_pos = self:get_pos_relative({x=0, y=1, z=-1}, pos, dir);    --right up
            else
                n_pos = nil
            end
        end
        if n_pos then
            n_pos = vector.round(n_pos)
        end
        return n_pos
    end,

    on_activate = function(self, staticdata, dtime_s)
        self.object:set_armor_groups({immortal=1})

        --decrease speed after cart is left unattended
        self.object:setvelocity(vector.multiply(self.object:getvelocity(), 0.5))

        local pos = self.object:getpos()
        local d = self:get_yaw()

        self.old_pos = vector.round(pos)
        self.old_direction = self:get_yaw()

        --strict direction
        self.old_direction.y = 0
        if math.abs(self.old_direction.x) > math.abs(self.old_direction.z) then
            self.old_direction.z = 0
        else
            self.old_direction.x = 0
        end
        self.old_direction = vector.normalize(self.old_direction)
    end,

    on_step = function(self, dtime)
        local pos = self.object:getpos()
        local p = vector.round(pos)
        local v = self.object:getvelocity()
        local s = vector.length(v)

        --reset if cart stopped because of energy loss
        if self.next_pos ~= nil and s < 0.01 then
            self.next_pos = nil
        end

        -- Get player controls
        if self.driver then
            player = minetest.get_player_by_name(self.driver)
            if player then
                ctrl = player:get_player_control()
                if ctrl and ctrl.up then
                    self.control_left = nil
                    self.control_right = nil
                elseif ctrl and ctrl.right then
                    self.control_left = nil
                    self.control_right = true
                elseif ctrl and ctrl.left then
                    self.control_left = true
                    self.control_right = nil
                elseif ctrl and ctrl.down then
                    if (s - 1) >= 0 then
                        s = s - 1.5
                    end
                end
            end
        end

        --align cart on railroad
        self:precize_on_rail(pos)

        --calculate where cart will go next
        if self.next_pos == nil or
            (math.abs(self.old_pos.x - pos.x) + math.abs(self.old_pos.z - pos.z)) > 0.5 then
            local node = minetest.get_node(p)

            if node.name == "ignore" then
                --map not loaded yet
                self.next_pos = nil
            elseif minetest.get_item_group(node.name, "rail") > 0 and
                (math.abs(self.old_pos.x - pos.x) + math.abs(self.old_pos.z - pos.z)) > 1.5 then
                --cart went too far, accept new road
                self.old_pos = table.copy(p)
                self.next_pos = self:get_next_rail_pos(p, self.old_direction)
                s = s * 0.9
            elseif (math.abs(self.old_pos.x - pos.x) + math.abs(self.old_pos.z - pos.z)) > 1.5 then
                --cart went too far, return to old road
                if self.next_pos then
                    local nextnext_pos = self:get_next_rail_pos(self.next_pos, self.old_direction)
                    if nextnext_pos == nil then
                        --dead end, stop cart
                        self.old_pos = table.copy(self.next_pos)
                        self.next_pos = nil
                        self.object:setpos(self.old_pos)
                        s = 0
                    else
                        --continue from last rail
                        self.old_pos = table.copy(nextnext_pos)
                        self.object:setpos(nextnext_pos)
                        self.next_pos = self:get_next_rail_pos(nextnext_pos, self.old_direction)
                    end
                end
                s = s * 0.9
            elseif minetest.get_item_group(node.name, "rail") > 0 and self.next_pos and
                (math.abs(self.next_pos.x - pos.x) + math.abs(self.next_pos.z - pos.z)) < 0.5 then
                --on next rail
                self.old_pos = table.copy(p)
                self.next_pos = self:get_next_rail_pos(p, self.old_direction)

                if self.next_pos == nil then
                    --dead end, stop cart
                    self.next_pos = nil
                    self.object:setpos(self.old_pos)
                    s = 0
                end
            elseif minetest.get_item_group(node.name, "rail") > 0 and self.next_pos == nil then
                --on rail position
                self.old_pos = table.copy(p)
                self.next_pos = self:get_next_rail_pos(p, self.old_direction)

                if self.next_pos == nil then
                    --dead end, stop cart
                    self.next_pos = nil
                    self.object:setpos(self.old_pos)
                    s = 0
                end
            end

            self.control_left = nil
            self.control_right = nil
        end

        --calculate next cart direction
        if self.old_pos ~=nil and self.next_pos ~= nil then
            local dir = vector.direction(self.old_pos, self.next_pos)
            --dir.y = 0
            --strict direction
            if math.abs(dir.x) > math.abs(dir.z) then
                dir.z = 0
            else
                dir.x = 0
            end
            dir = vector.normalize(dir)

            --more energy loss on turns
            if dir.x ~= self.old_direction.x or dir.z ~= self.old_direction.z then
                s = s - 0.4
            end

            --do not flip!
            if dir.x * self.old_direction.x ~= -1 and dir.z * self.old_direction.z ~= -1 then
                self.old_direction = table.copy(dir)
            end
        end

        --handle punch
        if self.punched and self.punch_direction then
            if self.next_pos == nil then
                self.next_pos = self:get_next_rail_pos(p, self.old_direction)
                --wait...
            elseif (s + 1) <= carts.punch_speed_max then
                s = s + 1
                local dir = table.copy(self.punch_direction)
                dir.y = 0
                --strict direction
                if math.abs(dir.x) > math.abs(dir.z) then
                    dir.z = 0
                else
                    dir.x = 0
                end
                dir = vector.normalize(dir)
                self.old_direction = table.copy(dir)
                self.punched = nil
            else
                self.punched = nil
            end
        end

        --check rail and handle energy loss/increase
        if self.next_pos ~= nil then
            local node = minetest.get_node(p)

            if node.name == "carts:powerrail" then
                s = s + 0.5     --powerrail
            elseif node.name == "carts:brakerail" then
                s = s - 0.5    --brakerail
            else
                s = s - 0.05    --rail or something else
            end
        end

        --mesecons support?
        -- --local acceleration = minetest.get_item_group(node.name, "acceleration")
        -- local acceleration = tonumber(minetest.get_meta(p):get_string("cart_acceleration"))--original PilzAdam version
        -- if acceleration > 0 or acceleration < 0 then
        --     s = s + acceleration     --powerrail
        -- end

        --handle uphill/downhill
        if self.next_pos ~= nil then
            if self.next_pos.y < self.old_pos.y then
                s = s + 0.5
            elseif self.next_pos.y > self.old_pos.y then
                s = s - 0.5
            end
        end

        --limit speed
        if s > carts.speed_max then
            s = carts.speed_max
        elseif s < 0 then
            s = 0
        end

        --set new cart object parameters
        v = vector.multiply(self.old_direction, s)
        self:set_velocity(v)
        self:set_yaw(self.old_direction)

        --animation for uphill/downhill
        if self.next_pos then
            if self.next_pos.y < self.old_pos.y then
                self.object:set_animation({x=1, y=1}, 1, 0)
            elseif self.next_pos.y > self.old_pos.y then
                self.object:set_animation({x=2, y=2}, 1, 0)
            else
                self.object:set_animation({x=0, y=0}, 1, 0)
            end
        else
            self.object:set_animation({x=0, y=0}, 1, 0)
        end

        --handle sound
        self:rail_sound(dtime)
    end,

    on_rightclick = function(self, clicker)
    	if not clicker or not clicker:is_player() then
    		return
    	end
    	local player_name = clicker:get_player_name()
    	if self.driver and player_name == self.driver then
    		self.driver = nil
    		carts:manage_attachment(clicker, nil)
    	elseif not self.driver then
    		self.driver = player_name
    		carts:manage_attachment(clicker, self.object)
    	end
    end,

    on_punch = function(self, puncher, time_from_last_punch, tool_capabilities, direction)
    	-- Punched by non-player
    	if not puncher or not puncher:is_player() then
    		self.punched = true
            self.punch_direction = direction
    		return
    	end
    	-- Player digs cart by sneak-punch
    	if puncher:get_player_control().sneak then
    		if self.sound_handle then
    			minetest.sound_stop(self.sound_handle)
    		end
    		-- Detach driver and items
    		if self.driver then
    			if self.old_pos then
    				self.object:setpos(self.old_pos)
    			end
    			local player = minetest.get_player_by_name(self.driver)
    			carts:manage_attachment(player, nil)
    		end
    		for _,obj_ in ipairs(self.attached_items) do
    			if obj_ then
    				obj_:set_detach()
    			end
    		end
    		-- Pick up cart
    		local inv = puncher:get_inventory()
    		if not (creative and creative.is_enabled_for
    				and creative.is_enabled_for(puncher:get_player_name()))
    				or not inv:contains_item("main", "carts:cart") then
    			local leftover = inv:add_item("main", "carts:cart")
    			-- If no room in inventory add a replacement cart to the world
    			if not leftover:is_empty() then
    				minetest.add_item(self.object:getpos(), leftover)
    			end
    		end
    		self.object:remove()
    		return
    	end

        self.punched = true
    	self.punch_direction = puncher:get_look_dir()
    end
}

minetest.register_entity("carts:cart", cart_entity)

minetest.register_craftitem("carts:cart", {
	description = "Cart (Sneak+Click to pick up)",
	inventory_image = minetest.inventorycube("carts_cart_top.png", "carts_cart_side.png", "carts_cart_side.png"),
	wield_image = "carts_cart_side.png",
	on_place = function(itemstack, placer, pointed_thing)
		local under = pointed_thing.under
		local node = minetest.get_node(under)
		local udef = minetest.registered_nodes[node.name]
		if udef and udef.on_rightclick and
				not (placer and placer:get_player_control().sneak) then
			return udef.on_rightclick(under, node, placer, itemstack,
				pointed_thing) or itemstack
		end

		if not pointed_thing.type == "node" then
			return
		end
        if minetest.get_item_group(minetest.get_node(pointed_thing.under).name, "rail") > 0 then
			minetest.add_entity(pointed_thing.under, "carts:cart")
        elseif minetest.get_item_group(minetest.get_node(pointed_thing.above).name, "rail") > 0 then
			minetest.add_entity(pointed_thing.above, "carts:cart")
		else
			return
		end

		minetest.sound_play({name = "default_place_node_metal", gain = 0.5},
			{pos = pointed_thing.above})

		if not (creative and creative.is_enabled_for
				and creative.is_enabled_for(placer:get_player_name())) then
			itemstack:take_item()
		end
		return itemstack
	end,
})

minetest.register_craft({
	output = "carts:cart",
	recipe = {
		{"default:steel_ingot", "", "default:steel_ingot"},
		{"default:steel_ingot", "default:steel_ingot", "default:steel_ingot"},
	},
})
