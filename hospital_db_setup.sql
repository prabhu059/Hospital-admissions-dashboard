USE HospitalDB;
SELECT COUNT(*) AS raw_rows FROM dbo.healthcare_dataset;

/* =====================================================================
   Hospital Analytics Project - SQL Server setup script
   Dataset: Kaggle "Healthcare Dataset" (prasad22), synthetic data
   Run each STEP one at a time in SSMS (select the code, press F5).
   ===================================================================== */

/* ---------------------------------------------------------------------
   STEP 1: Create the database
   --------------------------------------------------------------------- */
CREATE DATABASE HospitalDB;
GO
USE HospitalDB;
GO

/* ---------------------------------------------------------------------
   STEP 2: Import the CSV (done with the wizard, not with code)
   Right-click HospitalDB > Tasks > Import Flat File...
   - Pick healthcare_dataset.csv
   - Table name: healthcare_dataset  (schema dbo)
   - In "Modify Columns" set: Age = int, Billing Amount = float,
     Room Number = int, both date columns = date
   Then run the check below. The count should be about 55,500.
   --------------------------------------------------------------------- */
SELECT COUNT(*) AS raw_rows FROM dbo.healthcare_dataset;
SELECT TOP 10 * FROM dbo.healthcare_dataset;

/* ---------------------------------------------------------------------
   STEP 3: Check data quality
   --------------------------------------------------------------------- */
-- Exact duplicate rows (this dataset often has some)
SELECT COUNT(*) AS duplicate_groups
FROM (
    SELECT [Name], [Age], [Gender], [Blood_Type], [Medical_Condition],
           [Date_of_Admission], [Doctor], [Hospital], [Insurance_Provider],
           [Billing_Amount], [Room_Number], [Admission_Type],
           [Discharge_Date], [Medication], [Test_Results]
    FROM dbo.healthcare_dataset
    GROUP BY [Name], [Age], [Gender], [Blood_Type], [Medical_Condition],
             [Date_of_Admission], [Doctor], [Hospital], [Insurance_Provider],
             [Billing_Amount], [Room_Number], [Admission_Type],
             [Discharge_Date], [Medication], [Test_Results]
    HAVING COUNT(*) > 1
) d;

-- Negative or missing billing amounts
SELECT COUNT(*) AS bad_billing
FROM dbo.healthcare_dataset
WHERE [Billing_Amount] IS NULL OR [Billing_Amount] < 0;

-- Discharge before admission
SELECT COUNT(*) AS bad_dates
FROM dbo.healthcare_dataset
WHERE [Discharge_Date] < [Date_of_Admission];

/* ---------------------------------------------------------------------
   STEP 4: Clean data into a staging table (removes exact duplicates)
   Note: odd name capitalization is fixed later in Power Query
   (Transform > Format > Capitalize Each Word).
   --------------------------------------------------------------------- */
SELECT DISTINCT
    LTRIM(RTRIM([Name]))               AS patient_name,
    CAST([Age] AS INT)                 AS age,
    LTRIM(RTRIM([Gender]))             AS gender,
    LTRIM(RTRIM([Blood_Type]))         AS blood_type,
    LTRIM(RTRIM([Medical_Condition]))  AS medical_condition,
    CAST([Date_of_Admission] AS DATE)  AS admission_date,
    LTRIM(RTRIM([Doctor]))             AS doctor_name,
    LTRIM(RTRIM([Hospital]))           AS hospital_name,
    LTRIM(RTRIM([Insurance_Provider])) AS insurance_provider,
    CAST([Billing_Amount] AS DECIMAL(12,2)) AS billing_amount,
    CAST([Room_Number] AS INT)         AS room_number,
    LTRIM(RTRIM([Admission_Type]))     AS admission_type,
    CAST([Discharge_Date] AS DATE)     AS discharge_date,
    LTRIM(RTRIM([Medication]))         AS medication,
    LTRIM(RTRIM([Test_Results]))       AS test_results
INTO dbo.stg_admissions
FROM dbo.healthcare_dataset
WHERE [Billing_Amount] IS NOT NULL;

SELECT COUNT(*) AS clean_rows FROM dbo.stg_admissions;

/* ---------------------------------------------------------------------
   STEP 5: Create the related tables (the data model)
   patients, doctors, hospitals  -->  admissions
   --------------------------------------------------------------------- */
CREATE TABLE dbo.patients (
    patient_id   INT IDENTITY(1,1) PRIMARY KEY,
    patient_name NVARCHAR(150) NOT NULL,
    age          INT,
    gender       NVARCHAR(20),
    blood_type   NVARCHAR(10)
);

CREATE TABLE dbo.doctors (
    doctor_id   INT IDENTITY(1,1) PRIMARY KEY,
    doctor_name NVARCHAR(150) NOT NULL
);

CREATE TABLE dbo.hospitals (
    hospital_id   INT IDENTITY(1,1) PRIMARY KEY,
    hospital_name NVARCHAR(200) NOT NULL
);

