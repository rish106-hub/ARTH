ALTER TABLE tax_profiles
  ADD COLUMN IF NOT EXISTS actual_basic_salary INTEGER CHECK (actual_basic_salary IS NULL OR actual_basic_salary >= 0),
  ADD COLUMN IF NOT EXISTS actual_hra_received INTEGER CHECK (actual_hra_received IS NULL OR actual_hra_received >= 0),
  ADD COLUMN IF NOT EXISTS actual_professional_tax INTEGER CHECK (actual_professional_tax IS NULL OR actual_professional_tax >= 0),
  ADD COLUMN IF NOT EXISTS health_insurance_self_premium INTEGER CHECK (health_insurance_self_premium IS NULL OR health_insurance_self_premium >= 0),
  ADD COLUMN IF NOT EXISTS health_insurance_parents_premium INTEGER CHECK (health_insurance_parents_premium IS NULL OR health_insurance_parents_premium >= 0),
  ADD COLUMN IF NOT EXISTS savings_interest INTEGER CHECK (savings_interest IS NULL OR savings_interest >= 0),
  ADD COLUMN IF NOT EXISTS fd_interest INTEGER CHECK (fd_interest IS NULL OR fd_interest >= 0),
  ADD COLUMN IF NOT EXISTS employer_nps_contribution INTEGER CHECK (employer_nps_contribution IS NULL OR employer_nps_contribution >= 0),
  ADD COLUMN IF NOT EXISTS donation_deduction_rate_percent INTEGER CHECK (donation_deduction_rate_percent IS NULL OR donation_deduction_rate_percent BETWEEN 0 AND 100);

ALTER TABLE tax_profiles
  DROP CONSTRAINT IF EXISTS tax_profiles_age_group_check;

ALTER TABLE tax_profiles
  ADD CONSTRAINT tax_profiles_age_group_check
  CHECK (age_group IN ('below30', 'age30to45', 'age45to60', 'above60', 'above80'));
