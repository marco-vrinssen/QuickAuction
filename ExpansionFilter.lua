-- Auto-checks current expansion filter on auction house and crafting order searches

-- Enable current expansion filter for auction house searches
local function enableAuctionHouseExpansionFilter()
	if AUCTION_HOUSE_DEFAULT_FILTERS then
		AUCTION_HOUSE_DEFAULT_FILTERS[Enum.AuctionHouseFilter.CurrentExpansionOnly] = true
	end
end

-- Enable current expansion filter for crafting order searches
local function enableCraftingOrderExpansionFilter()
	if AUCTION_HOUSE_DEFAULT_FILTERS then
		AUCTION_HOUSE_DEFAULT_FILTERS[Enum.AuctionHouseFilter.CurrentExpansionOnly] = true
	end
end

-- Event handler frame for monitoring Blizzard UI loads
local expansionFilterFrame = CreateFrame("Frame")
expansionFilterFrame:RegisterEvent("ADDON_LOADED")
expansionFilterFrame:SetScript("OnEvent", function(self, event, addonName)
	-- Apply filter when auction house UI loads
	if addonName == "Blizzard_AuctionHouseUI" then
		enableAuctionHouseExpansionFilter()
	end

	-- Apply filter when professions customer orders UI loads
	if addonName == "Blizzard_ProfessionsCustomerOrders" then
		enableCraftingOrderExpansionFilter()
	end
end)
