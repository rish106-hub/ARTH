import { createHash, randomUUID } from 'node:crypto';
import { FastifyInstance, FastifyRequest } from 'fastify';
import rateLimit from '@fastify/rate-limit';
import { z } from 'zod';
import { OAuth2Client } from 'google-auth-library';
import { buildRevision } from './buildRevision.js';
import { db, Queryable, runSerializableTransaction } from './db.js';
import { parseUploadedDocument, type PanVaultSuffix } from './documentParser.js';
import { categorizeTransactions } from './spendCategorizer.js';
import { sendPushToUser } from './pushNotifications.js';
import { env } from './config.js';
import {
  createRefreshToken,
  decryptDocument,
  encryptDocument,
  encryptPan,
  type EncryptedSecret,
  hashPan,
  hashPassword,
  passwordNeedsRehash,
  hashRefreshToken,
  signAccessToken,
  verifyPassword,
} from './security.js';
import { requireAuth } from './auth.js';
import { blindIndex } from './envelopeEncryption.js';

const signUpPasswordSchema = z.string()
  .min(12)
  .max(128)
  .regex(/[a-z]/)
  .regex(/[A-Z]/)
  .regex(/[0-9]/);

const signUpSchema = z.object({
  name: z.string().trim().min(2).max(80),
  email: z.string().email(),
  password: signUpPasswordSchema,
});

const signInSchema = z.object({
  email: z.string().email(),
  password: z.string().min(8).max(128),
});

const googleAuthSchema = z.object({
  idToken: z.string().min(100).max(10_000),
});

const refreshSchema = z.object({
  refreshToken: z.string().min(20).max(256),
});

const deleteAccountSchema = z.object({
  confirmation: z.literal('DELETE'),
});

const accountProfileSchema = z.object({
  name: z.string().trim().min(2).max(80).optional(),
  phoneNumber: z.string().trim().regex(/^\+[1-9][0-9]{7,14}$/).nullable().optional(),
  avatarInitials: z.string().trim().min(1).max(2).regex(/^[A-Za-z]+$/).nullable().optional(),
  avatarColor: z.enum(['gold', 'teal', 'amber', 'green', 'blue']).nullable().optional(),
}).refine((value) => Object.keys(value).length > 0);

const panSchema = z.object({
  pan: z.string().trim().regex(/^[A-Za-z]{5}[0-9]{4}[A-Za-z]$/),
  consentAccepted: z.literal(true),
  consentVersion: z.string().trim().min(1).max(40),
});

const profileSchema = z.object({
  name: z.string().trim().min(2).max(80),
  email: z.string().email(),
  annualCTC: z.number().int().min(0).max(100_000_000),
  employmentType: z.enum(['salaried', 'selfEmployed']),
  employerName: z.string().trim().max(120).default(''),
  city: z.string().trim().min(1).max(80),
  isMetroCity: z.boolean(),
  paysRent: z.boolean(),
  monthlyRent: z.number().int().min(0).max(10_000_000),
  hasHRA: z.boolean(),
  invested80C: z.number().int().min(0).max(1_500_000),
  hasHomeLoan: z.boolean(),
  propertyType: z.enum(['selfOccupied', 'letOut']).nullable(),
  homeLoanInterest: z.number().int().min(0).max(10_000_000),
  hasNPS: z.boolean(),
  npsExtraContribution: z.number().int().min(0).max(1_000_000),
  hasHealthInsuranceSelf: z.boolean(),
  hasHealthInsuranceParents: z.boolean(),
  parentsAbove60: z.boolean(),
  hasEducationLoan: z.boolean(),
  educationLoanRepaymentYear: z.number().int().min(1).max(8),
  educationLoanInterest: z.number().int().min(0).max(10_000_000),
  hasDonations: z.boolean(),
  donationAmount: z.number().int().min(0).max(10_000_000),
  ageGroup: z.enum(['below30', 'age30to45', 'age45to60', 'above60', 'above80']),
  actualBasicSalary: z.number().int().min(0).max(100_000_000).nullable().optional(),
  actualHraReceived: z.number().int().min(0).max(100_000_000).nullable().optional(),
  actualProfessionalTax: z.number().int().min(0).max(100_000).nullable().optional(),
  healthInsuranceSelfPremium: z.number().int().min(0).max(10_000_000).nullable().optional(),
  healthInsuranceParentsPremium: z.number().int().min(0).max(10_000_000).nullable().optional(),
  savingsInterest: z.number().int().min(0).max(100_000_000).nullable().optional(),
  fdInterest: z.number().int().min(0).max(100_000_000).nullable().optional(),
  employerNpsContribution: z.number().int().min(0).max(100_000_000).nullable().optional(),
  donationDeductionRatePercent: z.number().int().min(0).max(100).nullable().optional(),
});

const taxResultSchema = z.record(z.string(), z.any());
const doneGapsSchema = z.object({
  gapIds: z.array(z.string().min(1).max(120)).max(100),
});

const eventSchema = z.object({
  name: z.string().min(1).max(64),
  metadata: z.record(z.string(), z.any()).optional(),
});

const moneyGoalSchema = z.object({
  name: z.string().trim().min(3).max(80),
  category: z.enum(['safety', 'family', 'education', 'home', 'travel', 'other']),
  targetAmount: z.number().int().min(1).max(1_000_000_000),
  currentAmount: z.number().int().min(0).max(1_000_000_000),
  targetDate: z.string().date(),
  monthlyEssentials: z.number().int().min(0).max(100_000_000),
  monthlyFamilySupport: z.number().int().min(0).max(100_000_000),
});

// Accept UTC ('Z'), zoned offset, and offset-less local timestamps. Dart's
// DateTime.toIso8601String() on a local DateTime emits no timezone, which the
// default (Z-only) datetime() would reject — silently 400ing the sync.
const flexibleDatetime = () => z.string().datetime({ offset: true, local: true });

const spendMapSchema = z.object({
  windowStart: flexibleDatetime(),
  windowEnd: flexibleDatetime(),
  generatedAt: flexibleDatetime(),
  monthlyIncome: z.number().int().min(0).max(1_000_000_000),
  monthlySpend: z.number().int().min(0).max(1_000_000_000),
  realisticMonthlySavings: z.number().int().min(0).max(1_000_000_000),
  spendByCategory: z.record(
    z.string().min(1).max(40),
    z.number().int().min(0).max(1_000_000_000),
  ),
  monthlyTrend: z.array(z.object({
    month: flexibleDatetime(),
    spent: z.number().int().min(0).max(1_000_000_000),
    income: z.number().int().min(0).max(1_000_000_000),
  })).max(24).default([]),
});

const deviceTokenSchema = z.object({
  fcmToken: z.string().trim().min(20).max(4096),
  platform: z.enum(['android', 'ios']),
});

const categorizeRequestSchema = z.object({
  items: z.array(z.object({
    id: z.string().min(1).max(64),
    // Redacted SMS/merchant text. Never persisted; used only to call the model.
    text: z.string().min(1).max(300),
  })).min(1).max(40),
});

const employerSubmissionSchema = z.object({
  name: z.string().trim().min(2).max(120),
});

