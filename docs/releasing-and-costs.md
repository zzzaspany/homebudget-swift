# Shipping the iOS app: distribution, costs, and how it lands in a Polish JDG

Researched September 2026. Two warnings before anything else.

**This is not tax advice.** The tax section below is a briefing to take to an accountant, not a
substitute for one. The rules are specific to a Polish sole proprietorship (JDG), they change, and
the consequences of getting VAT registration wrong land on the person who signed the declaration.
Confirm everything with your księgowa before acting.

**Prices and free tiers move.** Everything here carries a date. Check before you spend.

## The question that decides everything else

HomeBudget is not a product. It talks to one server, on one private network, behind Authelia and a
VPN, with an internal certificate authority. That single fact rules out the route most iOS advice
assumes.

**The App Store is not a realistic target for this app.** App review means a human at Apple runs the
build. They cannot reach `rachunki.office.lab`, cannot get through Authelia, and would be handed a
sign-in screen that goes nowhere. That is a rejection, and reasonably so — Apple has no way to
evaluate an app whose entire function is behind someone's VPN.

So the real question is not "how do I publish this" but "how do I get a signed build onto my own
phone and keep it working". That has four answers.

## Distribution options

| Route | Cost | Build life | Devices | Verdict for this app |
| --- | --- | --- | --- | --- |
| **Free provisioning** (Apple ID, no membership) | none | **7 days**, then the app refuses to launch | the devices you plug in | Works today. Reinstalling from Xcode every week is the price. |
| **Developer Program, development/ad-hoc signing** | **$99/year** | up to a year, until the certificate or profile expires | 100 per device type per membership year | **The realistic choice.** Install once, forget for a year. |
| **TestFlight** | $99/year | **90 days** per build | 100 internal testers | Needs an App Store Connect record and, for external testers, review. Internal testing avoids review but still needs the app to exist in App Store Connect. |
| **Apple Developer Enterprise Program** | $299/year | a year | unlimited, employees only | **Not eligible.** Requires a legal entity with 100+ employees and an internal-use case. |

Two details on the 100-device limit that catch people out: it is per product type (iPhone, iPad,
Mac… each has its own hundred), and **the count only resets at membership renewal** — removing a
device does not free the slot before then. For a household that is irrelevant; worth knowing anyway.

Ad-hoc builds can be installed over the air with the `itms-services` protocol, which is Apple's
supported mechanism outside TestFlight and the App Store. That would let you put the `.ipa` on the
lab's own web server behind Authelia and install from Safari — fitting, given everything else here
already lives there.

### Recommendation

**Free provisioning until the weekly reinstall annoys you, then the $99 membership.** There is no
technical reason to pay before that, and the membership buys exactly one thing you actually need:
signing that lasts a year instead of a week.

The membership also throws in 25 Xcode Cloud compute hours a month, which is worth noting but is not
a reason to buy it — GitHub Actions macOS runners are free on this public repository. See
[ci.md](ci.md).

## What it costs

| Item | Amount | Frequency | Needed? |
| --- | --- | --- | --- |
| Apple Developer Program | $99 (in PLN at enrolment) | yearly, auto-renewing | Only for year-long signing |
| A Mac | already owned | — | Non-negotiable: iOS builds require macOS |
| CI | 0 zł | — | Public repository, free macOS runners |
| App Store commission | 15% or 30% | per sale | **Not applicable** — nothing is being sold |

Total realistic outlay: **$99/year, or nothing at all.**

## Accounting for it in a JDG

### The Developer Program fee is an import of services

Apple invoices the membership from **Apple Distribution International Ltd**, Ireland, VAT
`IE9700053D`. For a Polish business that is *import usług* under art. 28b of the VAT Act: the place
of supply moves to Poland and **you** account for the VAT, not Apple.

Give Apple your NIP with the `PL` prefix at enrolment. Without it Apple treats you as a consumer and
adds VAT itself, which you then cannot recover and cannot reverse-charge — a mess that is much
easier to avoid than to unwind.

