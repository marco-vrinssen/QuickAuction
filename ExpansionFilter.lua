-- Auto-checks current expansion filter on auction house and crafting order searches

local function setAuctionHouseExpansionFilter()
  if AUCTION_HOUSE_DEFAULT_FILTERS then
    AUCTION_HOUSE_DEFAULT_FILTERS[Enum.AuctionHouseFilter.CurrentExpansionOnly] = true
  end
end

local function setCraftingOrderExpansionFilter()
  if AUCTION_HOUSE_DEFAULT_FILTERS then
    AUCTION_HOUSE_DEFAULT_FILTERS[Enum.AuctionHouseFilter.CurrentExpansionOnly] = true
  end
end

local filterFrame = CreateFrame("Frame")
filterFrame:RegisterEvent("ADDON_LOADED")
filterFrame:SetScript("OnEvent", function(self, event, name)
  if name == "Blizzard_AuctionHouseUI" then
    setAuctionHouseExpansionFilter()
  end
  
  if name == "Blizzard_ProfessionsCustomerOrders" then
    setCraftingOrderExpansionFilter()
  end
end)
