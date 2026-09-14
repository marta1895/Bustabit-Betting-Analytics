CREATE TABLE bets (
  id BIGINT PRIMARY KEY,
  game_id BIGINT,
  username VARCHAR(50),
  bet DECIMAL(12,2),
  cashed_out DECIMAL(10,2),
  bonus DECIMAL(6,4),
  profit DECIMAL(12,2),
  busted_at DECIMAL(10,2),
  play_date TIMESTAMP
);

ALTER TABLE bets
DROP COLUMN cashed_out,
DROP COLUMN gameid,
DROP COLUMN bustedat,
DROP COLUMN playdate;

SELECT * FROM bets;

-- =========Analysis===========

-- (1.) -- Among users whose first observed bet falls in the early part of the window, 
--         does the outcome of their first bet (win vs bust) predict whether they return in the following days? 
WITH ranked_bets AS (
    SELECT
        username,
        play_date,
        cashedout,
        -- using window function to find which row is this user's first bet
        ROW_NUMBER() OVER (PARTITION BY username ORDER BY play_date) AS bet_rank
    FROM bets
),
early_users_games AS (
    SELECT
        username,
        play_date AS first_bet_date,
        -- outcome win or bust at the user's first bet
        CASE WHEN cashedout IS NULL THEN 'bust' ELSE 'win' END AS bet_outcome,
        -- defining early user, the users whose first observed bet falls in the early part of the window, in this case first week of available play dates
        CASE WHEN play_date < '2016-11-06' THEN 'Yes' ELSE 'No' END AS early_user
    FROM ranked_bets
    WHERE bet_rank = 1
),
-- finding early users and their days offset between each next bet and first bet date
user_bets AS (
    SELECT
        b.username,
        b.play_date,
        eu.first_bet_date,
        eu.bet_outcome,
        eu.early_user,
        DATE(b.play_date) - DATE(eu.first_bet_date) AS day_offset -- how many days after joining this bet happened
    FROM bets b
    JOIN early_users_games eu ON b.username = eu.username
    WHERE eu.early_user = 'Yes' -- filtering only defined early users for full 30 days analysis
),
-- counting distinct users who returned at day 1 / 7 / 30 based on bet outcome
cohorts AS (
    SELECT 
    	bet_outcome,
        COUNT(DISTINCT CASE WHEN day_offset = 1 THEN username END) AS day1_cohort,
        COUNT(DISTINCT CASE WHEN day_offset = 7 THEN username END) AS day7_cohort,
        COUNT(DISTINCT CASE WHEN day_offset = 30 THEN username END) AS day30_cohort
    FROM user_bets
    GROUP BY bet_outcome
),
-- finding the total number of unqiue early users based on bet outcome
early_users_total AS (
	SELECT
		bet_outcome,
		COUNT(DISTINCT username) AS total_early_user
	FROM early_users_games
    WHERE early_user = 'Yes'
    GROUP BY bet_outcome
)
-- joining the last two cte on bet_outcome to get retention pct grouped by win/bust
SELECT 
    c.bet_outcome,
 	c.day1_cohort,
    c.day7_cohort,
    c.day30_cohort,
    t.total_early_user,
    ROUND(100.0 * c.day1_cohort / t.total_early_user, 2) AS day1_retention_pct,
    ROUND(100.0 * c.day7_cohort / t.total_early_user, 2) AS day7_retention_pct,
    ROUND(100.0 * c.day30_cohort / t.total_early_user, 2) AS day30_retention_pct
FROM cohorts c
JOIN early_users_total t ON c.bet_outcome = t.bet_outcome;
-- RESULT: first bet outcome doesn't really predict retention, day1 and day7 are basically the same for win vs bust
-- day30 shows losers coming back slightly more than winners, but with only 437 vs 646 users
-- in each group, could just be noise, not a real pattern



-- (2.) -- What does the DAU/WAU trend look like across the ~41-day window — growing, flat, declining?

WITH dau_calc AS ( -- Daily Active User count
    SELECT
        DATE(play_date) AS day,
        COUNT(DISTINCT username) AS dau
    FROM bets
    GROUP BY DATE(play_date)
)
SELECT
    day,
    dau,
    dau - LAG(dau) OVER (ORDER BY day) AS dau_diff
FROM dau_calc
ORDER BY day;

WITH wau_calc AS ( -- Weekly Active Users count
	SELECT 
    	DATE_TRUNC('week', play_date)::DATE AS week_start,
    	COUNT(DISTINCT username) AS wau
	FROM bets
	GROUP BY week_start
)
SELECT 
	week_start,
	wau,
	wau - LAG(wau) OVER (ORDER BY week_start) AS wau_diff