**If you are VAT-registered (czynny podatnik):** reverse charge. Output and input VAT both go in
`JPK_V7`, netting to zero, and the net amount is a cost.

**If you are VAT-exempt (zwolniony, the 200 000 zł threshold):** this is the part that surprises
people. **Exemption does not cover imported services.** Before the first purchase you must register
for EU VAT on form `VAT-R` (the section for entities not otherwise required to register), then for
each month with a purchase file **`VAT-9M`** and pay the VAT by the **25th of the following month**.
You cannot deduct it — for you the VAT is a real 23% on top.

Either way the fee is an ordinary **koszt uzyskania przychodu**, provided the app serves the
business. Which brings up the honest question below.

### Is a household budget app a business expense?

If HomeBudget is used to track your own household bills, the membership is a **private expense**,
not a deductible cost, and putting it in the KPiR would be wrong. Do not let the fact that it is
software make it look like a tool of the trade.

It becomes deductible if there is a genuine business connection — the app is a portfolio piece you
show clients, the account is used for work builds, or the app is actually sold. That is a question
of fact about how you use it, and exactly the sort of thing to put to your accountant plainly rather
than to decide by wishful thinking.

### If the app were ever sold

Not the plan, but worth writing down once so nobody has to work it out under time pressure.

You do not sell to the end user. **You license the app to Apple**, and Apple sells to the customer
and collects that customer's local VAT. Practically:

- Your counterparty is **Apple Distribution International** (Ireland) for most territories, and
  Apple entities elsewhere for some regions — which entity matters, because it decides whether a
  sale is an intra-EU service or an export outside the EU.
- You issue **one collective invoice to Apple** per period, from Apple's own sales report. Never to
  the end customer.
- For the Irish entity this is a service whose place of supply is outside Poland (art. 28b): the
  invoice carries **odwrotne obciążenie**, no Polish VAT, and it goes into `JPK_V7` and the
  **VAT-UE** summary. That means EU VAT registration, again via `VAT-R`, even if you are otherwise
  exempt.
- Income goes into the **KPiR** on Apple's report, converted at the **NBP rate from the working day
  before** the income arises.
- Apple's commission is 30%, or **15% under the Small Business Program** for developers under
  $1 000 000 a year. What you book as revenue and what Apple pays out therefore differ — the
  commission is a cost, not a discount on revenue.

### A checklist for the conversation with your accountant

1. Is the Developer Program fee deductible given how I actually use the app?
2. Am I VAT-registered, and if not, do I need `VAT-R` + `VAT-UE` before the first purchase?
3. Who files `VAT-9M`, and by when?
4. Where does the fee go in the KPiR, and at which NBP rate?
5. If income ever appears: which Apple entity, and does that make it EU or export?

## Sources

- [Apple Developer Program enrolment](https://developer.apple.com/help/account/membership/program-enrollment/)
- [Apple Developer Program membership details](https://developer.apple.com/programs/whats-included/)
- [iOS app distribution: TestFlight, ad hoc, enterprise, App Store](https://appcircle.io/guides/ios/ios-app-distribution)
- [Distributing an iOS app without the App Store](https://appisto.app/blog/distribute-ios-app-without-app-store)
- [Sprzedaż aplikacji w App Store – jak rozliczyć przychód i VAT](https://podatkiprogramisty.pl/sprzedaz-aplikacji-w-app-store-jak-rozliczyc-przychod-i-vat/)
- [Import usług u podatnika zwolnionego z VAT](https://poradnikprzedsiebiorcy.pl/-import-uslug-a-podatnik-zwolniony-z-vat)
- [Rozliczanie importu usług i WNT przez podatnika zwolnionego z VAT](https://mentzen.pl/blog/vat/rozliczanie-importu-uslug-i-wnt-przez-podatnika-zwolnionego-z-vat/)
- [Zakupy w Apple na firmę – jak uzyskać fakturę](https://www.fakturowo.pl/blog/zakupy-w-apple-na-firme-jak-uzyskac-fakture)