const employerSearchSchema = z.object({
  q: z.string().trim().max(80).default(''),
});

const documentPatchSchema = z.object({
  userLabel: z.string().trim().max(80).nullable().optional(),
  notes: z.string().trim().max(1200).nullable().optional(),
  tags: z.array(z.string().trim().min(1).max(32)).max(12).optional(),
  vaultStatus: z.enum(['active', 'archived']).optional(),
  reviewStatus: z.enum(['not_reviewed', 'needs_review', 'reviewed']).optional(),
}).refine((value) => Object.keys(value).length > 0);

const manualPayslipRowSchema = z.object({
  label: z.string().trim().min(1).max(120),
  canonicalKey: z.string().trim().min(1).max(80).optional(),
  amount: z.number().finite().min(-100_000_000).max(100_000_000),
  classification: z.string().trim().min(1).max(40).default('other'),
  confidence: z.literal('high').default('high'),
}).strict();

const manualPayslipFieldsSchema = z.object({
  employerName: z.string().trim().max(160).nullable().default(null),
  employeeName: z.string().trim().max(160).nullable().default(null),
  payPeriod: z.string().trim().max(80).nullable().default(null),
  paymentDate: z.string().trim().max(40).nullable().default(null),
  currency: z.string().trim().min(1).max(8).default('INR'),
  attendance: z.object({
    actualPayableDays: z.number().finite().nonnegative().max(366).nullable(),
    totalWorkingDays: z.number().finite().nonnegative().max(366).nullable(),
    lossOfPayDays: z.number().finite().nonnegative().max(366).nullable(),
    daysPayable: z.number().finite().nonnegative().max(366).nullable(),
  }).strict().default({
    actualPayableDays: null,
    totalWorkingDays: null,
    lossOfPayDays: null,
    daysPayable: null,
  }),
  earnings: z.array(manualPayslipRowSchema).max(120).default([]),
  deductions: z.array(manualPayslipRowSchema).max(120).default([]),
  grossEarnings: z.number().finite().positive().max(100_000_000),
  totalDeductions: z.number().finite().nonnegative().max(100_000_000),
  netSalary: z.number().finite().positive().max(100_000_000),
  warnings: z.array(z.string().trim().min(1).max(240)).max(20)
    .default(['Entered manually by the user.']),
  questionsForUser: z.array(z.string().trim().min(1).max(240)).max(12)
    .default([]),
}).strict().superRefine((fields, context) => {
  const expectedNet = fields.grossEarnings - fields.totalDeductions;
  if (Math.abs(expectedNet - fields.netSalary) > 1) {
    context.addIssue({
      code: z.ZodIssueCode.custom,
      path: ['netSalary'],
      message: 'Net salary must equal gross earnings minus total deductions',
    });
  }
});

const documentConfirmationSchema = z.preprocess(
  (value) => value ?? {},
  z.object({
    fields: manualPayslipFieldsSchema.optional(),
  }).strict(),
);

const documentTypeSchema = z.enum([
  'offerLetter',
  'payslip',
  'form16',
  'rentReceipts',
  'investment80c',
  'healthInsurance80d',
  'homeLoanCertificate',
  'educationLoanInterest',
  'donationReceipts',
  'ais26asReview',
  'otherTaxDocument',
]);

const allowedDocumentTypes = new Set<string>(documentTypeSchema.options);
const allowedMimeTypes = new Set([
  'application/pdf',
  'image/jpeg',
  'image/png',
]);

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

