# Practice I — From pixels to the integral

Functional programming with Haskell and logic programming with Prolog.  
ST0244 — Programming Paradigms, EAFIT University (Alexander Narváez, Aug 2026).

## Team members

- Andres Santiago Jaimes Mora
- Miguel Jimenez Moreno

## Development environment

- Windows 10
- GHC 9.8.2 (`runghc` / `ghc`)
- SWI-Prolog (run `swipl` from a terminal)

## Input file

`curva_binaria_P4.pbm` (PBM P4, binary). Do not convert it to a text matrix by hand. Both programs read this file directly.

## How to run — Haskell

From the repository root:

```bash
runghc Haskell/Main.hs curva_binaria_P4.pbm
```

Or compile:

```bash
ghc -O2 -o haskell-area Haskell/Main.hs
./haskell-area curva_binaria_P4.pbm
```

## How to run — Prolog

From the repository root:

```bash
swipl -q -t main -s Prolog/area.pl -- curva_binaria_P4.pbm
```

## Console strategy (large image)

The source image is larger than a terminal. Both programs use the same reduction:

- **Spatial sampling / block aggregation.** The bitmap is divided into blocks (about 72 columns × 22 rows of glyphs). Each glyph stands for a block of original pixels.
- A cell is drawn as `█` if a **majority** of a small sample inside that block is black (bit = 1 = region under the curve).
- The height function `M[x] = f(x)` is shown as a second chart: columns of `█` scaled to the maximum height, sampled horizontally so the bars fit the console.

The shape of the curve is preserved; individual pixels are not.

## Mathematics

For each column `x`, `f(x)` is the number of **consecutive black pixels from the bottom** until the first white pixel.

\[
M = [f(0), f(1), \ldots, f(n-1)], \qquad A = \sum_{i=0}^{n-1} f(x_i)\,\Delta x
\]

with \(\Delta x = 1\) pixel, so **area = `sum M`**, in square pixels.

- **Haskell:** `m = map f [0 .. width-1]` then `area = sum m` (transformations).
- **Prolog:** `f(X, ..., Altura)` as a relation, then `findall` + `sum_list` (values that satisfy the relation).

Both programs must print the **same area**.

## Area obtained

Both programs, on `curva_binaria_P4.pbm` (567 × 319):

- **Area: 108660 square pixels**