FROM wau_calc
ORDER BY week_start;
-- SUMMARY: dau/wau goes up and down a lot day to day, no big drop or big growth overall
-- first day is low but that's because data starts mid-day, not real
-- goes up first ~10 days, then goes down through mid-november, then goes up again
-- little bit end of nov/start of dec, then goes down again at the end
-- but last week is also partial so that last drop is not fully real either
-- overall looks pretty flat, maybe slightly going down, but nothing big happening either way



-- (3). -- DAU/WAU Ratio (User Stickiness)

WITH user_cnt_per_day AS (
    SELECT
        DATE(play_date) AS day,
        DATE_TRUNC('week', play_date)::DATE AS week_start, -- tag each day with its week, so DAU can be joined to WAU
        COUNT(DISTINCT username) AS dau
    FROM bets
    GROUP BY DATE(play_date), DATE_TRUNC('week', play_date)::DATE
),
avg_dau_per_week AS (
    SELECT
        week_start,
        AVG(dau) AS avg_dau
    FROM user_cnt_per_day
    GROUP BY week_start
),
user_cnt_per_week AS (
    SELECT
        DATE_TRUNC('week', play_date)::DATE AS week_start,
        COUNT(DISTINCT username) AS wau
    FROM bets
    GROUP BY DATE_TRUNC('week', play_date)::DATE
)
SELECT
    a.week_start,
    a.avg_dau,
    w.wau,
    ROUND(a.avg_dau / w.wau, 3) AS stickiness_ratio
FROM avg_dau_per_week a
JOIN user_cnt_per_week w ON a.week_start = w.week_start
ORDER BY a.week_start;
-- SUMMARY: stickiness stays pretty much the same every week, around 0.32-0.36
-- so even when total dau/wau goes up and down like we saw before, the users who are
-- active still come back at about the same rate. means the ups and downs in activity
-- are more about how many people show up total, not about people getting more or less engaged



-- (4.) -- Inactivity investigation

-- checking this first before deciding on a threshold, want to see where the buckets actually split
WITH user_activity AS ( -- Distribution of users by days since last bet at the end of the observation period
    SELECT
        username,
        MAX(play_date)::date AS last_bet_date
    FROM bets
    GROUP BY username
),
dataset AS (
    SELECT 
    	MAX(play_date)::date AS dataset_end
    FROM bets
)
SELECT
    CASE -- creating cohorts for inactivity buckets
        WHEN dataset_end - last_bet_date < 7 THEN '0-6 days'
        WHEN dataset_end - last_bet_date < 14 THEN '7-13 days'
        WHEN dataset_end - last_bet_date < 30 THEN '14-29 days'
        WHEN dataset_end - last_bet_date < 60 THEN '30-59 days'
        ELSE '60+ days'
    END AS inactivity_bucket,
    COUNT(*) AS users
FROM user_activity
CROSS JOIN dataset
GROUP BY inactivity_bucket
ORDER BY inactivity_bucket;


WITH user_activity AS ( -- 7-day end-of-period inactivity rate
    SELECT
        username,
        MAX(play_date)::date AS last_bet_date
    FROM bets
    GROUP BY username
),
dataset AS (
    SELECT MAX(play_date)::date AS dataset_end
    FROM bets
),
user_inactivity AS (
    SELECT
        ua.username,
        CASE
            WHEN d.dataset_end - ua.last_bet_date >= 7 THEN 1
            ELSE 0
        END AS inactive_7d_plus
    FROM user_activity ua
    CROSS JOIN dataset d
)
SELECT
    COUNT(*) AS total_users,
    SUM(inactive_7d_plus) AS inactive_users_7d_plus,
    ROUND(
        100.0 * SUM(inactive_7d_plus) / COUNT(*),
        2
    ) AS inactivity_rate_pct
FROM user_inactivity;
-- A 7-day inactivity threshold was tested; however, because the dataset ends at a fixed observation date,
-- users classified as inactive may subsequently return. Therefore, this metric should not be interpreted as confirmed churn



-- (5.) -- What is the customer lifetime value (LTV) for the early-joiner cohort?

-- When I computed LTV value, it turned out significant negative for this cohort, which at first looked like the company is losing money
-- I decided to divide the ltv calculation into two groups: including and excluding self-defined extreme-loss outliers

-- checked top 10-20 users by lowest revenue, no clear jump anywhere, losses just get smaller little by little
-- so -500,000 is not some exact statistical cutoff, just a round number i picked as "extreme"
WITH user_stats AS (
    SELECT
        username,
        SUM(CASE WHEN cashedout IS NULL THEN bet ELSE -profit END) AS revenue
    FROM bets
    GROUP BY username
)
SELECT COUNT(*) AS num_outliers
FROM user_stats
WHERE revenue <= -500000;

