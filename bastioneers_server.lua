-- Created by the Legend that is RepeatPan, because after 5 hours I wanted stove my own head in :/ Pun intended!!

bastioneers = {}

function bastioneers:_on_init()

local old_fnc = stonehearth.game_master.start

	stonehearth.game_master.start = function(self, ...)

local ret = { old_fnc(self, ...) }

	self:_start_campaign 'helper'
   return unpack(ret)

	end

end
radiant.events.listen(radiant, 'radiant:required_loaded', bastioneers, bastioneers._on_init)

return bastioneers