CREATE TABLE dbo.admissions (
    admission_id       INT IDENTITY(1,1) PRIMARY KEY,
    patient_id         INT NOT NULL FOREIGN KEY REFERENCES dbo.patients(patient_id),
    doctor_id          INT NOT NULL FOREIGN KEY REFERENCES dbo.doctors(doctor_id),
    hospital_id        INT NOT NULL FOREIGN KEY REFERENCES dbo.hospitals(hospital_id),
    medical_condition  NVARCHAR(100),
    admission_date     DATE,
    discharge_date     DATE,
    admission_type     NVARCHAR(50),
    insurance_provider NVARCHAR(100),
    billing_amount     DECIMAL(12,2),
    room_number        INT,
    medication         NVARCHAR(100),
    test_results       NVARCHAR(50)
);

/* ---------------------------------------------------------------------
   STEP 6: Fill the tables from the staging table
   --------------------------------------------------------------------- */
INSERT INTO dbo.patients (patient_name, age, gender, blood_type)
SELECT DISTINCT patient_name, age, gender, blood_type
FROM dbo.stg_admissions;

INSERT INTO dbo.doctors (doctor_name)
SELECT DISTINCT doctor_name FROM dbo.stg_admissions;

INSERT INTO dbo.hospitals (hospital_name)
SELECT DISTINCT hospital_name FROM dbo.stg_admissions;

INSERT INTO dbo.admissions
    (patient_id, doctor_id, hospital_id, medical_condition, admission_date,
     discharge_date, admission_type, insurance_provider, billing_amount,
     room_number, medication, test_results)
SELECT p.patient_id, d.doctor_id, h.hospital_id, s.medical_condition,
       s.admission_date, s.discharge_date, s.admission_type,
       s.insurance_provider, s.billing_amount, s.room_number,
       s.medication, s.test_results
FROM dbo.stg_admissions s
JOIN dbo.patients  p ON p.patient_name = s.patient_name
                    AND p.age = s.age
                    AND p.gender = s.gender
                    AND p.blood_type = s.blood_type
JOIN dbo.doctors   d ON d.doctor_name = s.doctor_name
JOIN dbo.hospitals h ON h.hospital_name = s.hospital_name;

-- Check: admissions count should match clean_rows from Step 4
SELECT
    (SELECT COUNT(*) FROM dbo.patients)   AS patients,
    (SELECT COUNT(*) FROM dbo.doctors)    AS doctors,
    (SELECT COUNT(*) FROM dbo.hospitals)  AS hospitals,
    (SELECT COUNT(*) FROM dbo.admissions) AS admissions;

/* ---------------------------------------------------------------------
   STEP 7: Analysis views (use these in SQL practice and in Power BI)
   Each CREATE VIEW must be run as its own batch (GO between them).
   --------------------------------------------------------------------- */
GO
CREATE VIEW dbo.vw_revenue_by_hospital AS
SELECT h.hospital_name,
       COUNT(*)                       AS total_admissions,
       SUM(a.billing_amount)          AS total_revenue,
       AVG(a.billing_amount)          AS avg_billing
FROM dbo.admissions a
JOIN dbo.hospitals h ON h.hospital_id = a.hospital_id
GROUP BY h.hospital_name;
GO

CREATE VIEW dbo.vw_admissions_by_month AS
SELECT YEAR(admission_date)  AS admission_year,
       MONTH(admission_date) AS admission_month,
       COUNT(*)              AS total_admissions,
       SUM(billing_amount)   AS total_revenue
FROM dbo.admissions
GROUP BY YEAR(admission_date), MONTH(admission_date);
GO

CREATE VIEW dbo.vw_top_doctors AS
SELECT d.doctor_name,
       COUNT(*)              AS patients_treated,
       SUM(a.billing_amount) AS total_billing
FROM dbo.admissions a
JOIN dbo.doctors d ON d.doctor_id = a.doctor_id
GROUP BY d.doctor_name;
GO

CREATE VIEW dbo.vw_avg_stay_by_condition AS
SELECT medical_condition,
       COUNT(*)                                      AS total_admissions,
       AVG(DATEDIFF(DAY, admission_date, discharge_date)) AS avg_stay_days,
       AVG(billing_amount)                           AS avg_billing
FROM dbo.admissions
GROUP BY medical_condition;
GO

CREATE VIEW dbo.vw_insurance_share AS
SELECT insurance_provider,
       COUNT(*)              AS total_admissions,
       SUM(billing_amount)   AS total_billing
FROM dbo.admissions
GROUP BY insurance_provider;
GO

-- Try them:
SELECT * FROM dbo.vw_revenue_by_hospital ORDER BY total_revenue DESC;
SELECT * FROM dbo.vw_top_doctors ORDER BY patients_treated DESC;
SELECT * FROM dbo.vw_avg_stay_by_condition ORDER BY avg_stay_days DESC;


--finding the negitive billing data inthe dataset
SELECT TOP 10 * FROM dbo.admissions WHERE billing_amount < 0;

--deleting that nagitive billing amount data
DELETE FROM dbo.admissions WHERE billing_amount < 0;
SELECT COUNT(*) FROM dbo.admissions;

--checking after deleting ,if they are present or not
SELECT COUNT(*) FROM dbo.admissions WHERE billing_amount < 0;


SELECT COUNT(*) AS raw_rows FROM healthcare_dataset;


SELECT COUNT(*) AS clean_rows FROM dbo.admissions;

SELECT COUNT(*) AS negative_billing
FROM dbo.healthcare_dataset
WHERE [Billing_Amount] < 0;







