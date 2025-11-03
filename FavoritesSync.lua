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
		print("[Auction Favorites]: |cff00ff00●|r " .. getItemLink(itemKey))
	else
		print("[Auction Favorites]: |cffff0000●|r " .. getItemLink(itemKey))
	end

	return true
end

-- Saves item favorite status to both account and character databases
local function setFavorite(itemKey, isFavorited)
	local key = serializeValues(itemKey)

	gdb.favorites[key] = isFavorited and itemKey or nil
	cdb.favorites[key] = isFavorited and itemKey or nil
end

-- Hooks into auction house API to intercept favorite changes
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

		-- Register search result events for first-time sync on this character
		if not cdb.synced then
			eventFrame:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
			eventFrame:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_ADDED")
			eventFrame:RegisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED")
			eventFrame:RegisterEvent("COMMODITY_SEARCH_RESULTS_ADDED")
			eventFrame:RegisterEvent("ITEM_SEARCH_RESULTS_UPDATED")
			eventFrame:RegisterEvent("ITEM_SEARCH_RESULTS_ADDED")
		end
	end

	-- Sync favorites when auction house opens
	if event == "AUCTION_HOUSE_SHOW" then
		local needRefresh = false

		if cdb.synced then
			for _, favorites in ipairs { gdb.favorites, cdb.favorites } do
				for _, itemKey in pairs(favorites) do
					needRefresh = sync(itemKey) or needRefresh
				end
			end
		else
			for _, itemKey in pairs(gdb.favorites) do
				C_AuctionHouse.SetFavoriteItem(itemKey, true)
				print("[Auction Favorites]: |cff00ff00●|r " .. getItemLink(itemKey))
				needRefresh = true
			end
		end

		if needRefresh then
			C_AuctionHouse.SearchForFavorites({})
		end
	end

	-- Mark character as synced and cleanup when auction house closes
	if event == "AUCTION_HOUSE_CLOSED" then
		cdb.synced = true
		eventFrame:UnregisterAllEvents()
	end

	-- Processes search results and saves favorite status for discovered items
	local function processItemKey(itemKey)
		setFavorite(itemKey, C_AuctionHouse.IsFavoriteItem(itemKey))
	end

	if event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" then
		for _, result in ipairs(C_AuctionHouse.GetBrowseResults()) do
			processItemKey(result.itemKey)
		end
	end

	if event == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" then
		for _, result in ipairs(...) do
			processItemKey(result.itemKey)
		end
	end

	if event == "COMMODITY_SEARCH_RESULTS_UPDATED" or event == "COMMODITY_SEARCH_RESULTS_ADDED" then
		processItemKey(C_AuctionHouse.MakeItemKey(...))
	end

	if event == "ITEM_SEARCH_RESULTS_UPDATED" or event == "ITEM_SEARCH_RESULTS_ADDED" then
		processItemKey(...)
	end
end)
