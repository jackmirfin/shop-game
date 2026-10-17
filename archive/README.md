# Safety Archive — ShopGame Project Reset

Created: Before Step 3 stripping (controlled reset).

This archive contains copies of ALL gameplay systems, scripts, scenes, and resources that will be disconnected during the project reset. Every file here is a COPY — no original files have been moved or deleted.

## Archive Structure

| Folder | Contents |
|---|---|
| `player/` | Current Player scene + script (movement, attack, health, bag, inventory, interaction) |
| `enemies/slime/` | Slime scene, script, all 16-bit animation atlases + metadata |
| `enemies/skeleton/` | Skeleton scene, script, all animation atlases |
| `enemies/skeleton_bag/` | Skeleton bag scene, script, bag anim assets, player_bag.tscn |
| `enemies/spider/` | Spider scene, enemy_base.gd, spider animation atlases |
| `npcs/` | NPC base, shopkeeper, wandering NPC — scenes + scripts |
| `game_wrapper/` | game.tscn, main.gd, main_menu.tscn, main_menu.gd |
| `village/` | AI-generated level_2_village.tscn + village_decor.gd |
| `shop_systems/` | All 3 shop system scripts, shop UI logic, locked door, counter view, shop data, general store resource |
| `tea_world/` | WorldStateManager autoload, tea world node/door/husk, shader, HUD scenes |
| `dialogue/` | DialogueManager autoload, dialogue display, dialogue data class, all 9 dialogue .tres files |
| `combat_health/` | Health component, health bar scene+script, pickup script, detection area |
| `inventory/` | Inventory component, item data class |
| `ui/` | Letter UI, animation player, main menu copies |
| `old_levels/` | level_0.tscn (old forest), level_2.tscn (old cave), base_level.tscn (template), level_2_village.tscn |
| `autoloads/` | global.gd, game_state.gd, event_bus.gd |
| `resources/` | All item .tres files, dialogue .tres files, shop .tres files |
| `assets_generated/` | Generated NPC sprites, shop assets, player/bag anims, husk entity, letter parchment |

## Recovery Notes

- To recover the old Player: copy `archive/player/` back to `scenes/` and `scripts/`
- To recover slime combat: copy `archive/enemies/slime/` scenes back, plus `archive/combat_health/`
- To recover shop systems: copy `archive/shop_systems/` scripts back
- To recover tea world: copy `archive/tea_world/` back and re-register WorldStateManager as autoload

## What Was NOT Archived

The canonical map scenes are intentionally NOT in this archive:
- `scenes/Levels/level_1.tscn` (forest) — PRESERVED IN PLACE
- `scenes/Navaria.tscn` (village) — PRESERVED IN PLACE
- `scenes/Levels/shop_interior.tscn` — PRESERVED IN PLACE
- `scenes/Levels/shop_basement.tscn` — PRESERVED IN PLACE
- `scenes/Levels/dungeon_floor_1.tscn` — PRESERVED IN PLACE
- `scenes/player.tscn` — PRESERVED IN PLACE (will be cleaned in Step 4)
- `scenes/Levels/village.tscn` — PRESERVED IN PLACE (will be cleaned in Step 3)

Map artwork assets (tilemaps, village sprites, etc.) in `assets/generated/` were also NOT archived because they remain in active use.
