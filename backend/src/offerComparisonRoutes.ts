import type { FastifyInstance } from 'fastify';
import { z } from 'zod';

import { withAuthUser } from './auth.js';
import { env } from './config.js';
import { db } from './db.js';
import { ledgerSpendGuard } from './documentSpendGuard.js';
import { parseStoredOfferLetterInterpretation } from './geminiInterpreter.js';
import {
  adviceFingerprint,
  adviseOnOffers,
  type AnsweredQuestion,
  type OfferAdvice,
} from './offerAdvisor.js';
import {
  compareOffers,
  type OfferComparison,
  type OfferInput,
} from './offerComparisonEngine.js';
import {
  MAX_QUESTIONS,
  selectQuestions,
  type SelectedQuestion,
} from './offerQuestionSelector.js';
import { decryptDocument, encryptDocument, type EncryptedSecret } from './security.js';

/// Routes for comparing several stored offer letters.
///
/// Lives in its own module rather than in routes.ts because this is one product
/// area, and it should review and hand off without dragging the rest of the API
/// with it.

const dataRateLimit = {
  config: {
    rateLimit: {
      max: 60,
      timeWindow: '1 minute',
    },
  },
};

/// Comparing more than a handful of offers is not a real situation, and the cap
/// also bounds how much a single request can be made to decrypt and normalize.
const MAX_OFFERS_PER_COMPARISON = 10;

const createSchema = z.object({
  documentIds: z.array(z.string().uuid()).min(1).max(MAX_OFFERS_PER_COMPARISON),
}).strict();

const answersSchema = z.object({
  answers: z.array(z.object({
    id: z.string().min(1).max(64),
    answer: z.string().trim().min(1).max(600),
  })).min(1).max(MAX_QUESTIONS),
}).strict();

const paramsSchema = z.object({ id: z.string().uuid() });

/// What a session holds, inside the encrypted envelope.
type SessionState = {
  comparison: OfferComparison;
  questions: SelectedQuestion[];
  answers: AnsweredQuestion[];
  advice: OfferAdvice | null;
};

function encryptState(state: SessionState): EncryptedSecret {
  return encryptDocument(Buffer.from(JSON.stringify(state), 'utf8'));
}

function decryptState(value: unknown): SessionState | null {
  if (!value || typeof value !== 'object') return null;
  const candidate = value as Record<string, unknown>;
  if (
    typeof candidate.ciphertext !== 'string'
    || typeof candidate.iv !== 'string'
    || typeof candidate.authTag !== 'string'
  ) {
    return null;
  }
  try {
    return JSON.parse(decryptDocument({
      ciphertext: candidate.ciphertext,
      iv: candidate.iv,
      authTag: candidate.authTag,
    }).toString('utf8')) as SessionState;
  } catch {
    return null;
  }
}

/// The extracted interpretation for one stored offer letter.
///
/// Extracted fields are encrypted inside the parse summary, so reading an offer
/// back means decrypting it here. A document whose fields cannot be read is left
/// out of the comparison rather than compared as blanks.
function readInterpretation(row: {
  parse_summary: unknown;
}): ReturnType<typeof parseStoredOfferLetterInterpretation> {
  const summary = row.parse_summary;
  if (!summary || typeof summary !== 'object') return null;
  const encrypted = (summary as Record<string, unknown>).encryptedExtractedFields;
  if (!encrypted || typeof encrypted !== 'object') return null;
  const fields = encrypted as Record<string, unknown>;
  if (
    typeof fields.ciphertext !== 'string'
    || typeof fields.iv !== 'string'
    || typeof fields.authTag !== 'string'
  ) {
    return null;
  }
  try {
    return parseStoredOfferLetterInterpretation(JSON.parse(
      decryptDocument({
        ciphertext: fields.ciphertext,
        iv: fields.iv,
        authTag: fields.authTag,
      }).toString('utf8'),
    ));
  } catch {
    return null;
  }
}

function sessionResponse(
  row: { id: string; status: string; created_at: string | Date; updated_at: string | Date },
  state: SessionState,
) {
  return {
    comparison: {
      id: row.id,
      status: row.status,
      createdAt: new Date(row.created_at).toISOString(),
      updatedAt: new Date(row.updated_at).toISOString(),
      offers: state.comparison.offers,
      rankedDocumentIds: state.comparison.rankedDocumentIds,
      decidingAxis: state.comparison.decidingAxis,
      guaranteedPayGap: state.comparison.guaranteedPayGap,
      largestCtcIsNotBestGuaranteed: state.comparison.largestCtcIsNotBestGuaranteed,
      currencies: state.comparison.currencies,
      // The selection rationale stays server-side. It exists to make the choice
      // reviewable and to brief the advice call, not to be read by the candidate.
      questions: state.questions.map(({ because: _because, ...question }) => question),
      answers: state.answers.map((answer) => ({
        id: answer.id,
        answer: answer.answer,
      })),
      advice: state.advice,
    },
  };
}

