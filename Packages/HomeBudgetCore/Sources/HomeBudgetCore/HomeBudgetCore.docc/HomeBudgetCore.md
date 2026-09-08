# ``HomeBudgetCore``

The household budget's domain logic, shared unchanged by the server, the web client and the iOS app.

## Overview

Everything that decides *what a number means* lives here: when a bill is due, what it costs per
month, how much has to be set aside for it, and what to call it in Polish or English. The three
front ends render it; none of them recalculates it.

Two constraints shape the whole module.

**No Foundation.** Not a style preference. Importing it for `JSONDecoder` took the WebAssembly
bundle from 9 MB to 60 MB, so calendar arithmetic (``CalendarDate``) and number formatting
(``NumberFormatting``) are written by hand. Anything added here has to hold to that, or the web
client's bundle regresses without anyone noticing until deployment.

**One copy of each rule.** The Python application this replaced had its translations in three places
and its status thresholds in two, and they drifted. A calculation that exists twice is a bug waiting
for a release.

## Topics

### The expenses themselves

- ``Expense``
- ``Frequency``
- ``RecurrenceInterval``
- ``Payment``
- ``PaymentRecord``

### When something is due

- ``StatusCalculator``
- ``ExpenseStatus``
- ``ExpenseStatusResult``
- ``PeriodKey``
- ``CalendarDate``

### What it adds up to

- ``DashboardBuilder``
- ``Dashboard``
- ``PriceHistory``

### Presentation

- ``Language``
- ``UIString``
- ``Localization``
- ``NumberFormatting``
- ``MonthGrid``

### Reports and alerts

- ``CSVReport``
- ``AlertEmail``

### Articles

- <doc:BusinessRules>
