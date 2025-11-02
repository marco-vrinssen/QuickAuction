-- Filters auction house searches to current expansion only

local function setExpansionFilter()
  local searchBar = AuctionHouseFrame and AuctionHouseFrame.SearchBar
  local filterButton = searchBar and searchBar.FilterButton
  if not filterButton then return end

  filterButton.filters = filterButton.filters or {}
  filterButton.filters[Enum.AuctionHouseFilter.CurrentExpansionOnly] = true
  searchBar:UpdateClearFiltersButton()
end

local function hookSearchBar()
  local searchBar = AuctionHouseFrame and AuctionHouseFrame.SearchBar
  if not searchBar then return end

  if not searchBar.hooked then
    searchBar:HookScript("OnShow", setExpansionFilter)
    searchBar.hooked = true
  end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("AUCTION_HOUSE_SHOW")
eventFrame:SetScript("OnEvent", hookSearchBar)











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
	if event == "ADDON_LOADED" and ... == "BentoAuctionUtility" then
		eventFrame:UnregisterEvent("ADDON_LOADED")

		BentoAuctionFavoritesDB = BentoAuctionFavoritesDB or {}
		accountFavorites = BentoAuctionFavoritesDB
		accountFavorites.favorites = accountFavorites.favorites or {}

		BentoAuctionFavoritesCharDB = BentoAuctionFavoritesCharDB or {}
		characterFavorites = BentoAuctionFavoritesCharDB
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









-- Enables spacebar to post auctions for faster listing workflow

local postItemFrame = CreateFrame("Frame")
local postKey = "SPACE"
local isEnabled = false

local function postAuction()
  if not isEnabled or not AuctionHouseFrame or not AuctionHouseFrame:IsShown() then
    return
  end

  local commoditiesFrame = AuctionHouseFrame.CommoditiesSellFrame
  if commoditiesFrame and commoditiesFrame:IsShown() and commoditiesFrame.PostButton and commoditiesFrame.PostButton:IsEnabled() then
    commoditiesFrame.PostButton:Click()
    return
  end

  local itemFrame = AuctionHouseFrame.ItemSellFrame
  if itemFrame and itemFrame:IsShown() and itemFrame.PostButton and itemFrame.PostButton:IsEnabled() then
    itemFrame.PostButton:Click()
    return
  end

  local sellFrame = AuctionHouseFrame.SellFrame
  if sellFrame and sellFrame:IsShown() and sellFrame.PostButton and sellFrame.PostButton:IsEnabled() then
    sellFrame.PostButton:Click()
    return
  end
end

local function handleKeyDown(self, key)
  if key == postKey and isEnabled then
    postAuction()
    self:SetPropagateKeyboardInput(false)
  else
    self:SetPropagateKeyboardInput(true)
  end
end

local function handleEvent(self, event)
  if event == "AUCTION_HOUSE_SHOW" then
    isEnabled = true
    self:SetScript("OnKeyDown", handleKeyDown)
    self:SetPropagateKeyboardInput(true)
    self:EnableKeyboard(true)
    self:SetFrameStrata("HIGH")
  elseif event == "AUCTION_HOUSE_CLOSED" then
    isEnabled = false
    self:SetScript("OnKeyDown", nil)
    self:EnableKeyboard(false)
  end
end

postItemFrame:RegisterEvent("AUCTION_HOUSE_SHOW")
postItemFrame:RegisterEvent("AUCTION_HOUSE_CLOSED")
postItemFrame:SetScript("OnEvent", handleEvent)
