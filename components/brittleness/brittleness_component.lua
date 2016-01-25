 local Brittleness = class()

-- Called when the component is first created
function Brittleness:initialize(entity)
    local json = radiant.entities.get_json(self)
    self._sv._total_durability = json.total_durability
    self._sv._current_durability = json.total_durability
end

function Brittleness:get_current_durability ()
   return self._sv._current_durability
end

function Brittleness:increase_current_durability ()
   self._sv._current_durability = self._sv._current_durability + 1
end

function Brittleness:reduce_current_durability ()
   self._sv._current_durability = self._sv._current_durability - 1
end

function Brittleness:reset_current_durability ()
   self._sv._current_durability = self._sv._total_durability
end

 return Brittleness