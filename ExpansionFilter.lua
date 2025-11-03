-- Auto-checks current expansion filter on auction house searches

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