-- LTV computing
WITH user_stats AS (
    SELECT
        username,
        MIN(play_date) AS start_date,
        MAX(play_date)::date - MIN(play_date)::date AS lifespan_days,
        SUM(CASE WHEN cashedout IS NULL THEN bet ELSE -profit END) AS revenue
    FROM bets
    GROUP BY username
),
-- Computing the LTV value by including extreme-loss outliers
cohort_ltv_total AS (
    SELECT
        ROUND(SUM(revenue) / COUNT(DISTINCT username), 2) AS ltv
    FROM user_stats
    WHERE (start_date BETWEEN '2016-10-31' AND '2016-11-06')
    AND lifespan_days > 5 
),
-- Computing the LTV value by excluding extreme-loss outliers
cohort_ltv_filtered AS (
    SELECT
        ROUND(SUM(revenue) / COUNT(DISTINCT username), 2) AS ltv
    FROM user_stats
    WHERE (start_date BETWEEN '2016-10-31' AND '2016-11-06')
    AND lifespan_days > 5
    AND revenue > -500000 -- chose -500,000 as the cutoff; confirmed with a count query that exactly 6 users fall below it, consistent with the small number of extreme outliers seen in the min/max check earlier
)
SELECT 'ltv_with_outliers' AS ltv_type, ltv FROM cohort_ltv_total    
    UNION ALL
SELECT 'ltv_without_outliers' AS ltv_type, ltv FROM cohort_ltv_filtered;
   
-- Additionally I decided to find Gross Gaming Revenue (GGR) by applying the same groups:
-- including and excluding self-defined extreme-loss outliers
WITH user_stats AS (
    SELECT
        username,
        play_date,
        SUM(CASE WHEN cashedout IS NULL THEN bet ELSE -profit END) AS revenue
    FROM bets
    GROUP BY username, play_date
),
total_ggr_all AS (
    SELECT SUM(revenue) AS total_ggr
    FROM user_stats
),
total_ggr_filtered AS (
    SELECT SUM(revenue) AS total_ggr
    FROM user_stats
    WHERE revenue > -500000
)
SELECT 'ggr_with_outliers' AS ggr_type, total_ggr FROM total_ggr_all
UNION ALL
SELECT 'ggr_without_outliers' AS ggr_type, total_ggr FROM total_ggr_filtered; 
-- SUMMARY:
-- Raw GGR for the whole 41-day window comes out negative (-$2.29M), which looks like
-- the platform is losing money. Turns out that's driven by just 6 users out of ~4,000
-- who hit huge multiplier wins, together accounting for over $8M in payouts.
-- Excluding those 6, GGR flips to +$6M+, which lines up with what you'd expect from
-- normal house-edge behavior. Same pattern shows up in the early-joiner cohort's LTV:
-- negative overall, but that's one extreme user in a 623-person group, not the cohort
-- actually losing money on average.


-- (6). -- ARPU/ARPPU by segment (bet-size tier, or session-frequency tier) 
--         Is platform revenue coming from a lot of regular users, or mostly from a small group of high rollers?

-- =========================================================
-- MAIN QUERY: ARPU by bet-size tier and tenure tier, outliers excluded

WITH user_bets AS ( --first cte, finding avg bet and revenue per user
    SELECT
        username,
        AVG(bet) AS avg_bet,
        SUM(CASE WHEN cashedout IS NULL THEN bet ELSE -profit END) AS revenue
    FROM bets
    GROUP BY username
),
bet_size_arpu AS (
    SELECT
        'bet_size' AS segment_type, -- creating allieas that will help define segment type for better readability
        tier_size,
        total_revenue,
        active_users,
        arpu
    FROM (
        SELECT
            CASE --defining bet sizes
                WHEN avg_bet BETWEEN 0 AND 999 THEN 'Small Bet-Size Tier'
                WHEN avg_bet BETWEEN 1000 AND 9999 THEN 'Medium Bet-Size Tier'
                WHEN avg_bet BETWEEN 10000 AND 199999 THEN 'Large Bet-Size Tier'
                WHEN avg_bet BETWEEN 200000 AND 1000000 THEN 'Very Large Bet-Size Tier'
            END AS tier_size,
            SUM(revenue) AS total_revenue,
            COUNT(DISTINCT username) AS active_users,
            ROUND(SUM(revenue) / COUNT(DISTINCT username), 2) AS arpu
        FROM user_bets
        WHERE revenue > -500000
        GROUP BY tier_size
        )
),
user_stats AS ( -- before defining tenure sizes, I had to find lifespan for each user
    SELECT
        username,
        MAX(play_date)::date - MIN(play_date)::date AS lifespan_days,
        SUM(CASE WHEN cashedout IS NULL THEN bet ELSE -profit END) AS revenue
    FROM bets
    GROUP BY username
),
tenure_size_arpu AS (
    SELECT
        'tenure' AS segment_type, -- creating allieas that will help define segment type for better readability
        tier_size,
        total_revenue,
        active_users,
        arpu
    FROM (
        SELECT
            CASE -- defining lifespans
                WHEN lifespan_days <= 7  THEN 'Small Tenure Size Tier'
                WHEN lifespan_days <= 14 THEN 'Medium Tenure Size Tier'
                WHEN lifespan_days <= 30 THEN 'Large Tenure Size Tier'
                WHEN lifespan_days <= 60 THEN 'Very Large Tenure Size Tier'
                ELSE 'Extra Large Tenure Size Tier'
            END AS tier_size,
            SUM(revenue) AS total_revenue,
            COUNT(*) AS active_users,
            ROUND(SUM(revenue) / COUNT(*), 2) AS arpu
        FROM user_stats
        WHERE revenue > -500000
        GROUP BY tier_size
        )
)
SELECT * FROM bet_size_arpu
UNION ALL
SELECT * FROM tenure_size_arpu
ORDER BY arpu DESC;
-- RESULT: bet_size tiers show revenue concentrated in Very Large Bet-Size Tier (few users, high ARPU), 
-- while Small/Medium bet-size tiers are slightly negative.
-- Tenure tiers: Small Tenure is solidly positive, but Large/Very Large came out negative
-- See investigation below:

