local PopulationFaction = class()

local rng = _radiant.math.get_default_rng()

local ALL_WORK_ORDERS = {
   'haul',
   'build',
   'mine',
   'job',
}

local THREAT_ESCAPED_TIMER = 10000

local VERSIONS = {
   ZERO = 0,
   MILITIA = 1,
}
local NUM_PARTIES = 4

function PopulationFaction:get_version()
   return VERSIONS.MILITIA
end

function PopulationFaction:initialize()
   self._log = radiant.log.create_logger('population')

   self._sv.kingdom = nil
   self._sv.player_id = nil
   self._sv.citizens = {}
   self._sv.parties = {}
   self._sv.bulletins = {}
   self._sv.militia = {}
   self._sv._global_vision = {}
   self._sv.work_orders = {}
   self._sv.is_npc = true
   self._sv.threat_level = 0
end

function PopulationFaction:create(player_id, kingdom)
   self._sv.kingdom = kingdom
   self._sv.player_id = player_id

   self:_initialize_work_orders()
end


function PopulationFaction:_create_default_parties()
   local player_id = self._sv.player_id
   for i=1, NUM_PARTIES do
      local party_name = 'party_' .. i
      if not self._sv.parties[party_name] then
         local party = stonehearth.unit_control:create_party_command({player_id = player_id}).party
         self._sv.parties[party_name] = party
         radiant.entities.set_icon(party, '/stonehearth/services/server/population/data/images/'..party_name..'_banner.png')
      end
   end
end

function PopulationFaction:restore()
   if not self._sv.is_npc then
      self:_create_default_parties()
   end
end

function PopulationFaction:activate()
   self._sensor_traces = {}
   self._data = {}

   if self._sv.kingdom then
      self._data = radiant.resources.load_json(self._sv.kingdom)
   end 

   radiant.events.listen_once(radiant, 'radiant:game_loaded', function(e)
         for id, citizen in pairs(self._sv.citizens) do
            self:_monitor_citizen(citizen)
            if self._need_init_militia then
               self:_initialize_militia(citizen)
            end
         end
      end)

   --Listen on amenity changes 
   radiant.events.listen(self, 'stonehearth:amenity_changed', self, self._on_amenity_changed) 
end

function PopulationFaction:get_datastore(reason)
   return self.__saved_variables
end

function PopulationFaction:set_kingdom(kingdom) 
   if not self._sv.kingdom then
      self._sv.kingdom = kingdom
      self._data = radiant.resources.load_json(self._sv.kingdom)
      self:_create_town_name()
      self.__saved_variables:mark_changed()
   end
end

function PopulationFaction:get_kingdom()
   return self._sv.kingdom
end

function PopulationFaction:get_banner_style()
   return self._data.camp_standard, self._data.camp_standard_ghost
end

--Create 4 default parties for this population
--Give each it's signiture banner
function PopulationFaction:create_default_parties()
   self:_create_default_parties()
end

function PopulationFaction:get_job_index() 
   local job_index = 'stonehearth:jobs:index'
   if self._data.job_index then
      job_index = self._data.job_index
   end
   return job_index
end

function PopulationFaction:get_amenity_to_strangers()
   return self._data.amenity_to_strangers or 'neutral'
end

function PopulationFaction:get_player_id()
   return self._sv.player_id
end

function PopulationFaction:get_citizen_count()
   return radiant.size(self._sv.citizens)
end

function PopulationFaction:get_militia()
   return self._sv.militia
end

function PopulationFaction:is_citizen(entity)
   if not entity or not entity:is_valid() then
      return false
   end
   return self._sv.citizens[entity:get_id()] ~= nil
end

function PopulationFaction:get_party_by_name(name)
   return self._sv.parties[name]
end

function PopulationFaction:is_npc()
   return self._sv.is_npc
end

function PopulationFaction:set_is_npc(value)
   self._sv.is_npc = value
   self.__saved_variables:mark_changed()
end

