local ENTITY_TO_ITEM_BY_FORCE = {}

local function get_item_prototype_table()
  if prototypes and prototypes.item then
    return prototypes.item
  end

  if prototypes and prototypes.get_item_filtered then
    return prototypes.get_item_filtered({})
  end

  return nil
end

local function get_player_setting(player, name)
  return settings.get_player_settings(player)[name].value
end

local function maybe_print(player, message_key, message_param)
  if not get_player_setting(player, "craft-picker-show-messages") then
    return
  end

  if message_param ~= nil then
    player.print({message_key, message_param})
  else
    player.print({message_key})
  end
end

local function build_entity_to_item_map_for_force(force)
  local map = {}
  local item_prototypes = get_item_prototype_table()
  if not item_prototypes then
    ENTITY_TO_ITEM_BY_FORCE[force.index] = map
    return
  end

  for item_name, item_proto in pairs(item_prototypes) do
    local place_result = item_proto.place_result
    if place_result and place_result.valid then
      map[place_result.name] = item_name
    end
  end

  ENTITY_TO_ITEM_BY_FORCE[force.index] = map
end

local function get_entity_to_item_map(force)
  local map = ENTITY_TO_ITEM_BY_FORCE[force.index]
  if not map then
    build_entity_to_item_map_for_force(force)
    map = ENTITY_TO_ITEM_BY_FORCE[force.index]
  end
  return map
end

local function try_get_minable_item_name(entity)
  local minable = entity.prototype.mineable_properties
  if not minable then
    return nil
  end

  if minable.products then
    for _, product in ipairs(minable.products) do
      if product.type == "item" and product.name then
        return product.name
      end
    end
  end

  return nil
end

local function get_selected_entity_name(player)
  local selected = player.selected
  if not selected or not selected.valid then
    return nil, nil
  end

  if selected.name == "entity-ghost" then
    if not get_player_setting(player, "craft-picker-allow-ghosts") then
      return nil, "craft-picker.error.ghosts-disabled"
    end

    if selected.ghost_name and selected.ghost_name ~= "" then
      return selected.ghost_name, nil
    end

    if selected.ghost_prototype and selected.ghost_prototype.valid then
      return selected.ghost_prototype.name, nil
    end

    return nil, "craft-picker.error.ghost-unknown"
  end

  return selected.name, nil
end

local function is_hand_craftable_by_player(player, recipe)
  local character = player.character
  if not character or not character.valid then
    return nil
  end

  local categories = character.prototype.crafting_categories
  if not categories then
    return false
  end

  return categories[recipe.category] == true
end

local function find_hand_craft_recipe(force, item_name, player)
  for _, recipe in pairs(force.recipes) do
    if recipe.enabled and not recipe.hidden then
      local products = recipe.products
      if products then
        for _, product in pairs(products) do
          if product.type == "item" and product.name == item_name then
            if is_hand_craftable_by_player(player, recipe) then
              return recipe
            end
          end
        end
      end
    end
  end

  return nil
end

local function is_recipe_unlocked_for_item(force, item_name)
  for _, recipe in pairs(force.recipes) do
    if recipe.enabled and not recipe.hidden then
      for _, product in pairs(recipe.products) do
        if product.type == "item" and product.name == item_name then
          return true
        end
      end
    end
  end
  return false
end

local function get_item_name_from_entity(player, selected_entity, selected_entity_name)
  local map = get_entity_to_item_map(player.force)
  local item_name = map[selected_entity_name]
  if item_name then
    return item_name
  end

  if get_player_setting(player, "craft-picker-use-minable-fallback") then
    return try_get_minable_item_name(selected_entity)
  end

  return nil
end

local CRAFT_MODE_DEFAULT = "default"
local CRAFT_MODE_FIVE = "five"
local CRAFT_MODE_MAX = "max"

local function craft_selected_entity(event, craft_mode)
  local player = game.get_player(event.player_index)
  if not player or not player.valid then
    return
  end

  if not player.character or not player.character.valid then
    maybe_print(player, "craft-picker.error.no-character")
    return
  end

  local selected = player.selected
  if not selected or not selected.valid then
    maybe_print(player, "craft-picker.error.no-selection")
    return
  end

  if get_player_setting(player, "craft-picker-ignore-other-forces") then
    local force = selected.force
    if force and force.valid and force.index ~= player.force.index and force.name ~= "neutral" then
      maybe_print(player, "craft-picker.error.other-force")
      return
    end
  end

  local selected_entity_name, entity_error = get_selected_entity_name(player)
  if not selected_entity_name then
    maybe_print(player, entity_error or "craft-picker.error.no-selection")
    return
  end

  local item_name = get_item_name_from_entity(player, selected, selected_entity_name)
  if not item_name then
    maybe_print(player, "craft-picker.error.no-item", selected_entity_name)
    return
  end

  local recipe = find_hand_craft_recipe(player.force, item_name, player)
  if not recipe then
    if is_recipe_unlocked_for_item(player.force, item_name) then
      maybe_print(player, "craft-picker.error.not-hand-craftable", item_name)
    else
      maybe_print(player, "craft-picker.error.recipe-locked", item_name)
    end
    return
  end

  local craftable_count = player.get_craftable_count(recipe.name)

  local base_amount = get_player_setting(player, "craft-picker-craft-amount")
  local amount = base_amount

  if craft_mode == CRAFT_MODE_MAX then
    amount = craftable_count
  elseif craft_mode == CRAFT_MODE_FIVE then
    amount = 5
  end

  if amount < 1 then
    maybe_print(player, "craft-picker.error.not-enough-resources", base_amount)
    return
  end

  if craftable_count < amount then
    maybe_print(player, "craft-picker.error.not-enough-resources", amount)
    return
  end

  local crafted = player.begin_crafting({count = amount, recipe = recipe.name})
  if crafted and crafted > 0 then
    maybe_print(player, "craft-picker.ok.queued", crafted)
    return
  end

  maybe_print(player, "craft-picker.error.queue-failed")
end

script.on_event("craft-picker-craft-selected", function(event)
  craft_selected_entity(event, CRAFT_MODE_DEFAULT)
end)

script.on_event("craft-picker-craft-selected-five", function(event)
  craft_selected_entity(event, CRAFT_MODE_FIVE)
end)

script.on_event("craft-picker-craft-selected-max", function(event)
  craft_selected_entity(event, CRAFT_MODE_MAX)
end)

script.on_init(function()
  ENTITY_TO_ITEM_BY_FORCE = {}
  for _, force in pairs(game.forces) do
    build_entity_to_item_map_for_force(force)
  end
end)

script.on_configuration_changed(function()
  ENTITY_TO_ITEM_BY_FORCE = {}
  for _, force in pairs(game.forces) do
    build_entity_to_item_map_for_force(force)
  end
end)