-- After building arpu by bet-size and tenure tier with the top 6 outliers already excluded,
-- Large and Very Large tenure tiers still came out strongly negative.
-- That was surprising since I'd already pulled the biggest outliers out, so I wanted
-- to check whether this is a real tenure effect or just leftover outliers I hadn't accounted for

-- =========================================================
-- SECONDARY OUTLIER CHECK: even after removing the top 6 outliers, Large/Very Large
-- tenure tiers were still negative. Checking next-worst losses split by tenure:
-- >30 days vs <30 days to see if it's a tenure thing or not

WITH user_stats AS (
    SELECT
        username,
        MAX(play_date)::date - MIN(play_date)::date AS lifespan_days,
        SUM(CASE WHEN cashedout IS NULL THEN bet ELSE -profit END) AS revenue
    FROM bets
    GROUP BY username
)
SELECT username, revenue
FROM user_stats
WHERE lifespan_days > 30   -- switch to < 30 to check the other side
  AND revenue > -500000    -- excluding the known 6 outliers
ORDER BY revenue ASC
LIMIT 10;

-- RESULT: losses in the -100K to -400K range show up on both sides pretty evenly,
-- so it's not tenure-driven. Those tenure tiers are just smaller groups, so a few big losses
-- pull the average down more than they would in a bigger tier like Small Tenure.



-- (7.) -- Average bet and total revenue by game outcome

SELECT
	CASE WHEN cashedout IS NULL THEN 'bust' ELSE 'win' END AS bet_outcome,
	AVG(bet) AS avg_bet,
	SUM(CASE WHEN cashedout IS NULL THEN bet ELSE -profit END) AS revenue_by_outcome
FROM bets
GROUP BY bet_outcome;



-- (8.) -- Daily GGR

WITH daily_user_revenue AS (
    SELECT
        username,
        DATE(play_date) AS day,
        SUM(CASE WHEN cashedout IS NULL THEN bet ELSE -profit END) AS revenue
    FROM bets
    GROUP BY username, DATE(play_date)
),
daily_ggr_all AS (
    SELECT
        day,
        SUM(revenue) AS ggr_per_day
    FROM daily_user_revenue
    GROUP BY day
)
SELECT
	day,
	ggr_per_day,
	SUM(ggr_per_day) OVER (ORDER BY day) AS cumulative_ggr
FROM daily_ggr_all
ORDER BY day;



-- (9.) -- Number of Bets

SELECT
    COUNT(*) AS total_bets,
    COUNT(*) FILTER (WHERE cashedout IS NULL) AS bust_bets,
    COUNT(*) FILTER (WHERE cashedout IS NOT NULL) AS win_bets,
    ROUND(100.0 * COUNT(*) FILTER (WHERE cashedout IS NOT NULL) / COUNT(*), 2) AS win_rate_pct
FROM bets;


-- (10.) -- Total unique users for whole time window of 41 days

SELECT 
	COUNT(DISTINCT username) AS unique_user_count
FROM bets;


select max(play_date) from bets;
SELECT 
	COUNT(DISTINCT username) AS total_users,
	COUNT(DISTINCT CASE WHEN play_date::date = '2016-11-06' THEN username END) AS user_cnt_begining,
	COUNT(DISTINCT CASE WHEN play_date::date = '2016-12-10' THEN username END) AS user_cnt_end
FROM bets;



-- (11.) -- Median Bet
SELECT
    MIN(bet) AS min_bet,
    MAX(bet) AS max_bet,
    AVG(bet) AS avg_bet,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY bet) AS median_bet
FROM bets;


-- (12.) -- Average Bet
SELECT 
	AVG(bet) AS avg_bet
FROM bets;