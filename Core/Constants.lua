-- Constants.lua
-- Shared constants for SmartCraft v0.3.0

SmartCraft = SmartCraft or {}
SmartCraft.Constants = {}

local C = SmartCraft.Constants

-- Difficulty display colors
C.DIFF_COLOR = {
    OPTIMAL = { r=1.00, g=0.50, b=0.25, label="Orange" },
    MEDIUM  = { r=1.00, g=1.00, b=0.00, label="Yellow" },
    EASY    = { r=0.25, g=0.75, b=0.25, label="Green"  },
    TRIVIAL = { r=0.55, g=0.55, b=0.55, label="Gray"   },
}

-- Tabs
C.TABS = { "crafts", "shopping", "planner" }

-- UI dimensions
C.UI = {
    W        = 460,
    H        = 520,
    TAB_H    = 24,
    HEADER_H = 46,
    FOOTER_H = 30,
    LINE_H   = 15,
    SCROLL_R = 26,
}
