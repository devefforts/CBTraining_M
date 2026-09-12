-- Vayu Air Session 3 — working assignment solution
-- TrainingCBDB. Run in order. Q5/Q6 change dw tables.

USE TrainingCBDB;
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'dw')
    EXEC('CREATE SCHEMA dw');
GO


-- =============================================================================
-- TASK 1 — Grain + classify bronze_bookings (joined to flight)
-- =============================================================================
/*
GRAIN: one row in FactTicketSales = one booking = one ticket sold for one flight
       (one passenger, one flight_id, one booking_id).

Dimension keys (who / what / where / when — join to a dimension or stay degenerate):
  booking_id              degenerate on the fact (identifies the ticket)
  passenger_id            -> DimPassenger
  flight_id               -> DimFlight
  booking_date            -> DimDate (BookingDateKey)
  travel_date             -> DimDate (TravelDateKey)
  fare_class              degenerate (Economy / Premium Economy / Business / First)
  booking_status          degenerate (Confirmed / Cancelled / NoShow)
  From the flight: origin_airport_code, dest_airport_code -> DimAirport (role-playing)
                   aircraft_code -> DimAircraft
                   flight_date (same idea as travel_date; kept on DimFlight)

Measures (numbers):
  fare_amount     additive — SUM is valid
  tax_amount      additive — SUM is valid
  miles_earned    additive — SUM is valid

Additive vs not:
  Fare, tax and miles are additive (you can SUM across routes, months, tiers).
  A non-additive example: average fare (AVG), or seat_capacity if it were copied onto the fact
  (you must not SUM seats across tickets).
*/


-- =============================================================================
-- TASK 2 — Star schema DDL (surrogate keys on dims, FKs on fact, additive measures only)
-- =============================================================================

IF OBJECT_ID('dw.FactTicketSales', 'U') IS NOT NULL DROP TABLE dw.FactTicketSales;
IF OBJECT_ID('dw.DimAirportSnow', 'U') IS NOT NULL DROP TABLE dw.DimAirportSnow;
IF OBJECT_ID('dw.DimAirport', 'U') IS NOT NULL DROP TABLE dw.DimAirport;
IF OBJECT_ID('dw.DimCity', 'U') IS NOT NULL DROP TABLE dw.DimCity;
IF OBJECT_ID('dw.DimCountry', 'U') IS NOT NULL DROP TABLE dw.DimCountry;
IF OBJECT_ID('dw.DimAircraft', 'U') IS NOT NULL DROP TABLE dw.DimAircraft;
IF OBJECT_ID('dw.DimFlight', 'U') IS NOT NULL DROP TABLE dw.DimFlight;
IF OBJECT_ID('dw.DimPassenger', 'U') IS NOT NULL DROP TABLE dw.DimPassenger;
IF OBJECT_ID('dw.DimDate', 'U') IS NOT NULL DROP TABLE dw.DimDate;
GO

CREATE TABLE dw.DimDate (
    DateKey     INT           NOT NULL PRIMARY KEY,  -- yyyymmdd
    FullDate    DATE          NOT NULL,
    [Year]      INT           NOT NULL,
    [Month]     INT           NOT NULL,
    MonthName   NVARCHAR(20)  NOT NULL,
    [Day]       INT           NOT NULL,
    Quarter     INT           NOT NULL
);

CREATE TABLE dw.DimPassenger (
    PassengerKey        INT           IDENTITY(1,1) NOT NULL PRIMARY KEY, -- surrogate
    PassengerId         BIGINT        NOT NULL,  -- business key (stable)
    PassengerName       NVARCHAR(255) NOT NULL,
    HomeAirportCode     NVARCHAR(10)  NULL,
    FrequentFlyerTier   NVARCHAR(50)  NULL,
    SignupDate          DATE          NULL,
    IsCurrent           BIT           NOT NULL CONSTRAINT DF_DimPassenger_IsCurrent DEFAULT (1),
    EffectiveFrom       DATE          NOT NULL CONSTRAINT DF_DimPassenger_From DEFAULT ('1900-01-01'),
    EffectiveTo         DATE          NOT NULL CONSTRAINT DF_DimPassenger_To DEFAULT ('9999-12-31')
);

