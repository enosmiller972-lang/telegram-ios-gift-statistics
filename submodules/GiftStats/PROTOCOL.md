# Gift statistics: what the client asks the server

The client reads the statistics of a gift through `GiftStatsProvider` (`submodules/GiftStats`). Until a provider is installed
(`GiftStatsService.shared.provider`) the gift card shows its stock "Value" row and nothing else. `submodules/GiftStatsPreview` is a local stand-in that makes
the numbers without a server; it is installed by `GiftStatsPreviewInstaller.install` and is meant to be replaced by an implementation that talks to the server.

## What changes on screen, and when

- The restyle of the gift card (dark card, tonal table, flat tiles, glass button) applies to every unique gift, whatever the provider is and whether it has
  data or not. Gifts that are not collectibles keep the stock look.
- The "Value" row is replaced by the statistics row ("price", "View More") only when the statistics of both scopes, the model of the gift and its whole
  collection, have been loaded (and the price graph of the model can be read). Otherwise the stock row stays and opens nothing.
- The statistics screen shows the collection scope. The model scope gives only the price on the row.

## Scope of the numbers

Everything is the fixed-price market only (listings and sales at a price the seller set): `price_graph`, `sales_graph`, `recent_sales` and `floor_usd`
leave out sales by auction, and so do the counters (`listed_count`). A price set by bidding says little about what a gift costs, so it is a separate
market with its own screens. For the same reason a client stand-in must not take the gift value that Telegram sends with a gift (`valueAmount`,
`valueUsdAmount`): that estimate includes sales by auction. The collection floor a stand-in starts from is the lowest fixed-price resale listing of the
collection (`StarGift.Gift.availability.minResaleStars`).

## Units

Every price the client reads from the server is in **US cents** (whole numbers): `floor_usd`, `price_usd` of a sale, and the y values of `price_graph`.
The server never sends Gram, TON or Stars amounts. The client turns cents into Gram itself, with `ton_usd_rate` of the app configuration (dollars for one
Gram; the key is named for the blockchain, the client shows the currency as Gram), and shows the dollars next to it ("~$12.55"). Dates are Unix time in
seconds (`date` of a sale) and in milliseconds on the x axis of the graphs.

## Proposed methods, one request per scope

```
payments.getStarGiftStats#xxxxxxxx flags:# slug:string model_id:flags.0?long = payments.StarGiftStats;

payments.starGiftStats#xxxxxxxx price_graph:StatsGraph sales_graph:StatsGraph floor_usd:flags.0?long
    supply:int listed_count:int recent_sales:Vector<StarGiftSale> = payments.StarGiftStats;

starGiftSale#xxxxxxxx market:string gift:StarGift price_usd:long date:int = StarGiftSale;

payments.getStarGiftSales#xxxxxxxx flags:# slug:string model_id:flags.0?long offset:int limit:int = payments.StarGiftSales;

payments.starGiftSales#xxxxxxxx count:int sales:Vector<StarGiftSale> = payments.StarGiftSales;
```

`slug` is the slug of any gift of the collection (it names the collection and the gift whose model is meant), `model_id` is the id of the sticker file of
the model; without it the request is about the whole collection. Both scopes are requested when the card opens, in parallel.

What the client reads from each scope:

| Field | Collection scope (the statistics screen) | Model scope (the row of the card) |
| --- | --- | --- |
| `price_graph` | the price chart and the range of the periods | the floor shown on the row when `floor_usd` is missing |
| `sales_graph` | the sales chart | not read |
| `floor_usd` | the "Floor" tile and the "Buy from" button; when missing, the last point of `price_graph` | the price on the row; when missing, the last point of `price_graph` |
| `supply` | the "Supply" tile (the issued count of the collection) | not read |
| `listed_count` | the "Listed" tile and "for sale" on the button | not read |
| `recent_sales` | the first page of the log of sales | not read |

A field that is "not read" may be sent or left out (send 0 or an empty graph for a required TL field).

`recent_sales` is the first page of the log of the latest sales of the collection on every market (the newest first, up to 20, `GiftStats.salesPageSize`).
`market` is the name of the market ("Telegram", "Fragment", "Portals", "MRKT", "Tonnel", case-insensitive; any other is shown as it is, as text: the
log shows names, never logos). `gift` is the sold gift (`starGiftUnique`: its slug, number and attributes; the owner may be left out): the row shows its number and its model on a small square of its backdrop (`center_color` to `edge_color`), and a tap on the row opens it as a gift card. Sales by auction are not in the log.

The rest of the log is read page by page while the person scrolls it (pages of 20, the log can hold hundreds of sales) with `getStarGiftSales`:

- `offset` is an integer: the number of sales the client has already received (the first page of the statistics is the sales 0 to 19, so the next
  request has `offset` 20, then 40, and so on). It is the position in the log, never a token.
- `limit` is the page size (20).
- `count` is the total number of sales the log holds, not the size of the page. The client stops when a page is empty or when it has received `count`
  sales. A page that comes back for an `offset` that no longer matches what the client has is dropped and asked again.

## Graphs

A graph is a `StatsGraph` sent in full: `statsGraph` with the JSON in `json`. `statsGraphAsync` (a token that is loaded later with
`stats.loadAsyncGraph`) is **not supported**: the client reads the data of the graph at once to find the range and the floor, and the charts of these
screens do not zoom, so they never load a finer series.

- **Daily points.** Both graphs have one point per day, on the same dates, oldest first, x in milliseconds (the charts expect milliseconds; the reader of the price
  series also tolerates seconds). The client builds its bars from these daily points: it sums them into buckets of 1, 7, 30, 90 or 365 days (so that
  no more than about 40 bars are visible) and chooses the bucket from the range that is on screen. A graph with a different step is shown wrongly.
- **Price graph** (`price_graph`): one line series, id `y0`, y in US cents (the floor of the collection or of the model on that day).
- **Sales graph** (`sales_graph`): one bar series, id `y0`, y is the number of sales of that day (fixed-price sales only).
- The graph JSON has `columns` (an `x` column and the `y0` column, whole numbers, no gaps and no NaN), `types` (`x` and `line` or `bar`), `names` and
  `colors` as for any chart. A graph with fewer than two points or with columns of different lengths cannot be read.
- The client renames and recolours the series itself (the names come from the localization of the app, the price is `#FFFFFF`, the sales `#FFFFFF8C`;
  `GiftStatsGraphNames.localized`, it looks for the id `y0`), so the `names` and `colors` of the server only have to be valid, and the id has to be `y0`.

## The numbers of the summary

`floor_usd` is the number that the "Value" row, the "Floor" tile and the "Buy from X" button show. The client sends nothing but the gift and the scope;
the market (the catalog floor and the rate of a star) is the business of the provider, which is why a stand-in has to look it up itself.

`supply` is the issued count of the collection (of the gifts that have the model, for the model scope). `listed_count` is the number of gifts of the
collection that are listed now at a fixed price. The first sale and the last sale of a collection are not part of this protocol: the client does not use them.
