local ADDON_NAME, ns = ...

local Utils = {}
ns.Utils = Utils

-- LOCALIZED GLOBALS
local pairs, ipairs, type, select, unpack, next = pairs, ipairs, type, select, unpack, next
local tinsert, tsort, tconcat, tremove = table.insert, table.sort, table.concat, table.remove
local sfind, slower, ssub, sformat, smatch = string.find, string.lower, string.sub, string.format, string.match
local mmin, mmax, mabs, mceil, mfloor = math.min, math.max, math.abs, math.ceil, math.floor
local pcall, tostring, tonumber = pcall, tostring, tonumber
local GetTime, CreateFrame = GetTime, CreateFrame
local wipe = wipe

Utils.pairs    = pairs
Utils.ipairs   = ipairs
Utils.type     = type
Utils.select   = select
Utils.unpack   = unpack
Utils.next     = next

Utils.tinsert  = tinsert
Utils.tsort    = tsort
Utils.tconcat  = tconcat
Utils.tremove  = tremove

Utils.sfind    = sfind
Utils.slower   = slower
Utils.ssub     = ssub
Utils.sformat  = sformat
Utils.smatch   = smatch

Utils.mmin     = mmin
Utils.mmax     = mmax
Utils.mabs     = mabs
Utils.mceil    = mceil
Utils.mfloor   = mfloor

Utils.pcall    = pcall
Utils.tostring = tostring
Utils.tonumber = tonumber

Utils.GetTime     = GetTime
Utils.CreateFrame = CreateFrame
Utils.wipe        = wipe

function Utils.Print(msg)
    print(sformat("|cFF55CCFF[BoundToLearn]|r %s", msg))
end

function Utils.DebugPrint(...)
    if BoundToLearn and BoundToLearn.db and BoundToLearn.db.devMode then
        print("|cff33ff99[BTL Debug]|r", ...)
    end
end
