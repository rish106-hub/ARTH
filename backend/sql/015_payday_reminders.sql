ALTER TABLE spend_maps
    ADD COLUMN IF NOT EXISTS salary_credit_day SMALLINT;

ALTER TABLE spend_maps
    DROP CONSTRAINT IF EXISTS spend_maps_salary_credit_day_check;

ALTER TABLE spend_maps
    ADD CONSTRAINT spend_maps_salary_credit_day_check
    CHECK (salary_credit_day IS NULL OR salary_credit_day BETWEEN 1 AND 31);

CREATE INDEX IF NOT EXISTS idx_spend_maps_salary_credit_day
    ON spend_maps(salary_credit_day)
    WHERE salary_credit_day IS NOT NULL;
