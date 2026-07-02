import { FastifyInstance } from 'fastify';
import rateLimit from '@fastify/rate-limit';
import { z } from 'zod';
import { db } from './db.js';
import { env } from './config.js';
import {
  createRefreshToken,
  hashPassword,
  hashRefreshToken,
  signAccessToken,
  verifyPassword,
} from './security.js';
import { requireAuth } from './auth.js';

const signUpSchema = z.object({
  name: z.string().min(2).max(100),
  email: z.string().email(),
  password: z.string().min(8).max(128),
});

const signInSchema = z.object({
  email: z.string().email(),
  password: z.string().min(8).max(128),
});

const refreshSchema = z.object({
  refreshToken: z.string().min(20),
});

const profileSchema = z.object({
  name: z.string().min(2),
  email: z.string().email(),
  annualCTC: z.number().int().nonnegative(),
  employmentType: z.enum(['salaried', 'selfEmployed']),
  city: z.string().min(1),
  isMetroCity: z.boolean(),
  paysRent: z.boolean(),
  monthlyRent: z.number().int().nonnegative(),
  hasHRA: z.boolean(),
  invested80C: z.number().int().nonnegative(),
  hasHomeLoan: z.boolean(),
  propertyType: z.enum(['selfOccupied', 'letOut']).nullable(),
  homeLoanInterest: z.number().int().nonnegative(),
  hasNPS: z.boolean(),
  npsExtraContribution: z.number().int().nonnegative(),
  hasHealthInsuranceSelf: z.boolean(),
  hasHealthInsuranceParents: z.boolean(),
  parentsAbove60: z.boolean(),
  hasEducationLoan: z.boolean(),
  educationLoanRepaymentYear: z.number().int().min(1).max(8),
  educationLoanInterest: z.number().int().nonnegative(),
  hasDonations: z.boolean(),
  donationAmount: z.number().int().nonnegative(),
  ageGroup: z.enum(['below30', 'age30to45', 'age45to60', 'above60']),
});

const taxResultSchema = z.record(z.any());
const doneGapsSchema = z.object({
  gapIds: z.array(z.string()).default([]),
});

const eventSchema = z.object({
  name: z.string().min(1).max(100),
  metadata: z.record(z.any()).optional(),
});

const authRateLimit = {
  config: {
    rateLimit: {
      max: 20,
      timeWindow: '1 minute',
    },
  },
};

const dataRateLimit = {
  config: {
    rateLimit: {
      max: 60,
      timeWindow: '1 minute',
    },
  },
};

const readRateLimit = {
  config: {
    rateLimit: {
      max: 120,
      timeWindow: '1 minute',
    },
  },
};

function refreshExpiryDate(): Date {
  return new Date(Date.now() + env.REFRESH_TOKEN_TTL_DAYS * 24 * 60 * 60 * 1000);
}

async function issueSession(user: {
  id: string;
  email: string;
  name: string;
  created_at: string | Date;
}) {
  const refreshToken = createRefreshToken();
  const refreshTokenHash = hashRefreshToken(refreshToken);
  await db.query(
    `insert into auth_refresh_sessions (user_id, token_hash, expires_at)
     values ($1, $2, $3)`,
    [user.id, refreshTokenHash, refreshExpiryDate()],
  );

  const accessToken = await signAccessToken(user.id, user.email);
  return {
    user: {
      id: user.id,
      email: user.email,
      name: user.name,
      createdAt: new Date(user.created_at).toISOString(),
    },
    accessToken,
    refreshToken,
  };
}

