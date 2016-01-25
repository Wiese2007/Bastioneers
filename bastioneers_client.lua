bastioneers = {
   constants = require 'constants'
}
local player_service_trace = nil

local function check_override_ui(players, player_id)
   -- Load ui mod
   if not player_id then
      player_id = 'player_1' -- TODO(Yshan) client should know what player id it is
   end
   
   local client_player = players[player_id]
   if client_player then
      if client_player.kingdom == "bastioneers:kingdoms:bastioneers" then
         -- hot load bastioneers ui mod
         _radiant.res.load_mod("bastioneers_ui")
      end
   end
end

local function trace_player_service()
   _radiant.call('stonehearth:get_service', 'player')
      :done(function(r)
         local player_service = r.result
         check_override_ui(player_service:get_data().players)
         player_service_trace = player_service:trace('bastioneers ui change')
               :on_changed(function(o)
                     check_override_ui(player_service:get_data().players)
                  end)
         end)
end

radiant.events.listen(bastioneers, 'radiant:init', function()
      trace_player_service()
   end)

return bastioneers