CREATE TABLE dw.DimAircraft (
    AircraftKey    INT           IDENTITY(1,1) NOT NULL PRIMARY KEY,
    AircraftCode   NVARCHAR(50)  NOT NULL,  -- business key
    Model          NVARCHAR(255) NULL,
    Manufacturer   NVARCHAR(255) NULL,
    SeatCapacity   INT           NULL
);

CREATE TABLE dw.DimAirport (
    AirportKey    INT           IDENTITY(1,1) NOT NULL PRIMARY KEY,
    AirportCode   NVARCHAR(10)  NOT NULL,  -- business key (IATA)
    AirportName   NVARCHAR(255) NULL,
    City          NVARCHAR(255) NULL,
    Country       NVARCHAR(255) NULL,
    Region        NVARCHAR(255) NULL
);

CREATE TABLE dw.DimFlight (
    FlightKey           INT           IDENTITY(1,1) NOT NULL PRIMARY KEY,
    FlightId            BIGINT        NOT NULL,  -- business key
    FlightNumber        NVARCHAR(50)  NULL,
    OriginAirportCode   NVARCHAR(10)  NULL,
    DestAirportCode     NVARCHAR(10)  NULL,
    AircraftCode        NVARCHAR(50)  NULL,
    FlightDate          DATE          NULL
);

CREATE TABLE dw.FactTicketSales (
    FactTicketSalesKey  BIGINT         IDENTITY(1,1) NOT NULL,
    BookingId           BIGINT         NOT NULL,          -- degenerate
    PassengerKey        INT            NOT NULL,
    FlightKey           INT            NOT NULL,
    OriginAirportKey    INT            NOT NULL,
    DestAirportKey      INT            NOT NULL,
    AircraftKey         INT            NOT NULL,
    BookingDateKey      INT            NOT NULL,
    TravelDateKey       INT            NOT NULL,          -- partition key (Q6)
    FareClass           NVARCHAR(50)   NULL,              -- degenerate
    BookingStatus       NVARCHAR(50)   NULL,              -- degenerate
    FareAmount          DECIMAL(18,2)  NOT NULL,
    TaxAmount           DECIMAL(18,2)  NOT NULL,
    MilesEarned         BIGINT         NOT NULL,
    CONSTRAINT PK_FactTicketSales PRIMARY KEY NONCLUSTERED (FactTicketSalesKey),
    CONSTRAINT FK_Fact_Passenger      FOREIGN KEY (PassengerKey)     REFERENCES dw.DimPassenger (PassengerKey),
    CONSTRAINT FK_Fact_Flight         FOREIGN KEY (FlightKey)        REFERENCES dw.DimFlight (FlightKey),
    CONSTRAINT FK_Fact_OriginAirport  FOREIGN KEY (OriginAirportKey) REFERENCES dw.DimAirport (AirportKey),
    CONSTRAINT FK_Fact_DestAirport    FOREIGN KEY (DestAirportKey)   REFERENCES dw.DimAirport (AirportKey),
    CONSTRAINT FK_Fact_Aircraft       FOREIGN KEY (AircraftKey)      REFERENCES dw.DimAircraft (AircraftKey),
    CONSTRAINT FK_Fact_BookingDate    FOREIGN KEY (BookingDateKey)   REFERENCES dw.DimDate (DateKey),
    CONSTRAINT FK_Fact_TravelDate     FOREIGN KEY (TravelDateKey)    REFERENCES dw.DimDate (DateKey)
);
GO


-- =============================================================================
-- TASK 3 — Load dimensions (surrogate IDENTITY) and fact (join on business keys)
-- =============================================================================