function PopulationFaction:_create_town_name()
   local composite_name = 'Defaultville'

   --If we do not yet have the town data, then return a default town name
   if self._data.town_pieces then
      local prefixes = self._data.town_pieces.optional_prefix
      local base_names = self._data.town_pieces.town_name
      local suffix = self._data.town_pieces.suffix

      --make a composite
      local target_prefix = prefixes[rng:get_int(1, #prefixes)]
      local target_base = base_names[rng:get_int(1, #base_names)]
      local target_suffix = suffix[rng:get_int(1, #suffix)]

      if target_base then
         composite_name = target_base
      end

      if target_prefix and rng:get_int(1, 100) < 40 then
         composite_name = target_prefix .. ' ' .. composite_name
      end

      if target_suffix and rng:get_int(1, 100) < 80 then
         composite_name = composite_name .. target_suffix
      end
   end

   --Set the town name for the town
   local town =  stonehearth.town:get_town(self._sv.player_id)
   town:set_town_name(composite_name)
   
   return composite_name
end

function PopulationFaction:create_new_citizen(role)
   local gender
   checks("self", "?string")

   if not role then
      role = "default"
   end

   if radiant.empty(self._sv.citizens) then
      gender = 'female'
   else 
      if rng:get_int(1, 2) == 1 then
         gender = 'male'
      else 
         gender = 'female'
      end
   end

   local role_data = self._data.roles[role]
   if not role_data then
      error(string.format('unknown role %s in population', role))
   end
   
   --If there is no gender, default to male
   if not role_data[gender] then
      gender = 'male'
   end
   local entities = role_data[gender].uri
   if not entities then
      error(string.format('role %s in population has no gender table for %s', role, gender))
   end

   local kind = entities[rng:get_int(1, #entities)]
   local citizen = radiant.entities.create_entity(kind, { owner = self._sv.player_id })
   
   local all_variants = radiant.entities.get_entity_data(citizen, 'stonehearth:customization_variants')
   if all_variants then
      self:customize_citizen(citizen, all_variants, "root")
   end

   citizen:add_component('unit_info')
               :set_player_id(self._sv.player_id)

   self:_set_citizen_initial_state(citizen, gender, role_data)

   self._sv.citizens[citizen:get_id()] = citizen

   self:_initialize_militia(citizen)

   self.__saved_variables:mark_changed()

   self:_monitor_citizen(citizen)

   return citizen
end

--When the amenity changes for this population, citizens should 
--check the threat level of everyone already in their sight sensors
function PopulationFaction:_on_amenity_changed(e)
   self._sv.threat_level = 0
   self._sv._global_vision = {}
   for _, trace in pairs(self._sensor_traces) do
      trace:push_object_state()
   end
   self.__saved_variables:mark_changed()
end


function PopulationFaction:_monitor_citizen(citizen)
   local citizen_id = citizen:get_id()

   -- listen for entity destroy bulletins so we'll know when the pass away
   radiant.events.listen_once(citizen, 'radiant:entity:pre_destroy', self, self._on_entity_destroyed)

   -- subscribe to their sensor so we can look for trouble.
   local sensor_list = citizen:get_component('sensor_list')
   if sensor_list then
      local sensor = sensor_list:get_sensor('sight')
      if sensor then
         self._sensor_traces[citizen_id] = sensor:trace_contents('monitoring threat level')
                                                      :on_added(function(visitor_id, visitor)
                                                            self:_on_seen_by(citizen_id, visitor_id, visitor)
                                                         end)
                                                      :on_removed(function(visitor_id)
                                                            self:_on_unseen_by(citizen_id, visitor_id)
                                                         end)
                                                      :push_object_state()

      end
   end   
end

function PopulationFaction:_get_threat_level(visitor)
   local visitor_id = radiant.entities.get_player_id(visitor)
   if stonehearth.player:are_player_ids_hostile(self._sv.player_id, visitor_id) then
      return radiant.entities.get_attribute(visitor, 'menace', 0)
   end 
   return 0
   
end

function PopulationFaction:_on_seen_by(spotter_id, visitor_id, visitor)
   if not visitor or not visitor:is_valid() then
      -- visitor is already destroyed
      return
   end

   local threat_level = self:_get_threat_level(visitor)
   if threat_level <= 0 then
      -- not interesting.  move along!
      return
   end

   local entry = self._sv._global_vision[visitor_id]
   if not entry then
      entry = {
         seen_by = { [spotter_id] = true },
         threat_level = threat_level,
         entity = visitor,
      }
      self._sv._global_vision[visitor_id] = entry

      self:_update_threat_level()

      radiant.events.trigger_async(self, 'stonehearth:population:new_threat', {
            entity_id = visitor_id,
            entity = visitor,
         });     
   end 
   entry.seen_by[spotter_id] = true
   self.__saved_variables:mark_changed()
end

function PopulationFaction:_on_unseen_by(spotter_id, visitor_id)
   local entry = self._sv._global_vision[visitor_id]
   if entry then
      entry.seen_by[spotter_id] = nil
      self._log:debug("visitor %d still seen by %d citizens", visitor_id, radiant.size(entry.seen_by))
      if radiant.empty(entry.seen_by) then
         self._sv._global_vision[visitor_id] = nil

         --If the threat goes down because you've just unseen someone 
         --as opposed to b/c they died, wait to update the threat level until 
         --a few seconds (10?) have gone by. Makes sense--how do you know you've escaped--
         --and also so that we don't switch back to non-combat modes when there's a high
         --chance of getting back into combat. 
         radiant.set_realtime_timer("waiting for unseen threat update", THREAT_ESCAPED_TIMER, function()
               self:_update_threat_level()
            end)         
      end
      self.__saved_variables:mark_changed()
   end
end

--Will show a simple notification that zooms to a citizen when clicked. 
--will expire if the citizen isn't around anymore
function PopulationFaction:show_notification_for_citizen(citizen, title)
   local citizen_id = citizen:get_id()
   if not self._sv.bulletins[citizen_id] then
      self._sv.bulletins[citizen_id] = {}
   elseif self._sv.bulletins[citizen_id][title] then
      --If a bulletin already exists for this citizen with this title, remove it to replace with the new one
      local bulletin_id = self._sv.bulletins[citizen_id][title]:get_id()
      stonehearth.bulletin_board:remove_bulletin(bulletin_id)
   end
   local town_name = stonehearth.town:get_town(self._sv.player_id):get_town_name()

   self._sv.bulletins[citizen_id][title] = stonehearth.bulletin_board:post_bulletin(self._sv.player_id)
            :set_callback_instance(self)
            :set_data({
               title = title,
               message = '',
               zoom_to_entity = citizen,
            })
            :add_i18n_data('citizen_custom_name', radiant.entities.get_custom_name(citizen))
            :add_i18n_data('citizen_display_name', radiant.entities.get_display_name(citizen))
            :add_i18n_data('town_name', town_name)

   self.__saved_variables:mark_changed()
end

function PopulationFaction:_on_entity_destroyed(evt)
   local entity_id = evt.entity_id

   -- update the score
   if self._sv.citizens[entity_id] then
      self:_on_citizen_destroyed(entity_id)
   end
   if self._sv._global_vision[entity_id] then
      self:_on_global_vision_entity_destroyed(evt.entity_id)
   end
end

function PopulationFaction:_on_citizen_destroyed(entity_id)
   self._sv.citizens[entity_id] = nil

   -- remove associated bulletins
   local bulletins = self._sv.bulletins[entity_id]
   if bulletins then
      self._sv.bulletins[entity_id] = nil
      for title, bulletin in pairs(bulletins) do
         local bulletin_id = bulletin:get_id()
         stonehearth.bulletin_board:remove_bulletin(bulletin_id)
      end
   end   

   -- nuke sensors
   local sensor_trace = self._sensor_traces[entity_id]
   if sensor_trace then
      self._sensor_traces[entity_id] = nil
      sensor_trace:destroy()
   end

   -- global vision
   for visitor_id, _ in pairs(self._sv._global_vision) do
      self:_on_unseen_by(entity_id, visitor_id)
   end

   self.__saved_variables:mark_changed()
   return radiant.events.UNLISTEN
end

function PopulationFaction:_on_global_vision_entity_destroyed(entity_id)
   self._sv._global_vision[entity_id] = nil
   self:_update_threat_level()
   self.__saved_variables:mark_changed()
end

function PopulationFaction:_update_threat_level()
   local threat_level = 0
   for _, entry in pairs(self._sv._global_vision) do
      threat_level = threat_level + entry.threat_level
   end
   self._sv.threat_level = threat_level
   self.__saved_variables:mark_changed()
end


function PopulationFaction:customize_citizen(entity, all_variants, this_variant)   
   local variant = all_variants[this_variant]

   if not variant then
      return
   end
   
   -- load any models at this node in the customization tree
   if variant.models then
      local variant_name = 'default'
      local random_model = variant.models[rng:get_int(1, #variant.models)]
      local model_variants_component = entity:add_component('model_variants')
      model_variants_component:add_variant(variant_name):add_model(random_model)
   end

   -- for each set of child variants, pick a random option
   if variant.variants then
      for _, variant_set in ipairs(variant.variants) do
         local random_option = variant_set[rng:get_int(1, #variant_set)]
         self:customize_citizen(entity, all_variants, random_option)
      end
   end
end

function PopulationFaction:get_citizens()
   return self._sv.citizens
end

function PopulationFaction:_set_citizen_initial_state(citizen, gender, role_data)
   -- name
   local name = self:generate_random_name(gender, role_data)
   if name then
      radiant.entities.set_custom_name(citizen, name)
   end
   
   -- personality
   --TODO: parametrize these by role too?
   local personality = stonehearth.personality:get_new_personality()
   local personality_component = citizen:add_component('stonehearth:personality')
   personality_component:set_personality(personality)

   --For the teacher field, assign the one appropriate for this kingdom
   personality_component:add_substitution_by_parameter('teacher', self._sv.kingdom, 'stonehearth')
end

function PopulationFaction:create_entity(uri)
   return radiant.entities.create_entity(uri, { owner = self._sv.player_id })
end

function PopulationFaction:get_home_location()
   return self._town_location
end

function PopulationFaction:set_home_location(location)
   self._town_location = location
end

function PopulationFaction:generate_random_name(gender, role_data)
   if role_data[gender].given_names then
      local first_names = ""

      first_names = role_data[gender].given_names

      local first = first_names[rng:get_int(1, #first_names)]
      local surname = ""
      local lineage = ""
      if role_data.surnames then
         surname = role_data.surnames[rng:get_int(1, #role_data.surnames)]
         if role_data.lineages then
            lineage = ' ' .. role_data.lineages[rng:get_int(1, #role_data.lineages)]
            return first .. 'i' .. surname .. lineage
         end
      end
      return first .. ' ' .. surname
   else
      return nil
   end
end

--- Given an entity, iterate through the array of people in this town and find the
--  person closest to the entity.
--  Returns the closest person and the entity's distance to that person. 
function PopulationFaction:find_closest_townsperson_to(entity)
   local shortest_distance = nil
   local closest_person = nil
   for id, citizen in pairs(self._sv.citizens) do
      if citizen:is_valid() and entity:get_id() ~= id then
         local distance = radiant.entities.distance_between(entity, citizen)
         if not shortest_distance or distance < shortest_distance then
            shortest_distance = distance
            closest_person = citizen
         end 
      end
   end
   return closest_person, shortest_distance
end

--If we have kingdom data for this job, use that, instead of the default
function PopulationFaction:get_job_description(job_uri)
   if self._data.jobs and self._data.jobs[job_uri] then
      return self._data.jobs[job_uri]
   else
      return job_uri
   end
end

function PopulationFaction:_initialize_work_orders()
   self._sv.work_orders = {}

   for _, work_order in pairs(ALL_WORK_ORDERS) do
      self._sv.work_orders[work_order] = {
         citizens = {},
         locked_for_citizens = {},
         is_suspended = false
      }
   end

   self.__saved_variables:mark_changed()
end

function PopulationFaction:get_work_order_enabled(citizen, work_order)
   local id = citizen:get_id()
   local entry = self._sv.work_orders[work_order]
   local enabled = entry.citizens[id] ~= nil
   return enabled
end

-- the entry point to be used by the town to notify us that someone has joined
-- a task group associated with a work order, so we should "check the box"
function PopulationFaction:notify_citizen_work_order_changed(citizen_id, work_order, value)
   local entry = self._sv.work_orders[work_order]
   if not entry then
      return
   end
   if value == false then
      value = nil
   end
   entry.citizens[citizen_id] = value
   self.__saved_variables:mark_changed()
end

-- the entry point in the ui when someone clicks a check box to opt into or out of a job
-- we need to update our work_order map and notify the town
function PopulationFaction:change_work_order_command(session, response, work_order, citizen_id, checked)
   local entry = self._sv.work_orders[work_order]
   if not entry then
      response:reject(string.format('unknown work order %s', work_order))
      return
   end


   if checked == false then
      checked = nil
   end
   if entry.citizens[citizen_id] ~= checked then
      entry.citizens[citizen_id] = checked
      self.__saved_variables:mark_changed()

      local citizen = self._sv.citizens[citizen_id]
      if not citizen then
         return
      end

      local town = stonehearth.town:get_town(self._sv.player_id)
      if town then
         town:update_task_groups_for_work_order(work_order, citizen, checked)
      end
   end

   return true
end

-- Called when user wants to toggle whether a work order is suspended
function PopulationFaction:set_work_order_suspend_command(session, response, work_order, is_suspended)
   local entry = self._sv.work_orders[work_order]
   if not entry then
      response:reject(string.format('unknown work order %s', work_order))
      return
   end

   if entry.is_suspended ~= is_suspended then
      entry.is_suspended = is_suspended

      local town = stonehearth.town:get_town(self._sv.player_id)
      if town then
         local enabled = not is_suspended
         town:enable_task_groups_for_work_order(work_order, enabled)
      end
      self.__saved_variables:mark_changed()
   end

   return true
end

function PopulationFaction:set_work_order_locked(citizen, work_order, locked)
   local id = citizen:get_id()
   local entry = self._sv.work_orders[work_order]
   assert(entry)
   local value = locked and citizen or nil
   entry.locked_for_citizens[id] = value
   self.__saved_variables:mark_changed()
end

function PopulationFaction:get_work_order_categories()
   return ALL_WORK_ORDERS
end

-- Adds citizen to militia or nonmilitia groups depending whether or not the class opts out of militia
-- Called when initializing an old save or adding a new citizen to the population
function PopulationFaction:_initialize_militia(citizen)
   if not self._sv.is_npc then
      local add_to_militia = self:should_add_to_militia(citizen)
      self:update_militia_command({}, {}, citizen:get_id(), add_to_militia)
   end
end

function PopulationFaction:should_add_to_militia(citizen)
   local job = citizen:add_component('stonehearth:job')
   -- add citizens to militia by default unless class opts out (ex. combat classes, crafters)
   if job and job.is_militia_opt_out then
      return not job:is_militia_opt_out()
   else
      return true
   end
end

function PopulationFaction:update_militia_command(session, response, entity_id, checked)
   local town = stonehearth.town:get_town(self._sv.player_id)
   local entity = radiant.entities.get_entity(entity_id)
   if entity and entity:is_valid() then
      town:update_alert_mode_task_groups(entity, checked)
      if checked then
         self._sv.militia[entity_id] = entity
      else
         self._sv.militia[entity_id] = nil
      end
      self.__saved_variables:mark_changed()
   end
end

function PopulationFaction:fixup_post_load(old_save_data)
   if old_save_data.version == VERSIONS.ZERO then
      self._need_init_militia = true
   end
end

return PopulationFaction
