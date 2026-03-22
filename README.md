# SmartCraft

**WoW TBC Classic 2.5.5 addon** — Inventory-aware profession leveling optimizer.

## What It Does
1. Scans your bags for crafting materials
2. Reserves mats for highest-skill recipes first (top-down)
3. Suggests what you can safely craft with leftovers
4. Shows you what to buy to unlock more skill-ups

## Usage
- Open your profession window (Blacksmithing, Leatherworking, etc.)
- Type `/sc` or `/smartcraft`
- SmartCraft panel opens alongside your tradeskill window

## Files
```
SmartCraft/
├── SmartCraft.toc        — Addon manifest (Interface: 20502)
├── SmartCraft.lua        — Entry point, event handling
├── Core/
│   ├── Constants.lua     — Shared constants & color definitions
│   ├── Inventory.lua     — Bag scanner (GetContainerItemInfo)
│   ├── Recipes.lua       — TradeSkill reader (GetTradeSkillInfo etc.)
│   ├── Reservation.lua   — Top-down reservation + suggestion algorithm
│   └── Suggestion.lua    — Display formatting
└── UI/
    └── MainFrame.lua     — Native WoW frame UI
```

## Algorithm
**Phase 1 — RESERVE:** Scan recipes high→low skill. Reserve mats for orange/yellow recipes first.  
**Phase 2 — SUGGEST:** Use leftover pool to find craftable recipes (low→high skill).  
**Phase 3 — GAPS:** For any unreserved orange/yellow recipe, report what's missing.

## TBC Classic API Used
- `GetTradeSkillInfo(i)` — recipe name, difficulty color
- `GetTradeSkillNumReagents(i)` — reagent count
- `GetTradeSkillReagentInfo(i, r)` — reagent name/count
- `GetTradeSkillReagentItemLink(i, r)` — reagent item link (for ID)
- `GetContainerNumSlots(bag)` — bag size
- `GetContainerItemInfo(bag, slot)` — item link + stack count
- `GetTradeSkillLine()` — current skill / max skill

## Install
Drop the `SmartCraft/` folder into:
`World of Warcraft/_classic_era_/Interface/AddOns/`

Enable in the AddOns list on character select.
