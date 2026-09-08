# The business rules

What the numbers on every screen actually mean, and the two places this deliberately disagrees with
the application it replaced.

## Overview

These rules are the contract. They are covered by ``HomeBudgetCore``'s test suite, and a change to
any of them needs a test case before it counts as done — there is no other guardrail on them.

## Proration

Every cycle is reduced to a monthly share, so figures for bills paid at different intervals can be
added together:

| Cycle | Monthly share |
| --- | --- |
| Monthly | the amount |
| Fortnightly | amount × 26 ÷ 12 |
| Quarterly | amount ÷ 3 |
| Half-yearly | amount ÷ 6 |
| Yearly | amount ÷ 12 |

`Monthly budget` is the sum of those shares across active expenses. `Monthly reserve` is the same
sum restricted to bills that are not paid monthly — the money that has to accumulate somewhere
between one payment and the next.

## Status

``StatusCalculator`` answers three things at once: the status, the next due date, and how many days
away it is. An inactive expense short-circuits to no date at all.

"Due soon" begins at a different distance for each cycle, because a fortnightly bill and a yearly
one need warning on different timescales:

| Cycle | Warned |
| --- | --- |
| Fortnightly | 3 days ahead |
| Monthly | 5 days ahead |
| Quarterly | 7 days ahead |
| Half-yearly | 10 days ahead |
| Yearly | 14 days ahead |

The invariant worth remembering: **a paid bill shows the date of its next occurrence, not the one
just settled.** Once the current period is marked paid, the due date rolls forward.

Day numbers are clamped, not wrapped — a bill due on the 31st falls on the 30th in April and the
28th in February, via ``CalendarDate/clamping(year:month:day:)``. The same clamping is why the
iOS app's reminder recurrence uses "last day of the month" for anything due on the 29th or later.

## Periods

``PeriodKey`` stamps which period a payment settled. The format depends on the cycle — `2026-09` for
a monthly bill, `2026-W37` for a fortnightly one, a bare `2026` for a yearly one — and it is opaque
everywhere else. Nothing outside ``PeriodKey`` parses it, including the database, which stores it as
a plain string.

## Two deliberate differences from the Python application

Both are bug fixes agreed before the rewrite began, not redesigns. They are listed here as well as
in the repository README because anyone comparing figures between the two applications will hit them.

**Fortnightly bills count towards the budget.** The old application included them in the category
breakdown but left them out of the monthly budget and the reserve, so a fortnightly bill vanished
from the headline figure while still appearing in the chart beneath it.

**Marking a non-monthly bill as paid registers.** The old pay endpoint stamped a bare year on every
non-monthly expense, while its status check compared quarterly bills against a year-and-month key.
The two never matched, so a quarterly bill could not be marked paid at all.
