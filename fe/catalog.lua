-- What each tab shows. `id` is Gen1 Recomp's game id for the games it runs;
-- spin-offs have their own ids and aren't playable yet.
-- `boxes` are the bundled box arts offered by Cust. Art (first = default).

local Catalog = {}

Catalog.tabs = {
  {
    id = "gen12", label = "Gen 1 & 2",
    games = {
      { id = "red", name = "Red", boxes = {
        { "North America", "na_red_box.jpg" }, { "Japan", "jp_red_box.jpg" } } },
      { id = "blue", name = "Blue", boxes = {
        { "North America", "na_blue_box.jpg" }, { "Japan", "jp_blue_box.jpg" },
        { "Green (North America style)", "na_green_box.jpg" },
        { "Green (Japan)", "jp_green_box.jpg" } } },
      { id = "yellow", name = "Yellow", boxes = {
        { "North America", "na_yellow_box.jpg" }, { "Japan", "jp_yellow_box.jpg" } } },
      { id = "gold", name = "Gold", boxes = {
        { "North America", "na_gold_box.jpg" }, { "Japan", "jp_gold_box.jpg" } } },
      { id = "silver", name = "Silver", boxes = {
        { "North America", "na_silver_box.jpg" }, { "Japan", "jp_silver_box.jpg" } } },
      { id = "crystal", name = "Crystal", boxes = {
        { "North America", "na_crystal_box.jpg" }, { "Japan", "jp_crystal_box.jpg" } } },
    },
  },
  {
    id = "gen3", label = "Gen 3",
    games = {
      { id = "firered", name = "Fire Red", boxes = {
        { "North America", "na_firered_box.jpg" }, { "Japan", "jp_firered_box.jpg" } } },
      { id = "leafgreen", name = "Leaf Green", boxes = {
        { "North America", "na_leafgreen_box.jpg" }, { "Japan", "jp_leafgreen_box.jpg" } } },
      { id = "ruby", name = "Ruby", boxes = {
        { "North America", "na_ruby_box.jpg" }, { "Japan", "jp_ruby_box.jpg" } } },
      { id = "sapphire", name = "Sapphire", boxes = {
        { "North America", "na_sapphire_box.jpg" }, { "Japan", "jp_sapphire_box.jpg" } } },
      { id = "emerald", name = "Emerald", boxes = {
        { "North America", "na_emerald_box.jpg" }, { "Japan", "jp_emerald_box.jpg" } } },
    },
  },
  {
    id = "spinoffs", label = "Spin-Offs", spinoff = true,
    games = {
      { id = "pinball", name = "Pinball", boxes = {
        { "North America", "na_pinball_box.jpg" }, { "Japan", "jp_pinball_box.jpg" } } },
      { id = "tcg", name = "Trading Card Game", boxes = {
        { "North America", "na_tradingcard_box.jpg" }, { "Japan", "jp_tradingcard_box.jpg" } } },
      { id = "tcg2", name = "TCG 2", boxes = {
        { "North America", "na_tradingcard2_box.jpg" }, { "Japan", "jp_tradingcard2_box.jpg" } } },
      { id = "puzzle", name = "Puzzle Challenge", boxes = {
        { "North America", "na_panepon_box.jpg" }, { "Japan", "jp_panepon_box.jpg" } } },
      { id = "picross", name = "Picross", boxes = {
        { "North America", "na_picross_box.jpg" } } },
      { id = "pinballrs", name = "Pinball R&S", boxes = {
        { "North America", "na_pinballrubysapphire_box.jpg" },
        { "Japan", "jp_pinballrubysapphire_box.jpg" } } },
      { id = "mysterydungeon", name = "Mystery Dungeon", boxes = {
        { "North America", "na_mysterydungeon_box.jpg" }, { "Japan", "jp_mysterydungeon_box.jpg" } } },
    },
  },
  { id = "mods", label = "Mods" },
  { id = "launch", label = "Launch G1R" },
}

Catalog.byId = {}
for _, tab in ipairs(Catalog.tabs) do
  for _, g in ipairs(tab.games or {}) do
    g.spinoff = tab.spinoff == true
    Catalog.byId[g.id] = g
  end
end

-- Short labels for the Mods tab's "Show for" chips.
Catalog.modGames = {
  { "red", "Red" }, { "blue", "Blue" }, { "yellow", "Yellow" }, { "gold", "Gold" },
  { "silver", "Silver" }, { "crystal", "Crystal" }, { "firered", "FireRed" },
  { "leafgreen", "LeafGreen" }, { "ruby", "Ruby" }, { "sapphire", "Sapphire" },
  { "emerald", "Emerald" },
}

return Catalog
