-- Sync auction house favorites across all characters on the account

local gdb, cdb

local itemKeyFields = { "itemID", "itemLevel", "itemSuffix", "battlePetSpeciesID", "itemContext" }

local itemKeyLookup = {}

for _, field in ipairs(itemKeyFields) do
	itemKeyLookup[field] = true
end

local searchEvents = {
	"AUCTION_HOUSE_BROWSE_RESULTS_UPDATED",
	"AUCTION_HOUSE_BROWSE_RESULTS_ADDED",
	"COMMODITY_SEARCH_RESULTS_UPDATED",
	"COMMODITY_SEARCH_RESULTS_ADDED",
	"ITEM_SEARCH_RESULTS_UPDATED",
	"ITEM_SEARCH_RESULTS_ADDED",
}

local sessionSnapshot, sessionNotified
local suppressedKeys = {}

local function pushSuppressed(key)
	suppressedKeys[key] = (suppressedKeys[key] or 0) + 1
end

local function popSuppressed(key)
	local count = suppressedKeys[key]

	if not count then
		return false
	end

	if count <= 1 then
		suppressedKeys[key] = nil
	else
		suppressedKeys[key] = count - 1
	end

	return true
end

local function copyItemKey(itemKey)
	local copy = {}

	for _, field in ipairs(itemKeyFields) do
		local value = itemKey[field]

		if value ~= nil then
			copy[field] = value
		end
	end

	for key, value in pairs(itemKey) do
		if not itemKeyLookup[key] and type(value) ~= "table" then
			copy[key] = value
		end
	end

	return copy
end

-- Generate unique hash from item key properties for storage and comparison