export async function registerOfferComparisonRoutes(app: FastifyInstance) {
  app.post('/offers/compare', dataRateLimit, async (request, reply) => {
    return withAuthUser(request, reply, async (userId) => {

    const payload = createSchema.parse(request.body);
    const unique = [...new Set(payload.documentIds)];
    const documents = await db.query(
      `select id, document_type, parse_status, parse_summary
       from tax_documents
       where user_id = $1 and id = any($2::uuid[])`,
      [userId, unique],
    );
    if (documents.rowCount !== unique.length) {
      return reply.code(404).send({ message: 'One or more documents were not found' });
    }

    const inputs: OfferInput[] = [];
    const unreadable: string[] = [];
    // Ordered by the request, so "Offer A" is whatever the candidate listed first
    // and stays that way on every screen.
    for (const [position, documentId] of unique.entries()) {
      const row = documents.rows.find((candidate) => candidate.id === documentId);
      if (!row) continue;
      if (row.document_type !== 'offerLetter') {
        return reply.code(409).send({
          message: 'Only offer letters can be compared',
        });
      }
      const interpretation = readInterpretation(row);
      if (!interpretation) {
        unreadable.push(documentId);
        continue;
      }
      inputs.push({ documentId, position, interpretation });
    }

    if (!inputs.length) {
      return reply.code(409).send({
        message: 'None of these offer letters have been interpreted yet',
        unreadableDocumentIds: unreadable,
      });
    }

    const comparison = compareOffers(inputs);
    const state: SessionState = {
      comparison,
      questions: selectQuestions(comparison),
      answers: [],
      advice: null,
    };
    const inserted = await db.query(
      `insert into offer_comparisons (user_id, fy, status, state_encrypted)
       values ($1, $2, 'questions_pending', $3::jsonb)
       returning id, status, created_at, updated_at`,
      [userId, env.CURRENT_FY, JSON.stringify(encryptState(state))],
    );
    const comparisonId = inserted.rows[0].id as string;
    for (const offer of inputs) {
      await db.query(
        `insert into offer_comparison_offers (comparison_id, document_id, user_id, position)
         values ($1, $2, $3, $4)`,
        [comparisonId, offer.documentId, userId, offer.position],
      );
    }
    await db.query(
      'insert into user_events (user_id, name, metadata) values ($1, $2, $3::jsonb)',
      [userId, 'offer_comparison_started', JSON.stringify({
        offerCount: inputs.length,
        decidingAxis: comparison.decidingAxis,
        questionCount: state.questions.length,
      })],
    );

    return reply.code(201).send({
      ...sessionResponse(inserted.rows[0], state),
      unreadableDocumentIds: unreadable,
    });
    });
  });

  app.post('/offers/compare/:id/answers', dataRateLimit, async (request, reply) => {
    return withAuthUser(request, reply, async (userId) => {

    const params = paramsSchema.parse(request.params);
    const payload = answersSchema.parse(request.body);
    const existing = await db.query(
      `select id, status, state_encrypted, advice_fingerprint, created_at, updated_at
       from offer_comparisons
       where id = $1 and user_id = $2`,
      [params.id, userId],
    );
    if (!existing.rowCount) {
      return reply.code(404).send({ message: 'Comparison not found' });
    }
    const row = existing.rows[0];
    const state = decryptState(row.state_encrypted);
    if (!state) {
      return reply.code(409).send({
        message: 'This comparison can no longer be read. Start a new one.',
      });
    }

    // Answers are matched to the questions this session actually asked. An answer
    // to a question that was never put would end up briefing the advice call with
    // a premise nothing in the comparison supports.
    const asked = new Map(state.questions.map((question) => [question.id, question]));
    const answers: AnsweredQuestion[] = [];
    for (const submitted of payload.answers) {
      const question = asked.get(submitted.id as SelectedQuestion['id']);
      if (!question) {
        return reply.code(400).send({
          message: `This comparison did not ask "${submitted.id}"`,
        });
      }
      answers.push({
        id: question.id,
        prompt: question.prompt,
        because: question.because,
        answer: submitted.answer,
      });
    }

    const fingerprint = adviceFingerprint(state.comparison, answers);
    if (row.advice_fingerprint === fingerprint && state.advice) {
      // Same offers, same answers. Paying again would buy the same paragraph.
      return sessionResponse({ ...row, status: 'advised' }, {
        ...state,
        answers,
      });
    }

    const advice = await adviseOnOffers({
      comparison: state.comparison,
      answers,
      spendGuard: ledgerSpendGuard(userId),
    });
    const nextState: SessionState = { ...state, answers, advice };
    const status = advice ? 'advised' : 'answered';
    const updated = await db.query(
      `update offer_comparisons
       set status = $3,
           state_encrypted = $4::jsonb,
           advice_fingerprint = $5,
           updated_at = now()
       where id = $1 and user_id = $2
       returning id, status, created_at, updated_at`,
      [
        params.id,
        userId,
        status,
        JSON.stringify(encryptState(nextState)),
        advice ? fingerprint : null,
      ],
    );
    await db.query(
      'insert into user_events (user_id, name, metadata) values ($1, $2, $3::jsonb)',
      [userId, 'offer_comparison_answered', JSON.stringify({
        answerCount: answers.length,
        adviceAvailable: advice !== null,
      })],
    );

    if (!advice) {
      // The answers are saved either way, so the candidate never re-enters them
      // just because the model was unavailable or the budget was spent.
      return reply.code(503).send({
        message: 'Answers saved. Advice is unavailable right now, so try again later.',
        ...sessionResponse(updated.rows[0], nextState).comparison,
      });
    }
    return sessionResponse(updated.rows[0], nextState);
    });
  });

  app.get('/offers/compare/:id', dataRateLimit, async (request, reply) => {
    return withAuthUser(request, reply, async (userId) => {

    const params = paramsSchema.parse(request.params);
    const existing = await db.query(
      `select id, status, state_encrypted, created_at, updated_at
       from offer_comparisons
       where id = $1 and user_id = $2`,
      [params.id, userId],
    );
    if (!existing.rowCount) {
      return reply.code(404).send({ message: 'Comparison not found' });
    }
    const state = decryptState(existing.rows[0].state_encrypted);
    if (!state) {
      return reply.code(409).send({
        message: 'This comparison can no longer be read. Start a new one.',
      });
    }
    return sessionResponse(existing.rows[0], state);
    });
  });
}