-- DimDate: cover signup through travel dates
;WITH d AS (
    SELECT CAST('2021-01-01' AS DATE) AS FullDate
    UNION ALL
    SELECT DATEADD(DAY, 1, FullDate) FROM d WHERE FullDate < '2026-12-31'
)
INSERT INTO dw.DimDate (DateKey, FullDate, [Year], [Month], MonthName, [Day], Quarter)
SELECT YEAR(FullDate) * 10000 + MONTH(FullDate) * 100 + DAY(FullDate),
       FullDate,
       YEAR(FullDate),
       MONTH(FullDate),
       DATENAME(MONTH, FullDate),
       DAY(FullDate),
       DATEPART(QUARTER, FullDate)
FROM d
OPTION (MAXRECURSION 0);

INSERT INTO dw.DimPassenger (PassengerId, PassengerName, HomeAirportCode, FrequentFlyerTier, SignupDate, IsCurrent, EffectiveFrom, EffectiveTo)
SELECT passenger_id,
       passenger_name,
       REPLACE(home_airport_code, CHAR(13), N''),
       REPLACE(frequent_flyer_tier, CHAR(13), N''),
       signup_date,
       1,
       ISNULL(signup_date, '1900-01-01'),
       '9999-12-31'
FROM bronze_passengers;

INSERT INTO dw.DimAircraft (AircraftCode, Model, Manufacturer, SeatCapacity)
SELECT REPLACE(aircraft_code, CHAR(13), N''),
       REPLACE(model, CHAR(13), N''),
       REPLACE(manufacturer, CHAR(13), N''),
       CAST(seat_capacity AS INT)
FROM bronze_aircraft;

INSERT INTO dw.DimAirport (AirportCode, AirportName, City, Country, Region)
SELECT REPLACE(airport_code, CHAR(13), N''),
       REPLACE(airport_name, CHAR(13), N''),
       REPLACE(city, CHAR(13), N''),
       REPLACE(country, CHAR(13), N''),
       REPLACE(region, CHAR(13), N'')
FROM bronze_airports;

INSERT INTO dw.DimFlight (FlightId, FlightNumber, OriginAirportCode, DestAirportCode, AircraftCode, FlightDate)
SELECT flight_id,
       REPLACE(flight_number, CHAR(13), N''),
       REPLACE(origin_airport_code, CHAR(13), N''),
       REPLACE(dest_airport_code, CHAR(13), N''),
       REPLACE(aircraft_code, CHAR(13), N''),
       flight_date
FROM bronze_flights;

INSERT INTO dw.FactTicketSales (
    BookingId, PassengerKey, FlightKey, OriginAirportKey, DestAirportKey, AircraftKey,
    BookingDateKey, TravelDateKey, FareClass, BookingStatus, FareAmount, TaxAmount, MilesEarned
)
SELECT b.booking_id,
       p.PassengerKey,
       f.FlightKey,
       orig.AirportKey,
       dest.AirportKey,
       a.AircraftKey,
       YEAR(b.booking_date) * 10000 + MONTH(b.booking_date) * 100 + DAY(b.booking_date),
       YEAR(b.travel_date)  * 10000 + MONTH(b.travel_date)  * 100 + DAY(b.travel_date),
       REPLACE(b.fare_class, CHAR(13), N''),
       REPLACE(b.booking_status, CHAR(13), N''),
       b.fare_amount,
       b.tax_amount,
       b.miles_earned
FROM bronze_bookings b
INNER JOIN dw.DimPassenger p ON p.PassengerId = b.passenger_id AND p.IsCurrent = 1
INNER JOIN dw.DimFlight    f ON f.FlightId = b.flight_id
INNER JOIN dw.DimAirport orig ON orig.AirportCode = f.OriginAirportCode
INNER JOIN dw.DimAirport dest ON dest.AirportCode = f.DestAirportCode
INNER JOIN dw.DimAircraft  a ON a.AircraftCode = f.AircraftCode;

