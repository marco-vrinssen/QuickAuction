-- Syncs auction house favorites across all characters on the account

local accountFavorites
local characterFavorites

-- Creates a unique hash from item key properties for storage and comparison
local function createItemKeyHash(itemKey)
	local keys, values = {}, {}
	for k in pairs(itemKey) do table.insert(keys, k) end
	table.sort(keys)
	for _, k in ipairs(keys) do table.insert(values, itemKey[k]) end
	return table.concat(values, "-")
end

-- Syncs item favorite status between account and character databases
local function syncFavorite(itemKey)
	local itemKeyHash = createItemKeyHash(itemKey)

	if not accountFavorites.favorites[itemKeyHash] == not characterFavorites.favorites[itemKeyHash] then
		return false
	end

	C_AuctionHouse.SetFavoriteItem(itemKey, accountFavorites.favorites[itemKeyHash] ~= nil)
	return true
end

-- Saves item favorite status to both account and character databases
local function saveFavorite(itemKey, isFavorited)
	local itemKeyHash = createItemKeyHash(itemKey)

	accountFavorites.favorites[itemKeyHash] = isFavorited and itemKey or nil
	characterFavorites.favorites[itemKeyHash] = isFavorited and itemKey or nil
end

-- Hooks into auction house API to intercept favorite changes
hooksecurefunc(C_AuctionHouse, "SetFavoriteItem", saveFavorite)

local eventFrame = CreateFrame("Frame")

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("AUCTION_HOUSE_SHOW")
eventFrame:RegisterEvent("AUCTION_HOUSE_CLOSED")

eventFrame:SetScript("OnEvent", function(_, event, ...)
	-- Initialize databases when addon loads
	if event == "ADDON_LOADED" and ... == "QuickAuction" then
		eventFrame:UnregisterEvent("ADDON_LOADED")

		AuctionFavoritesDB = AuctionFavoritesDB or {}
		accountFavorites = AuctionFavoritesDB
		accountFavorites.favorites = accountFavorites.favorites or {}

		AuctionFavoritesCharDB = AuctionFavoritesCharDB or {}
		characterFavorites = AuctionFavoritesCharDB
		characterFavorites.favorites = characterFavorites.favorites or {}

		-- Register search result events for first-time sync on this character
		if not characterFavorites.synced then
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
		local shouldRefreshSearch = false

		if characterFavorites.synced then
			for _, favorites in ipairs { accountFavorites.favorites, characterFavorites.favorites } do
				for _, itemKey in pairs(favorites) do
					shouldRefreshSearch = syncFavorite(itemKey) or shouldRefreshSearch
				end
			end
		else
			for _, itemKey in pairs(accountFavorites.favorites) do
				C_AuctionHouse.SetFavoriteItem(itemKey, true)
				shouldRefreshSearch = true
			end
		end

		if shouldRefreshSearch then
			C_AuctionHouse.SearchForFavorites({})
		end
	end

	-- Mark character as synced and cleanup when auction house closes
	if event == "AUCTION_HOUSE_CLOSED" then
		characterFavorites.synced = true
		eventFrame:UnregisterAllEvents()
	end

	-- Processes search results and saves favorite status for discovered items
	local function processItemKey(itemKey)
		saveFavorite(itemKey, C_AuctionHouse.IsFavoriteItem(itemKey))
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
