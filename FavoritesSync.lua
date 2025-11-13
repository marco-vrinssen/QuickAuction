-- Sync auction house favorites across all characters on the account

-- Database references for account-wide and character-specific data
local accountDatabase, characterDatabase

-- Core fields that define an item's identity in the auction house
local itemKeyFields = { "itemID", "itemLevel", "itemSuffix", "battlePetSpeciesID", "itemContext" }

-- Lookup table for quick field validation
local itemKeyFieldLookup = {}

for _, field in ipairs(itemKeyFields) do
	itemKeyFieldLookup[field] = true
end

-- Convert item key to unique string identifier for storage
local function serializeItemKey(itemKey)
	local serializedValues = {}

	-- Serialize core item fields in consistent order
	for index, field in ipairs(itemKeyFields) do
		local value = itemKey[field]
		serializedValues[index] = value ~= nil and tostring(value) or ""
	end

	-- Collect any extra fields not in core set
	local extraFields = {}

	for fieldName in pairs(itemKey) do
		if not itemKeyFieldLookup[fieldName] then
			extraFields[#extraFields + 1] = fieldName
		end
	end

	-- Append extra fields in sorted order for consistency
	if #extraFields > 0 then
		table.sort(extraFields)

		for _, fieldName in ipairs(extraFields) do
			serializedValues[#serializedValues + 1] = itemKey[fieldName] ~= nil and tostring(itemKey[fieldName]) or ""
		end
	end

	return table.concat(serializedValues, "-")
end

-- Get item link for chat messages with fallback for uncached items
local function getItemLink(itemKey)
	local itemID = itemKey.itemID

	if itemID then
		local itemName, itemLink = C_Item.GetItemInfo(itemID)

		-- Return full clickable item link if available
		if itemLink then
			return itemLink
		end

		-- Return plain item name if link not yet cached
		if itemName then
			return itemName
		end

		-- Request item data from server for future use
		C_Item.RequestLoadItemDataByID(itemID)

		-- Return gray placeholder with item ID until data loads
		return "|cff9d9d9d[Item:" .. itemID .. "]|r"
	end

	return "Unknown Item"
end

-- Synchronize favorite status when account and character databases differ
local function syncFavoriteItem(itemKey)
	local serializedKey = serializeItemKey(itemKey)

	-- Check if both databases agree on favorite status
	if not accountDatabase.favorites[serializedKey] == not characterDatabase.favorites[serializedKey] then
		return false
	end

	-- Use account database as source of truth
	local shouldBeFavorited = accountDatabase.favorites[serializedKey] ~= nil

	-- Apply favorite status to auction house UI
	C_AuctionHouse.SetFavoriteItem(itemKey, shouldBeFavorited)

	-- Show notification with color-coded status
	local statusPrefix = shouldBeFavorited and "|cff00ff00[+]|r " or "|cffff0000[-]|r "
	local notificationMessage = "[Auction Favorites]: " .. statusPrefix .. getItemLink(itemKey)

	if DEFAULT_CHAT_FRAME then
		DEFAULT_CHAT_FRAME:AddMessage(notificationMessage)
	else
		print(notificationMessage)
	end

	return true
end

-- Update favorite in both databases when user makes changes
local function updateFavoriteStatus(itemKey, isFavorited)
	if not accountDatabase or not characterDatabase then
		return
	end

	local serializedKey = serializeItemKey(itemKey)
	local wasAlreadyFavorited = accountDatabase.favorites[serializedKey] ~= nil

	-- Store item key if favorited, nil if unfavorited in both databases
	accountDatabase.favorites[serializedKey] = isFavorited and itemKey or nil
	characterDatabase.favorites[serializedKey] = isFavorited and itemKey or nil

	-- Only show notification if status actually changed
	if wasAlreadyFavorited ~= isFavorited then
		local statusPrefix = isFavorited and "|cff00ff00[+]|r " or "|cffff0000[-]|r "
		local notificationMessage = "[Auction Favorites]: " .. statusPrefix .. getItemLink(itemKey)

		if DEFAULT_CHAT_FRAME then
			DEFAULT_CHAT_FRAME:AddMessage(notificationMessage)
		else
			print(notificationMessage)
		end
	end
end

-- Capture current favorite state from auction house UI
local function captureCurrentFavoriteState(itemKey)
	if not itemKey then
		return
	end

	-- Query current favorite status and update databases
	updateFavoriteStatus(itemKey, C_AuctionHouse.IsFavoriteItem(itemKey))
end

-- Hook into auction house API to intercept all favorite changes
hooksecurefunc(C_AuctionHouse, "SetFavoriteItem", updateFavoriteStatus)

-- Event handler frame for addon lifecycle and auction house events
local eventFrame = CreateFrame("Frame")

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("AUCTION_HOUSE_SHOW")
eventFrame:RegisterEvent("AUCTION_HOUSE_CLOSED")

eventFrame:SetScript("OnEvent", function(_, event, ...)
	-- Initialize databases when addon loads
	if event == "ADDON_LOADED" and ... == "AuctionAndy" then
		eventFrame:UnregisterEvent("ADDON_LOADED")

		-- Initialize account-wide database (persists across all characters)
		AuctionFavoritesDB = AuctionFavoritesDB or {}
		accountDatabase = AuctionFavoritesDB
		accountDatabase.favorites = accountDatabase.favorites or {}

		-- Initialize character-specific database (unique per character)
		AuctionFavoritesCharDB = AuctionFavoritesCharDB or {}
		characterDatabase = AuctionFavoritesCharDB
		characterDatabase.favorites = characterDatabase.favorites or {}

		-- Register search events on first login to capture initial favorites
		if not characterDatabase.sync then
			eventFrame:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
			eventFrame:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_ADDED")
			eventFrame:RegisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED")
			eventFrame:RegisterEvent("COMMODITY_SEARCH_RESULTS_ADDED")
			eventFrame:RegisterEvent("ITEM_SEARCH_RESULTS_UPDATED")
			eventFrame:RegisterEvent("ITEM_SEARCH_RESULTS_ADDED")
		end

		return
	end

	-- Synchronize favorites when auction house opens
	if event == "AUCTION_HOUSE_SHOW" then
		local needsRefresh = false

		-- If character has been synced before, compare and sync differences
		if characterDatabase.sync then
			for _, favoritesTable in ipairs { accountDatabase.favorites, characterDatabase.favorites } do
				for _, itemKey in pairs(favoritesTable) do
					needsRefresh = syncFavoriteItem(itemKey) or needsRefresh
				end
			end
		-- First time sync: apply all account favorites to this character
		else
			for _, itemKey in pairs(accountDatabase.favorites) do
				C_AuctionHouse.SetFavoriteItem(itemKey, true)
				needsRefresh = true
			end
		end

		-- Refresh auction house UI if any changes were made
		if needsRefresh then
			C_AuctionHouse.SearchForFavorites({})
		end

		return
	end

	-- Mark character as synced and unregister search events
	if event == "AUCTION_HOUSE_CLOSED" then
		-- Mark this character as having completed initial sync
		characterDatabase.sync = true

		-- Unregister search events (only needed for first-time sync)
		eventFrame:UnregisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
		eventFrame:UnregisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_ADDED")
		eventFrame:UnregisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED")
		eventFrame:UnregisterEvent("COMMODITY_SEARCH_RESULTS_ADDED")
		eventFrame:UnregisterEvent("ITEM_SEARCH_RESULTS_UPDATED")
		eventFrame:UnregisterEvent("ITEM_SEARCH_RESULTS_ADDED")

		return
	end

	-- Capture favorite state when browse results update
	if event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" then
		for _, searchResult in ipairs(C_AuctionHouse.GetBrowseResults()) do
			captureCurrentFavoriteState(searchResult.itemKey)
		end

		return
	end

	-- Capture favorite state when new browse results are added
	if event == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" then
		for _, searchResult in ipairs(...) do
			captureCurrentFavoriteState(searchResult.itemKey)
		end

		return
	end

	-- Capture favorite state for commodity search results
	if event == "COMMODITY_SEARCH_RESULTS_UPDATED" or event == "COMMODITY_SEARCH_RESULTS_ADDED" then
		captureCurrentFavoriteState(C_AuctionHouse.MakeItemKey(...))

		return
	end

	-- Capture favorite state for item search results
	if event == "ITEM_SEARCH_RESULTS_UPDATED" or event == "ITEM_SEARCH_RESULTS_ADDED" then
		captureCurrentFavoriteState(...)

		return
	end
end)