const documentUploadOptions = {
  bodyLimit: 9 * 1024 * 1024,
  config: {
    rateLimit: {
      max: 20,
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
  phone_e164?: string | null;
  avatar_initials?: string | null;
  avatar_color?: string | null;
  created_at: string | Date;
}, store: Queryable = db, metadata: SessionMetadata = {}) {
  const sessionId = randomUUID();
  const refreshToken = createRefreshToken();
  const refreshTokenHash = hashRefreshToken(refreshToken);
  await store.query(
    `insert into auth_refresh_sessions (
       id, user_id, token_hash, expires_at, user_agent, ip_address
     ) values ($1, $2, $3, $4, $5, $6)`,
    [
      sessionId,
      user.id,
      refreshTokenHash,
      refreshExpiryDate(),
      metadata.userAgentHash ?? null,
      metadata.ipPrefixHash ?? null,
    ],
  );

  const accessToken = await signAccessToken(user.id, sessionId);
  return {
    user: {
      id: user.id,
      email: user.email,
      name: user.name,
      phoneNumber: user.phone_e164 ?? null,
      avatarInitials: user.avatar_initials ?? null,
      avatarColor: user.avatar_color ?? null,
      createdAt: new Date(user.created_at).toISOString(),
    },
    accessToken,
    refreshToken,
  };
}

type SessionMetadata = {
  userAgentHash?: string;
  ipPrefixHash?: string;
};

function sessionMetadata(request: FastifyRequest): SessionMetadata {
  const userAgent = request.headers['user-agent'];
  const userAgentValue = Array.isArray(userAgent) ? userAgent.join(',') : userAgent;
  return {
    userAgentHash: hashMetadata(userAgentValue),
    ipPrefixHash: hashMetadata(ipPrefix(request.ip)),
  };
}

function hashMetadata(value: string | undefined): string | undefined {
  if (!value) return undefined;
  return `sha256:${createHash('sha256').update(value).digest('hex')}`;
}

function ipPrefix(ip: string | undefined): string | undefined {
  if (!ip) return undefined;
  if (/^\d+\.\d+\.\d+\.\d+$/.test(ip)) {
    return ip.split('.').slice(0, 3).join('.');
  }
  if (ip.includes(':')) {
    return ip.split(':').slice(0, 4).join(':');
  }
  return undefined;
}

function maskPan(last4: unknown, lastChar: unknown): string | null {
  if (typeof last4 !== 'string' || typeof lastChar !== 'string') return null;
  if (last4.length !== 4 || lastChar.length !== 1) return null;
  return `•••••${last4}${lastChar}`;
}

function accountResponse(user: {
  id: string;
  email: string;
  name: string;
  phone_e164?: string | null;
  avatar_initials?: string | null;
  avatar_color?: string | null;
  created_at: string | Date;
}, identity?: Record<string, unknown>) {
  const maskedPan = identity ? maskPan(identity.pan_last4, identity.pan_last_char) : null;
  return {
    user: {
      id: user.id,
      email: user.email,
      name: user.name,
      phoneNumber: user.phone_e164 ?? null,
      avatarInitials: user.avatar_initials ?? null,
      avatarColor: user.avatar_color ?? null,
      createdAt: new Date(user.created_at).toISOString(),
    },
    pan: {
      status: maskedPan ? 'present' : 'missing',
      maskedPan,
      consentVersion: maskedPan ? identity?.pan_consent_version ?? null : null,
      updatedAt: maskedPan && identity?.updated_at
        ? new Date(identity.updated_at as string | Date).toISOString()
        : null,
    },
  };
}

function documentResponse(row: Record<string, unknown>) {
  const parseSummary = publicParseSummary(row.parse_summary);
  return {
    id: row.id,
    fy: row.fy,
    documentType: row.document_type,
    originalFilename: row.original_filename,
    mimeType: row.mime_type,
    byteSize: row.byte_size,
    sha256Fingerprint: row.sha256_fingerprint,
    parseStatus: row.parse_status,
    parseSummary,
    userLabel: row.user_label ?? null,
    notes: row.notes ?? null,
    tags: Array.isArray(row.tags) ? row.tags : [],
    vaultStatus: row.vault_status ?? 'active',
    reviewStatus: row.review_status ?? 'not_reviewed',
    confirmedFields: row.confirmed_fields && typeof row.confirmed_fields === 'object'
      ? row.confirmed_fields
      : {},
    reviewedAt: row.reviewed_at
      ? new Date(row.reviewed_at as string | Date).toISOString()
      : null,
    archivedAt: row.archived_at
      ? new Date(row.archived_at as string | Date).toISOString()
      : null,
    createdAt: row.created_at
      ? new Date(row.created_at as string | Date).toISOString()
      : null,
    updatedAt: row.updated_at
      ? new Date(row.updated_at as string | Date).toISOString()
      : null,
  };
}

function documentSummary(rows: Record<string, unknown>[]) {
  const active = rows.filter((row) => (row.vault_status ?? 'active') !== 'archived');
  const needsReview = active.filter((row) =>
    row.parse_status === 'needs_confirmation'
    || row.review_status === 'needs_review',
  ).length;
  const ready = active.filter((row) =>
    row.parse_status === 'parsed'
    || row.review_status === 'reviewed',
  ).length;
  const unsupported = active.filter((row) => row.parse_status === 'unsupported').length;
  return {
    total: rows.length,
    active: active.length,
    archived: rows.length - active.length,
    needsReview,
    ready,
    unsupported,
  };
}

function moneyGoalResponse(row: Record<string, unknown>) {
  return {
    id: row.id,
    name: row.name,
    category: row.category,
    targetAmount: row.target_amount,
    currentAmount: row.current_amount,
    targetDate: row.target_date instanceof Date
      ? row.target_date.toISOString().slice(0, 10)
      : String(row.target_date).slice(0, 10),
    monthlyEssentials: row.monthly_essentials,
    monthlyFamilySupport: row.monthly_family_support,
    createdAt: row.created_at instanceof Date
      ? row.created_at.toISOString()
      : row.created_at,
    updatedAt: row.updated_at instanceof Date
      ? row.updated_at.toISOString()
      : row.updated_at,
  };
}

async function recordDocumentEvent(input: {
  userId: string;
  documentId?: string | null;
  eventType: string;
  metadata?: Record<string, unknown>;
}) {
  await db.query(
    `insert into document_events (user_id, document_id, event_type, metadata)
     values ($1, $2, $3, $4::jsonb)`,
    [
      input.userId,
      input.documentId ?? null,
      input.eventType,
      JSON.stringify(input.metadata ?? {}),
    ],
  );
}

function safeFilename(filename: string): string {
  return filename.replace(/[^\w.\- ()]/g, '').slice(0, 160) || 'document';
}

function storedParseSummary(summary: Record<string, unknown>) {
  const extractedFields = summary.extractedFields;
  if (!extractedFields || typeof extractedFields !== 'object') {
    return summary;
  }
  const encrypted = encryptDocument(
    Buffer.from(JSON.stringify(extractedFields), 'utf8'),
  );
  const { extractedFields: _removed, ...rest } = summary;
  return {
    ...rest,
    encryptedExtractedFields: encrypted,
    extractedFieldKeys: Object.keys(extractedFields),
  };
}

function publicParseSummary(raw: unknown) {
  const summary = raw && typeof raw === 'object'
    ? { ...(raw as Record<string, unknown>) }
    : {};
  const encrypted = encryptedExtractedFields(summary.encryptedExtractedFields);
  if (encrypted) {
    try {
      summary.extractedFields = JSON.parse(
        decryptDocument(encrypted).toString('utf8'),
      );
    } catch (_) {
      summary.extractedFieldsUnavailable = true;
    }
  }
  delete summary.encryptedExtractedFields;
  return summary;
}

function encryptedExtractedFields(value: unknown): EncryptedSecret | null {
  if (!value || typeof value !== 'object') return null;
  const candidate = value as Record<string, unknown>;
  return typeof candidate.ciphertext === 'string'
    && typeof candidate.iv === 'string'
    && typeof candidate.authTag === 'string'
    ? {
        ciphertext: candidate.ciphertext,
        iv: candidate.iv,
        authTag: candidate.authTag,
      }
    : null;
}

export async function registerRoutes(app: FastifyInstance) {
  await app.register(rateLimit, {
    global: false,
    max: 100,
    timeWindow: '1 minute',
  });
  app.get('/health', async () => ({ ok: true }));
  app.get('/ping', async () => ({
    ok: true,
    commit: process.env.RAILWAY_GIT_COMMIT_SHA
      ?? process.env.GIT_COMMIT_SHA
      ?? buildRevision,
  }));

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
    return issueSession(user, db, sessionMetadata(request));
  });

  app.post('/auth/sign-in', authRateLimit, async (request, reply) => {
    const payload = signInSchema.parse(request.body);
    const email = payload.email.toLowerCase();
    const result = await db.query(
      `select id, email, name, phone_e164, avatar_initials, avatar_color, password_hash, created_at
       from app_users
       where email = $1`,
      [email],
    );
    if (!result.rowCount) {
      return reply.code(401).send({ message: 'Invalid credentials' });
    }
    const user = result.rows[0];
    const valid = typeof user.password_hash === 'string'
      && await verifyPassword(payload.password, user.password_hash);
    if (!valid) {
      return reply.code(401).send({ message: 'Invalid credentials' });
    }

    if (passwordNeedsRehash(user.password_hash)) {
      await db.query(
        'update app_users set password_hash = $2, updated_at = now() where id = $1',
        [user.id, await hashPassword(payload.password)],
      );
    }
    await db.query(
      'update app_users set last_seen_at = now(), updated_at = now() where id = $1',
      [user.id],
    );
    return issueSession(user, db, sessionMetadata(request));
  });

  app.post('/auth/google', authRateLimit, async (request, reply) => {
    if (!env.GOOGLE_OAUTH_CLIENT_ID) {
      return reply.code(503).send({ message: 'Google sign-in is not configured' });
    }
    const payload = googleAuthSchema.parse(request.body);
    let ticket;
    try {
      ticket = await new OAuth2Client().verifyIdToken({
        idToken: payload.idToken,
        audience: env.GOOGLE_OAUTH_CLIENT_ID,
      });
    } catch {
      return reply.code(401).send({ message: 'Invalid Google identity' });
    }
    const claims = ticket.getPayload();
    if (!claims?.sub || !claims.email || claims.email_verified !== true) {
      return reply.code(401).send({ message: 'Invalid Google identity' });
    }

    const email = claims.email.toLowerCase();
    const byGoogleId = await db.query(
      `select id, email, name, phone_e164, avatar_initials, avatar_color, created_at
       from app_users where google_subject = $1`,
      [claims.sub],
    );
    if (byGoogleId.rowCount) {
      return issueSession(byGoogleId.rows[0], db, sessionMetadata(request));
    }

    const byEmail = await db.query(
      `select id, email, name, phone_e164, avatar_initials, avatar_color,
              google_subject, created_at
       from app_users where email = $1`,
      [email],
    );
    if (byEmail.rowCount) {
      const authoritativeGoogleEmail = email.endsWith('@gmail.com') || Boolean(claims.hd);
      if (!authoritativeGoogleEmail || byEmail.rows[0].google_subject) {
        return reply.code(409).send({
          message: 'Use your existing sign-in method for this email',
        });
      }
      const linked = await db.query(
        `update app_users
         set google_subject = $2, auth_provider = 'google', email_verified = true,
             updated_at = now(), last_seen_at = now()
         where id = $1
         returning id, email, name, phone_e164, avatar_initials, avatar_color, created_at`,
        [byEmail.rows[0].id, claims.sub],
      );
      return issueSession(linked.rows[0], db, sessionMetadata(request));
    }

    const inserted = await db.query(
      `insert into app_users (
         email, name, password_hash, google_subject, auth_provider, email_verified
       ) values ($1, $2, null, $3, 'google', true)
       returning id, email, name, phone_e164, avatar_initials, avatar_color, created_at`,
      [email, claims.name?.trim() || email.split('@')[0], claims.sub],
    );
    return issueSession(inserted.rows[0], db, sessionMetadata(request));
  });

  app.post('/auth/refresh', authRateLimit, async (request, reply) => {
    const payload = refreshSchema.parse(request.body);
    const tokenHash = hashRefreshToken(payload.refreshToken);
    const response = await runSerializableTransaction(async (client) => {
      const session = await client.query(
      `select s.id, s.user_id, s.expires_at, u.email, u.name, u.created_at
       from auth_refresh_sessions s
       join app_users u on u.id = s.user_id
       where s.token_hash = $1
         and s.revoked_at is null
         and s.expires_at > now()
       for update`,
        [tokenHash],
      );
      if (!session.rowCount) {
        return null;
      }

      const row = session.rows[0];
      await client.query(
        'update auth_refresh_sessions set revoked_at = now() where id = $1',
        [row.id],
      );

      return issueSession({
        id: row.user_id as string,
        email: row.email as string,
        name: row.name as string,
        phone_e164: row.phone_e164 as string | null,
        avatar_initials: row.avatar_initials as string | null,
        avatar_color: row.avatar_color as string | null,
        created_at: row.created_at as string | Date,
      }, client, sessionMetadata(request));
    });
    if (!response) {
      return reply.code(401).send({ message: 'Invalid refresh token' });
    }
    return response;
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
      'select id, email, name, phone_e164, avatar_initials, avatar_color, created_at from app_users where id = $1',
      [auth.userId],
    );
    if (!result.rowCount) {
      return reply.code(401).send({ message: 'Account no longer exists' });
    }
    const user = result.rows[0];
    return {
      user: {
        id: user.id,
        email: user.email,
        name: user.name,
        phoneNumber: user.phone_e164 ?? null,
        avatarInitials: user.avatar_initials ?? null,
        avatarColor: user.avatar_color ?? null,
        createdAt: new Date(user.created_at as string | Date).toISOString(),
      },
    };
  });

  app.get('/account/profile', readRateLimit, async (request, reply) => {
    const auth = await requireAuth(request, reply);
    if (!auth) return;

    const userResult = await db.query(
      'select id, email, name, phone_e164, avatar_initials, avatar_color, created_at from app_users where id = $1',
      [auth.userId],
    );
    const identityResult = await db.query(
      `select pan_last4, pan_last_char, pan_consent_version, pan_consented_at, updated_at
       from user_private_identity
       where user_id = $1 and pan_ciphertext is not null`,
      [auth.userId],
    );
    return accountResponse(
      userResult.rows[0] as {
        id: string;
        email: string;
        name: string;
        phone_e164?: string | null;
        avatar_initials?: string | null;
        avatar_color?: string | null;
        created_at: string | Date;
      },
      identityResult.rows[0],
    );
  });

  app.patch('/account/profile', dataRateLimit, async (request, reply) => {
    const auth = await requireAuth(request, reply);
    if (!auth) return;

    const payload = accountProfileSchema.parse(request.body);
    const currentResult = await db.query(
      `select id, email, name, phone_e164, avatar_initials, avatar_color, created_at
       from app_users
       where id = $1`,
      [auth.userId],
    );
    if (!currentResult.rowCount) {
      return reply.code(404).send({ message: 'Account not found' });
    }
    const current = currentResult.rows[0] as {
      id: string;
      email: string;
      name: string;
      phone_e164?: string | null;
      avatar_initials?: string | null;
      avatar_color?: string | null;
      created_at: string | Date;
    };
    const nextName = payload.name?.trim() ?? current.name;
    const nextPhone = Object.hasOwn(payload, 'phoneNumber')
      ? payload.phoneNumber
      : current.phone_e164 ?? null;
    const nextAvatarInitials = Object.hasOwn(payload, 'avatarInitials')
      ? payload.avatarInitials?.toUpperCase() ?? null
      : current.avatar_initials ?? null;
    const nextAvatarColor = Object.hasOwn(payload, 'avatarColor')
      ? payload.avatarColor ?? null
      : current.avatar_color ?? null;

    const result = await db.query(
      `update app_users
       set name = $1,
           phone_e164 = $2,
           avatar_initials = $3,
           avatar_color = $4,
           updated_at = now()
       where id = $5
       returning id, email, name, phone_e164, avatar_initials, avatar_color, created_at`,
      [nextName, nextPhone, nextAvatarInitials, nextAvatarColor, auth.userId],
    );
    await db.query(
      'insert into user_events (user_id, name, metadata) values ($1, $2, $3::jsonb)',
      [auth.userId, 'account_profile_updated', '{}'],
    );
    return accountResponse(
      result.rows[0] as {
        id: string;
        email: string;
        name: string;
        phone_e164?: string | null;
        avatar_initials?: string | null;
        avatar_color?: string | null;
        created_at: string | Date;
      },
    );
  });

  app.put('/account/pan', dataRateLimit, async (request, reply) => {
    const auth = await requireAuth(request, reply);
    if (!auth) return;

    const payload = panSchema.parse(request.body);
    const pan = payload.pan.toUpperCase();
    const encrypted = encryptPan(pan);
    const fingerprint = hashPan(pan);
    const last4 = pan.slice(5, 9);
    const lastChar = pan.slice(9);
    const currentPan = await db.query(
      `select pan_fingerprint
       from user_private_identity
       where user_id = $1
         and pan_ciphertext is not null`,
      [auth.userId],
    );
    if (
      currentPan.rowCount
      && currentPan.rows[0]?.pan_fingerprint
      && currentPan.rows[0].pan_fingerprint !== fingerprint
    ) {
      return reply.code(409).send({
        message: 'This account already has a different PAN linked',
      });
    }

    const existingPanOwner = await db.query(
      `select user_id
       from user_private_identity
       where pan_fingerprint = $1
         and user_id <> $2
         and pan_ciphertext is not null`,
      [fingerprint, auth.userId],
    );
    if (existingPanOwner.rowCount) {
      return reply.code(409).send({
        message: 'This PAN is already linked to another ARTH account',
      });
    }

    try {
      await db.query(
        `insert into user_private_identity (
           user_id, pan_ciphertext, pan_iv, pan_auth_tag, pan_last4, pan_last_char,
           pan_fingerprint, pan_consent_version, pan_consented_at, pan_deleted_at,
           created_at, updated_at
         ) values (
           $1, $2, $3, $4, $5, $6, $7, $8, now(), null, now(), now()
         )
         on conflict (user_id) do update set
           pan_ciphertext = excluded.pan_ciphertext,
           pan_iv = excluded.pan_iv,
           pan_auth_tag = excluded.pan_auth_tag,
           pan_last4 = excluded.pan_last4,
           pan_last_char = excluded.pan_last_char,
           pan_fingerprint = excluded.pan_fingerprint,
           pan_consent_version = excluded.pan_consent_version,
           pan_consented_at = now(),
           pan_deleted_at = null,
           updated_at = now()`,
        [
          auth.userId,
          encrypted.ciphertext,
          encrypted.iv,
          encrypted.authTag,
          last4,
          lastChar,
          fingerprint,
          payload.consentVersion,
        ],
      );
    } catch (error) {
      if ((error as { code?: string }).code === '23505') {
        return reply.code(409).send({
          message: 'This PAN is already linked to another ARTH account',
        });
      }
      throw error;
    }
    await db.query(
      'insert into user_events (user_id, name, metadata) values ($1, $2, $3::jsonb)',
      [auth.userId, 'pan_added', '{}'],
    );
    return {
      pan: {
        status: 'present',
        maskedPan: maskPan(last4, lastChar),
        consentVersion: payload.consentVersion,
        updatedAt: new Date().toISOString(),
      },
    };
  });

  app.delete('/account/pan', dataRateLimit, async (request, reply) => {
    const auth = await requireAuth(request, reply);
    if (!auth) return;

    await db.query(
      `update user_private_identity
       set pan_ciphertext = null,
           pan_iv = null,
           pan_auth_tag = null,
           pan_last4 = null,
           pan_last_char = null,
           pan_fingerprint = null,
           pan_deleted_at = now(),
           updated_at = now()
       where user_id = $1`,
      [auth.userId],
    );
    await db.query(
      'insert into user_events (user_id, name, metadata) values ($1, $2, $3::jsonb)',
      [auth.userId, 'pan_deleted', '{}'],
    );
    return reply.code(204).send();
  });

  app.get('/documents', readRateLimit, async (request, reply) => {
    const auth = await requireAuth(request, reply);
    if (!auth) return;

    const result = await db.query(
      `select id, fy, document_type, original_filename, mime_type, byte_size,
              sha256_fingerprint, parse_status, parse_summary, user_label,
              notes, tags, vault_status, review_status, confirmed_fields,
              reviewed_at, archived_at, created_at, updated_at
       from tax_documents
       where user_id = $1 and fy = $2
       order by created_at desc`,
      [auth.userId, env.CURRENT_FY],
    );
    return {
      documents: result.rows.map(documentResponse),
      summary: documentSummary(result.rows),
    };
  });

  app.post('/documents', documentUploadOptions, async (request, reply) => {
    const auth = await requireAuth(request, reply);
    if (!auth) return;

    const part = await request.file();
    if (!part) {
      return reply.code(400).send({ message: 'Document file is required' });
    }

    const fields = part.fields as Record<string, { value?: unknown }>;
    const documentTypeRaw = fields.documentType?.value;
    const documentType = typeof documentTypeRaw === 'string'
      ? documentTypeRaw
      : 'otherTaxDocument';
    if (!allowedDocumentTypes.has(documentType)) {
      return reply.code(400).send({ message: 'Unsupported document type' });
    }
    const ocrTextRaw = fields.ocrText?.value;
    const ocrText = typeof ocrTextRaw === 'string'
      && ocrTextRaw.length >= 40
      && ocrTextRaw.length <= 100_000
      ? ocrTextRaw
      : undefined;
    if (!allowedMimeTypes.has(part.mimetype)) {
      return reply.code(415).send({ message: 'Unsupported document file type' });
    }

    const buffer = await part.toBuffer();
    if (!buffer.length) {
      return reply.code(400).send({ message: 'Document file is empty' });
    }
    const fingerprint = createHash('sha256').update(buffer).digest('hex');
    const encrypted = encryptDocument(buffer);
    const identity = await db.query(
      `select pan_last4, pan_last_char
       from user_private_identity
       where user_id = $1 and pan_ciphertext is not null`,
      [auth.userId],
    );
    const panVaultSuffix: PanVaultSuffix = identity.rowCount
      && typeof identity.rows[0].pan_last4 === 'string'
      && typeof identity.rows[0].pan_last_char === 'string'
      ? {
          last4: identity.rows[0].pan_last4 as string,
          lastChar: identity.rows[0].pan_last_char as string,
        }
      : null;
    const parsed = await parseUploadedDocument({
      documentType,
      mimeType: part.mimetype,
      bytes: buffer,
      ocrText,
      panVaultSuffix,
    });
    const detectedDocumentType = parsed.summary.detectedDocumentType;
    const storedDocumentType = documentType === 'offerLetter'
      && detectedDocumentType === 'payslip'
      ? 'payslip'
      : documentType;
    const inserted = await db.query(
      `insert into tax_documents (
         user_id, fy, document_type, original_filename, mime_type, byte_size,
         sha256_fingerprint, ciphertext, iv, auth_tag, parse_status,
         parse_summary, created_at, updated_at
       ) values (
         $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11,
         $12::jsonb, now(), now()
       )
       on conflict (user_id, fy, document_type, sha256_fingerprint) do update set
         original_filename = excluded.original_filename,
         mime_type = excluded.mime_type,
         byte_size = excluded.byte_size,
         ciphertext = excluded.ciphertext,
         iv = excluded.iv,
         auth_tag = excluded.auth_tag,
         parse_status = case
           when tax_documents.parse_status in ('needs_confirmation', 'parsed')
             and excluded.parse_status not in ('needs_confirmation', 'parsed')
           then tax_documents.parse_status
           else excluded.parse_status
         end,
         parse_summary = case
           when tax_documents.parse_status in ('needs_confirmation', 'parsed')
             and excluded.parse_status not in ('needs_confirmation', 'parsed')
           then tax_documents.parse_summary
           else excluded.parse_summary
         end,
         updated_at = now()
       returning id, fy, document_type, original_filename, mime_type, byte_size,
                 sha256_fingerprint, parse_status, parse_summary, user_label,
                 notes, tags, vault_status, review_status, confirmed_fields,
                 reviewed_at, archived_at, created_at, updated_at`,
      [
        auth.userId,
        env.CURRENT_FY,
        storedDocumentType,
        safeFilename(part.filename),
        part.mimetype,
        buffer.length,
        fingerprint,
        encrypted.ciphertext,
        encrypted.iv,
        encrypted.authTag,
        parsed.status,
        JSON.stringify(storedParseSummary(parsed.summary)),
      ],
    );
    await db.query(
      'insert into user_events (user_id, name, metadata) values ($1, $2, $3::jsonb)',
      [auth.userId, 'document_uploaded', JSON.stringify({
        documentType: storedDocumentType,
        selectedDocumentType: documentType,
      })],
    );
    await recordDocumentEvent({
      userId: auth.userId,
      documentId: inserted.rows[0].id as string,
      eventType: 'upload',
      metadata: {
        documentType: storedDocumentType,
        selectedDocumentType: documentType,
      },
    });
    return { document: documentResponse(inserted.rows[0]) };
  });

  app.post('/documents/:id/confirm', dataRateLimit, async (request, reply) => {
    const auth = await requireAuth(request, reply);
    if (!auth) return;

    const params = z.object({ id: z.string().uuid() }).parse(request.params);
    const payload = documentConfirmationSchema.parse(request.body);
    const current = await db.query(
      `select parse_status, parse_summary, document_type
       from tax_documents
       where id = $1 and user_id = $2`,
      [params.id, auth.userId],
    );
    if (!current.rowCount) {
      return reply.code(404).send({ message: 'Document not found' });
    }

    const row = current.rows[0];
    const storedSummary = typeof row.parse_summary === 'object' && row.parse_summary
      ? row.parse_summary as Record<string, unknown>
      : {};
    const storedParser = typeof storedSummary.parser === 'string'
      ? storedSummary.parser
      : '';
    const isPayslip = row.document_type === 'payslip'
      || storedSummary.detectedDocumentType === 'payslip'
      || storedParser.includes('payslip');
    const manualFields = payload.fields;
    const canConfirmExtracted = row.parse_status === 'needs_confirmation';
    const canConfirmManually = manualFields
      && isPayslip
      && ['metadata_ready', 'needs_confirmation'].includes(row.parse_status);
    if (!canConfirmExtracted && !canConfirmManually) {
      return reply.code(409).send({
        message: 'This document has no pending parsed fields to confirm',
      });
    }

    const summary = publicParseSummary(storedSummary);
    const extractedFields = manualFields ?? (
      summary.extractedFields && typeof summary.extractedFields === 'object'
        ? summary.extractedFields as Record<string, unknown>
        : {}
    );
    const confirmedSummary = {
      ...storedSummary,
      confirmationStatus: 'confirmed',
      confirmedAt: new Date().toISOString(),
      confirmedFieldKeys: Object.keys(extractedFields),
      ...(manualFields ? { manualEntry: true } : {}),
    };
    const payslipFields = Array.isArray(extractedFields.earnings)
      && Array.isArray(extractedFields.deductions)
      && ('netSalary' in extractedFields || 'grossEarnings' in extractedFields);
    const confirmedDocumentType = manualFields
      ? 'payslip'
      : row.document_type === 'offerLetter' && payslipFields
        ? 'payslip'
        : row.document_type;
    const updated = await db.query(
      `update tax_documents
       set parse_status = 'parsed',
           parse_summary = $3::jsonb,
           confirmed_fields = $4::jsonb,
           document_type = $5,
           review_status = 'reviewed',
           reviewed_at = now(),
           updated_at = now()
       where id = $1 and user_id = $2
       returning id, fy, document_type, original_filename, mime_type, byte_size,
                 sha256_fingerprint, parse_status, parse_summary, user_label,
                 notes, tags, vault_status, review_status, confirmed_fields,
                 reviewed_at, archived_at, created_at, updated_at`,
      [
        params.id,
        auth.userId,
        JSON.stringify(confirmedSummary),
        JSON.stringify(extractedFields),
        confirmedDocumentType,
      ],
    );
    await db.query(
      'insert into user_events (user_id, name, metadata) values ($1, $2, $3::jsonb)',
      [auth.userId, 'document_fields_confirmed', '{}'],
    );
    await recordDocumentEvent({
      userId: auth.userId,
      documentId: params.id,
      eventType: 'confirm',
      metadata: {
        documentType: row.document_type,
        fieldKeys: Object.keys(extractedFields),
      },
    });
    return { document: documentResponse(updated.rows[0]) };
  });

  app.patch('/documents/:id', dataRateLimit, async (request, reply) => {
    const auth = await requireAuth(request, reply);
    if (!auth) return;

    const params = z.object({ id: z.string().uuid() }).parse(request.params);
    const payload = documentPatchSchema.parse(request.body);
    const current = await db.query(
      `select user_label, notes, tags, vault_status, review_status, document_type
       from tax_documents
       where id = $1 and user_id = $2`,
      [params.id, auth.userId],
    );
    if (!current.rowCount) {
      return reply.code(404).send({ message: 'Document not found' });
    }
    const row = current.rows[0];
    const vaultStatus = payload.vaultStatus ?? row.vault_status ?? 'active';
    const reviewStatus = payload.reviewStatus ?? row.review_status ?? 'not_reviewed';
    const reviewedAt = reviewStatus === 'reviewed' ? new Date() : null;
    const archivedAt = vaultStatus === 'archived' ? new Date() : null;
    const updated = await db.query(
      `update tax_documents
       set user_label = $3,
           notes = $4,
           tags = $5::jsonb,
           vault_status = $6,
           review_status = $7,
           reviewed_at = $8,
           archived_at = $9,
           updated_at = now()
       where id = $1 and user_id = $2
       returning id, fy, document_type, original_filename, mime_type, byte_size,
                 sha256_fingerprint, parse_status, parse_summary, user_label,
                 notes, tags, vault_status, review_status, confirmed_fields,
                 reviewed_at, archived_at, created_at, updated_at`,
      [
        params.id,
        auth.userId,
        payload.userLabel === undefined ? row.user_label ?? null : payload.userLabel,
        payload.notes === undefined ? row.notes ?? null : payload.notes,
        JSON.stringify(payload.tags ?? row.tags ?? []),
        vaultStatus,
        reviewStatus,
        reviewedAt,
        archivedAt,
      ],
    );
    await recordDocumentEvent({
      userId: auth.userId,
      documentId: params.id,
      eventType: vaultStatus === 'archived' ? 'archive' : 'review',
      metadata: {
        documentType: row.document_type,
        reviewStatus,
        vaultStatus,
      },
    });
    return { document: documentResponse(updated.rows[0]) };
  });

  app.get('/documents/:id/download', readRateLimit, async (request, reply) => {
    const auth = await requireAuth(request, reply);
    if (!auth) return;

    const params = z.object({ id: z.string().uuid() }).parse(request.params);
    const result = await db.query(
      `select original_filename, mime_type, ciphertext, iv, auth_tag
       from tax_documents
       where id = $1 and user_id = $2`,
      [params.id, auth.userId],
    );
    if (!result.rowCount) {
      return reply.code(404).send({ message: 'Document not found' });
    }
    const row = result.rows[0];
    const bytes = decryptDocument({
      ciphertext: row.ciphertext as string,
      iv: row.iv as string,
      authTag: row.auth_tag as string,
    });
    reply.header('content-type', row.mime_type as string);
    reply.header(
      'content-disposition',
      `attachment; filename="${safeFilename(row.original_filename as string)}"`,
    );
    return reply.send(bytes);
  });

  app.delete('/documents/:id', dataRateLimit, async (request, reply) => {
    const auth = await requireAuth(request, reply);
    if (!auth) return;

    const params = z.object({ id: z.string().uuid() }).parse(request.params);
    const result = await db.query(
      'delete from tax_documents where id = $1 and user_id = $2 returning document_type',
      [params.id, auth.userId],
    );
    if (!result.rowCount) {
      return reply.code(404).send({ message: 'Document not found' });
    }
    await db.query(
      'insert into user_events (user_id, name, metadata) values ($1, $2, $3::jsonb)',
      [
        auth.userId,
        'document_deleted',
        JSON.stringify({ documentType: result.rows[0].document_type }),
      ],
    );
    await recordDocumentEvent({
      userId: auth.userId,
      documentId: null,
      eventType: 'delete',
      metadata: {
        documentType: result.rows[0].document_type,
        deletedDocumentId: params.id,
      },
    });
    return reply.code(204).send();
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
        employerName: row.employer_name ?? '',
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
        actualBasicSalary: row.actual_basic_salary ?? null,
        actualHraReceived: row.actual_hra_received ?? null,
        actualProfessionalTax: row.actual_professional_tax ?? null,
        healthInsuranceSelfPremium: row.health_insurance_self_premium ?? null,
        healthInsuranceParentsPremium: row.health_insurance_parents_premium ?? null,
        savingsInterest: row.savings_interest ?? null,
        fdInterest: row.fd_interest ?? null,
        employerNpsContribution: row.employer_nps_contribution ?? null,
        donationDeductionRatePercent: row.donation_deduction_rate_percent ?? null,
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
           user_id, fy, name, email, annual_ctc, employment_type, employer_name, city, is_metro_city,
           pays_rent, monthly_rent, has_hra, invested_80c, has_home_loan, property_type,
           home_loan_interest, has_nps, nps_extra_contribution, has_health_insurance_self,
           has_health_insurance_parents, parents_above_60, has_education_loan,
           education_loan_repayment_year, education_loan_interest, has_donations,
           donation_amount, age_group, actual_basic_salary, actual_hra_received,
           actual_professional_tax, health_insurance_self_premium,
           health_insurance_parents_premium, savings_interest, fd_interest,
           employer_nps_contribution, donation_deduction_rate_percent, updated_at
         ) values (
           $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15,
           $16, $17, $18, $19, $20, $21, $22, $23, $24, $25, $26, $27, $28,
           $29, $30, $31, $32, $33, $34, $35, $36, now()
         )
         on conflict (user_id, fy) do update set
           name = excluded.name,
           email = excluded.email,
           annual_ctc = excluded.annual_ctc,
           employment_type = excluded.employment_type,
           employer_name = excluded.employer_name,
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
           actual_basic_salary = excluded.actual_basic_salary,
           actual_hra_received = excluded.actual_hra_received,
           actual_professional_tax = excluded.actual_professional_tax,
           health_insurance_self_premium = excluded.health_insurance_self_premium,
           health_insurance_parents_premium = excluded.health_insurance_parents_premium,
           savings_interest = excluded.savings_interest,
           fd_interest = excluded.fd_interest,
           employer_nps_contribution = excluded.employer_nps_contribution,
           donation_deduction_rate_percent = excluded.donation_deduction_rate_percent,
           updated_at = now()`,
        [
          auth.userId,
          env.CURRENT_FY,
          profile.name,
          profile.email,
          profile.annualCTC,
          profile.employmentType,
          profile.employerName,
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
          profile.actualBasicSalary ?? null,
          profile.actualHraReceived ?? null,
          profile.actualProfessionalTax ?? null,
          profile.healthInsuranceSelfPremium ?? null,
          profile.healthInsuranceParentsPremium ?? null,
          profile.savingsInterest ?? null,
          profile.fdInterest ?? null,
          profile.employerNpsContribution ?? null,
          profile.donationDeductionRatePercent ?? null,
        ],
      );
      return { ok: true };
    },
  );

  app.get(
    '/tax-results/current',
    readRateLimit,
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
    dataRateLimit,
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

  app.get('/money-goals', readRateLimit, async (request, reply) => {
    const auth = await requireAuth(request, reply);
    if (!auth) return;
    const result = await db.query(
      `select * from money_goals
       where user_id = $1
       order by updated_at desc
       limit 10`,
      [auth.userId],
    );
    return { goals: result.rows.map(moneyGoalResponse) };
  });

  app.post('/spend-map', dataRateLimit, async (request, reply) => {
    const auth = await requireAuth(request, reply);
    if (!auth) return;
    const summary = spendMapSchema.parse(request.body);
    await db.query(
      `insert into spend_maps (
         user_id, window_start, window_end, generated_at, monthly_income,
         monthly_spend, realistic_monthly_savings, spend_by_category,
         monthly_trend, updated_at
       ) values ($1, $2, $3, $4, $5, $6, $7, $8::jsonb, $9::jsonb, now())
       on conflict (user_id) do update set
         window_start = excluded.window_start,
         window_end = excluded.window_end,
         generated_at = excluded.generated_at,
         monthly_income = excluded.monthly_income,
         monthly_spend = excluded.monthly_spend,
         realistic_monthly_savings = excluded.realistic_monthly_savings,
         spend_by_category = excluded.spend_by_category,
         monthly_trend = excluded.monthly_trend,
         updated_at = now()`,
      [
        auth.userId,
        summary.windowStart,
        summary.windowEnd,
        summary.generatedAt,
        summary.monthlyIncome,
        summary.monthlySpend,
        summary.realisticMonthlySavings,
        JSON.stringify(summary.spendByCategory),
        JSON.stringify(summary.monthlyTrend),
      ],
    );

    // Best-effort overspend alert. Fire-and-forget: never block or fail the
    // sync just because a push could not be delivered.
    if (summary.monthlyIncome > 0 && summary.monthlySpend > summary.monthlyIncome) {
      const overBy = summary.monthlySpend - summary.monthlyIncome;
      sendPushToUser(auth.userId, {
        title: 'Spending is ahead of income this month',
        body: `You're about ${overBy.toLocaleString('en-IN')} over your detected income. Tap to review.`,
        data: { type: 'spend_overspend', screen: 'spend-map' },
      }).catch(() => undefined);
    }

    return { ok: true };
  });

  // Register (or refresh) this device's FCM token for push notifications.
  // Upserts on the token itself so re-installs / re-logins on the same device
  // move ownership to the current user instead of erroring.
  app.post('/devices', dataRateLimit, async (request, reply) => {
    const auth = await requireAuth(request, reply);
    if (!auth) return;
    const { fcmToken, platform } = deviceTokenSchema.parse(request.body);
    await db.query(
      `insert into device_tokens (user_id, fcm_token, platform, last_seen_at)
       values ($1, $2, $3, now())
       on conflict (fcm_token) do update set
         user_id = excluded.user_id,
         platform = excluded.platform,
         last_seen_at = now()`,
      [auth.userId, fcmToken, platform],
    );
    return reply.code(201).send({ ok: true });
  });

  // Unregister a device token (e.g. on sign-out) so it stops receiving push.
  app.delete('/devices', dataRateLimit, async (request, reply) => {
    const auth = await requireAuth(request, reply);
    if (!auth) return;
    const { fcmToken } = z.object({ fcmToken: z.string().min(1).max(4096) }).parse(request.body);
    await db.query(
      'delete from device_tokens where user_id = $1 and fcm_token = $2',
      [auth.userId, fcmToken],
    );
    return { ok: true };
  });

  // Hybrid categorization fallback: the client parses & categorizes on-device
  // with rules, then sends only the transactions it could not confidently
  // categorize (redacted text — no account/card numbers) for an AI pass. When
  // Gemini is unconfigured or errors, returns an empty result set so the client
  // simply keeps its on-device categories.
  app.post('/spend-map/categorize', dataRateLimit, async (request, reply) => {
    const auth = await requireAuth(request, reply);
    if (!auth) return;
    const { items } = categorizeRequestSchema.parse(request.body);
    const results = await categorizeTransactions(items);
    return { results: results ?? [] };
  });

  app.post('/money-goals', dataRateLimit, async (request, reply) => {
    const auth = await requireAuth(request, reply);
    if (!auth) return;
    const goal = moneyGoalSchema.parse(request.body);
    const result = await db.query(
      `insert into money_goals (
         user_id, name, category, target_amount, current_amount, target_date,
         monthly_essentials, monthly_family_support
       ) values ($1, $2, $3, $4, $5, $6, $7, $8)
       returning *`,
      [
        auth.userId,
        goal.name,
        goal.category,
        goal.targetAmount,
        goal.currentAmount,
        goal.targetDate,
        goal.monthlyEssentials,
        goal.monthlyFamilySupport,
      ],
    );
    return reply.code(201).send({ goal: moneyGoalResponse(result.rows[0]) });
  });

  app.put('/money-goals/:id', dataRateLimit, async (request, reply) => {
    const auth = await requireAuth(request, reply);
    if (!auth) return;
    const { id } = z.object({ id: z.string().uuid() }).parse(request.params);
    const goal = moneyGoalSchema.parse(request.body);
    const result = await db.query(
      `update money_goals set
         name = $3,
         category = $4,
         target_amount = $5,
         current_amount = $6,
         target_date = $7,
         monthly_essentials = $8,
         monthly_family_support = $9,
         updated_at = now()
       where id = $1 and user_id = $2
       returning *`,
      [
        id,
        auth.userId,
        goal.name,
        goal.category,
        goal.targetAmount,
        goal.currentAmount,
        goal.targetDate,
        goal.monthlyEssentials,
        goal.monthlyFamilySupport,
      ],
    );
    if (!result.rowCount) {
      return reply.code(404).send({
        code: 'goal_not_found',
        message: 'Goal not found',
        retryable: false,
      });
    }
    return { goal: moneyGoalResponse(result.rows[0]) };
  });

  app.delete('/money-goals/:id', dataRateLimit, async (request, reply) => {
    const auth = await requireAuth(request, reply);
    if (!auth) return;
    const { id } = z.object({ id: z.string().uuid() }).parse(request.params);
    await db.query(
      'delete from money_goals where id = $1 and user_id = $2',
      [id, auth.userId],
    );
    return reply.code(204).send();
  });

  app.get('/employers', readRateLimit, async (request) => {
    const { q } = employerSearchSchema.parse(request.query);
    const result = await db.query(
      `select display_name from employer_catalog
       where ($1 = '' or display_name ilike '%' || $1 || '%')
         and (approved = true or usage_count >= 2)
       order by
         case when lower(display_name) = lower($1) then 0 else 1 end,
         usage_count desc,
         display_name asc
       limit 50`,
      [q],
    );
    return { employers: result.rows.map((row) => row.display_name) };
  });

  app.post('/employers', dataRateLimit, async (request, reply) => {
    const auth = await requireAuth(request, reply);
    if (!auth) return;
    const { name } = employerSubmissionSchema.parse(request.body);
    const normalized = name.toLocaleLowerCase('en-IN').replace(/\s+/g, ' ').trim();
    const result = await db.query(
      `insert into employer_catalog (
         normalized_name, display_name, source, submitted_by
       ) values ($1, $2, 'user', $3)
       on conflict (normalized_name) do update set
         usage_count = employer_catalog.usage_count + 1,
         updated_at = now()
       returning display_name`,
      [normalized, name, auth.userId],
    );
    return reply.code(201).send({ employer: result.rows[0].display_name });
  });

  app.get(
    '/done-gaps/current',
    readRateLimit,
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
    dataRateLimit,
    async (request, reply) => {
      const auth = await requireAuth(request, reply);
      if (!auth) return;

      const payload = doneGapsSchema.parse(request.body);
      await runSerializableTransaction(async (client) => {
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
      });
      return { ok: true };
    },
  );

  app.delete(
    '/profile',
    dataRateLimit,
    async (request, reply) => {
      const auth = await requireAuth(request, reply);
      if (!auth) return;
      await runSerializableTransaction(async (client) => {
        await client.query('delete from done_gaps where user_id = $1', [auth.userId]);
        await client.query('delete from tax_profiles where user_id = $1', [auth.userId]);
        await client.query('delete from tax_results where user_id = $1', [auth.userId]);
        await client.query('delete from money_goals where user_id = $1', [auth.userId]);
        await client.query('delete from spend_maps where user_id = $1', [auth.userId]);
        await client.query('delete from tax_documents where user_id = $1', [auth.userId]);
        await client.query(
          `update user_private_identity
           set pan_ciphertext = null,
               pan_iv = null,
               pan_auth_tag = null,
               pan_last4 = null,
               pan_last_char = null,
               pan_fingerprint = null,
               pan_deleted_at = now(),
               updated_at = now()
           where user_id = $1`,
          [auth.userId],
        );
      });
      return reply.code(204).send();
    },
  );

  app.delete(
    '/account',
    dataRateLimit,
    async (request, reply) => {
      const auth = await requireAuth(request, reply);
      if (!auth) return;
      deleteAccountSchema.parse(request.body);

      const anonymousSubjectHash = blindIndex('deleted-user', auth.userId).toString('hex');
      const deletionId = randomUUID();
      const backupExpiresAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1_000);
      const deleted = await runSerializableTransaction(async (client) => {
        await client.query(
          'update auth_refresh_sessions set revoked_at = now() where user_id = $1 and revoked_at is null',
          [auth.userId],
        );
        const result = await client.query(
          'delete from app_users where id = $1 returning id',
          [auth.userId],
        );
        if (!result.rowCount) return false;
        await client.query(
          `insert into security_tombstones (
             deletion_id, anonymous_subject_hash, deleted_at, backup_expires_at
           ) values ($1, $2, now(), $3)`,
          [deletionId, anonymousSubjectHash, backupExpiresAt],
        );
        return true;
      });
      if (!deleted) {
        return reply.code(404).send({ message: 'Account not found' });
      }
      return reply.code(204).send();
    },
  );

  app.post(
    '/events',
    dataRateLimit,
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