local function serializeValues(itemKey)
	local values = {}

	for index, field in ipairs(itemKeyFields) do
		local value = itemKey[field]
		values[index] = value ~= nil and tostring(value) or ""
	end

	local extras = {}

	for key in pairs(itemKey) do
		if not itemKeyLookup[key] then
			extras[#extras + 1] = key
		end
	end

	if #extras > 0 then
		table.sort(extras)

		for _, key in ipairs(extras) do
			values[#values + 1] = itemKey[key] ~= nil and tostring(itemKey[key]) or ""
		end
	end

	return table.concat(values, "-")
end

-- Fetch item link for chat messages with tooltips

local function getItemLink(itemKey)
	local itemID = itemKey.itemID

	if itemID then
		local itemName, itemLink = C_Item.GetItemInfo(itemID)

		if itemLink then
			return itemLink
		end

		if itemName then
			return itemName
		end
	end

	return "Unknown Item"
end

local function notifyFavoriteChange(itemKey, isFavorited, key)
	local prefix = isFavorited and "|cff00ff00[+]|r " or "|cffff0000[-]|r "
	local message = "[Auction Favorites]: " .. prefix .. getItemLink(itemKey)

	if DEFAULT_CHAT_FRAME then
		DEFAULT_CHAT_FRAME:AddMessage(message)
	else
		print(message)
	end

	if sessionNotified and key then
		sessionNotified[key] = true
	end
end

-- Align item favorite status between account and character databases

local function sync(itemKey)
	local key = serializeValues(itemKey)
	local accountHas = gdb.favorites[key] ~= nil
	local characterHas = cdb.favorites[key] ~= nil

	if accountHas == characterHas then
		return false
	end

	pushSuppressed(key)
	C_AuctionHouse.SetFavoriteItem(itemKey, accountHas)
	notifyFavoriteChange(itemKey, accountHas, key)

	return true
end

-- Store item favorite status to both account and character databases

local function setFavorite(itemKey, isFavorited)
	if not gdb or not cdb then
		return
	end

	local key = serializeValues(itemKey)
	local wasFavorited = gdb.favorites[key] ~= nil
	local suppressed = popSuppressed(key)

	if isFavorited then
		local trimmed = copyItemKey(itemKey)
		gdb.favorites[key] = trimmed
		cdb.favorites[key] = trimmed
	else
		gdb.favorites[key] = nil
		cdb.favorites[key] = nil
	end

	if suppressed then
		return
	end

	if wasFavorited ~= isFavorited then
		notifyFavoriteChange(itemKey, isFavorited, key)
	end
end

local function processItemKey(itemKey)
	if not itemKey then
		return
	end

	setFavorite(itemKey, C_AuctionHouse.IsFavoriteItem(itemKey))
end

local function registerSearchEvents(frame)
	for _, eventName in ipairs(searchEvents) do
		frame:RegisterEvent(eventName)
	end
end

local function unregisterSearchEvents(frame)
	for _, eventName in ipairs(searchEvents) do
		frame:UnregisterEvent(eventName)
	end
end

-- Hook auction house API to intercept favorite changes

hooksecurefunc(C_AuctionHouse, "SetFavoriteItem", setFavorite)

local eventFrame = CreateFrame("Frame")

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("AUCTION_HOUSE_SHOW")
eventFrame:RegisterEvent("AUCTION_HOUSE_CLOSED")

eventFrame:SetScript("OnEvent", function(_, event, ...)
	if event == "ADDON_LOADED" and ... == "AuctionAndy" then
		eventFrame:UnregisterEvent("ADDON_LOADED")

		AuctionFavoritesDB = AuctionFavoritesDB or {}
		gdb = AuctionFavoritesDB
		gdb.favorites = gdb.favorites or {}

		AuctionFavoritesCharDB = AuctionFavoritesCharDB or {}
		cdb = AuctionFavoritesCharDB
		cdb.favorites = cdb.favorites or {}

		if not cdb.synced then
			registerSearchEvents(eventFrame)
		end

		return
	end

	if event == "AUCTION_HOUSE_SHOW" then
		sessionSnapshot = {}
		sessionNotified = {}

		for key, itemKey in pairs(gdb.favorites) do
			sessionSnapshot[key] = itemKey
		end

		local needRefresh = false
		local processed = {}

		if cdb.synced then
			for _, favorites in ipairs { gdb.favorites, cdb.favorites } do
				for key, itemKey in pairs(favorites) do
					if not processed[key] then
						processed[key] = true
						needRefresh = sync(itemKey) or needRefresh
					end
				end
			end
		else
			for key, itemKey in pairs(gdb.favorites) do
				processed[key] = true
				pushSuppressed(key)
				C_AuctionHouse.SetFavoriteItem(itemKey, true)
				notifyFavoriteChange(itemKey, true, key)
				needRefresh = true
			end
		end

		if needRefresh then
			C_AuctionHouse.SearchForFavorites({})
		end

		return
	end

	if event == "AUCTION_HOUSE_CLOSED" then
		if cdb then
			cdb.synced = true
		end

		if sessionSnapshot then
			for key, itemKey in pairs(sessionSnapshot) do
				if not gdb.favorites[key] and not (sessionNotified and sessionNotified[key]) then
					notifyFavoriteChange(itemKey, false, key)
				end
			end

			for key, itemKey in pairs(gdb.favorites) do
				if not sessionSnapshot[key] and not (sessionNotified and sessionNotified[key]) then
					notifyFavoriteChange(itemKey, true, key)
				end
			end
		end

		sessionSnapshot = nil
		sessionNotified = nil

		unregisterSearchEvents(eventFrame)

		return
	end

	if event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" then
		for _, result in ipairs(C_AuctionHouse.GetBrowseResults()) do
			processItemKey(result.itemKey)
		end

		return
	end

	if event == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" then
		for _, result in ipairs(...) do
			processItemKey(result.itemKey)
		end

		return
	end

	if event == "COMMODITY_SEARCH_RESULTS_UPDATED" or event == "COMMODITY_SEARCH_RESULTS_ADDED" then
		processItemKey(C_AuctionHouse.MakeItemKey(...))

		return
	end

	if event == "ITEM_SEARCH_RESULTS_UPDATED" or event == "ITEM_SEARCH_RESULTS_ADDED" then
		processItemKey(...)

		return
	end
end)
-- Syncs auction house favorites across all characters on the account

local gdb, cdb

-- Creates a unique hash from item key properties for storage and comparison
local function serializeValues(itemKey)
	local keys, values = {}, {}
	for k in pairs(itemKey) do table.insert(keys, k) end
	table.sort(keys)
	for _, k in ipairs(keys) do table.insert(values, itemKey[k]) end
	return table.concat(values, "-")
end

-- Gets item link from item key for chat messages with tooltips
local function getItemLink(itemKey)
	local itemID = itemKey.itemID
	if itemID then
		local itemName, itemLink = C_Item.GetItemInfo(itemID)
		if itemLink then
			return itemLink
		end
		if itemName then
			return itemName
		end
	end
	return "Unknown Item"
end

-- Syncs item favorite status between account and character databases
local function sync(itemKey)
	local key = serializeValues(itemKey)

	if not gdb.favorites[key] == not cdb.favorites[key] then
		return false
	end

	local shouldBeFavorited = gdb.favorites[key] ~= nil
	C_AuctionHouse.SetFavoriteItem(itemKey, shouldBeFavorited)

	if shouldBeFavorited then
		print("[Auction Favorites]: |cff00ff00[+]|r " .. getItemLink(itemKey))
	else
		print("[Auction Favorites]: |cffff0000[-]|r " .. getItemLink(itemKey))
	end

	return true
end
-- Sync auction house favorites across all characters on the account

local gdb, cdb

local itemKeyFields = { "itemID", "itemLevel", "itemSuffix", "battlePetSpeciesID", "itemContext" }

local itemKeyLookup = {}

for _, field in ipairs(itemKeyFields) do
	itemKeyLookup[field] = true
end

local searchEvents = {
	"AUCTION_HOUSE_BROWSE_RESULTS_UPDATED",
	"AUCTION_HOUSE_BROWSE_RESULTS_ADDED",
	"COMMODITY_SEARCH_RESULTS_UPDATED",
	"COMMODITY_SEARCH_RESULTS_ADDED",
	"ITEM_SEARCH_RESULTS_UPDATED",
	"ITEM_SEARCH_RESULTS_ADDED",
}

local function copyItemKey(itemKey)
	local copy = {}

	for _, field in ipairs(itemKeyFields) do
		local value = itemKey[field]
		if value ~= nil then
			copy[field] = value
		end
	end

	for key, value in pairs(itemKey) do
		if not itemKeyLookup[key] and type(value) ~= "table" then
			copy[key] = value
		end
	end

	return copy
end

-- Generate unique hash from item key properties for storage and comparison

local function serializeValues(itemKey)
	local values = {}

	for index, field in ipairs(itemKeyFields) do
		local value = itemKey[field]
		values[index] = value ~= nil and tostring(value) or ""
	end

	local extras = {}

	for key in pairs(itemKey) do
		if not itemKeyLookup[key] then
			extras[#extras + 1] = key
		end
	end

	if #extras > 0 then
		table.sort(extras)
		for _, key in ipairs(extras) do
			values[#values + 1] = itemKey[key] ~= nil and tostring(itemKey[key]) or ""
		end
	end

	return table.concat(values, "-")
end

-- Fetch item link for chat messages with tooltips

local function getItemLink(itemKey)
	local itemID = itemKey.itemID

	if itemID then
		local itemName, itemLink = C_Item.GetItemInfo(itemID)

		if itemLink then
			return itemLink
		end

		if itemName then
			return itemName
		end
	end

	return "Unknown Item"
end

local function notifyFavoriteChange(itemKey, isFavorited)
	local text = isFavorited and "|cff00ff00[+]|r " or "|cffff0000[-]|r "
	local message = "[Auction Favorites]: " .. text .. getItemLink(itemKey)

	if DEFAULT_CHAT_FRAME then
		DEFAULT_CHAT_FRAME:AddMessage(message)
	else
		print(message)
	end
end

-- Align item favorite status between account and character databases

local function sync(itemKey)
	local key = serializeValues(itemKey)
	local accountHas = gdb.favorites[key] ~= nil
	local characterHas = cdb.favorites[key] ~= nil

	if accountHas == characterHas then
		return false
	end

	C_AuctionHouse.SetFavoriteItem(itemKey, accountHas)
	notifyFavoriteChange(itemKey, accountHas)

	return true
end

-- Store item favorite status to both account and character databases

local function setFavorite(itemKey, isFavorited)
	if not gdb or not cdb then
		return
	end

	local key = serializeValues(itemKey)

	if isFavorited then
		local trimmed = copyItemKey(itemKey)
		gdb.favorites[key] = trimmed
		cdb.favorites[key] = trimmed
	else
		gdb.favorites[key] = nil
		cdb.favorites[key] = nil
	end
end

local function processItemKey(itemKey)
	if not itemKey then
		return
	end

	setFavorite(itemKey, C_AuctionHouse.IsFavoriteItem(itemKey))
end

local function registerSearchEvents(frame)
	for _, eventName in ipairs(searchEvents) do
		frame:RegisterEvent(eventName)
	end
end

local function unregisterSearchEvents(frame)
	for _, eventName in ipairs(searchEvents) do
		frame:UnregisterEvent(eventName)
	end
end

-- Hook auction house API to intercept favorite changes

hooksecurefunc(C_AuctionHouse, "SetFavoriteItem", setFavorite)

local eventFrame = CreateFrame("Frame")

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("AUCTION_HOUSE_SHOW")
eventFrame:RegisterEvent("AUCTION_HOUSE_CLOSED")

eventFrame:SetScript("OnEvent", function(_, event, ...)
	-- Initialize databases when addon loads

	if event == "ADDON_LOADED" and ... == "AuctionAndy" then
		eventFrame:UnregisterEvent("ADDON_LOADED")

		AuctionFavoritesDB = AuctionFavoritesDB or {}
		gdb = AuctionFavoritesDB
		gdb.favorites = gdb.favorites or {}

		AuctionFavoritesCharDB = AuctionFavoritesCharDB or {}
		cdb = AuctionFavoritesCharDB
		cdb.favorites = cdb.favorites or {}

		if not cdb.synced then
			registerSearchEvents(eventFrame)
		end

		return
	end

	-- Sync favorites when auction house opens

	if event == "AUCTION_HOUSE_SHOW" then
		local needRefresh = false
		local processed = {}

		if cdb.synced then
			for _, favorites in ipairs { gdb.favorites, cdb.favorites } do
				for key, itemKey in pairs(favorites) do
					if not processed[key] then
						processed[key] = true
						needRefresh = sync(itemKey) or needRefresh
					end
				end
			end
		else
			for key, itemKey in pairs(gdb.favorites) do
				processed[key] = true
				C_AuctionHouse.SetFavoriteItem(itemKey, true)
				notifyFavoriteChange(itemKey, true)
				needRefresh = true
			end
		end

		if needRefresh then
			C_AuctionHouse.SearchForFavorites({})
		end

		return
	end

	-- Mark character as synced and cleanup when auction house closes

	if event == "AUCTION_HOUSE_CLOSED" then
		if cdb then
			cdb.synced = true
		end

		unregisterSearchEvents(eventFrame)

		return
	end

	-- Process browse results when updates arrive

	if event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" then
		for _, result in ipairs(C_AuctionHouse.GetBrowseResults()) do
			processItemKey(result.itemKey)
		end

		return
	end

	if event == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" then
		for _, result in ipairs(...) do
			processItemKey(result.itemKey)
		end

		return
	end

	if event == "COMMODITY_SEARCH_RESULTS_UPDATED" or event == "COMMODITY_SEARCH_RESULTS_ADDED" then
		processItemKey(C_AuctionHouse.MakeItemKey(...))

		return
	end

	if event == "ITEM_SEARCH_RESULTS_UPDATED" or event == "ITEM_SEARCH_RESULTS_ADDED" then
		processItemKey(...)

		return
	end
end)