export async function registerRoutes(app: FastifyInstance) {
  await app.register(rateLimit, {
    global: false,
    max: 100,
    timeWindow: '1 minute',
  });
  app.get('/health', async () => ({ ok: true }));
  app.get('/ping', async () => ({ ok: true, ts: Date.now() }));

  app.post('/auth/sign-up', authRateLimit, async (request, reply) => {
    const payload = signUpSchema.parse(request.body);
    const email = payload.email.toLowerCase();
    const existing = await db.query(
      'select id from app_users where email = $1',
      [email],
    );
    if (existing.rowCount) {
      return reply.code(409).send({ message: 'Email already registered' });
    }

    const passwordHash = await hashPassword(payload.password);
    const inserted = await db.query(
      `insert into app_users (email, name, password_hash)
       values ($1, $2, $3)
       returning id, email, name, created_at`,
      [email, payload.name.trim(), passwordHash],
    );
    const user = inserted.rows[0];
    return issueSession(user);
  });

  app.post('/auth/sign-in', authRateLimit, async (request, reply) => {
    const payload = signInSchema.parse(request.body);
    const email = payload.email.toLowerCase();
    const result = await db.query(
      `select id, email, name, password_hash, created_at
       from app_users
       where email = $1`,
      [email],
    );
    if (!result.rowCount) {
      return reply.code(401).send({ message: 'Invalid credentials' });
    }
    const user = result.rows[0];
    const valid = await verifyPassword(payload.password, user.password_hash as string);
    if (!valid) {
      return reply.code(401).send({ message: 'Invalid credentials' });
    }

    await db.query(
      'update app_users set last_seen_at = now(), updated_at = now() where id = $1',
      [user.id],
    );
    return issueSession(user);
  });

  app.post('/auth/refresh', authRateLimit, async (request, reply) => {
    const payload = refreshSchema.parse(request.body);
    const tokenHash = hashRefreshToken(payload.refreshToken);
    const session = await db.query(
      `select s.id, s.user_id, s.expires_at, u.email, u.name, u.created_at
       from auth_refresh_sessions s
       join app_users u on u.id = s.user_id
       where s.token_hash = $1
         and s.revoked_at is null
         and s.expires_at > now()`,
      [tokenHash],
    );
    if (!session.rowCount) {
      return reply.code(401).send({ message: 'Invalid refresh token' });
    }

    const row = session.rows[0];
    await db.query(
      'update auth_refresh_sessions set revoked_at = now() where id = $1',
      [row.id],
    );

    return issueSession({
      id: row.user_id as string,
      email: row.email as string,
      name: row.name as string,
      created_at: row.created_at as string | Date,
    });
  });

  app.post('/auth/sign-out', authRateLimit, async (request, reply) => {
    const payload = refreshSchema.parse(request.body);
    const tokenHash = hashRefreshToken(payload.refreshToken);
    await db.query(
      'update auth_refresh_sessions set revoked_at = now() where token_hash = $1 and revoked_at is null',
      [tokenHash],
    );
    return reply.code(204).send();
  });

  app.get('/me', readRateLimit, async (request, reply) => {
    const auth = await requireAuth(request, reply);
    if (!auth) return;

    const result = await db.query(
      'select id, email, name, created_at from app_users where id = $1',
      [auth.userId],
    );
    const user = result.rows[0];
    return {
      user: {
        id: user.id,
        email: user.email,
        name: user.name,
        createdAt: new Date(user.created_at as string | Date).toISOString(),
      },
    };
  });

  app.get('/profile', readRateLimit, async (request, reply) => {
    const auth = await requireAuth(request, reply);
    if (!auth) return;

    const result = await db.query(
      'select * from tax_profiles where user_id = $1 and fy = $2',
      [auth.userId, env.CURRENT_FY],
    );
    if (!result.rowCount) {
      return { profile: null };
    }
    const row = result.rows[0];
    return {
      profile: {
        name: row.name,
        email: row.email,
        annualCTC: row.annual_ctc,
        employmentType: row.employment_type,
        city: row.city,
        isMetroCity: row.is_metro_city,
        paysRent: row.pays_rent,
        monthlyRent: row.monthly_rent,
        hasHRA: row.has_hra,
        invested80C: row.invested_80c,
        hasHomeLoan: row.has_home_loan,
        propertyType: row.property_type,
        homeLoanInterest: row.home_loan_interest,
        hasNPS: row.has_nps,
        npsExtraContribution: row.nps_extra_contribution,
        hasHealthInsuranceSelf: row.has_health_insurance_self,
        hasHealthInsuranceParents: row.has_health_insurance_parents,
        parentsAbove60: row.parents_above_60,
        hasEducationLoan: row.has_education_loan,
        educationLoanRepaymentYear: row.education_loan_repayment_year,
        educationLoanInterest: row.education_loan_interest,
        hasDonations: row.has_donations,
        donationAmount: row.donation_amount,
        ageGroup: row.age_group,
      },
    };
  });

  app.put(
    '/profile',
    dataRateLimit,
    async (request, reply) => {
      const auth = await requireAuth(request, reply);
      if (!auth) return;

      const profile = profileSchema.parse(request.body);
      await db.query(
        `insert into tax_profiles (
           user_id, fy, name, email, annual_ctc, employment_type, city, is_metro_city,
           pays_rent, monthly_rent, has_hra, invested_80c, has_home_loan, property_type,
           home_loan_interest, has_nps, nps_extra_contribution, has_health_insurance_self,
           has_health_insurance_parents, parents_above_60, has_education_loan,
           education_loan_repayment_year, education_loan_interest, has_donations,
           donation_amount, age_group, updated_at
         ) values (
           $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15,
           $16, $17, $18, $19, $20, $21, $22, $23, $24, $25, $26, now()
         )
         on conflict (user_id, fy) do update set
           name = excluded.name,
           email = excluded.email,
           annual_ctc = excluded.annual_ctc,
           employment_type = excluded.employment_type,
           city = excluded.city,
           is_metro_city = excluded.is_metro_city,
           pays_rent = excluded.pays_rent,
           monthly_rent = excluded.monthly_rent,
           has_hra = excluded.has_hra,
           invested_80c = excluded.invested_80c,
           has_home_loan = excluded.has_home_loan,
           property_type = excluded.property_type,
           home_loan_interest = excluded.home_loan_interest,
           has_nps = excluded.has_nps,
           nps_extra_contribution = excluded.nps_extra_contribution,
           has_health_insurance_self = excluded.has_health_insurance_self,
           has_health_insurance_parents = excluded.has_health_insurance_parents,
           parents_above_60 = excluded.parents_above_60,
           has_education_loan = excluded.has_education_loan,
           education_loan_repayment_year = excluded.education_loan_repayment_year,
           education_loan_interest = excluded.education_loan_interest,
           has_donations = excluded.has_donations,
           donation_amount = excluded.donation_amount,
           age_group = excluded.age_group,
           updated_at = now()`,
        [
          auth.userId,
          env.CURRENT_FY,
          profile.name,
          profile.email,
          profile.annualCTC,
          profile.employmentType,
          profile.city,
          profile.isMetroCity,
          profile.paysRent,
          profile.monthlyRent,
          profile.hasHRA,
          profile.invested80C,
          profile.hasHomeLoan,
          profile.propertyType,
          profile.homeLoanInterest,
          profile.hasNPS,
          profile.npsExtraContribution,
          profile.hasHealthInsuranceSelf,
          profile.hasHealthInsuranceParents,
          profile.parentsAbove60,
          profile.hasEducationLoan,
          profile.educationLoanRepaymentYear,
          profile.educationLoanInterest,
          profile.hasDonations,
          profile.donationAmount,
          profile.ageGroup,
        ],
      );
      return { ok: true };
    },
  );

  app.get(
    '/tax-results/current',
    {
      ...readRateLimit,
    },
    async (request, reply) => {
      const auth = await requireAuth(request, reply);
      if (!auth) return;

      const result = await db.query(
        'select payload from tax_results where user_id = $1 and fy = $2',
        [auth.userId, env.CURRENT_FY],
      );
      return {
        taxResult: result.rowCount ? result.rows[0].payload : null,
      };
    },
  );

  app.put(
    '/tax-results/current',
    {
      ...dataRateLimit,
    },
    async (request, reply) => {
      const auth = await requireAuth(request, reply);
      if (!auth) return;

      const payload = taxResultSchema.parse(request.body);
      await db.query(
        `insert into tax_results (user_id, fy, payload, updated_at)
         values ($1, $2, $3::jsonb, now())
         on conflict (user_id, fy) do update set
           payload = excluded.payload,
           updated_at = now()`,
        [auth.userId, env.CURRENT_FY, JSON.stringify(payload)],
      );
      return { ok: true };
    },
  );

  app.get(
    '/done-gaps/current',
    {
      ...readRateLimit,
    },
    async (request, reply) => {
      const auth = await requireAuth(request, reply);
      if (!auth) return;

      const result = await db.query(
        'select gap_id from done_gaps where user_id = $1 and fy = $2 order by gap_id asc',
        [auth.userId, env.CURRENT_FY],
      );
      return {
        gapIds: result.rows.map((row) => row.gap_id),
      };
    },
  );

  app.put(
    '/done-gaps/current',
    {
      ...dataRateLimit,
    },
    async (request, reply) => {
      const auth = await requireAuth(request, reply);
      if (!auth) return;

      const payload = doneGapsSchema.parse(request.body);
      const client = await db.connect();
      try {
        await client.query('begin');
        await client.query(
          'delete from done_gaps where user_id = $1 and fy = $2',
          [auth.userId, env.CURRENT_FY],
        );
        for (const gapId of payload.gapIds) {
          await client.query(
            'insert into done_gaps (user_id, fy, gap_id) values ($1, $2, $3)',
            [auth.userId, env.CURRENT_FY, gapId],
          );
        }
        await client.query('commit');
      } catch (error) {
        await client.query('rollback');
        throw error;
      } finally {
        client.release();
      }
      return { ok: true };
    },
  );

  app.delete(
    '/profile',
    {
      ...dataRateLimit,
    },
    async (request, reply) => {
      const auth = await requireAuth(request, reply);
      if (!auth) return;
      const client = await db.connect();
      try {
        await client.query('begin');
        await client.query('delete from done_gaps where user_id = $1', [auth.userId]);
        await client.query('delete from tax_profiles where user_id = $1', [auth.userId]);
        await client.query('delete from tax_results where user_id = $1', [auth.userId]);
        await client.query('commit');
      } catch (error) {
        await client.query('rollback');
        throw error;
      } finally {
        client.release();
      }
      return reply.code(204).send();
    },
  );

  app.post(
    '/events',
    {
      ...dataRateLimit,
    },
    async (request, reply) => {
      const auth = await requireAuth(request, reply);
      if (!auth) return;

      const payload = eventSchema.parse(request.body);
      await db.query(
        'insert into user_events (user_id, name, metadata) values ($1, $2, $3::jsonb)',
        [auth.userId, payload.name, JSON.stringify(payload.metadata ?? {})],
      );
      return reply.code(204).send();
    },
  );
}
