
local ArmorBatteryObserver = class()

--Called first every time
function ArmorBatteryObserver:initialize()
	-- list all the saved variables
	self._sv.entity = nil
end

--Called once on creation
function ArmorBatteryObserver:create(entity)
	self._sv.entity = entity
end

--Always called. If restore, called after restore.
function ArmorBatteryObserver:activate()
	self._entity = self._sv.entity
end

function ArmorBatteryObserver:post_activate()
  self._battery_listener = radiant.events.listen(self._entity, 'stonehearth:combat:battery', self, self._on_battery)
end

function ArmorBatteryObserver:_on_battery(e)

	-- Get the entity's armor data
  local armor = radiant.entities.get_equipped_item(self._entity, 'torso')

  -- Check the armor's data
  if not armor then
        -- Leave if no armor exists
    return
  end
    -- Get the armor's brittleness component
    local brittle_component = armor:get_component('bastioneers:brittleness')

    -- Check if it is brittle
  	if not brittle_component then
      -- leave if no brittle data exists
    	return
  	end

    brittle_component:reduce_current_durability()

    if brittle_component:get_current_durability() <= 0 then
      radiant.entities.unequip_item (self._entity, armor)
    end
end

function ArmorBatteryObserver:destroy()
  	if self._batterylistener then
		self._batterylistener:destroy()
		self._batterylistener = nil
	end
end

function ArmorBatteryObserver:entity()
  return self._entity
end

return ArmorBatteryObserver