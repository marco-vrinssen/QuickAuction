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
