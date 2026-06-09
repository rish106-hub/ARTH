import 'dotenv/config';
import { z } from 'zod';

const schema = z.object({
  NEON_API_KEY: z.string().min(1),
  NEON_PROJECT_NAME: z.string().default('arth-prod'),
  NEON_REGION_ID: z.string().default('aws-ap-southeast-1'),
  NEON_PG_VERSION: z.number().default(16),
});

const env = schema.parse({
  NEON_API_KEY: process.env.NEON_API_KEY,
  NEON_PROJECT_NAME: process.env.NEON_PROJECT_NAME,
  NEON_REGION_ID: process.env.NEON_REGION_ID,
  NEON_PG_VERSION: process.env.NEON_PG_VERSION
    ? Number(process.env.NEON_PG_VERSION)
    : 16,
});

async function main() {
  const response = await fetch('https://console.neon.tech/api/v2/projects', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      authorization: `Bearer ${env.NEON_API_KEY}`,
    },
    body: JSON.stringify({
      project: {
        name: env.NEON_PROJECT_NAME,
        region_id: env.NEON_REGION_ID,
        pg_version: env.NEON_PG_VERSION,
      },
    }),
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`Neon project creation failed: ${response.status} ${text}`);
  }

  const data = (await response.json()) as {
    connection_uris?: Array<{ connection_uri: string }>;
    project?: { id?: string; name?: string };
  };

  const connectionUri = data.connection_uris?.[0]?.connection_uri;

  console.log(
    JSON.stringify(
      {
        projectId: data.project?.id ?? null,
        projectName: data.project?.name ?? env.NEON_PROJECT_NAME,
        connectionUri,
      },
      null,
      2,
    ),
  );
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