-- Verify: fact rows = bronze_bookings; every fact row has all dimension keys
SELECT (SELECT COUNT(*) FROM bronze_bookings) AS bronze_bookings,
       (SELECT COUNT(*) FROM dw.FactTicketSales) AS fact_rows;

SELECT COUNT(*) AS fact_rows_missing_a_dimension
FROM dw.FactTicketSales
WHERE PassengerKey IS NULL OR FlightKey IS NULL OR OriginAirportKey IS NULL
   OR DestAirportKey IS NULL OR AircraftKey IS NULL
   OR BookingDateKey IS NULL OR TravelDateKey IS NULL;
GO


-- =============================================================================
-- TASK 4 — Snowflake geography: country <- city <- airport
-- =============================================================================

IF OBJECT_ID('dw.DimAirportSnow', 'U') IS NOT NULL DROP TABLE dw.DimAirportSnow;
IF OBJECT_ID('dw.DimCity', 'U') IS NOT NULL DROP TABLE dw.DimCity;
IF OBJECT_ID('dw.DimCountry', 'U') IS NOT NULL DROP TABLE dw.DimCountry;
GO

CREATE TABLE dw.DimCountry (
    CountryKey  INT           IDENTITY(1,1) NOT NULL PRIMARY KEY,
    Country     NVARCHAR(255) NOT NULL,
    Region      NVARCHAR(255) NULL
);

CREATE TABLE dw.DimCity (
    CityKey     INT           IDENTITY(1,1) NOT NULL PRIMARY KEY,
    City        NVARCHAR(255) NOT NULL,
    CountryKey  INT           NOT NULL,
    CONSTRAINT FK_DimCity_Country FOREIGN KEY (CountryKey) REFERENCES dw.DimCountry (CountryKey)
);

CREATE TABLE dw.DimAirportSnow (
    AirportKey   INT           IDENTITY(1,1) NOT NULL PRIMARY KEY,
    AirportCode  NVARCHAR(10)  NOT NULL,
    AirportName  NVARCHAR(255) NULL,
    CityKey      INT           NOT NULL,
    CONSTRAINT FK_DimAirportSnow_City FOREIGN KEY (CityKey) REFERENCES dw.DimCity (CityKey)
);
GO

INSERT INTO dw.DimCountry (Country, Region)
SELECT DISTINCT
       REPLACE(country, CHAR(13), N''),
       REPLACE(region, CHAR(13), N'')
FROM bronze_airports;

INSERT INTO dw.DimCity (City, CountryKey)
SELECT DISTINCT
       REPLACE(a.city, CHAR(13), N''),
       c.CountryKey
FROM bronze_airports a
INNER JOIN dw.DimCountry c ON c.Country = REPLACE(a.country, CHAR(13), N'');

INSERT INTO dw.DimAirportSnow (AirportCode, AirportName, CityKey)
SELECT REPLACE(a.airport_code, CHAR(13), N''),
       REPLACE(a.airport_name, CHAR(13), N''),
       ci.CityKey
FROM bronze_airports a
INNER JOIN dw.DimCity ci ON ci.City = REPLACE(a.city, CHAR(13), N'')
INNER JOIN dw.DimCountry co ON co.CountryKey = ci.CountryKey
                           AND co.Country = REPLACE(a.country, CHAR(13), N'');

-- Airport all the way up to country
SELECT ap.AirportCode, ap.AirportName, ci.City, co.Country, co.Region
FROM dw.DimAirportSnow ap
INNER JOIN dw.DimCity ci ON ci.CityKey = ap.CityKey
INNER JOIN dw.DimCountry co ON co.CountryKey = ci.CountryKey
ORDER BY co.Country, ci.City, ap.AirportCode;

-- Trade-off: snowflake stores city/country once (less repetition, easier geo hierarchy)
-- but every airport-to-country question needs extra joins. Star DimAirport is simpler for reports.
GO


-- =============================================================================
-- TASK 5 — SCD Type 2 on DimPassenger from stg_passenger_updates
-- Two-pass: (1) MERGE expire changed + insert brand-new
--           (2) INSERT new current version for rows just expired
-- =============================================================================

