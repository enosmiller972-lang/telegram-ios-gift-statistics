# Gift card restyle and gift collection statistics

Base: `TelegramMessenger/Telegram-iOS` `f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838` (public `master`, 13.0).
Server contract: `submodules/GiftStats/PROTOCOL.md`.

## What the user gets

- **Gift card** of every unique gift: the backdrop fills the whole sheet, the table of attributes sits on a tonal panel derived from the
  backdrop (`GiftTableColors`; a separate formula for light backdrops keeps white text readable), the buttons share one flat tonal recipe.
  Regular (non-collectible) gifts keep the stock look.
- **Value row**: price in Gram with dollars and "View More". It appears only when statistics are available; otherwise the stock row stays.
- **Statistics** (tap on the Value row; the card morphs into them and back from any scroll position):
  collection name and a two-line description, tiles Floor / Supply / Listed, **Your Item** (the viewer's own gift, Average price, Sell /
  Unlist via the stock resale flow), **Recent Sales** (model on its backdrop with symbols, number, price, market, time; Show All opens a
  scrollable list that pages in 20 at a time and always fits the screen), price chart, sales chart, "Buy from X" (opens the collection market).
- **Mini card**: a tap on a sale or on Your Item morphs its icon into a small card (owner, model, symbol, backdrop, price capsule, Copy Link
  in "…", OK / cross). Swipe sideways pages through the sales, swipe down closes. Closing morphs back into the row.
- Accessibility: VoiceOver labels, charts are adjustable elements, Reduce Motion, Increase Contrast, Reduce Transparency, right-to-left.

## Connecting the server

The screens read data only through `GiftStatsProvider` (`submodules/GiftStats/Sources/GiftStatsProvider.swift`), held by
`GiftStatsService.shared.provider`. Default is `UnavailableGiftStatsProvider` (no statistics, stock Value row).

1. Add the TL methods from `PROTOCOL.md` (`payments.getStarGiftStats`, `payments.getStarGiftSales`).
2. Implement `GiftStatsProvider` on top of them and assign it to `GiftStatsService.shared.provider` (e.g. in `TelegramRootController` next to
   `GiftStatsPreviewInstaller.install`).
3. Each sale should carry the sold gift (`StarGift.UniqueGift`, owner included) in `GiftSale.gift`: it drives the backdrop icon and the mini card.

## Local stand-in

`submodules/GiftStatsPreview` (`LocalGiftStatsProvider`) generates the numbers, sales, sold gifts and owners locally so the feature can be seen
without a server. It is switched by **Debug settings → "Gift Stats Preview Data"** (`ExperimentalUISettings.giftStatsPreview`), on by default
in every build so the feature can be seen right away; turn it off there to see the card without statistics. Open the debug settings with
`tg://settings/enable_log` or ten taps on the Settings tab.
`GiftStatsPreviewInstaller` (`submodules/TelegramUI/Sources/GiftStatsPreview.swift`) only installs it while the switch is on and never replaces
a non-preview provider. Remove the module and the installer when the server provider ships.

## Structure

| Module | Purpose |
|---|---|
| `submodules/GiftStats` | Models, `GiftStatsProvider`, `GiftStatsService`, `PROTOCOL.md` |
| `submodules/GiftStatsPreview` | Local stand-in (until the server provides the data) |
| `Components/Gifts/GiftStatsScreen` | Statistics UI, morph engine, tonal palette, table colours, chart wrappers |
| `Components/Gifts/GiftViewScreen` (new files) | Card restyle, card ↔ statistics flow (`GiftViewScreen+Stats*`), mini card (`GiftSaleMiniCard*`, `GiftStatsSaleOpening`) |
| `Components/Gifts/GiftCardStyle`, `GiftCraftBackdrop` | Symbol field / wave, Craft background (shared with the Craft screen) |
| `GraphCore`, `GraphUI` | Gift chart style, all behind `giftStyle` (channel statistics unchanged) |

Changed upstream files are small hooks: `GiftViewScreen.swift`, `TableComponent`, `GiftPagerComponent` (paging locked during statistics),
`GiftCompositionComponent` (`drawsBackground`, `finishAnimation`), `GiftCraftScreen` (background moved to `GiftCraftBackdrop`),
`ExperimentalUISettings` + `DebugController` (the preview switch), `TelegramRootController` (installer line), `Localizable.strings` (`Gift.Stats.*`).

## Checked

- **Release simulator builds 16531 & 16532** (iPhone 17 Pro Max, iPad): card, morph both ways, Your Item, Sell flow, Recent Sales with Show All / paging / swipe hand-off, charts and scrubbing, mini card (open, page, close morph, Copy Link), other people's gifts (no Your Item), regular gifts (stock look), preview switch on/off, system dark appearance, Increase Contrast.
- **iPhone SE (3rd gen)**: verified compact card layout and statistics presentation.
- **iPad**: verified centered modal presentation on `QA iPad`, list expansion/collapse, mini card modal presentation and dismiss.
- **VoiceOver & Accessibility**: verified composite single-element labels on `Your Item` and sales rows with subview digit pieces hidden from accessibility tree, charts exposed as adjustable AXSliders.
- **Reduce Motion**: verified graceful cross-fade fallback transitions in mini card (`GiftSaleMiniCardController`).
- **Right-to-Left (RTL)**: verified layout order, whitespace prefix trimming, and symmetric gap & glyph positioning in `GiftStatsNumberLineView`.
- **Russian localization**: verified layout length and Cyrillic string presentation.
- **Mini card scroll lag fix**: diagnosed touch interception during morph dismissal in `GiftSaleMiniCardController`, resolved by immediately disabling user interaction on `close()`.
- **Debug build 16533**: verified clean compilation (`debug_sim_arm64`, exit=0).
- **Comments style**: all 121 files updated to concise Telegram code style without any logic alterations.

Not checked: physical device, a real server.
