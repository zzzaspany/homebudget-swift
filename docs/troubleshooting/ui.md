# Interface problems

## Everything on the web client is too small, and `font-size` does not fix it

**Symptom.** Text renders at 16 px no matter what `font-size` is set on `body`. Raising it changes
almost nothing.

**Cause.** `rem` resolves against the **root** element, not against `body`. Every label in the
stylesheet is sized in `rem`, so setting `font-size` on `body` moved only the handful of things
sized in `em` or inherited directly.

Two wrong diagnoses came first, both worth recording because they wasted the time: it was blamed on
the viewport width (it is not — 1920×1200 is not a narrow screen), and then on the browser's default
zoom.

**Fix.**

```css
html { font-size: 18px; }
```

*Hit 2026-09-06.*

## The price-history chart's Y axis always starts at zero

**Symptom.** A bill that moved between 198 zł and 262 zł renders as a nearly flat line at the top of
an axis starting from 0, hiding the trend the chart exists to show.

**Cause.** `AreaMark` forces the baseline into the domain — that is what makes it an area rather
than a line. Setting the mark's style does not change it.

**Fix.** State the domain, and give the area an explicit start:

```swift
.chartYScale(domain: floor(minimum)...ceil(maximum))
AreaMark(x: ..., yStart: .value("", floor(minimum)), yEnd: .value("", amount))
```

*Hit 2026-09-07.*

## Summary cards leave half an iPad empty

**Symptom.** On iPad the four KPI cards huddle against the leading edge and their amounts wrap onto
two lines.

**Cause.** `GridItem(.adaptive(minimum:))` packs items at their minimum width rather than spreading
them.

**Fix.** Fixed column counts driven by the size class — two on a phone, four on an iPad — with
`GridItem(.flexible())`. See `DashboardScreen.summaryColumns`.