DECLARE @as_of DATE = '2026-04-01';  -- after the last travel date; feed date for this batch

-- Clean staging (CSV leftover CHAR(13) on tier)
IF OBJECT_ID('tempdb..#stg_pax') IS NOT NULL DROP TABLE #stg_pax;
SELECT passenger_id,
       REPLACE(passenger_name, CHAR(13), N'') AS passenger_name,
       REPLACE(home_airport_code, CHAR(13), N'') AS home_airport_code,
       REPLACE(frequent_flyer_tier, CHAR(13), N'') AS frequent_flyer_tier
INTO #stg_pax
FROM stg_passenger_updates;

-- Pass 1: expire current rows whose tier or home airport changed; insert brand-new passengers
MERGE dw.DimPassenger AS t
USING #stg_pax AS s
ON t.PassengerId = s.passenger_id AND t.IsCurrent = 1
WHEN MATCHED AND (
        ISNULL(t.FrequentFlyerTier, N'') <> ISNULL(s.frequent_flyer_tier, N'')
     OR ISNULL(t.HomeAirportCode, N'') <> ISNULL(s.home_airport_code, N'')
) THEN
    UPDATE SET t.IsCurrent = 0,
               t.EffectiveTo = DATEADD(DAY, -1, @as_of)
WHEN NOT MATCHED BY TARGET THEN
    INSERT (PassengerId, PassengerName, HomeAirportCode, FrequentFlyerTier, SignupDate, IsCurrent, EffectiveFrom, EffectiveTo)
    VALUES (s.passenger_id, s.passenger_name, s.home_airport_code, s.frequent_flyer_tier, @as_of, 1, @as_of, '9999-12-31');

-- Pass 2: open a new current version for everyone we just expired
INSERT INTO dw.DimPassenger (PassengerId, PassengerName, HomeAirportCode, FrequentFlyerTier, SignupDate, IsCurrent, EffectiveFrom, EffectiveTo)
SELECT s.passenger_id,
       s.passenger_name,
       s.home_airport_code,
       s.frequent_flyer_tier,
       p.SignupDate,
       1,
       @as_of,
       '9999-12-31'
FROM #stg_pax s
INNER JOIN dw.DimPassenger p
        ON p.PassengerId = s.passenger_id
       AND p.IsCurrent = 0
       AND p.EffectiveTo = DATEADD(DAY, -1, @as_of)
WHERE NOT EXISTS (
    SELECT 1
    FROM dw.DimPassenger x
    WHERE x.PassengerId = s.passenger_id
      AND x.IsCurrent = 1
);

-- Verify: a changed passenger has two versions; new passengers have one current row
SELECT PassengerId, PassengerKey, FrequentFlyerTier, HomeAirportCode, IsCurrent, EffectiveFrom, EffectiveTo
FROM dw.DimPassenger
WHERE PassengerId IN (
    SELECT TOP 1 passenger_id FROM #stg_pax s
    WHERE EXISTS (SELECT 1 FROM bronze_passengers b WHERE b.passenger_id = s.passenger_id)
)
ORDER BY PassengerId, EffectiveFrom;

SELECT 'changed_passengers_with_2_versions' AS check_name, COUNT(*) AS n
FROM (
    SELECT PassengerId
    FROM dw.DimPassenger
    GROUP BY PassengerId
    HAVING COUNT(*) = 2
) x
UNION ALL
SELECT 'new_passengers_current_only', COUNT(*)
FROM dw.DimPassenger p
WHERE p.IsCurrent = 1
  AND NOT EXISTS (SELECT 1 FROM bronze_passengers b WHERE b.passenger_id = p.PassengerId);
GO


-- =============================================================================
-- TASK 6 — Partition FactTicketSales by TravelDateKey (monthly RANGE RIGHT)
-- Then two queries: partition-key filter (prunes) vs other column (does not)
-- Turn on Include Actual Execution Plan in SSMS. Look at Actual Partition Count.
-- =============================================================================

IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'CX_FactTicketSales' AND object_id = OBJECT_ID('dw.FactTicketSales'))
    DROP INDEX CX_FactTicketSales ON dw.FactTicketSales;

IF EXISTS (SELECT 1 FROM sys.partition_schemes WHERE name = 'ps_TicketSalesDate')
    DROP PARTITION SCHEME ps_TicketSalesDate;

IF EXISTS (SELECT 1 FROM sys.partition_functions WHERE name = 'pf_TicketSalesDate')
    DROP PARTITION FUNCTION pf_TicketSalesDate;
GO

CREATE PARTITION FUNCTION pf_TicketSalesDate (INT)
AS RANGE RIGHT FOR VALUES (
    20250101, 20250201, 20250301, 20250401, 20250501, 20250601,
    20250701, 20250801, 20250901, 20251001, 20251101, 20251201,
    20260101, 20260201, 20260301, 20260401
);

CREATE PARTITION SCHEME ps_TicketSalesDate
AS PARTITION pf_TicketSalesDate ALL TO ([PRIMARY]);

CREATE CLUSTERED INDEX CX_FactTicketSales
ON dw.FactTicketSales (TravelDateKey)
ON ps_TicketSalesDate (TravelDateKey);
GO

-- Query A: filter on the partition key -> plan should show a SMALL Actual Partition Count
SELECT SUM(FareAmount) AS jun_2025_fare
FROM dw.FactTicketSales
WHERE TravelDateKey >= 20250601
  AND TravelDateKey <  20250701
  AND BookingStatus = N'Confirmed';

-- Query B: filter on a non-partition column only -> plan should touch ALL partitions
SELECT SUM(FareAmount) AS confirmed_fare
FROM dw.FactTicketSales
WHERE BookingStatus = N'Confirmed';

-- Why: the clustered index / table is aligned on TravelDateKey. SQL Server can
-- eliminate partitions only when the WHERE clause uses that key. BookingStatus
-- is not the partition column, so every partition must be read.
GO


-- =============================================================================
-- TASK 7 — Medallion map + data contract (written)
-- =============================================================================
/*
(a) Medallion layer for every table in this pipeline

  bronze_airports, bronze_aircraft, bronze_passengers, bronze_flights,
  bronze_bookings, stg_passenger_updates
      BRONZE — raw landed source, same grain and dirt as the booking system.

  dw.DimDate, dw.DimAircraft, dw.DimAirport, dw.DimFlight,
  dw.DimPassenger (after SCD2), dw.DimCountry, dw.DimCity, dw.DimAirportSnow
      SILVER — cleaned, conformed keys, history (SCD2) and snowflake geo.

  dw.FactTicketSales (partitioned star with surrogate FKs)
      GOLD — analysis-ready star that dashboards should query.

(b) Data contract for bronze_bookings

  Feed name:     bronze_bookings
  Owner:         Vayu Air Booking Systems / Analytics Engineering (Neha's team)
  Delivery:      daily batch by 06:00 IST; late if not landed by 07:00 IST (freshness SLA)
  Grain:         one row per ticket sold (booking_id unique)

  Schema / types:
    booking_id        INT / BIGINT   required, unique
    passenger_id      INT / BIGINT   required, FK to bronze_passengers
    flight_id         INT / BIGINT   required, FK to bronze_flights
    booking_date      DATE           required
    travel_date       DATE           required
    fare_class        VARCHAR        required, allowed: Economy, Premium Economy, Business, First
    fare_amount       DECIMAL(18,2)  required, >= 0
    tax_amount        DECIMAL(18,2)  required, >= 0
    booking_status    VARCHAR        required, allowed: Confirmed, Cancelled, NoShow
    miles_earned      INT            required, >= 0

  Breaking change example:     rename or drop fare_amount, or change allowed booking_status values.
  Non-breaking change example: add an optional column (e.g. promo_code NVARCHAR NULL).
*/
GO
