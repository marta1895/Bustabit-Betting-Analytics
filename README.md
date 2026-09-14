# Bustabit Betting Analytics

SQL + Tableau analysis of 50,000 bets from ~4,000 users on the Bustabit crash-gambling platform (Oct 31 – Dec 10, 2016), built as a data analyst portfolio project.

**[View the live dashboard on Tableau Public →](https://public.tableau.com/app/profile/marta.narozhnyak/viz/Bets_17893773576350/BustabitBettingAnalytics)**
<img width="2558" height="1918" alt="image" src="https://github.com/user-attachments/assets/2b8ec5cb-b7bc-4371-8046-9e8a40b7ed83" />


## Dataset

- Source: [Gambling Behavior Bustabit](https://www.kaggle.com/datasets/kingabzpro/gambling-behavior-bustabit) (Kaggle)
- ~50,000 bets, ~4,000 users, 41-day window
- One row per bet: user, timestamp, stake, cashout, bonus, profit

## What's in this repo

- `bets_analysis.sql` — all analysis queries, with inline comments explaining logic and reasoning
- Tableau dashboard (linked above) — KPIs, trends, and segment breakdowns built from these queries

## Metrics covered

- **Retention (D1/D7/D30)** — do people come back after their first bet, and does winning or losing that first bet change anything
- **DAU / WAU** — how many people were active each day, and each week
- **Stickiness ratio** — of the people active in a week, how many show up on a typical day
- **Inactivity distribution** — how long since each user's last bet, grouped into buckets
- **LTV** — average revenue per early-joining user, with and without the extreme-loss users
- **GGR (Gross Gaming Revenue)** — total platform revenue, with and without the extreme-loss users
- **ARPU** — average revenue per user, split by bet size and by how long someone's been active
- **Bet outcome breakdown** — win rate, average bet size, and revenue split by win vs bust

## A few things worth knowing before reading the numbers

- **Outliers matter a lot here.** Raw GGR and LTV both come out negative — that's driven by 6 users (out of ~4,000) who hit large multiplier payouts. Every GGR/LTV number is reported both with and without these 6 users, not just one version.
- **"Inactive" ≠ confirmed churn.** The dataset has a fixed end date, so users flagged inactive may simply not have re-appeared yet within the window, so they're not necessarily gone.
- **First 30-day cohort is left-censored.** Users' first appearance in the dataset doesn't guarantee they're new to the platform — Bustabit existed before this window starts.
- **Session length/frequency wasn't included.** The raw data has no session start/end, so building sessions requires extra gap-based logic that was out of scope here.

## Tools

PostgreSQL (via DBeaver) for analysis, Tableau Desktop and Tableau Public for visualization.
